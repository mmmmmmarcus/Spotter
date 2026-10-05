import Foundation

@MainActor
private final class Model: AIToolModel {
    var apiKey = "fixture-key"
    var isReady: Bool { !apiKey.isEmpty }
    var rounds = 0
    var callsPerTurn = 1
    var captured: [AIJSON] = []
    var onTurn: (() -> Void)?
    var onStream: (() -> Void)?
    var streams = 0
    var streamedModel: String?
    var streamedWebSearch = false
    var offeredTools: [AIToolDefinition] = []
    func chat(messages: [(role: String, content: String)], model: String, webSearch: Bool,
        onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws {
        streams += 1
        streamedModel = model
        streamedWebSearch = webSearch
        captured = messages.map { .object(["role": .string($0.role), "content": .string($0.content)]) }
        onStream?()
        onDelta("Plain answer")
    }
    func toolTurn(messages: [AIJSON], tools: [AIToolDefinition], model: String, webSearch: Bool) async throws -> AIToolTurn {
        captured = messages
        offeredTools = tools
        rounds += 1
        onTurn?()
        if rounds == 1 {
            guard tools.count == 2 else { throw AIToolFailure("Pagination lost tools") }
            return AIToolTurn(content: nil, tool_calls: (0..<callsPerTurn).map {
                AIToolCall(id: "call-\($0)", type: "function", function: .init(name: tools[0].name, arguments: "{\"text\":\"fixture response\"}"))
            }, reasoning_details: .array([.object(["type": .string("reasoning.encrypted"), "data": .string("opaque")])]))
        }
        return AIToolTurn(content: "Done", tool_calls: nil, reasoning_details: nil)
    }
}

@main
private struct Tests {
    @MainActor static var count = 0
    @MainActor static func check(_ condition: Bool, _ name: String) {
        guard condition else { fatalError("FAIL: \(name)") }
        count += 1
    }
    @MainActor static func rejects(_ name: String, _ body: () throws -> Void) {
        do { try body(); fatalError("FAIL: \(name)") } catch { count += 1 }
    }
    @MainActor static func rejectsAsync(_ name: String, _ body: () async throws -> Void) async {
        do { try await body(); fatalError("FAIL: \(name)") } catch { count += 1 }
    }
    @MainActor static func main() async throws {
        let fixture = URL(fileURLWithPath: "Tools/Fixtures/ai-mcp-server.py").standardizedFileURL.path
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("spotter-tools-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("calls.jsonl")
        let server = AIMCPServer(command: "/usr/bin/python3", args: [fixture], env: ["AI_TEST_LOG": log.path])
        let config = AIMCPConfiguration(mcpServers: ["fixture": server]).formatted
        check(try AIMCPConfiguration.parse(config).mcpServers["fixture"] == server, "configuration round trip")
        for text in ["{}", "{\"mcpServers\":{\"x\":{}}}", "{\"mcpServers\":{\"x\":{\"command\":\"echo\",\"url\":\"https://example.com\"}}}", "{\"mcpServers\":{\"x\":{\"url\":\"http://example.com\"}}}", "{\"mcpServers\":{\"x\":{\"url\":\"https://u:p@example.com\"}}}"] {
            rejects("invalid configuration") { _ = try AIMCPConfiguration.parse(text) }
        }
        let unsafe = AIMCPConfiguration(mcpServers: ["x": AIMCPServer(url: "https://example.com", headers: ["Authorization": "a\r\nb"])]).formatted
        rejects("header injection") { _ = try AIMCPConfiguration.parse(unsafe) }
        check(try AIMCPConfiguration.parse(AIMCPConfiguration(mcpServers: ["x": AIMCPServer(url: "http://127.0.0.1:8000/mcp")]).formatted).mcpServers.count == 1, "local HTTP")
        let call = AIToolCall(id: "c", type: "function", function: .init(name: "echo", arguments: "{}"))
        check(try call.parsedArguments() == .object([:]), "object arguments")
        rejects("non object arguments") { _ = try AIToolCall(id: "c", type: "function", function: .init(name: "echo", arguments: "[]")).parsedArguments() }
        let result = try AIToolResult(.object(["content": .array([
            .object(["type": .string("text"), "text": .string("Observation")]),
            .object(["type": .string("image"), "mimeType": .string("image/png"), "data": .string("aW1hZ2U=")])])]))
        check(result.messages(for: call).count == 2 && result.images.count == 1, "multimodal tool response")
        check(result.messages(for: call)[0]["tool_call_id"] == .string("c"), "tool call association")
        rejects("invalid base64") { _ = try AIToolResult(.object(["content": .array([.object(["type": .string("image"), "mimeType": .string("image/png"), "data": .string("!!!")])])])) }

        let connection = AIMCPConnection(configuration: server)
        try await connection.connect()
        let catalog = try await connection.request("tools/list", parameters: .object([:]))
        check(catalog["tools"]?.array?.count == 1, "stdio catalog and server ping")
        let response = try await connection.request("tools/call", parameters: .object(["name": .string("echo"), "arguments": .object(["text": .string("stdio")])]))
        check(try AIToolResult(response).text == "stdio", "stdio tool result")
        await rejectsAsync("JSON RPC error") { _ = try await connection.request("unknown", parameters: .object([:])) }
        let hang = Task { try await connection.request("tools/call", parameters: .object(["arguments": .object(["hang": .bool(true)])])) }
        try await Task.sleep(for: .milliseconds(100))
        hang.cancel()
        await rejectsAsync("cancel suspended stdio request") { _ = try await hang.value }
        await connection.close()
        await rejectsAsync("closed connection rejects requests") { _ = try await connection.request("tools/list", parameters: .object([:])) }

        let http = Process()
        let pipe = Pipe()
        http.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        http.arguments = [fixture, "--http"]
        http.standardOutput = pipe
        http.standardError = FileHandle.nullDevice
        try http.run()
        let port = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        defer { http.terminate(); pipe.closeHandles() }
        for path in ["mcp", "sse", "sse-cr"] {
            let client = AIMCPConnection(configuration: AIMCPServer(url: "http://127.0.0.1:\(port)/\(path)"))
            try await client.connect()
            let list = try await client.request("tools/list", parameters: .object([:]))
            check(list["nextCursor"] == .string("page2"), "HTTP \(path) session and result")
            await client.close()
        }
        let redirect = AIMCPConnection(configuration: AIMCPServer(url: "http://127.0.0.1:\(port)/redirect"))
        await rejectsAsync("refuse HTTP redirect") { try await redirect.connect() }
        await redirect.close()

        let suite = "com.spotter.tests.tools.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AIToolStore(defaults: defaults)
        let messages = [(role: "system", content: "Fixture"), (role: "user", content: "Echo this")]
        let session = UUID()
        check(!store.isEnabled, "default off")
        try store.saveConfiguration(config)
        check(!store.isEnabled, "configuration cannot grant consent")
        let model = Model()
        await rejectsAsync("off blocks model and process") { try await store.run(messages: messages, model: "fixture", webSearch: false, sessionID: session, router: model) { _ in } }
        check(model.rounds == 0, "no model call without consent")
        store.setEnabled(true)
        store.onApproval = { [weak store] approval in store?.resolveApproval(approval.id, allowed: true) }
        var text = ""
        try await store.run(messages: messages, model: "fixture", webSearch: false, sessionID: session, router: model) { text += $0 }
        check(text.trimmingCharacters(in: .whitespacesAndNewlines) == "Done", "full tool loop")
        check(model.captured.contains { $0["role"] == .string("tool") }, "tool result reaches model")
        check(model.captured.contains { $0["content"]?.string?.contains("FIXTURE_USAGE_NOTES") == true && $0["role"] == .string("user") }, "server usage notes stay untrusted reference context")
        check(model.captured.contains { $0["reasoning_details"] != nil }, "reasoning preserved")
        check(!store.isRunning && store.approval == nil, "finished run releases connections and approval")
        check(store.activities.count == 3, "activity captured")
        let before = try Data(contentsOf: log)
        store.onApproval = { [weak store] approval in store?.resolveApproval(approval.id, allowed: false) }
        await rejectsAsync("declined tool ends run") { try await store.run(messages: messages, model: "fixture", webSearch: false, sessionID: session, router: Model()) { _ in } }
        check(try Data(contentsOf: log) == before, "declined tool never executed")
        store.onApproval = { [weak store] _ in store?.setEnabled(false) }
        await rejectsAsync("revoke consent at approval") { try await store.run(messages: messages, model: "fixture", webSearch: false, sessionID: session, router: Model()) { _ in } }
        check(try Data(contentsOf: log) == before && !store.isRunning, "revocation prevents execution")
        store.setEnabled(true)
        let revokedModel = Model()
        revokedModel.onTurn = { [weak revokedModel] in revokedModel?.apiKey = "" }
        await rejectsAsync("key revoked across await") { try await store.run(messages: messages, model: "fixture", webSearch: false, sessionID: session, router: revokedModel) { _ in } }
        check(try Data(contentsOf: log) == before, "key revocation prevents execution")
        let parallel = Model()
        parallel.callsPerTurn = 2
        await rejectsAsync("parallel calls rejected") { try await store.run(messages: messages, model: "fixture", webSearch: false, sessionID: session, router: parallel) { _ in } }
        check(try Data(contentsOf: log) == before, "parallel calls execute nothing")
        store.onApproval = { _ in }
        let pending = Task { try await store.run(messages: messages, model: "fixture", webSearch: false, sessionID: session, router: Model()) { _ in } }
        for _ in 0..<200 {
            if store.approval != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(store.approval != nil, "approval waits for explicit answer")
        pending.cancel()
        await rejectsAsync("cancel while awaiting approval") { try await pending.value }
        check(store.approval == nil && !store.isRunning, "approval cancellation clears state")
        try store.saveConfiguration(config)
        check(!store.isEnabled, "saving resets consent")
        check(try AIMCPConfiguration.parse(store.addingCua(to: AIMCPConfiguration.empty)).mcpServers["cua"]?.args == ["mcp"], "Cua MCP preset")
        let missing = AIMCPServer(command: directory.appendingPathComponent("missing-cua-driver").path, args: ["mcp"])
        let ordinary = [(role: "system", content: "Fixture"), (role: "user", content: "What is 2 + 2?")]
        var approvals = 0
        store.onApproval = { [weak store] approval in
            approvals += 1
            store?.resolveApproval(approval.id, allowed: true)
        }
        for configuration in [AIMCPConfiguration(mcpServers: ["cua": missing]), AIMCPConfiguration()] {
            try store.saveConfiguration(configuration.formatted)
            store.setEnabled(true)
            let fallback = Model()
            var answer = ""
            try await store.run(messages: ordinary, model: "chosen-model", webSearch: true,
                sessionID: session, router: fallback) { answer += $0 }
            check(answer == "Plain answer" && fallback.streams == 1 && fallback.rounds == 0,
                "missing driver or empty configuration falls back to ordinary streaming")
            check(fallback.streamedModel == "chosen-model" && fallback.streamedWebSearch,
                "fallback retains chosen model and web search")
            check(fallback.captured.contains { $0["content"]?.string == "What is 2 + 2?" }, "fallback preserves the user question")
            check(fallback.captured.contains { $0["role"] == .string("system") && $0["content"]?.string?.contains("No MCP tools or computer access") == true },
                "computer requests receive an explicit capability limit instead of invented actions")
            check(!fallback.captured.contains { $0["content"]?.string?.contains(directory.path) == true }, "local executable paths stay out of fallback model context")
            check(approvals == 0 && !store.isRunning && store.approval == nil, "ordinary fallback asks for no tool approval and cleans up")
        }
        let broken = AIMCPServer(command: "/usr/bin/python3", args: [fixture], env: ["AI_TEST_BAD_PAGE": "1"])
        for unavailable in [missing, broken] {
            try store.saveConfiguration(AIMCPConfiguration(mcpServers: ["cua": unavailable, "fixture": server]).formatted)
            store.setEnabled(true)
            let healthy = Model()
            var answer = ""
            try await store.run(messages: messages, model: "fixture", webSearch: false, sessionID: session, router: healthy) { answer += $0 }
            check(answer.trimmingCharacters(in: .whitespacesAndNewlines) == "Done" && healthy.streams == 0,
                "one unavailable server does not block the healthy tool loop")
            check(healthy.offeredTools.count == 2 && healthy.offeredTools.allSatisfy { $0.server == "fixture" },
                "failed discovery publishes no partial catalog")
            check(Set(healthy.offeredTools.map(\.name)).count == 2, "discarded catalog cannot duplicate callable names")
        }
        let failingCall = AIMCPServer(command: "/usr/bin/python3", args: [fixture], env: ["AI_TEST_FAIL_CALL": "1"])
        try store.saveConfiguration(AIMCPConfiguration(mcpServers: ["fixture": failingCall]).formatted)
        store.setEnabled(true)
        let execution = Model()
        await rejectsAsync("actual tool execution failure remains an error") {
            try await store.run(messages: messages, model: "fixture", webSearch: false, sessionID: session, router: execution) { _ in }
        }
        check(execution.rounds == 1 && execution.streams == 0, "failed tool execution never restarts as ordinary chat")
        for revocation in ["consent", "key", "cancel"] {
            let ready = directory.appendingPathComponent("initializing-\(revocation)")
            let hanging = AIMCPServer(command: "/usr/bin/python3", args: [fixture], env: ["AI_TEST_HANG_INITIALIZE": ready.path])
            try store.saveConfiguration(AIMCPConfiguration(mcpServers: ["fixture": hanging]).formatted)
            store.setEnabled(true)
            let discovery = Model()
            let request = Task {
                try await store.run(messages: ordinary, model: "fixture", webSearch: false, sessionID: session, router: discovery) { _ in }
            }
            for _ in 0..<200 {
                if FileManager.default.fileExists(atPath: ready.path) { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            check(FileManager.default.fileExists(atPath: ready.path), "fixture reached discovery before revocation")
            switch revocation {
            case "consent": store.setEnabled(false)
            case "key": discovery.apiKey = "replacement-key"; store.stop()
            default: request.cancel()
            }
            await rejectsAsync("discovery respects \(revocation)") { try await request.value }
            check(discovery.streams == 0 && discovery.rounds == 0 && !store.isRunning,
                "discovery revocation never falls back or calls the model")
        }
        for revocation in ["consent", "key", "stop", "cancel"] {
            try store.saveConfiguration(AIMCPConfiguration(mcpServers: ["cua": missing]).formatted)
            store.setEnabled(true)
            let fallback = Model()
            var answer = ""
            fallback.onStream = { [weak store, weak fallback] in
                switch revocation {
                case "consent": store?.setEnabled(false)
                case "key": fallback?.apiKey = "replacement-key"
                case "stop": store?.stop()
                default: withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            let cancelled = Task {
                try await store.run(messages: ordinary, model: "fixture", webSearch: false, sessionID: session, router: fallback) { answer += $0 }
            }
            await rejectsAsync("fallback respects \(revocation)") { try await cancelled.value }
            check(answer.isEmpty && !store.isRunning, "fallback drops late text after \(revocation)")
        }
        print("\(count) AI tools checks passed")
    }
}
