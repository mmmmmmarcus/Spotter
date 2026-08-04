import AppKit
import Carbon.HIToolbox

/// Last-resort selection capture: ask the source app to copy, read the produced string, put the user's pasteboard back. Canvas surfaces (Figma) and some web views never expose a selection through Accessibility, so ⌘C is the only capture that works there.
@MainActor
enum SelectionCopyCapture {
    enum Outcome: Equatable {
        case copied(String)
        /// The app wrote to the pasteboard but produced no plain text (e.g. a proprietary object copy).
        case noText
        /// The app never wrote — there was nothing to copy.
        case nothingCopied
    }

    /// The caller must suppress clipboard-history capture around this call; the transient copy and the restore both bump the pasteboard.
    static func read(pid: pid_t) async -> Outcome {
        let pasteboard = NSPasteboard.general
        let saved = snapshotItems(of: pasteboard)
        let baseline = pasteboard.changeCount

        postCommandC(toPid: pid)

        var copied: String?
        var changed = false
        // Electron apps can take several hundred ms to service a synthetic ⌘C.
        for _ in 0..<14 {
            try? await Task.sleep(for: .milliseconds(50))
            if pasteboard.changeCount != baseline {
                changed = true
                copied = pasteboard.string(forType: .string)
                break
            }
        }

        // Untouched pasteboard needs no restore — rewriting identical contents would only churn the change count.
        if changed { restore(saved, to: pasteboard) }

        guard changed else { return .nothingCopied }
        guard let copied, !copied.isEmpty else { return .noText }
        return .copied(copied)
    }

    /// Data must be materialized now — `clearContents` during restore invalidates the original items' promises.
    private static func snapshotItems(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        // The internal marker keeps the poller from re-capturing the restore even after suppression lifts.
        for item in items {
            item.setData(Data(), forType: ClipboardManager.internalType)
        }
        if items.isEmpty {
            let marker = NSPasteboardItem()
            marker.setData(Data(), forType: ClipboardManager.internalType)
            pasteboard.writeObjects([marker])
        } else {
            pasteboard.writeObjects(items)
        }
    }

    /// Synthetic ⌘C delivered straight to the source process, mirroring `Paster.postCommandV(toPid:)`.
    private static func postCommandC(toPid pid: pid_t) {
        guard Permissions.ensureAccessibility() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let c = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: source, virtualKey: c, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: c, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.postToPid(pid)
        up?.postToPid(pid)
    }
}
