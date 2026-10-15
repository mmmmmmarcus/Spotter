import Foundation
import Darwin

enum ClipboardEmbeddingError: LocalizedError {
    case unavailable, unsupported, failed, timedOut, invalidReply

    var errorDescription: String? {
        switch self {
        case .unavailable: "The local search helper is missing. Reinstall Spotter."
        case .unsupported: "Local semantic search requires Apple silicon."
        case .failed: "The local search model could not process this content."
        case .timedOut: "Local indexing took too long. Try again."
        case .invalidReply: "The local search model returned an invalid embedding."
        }
    }
}

struct ClipboardEmbeddingInput: Sendable {
    let value: String
    let isImage: Bool
    var isQuery = false
}

struct ClipboardEmbeddingClient: Sendable {
    let executable: URL
    let models: URL

    func embed(_ inputs: [ClipboardEmbeddingInput]) async throws -> [[Float]?] {
        guard !inputs.isEmpty else { return [] }
        let job = Task.detached(priority: .utility) {
            var vectors: [[Float]?] = []
            for start in stride(from: 0, to: inputs.count, by: ClipboardSemanticEngine.batchSize) {
                try Task.checkCancellation()
                vectors += try run(Array(inputs[start..<min(inputs.count, start + ClipboardSemanticEngine.batchSize)]))
            }
            return vectors
        }
        return try await withTaskCancellationHandler {
            try await job.value
        } onCancel: { job.cancel() }
    }

    private func run(_ inputs: [ClipboardEmbeddingInput]) throws -> [[Float]?] {
        try Task.checkCancellation()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ClipboardEmbeddingError.unavailable
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("spotter-embedding-\(UUID())")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let inputURL = temporary.appendingPathComponent("input")
        let outputURL = temporary.appendingPathComponent("output")
        var data = Data()
        for (index, input) in inputs.enumerated() {
            let line = try JSONSerialization.data(withJSONObject: [
                "id": index + 1, "op": input.isImage ? "image" : "text", "inputs": [input.value], "budget": 280
            ])
            data.append(line)
            data.append(0x0A)
        }
        data.append(Data("{\"id\":0,\"op\":\"quit\"}\n".utf8))
        try data.write(to: inputURL)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let input = try FileHandle(forReadingFrom: inputURL)
        defer { try? input.close() }
        // The inherited descriptor stays readable, but a crash must not leave copied text in a temp file.
        try FileManager.default.removeItem(at: inputURL)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["worker"] + (inputs.allSatisfy(\.isQuery) ? ["--text-only"] : [])
        process.environment = ["PATH": "/usr/bin:/bin", "DIGUP_MODELS": models.path, "DIGUP_THREADS": "4"]
        process.currentDirectoryURL = temporary
        process.qualityOfService = .utility
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        }
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning {
            try Task.checkCancellation()
            guard Date() < deadline else { throw ClipboardEmbeddingError.timedOut }
            let size = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size < 2_000_000 else { throw ClipboardEmbeddingError.invalidReply }
            Thread.sleep(forTimeInterval: 0.025)
        }
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw ClipboardEmbeddingError.failed }
        let response = try Data(contentsOf: outputURL)
        guard response.count < 2_000_000 else { throw ClipboardEmbeddingError.invalidReply }
        var vectors = [[Float]?](repeating: nil, count: inputs.count)
        var seen = Set<Int>()
        var ready = false
        for line in response.split(separator: 0x0A) {
            guard let reply = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                throw ClipboardEmbeddingError.invalidReply
            }
            if reply["ready"] as? Bool == true {
                ready = (reply["info"] as? [String: Any])?["dim"] as? Int == ClipboardSemanticEngine.dimension
                continue
            }
            guard let id = reply["id"] as? Int, id > 0 else { continue }
            guard id <= inputs.count, seen.insert(id).inserted, reply["ok"] as? Bool == true,
                reply["dim"] as? Int == ClipboardSemanticEngine.dimension,
                let encoded = reply["vectors"] as? String, let bytes = Data(base64Encoded: encoded),
                bytes.count == ClipboardSemanticEngine.dimension * 4 else {
                throw ClipboardEmbeddingError.invalidReply
            }
            if let errors = reply["errors"] as? [Any], errors.contains(where: { !($0 is NSNull) }) { continue }
            let vector = stride(from: 0, to: bytes.count, by: 4).map { offset in
                bytes.withUnsafeBytes { Float(bitPattern: UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))) }
            }
            vectors[id - 1] = ClipboardSemanticEngine.normalized(vector)
        }
        guard ready, seen.count == inputs.count else { throw ClipboardEmbeddingError.invalidReply }
        return vectors
    }
}
