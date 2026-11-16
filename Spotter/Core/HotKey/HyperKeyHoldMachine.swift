import Foundation

/// `NX_DEVICE…KEYMASK` bits (IOLLEvent.h): the device-level flags a real modifier press carries alongside its generic mask. A key's bit stays set for as long as that physical key is down, which is what lets `HyperKeyHoldMachine` read press-versus-release out of the event itself.
enum HyperKeyDeviceFlag {
    static let leftControl: UInt64 = 0x0000_0001
    static let leftShift: UInt64 = 0x0000_0002
    static let rightShift: UInt64 = 0x0000_0004
    static let leftCommand: UInt64 = 0x0000_0008
    static let rightCommand: UInt64 = 0x0000_0010
    static let leftOption: UInt64 = 0x0000_0020
    static let rightOption: UInt64 = 0x0000_0040
    static let rightControl: UInt64 = 0x0000_2000
}

/// The generic `CGEventFlags` masks the chord is built from. `HyperKeyTap` supplies the real values so this file needs no CoreGraphics; what matters here — and what the harness pins — is how they are combined, not their numbers.
struct HyperKeyModifierMasks: Equatable, Sendable {
    let control: UInt64
    let option: UInt64
    let shift: UInt64
    let command: UInt64
    let alphaShift: UInt64
}

/// How the synthetic ⌃⌥(⇧)⌘ chord is composed, and what of the Hyper key's own state is scrubbed from the events it rewrites.
enum HyperKeyChord {
    /// The flags OR'd into every event while Hyper is held: the generic masks plus the *left* device bits, since some consumers distinguish sides and generic-only flags don't always read as fully pressed.
    static func heldFlags(masks: HyperKeyModifierMasks, includesShift: Bool) -> UInt64 {
        var raw =
            masks.control | masks.option | masks.command
            | HyperKeyDeviceFlag.leftControl | HyperKeyDeviceFlag.leftOption
            | HyperKeyDeviceFlag.leftCommand
        if includesShift { raw |= masks.shift | HyperKeyDeviceFlag.leftShift }
        return raw
    }

    /// The Hyper key's own flag residue scrubbed from rewritten events: Caps Lock's alpha-shift bit, or — only for a key whose modifier sits outside the chord — its generic mask plus both of its device bits.
    static func strippedFlags(
        ownMask: UInt64?, isCapsLock: Bool, masks: HyperKeyModifierMasks, includesShift: Bool
    ) -> UInt64 {
        if isCapsLock { return masks.alphaShift }
        guard let ownMask,
            heldFlags(masks: masks, includesShift: includesShift) & ownMask == 0
        else { return 0 }
        return ownMask | deviceBits(of: ownMask, masks)
    }

    private static func deviceBits(of mask: UInt64, _ masks: HyperKeyModifierMasks) -> UInt64 {
        switch mask {
        case masks.control: return HyperKeyDeviceFlag.leftControl | HyperKeyDeviceFlag.rightControl
        case masks.shift: return HyperKeyDeviceFlag.leftShift | HyperKeyDeviceFlag.rightShift
        case masks.option: return HyperKeyDeviceFlag.leftOption | HyperKeyDeviceFlag.rightOption
        case masks.command: return HyperKeyDeviceFlag.leftCommand | HyperKeyDeviceFlag.rightCommand
        default: return 0
        }
    }
}

/// The Hyper key's hold state: whether the chord is currently held, and whether a release ends a
/// Quick Press. Pure and clock-injected (`now` is a caller-supplied monotonic timestamp) so
/// `Tools/hotkey-test.swift` can drive it without an event tap.
///
/// Direction comes from each event's own device bit rather than from toggling a bool. Toggling has
/// no ground truth, so one missed or duplicated `flagsChanged` — which a `.tapDisabledByTimeout`
/// mid-hold guarantees — inverted the machine for the rest of the session: every later press read
/// as a release and the Hyper key stopped working entirely.
struct HyperKeyHoldMachine {
    /// Longest a lone press may last and still fire Quick Press — matches `DoubleTapDetector.maxHold`, so a "tap" means the same thing in both features.
    static let quickPressWindow: TimeInterval = 0.25

    /// What the caller should do with the Hyper key's own event, plus the two facts worth reporting.
    struct Outcome: Equatable, Sendable {
        /// True while the chord is held: the event is rewritten as ⌃⌥(⇧)⌘. False restores the key's own flags.
        var isHeld: Bool
        /// A lone press short enough to count as a Quick Press just ended.
        var firesQuickPress = false
        /// The event's own direction contradicted the tracked state, so the machine re-derived it — a lifecycle anomaly worth one log line, never a per-keystroke one.
        var corrected = false
    }

    /// The device bit of the configured physical key, or `nil` for one that has none: Caps Lock, whose remapped F18 arrives as self-describing keyDown/keyUp, and `.none`.
    let deviceBit: UInt64?

    private(set) var isHeld = false
    /// Set when the system disabled the tap: the hold stands (the key is most likely still down), but a release may have landed in the blackout, so the next event re-derives it.
    private(set) var needsResync = false
    /// Whether this keyboard has ever been seen to report the configured key's device bit. Until it has, a clear bit is no evidence of a release — it could just as well mean the bit is never reported — so the machine keeps the old toggle semantics rather than reading every press as a release and disabling Hyper outright.
    private(set) var hasSeenDeviceBit = false

    private var heldSince: TimeInterval?
    private var otherKeyPressed = false

    init(deviceBit: UInt64?) {
        self.deviceBit = deviceBit
    }

    /// Whether the Hyper key is physically down according to an event's own flags; `nil` when the configured key has no device bit to read.
    func isKeyDown(flagsRaw: UInt64) -> Bool? {
        guard let deviceBit, deviceBit != 0 else { return nil }
        return flagsRaw & deviceBit != 0
    }

    /// A `flagsChanged` carrying the Hyper key's own keycode. A key with no bit to read, or one this keyboard has not been seen to report, falls back to toggling — which is all the machine ever had before.
    mutating func modifierTransition(flagsRaw: UInt64, at now: TimeInterval) -> Outcome {
        needsResync = false
        guard let down = isKeyDown(flagsRaw: flagsRaw) else { return toggle(at: now) }
        if down { hasSeenDeviceBit = true }
        guard down || hasSeenDeviceBit else { return toggle(at: now) }
        let contradicts = down == isHeld
        return down
            ? press(at: now, corrected: contradicts) : release(at: now, corrected: contradicts)
    }

    /// Caps Lock's remapped F18, which arrives as keyDown/keyUp and already says which it is.
    mutating func keyTransition(isDown: Bool, at now: TimeInterval) -> Outcome {
        needsResync = false
        let contradicts = isDown == isHeld
        return isDown
            ? press(at: now, corrected: contradicts) : release(at: now, corrected: contradicts)
    }

    /// The first event after a tap interruption: re-derive the hold from that event's own flags, since a release delivered while the tap was off was never seen. Returns an outcome only when the state actually changed, so the caller logs once rather than per keystroke.
    mutating func resync(flagsRaw: UInt64, at now: TimeInterval) -> Outcome? {
        guard needsResync else { return nil }
        needsResync = false
        guard let down = isKeyDown(flagsRaw: flagsRaw), down != isHeld else { return nil }
        if down { hasSeenDeviceBit = true }
        guard down || hasSeenDeviceBit else { return nil }
        if down {
            isHeld = true
            heldSince = now
            // Nothing is known about what happened during the blackout, so this hold may never fire a Quick Press.
            otherKeyPressed = true
        } else {
            isHeld = false
            heldSince = nil
            otherKeyPressed = false
        }
        return Outcome(isHeld: isHeld, corrected: true)
    }

    /// Another key or modifier went down while Hyper is held: this press is a combo, not a tap.
    mutating func noteOtherKeyPressed() {
        otherKeyPressed = true
    }

    /// The system disabled the tap. The hold is not dropped — dropping it mid-press is what stranded the old machine — only marked unverified until the next event re-derives it.
    mutating func tapInterrupted() {
        needsResync = true
    }

    /// Another session owns the keyboard, or the configured key changed: there is no hold left to recover.
    mutating func cancel() {
        isHeld = false
        heldSince = nil
        otherKeyPressed = false
        needsResync = false
    }

    /// The pre-ground-truth behaviour, kept only for the cases where the event says nothing: alternate on every transition.
    private mutating func toggle(at now: TimeInterval) -> Outcome {
        isHeld ? release(at: now, corrected: false) : press(at: now, corrected: false)
    }

    private mutating func press(at now: TimeInterval, corrected: Bool) -> Outcome {
        // Idempotent: a duplicated press must not restart the Quick Press clock or forget a combo already in flight.
        if !isHeld {
            isHeld = true
            heldSince = now
            otherKeyPressed = false
        }
        return Outcome(isHeld: true, corrected: corrected)
    }

    private mutating func release(at now: TimeInterval, corrected: Bool) -> Outcome {
        guard isHeld else { return Outcome(isHeld: false, corrected: corrected) }
        let isQuick =
            !otherKeyPressed && heldSince.map { now - $0 < Self.quickPressWindow } ?? false
        isHeld = false
        heldSince = nil
        otherKeyPressed = false
        return Outcome(isHeld: false, firesQuickPress: isQuick, corrected: corrected)
    }
}
