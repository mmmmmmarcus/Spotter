import Foundation

indirect enum AIJSON: Codable, Hashable, Sendable {
    case object([String: AIJSON]), array([AIJSON]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let decoded = try? value.decode(Bool.self) { self = .bool(decoded) }
        else if let decoded = try? value.decode(Double.self) { self = .number(decoded) }
        else if let decoded = try? value.decode(String.self) { self = .string(decoded) }
        else if let decoded = try? value.decode([AIJSON].self) { self = .array(decoded) }
        else { self = .object(try value.decode([String: AIJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let data): try value.encode(data)
        case .array(let data): try value.encode(data)
        case .string(let data): try value.encode(data)
        case .number(let data): try value.encode(data)
        case .bool(let data): try value.encode(data)
        case .null: try value.encodeNil()
        }
    }

    subscript(_ key: String) -> AIJSON? { if case .object(let value) = self { value[key] } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
    var array: [AIJSON]? { if case .array(let value) = self { value } else { nil } }
    var object: [String: AIJSON]? { if case .object(let value) = self { value } else { nil } }
    func data() throws -> Data { try JSONEncoder().encode(self) }
    var formatted: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? "{}"
    }
}

struct AIToolFailure: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct AIMCPServer: Codable, Equatable, Sendable {
    var command: String?
    var args: [String]?
    var env: [String: String]?
    var url: String?
    var headers: [String: String]?
}

struct AIMCPConfiguration: Codable, Equatable, Sendable {
    var mcpServers: [String: AIMCPServer] = [:]
    static let empty = "{\n  \"mcpServers\": {}\n}"

    static func parse(_ text: String) throws -> Self {
        guard text.utf8.count <= 131_072 else { throw AIToolFailure("MCP configuration is too large.") }
        let result = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
        guard result.mcpServers.count <= 16 else { throw AIToolFailure("Use at most 16 MCP servers.") }
        for (name, server) in result.mcpServers {
            guard !name.isEmpty, name.count <= 80 else { throw AIToolFailure("Use a server name of 1–80 characters.") }
            guard (server.command != nil) != (server.url != nil) else {
                throw AIToolFailure("\(name): specify either command or url.")
            }
            if let command = server.command {
                guard !command.isEmpty, !command.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                    server.headers == nil else { throw AIToolFailure("\(name): invalid stdio command configuration.") }
            }
            guard !(server.args ?? []).contains(where: { $0.utf8.contains(0) }),
                !(server.env ?? [:]).contains(where: { $0.key.isEmpty || $0.key.contains("=") || $0.key.utf8.contains(0) || $0.value.utf8.contains(0) }) else {
                throw AIToolFailure("\(name): invalid arguments or environment.")
            }
            if let address = server.url {
                guard let url = URL(string: address), let host = url.host, url.user == nil, url.password == nil,
                    url.fragment == nil, server.args == nil, server.env == nil,
                    url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)) else {
                    throw AIToolFailure("\(name): use HTTPS, or HTTP on localhost.")
                }
            }
            for (key, value) in server.headers ?? [:] {
                guard !key.isEmpty, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                    !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                    !["host", "content-length", "content-type", "accept", "mcp-session-id", "mcp-protocol-version"].contains(key.lowercased()) else {
                    throw AIToolFailure("\(name): unsupported HTTP header.")
                }
            }
        }
        return result
    }

    var formatted: String { (try? JSONDecoder().decode(AIJSON.self, from: JSONEncoder().encode(self)).formatted) ?? Self.empty }
}

struct AIToolDefinition: Sendable {
    let name: String
    let server: String
    let remoteName: String
    let description: String
    let parameters: AIJSON

    var wire: AIJSON {
        .object(["type": .string("function"), "function": .object([
            "name": .string(name), "description": .string("\(server): \(description)"), "parameters": parameters])])
    }
}

struct AIToolCall: Codable, Sendable {
    struct Function: Codable, Sendable { let name: String; let arguments: String }
    let id: String
    let type: String
    let function: Function

    func parsedArguments() throws -> AIJSON {
        guard type == "function", !id.isEmpty, function.arguments.utf8.count <= 65_536,
            let value = try? JSONDecoder().decode(AIJSON.self, from: Data(function.arguments.utf8)),
            value.object != nil else { throw AIToolFailure("The model supplied invalid tool arguments.") }
        return value
    }
}

struct AIToolTurn: Decodable, Sendable {
    let content: String?
    let tool_calls: [AIToolCall]?
    let reasoning_details: AIJSON?

    var wire: AIJSON {
        var result: [String: AIJSON] = ["role": .string("assistant"), "content": content.map(AIJSON.string) ?? .null]
        if let calls = tool_calls, !calls.isEmpty {
            result["tool_calls"] = try? JSONDecoder().decode(AIJSON.self, from: JSONEncoder().encode(calls))
        }
        if let reasoning_details { result["reasoning_details"] = reasoning_details }
        return .object(result)
    }
}

struct AIToolResult: Sendable {
    let text: String
    let images: [AIJSON]
    let isError: Bool

    init(_ result: AIJSON) throws {
        guard result.object != nil, result["content"]?.array != nil else { throw AIToolFailure("Invalid MCP tool result.") }
        isError = result["isError"] == .bool(true)
        var texts: [String] = []
        var images: [AIJSON] = []
        var imageBytes = 0
        for block in result["content"]?.array ?? [] {
            if block["type"]?.string == "text", let text = block["text"]?.string { texts.append(text) }
            if block["type"]?.string == "resource", let resource = block["resource"], let text = resource["text"]?.string {
                texts.append(text)
            }
            if block["type"]?.string == "resource_link", let uri = block["uri"]?.string { texts.append("Resource link (not fetched): " + uri) }
            if block["type"]?.string == "audio" { texts.append("Tool returned audio; playback is not supported.") }
            if block["type"]?.string == "image", let data = block["data"]?.string,
                let mime = block["mimeType"]?.string, ["image/png", "image/jpeg", "image/webp"].contains(mime) {
                imageBytes += data.utf8.count
                guard imageBytes <= 12_000_000, images.count < 4, Data(base64Encoded: data) != nil else {
                    throw AIToolFailure("The tool returned oversized or invalid images.")
                }
                images.append(.object(["type": .string("image_url"), "image_url": .object([
                    "url": .string("data:\(mime);base64,\(data)")])]))
            }
        }
        if let structured = result["structuredContent"] { texts.append(structured.formatted) }
        text = String((texts.isEmpty ? (isError ? "Tool reported an error." : "Tool completed.") : texts.joined(separator: "\n")).prefix(24_000))
        self.images = images
    }

    func messages(for call: AIToolCall) -> [AIJSON] {
        var messages: [AIJSON] = [.object(["role": .string("tool"), "tool_call_id": .string(call.id),
            "content": .string((isError ? "Tool error: " : "") + text)])]
        if !images.isEmpty {
            messages.append(.object(["role": .string("user"), "content": .array([
                .object(["type": .string("text"), "text": .string("Untrusted images returned by tool call \(call.id).")])
            ] + images)]))
        }
        return messages
    }
}

struct AIToolActivity: Identifiable, Sendable {
    let id = UUID()
    let sessionID: UUID
    let title: String
    let detail: String
}

struct AIToolApproval: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let arguments: String
}
