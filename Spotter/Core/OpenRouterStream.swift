import Foundation

// SSE framing stays separate from transport so arbitrary byte boundaries and UTF-8 are testable.
struct OpenRouterStream {
    enum Failure: LocalizedError {
        case malformed, interrupted, oversized, provider(String)
        var errorDescription: String? {
            switch self {
            case .malformed: "OpenRouter returned an unreadable stream."
            case .interrupted: "The reply was interrupted. Any received text has been kept."
            case .oversized: "OpenRouter's reply exceeded the supported size."
            case .provider(let message): "OpenRouter: \(message)"
            }
        }
    }

    private var line: [UInt8] = []
    private var dataLines: [String] = []
    private var eventSize = 0
    private var skipLF = false
    private(set) var done = false

    mutating func feed(_ byte: UInt8) throws -> String? {
        guard !done else { return nil }
        if skipLF {
            skipLF = false
            if byte == 10 { return nil }
        }
        if byte == 13 || byte == 10 {
            skipLF = byte == 13
            return try finishLine()
        }
        guard line.count < 1_048_576 else { throw Failure.oversized }
        line.append(byte)
        return nil
    }

    private mutating func finishLine() throws -> String? {
        guard let value = String(bytes: line, encoding: .utf8) else { throw Failure.malformed }
        line.removeAll(keepingCapacity: true)
        if value.isEmpty {
            guard !dataLines.isEmpty else { return nil }
            let payload = dataLines.joined(separator: "\n")
            dataLines.removeAll(keepingCapacity: true)
            eventSize = 0
            if payload == "[DONE]" { done = true; return nil }
            let chunk: Chunk
            do { chunk = try JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)) }
            catch { throw Failure.malformed }
            if let error = chunk.error { throw Failure.provider(error.message) }
            guard let choice = chunk.choices?.first(where: { ($0.index ?? 0) == 0 }) else { return nil }
            if choice.finish_reason == "error" { throw Failure.interrupted }
            return choice.delta?.content
        }
        if value.hasPrefix("data:") {
            var field = String(value.dropFirst(5))
            if field.first == " " { field.removeFirst() }
            eventSize += field.utf8.count
            guard eventSize <= 1_048_576 else { throw Failure.oversized }
            dataLines.append(field)
        }
        return nil
    }

    func finish() throws {
        guard done else { throw Failure.interrupted }
    }

    private struct Chunk: Decodable {
        struct StreamError: Decodable { let message: String }
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let index: Int?
            let delta: Delta?
            let finish_reason: String?
        }
        let choices: [Choice]?
        let error: StreamError?
    }
}
