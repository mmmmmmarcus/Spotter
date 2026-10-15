import Foundation
import CryptoKit

actor ClipboardSemanticIndex {
    private let directory: URL
    private var entries: [UUID: ClipboardSemanticEntry] = [:]

    init(directory: URL) { self.directory = directory }

    func reconcile(_ fingerprints: [UUID: String]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "plist" {
            try Task.checkCancellation()
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            guard let fingerprint = fingerprints[id] else {
                try FileManager.default.removeItem(at: file)
                entries[id] = nil
                continue
            }
            if entries[id]?.fingerprint == fingerprint { continue }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let snapshot = size > 0 && size <= 524_288
                ? try? PropertyListDecoder().decode(ClipboardSemanticSnapshot.self, from: Data(contentsOf: file)) : nil
            let entry = snapshot?.compatibleEntries.first
            if let entry, entry.id == id, entry.fingerprint == fingerprint {
                entries[id] = entry
            } else {
                entries[id] = nil
                try FileManager.default.removeItem(at: file)
            }
        }
        entries = entries.filter { fingerprints[$0.key] == $0.value.fingerprint }
    }

    func indexed() -> [UUID: String] { entries.mapValues(\.fingerprint) }

    func save(_ entry: ClipboardSemanticEntry) throws {
        try Task.checkCancellation()
        guard !entry.vectors.isEmpty, entry.vectors.count <= 32,
            entry.vectors.allSatisfy({ ClipboardSemanticEngine.normalized($0) != nil }) else {
            throw ClipboardEmbeddingError.invalidReply
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(ClipboardSemanticSnapshot(model: ClipboardSemanticEngine.modelID, entries: [entry]))
        try data.write(to: directory.appendingPathComponent(entry.id.uuidString + ".plist"), options: .atomic)
        entries[entry.id] = entry
    }

    func remove(_ id: UUID) {
        entries[id] = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString + ".plist"))
    }

    func clear() throws {
        entries = [:]
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func search(_ vector: [Float]) -> [UUID] {
        ClipboardSemanticEngine.ranked(query: vector, entries: Array(entries.values))
    }

    static func fingerprint(text: String?, imagePath: String?) -> String? {
        let content: String
        if let text {
            content = ClipboardSemanticEngine.documents(text).joined(separator: "\n")
        } else if let imagePath,
            let attributes = try? FileManager.default.attributesOfItem(atPath: imagePath),
            attributes[.type] as? FileAttributeType == .typeRegular,
            let size = attributes[.size] as? NSNumber,
            let modified = attributes[.modificationDate] as? Date {
            content = "\(imagePath)|\(size)|\(modified.timeIntervalSince1970)"
        } else { return nil }
        return SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
