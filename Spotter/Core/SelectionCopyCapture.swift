import AppKit
import Carbon.HIToolbox

/// Last-resort capture for canvases and web views that do not expose an Accessibility selection.
@MainActor
enum SelectionCopyCapture {
    enum Outcome: Equatable {
        case copied(String)
        case noText
        case nothingCopied
    }

    static func read(pid: pid_t) async -> Outcome {
        await read(pasteboard: .general) { postCommandC(toPid: pid) }
    }

    static func read(pasteboard: NSPasteboard, copy: () -> Void) async -> Outcome {
        guard !Task.isCancelled else { return .nothingCopied }
        let saved = snapshotItems(of: pasteboard)
        let baseline = pasteboard.changeCount
        copy()
        var changed = false
        defer { if changed { restore(saved, to: pasteboard) } }
        for _ in 0..<24 {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
            if pasteboard.changeCount != baseline {
                changed = true
                // Web editors can declare clipboard formats before supplying the selected text.
                if let text = pasteboard.string(forType: .string),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .copied(text)
                }
            }
        }
        changed = pasteboard.changeCount != baseline
        return changed ? .noText : .nothingCopied
    }

    private static func snapshotItems(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for item in items { item.setData(Data(), forType: ClipboardManager.internalType) }
        if items.isEmpty {
            let marker = NSPasteboardItem()
            marker.setData(Data(), forType: ClipboardManager.internalType)
            pasteboard.writeObjects([marker])
        } else {
            pasteboard.writeObjects(items)
        }
    }

    private static func postCommandC(toPid pid: pid_t) {
        guard Permissions.ensureAccessibility() else { return }
        commandCEvents().forEach { $0.postToPid(pid) }
    }

    static func commandCEvents() -> [CGEvent] {
        let source = CGEventSource(stateID: .privateState)
        return [true, false].compactMap { down in
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: down) else { return nil }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: HyperKeyTap.syntheticTag)
            return event
        }
    }
}
