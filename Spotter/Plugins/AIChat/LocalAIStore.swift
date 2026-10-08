import Combine
import Foundation

enum LocalAIModel: String, CaseIterable, Identifiable, Sendable {
    case claude = "local-cli/claude"
    case codex = "local-cli/codex"

    var id: String { rawValue }
    var title: String { self == .claude ? "Claude CLI" : "Codex CLI" }
    var executable: String { self == .claude ? "claude" : "codex" }

    static func resolve(_ id: String) -> Self? { Self(rawValue: id) }
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
    @Published private(set) var isRefreshing = false

    var isAvailable: Bool { !paths.isEmpty }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { Self.discover() }.value
            guard let self else { return }
            paths = result
            isRefreshing = false
        }
    }

    func path(for model: LocalAIModel) -> String? { paths[model] }

    func chat(
        messages: [(role: String, content: String)], modelID: String,
        onDelta: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        guard let model = LocalAIModel.resolve(modelID), let path = paths[model] else {
            throw LocalAIError.unavailable(LocalAIModel.resolve(modelID)?.title ?? modelID)
        }
        let prompt = Self.prompt(messages)
        let reply = try await Self.run(model: model, executable: path, prompt: prompt)
        try Task.checkCancellation()
        onDelta(reply)
    }

    private nonisolated static func prompt(_ messages: [(role: String, content: String)]) -> String {
        messages.map { turn in
            let label = turn.role == "system" ? "System" : turn.role == "assistant" ? "Assistant" : "User"
            return "\(label):\n\(turn.content)"
        }.joined(separator: "\n\n") + "\n\nAssistant:\n"
    }

    private nonisolated static func discover() -> [LocalAIModel: String] {
        var result: [LocalAIModel: String] = [:]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin",
            home + "/.npm-global/bin", home + "/.claude/local"]
        for model in LocalAIModel.allCases {
            if let path = roots.map({ $0 + "/" + model.executable })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) && isUsable($0) }) {
                result[model] = path
                continue
            }
            if let path = loginShellPath(for: model.executable) { result[model] = path }
        }
        return result
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

    private nonisolated static func isUsable(_ path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return false }
        return process.terminationStatus == 0
    }

    private nonisolated static func run(
        model: LocalAIModel, executable: String, prompt: String
    ) async throws -> String {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        let capture = LocalAICapture(limit: 2_097_152)
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.arguments = model == .claude
            ? ["-p", "--output-format", "text", "--tools", ""]
            : ["exec", "--skip-git-repo-check", "--sandbox", "read-only", "-"]
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
                    if finished.terminationStatus != 0 {
                        continuation.resume(throwing: LocalAIError.failed(stderr.isEmpty ? stdout : stderr))
                    } else if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.resume(throwing: LocalAIError.emptyReply)
                    } else {
                        continuation.resume(returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
                do {
                    try process.run()
                    input.fileHandleForWriting.write(Data(prompt.utf8))
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
