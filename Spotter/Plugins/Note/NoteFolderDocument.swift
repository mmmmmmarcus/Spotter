import Foundation

/// One Note as it lives in the user-chosen folder: Markdown with a small front-matter header.
/// Everything here is pure so `Tools/note-test.swift` can exercise the format, the naming scheme
/// and the reconciliation without touching a real folder.
enum NoteFolderFormat {
    static let fileExtension = "md"
    /// Hidden, so the scanner skips it, and JSON rather than Markdown so it can never read as a Note.
    static let ledgerFileName = ".spotter-notes.json"
    static let fence = "---"
    static let idKey = "spotter-id"
    static let createdKey = "created"
    static let updatedKey = "updated"
    static let contentUpdatedKey = "content-updated"
    static let tintKey = "tint"

    static let knownKeys: Set<String> = [idKey, createdKey, updatedKey, contentUpdatedKey, tintKey]

    /// Reserved for the two-step rename that unblocks a name swap; a crash mid-move therefore
    /// leaves a well-formed Note file the next scan simply renames.
    static let temporaryPrefix = "~"

    static func temporaryName(for id: UUID) -> String {
        temporaryPrefix + id.uuidString + "." + fileExtension
    }

    static func isNoteFileName(_ name: String) -> Bool {
        guard !name.hasPrefix(".") else { return false }
        return (name as NSString).pathExtension.lowercased() == fileExtension
    }
}

enum NoteFolderDates {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.timeZone = TimeZone(secondsFromGMT: 0)
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        plain.timeZone = TimeZone(secondsFromGMT: 0)
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }
}

enum NoteFolderDocument {
    /// What one readable `.md` file turned out to be.
    enum Parsed: Equatable, Sendable {
        /// The file carried Spotter front matter, so it keeps its identity.
        case note(SpotterNote, extras: [String])
        /// No front matter at all — a file a human wrote. It becomes a Note rather than an error.
        case adopted(SpotterNote)
        /// Blank and unidentified. Not a Note, and never written to or removed.
        case ignored
    }

    static func serialize(_ note: SpotterNote, extras: [String] = []) -> String {
        var header = [NoteFolderFormat.fence]
        header.append("\(NoteFolderFormat.idKey): \(note.id.uuidString)")
        header.append("\(NoteFolderFormat.createdKey): \(NoteFolderDates.string(from: note.createdAt))")
        header.append("\(NoteFolderFormat.updatedKey): \(NoteFolderDates.string(from: note.updatedAt))")
        header.append(
            "\(NoteFolderFormat.contentUpdatedKey): "
                + NoteFolderDates.string(from: note.contentUpdatedAt))
        if let tint = note.tint {
            header.append("\(NoteFolderFormat.tintKey): \(tint.rawValue)")
        }
        header.append(contentsOf: sanitizedExtras(extras))
        header.append(NoteFolderFormat.fence)
        // The body is appended verbatim, so a write→read cycle returns the user's Markdown exactly.
        return header.joined(separator: "\n") + "\n" + note.content
    }

    /// Front matter is only Spotter's when it carries a usable `spotter-id`; anything else is body,
    /// so a hand-written file with its own `---` block keeps every byte of it.
    static func parse(_ text: String, newID: () -> UUID, now: () -> Date) -> Parsed {
        if let header = frontMatter(in: text) {
            let fields = header.fields
            if let raw = fields[NoteFolderFormat.idKey], let id = UUID(uuidString: raw) {
                let created = fields[NoteFolderFormat.createdKey].flatMap(NoteFolderDates.date(from:))
                let updated = fields[NoteFolderFormat.updatedKey].flatMap(NoteFolderDates.date(from:))
                let contentUpdated = fields[NoteFolderFormat.contentUpdatedKey]
                    .flatMap(NoteFolderDates.date(from:))
                // A missing or malformed date reads as "just appeared" rather than as ancient: the
                // file then wins its merge, and winning a merge is the branch that keeps content.
                let stamp = now()
                let note = SpotterNote(
                    id: id, content: header.body, createdAt: created ?? stamp,
                    updatedAt: updated ?? created ?? stamp,
                    contentUpdatedAt: contentUpdated ?? updated ?? created ?? stamp,
                    tint: fields[NoteFolderFormat.tintKey].flatMap(NoteTint.init(rawValue:)))
                return .note(note, extras: header.extras)
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .ignored }
        let stamp = now()
        return .adopted(SpotterNote(id: newID(), content: text, createdAt: stamp))
    }

    private struct FrontMatter {
        var fields: [String: String]
        var extras: [String]
        var body: String
    }

    private static func frontMatter(in text: String) -> FrontMatter? {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1, isFence(lines[0]) else { return nil }
        guard let close = lines.dropFirst().firstIndex(where: isFence) else { return nil }
        var fields: [String: String] = [:]
        var extras: [String] = []
        for line in lines[1..<close] {
            let content = line.hasSuffix("\r") ? String(line.dropLast()) : line
            guard let separator = content.firstIndex(of: ":") else {
                extras.append(content)
                continue
            }
            let key = String(content[content.startIndex..<separator])
                .trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(content[content.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            if NoteFolderFormat.knownKeys.contains(key) {
                fields[key] = value
            } else {
                extras.append(content)
            }
        }
        // Whole lines are consumed, so the remainder is the original string byte-for-byte.
        let consumed = lines[0...close].reduce(0) { $0 + $1.count + 1 }
        return FrontMatter(fields: fields, extras: extras, body: String(text.dropFirst(consumed)))
    }

    private static func isFence(_ line: String) -> Bool {
        let trimmed = line.hasSuffix("\r") ? String(line.dropLast()) : line
        return trimmed.trimmingCharacters(in: .whitespaces) == NoteFolderFormat.fence
    }

    /// Foreign header lines are carried through a rewrite, but never one that could close the block.
    private static func sanitizedExtras(_ extras: [String]) -> [String] {
        extras.filter { line in
            guard !line.contains("\n"), !line.contains("\r") else { return false }
            guard line.trimmingCharacters(in: .whitespaces) != NoteFolderFormat.fence else {
                return false
            }
            guard let separator = line.firstIndex(of: ":") else { return true }
            let key = String(line[line.startIndex..<separator])
                .trimmingCharacters(in: .whitespaces).lowercased()
            return !NoteFolderFormat.knownKeys.contains(key)
        }
    }
}

/// The folder is worth having in Finder only if the files are named after their notes, so the name
/// is derived from the title — while identity stays in the front matter, which is what keeps a
/// retitle a rename instead of a delete plus a create.
enum NoteFileName {
    static let maximumBaseLength = 60
    static let fallbackBase = "Untitled Note"

    private static let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")

    static func sanitizedBase(for title: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in title.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) || illegal.contains(scalar) {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        let collapsed = String(String(scalars).split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " "))
        var base = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        // A leading `~` is how an interrupted rename names its file; keep titles clear of it.
        while base.hasPrefix(NoteFolderFormat.temporaryPrefix) { base.removeFirst() }
        if base.count > maximumBaseLength { base = String(base.prefix(maximumBaseLength)) }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return base.isEmpty ? fallbackBase : base
    }

    /// Deterministic across Macs: the oldest note claims the bare name, later ones take a suffix, so
    /// two devices resolving the same collision independently pick the same names and never fight.
    static func names(for notes: [SpotterNote], reserved: Set<String> = []) -> [UUID: String] {
        var taken = Set(reserved.map { $0.lowercased() })
        taken.insert(NoteFolderFormat.ledgerFileName.lowercased())
        var result: [UUID: String] = [:]
        let ordered = notes.sorted {
            $0.createdAt == $1.createdAt
                ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
        for note in ordered {
            let base = sanitizedBase(for: note.title)
            var candidate = base + "." + NoteFolderFormat.fileExtension
            var suffix = 2
            while taken.contains(candidate.lowercased()) {
                candidate = "\(base) \(suffix)." + NoteFolderFormat.fileExtension
                suffix += 1
            }
            taken.insert(candidate.lowercased())
            result[note.id] = candidate
        }
        return result
    }
}

/// One file as the scanner found it. `contents == nil` means present but unavailable — an iCloud
/// placeholder, an unreadable file, something not UTF-8 — and Spotter never writes over or removes
/// one of those, because "absent" and "not downloaded yet" must never read as "deleted".
struct NoteFolderFile: Equatable, Sendable {
    let name: String
    let contents: String?
    /// Only ever used to break a tie an external editor caused: a file whose body changed while its
    /// header did not. Never to decide that a file is gone.
    let modifiedAt: Date?

    init(name: String, contents: String?, modifiedAt: Date? = nil) {
        self.name = name
        self.contents = contents
        self.modifiedAt = modifiedAt
    }
}

/// The tombstone ledger. Its own absence is not a reset: deletions are only ever learned, never
/// unlearned, from a file we could not read.
enum NoteFolderLedgerState: Equatable, Sendable {
    case missing
    case readable([NoteTombstone])
    /// Present but not downloaded or not decodable. Deletions stay unknown and the ledger is not
    /// rewritten, so another Mac's tombstones cannot be erased by this one.
    case unavailable
}

struct NoteFolderScan: Equatable, Sendable {
    var files: [NoteFolderFile]
    var ledger: NoteFolderLedgerState

    init(files: [NoteFolderFile], ledger: NoteFolderLedgerState = .missing) {
        self.files = files
        self.ledger = ledger
    }
}

/// Where one Note's file should end up. `currentName == nil` means no file holds it yet, which is a
/// file to write — never a Note to drop.
struct NoteFolderPlacement: Equatable, Sendable {
    let id: UUID
    let currentName: String?
    let desiredName: String
    let contents: String
    let currentContents: String?

    var needsMove: Bool { currentName != nil && currentName != desiredName }
    var needsWrite: Bool { currentContents != contents }
}

/// Why a file is being removed. Both cases provably keep the content: a tombstone is an explicit
/// deletion, and a redundant duplicate is byte-identical to the file that stays.
enum NoteFolderRemoval: Equatable, Sendable {
    case deleted(UUID)
    case redundantDuplicate(UUID)
}

struct NoteFolderPlan: Equatable, Sendable {
    var snapshot: NoteSyncSnapshot
    var placements: [NoteFolderPlacement]
    var removals: [String: NoteFolderRemoval]
    /// The tombstones to write. `nil` means leave the ledger alone — either it already says this,
    /// or it could not be read and overwriting it would erase another Mac's deletions.
    var ledger: [NoteTombstone]?
    /// Files left completely untouched this cycle: placeholders, unreadable files, blank strays.
    var deferred: [String]
    var adopted: [UUID]
    var forked: [UUID]

    var hasFileWork: Bool {
        !removals.isEmpty || ledger != nil || placements.contains { $0.needsMove || $0.needsWrite }
    }
}

/// Which reconcile this is. The two are deliberately not the same policy, and the caller — not
/// anything read from inside this file — decides which one applies.
///
/// `adoption` is the first pass after the user picks a folder, and it runs exactly once per Mac.
/// That pass is the upgrade: someone arriving with Notes already on two Macs can hold one Note
/// diverged under a single id, with `updatedAt` stamps that were never comparable across machines
/// to begin with. Picking a winner there loses a version of the user's writing invisibly and
/// unrecoverably, so both are kept instead — the same fork-to-a-fresh-id treatment two divergent
/// files get.
///
/// `steady` is every pass after that, and it merges by `NoteSyncMerge` alone. A conflict there is a
/// different animal: both sides are live, recent and observable, and forking on every ordinary edit
/// collision would bury the user in duplicates. Same-looking situation, opposite right answer — do
/// not unify the two paths.
enum NoteFolderPass: Equatable, Sendable {
    case adoption
    case steady
}

enum NoteFolderReconciler {
    private struct Adopted {
        var name: String
        var note: SpotterNote
        var extras: [String]
        var raw: String
    }

    /// The whole policy in one pure function: what the store should hold, and what the folder should
    /// look like. Conflicts are resolved by `NoteSyncMerge` — the same newest-edit-wins,
    /// deletion-wins-a-tie rule the CloudKit pipeline used, so there is only ever one merge
    /// policy — except on the adoption pass, which keeps both sides instead. `pass` has no default:
    /// neither value is the safe one to forget, since `.steady` can merge an upgrade away and
    /// `.adoption` would duplicate on every ordinary collision.
    static func plan(
        local: NoteSyncSnapshot, scan: NoteFolderScan, pass: NoteFolderPass,
        newID: () -> UUID = UUID.init, now: () -> Date = Date.init
    ) -> NoteFolderPlan {
        var deferred: [String] = []
        var reserved: Set<String> = []
        var parsed: [UUID: Adopted] = [:]
        var removals: [String: NoteFolderRemoval] = [:]
        var adopted: [UUID] = []
        var forked: [UUID] = []

        for file in scan.files.sorted(by: { $0.name < $1.name }) {
            guard NoteFolderFormat.isNoteFileName(file.name) else {
                reserved.insert(file.name)
                continue
            }
            guard let contents = file.contents else {
                deferred.append(file.name)
                reserved.insert(file.name)
                continue
            }
            switch NoteFolderDocument.parse(contents, newID: newID, now: now) {
            case .ignored:
                deferred.append(file.name)
                reserved.insert(file.name)
            case .adopted(let note):
                adopted.append(note.id)
                parsed[note.id] = Adopted(name: file.name, note: note, extras: [], raw: contents)
            case .note(let note, let extras):
                let note = reconciledWithFile(note, local: local, modifiedAt: file.modifiedAt)
                guard let existing = parsed[note.id] else {
                    parsed[note.id] = Adopted(
                        name: file.name, note: note, extras: extras, raw: contents)
                    continue
                }
                let candidate = Adopted(
                    name: file.name, note: note, extras: extras, raw: contents)
                let keepsExisting = wins(existing.note, existing.name, over: note, file.name)
                let winner = keepsExisting ? existing : candidate
                let loser = keepsExisting ? candidate : existing
                parsed[note.id] = winner
                if loser.note.content == winner.note.content, loser.note.tint == winner.note.tint {
                    // Byte-identical to the file that stays, so removing it cannot lose anything.
                    removals[loser.name] = .redundantDuplicate(note.id)
                } else {
                    // Two different texts under one id: keep both. A stale duplicate is the price
                    // of never dropping a version of the user's writing.
                    let fork = SpotterNote(
                        id: newID(), content: loser.note.content, createdAt: loser.note.createdAt,
                        updatedAt: loser.note.updatedAt,
                        contentUpdatedAt: loser.note.contentUpdatedAt, tint: loser.note.tint)
                    forked.append(fork.id)
                    parsed[fork.id] = Adopted(
                        name: loser.name, note: fork, extras: loser.extras, raw: loser.raw)
                }
            }
        }

        let ledgerTombstones: [NoteTombstone]
        let ledgerReadable: Bool
        switch scan.ledger {
        case .missing:
            ledgerTombstones = []
            ledgerReadable = true
        case .readable(let tombstones):
            ledgerTombstones = tombstones
            ledgerReadable = true
        case .unavailable:
            ledgerTombstones = []
            ledgerReadable = false
        }

        let remote = NoteSyncSnapshot(
            notes: parsed.values.map(\.note), tombstones: ledgerTombstones)
        var merged = NoteSyncMerge.merging(local, with: remote)
        if pass == .adoption {
            let forks = adoptionForks(local: local, parsed: &parsed, merged: merged, newID: newID)
            if !forks.isEmpty {
                forked.append(contentsOf: forks.map(\.id))
                // Fresh identifiers, so this second merge only ever inserts and sorts.
                merged = NoteSyncMerge.merging(
                    merged, with: NoteSyncSnapshot(notes: forks, tombstones: []))
            }
        }
        let mergedIDs = Set(merged.notes.map(\.id))

        for (id, entry) in parsed where !mergedIDs.contains(id) {
            // The only other way a file leaves: an explicit tombstone won its merge.
            removals[entry.name] = .deleted(id)
        }
        for name in removals.keys { reserved.remove(name) }

        let names = NoteFileName.names(for: merged.notes, reserved: reserved)
        var placements: [NoteFolderPlacement] = []
        for note in merged.notes {
            guard let desired = names[note.id] else { continue }
            let entry = parsed[note.id]
            // A blank note that has no file yet stays unwritten: an empty file adds nothing to the
            // folder, and the Notes window sweeps blank notes away when it closes anyway.
            if entry == nil, note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            let extras = entry?.extras ?? []
            placements.append(
                NoteFolderPlacement(
                    id: note.id, currentName: entry?.name, desiredName: desired,
                    contents: NoteFolderDocument.serialize(note, extras: extras),
                    currentContents: entry?.raw))
        }
        placements.sort { $0.desiredName < $1.desiredName }

        let writesLedger = ledgerReadable && merged.tombstones != ledgerTombstones
        return NoteFolderPlan(
            snapshot: merged, placements: placements, removals: removals,
            ledger: writesLedger ? merged.tombstones : nil,
            deferred: deferred, adopted: adopted, forked: forked)
    }

    /// One id, two different texts, one on this Mac and one in the folder — and this is the pass
    /// that runs once, on timestamps that may never have been comparable. The merge already named a
    /// winner; this hands the loser a fresh identifier so neither text is merged away. Only text is
    /// grounds for a fork: a tint that loses is visible and one click to restore, whereas writing
    /// that loses is gone without a trace.
    private static func adoptionForks(
        local: NoteSyncSnapshot, parsed: inout [UUID: Adopted], merged: NoteSyncSnapshot,
        newID: () -> UUID
    ) -> [SpotterNote] {
        var forks: [SpotterNote] = []
        // Sorted, so the same folder hands out the same fresh identifiers in the same order.
        for (id, entry) in parsed.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            // No `merged` note means a tombstone won, and an explicit deletion is a decision rather
            // than a divergence — reviving its text under a new id would undo it.
            guard let mine = local.notesByID[id], let winner = merged.notesByID[id],
                mine.content != entry.note.content
            else { continue }
            let fileWon = winner.content == entry.note.content
            let loser = fileWon ? mine : entry.note
            guard !loser.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            // Already kept somewhere else, so a copy would be noise, not insurance. This is also
            // what makes a retried adoption pass — one whose file work failed last time — stop
            // forking the same text again.
            guard !merged.notes.contains(where: { $0.id != id && $0.content == loser.content })
            else { continue }
            let fork = SpotterNote(
                id: newID(), content: loser.content, createdAt: loser.createdAt,
                updatedAt: loser.updatedAt, contentUpdatedAt: loser.contentUpdatedAt,
                tint: loser.tint)
            forks.append(fork)
            guard !fileWon else { continue }
            // The file lost, so it becomes the fork's file and the winning Note is written out
            // fresh; the same handover the two-divergent-files path performs.
            parsed[fork.id] = Adopted(
                name: entry.name, note: fork, extras: entry.extras, raw: entry.raw)
            parsed[id] = nil
        }
        return forks
    }

    /// An external editor changes a file's body without touching its `updated` header, which leaves
    /// the merge a tie it would break by comparing strings — and losing that tie would rewrite the
    /// user's edit away. The file's own modification date settles it in favour of the newer bytes.
    private static func reconciledWithFile(
        _ note: SpotterNote, local: NoteSyncSnapshot, modifiedAt: Date?
    ) -> SpotterNote {
        guard let mine = local.notesByID[note.id], mine.updatedAt == note.updatedAt,
            mine.content != note.content
        else { return note }
        let stamp = max(modifiedAt ?? note.updatedAt, note.updatedAt).addingTimeInterval(0.001)
        var edited = note
        edited.updatedAt = stamp
        edited.contentUpdatedAt = stamp
        return edited
    }

    /// Two files claiming one id. Newest edit wins; an exact tie falls back to the name, so both
    /// Macs pick the same survivor.
    private static func wins(
        _ lhs: SpotterNote, _ lhsName: String, over rhs: SpotterNote, _ rhsName: String
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhsName <= rhsName
    }
}

/// The on-disk deletion signal. Absence of a file is never a deletion; this ledger is.
struct NoteFolderLedger: Codable, Equatable, Sendable {
    static let version = 1

    var version = NoteFolderLedger.version
    var tombstones: [NoteTombstone]

    init(tombstones: [NoteTombstone]) {
        self.tombstones = tombstones
    }

    init(json data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self = try decoder.decode(NoteFolderLedger.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
