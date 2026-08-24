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
    var tombstones: [NoteTombstone]?
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
    static let maximumWindowTransparency = 1.0

    @Published private(set) var notes: [SpotterNote]
    @Published private(set) var saveState: NoteSaveState = .saved
    @Published private(set) var windowTransparency: Double
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
    private static let windowTransparencyKey = "note.window-transparency"
    private let writer: NoteWriter
    private let now: () -> Date
    private var saveTask: Task<Void, Never>?
    private var revision: UInt = 0
    private var tombstones: [UUID: NoteTombstone]
    var onSyncSnapshotChanged: ((NoteSyncSnapshot) -> Void)?

    init(
        fileURL: URL? = nil, defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        let resolvedURL = fileURL ?? Self.defaultFileURL()
        self.defaults = defaults
        self.writer = NoteWriter(fileURL: resolvedURL)
        self.now = now
        windowTransparency = defaults.object(forKey: Self.windowTransparencyKey) == nil
            ? 0
            : min(
                max(defaults.double(forKey: Self.windowTransparencyKey), 0),
                Self.maximumWindowTransparency)

        let archive = Self.load(from: resolvedURL)
        let loaded = archive.notes.sorted { $0.contentUpdatedAt > $1.contentUpdatedAt }
        tombstones = Dictionary(
            uniqueKeysWithValues: (archive.tombstones ?? []).map { ($0.id, $0) })
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
        tombstones.removeValue(forKey: note.id)
        selectedID = note.id
        scheduleSave(immediately: true)
        notifySyncSnapshotChanged()
        return note.id
    }

    func select(_ note: SpotterNote) {
        selectedID = note.id
    }

    /// A tint is a user modification, so it bumps `updatedAt` and syncs — but never
    /// `contentUpdatedAt`, so recoloring a Note leaves it where it sits in the list.
    func setTint(_ tint: NoteTint?, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].tint != tint
        else { return }
        notes[index].tint = tint
        notes[index].updatedAt = now()
        scheduleSave(immediately: true)
        notifySyncSnapshotChanged()
    }

    func setWindowTransparency(_ value: Double) {
        let clamped = min(max(value, 0), Self.maximumWindowTransparency)
        guard windowTransparency != clamped else { return }
        windowTransparency = clamped
        defaults.set(clamped, forKey: Self.windowTransparencyKey)
    }

    @discardableResult
    func selectAdjacent(_ direction: NoteNavigationDirection) -> SpotterNote? {
        guard !notes.isEmpty else { return nil }
        let current = notes.firstIndex { $0.id == selectedID } ?? 0
        let offset = direction == .previous ? -1 : 1
        let next = (current + offset + notes.count) % notes.count
        selectedID = notes[next].id
        return notes[next]
    }

    func updateSelectedContent(_ content: String) {
        guard let selectedID, let index = notes.firstIndex(where: { $0.id == selectedID }),
            notes[index].content != content
        else { return }
        let date = now()
        notes[index].content = content
        notes[index].updatedAt = date
        notes[index].contentUpdatedAt = date
        if index > 0 {
            let updated = notes.remove(at: index)
            notes.insert(updated, at: 0)
        }
        scheduleSave()
        notifySyncSnapshotChanged()
    }

    func delete(_ note: SpotterNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let wasSelected = selectedID == note.id
        notes.remove(at: index)
        tombstones[note.id] = NoteTombstone(id: note.id, deletedAt: now())
        if wasSelected {
            selectedID = notes.indices.contains(index) ? notes[index].id : notes.last?.id
        }
        scheduleSave(immediately: true)
        notifySyncSnapshotChanged()
    }

    @discardableResult
    func deleteEmptyNotes() -> Int {
        let emptyNotes = notes.filter {
            $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !emptyNotes.isEmpty else { return 0 }
        let emptyIDs = Set(emptyNotes.map(\.id))
        let deletedAt = now()
        notes.removeAll { emptyIDs.contains($0.id) }
        for id in emptyIDs {
            tombstones[id] = NoteTombstone(id: id, deletedAt: deletedAt)
        }
        if let selectedID, emptyIDs.contains(selectedID) {
            self.selectedID = notes.first?.id
        }
        scheduleSave(immediately: true)
        notifySyncSnapshotChanged()
        return emptyNotes.count
    }

    /// Full-state replacement follows the synced selection when that note still exists.
    func replace(notes newNotes: [SpotterNote], selectedID newSelectedID: UUID?) {
        let incomingIDs = Set(newNotes.map(\.id))
        for note in notes where !incomingIDs.contains(note.id) {
            tombstones[note.id] = NoteTombstone(id: note.id, deletedAt: now())
        }
        for id in incomingIDs { tombstones.removeValue(forKey: id) }
        notes = newNotes.sorted { $0.contentUpdatedAt > $1.contentUpdatedAt }
        selectedID = notes.contains(where: { $0.id == newSelectedID })
            ? newSelectedID : notes.first?.id
        scheduleSave(immediately: true)
        notifySyncSnapshotChanged()
    }

    var syncSnapshot: NoteSyncSnapshot {
        NoteSyncSnapshot(
            notes: notes,
            tombstones: tombstones.values.sorted { $0.deletedAt > $1.deletedAt })
    }

    func applyCloudSnapshot(_ remote: NoteSyncSnapshot) {
        let merged = NoteSyncMerge.merging(syncSnapshot, with: remote)
        let oldSelection = selectedID
        notes = merged.notes
        tombstones = merged.tombstonesByID
        selectedID = notes.contains(where: { $0.id == oldSelection }) ? oldSelection : notes.first?.id
        scheduleSave(immediately: true)
    }

    func flush() async {
        saveTask?.cancel()
        revision &+= 1
        let currentRevision = revision
        let archive = archiveSnapshot()
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
        let archive = archiveSnapshot()
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

    private func archiveSnapshot() -> NoteArchive {
        NoteArchive(
            version: 2, notes: notes,
            tombstones: tombstones.values.sorted { $0.deletedAt > $1.deletedAt })
    }

    private func notifySyncSnapshotChanged() {
        onSyncSnapshotChanged?(syncSnapshot)
    }

    private static func load(from fileURL: URL) -> NoteArchive {
        guard let data = try? Data(contentsOf: fileURL) else {
            return NoteArchive(version: 2, notes: [], tombstones: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(NoteArchive.self, from: data))
            ?? NoteArchive(version: 2, notes: [], tombstones: [])
    }

    private static func defaultFileURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.spotter.app1"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Notes", isDirectory: true)
            .appendingPathComponent("notes.json")
    }
}
