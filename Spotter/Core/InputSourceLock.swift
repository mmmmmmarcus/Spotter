import Carbon
import Foundation

/// Switches the keyboard to an ASCII-capable input source as the palette opens, so a query typed
/// with a CJK/IME layout active doesn't land in a composition buffer.
///
/// Deliberately one-shot: it selects the source at summon time and never watches or reverts. The
/// user staying in control is the point — switching to Pinyin *while* the palette is open (to search
/// a Chinese-named app, say) must keep working, and restoring the old source on hide would fight
/// the OS's own per-app input memory.
enum InputSourceLock {
    /// The user's ASCII-capable source, preferring the one macOS itself would pick.
    private nonisolated static func asciiSource() -> TISInputSource? {
        // The keyboard-layout companion of the current source is the OS's own answer for "the ASCII input for this setup".
        if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            isASCIICapable(current)
        {
            return nil  // already ASCII — nothing to switch
        }
        if let fallback = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() {
            return fallback
        }
        return nil
    }

    private nonisolated static func isASCIICapable(_ source: TISInputSource) -> Bool {
        guard
            let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable)
        else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue() == kCFBooleanTrue
    }

    /// No-op when the current source already types ASCII, so the common case costs one property read.
    static func selectASCIIKeyboard() {
        guard let source = asciiSource() else { return }
        TISSelectInputSource(source)
    }
}
