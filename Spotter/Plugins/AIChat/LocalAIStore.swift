import Combine
import Foundation

enum LocalAIModel: String, CaseIterable, Identifiable, Sendable {
    case claude = "local-cli/claude"
    case codex = "local-cli/codex"

    var id: String { rawValue }
    var title: String { self == .claude ? "Claude CLI" : "Codex CLI" }
    var executable: String { self == .claude ? "claude" : "codex" }

    static func resolve(_ id: String) -> Self? {
        codexModelID(id) != nil ? .codex : Self(rawValue: id)
    }

    static func codexModelID(_ id: String) -> String? {
        let prefix = codex.rawValue + "/"
        guard id.hasPrefix(prefix) else { return nil }
        let model = String(id.dropFirst(prefix.count))
        return model.isEmpty ? nil : model
    }

    static func label(_ id: String) -> String? {
        if let model = codexModelID(id) { return "Codex CLI · " + model }
        return resolve(id)?.title
    }
}

enum LocalAIError: LocalizedError {
    case unavailable(String)
    case failed(String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .unavailable(let name): "\(name) was not found. Install its CLI and reopen AI Chat Settings."
        case .failed(let detail): detail.isEmpty ? "The local AI CLI failed." : detail
        case .emptyReply: "The local AI CLI returned no reply."
        }
    }
}

@MainActor
final class LocalAIStore: ObservableObject {
    @Published private(set) var paths: [LocalAIModel: String] = [:]
    @Published private(set) var codexModels: [CodexCLIModel] = []
    @Published private(set) var codexCatalogError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var customPaths: [LocalAIModel: String]
    @Published private(set) var pathErrors: [LocalAIModel: String] = [:]
    private let workspace: URL
    private let defaults: UserDefaults
    private let pathsKey = "local-ai.executable-paths"
    private var refreshID = UUID()

    init(defaults: UserDefaults = .standard, workspace: URL? = nil) {
        self.workspace = workspace ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.spotter.app1", isDirectory: true)
            .appendingPathComponent("AIChat/Workspace", isDirectory: true)
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: pathsKey) as? [String: String] ?? [:]
        customPaths = Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in
            guard let model = LocalAIModel(rawValue: key), !value.isEmpty else { return nil }
            return (model, value)
        })
    }

    func setCustomPath(_ path: String?, for model: LocalAIModel) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        customPaths[model] = trimmed.isEmpty ? nil : (trimmed as NSString).expandingTildeInPath
        defaults.set(Dictionary(uniqueKeysWithValues: customPaths.map { ($0.key.rawValue, $0.value) }), forKey: pathsKey)
        paths[model] = nil
        pathErrors[model] = nil
        refresh()
    }

    var isAvailable: Bool { !paths.isEmpty }

    func refresh() {
        let id = UUID()
        refreshID = id
        let custom = customPaths
        isRefreshing = true
        Task { [weak self] in
            let (result, catalog) = await Task.detached(priority: .utility) {
                let result = Self.discover(custom: custom)
                let catalog = result.paths[.codex].map { Self.readCodexModels(executable: $0) } ?? []
                return (result, catalog)
            }.value
            guard let self, refreshID == id else { return }
            paths = result.paths
            codexModels = catalog
            codexCatalogError = catalog.isEmpty ? "Model list unavailable. Update Codex CLI or use its default model." : nil
            pathErrors = result.errors
            isRefreshing = false
        }
    }

    func path(for model: LocalAIModel) -> String? { paths[model] }

    func chat(
        messages: [(role: String, content: String)], modelID: String, webSearch: Bool = false, images: [Data] = [],
        onDelta: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        guard let model = LocalAIModel.resolve(modelID), let path = paths[model] else {
            throw LocalAIError.unavailable(LocalAIModel.resolve(modelID)?.title ?? modelID)
        }
        let prompt = Self.prompt(messages)
        let reply = try await Self.run(model: model, executable: path, prompt: prompt, workspace: workspace, codexModel: LocalAIModel.codexModelID(modelID), webSearch: webSearch, images: images)
        try Task.checkCancellation()
        onDelta(reply)
    }

    private nonisolated static func prompt(_ messages: [(role: String, content: String)]) -> String {
        messages.map { turn in
            let label = turn.role == "system" ? "System" : turn.role == "assistant" ? "Assistant" : "User"
            return "\(label):\n\(turn.content)"
        }.joined(separator: "\n\n") + "\n\nAssistant:\n"
    }

    private nonisolated static func discover(custom: [LocalAIModel: String]) -> (paths: [LocalAIModel: String], errors: [LocalAIModel: String]) {
        var errors: [LocalAIModel: String] = [:]
        var result: [LocalAIModel: String] = [:]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin",
            home + "/.npm-global/bin", home + "/.claude/local"]
        for model in LocalAIModel.allCases {
            if let path = custom[model] {
                var directory: ObjCBool = false
                if !path.hasPrefix("/") || !FileManager.default.fileExists(atPath: path, isDirectory: &directory) || directory.boolValue {
                    errors[model] = "Choose an executable file using an absolute path."
                } else if !FileManager.default.isExecutableFile(atPath: path) {
                    errors[model] = "This file is not executable."
                } else if !isUsable(path) {
                    errors[model] = "Could not run --version. Check the CLI and its dependencies."
                } else {
                    result[model] = path
                }
                continue
            }
            if let path = roots.map({ $0 + "/" + model.executable })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) && isUsable($0) }) {
                result[model] = path
                continue
            }
            if let path = loginShellPath(for: model.executable) { result[model] = path }
        }
        return (result, errors)
    }

    private nonisolated static func loginShellPath(for executable: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ilc", "command -v " + executable]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0,
            let value = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            value.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: value), isUsable(value) else { return nil }
        return value
    }

    private nonisolated static func readCodexModels(executable: String) -> [CodexCLIModel] {
        let process = Process()
        let output = Pipe()
        let capture = LocalAICapture(limit: 8_388_608)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["debug", "models", "--bundled"]
        process.environment = environment(for: executable)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { capture.appendOutput($0.availableData) }
        defer { output.fileHandleForReading.readabilityHandler = nil }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return [] }
        guard finished.wait(timeout: .now() + 5) == .success else {
            process.terminate()
            return []
        }
        output.fileHandleForReading.readabilityHandler = nil
        capture.appendOutput(output.fileHandleForReading.readDataToEndOfFile())
        guard process.terminationStatus == 0 else { return [] }
        return CodexCLIModel.decode(capture.strings().0)
    }

    private nonisolated static func isUsable(_ path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.environment = environment(for: path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return false }
        guard finished.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }

    private nonisolated static func environment(for path: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // npm and nvm launchers need sibling executables even when Spotter started from Finder.
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        environment["PATH"] = ([parent, "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        return environment
    }

    private nonisolated static func run(
        model: LocalAIModel, executable: String, prompt: String, workspace: URL, codexModel: String?, webSearch: Bool, images: [Data]
    ) async throws -> String {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        let capture = LocalAICapture(limit: 2_097_152)
        process.executableURL = URL(fileURLWithPath: executable)
        process.environment = environment(for: executable)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        process.currentDirectoryURL = workspace
        process.arguments = model == .claude
            ? ["-p", "--output-format", "text", "--tools", ""]
            : ["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only", "-"]
        if model == .codex, let codexModel { process.arguments?.insert(contentsOf: ["--model", codexModel], at: 1) }
        var inputData = Data(prompt.utf8)
        let imageDirectory = workspace.appendingPathComponent("attachments-" + UUID().uuidString, isDirectory: true)
        defer { if !images.isEmpty { try? FileManager.default.removeItem(at: imageDirectory) } }
        if model == .codex {
            process.arguments?.insert(contentsOf: ["-c", "web_search=\"\(webSearch ? "live" : "disabled")\""], at: 1)
            if !images.isEmpty {
                try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                for (index, data) in images.enumerated() {
                    let url = imageDirectory.appendingPathComponent("image-\(index).png")
                    try data.write(to: url, options: .atomic)
                    process.arguments?.insert(contentsOf: ["--image", url.path], at: 1)
                }
            }
        } else {
            if webSearch { process.arguments = ["-p", "--output-format", "text", "--tools", "WebSearch", "--allowedTools", "WebSearch"] }
            if !images.isEmpty {
                process.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--tools", webSearch ? "WebSearch" : ""]
                if webSearch { process.arguments?.append(contentsOf: ["--allowedTools", "WebSearch"]) }
                let content: [[String: Any]] = [["type": "text", "text": prompt]] + images.map {
                    ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": $0.base64EncodedString()]]
                }
                inputData = try JSONSerialization.data(withJSONObject: ["type": "user", "message": ["role": "user", "content": content]])
                inputData.append(0x0A)
            }
        }
        let requestData = inputData
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { handle in capture.appendOutput(handle.availableData) }
        errors.fileHandleForReading.readabilityHandler = { handle in capture.appendError(handle.availableData) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    output.fileHandleForReading.readabilityHandler = nil
                    errors.fileHandleForReading.readabilityHandler = nil
                    capture.appendOutput(output.fileHandleForReading.readDataToEndOfFile())
                    capture.appendError(errors.fileHandleForReading.readDataToEndOfFile())
                    let (stdout, stderr) = capture.strings()
                    do {
                        continuation.resume(returning: try LocalAIResponse.reply(
                            model: model, status: finished.terminationStatus, stdout: stdout, stderr: stderr, structured: model == .claude && !images.isEmpty))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                do {
                    try process.run()
                    input.fileHandleForWriting.write(requestData)
                    try? input.fileHandleForWriting.close()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

private final class LocalAICapture: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var output = Data()
    private var errors = Data()

    init(limit: Int) { self.limit = limit }

    func appendOutput(_ data: Data) { append(data, to: &output) }
    func appendError(_ data: Data) { append(data, to: &errors) }

    func strings() -> (String, String) {
        lock.lock(); defer { lock.unlock() }
        return (String(decoding: output, as: UTF8.self), String(decoding: errors, as: UTF8.self))
    }

    private func append(_ data: Data, to target: inout Data) {
        guard !data.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        guard target.count < limit else { return }
        target.append(data.prefix(limit - target.count))
    }
}


enum LocalAIResponse {
    static func reply(model: LocalAIModel, status: Int32, stdout: String, stderr: String, structured: Bool = false) throws -> String {
        guard model == .codex else {
            guard status == 0 else { throw LocalAIError.failed(diagnostic(stderr, model: model, status: status)) }
            for line in stdout.split(separator: "\n").reversed() {
                if let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                    event["type"] as? String == "result" {
                    guard event["is_error"] as? Bool != true else { throw LocalAIError.failed("Claude could not complete the attachment request.") }
                    guard let result = event["result"] as? String, !result.isEmpty else { throw LocalAIError.emptyReply }
                    return result
                }
            }
            guard !structured else { throw LocalAIError.emptyReply }
            let text = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw LocalAIError.emptyReply }
            return text
        }
        var answer: String?
        var failure: String?
        var completed = false
        for line in stdout.split(separator: "\n") {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let type = event["type"] as? String else { continue }
            if type == "item.completed", let item = event["item"] as? [String: Any],
                item["type"] as? String == "agent_message", item["phase"] as? String != "commentary" {
                answer = item["text"] as? String
            } else if type == "turn.completed" {
                completed = true
            } else if type == "turn.failed" {
                failure = (event["error"] as? [String: Any])?["message"] as? String ?? "Codex could not finish the reply."
            } else if type == "error", let message = event["message"] as? String {
                failure = message
            }
        }
        guard status == 0, completed else {
            let detail = failure.map { String($0.prefix(1200)) } ?? diagnostic(stderr, model: model, status: status)
            throw LocalAIError.failed(detail)
        }
        guard let text = answer?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw LocalAIError.emptyReply
        }
        return text
    }

    private static func diagnostic(_ stderr: String, model: LocalAIModel, status: Int32) -> String {
        if stderr.contains("missing field `base_instructions`") {
            return "Codex could not load its model cache (missing base_instructions). Update the standalone Codex CLI and retry."
        }
        if stderr.contains("timeout waiting for child process to exit") {
            return "Codex timed out while refreshing its models. Check that the selected CLI works in Terminal, then retry."
        }
        // CLI stderr can echo the complete prompt; never display the whole process transcript.
        let lines = stderr.split(separator: "\n").map(String.init)
        if let line = lines.first(where: { $0.hasPrefix("Error:") || $0.hasPrefix("error:") }) {
            return String(line.prefix(1200))
        }
        return "\(model.title) could not complete the request (exit \(status)). Check the CLI's login and configuration in Terminal."
    }
}

struct CodexCLIModel: Identifiable, Equatable, Sendable {
    let slug: String
    let title: String
    var id: String { LocalAIModel.codex.rawValue + "/" + slug }

    static func decode(_ json: String) -> [Self] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            let models = root["models"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return models.compactMap { model in
            guard let slug = model["slug"] as? String, !slug.isEmpty,
                model["visibility"] as? String != "hide", seen.insert(slug).inserted else { return nil }
            return Self(slug: slug, title: model["display_name"] as? String ?? slug)
        }
    }
}
