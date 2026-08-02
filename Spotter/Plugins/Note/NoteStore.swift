import Combine
import Foundation

enum NoteSaveState: Equatable {
    case saved
    case saving
    case failed(String)
}

private struct NoteArchive: Codable, Sendable {
    let version: Int
    let notes: [SpotterNote]
}

private actor NoteWriter {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func save(_ archive: NoteArchive) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [SpotterNote]
    @Published private(set) var saveState: NoteSaveState = .saved
    @Published var selectedID: UUID? {
        didSet {
            if let selectedID {
                defaults.set(selectedID.uuidString, forKey: selectedKey)
            } else {
                defaults.removeObject(forKey: selectedKey)
            }
        }
    }

    private let defaults: UserDefaults
    private let selectedKey = "note.selected-id"
    private let writer: NoteWriter
    private let now: () -> Date
    private var saveTask: Task<Void, Never>?
    private var revision: UInt = 0

    init(
        fileURL: URL? = nil, defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        let resolvedURL = fileURL ?? Self.defaultFileURL()
        self.defaults = defaults
        self.writer = NoteWriter(fileURL: resolvedURL)
        self.now = now

        let loaded = Self.load(from: resolvedURL).sorted { $0.updatedAt > $1.updatedAt }
        if loaded.isEmpty {
            let initial = SpotterNote(createdAt: now())
            notes = [initial]
            selectedID = initial.id
        } else {
            notes = loaded
            let persistedID = defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:))
            selectedID = loaded.contains(where: { $0.id == persistedID }) ? persistedID : loaded[0].id
        }
    }

    var selectedNote: SpotterNote? {
        guard let selectedID else { return nil }
        return notes.first { $0.id == selectedID }
    }

    func filteredNotes(query: String) -> [SpotterNote] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.content.localizedCaseInsensitiveContains(query)
        }
    }

    @discardableResult
    func createNote(content: String = "") -> UUID {
        let date = now()
        let note = SpotterNote(content: content, createdAt: date)
        notes.insert(note, at: 0)
        selectedID = note.id
        scheduleSave(immediately: true)
        return note.id
    }

    func select(_ note: SpotterNote) {
        selectedID = note.id
    }

    func updateSelectedContent(_ content: String) {
        guard let selectedID, let index = notes.firstIndex(where: { $0.id == selectedID }),
            notes[index].content != content
        else { return }
        notes[index].content = content
        notes[index].updatedAt = now()
        if index > 0 {
            let updated = notes.remove(at: index)
            notes.insert(updated, at: 0)
        }
        scheduleSave()
    }

    func delete(_ note: SpotterNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let wasSelected = selectedID == note.id
        notes.remove(at: index)
        if wasSelected {
            selectedID = notes.indices.contains(index) ? notes[index].id : notes.last?.id
        }
        scheduleSave(immediately: true)
    }

    func flush() async {
        saveTask?.cancel()
        revision &+= 1
        let currentRevision = revision
        let archive = NoteArchive(version: 1, notes: notes)
        saveState = .saving
        do {
            try await writer.save(archive)
            if revision == currentRevision { saveState = .saved }
        } catch {
            if revision == currentRevision { saveState = .failed(error.localizedDescription) }
        }
    }

    private func scheduleSave(immediately: Bool = false) {
        saveTask?.cancel()
        revision &+= 1
        let currentRevision = revision
        let archive = NoteArchive(version: 1, notes: notes)
        let writer = writer
        saveState = .saving
        saveTask = Task { [weak self] in
            if !immediately {
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            do {
                try await writer.save(archive)
                guard let self, self.revision == currentRevision else { return }
                self.saveState = .saved
            } catch {
                guard let self, self.revision == currentRevision else { return }
                self.saveState = .failed(error.localizedDescription)
            }
        }
    }

    private static func load(from fileURL: URL) -> [SpotterNote] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(NoteArchive.self, from: data).notes) ?? []
    }

    private static func defaultFileURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.spotter.app"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Notes", isDirectory: true)
            .appendingPathComponent("notes.json")
    }
}
