import Foundation

@main
struct LocalAITests {
    @MainActor
    static func main() async throws {
        let name = "com.spotter.test.local-ai.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("codex with spaces")
        let helper = root.appendingPathComponent("spotter-cli-test-helper")
        try Data("""
        #!/bin/sh
        if [ "$2" = "--version" ]; then echo fixture-version; exit 0; fi
        pwd > workspace.txt
        printf '%s\\n' "$@" > arguments.txt
        cat >/dev/null
        echo 'cache warning' >&2
        echo '{"type":"item.completed","item":{"type":"reasoning","text":"private reasoning"}}'
        echo '{"type":"item.completed","item":{"type":"agent_message","text":"fixture-reply"}}'
        echo '{"type":"turn.completed"}'
        """.utf8).write(to: helper)
        try Data("#!/usr/bin/env spotter-cli-test-helper\n".utf8).write(to: executable)
        for path in [helper, executable] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path) }
        defaults.set([LocalAIModel.codex.rawValue: executable.path, LocalAIModel.claude.rawValue: root.appendingPathComponent("missing").path], forKey: "local-ai.executable-paths")
        let workspace = root.appendingPathComponent("dedicated workspace")
        let store = LocalAIStore(defaults: defaults, workspace: workspace)
        store.refresh()
        try await wait(store)
        precondition(store.path(for: .codex) == executable.path)
        precondition(store.path(for: .claude) == nil && store.pathErrors[.claude] != nil)
        var reply = ""
        try await store.chat(messages: [], modelID: LocalAIModel.codex.rawValue) { reply += $0 }
        precondition(reply == "fixture-reply")
        let cwd = try String(contentsOf: workspace.appendingPathComponent("workspace.txt"), encoding: .utf8)
        precondition(URL(fileURLWithPath: cwd.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath().path == workspace.resolvingSymlinksInPath().path)
        let arguments = try String(contentsOf: workspace.appendingPathComponent("arguments.txt"), encoding: .utf8)
        precondition(arguments.contains("--json") && arguments.contains("read-only"))
        try responseTests()
        store.setCustomPath(root.path, for: .codex)
        store.setCustomPath(executable.path, for: .codex)
        try await wait(store)
        precondition(store.path(for: .codex) == executable.path)
        let restored = LocalAIStore(defaults: defaults)
        precondition(restored.customPaths[.codex] == executable.path)
        store.setCustomPath(root.path, for: .codex)
        try await wait(store)
        precondition(store.path(for: .codex) == nil && store.pathErrors[.codex] != nil)
        store.setCustomPath(nil, for: .codex)
        precondition(store.customPaths[.codex] == nil)
        precondition(LocalAIStore(defaults: defaults).customPaths[.codex] == nil)
        print("PASS custom paths, sibling executable environment, runtime dispatch, stale results, persistence, invalid paths and automatic reset")
    }

    static func responseTests() throws {
        let events = """
        {"type":"item.completed","item":{"type":"agent_message","phase":"commentary","text":"Working..."}}
        {"type":"item.completed","item":{"type":"command_execution","aggregated_output":"secret prompt"}}
        {"type":"item.completed","item":{"type":"agent_message","text":"Final answer"}}
        {"type":"turn.completed"}
        """
        let answer = try LocalAIResponse.reply(model: .codex, status: 0, stdout: events, stderr: "missing field `base_instructions`")
        precondition(answer == "Final answer")
        for (status, output, errors, expected) in [
            (Int32(1), events, "missing field `base_instructions`\nSystem: secret prompt", "model cache"),
            (Int32(1), "", "timeout waiting for child process to exit\nSystem: secret prompt", "timed out"),
            (Int32(0), "{\"type\":\"turn.failed\",\"error\":{\"message\":\"Login required\"}}", "", "Login required"),
            (Int32(1), "secret prompt", "System: secret prompt", "exit 1"),
            (Int32(0), "plain text without completion", "", "could not complete")
        ] {
            do {
                _ = try LocalAIResponse.reply(model: .codex, status: status, stdout: output, stderr: errors)
                fatalError("Expected failure")
            } catch {
                precondition(error.localizedDescription.contains(expected))
                precondition(!error.localizedDescription.contains("secret prompt"))
            }
        }
        let claude = try LocalAIResponse.reply(model: .claude, status: 0, stdout: "Claude answer\n", stderr: "warning")
        precondition(claude == "Claude answer")
        print("PASS JSON answer extraction, warnings, failures, transcript exclusion, dedicated workspace and CLI arguments")
    }

    @MainActor
    static func wait(_ store: LocalAIStore) async throws {
        for _ in 0..<200 {
            if !store.isRefreshing { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        fatalError("Discovery timed out")
    }
}
