import Foundation
import CryptoKit

enum ClipboardSemanticModels {
    struct File: Sendable {
        let name: String
        let bytes: Int64
        let sha256: String
        var url: URL {
            URL(string: "https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/bfcd298762cc34d0357ece5ebdd31791a3a374d8/\(name)")!
        }
    }

    // DigUp's pinned Q8 weights; floating-point weights overflow in this runtime.
    static let files = [
        File(name: "embeddinggemma-2-Q8_0.gguf", bytes: 309_855_456,
            sha256: "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135"),
        File(name: "mmproj-embeddinggemma-2-Q8_0.gguf", bytes: 554_821_024,
            sha256: "c4a8a52691ecef40618438928bdf9e68379b854e24166f292592353db0aab64f")
    ]

    static func valid(_ url: URL, file: File) throws -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            (attributes[.size] as? NSNumber)?.int64Value == file.bytes else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 4 << 20), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == file.sha256
    }

    static func validate(_ url: URL, file: File) async throws -> Bool {
        let job = Task.detached(priority: .utility) { try valid(url, file: file) }
        return try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
    }
}
