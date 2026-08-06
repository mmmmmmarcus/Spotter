import Combine
import Foundation

/// Persists the user's quicklinks as versioned JSON, alongside Notes' archive rather than in a
/// second SQLite database — the list is small, read whole, and worth keeping hand-editable.
/// Foundation + Combine only, so `Tools/quicklink-test.swift` compiles it standalone.
@MainActor
final class QuicklinkStore: ObservableObject {
    @Published private(set) var quicklinks: [Quicklink] = []

    /// Fired after any mutation so the plugin can republish its launcher slice.
    var onChange: (() -> Void)?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.spotter.app"
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent("Quicklinks", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("quicklinks.json")
        }
        quicklinks = Self.load(from: self.fileURL)
    }

    func add(_ quicklink: Quicklink) {
        quicklinks.append(quicklink)
        persist()
    }

    func update(_ quicklink: Quicklink) {
        guard let index = quicklinks.firstIndex(where: { $0.id == quicklink.id }) else { return }
        quicklinks[index] = quicklink
        persist()
    }

    func delete(id: UUID) {
        quicklinks.removeAll { $0.id == id }
        persist()
    }

    func togglePinned(id: UUID) {
        guard let index = quicklinks.firstIndex(where: { $0.id == id }) else { return }
        quicklinks[index].pinnedAt = quicklinks[index].isPinned ? nil : Date()
        persist()
    }

    func quicklink(id: UUID) -> Quicklink? {
        quicklinks.first { $0.id == id }
    }

    /// Settings-backup import: replace wholesale, dropping entries with no usable link.
    func replace(with newLinks: [Quicklink]) {
        quicklinks = newLinks.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                && !$0.link.trimmingCharacters(in: .whitespaces).isEmpty
        }
        persist()
    }

    var sorted: [Quicklink] { quicklinks.sorted(by: Quicklink.precedes) }

    private func persist() {
        quicklinks.sort(by: Quicklink.precedes)
        let payload = Archive(version: 1, quicklinks: quicklinks)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
        onChange?()
    }

    private static func load(from url: URL) -> [Quicklink] {
        guard let data = try? Data(contentsOf: url),
            let archive = try? JSONDecoder().decode(Archive.self, from: data)
        else { return [] }
        return archive.quicklinks.sorted(by: Quicklink.precedes)
    }

    private struct Archive: Codable {
        var version: Int
        var quicklinks: [Quicklink]
    }
}
