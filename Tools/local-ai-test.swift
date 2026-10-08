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
        try Data("#!/bin/sh\necho fixture-reply\n".utf8).write(to: helper)
        try Data("#!/usr/bin/env spotter-cli-test-helper\n".utf8).write(to: executable)
        for path in [helper, executable] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path) }
        defaults.set([LocalAIModel.codex.rawValue: executable.path, LocalAIModel.claude.rawValue: root.appendingPathComponent("missing").path], forKey: "local-ai.executable-paths")
        let store = LocalAIStore(defaults: defaults)
        store.refresh()
        try await wait(store)
        precondition(store.path(for: .codex) == executable.path)
        precondition(store.path(for: .claude) == nil && store.pathErrors[.claude] != nil)
        var reply = ""
        try await store.chat(messages: [], modelID: LocalAIModel.codex.rawValue) { reply += $0 }
        precondition(reply == "fixture-reply")
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

    @MainActor
    static func wait(_ store: LocalAIStore) async throws {
        for _ in 0..<200 {
            if !store.isRefreshing { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        fatalError("Discovery timed out")
    }
}
