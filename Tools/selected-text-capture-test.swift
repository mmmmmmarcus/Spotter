import AppKit
import Carbon.HIToolbox

enum ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("spotter.selection-test.internal")
}
enum Permissions {
    static func ensureAccessibility() -> Bool { fatalError("Tests must never ask for Accessibility") }
}
enum HyperKeyTap {
    static let syntheticTag: Int64 = 0x5459_4354
}

@main
@MainActor
struct SelectedTextCaptureTests {
    static func main() async {
        var failures = 0
        func check(_ name: String, _ passed: Bool) {
            print("\(passed ? "PASS" : "FAIL")  \(name)")
            if !passed { failures += 1 }
        }
        var markerRead = false
        let native = SelectedTextReader.resolveSelection(primary: { "  你好 🧭  " }, marker: {
            markerRead = true
            return "other"
        })
        check("native selection retains whitespace and bypasses markers", native == "  你好 🧭  " && !markerRead)
        check("empty AX text still tries the Chromium marker range", SelectedTextReader.resolveSelection(
            primary: { "" }, marker: { "selected words" }) == "selected words")
        check("empty Chromium marker cannot short-circuit copy fallback", SelectedTextReader.resolveSelection(
            primary: { nil }, marker: { "" }) == nil)
        check("whitespace-only selection cannot short-circuit copy fallback", SelectedTextReader.resolveSelection(
            primary: { " \n" }, marker: { "\t" }) == nil)

        let events = SelectionCopyCapture.commandCEvents()
        check("copy produces a down and up pair", events.map(\.type) == [.keyDown, .keyUp])
        check("copy does not inherit Hyper modifiers", events.count == 2 && events.allSatisfy { $0.flags == .maskCommand })
        check("copy targets C and bypasses Hyper rewriting", events.count == 2 && events.allSatisfy {
            $0.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_C)
                && $0.getIntegerValueField(.eventSourceUserData) == HyperKeyTap.syntheticTag
        })

        let board = NSPasteboard(name: .init("spotter-selection-test-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        func seed() {
            board.clearContents()
            board.setString("original", forType: .string)
            board.setData(Data([1, 2, 3]), forType: .rtf)
        }
        seed()
        let delayed = await SelectionCopyCapture.read(pasteboard: board) {
            board.clearContents()
            board.setString("", forType: .string)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                board.setString("选中的文字", forType: .string)
            }
        }
        check("copy waits through an early empty clipboard update", delayed == .copied("选中的文字"))
        check("original plain and rich clipboard content are restored", board.string(forType: .string) == "original"
            && board.data(forType: .rtf) == Data([1, 2, 3]))
        check("restoration is marked to skip clipboard history", board.types?.contains(ClipboardManager.internalType) == true)
        seed()
        let untouchedCount = board.changeCount
        let unchanged = await SelectionCopyCapture.read(pasteboard: board) {}
        check("no copy never translates stale clipboard text", unchanged == .nothingCopied)
        check("no copy leaves clipboard untouched", board.changeCount == untouchedCount)
        let nontext = await SelectionCopyCapture.read(pasteboard: board) {
            board.clearContents()
            board.setData(Data([4, 5]), forType: .png)
        }
        check("non-text copy is reported as unavailable", nontext == .noText)
        check("non-text copy restores original data", board.string(forType: .string) == "original")
        let cancelled = Task { @MainActor in
            await SelectionCopyCapture.read(pasteboard: board) { fatalError("Cancelled capture must not copy") }
        }
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        check("cancelled capture never synthesizes a key", cancelledResult == .nothingCopied)
        print("Selected text capture: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
