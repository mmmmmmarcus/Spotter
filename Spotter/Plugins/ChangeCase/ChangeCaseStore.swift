import AppKit

enum ChangeCaseInputSource: String, CaseIterable, Identifiable {
    case selectedText, clipboard
    var id: String { rawValue }
    var title: String { self == .selectedText ? "Selected Text" : "Clipboard" }
}

enum ChangeCasePrimaryAction: String, CaseIterable, Identifiable {
    case copy, paste
    var id: String { rawValue }
    var title: String { self == .copy ? "Copy" : "Paste" }
}

@MainActor
final class ChangeCaseStore: ObservableObject {
    @Published var input = ""
    @Published var query = ""
    @Published private(set) var pinned: Set<ChangeCaseKind> = []
    @Published private(set) var recent: [ChangeCaseKind] = []

    private let defaults = UserDefaults.standard

    init() {
        pinned = Set((defaults.stringArray(forKey: "change-case.pinned") ?? []).compactMap(ChangeCaseKind.init(rawValue:)))
        recent = (defaults.stringArray(forKey: "change-case.recent") ?? []).compactMap(ChangeCaseKind.init(rawValue:))
    }

    var enabledKinds: [ChangeCaseKind] {
        let disabled = Set(defaults.stringArray(forKey: "change-case.disabled") ?? [])
        return ChangeCaseKind.allCases.filter { !disabled.contains($0.rawValue) }
    }

    var options: ChangeCaseOptions {
        ChangeCaseOptions(
            preserveCase: defaults.object(forKey: "change-case.preserve-case") == nil
                || defaults.bool(forKey: "change-case.preserve-case"),
            preservePunctuation: defaults.bool(forKey: "change-case.preserve-punctuation"),
            exceptions: (defaults.string(forKey: "change-case.exceptions") ?? "iOS, iPadOS, iPhone, macOS, tvOS, watchOS")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            prefixCharacters: defaults.string(forKey: "change-case.prefix") ?? "",
            suffixCharacters: defaults.string(forKey: "change-case.suffix") ?? "")
    }

    func loadInput(from app: NSRunningApplication?) {
        let source = ChangeCaseInputSource(rawValue: defaults.string(forKey: "change-case.source") ?? "selectedText") ?? .selectedText
        let selected = app.flatMap {
            try? SelectedTextReader.read(pid: $0.processIdentifier).get()
        }
        let clipboard = NSPasteboard.general.string(forType: .string)
        input = source == .selectedText ? (selected ?? clipboard ?? "") : (clipboard ?? selected ?? "")
    }

    func output(for kind: ChangeCaseKind) -> String {
        ChangeCaseEngine.transform(input, as: kind, options: options)
    }

    func record(_ kind: ChangeCaseKind) {
        recent.removeAll { $0 == kind }
        recent.insert(kind, at: 0)
        recent = Array(recent.prefix(4))
        persist()
    }

    func togglePinned(_ kind: ChangeCaseKind) {
        if pinned.contains(kind) { pinned.remove(kind) } else { pinned.insert(kind) }
        persist()
    }

    func removeRecent(_ kind: ChangeCaseKind) {
        recent.removeAll { $0 == kind }
        persist()
    }

    func clearPinned() { pinned.removeAll(); persist() }
    func clearRecent() { recent.removeAll(); persist() }

    func isEnabled(_ kind: ChangeCaseKind) -> Bool {
        !Set(defaults.stringArray(forKey: "change-case.disabled") ?? []).contains(kind.rawValue)
    }

    func setEnabled(_ enabled: Bool, kind: ChangeCaseKind) {
        var disabled = Set(defaults.stringArray(forKey: "change-case.disabled") ?? [])
        if enabled { disabled.remove(kind.rawValue) } else { disabled.insert(kind.rawValue) }
        defaults.set(disabled.sorted(), forKey: "change-case.disabled")
        objectWillChange.send()
    }

    private func persist() {
        defaults.set(pinned.map(\.rawValue).sorted(), forKey: "change-case.pinned")
        defaults.set(recent.map(\.rawValue), forKey: "change-case.recent")
    }
}
