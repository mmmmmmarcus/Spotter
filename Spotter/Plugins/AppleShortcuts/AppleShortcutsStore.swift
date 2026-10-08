import Combine
import Foundation

@MainActor
final class AppleShortcutsStore: ObservableObject {
    @Published private(set) var shortcuts: [AppleShortcut] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    var onChange: (() -> Void)?
    private var refreshTask: Task<Void, Never>?

    func refresh() {
        guard refreshTask == nil else { return }
        isLoading = true
        errorMessage = nil
        refreshTask = Task { [weak self] in
            let result = await AppleShortcutsProcess.list()
            guard let self else { return }
            refreshTask = nil
            isLoading = false
            switch result {
            case .success(let shortcuts):
                if self.shortcuts != shortcuts {
                    self.shortcuts = shortcuts
                    onChange?()
                }
            case .failure(let failure):
                errorMessage = failure.message
            }
        }
    }

    func run(id: UUID) async -> String? {
        await AppleShortcutsProcess.run(id: id)
    }
}

enum AppleShortcutsProcess {
    struct Failure: Error, Sendable {
        let message: String
    }

    private static let queue = DispatchQueue(label: "com.spotter.apple-shortcuts", qos: .userInitiated)

    static func list() async -> Result<[AppleShortcut], Failure> {
        let result = await invoke(["list", "--show-identifiers"], capturesOutput: true)
        switch result {
        case .success(let output): return .success(AppleShortcut.parseList(output))
        case .failure(let failure): return .failure(failure)
        }
    }

    static func run(id: UUID) async -> String? {
        switch await invoke(["run", id.uuidString], capturesOutput: false) {
        case .success: return nil
        case .failure(let failure): return failure.message
        }
    }

    private static func invoke(_ arguments: [String], capturesOutput: Bool) async -> Result<String, Failure> {
        await withCheckedContinuation { continuation in
            queue.async {
                let process = Process()
                let output = Pipe()
                let errors = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = capturesOutput ? output : FileHandle.nullDevice
                process.standardError = errors
                do {
                    try process.run()
                    process.waitUntilExit()
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    let detail = String(decoding: errorData.suffix(8_192), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                        continuation.resume(returning: .failure(Failure(message: detail.isEmpty ? "The shortcuts command failed." : detail)))
                        return
                    }
                    let data = capturesOutput ? output.fileHandleForReading.readDataToEndOfFile() : Data()
                    continuation.resume(returning: .success(String(decoding: data, as: UTF8.self)))
                } catch {
                    continuation.resume(returning: .failure(Failure(message: error.localizedDescription)))
                }
            }
        }
    }
}
