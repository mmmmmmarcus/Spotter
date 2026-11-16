import CoreGraphics
import Foundation

/// Drives `DoubleTapDetector` on a virtual clock, so every window boundary is exact rather than timed.
@MainActor
private struct Keyboard {
    var detector = DoubleTapDetector()
    private(set) var fired: [DoubleTapModifier] = []

    mutating func press(
        _ modifiers: Set<DoubleTapModifier>, other: Bool = false, at time: TimeInterval
    ) {
        if let modifier = detector.handle(
            .modifiers(modifiers, hasOtherModifiers: other), at: time) {
            fired.append(modifier)
        }
    }

    mutating func release(other: Bool = false, at time: TimeInterval) {
        press([], other: other, at: time)
    }

    mutating func otherInput(at time: TimeInterval) {
        if let modifier = detector.handle(.otherInput, at: time) { fired.append(modifier) }
    }

    mutating func tap(
        _ modifier: DoubleTapModifier, at time: TimeInterval, hold: TimeInterval = 0.05
    ) {
        press([modifier], at: time)
        release(at: time + hold)
    }
}

@main
@MainActor
struct DoubleTapDetectorTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ fired: [DoubleTapModifier], _ expected: [DoubleTapModifier], _ m: String) {
        expect(fired == expected, "\(m) — fired \(fired.map(\.rawValue)), want \(expected.map(\.rawValue))")
    }

    static func main() {
        modifierGlyphs()
        firing()
        timing()
        chords()
        interruptions()
        repeats()
        resetting()
        hyperKeyMapping()
        hyperKeyPressRelease()
        hyperKeyInterruption()
        hyperKeyDuplicates()
        hyperKeyOrphanRelease()
        hyperKeyQuickPress()
        hyperKeyFallback()
        hyperKeyChord()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Model

    static func modifierGlyphs() {
        expect(DoubleTapModifier.allCases.count == 4, "exactly four modifiers are eligible")
        expect(
            Set(DoubleTapModifier.allCases.map(\.glyph)) == ["⌃", "⌥", "⇧", "⌘"],
            "the glyphs are the four macOS modifier symbols")
        expect(
            DoubleTapModifier.allCases.allSatisfy { $0.keycaps == [$0.glyph, $0.glyph] },
            "a double-tap renders as its glyph twice")
        expect(
            DoubleTapModifier.allCases.map(\.rawValue)
                == ["control", "option", "shift", "command"],
            "raw values are the persisted spelling and stay in canonical ⌃⌥⇧⌘ order")
    }

    // MARK: - Firing

    static func firing() {
        for modifier in DoubleTapModifier.allCases {
            var keyboard = Keyboard()
            keyboard.tap(modifier, at: 0)
            expect(keyboard.fired, [], "\(modifier.rawValue): one tap alone doesn't fire")
            keyboard.tap(modifier, at: 0.15)
            expect(keyboard.fired, [modifier], "\(modifier.rawValue): a clean double-tap fires")
        }

        // Firing is on the second release, not the second press.
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.press([.command], at: 0.15)
        expect(keyboard.fired, [], "the second press alone doesn't fire")
        keyboard.release(at: 0.20)
        expect(keyboard.fired, [.command], "the second release fires")
    }

    // MARK: - Timing

    static func timing() {
        var slowFirst = Keyboard()
        slowFirst.tap(.command, at: 0, hold: DoubleTapDetector.maxHold + 0.01)
        slowFirst.tap(.command, at: 0.5)
        expect(slowFirst.fired, [], "a held first press isn't a tap")

        var slowSecond = Keyboard()
        slowSecond.tap(.command, at: 0)
        slowSecond.tap(.command, at: 0.10, hold: DoubleTapDetector.maxHold + 0.01)
        expect(slowSecond.fired, [], "a held second press isn't a tap")

        var lateGap = Keyboard()
        lateGap.tap(.command, at: 0, hold: 0.05)
        lateGap.tap(.command, at: 0.05 + DoubleTapDetector.maxGap + 0.01)
        expect(lateGap.fired, [], "a second tap after the gap doesn't fire")

        // Just inside both windows: the slowest double-tap that still counts.
        let epsilon = 0.001
        var atLimit = Keyboard()
        atLimit.tap(.command, at: 0, hold: DoubleTapDetector.maxHold - epsilon)
        atLimit.tap(
            .command, at: DoubleTapDetector.maxHold + DoubleTapDetector.maxGap - 2 * epsilon,
            hold: DoubleTapDetector.maxHold - epsilon)
        expect(atLimit.fired, [.command], "the slowest qualifying double-tap still fires")

        // A late second tap becomes the new first tap rather than being discarded.
        var rolling = Keyboard()
        rolling.tap(.command, at: 0)
        rolling.tap(.command, at: 1.0)
        expect(rolling.fired, [], "the late tap doesn't fire")
        rolling.tap(.command, at: 1.15)
        expect(rolling.fired, [.command], "but it seeds the next pair")
    }

    // MARK: - Chords

    static func chords() {
        var joined = Keyboard()
        joined.tap(.command, at: 0)
        joined.press([.command], at: 0.15)
        joined.press([.command, .shift], at: 0.17)
        joined.press([.command], at: 0.19)
        joined.release(at: 0.21)
        expect(joined.fired, [], "a chord unwinding back to one modifier isn't a tap")

        var chorded = Keyboard()
        chorded.press([.command, .shift], at: 0)
        chorded.release(at: 0.05)
        chorded.press([.command, .shift], at: 0.10)
        chorded.release(at: 0.15)
        expect(chorded.fired, [], "double-tapping a two-modifier chord doesn't fire")

        var mixed = Keyboard()
        mixed.tap(.command, at: 0)
        mixed.tap(.shift, at: 0.15)
        expect(mixed.fired, [], "two different modifiers aren't a double-tap")
        mixed.tap(.shift, at: 0.30)
        expect(mixed.fired, [.shift], "but the second one starts its own pair")

        var withFn = Keyboard()
        withFn.press([.command], other: true, at: 0)
        withFn.release(other: true, at: 0.05)
        withFn.press([.command], other: true, at: 0.10)
        withFn.release(other: true, at: 0.15)
        // Only momentary keys may map to `hasOtherModifiers`: a latched bit (Caps Lock's `maskAlphaShift`) would disqualify every press for as long as it stays set, exactly as fn does here.
        expect(withFn.fired, [], "fn held alongside disqualifies the press")

        // The poison clears once the extra modifier is gone.
        var recovered = Keyboard()
        recovered.press([.command], other: true, at: 0)
        recovered.release(at: 0.05)
        recovered.tap(.command, at: 0.10)
        recovered.tap(.command, at: 0.25)
        expect(recovered.fired, [.command], "a clean pair after the poisoned one still fires")
    }

    // MARK: - Interruptions

    static func interruptions() {
        var typed = Keyboard()
        typed.tap(.command, at: 0)
        typed.otherInput(at: 0.08)
        typed.tap(.command, at: 0.15)
        expect(typed.fired, [], "a key press between taps cancels the pair")

        var shortcut = Keyboard()
        shortcut.press([.command], at: 0)
        shortcut.otherInput(at: 0.02)
        shortcut.release(at: 0.05)
        shortcut.tap(.command, at: 0.10)
        expect(shortcut.fired, [], "⌘K then ⌘ isn't a double-tap")

        var clicked = Keyboard()
        clicked.tap(.option, at: 0)
        clicked.otherInput(at: 0.10)
        clicked.tap(.option, at: 0.14)
        expect(clicked.fired, [], "a click between taps cancels the pair")
    }

    // MARK: - Repeats

    static func repeats() {
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.tap(.command, at: 0.15)
        expect(keyboard.fired, [.command], "the pair fires")
        keyboard.tap(.command, at: 0.30)
        expect(keyboard.fired, [.command], "a triple-tap doesn't fire twice")
        keyboard.tap(.command, at: 0.45)
        expect(keyboard.fired, [.command, .command], "the next full pair fires again")
    }

    // MARK: - Reset

    static func resetting() {
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.detector.reset()
        keyboard.tap(.command, at: 0.15)
        expect(keyboard.fired, [], "reset drops the pending tap")

        // Reset also forgets held modifiers, so the next press still reads as a clean start.
        var stuck = Keyboard()
        stuck.press([.command], at: 0)
        stuck.detector.reset()
        stuck.tap(.command, at: 0.10)
        stuck.tap(.command, at: 0.25)
        expect(stuck.fired, [.command], "reset clears a half-held press")
    }

    // MARK: - Hyper key: the four selectable modifier keys

    static let hyperKeys: [(name: String, bit: UInt64)] = [
        ("right control", HyperKeyDeviceFlag.rightControl),
        ("right shift", HyperKeyDeviceFlag.rightShift),
        ("right option", HyperKeyDeviceFlag.rightOption),
        ("right command", HyperKeyDeviceFlag.rightCommand),
    ]

    /// Bits that must never be mistaken for the configured key's: three left-side device flags and a generic modifier mask.
    static let decoyFlags: UInt64 =
        HyperKeyDeviceFlag.leftShift | HyperKeyDeviceFlag.leftCommand
        | HyperKeyDeviceFlag.leftControl | CGEventFlags.maskShift.rawValue

    static func hyperKeyMapping() {
        expect(HyperKeyPhysicalKey.none.deviceBit == nil, "`.none` has no device bit")
        expect(
            HyperKeyPhysicalKey.capsLock.deviceBit == nil,
            "Caps Lock needs none: its F18 remap arrives as keyDown/keyUp")
        expect(
            HyperKeyPhysicalKey.rightControl.deviceBit == HyperKeyDeviceFlag.rightControl,
            "Right Control maps to its own device bit")
        expect(
            HyperKeyPhysicalKey.rightShift.deviceBit == HyperKeyDeviceFlag.rightShift,
            "Right Shift maps to its own device bit")
        expect(
            HyperKeyPhysicalKey.rightOption.deviceBit == HyperKeyDeviceFlag.rightOption,
            "Right Option maps to its own device bit")
        expect(
            HyperKeyPhysicalKey.rightCommand.deviceBit == HyperKeyDeviceFlag.rightCommand,
            "Right Command maps to its own device bit")
        expect(
            Set(HyperKeyPhysicalKey.allCases.compactMap(\.deviceBit)).count == 4,
            "the four selectable modifier keys carry four distinct bits")
    }

    // MARK: - Hyper key: direction from the event's own flags

    static func hyperKeyPressRelease() {
        for key in hyperKeys {
            var machine = HyperKeyHoldMachine(deviceBit: key.bit)
            let down = machine.modifierTransition(flagsRaw: key.bit | decoyFlags, at: 0)
            expect(down.isHeld && !down.corrected, "\(key.name): the press hyperizes")
            expect(machine.isHeld, "\(key.name): the hold is tracked")
            let up = machine.modifierTransition(flagsRaw: decoyFlags, at: 1.0)
            expect(!up.isHeld && !up.corrected, "\(key.name): the release restores")
            expect(!up.firesQuickPress, "\(key.name): a one-second hold is no Quick Press")
            expect(!machine.isHeld, "\(key.name): and the hold is gone")

            expect(machine.hasSeenDeviceBit, "\(key.name): the keyboard is known to report the bit")
            expect(
                !machine.modifierTransition(flagsRaw: decoyFlags, at: 2.0).isHeld,
                "\(key.name): another key's bits never start a hold")
        }
    }

    // MARK: - Hyper key: the regression

    static func hyperKeyInterruption() {
        let bit = HyperKeyDeviceFlag.rightCommand

        // A stalled main thread makes the system disable the tap mid-hold. The old machine inferred
        // direction by toggling a bool and dropped the hold on re-enable, so it read the following
        // release as a press and stayed inverted for the rest of the session.
        var stranded = HyperKeyHoldMachine(deviceBit: bit)
        _ = stranded.modifierTransition(flagsRaw: bit, at: 0)
        stranded.tapInterrupted()
        expect(
            !stranded.modifierTransition(flagsRaw: 0, at: 0.4).isHeld,
            "the release after an interruption is still a release")
        expect(
            stranded.modifierTransition(flagsRaw: bit, at: 0.8).isHeld,
            "the next press after an interruption still hyperizes")
        expect(
            !stranded.modifierTransition(flagsRaw: 0, at: 1.2).isHeld,
            "and the machine keeps alternating correctly")

        // A release delivered into the blackout was never seen: the next event re-derives the hold.
        var missed = HyperKeyHoldMachine(deviceBit: bit)
        _ = missed.modifierTransition(flagsRaw: bit, at: 0)
        missed.tapInterrupted()
        let resynced = missed.resync(flagsRaw: decoyFlags, at: 0.4)
        expect(
            resynced?.isHeld == false && resynced?.corrected == true,
            "a release missed during the blackout is noticed by the next event")
        expect(!missed.isHeld, "so nothing typed afterwards gets hyperized")
        expect(missed.resync(flagsRaw: decoyFlags, at: 0.5) == nil, "the resync is one-shot")

        var survived = HyperKeyHoldMachine(deviceBit: bit)
        _ = survived.modifierTransition(flagsRaw: bit, at: 0)
        survived.tapInterrupted()
        expect(
            survived.resync(flagsRaw: bit | decoyFlags, at: 0.4) == nil,
            "a key still held through the blackout needs no correction")
        expect(survived.isHeld, "and its hold survives, rather than being thrown away")

        var late = HyperKeyHoldMachine(deviceBit: bit)
        late.tapInterrupted()
        let adopted = late.resync(flagsRaw: bit, at: 0)
        expect(
            adopted?.isHeld == true && adopted?.corrected == true,
            "a press that began during the blackout is adopted")
        expect(
            !late.modifierTransition(flagsRaw: 0, at: 0.05).firesQuickPress,
            "but an adopted hold of unknown history never fires Quick Press")

        var resigned = HyperKeyHoldMachine(deviceBit: bit)
        _ = resigned.modifierTransition(flagsRaw: bit, at: 0)
        resigned.cancel()
        expect(
            !resigned.isHeld && !resigned.needsResync,
            "a session switch drops the hold outright")
    }

    // MARK: - Hyper key: malformed event streams

    static func hyperKeyDuplicates() {
        let bit = HyperKeyDeviceFlag.rightOption
        var machine = HyperKeyHoldMachine(deviceBit: bit)
        expect(machine.modifierTransition(flagsRaw: bit, at: 0).isHeld, "the press holds")
        let again = machine.modifierTransition(flagsRaw: bit, at: 0.05)
        expect(again.isHeld && again.corrected, "a duplicated press stays held, and is reported")
        let up = machine.modifierTransition(flagsRaw: 0, at: 0.1)
        expect(
            !up.isHeld && up.firesQuickPress,
            "the duplicate neither inverts the machine nor restarts its Quick Press clock")
        let upAgain = machine.modifierTransition(flagsRaw: 0, at: 0.15)
        expect(
            !upAgain.isHeld && !upAgain.firesQuickPress && upAgain.corrected,
            "a duplicated release stays released")
        expect(
            machine.modifierTransition(flagsRaw: bit, at: 0.2).isHeld,
            "and the next real press still hyperizes")
    }

    static func hyperKeyOrphanRelease() {
        let bit = HyperKeyDeviceFlag.rightShift
        var machine = HyperKeyHoldMachine(deviceBit: bit)
        _ = machine.modifierTransition(flagsRaw: bit, at: 0)
        _ = machine.modifierTransition(flagsRaw: decoyFlags, at: 0.1)
        let orphan = machine.modifierTransition(flagsRaw: decoyFlags, at: 0.2)
        expect(!orphan.isHeld && orphan.corrected, "a release with no press reads as released")
        expect(!orphan.firesQuickPress, "and fires nothing")
        expect(
            machine.modifierTransition(flagsRaw: bit, at: 0.3).isHeld,
            "the press that follows it still hyperizes")
    }

    // MARK: - Hyper key: Quick Press and the no-device-bit fallback

    static func hyperKeyQuickPress() {
        let bit = HyperKeyDeviceFlag.rightCommand
        let window = HyperKeyHoldMachine.quickPressWindow

        var lone = HyperKeyHoldMachine(deviceBit: bit)
        _ = lone.modifierTransition(flagsRaw: bit, at: 0)
        expect(
            lone.modifierTransition(flagsRaw: 0, at: window - 0.01).firesQuickPress,
            "a short lone press is a Quick Press")

        var slow = HyperKeyHoldMachine(deviceBit: bit)
        _ = slow.modifierTransition(flagsRaw: bit, at: 0)
        expect(
            !slow.modifierTransition(flagsRaw: 0, at: window).firesQuickPress,
            "a press exactly at the window boundary is not")

        var combo = HyperKeyHoldMachine(deviceBit: bit)
        _ = combo.modifierTransition(flagsRaw: bit, at: 0)
        combo.noteOtherKeyPressed()
        expect(
            !combo.modifierTransition(flagsRaw: 0, at: 0.05).firesQuickPress,
            "a key pressed during the hold makes it a combo, however short")

        // Caps Lock arrives as keyDown/keyUp through its F18 remap and already says which it is.
        var caps = HyperKeyHoldMachine(deviceBit: nil)
        expect(caps.keyTransition(isDown: true, at: 0).isHeld, "Caps Lock's keyDown holds")
        expect(
            caps.keyTransition(isDown: false, at: 0.05).firesQuickPress,
            "and its short keyUp is a Quick Press")
        var capsCombo = HyperKeyHoldMachine(deviceBit: nil)
        _ = capsCombo.keyTransition(isDown: true, at: 0)
        capsCombo.noteOtherKeyPressed()
        expect(
            !capsCombo.keyTransition(isDown: false, at: 0.05).firesQuickPress,
            "a Caps Lock chord isn't a Quick Press either")
    }

    static func hyperKeyFallback() {
        // A key whose device bit can't be read falls back to toggling — all the machine ever had.
        var machine = HyperKeyHoldMachine(deviceBit: nil)
        expect(machine.isKeyDown(flagsRaw: ~0) == nil, "with no device bit there is nothing to read")
        expect(
            machine.modifierTransition(flagsRaw: 0, at: 0).isHeld,
            "the fallback's first transition holds")
        expect(
            !machine.modifierTransition(flagsRaw: 0, at: 0.05).isHeld,
            "and its second releases")
        machine.tapInterrupted()
        expect(machine.resync(flagsRaw: 0, at: 0.1) == nil, "there is nothing to resync from")
        expect(!machine.needsResync, "but the one-shot is spent either way")

        // A keyboard that never reports the bit must not read every press as a release, which
        // would disable Hyper outright; a bit that has never once been seen set proves nothing.
        let bit = HyperKeyDeviceFlag.rightControl
        var silent = HyperKeyHoldMachine(deviceBit: bit)
        expect(
            silent.modifierTransition(flagsRaw: 0, at: 0).isHeld,
            "an unreported device bit falls back to toggling rather than refusing to hold")
        expect(!silent.hasSeenDeviceBit, "and the keyboard is still unproven")
        expect(
            !silent.modifierTransition(flagsRaw: 0, at: 0.05).isHeld,
            "the fallback release still releases")

        // The first press that does carry the bit switches that key to ground truth for good.
        var proven = HyperKeyHoldMachine(deviceBit: bit)
        _ = proven.modifierTransition(flagsRaw: bit, at: 0)
        expect(proven.hasSeenDeviceBit, "one reported press is enough")
        _ = proven.modifierTransition(flagsRaw: 0, at: 0.3)
        expect(
            !proven.modifierTransition(flagsRaw: 0, at: 0.4).isHeld,
            "after which a clear bit always means released")
    }

    // MARK: - Hyper key: chord composition

    static func hyperKeyChord() {
        // The real CGEventFlags values, exactly as `HyperKeyTap` hands them over; what is pinned here is how they are combined.
        let masks = HyperKeyModifierMasks(
            control: CGEventFlags.maskControl.rawValue,
            option: CGEventFlags.maskAlternate.rawValue,
            shift: CGEventFlags.maskShift.rawValue,
            command: CGEventFlags.maskCommand.rawValue,
            alphaShift: CGEventFlags.maskAlphaShift.rawValue)
        let leftBits =
            HyperKeyDeviceFlag.leftControl | HyperKeyDeviceFlag.leftOption
            | HyperKeyDeviceFlag.leftCommand

        let withShift = HyperKeyChord.heldFlags(masks: masks, includesShift: true)
        expect(
            withShift
                == masks.control | masks.option | masks.shift | masks.command | leftBits
                    | HyperKeyDeviceFlag.leftShift,
            "the shift-included chord is ⌃⌥⇧⌘ with all four left device bits")
        let withoutShift = HyperKeyChord.heldFlags(masks: masks, includesShift: false)
        expect(
            withoutShift == masks.control | masks.option | masks.command | leftBits,
            "the shift-excluded chord drops both the shift mask and its device bit")
        expect(
            withShift & (HyperKeyDeviceFlag.rightCommand | HyperKeyDeviceFlag.rightShift) == 0,
            "the chord posts left-side device bits only")

        // A Hyper key whose own modifier the chord already carries leaves no residue to scrub.
        expect(
            HyperKeyChord.strippedFlags(
                ownMask: masks.command, isCapsLock: false, masks: masks, includesShift: true) == 0,
            "Right Command's ⌘ is part of the chord, so nothing is stripped")
        expect(
            HyperKeyChord.strippedFlags(
                ownMask: masks.shift, isCapsLock: false, masks: masks, includesShift: true) == 0,
            "nor is Right Shift's ⇧ while Include Shift is on")
        expect(
            HyperKeyChord.strippedFlags(
                ownMask: masks.shift, isCapsLock: false, masks: masks, includesShift: false)
                == masks.shift | HyperKeyDeviceFlag.leftShift | HyperKeyDeviceFlag.rightShift,
            "with Include Shift off, Right Shift's mask and both device bits are stripped")
        expect(
            HyperKeyChord.strippedFlags(
                ownMask: nil, isCapsLock: true, masks: masks, includesShift: true)
                == masks.alphaShift,
            "Caps Lock's own latch bit is always scrubbed")
    }
}
