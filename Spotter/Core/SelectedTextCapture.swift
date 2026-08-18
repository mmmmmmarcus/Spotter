import AppKit
import Carbon.HIToolbox

struct SelectedTextSourceSnapshot: Equatable, Sendable {
    let processIdentifier: Int32
    let appName: String
    let bundleIdentifier: String?
}

struct SelectedTextSnapshot: Equatable, Sendable {
    let text: String
    let source: SelectedTextSourceSnapshot
    let capturedAt: Date
}

enum SelectedTextCaptureFailure: Error, Equatable, Sendable {
    case accessibilityDenied
    case noFrontmostApplication
    case spotterIsFrontmost
    case focusedControlUnavailable
    case selectedTextUnavailable
    case emptySelection

    var message: String {
        switch self {
        case .accessibilityDenied:
            "Accessibility access is required to read selected text. Grant it in System Settings."
        case .noFrontmostApplication:
            "No frontmost application was available."
        case .spotterIsFrontmost:
            "Spotter is frontmost. Return to another app, select text, then use the global shortcut."
        case .focusedControlUnavailable:
            "The frontmost app did not expose a focused text control, and copying the selection produced no text."
        case .selectedTextUnavailable:
            "The selection could not be read through Accessibility, and copying it produced no text."
        case .emptySelection:
            "No text is selected in the frontmost app."
        }
    }

    var isTransientFocusFailure: Bool {
        switch self {
        case .noFrontmostApplication, .spotterIsFrontmost: true
        case .accessibilityDenied, .focusedControlUnavailable, .selectedTextUnavailable,
            .emptySelection: false
        }
    }
}

/// Shared capture for Selection Tools search/translation and AI Chat's selected-text actions.
/// `AppCore` owns the instance because both plugins use the same clipboard-history suppression hooks.
@MainActor
final class SelectedTextCapture {
    static let localSourceIdentifier = NSUserInterfaceItemIdentifier(
        "spotter.selected-text-source")

    var suspendClipboardCapture: (() -> Void)?
    var resumeClipboardCapture: (() -> Void)?
    private var selectionBeforePalette: Result<SelectedTextSnapshot, SelectedTextCaptureFailure>?

    func prepareForPalettePresentation() {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
        else {
            selectionBeforePalette = nil
            return
        }
        selectionBeforePalette = captureLocalSelection()
    }

    func capture() async -> Result<SelectedTextSnapshot, SelectedTextCaptureFailure> {
        // Snapshot before the first await so retries can never switch the capture to Spotter.
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return .failure(.noFrontmostApplication)
        }
        if application.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return captureLocalSelection()
        }

        let source = SelectedTextSourceSnapshot(
            processIdentifier: application.processIdentifier,
            appName: application.localizedName ?? "Unknown App",
            bundleIdentifier: application.bundleIdentifier)
        switch await SelectedTextReader.readAwaitingAccessibilityTree(
            pid: source.processIdentifier)
        {
        case .success(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.emptySelection)
            }
            return .success(SelectedTextSnapshot(text: text, source: source, capturedAt: Date()))
        case .failure(.accessibilityDenied):
            return .failure(.accessibilityDenied)
        case .failure(let error):
            return await copyFallback(source: source, accessibilityError: error)
        }
    }

    /// Launcher commands restore focus before capture; only those transient frontmost-app states retry.
    func captureAfterRestoringFocus()
        async -> Result<SelectedTextSnapshot, SelectedTextCaptureFailure>
    {
        if let selectionBeforePalette {
            self.selectionBeforePalette = nil
            return selectionBeforePalette
        }
        var lastResult: Result<SelectedTextSnapshot, SelectedTextCaptureFailure> =
            .failure(.noFrontmostApplication)
        for attempt in 0..<6 {
            await Task.yield()
            lastResult = await capture()
            guard case .failure(let error) = lastResult, error.isTransientFocusFailure,
                attempt < 5
            else { return lastResult }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return lastResult
    }

    private func captureLocalSelection()
        -> Result<SelectedTextSnapshot, SelectedTextCaptureFailure>
    {
        guard let textView = NSApp.windows.lazy.compactMap({ $0.firstResponder as? NSTextView })
            .first(where: { $0.identifier == Self.localSourceIdentifier })
        else { return .failure(.spotterIsFrontmost) }
        let selection = textView.selectedRange()
        guard selection.length > 0 else { return .failure(.emptySelection) }
        let text = (textView.string as NSString).substring(with: selection)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptySelection)
        }
        let application = NSRunningApplication.current
        let source = SelectedTextSourceSnapshot(
            processIdentifier: application.processIdentifier,
            appName: "Spotter Notes",
            bundleIdentifier: application.bundleIdentifier)
        return .success(SelectedTextSnapshot(text: text, source: source, capturedAt: Date()))
    }

    private func copyFallback(
        source: SelectedTextSourceSnapshot, accessibilityError: SelectedTextReadError
    ) async -> Result<SelectedTextSnapshot, SelectedTextCaptureFailure> {
        suspendClipboardCapture?()
        defer { resumeClipboardCapture?() }
        switch await SelectionCopyCapture.read(pid: source.processIdentifier) {
        case .copied(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.emptySelection)
            }
            return .success(SelectedTextSnapshot(text: text, source: source, capturedAt: Date()))
        case .nothingCopied:
            return .failure(.emptySelection)
        case .noText:
            return .failure(
                accessibilityError == .focusedControlUnavailable
                    ? .focusedControlUnavailable : .selectedTextUnavailable)
        }
    }
}

/// Last-resort capture for canvases and web views that do not expose an Accessibility selection.
@MainActor
private enum SelectionCopyCapture {
    enum Outcome: Equatable {
        case copied(String)
        case noText
        case nothingCopied
    }

    static func read(pid: pid_t) async -> Outcome {
        let pasteboard = NSPasteboard.general
        let saved = snapshotItems(of: pasteboard)
        let baseline = pasteboard.changeCount
        postCommandC(toPid: pid)

        var copied: String?
        var changed = false
        for _ in 0..<14 {
            try? await Task.sleep(for: .milliseconds(50))
            if pasteboard.changeCount != baseline {
                changed = true
                copied = pasteboard.string(forType: .string)
                break
            }
        }
        if changed { restore(saved, to: pasteboard) }
        guard changed else { return .nothingCopied }
        guard let copied, !copied.isEmpty else { return .noText }
        return .copied(copied)
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
