import Foundation
import Darwin

private final class AIMCPRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private actor AIMCPWriter {
    let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
    func write(_ data: Data) throws { try handle.write(contentsOf: data) }
}

actor AIMCPConnection {
    private let configuration: AIMCPServer
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var reader: Task<Void, Never>?
    private var writer: AIMCPWriter?
    private var timers: [AIJSON: Task<Void, Never>] = [:]
    private var pending: [AIJSON: CheckedContinuation<AIJSON, Error>] = [:]
    private var sequence = 0
    private var sessionID: String?
    private var protocolVersion = "2025-06-18"
    private var closed = false
    private let session: URLSession

    init(configuration: AIMCPServer) {
        self.configuration = configuration
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config, delegate: AIMCPRedirectPolicy(), delegateQueue: nil)
    }

    @discardableResult
    func connect() async throws -> String? {
        try Task.checkCancellation()
        if configuration.command != nil { try launch() }
        let result = try await request("initialize", parameters: .object([
            "protocolVersion": .string(protocolVersion), "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("Spotter"), "version": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")])]))
        guard let version = result["protocolVersion"]?.string,
            ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"].contains(version),
            result["capabilities"]?["tools"] != nil else {
            throw AIToolFailure("This MCP server did not negotiate a supported tools capability.")
        }
        protocolVersion = version
        try await notify("notifications/initialized", parameters: .object([:]))
        return result["instructions"]?.string.map { String($0.prefix(12_000)) }
    }

    func request(_ method: String, parameters: AIJSON) async throws -> AIJSON {
        try Task.checkCancellation()
        guard !closed else { throw AIToolFailure("MCP connection is closed.") }
        sequence += 1
        let id = AIJSON.number(Double(sequence))
        let message = AIJSON.object(["jsonrpc": .string("2.0"), "id": id,
            "method": .string(method), "params": parameters])
        return try await withTaskCancellationHandler {
            if configuration.url != nil { return try await http(message, expectedID: id) }
            return try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                Task {
                    do { try await write(message) }
                    catch { complete(id, outcome: .failure(error)) }
                }
                timers[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(method == "tools/call" ? 120 : 30)) }
                    catch { return }
                    await self?.expire(id)
                }
            }
        } onCancel: {
            Task { await self.close() }
        }
    }

    private func notify(_ method: String, parameters: AIJSON) async throws {
        let message = AIJSON.object(["jsonrpc": .string("2.0"), "method": .string(method), "params": parameters])
        if configuration.url != nil { _ = try await http(message, expectedID: nil) }
        else { try await write(message) }
    }

    private func launch() throws {
        guard process == nil, !closed, let command = configuration.command else { throw AIToolFailure("MCP process is unavailable.") }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        var environment = ["HOME": home, "PATH": path, "TMPDIR": NSTemporaryDirectory(), "LANG": "en_US.UTF-8"]
        environment.merge(configuration.env ?? [:]) { _, new in new }
        let expanded = (command as NSString).expandingTildeInPath
        let candidates = expanded.hasPrefix("/") ? [expanded] : (environment["PATH"] ?? path).split(separator: ":").map { "\($0)/\(expanded)" }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AIToolFailure("MCP executable not found: \(command). Install it or configure its absolute path.")
        }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = configuration.args ?? []
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: home)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(64))
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { continuation.finish(); return }
            if case .dropped = continuation.yield(data) { continuation.finish(throwing: AIToolFailure("MCP output exceeded the read buffer.")) }
        }
        do { try process.run() }
        catch {
            output.fileHandleForReading.readabilityHandler = nil
            input.closeHandles()
            output.closeHandles()
            continuation.finish()
            throw error
        }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        self.process = process
        self.input = input
        writer = AIMCPWriter(input.fileHandleForWriting)
        self.output = output
        reader = Task { [weak self] in
            var buffer = Data()
            do {
                for try await data in stream {
                    buffer.append(data)
                    guard buffer.count <= 24_000_000 else { throw AIToolFailure("MCP response is too large.") }
                    while let end = buffer.firstIndex(of: 10) {
                        let line = buffer.prefix(upTo: end)
                        if !line.isEmpty { try await self?.receive(JSONDecoder().decode(AIJSON.self, from: line)) }
                        buffer.removeSubrange(...end)
                    }
                }
                await self?.close(failure: AIToolFailure("MCP server disconnected."))
            } catch { await self?.close(failure: error) }
        }
    }

    private func write(_ message: AIJSON) async throws {
        guard !closed, let writer else { throw AIToolFailure("MCP input is closed.") }
        var data = try message.data()
        data.append(10)
        try await writer.write(data)
    }

    private func receive(_ message: AIJSON) async throws {
        guard message["jsonrpc"] == .string("2.0") else { throw AIToolFailure("Invalid MCP response.") }
        if let method = message["method"]?.string, let id = message["id"] {
            let reply: AIJSON = method == "ping"
                ? .object(["jsonrpc": .string("2.0"), "id": id, "result": .object([:])])
                : .object(["jsonrpc": .string("2.0"), "id": id, "error": .object([
                    "code": .number(-32601), "message": .string("Client capability not supported")])])
            try await write(reply)
        } else if let id = message["id"] {
            do { complete(id, outcome: .success(try Self.result(message))) }
            catch { complete(id, outcome: .failure(error)) }
        }
    }

    private static func result(_ message: AIJSON) throws -> AIJSON {
        if let error = message["error"] {
            throw AIToolFailure("MCP: " + String((error["message"]?.string ?? "Request failed.").prefix(1000)))
        }
        guard let result = message["result"] else { throw AIToolFailure("MCP response has no result.") }
        return result
    }

    private func complete(_ id: AIJSON, outcome: Result<AIJSON, Error>) {
        timers.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: outcome)
    }
    private func expire(_ id: AIJSON) {
        guard pending[id] != nil else { return }
        close(failure: AIToolFailure("MCP request timed out; the connection was closed."))
    }

    private func http(_ message: AIJSON, expectedID: AIJSON?) async throws -> AIJSON {
        guard !closed, let address = configuration.url, let url = URL(string: address) else { throw AIToolFailure("MCP URL is unavailable.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (name, value) in configuration.headers ?? [:] { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        request.httpBody = try message.data()
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIToolFailure("MCP HTTP request failed (\((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        if let value = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
            guard !value.isEmpty, value.utf8.count <= 1024, value.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
                throw AIToolFailure("Invalid MCP session identifier.")
            }
            sessionID = value
        }
        if expectedID == nil { return .object([:]) }
        let isSSE = http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true
        var data = Data()
        var event: [String] = []
        var total = 0
        var previousWasCR = false
        for try await byte in bytes {
            try Task.checkCancellation()
            total += 1
            guard !closed, total <= 24_000_000 else { throw AIToolFailure("MCP response was cancelled or is too large.") }
            if isSSE && byte == 10 && previousWasCR { previousWasCR = false; continue }
            previousWasCR = isSSE && byte == 13
            if isSSE && (byte == 10 || byte == 13) {
                guard let rawLine = String(data: data, encoding: .utf8) else { throw AIToolFailure("Invalid MCP event.") }
                data.removeAll(keepingCapacity: true)
                let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
                if line.isEmpty, !event.isEmpty {
                    let envelope = try JSONDecoder().decode(AIJSON.self, from: Data(event.joined(separator: "\n").utf8))
                    event.removeAll(keepingCapacity: true)
                    guard envelope["jsonrpc"] == .string("2.0") else { throw AIToolFailure("Invalid MCP event.") }
                    if envelope["id"] == expectedID, envelope["method"] == nil { return try Self.result(envelope) }
                    if let id = envelope["id"], let method = envelope["method"]?.string {
                        let reply: AIJSON = .object(["jsonrpc": .string("2.0"), "id": id,
                            method == "ping" ? "result" : "error": method == "ping" ? .object([:]) : .object([
                                "code": .number(-32601), "message": .string("Client capability not supported")])])
                        _ = try await self.http(reply, expectedID: nil)
                    }
                } else if line.hasPrefix("data:") {
                    let field = String(line.dropFirst(5))
                    event.append(field.hasPrefix(" ") ? String(field.dropFirst()) : field)
                }
            } else { data.append(byte) }
        }
        guard !isSSE, let envelope = try? JSONDecoder().decode(AIJSON.self, from: data),
            envelope["jsonrpc"] == .string("2.0"), envelope["id"] == expectedID else { throw AIToolFailure("Incomplete MCP response.") }
        return try Self.result(envelope)
    }

    func close(failure: Error = CancellationError()) {
        guard !closed else { return }
        closed = true
        if let process {
            Task.detached {
                try? await Task.sleep(for: .milliseconds(200))
                if process.isRunning { process.terminate() }
                try? await Task.sleep(for: .seconds(1))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        reader?.cancel()
        reader = nil
        output?.fileHandleForReading.readabilityHandler = nil
        input?.closeHandles()
        output?.closeHandles()
        input = nil
        output = nil
        for continuation in pending.values { continuation.resume(throwing: failure) }
        pending.removeAll()
        for timer in timers.values { timer.cancel() }
        timers.removeAll()
        writer = nil
        session.invalidateAndCancel()
        process = nil
    }
}
