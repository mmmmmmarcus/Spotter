import SwiftUI

struct AIToolSettingsSection: View {
    @ObservedObject private var tools = AppCore.shared.aiTools
    @State private var editor: ServerEditorTarget?
    @State private var error: String?
    private var servers: [String: AIMCPServer] { (try? AIMCPConfiguration.parse(tools.configurationText).mcpServers) ?? [:] }

    var body: some View {
        Section {
            ForEach(servers.keys.sorted { $0 == "cua" ? $1 != "cua" : ($1 == "cua" ? false : $0 < $1) }, id: \.self) { name in
                SettingsRow(title: name, subtitle: servers[name]?.command ?? servers[name]?.url, systemImage: "server.rack") {
                    Button("Edit…") { editor = .init(name: name, server: servers[name]) }
                    Button("Delete", role: .destructive) {
                        do {
                            var configuration = try AIMCPConfiguration.parse(tools.configurationText)
                            configuration.mcpServers.removeValue(forKey: name)
                            try tools.saveConfiguration(configuration.formatted)
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        } header: {
            Text("MCP")
        } footer: {
            SettingsListActions {
                Button("Add Server…") { editor = .init(name: nil, server: nil) }.controlSize(.small)
            }
        }
        .sheet(item: $editor) { target in AIMCPServerSheet(target: target) }
    }
}

private struct ServerEditorTarget: Identifiable {
    let id = UUID()
    let name: String?
    let server: AIMCPServer?
}

private struct AIMCPServerSheet: View {
    let target: ServerEditorTarget
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var remote: Bool
    @State private var address: String
    @State private var arguments: String
    @State private var values: String
    @State private var error: String?

    init(target: ServerEditorTarget) {
        self.target = target
        _name = State(initialValue: target.name ?? "")
        _remote = State(initialValue: target.server?.url != nil)
        _address = State(initialValue: target.server?.url ?? target.server?.command ?? "")
        _arguments = State(initialValue: target.server?.args?.joined(separator: "\n") ?? "")
        let dictionary = target.server?.headers ?? target.server?.env ?? [:]
        _values = State(initialValue: dictionary.keys.sorted().map { "\($0)=\(dictionary[$0]!)" }.joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(target.name == nil ? "Add MCP Server" : "Edit MCP Server").font(.headline)
            TextField("Server name", text: $name)
            Picker("Connection", selection: $remote) {
                Text("Local Command").tag(false)
                Text("Streamable HTTP").tag(true)
            }.onChange(of: remote) { values = ""; address = ""; arguments = "" }
            TextField(remote ? "https://server.example/mcp" : "Executable path", text: $address)
            if !remote {
                Text("Arguments · one per line").font(.caption)
                TextEditor(text: $arguments).frame(height: 70)
            }
            Text(remote ? "Headers · NAME=value, one per line" : "Environment · NAME=value, one per line").font(.caption)
            TextEditor(text: $values).frame(height: 80)
            Text("Servers run on this Mac. Tool results are shared with your model provider; each tool call asks for confirmation. Configuration stays on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }.textFieldStyle(.roundedBorder).padding(Theme.Spacing.xxl).frame(width: 540)
    }

    private func save() {
        do {
            let tools = AppCore.shared.aiTools
            var configuration = try AIMCPConfiguration.parse(tools.configurationText)
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == target.name || configuration.mcpServers[key] == nil else { throw AIToolFailure("A server with this name already exists.") }
            var dictionary: [String: String] = [:]
            for line in values.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let separator = line.firstIndex(of: "="), separator != line.startIndex else { throw AIToolFailure("Use NAME=value for each entry.") }
                let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                guard dictionary[name] == nil else { throw AIToolFailure("Duplicate entry: \(name)") }
                dictionary[name] = String(line[line.index(after: separator)...])
            }
            if let original = target.name { configuration.mcpServers.removeValue(forKey: original) }
            let endpoint = address.trimmingCharacters(in: .whitespacesAndNewlines)
            configuration.mcpServers[key] = remote
                ? AIMCPServer(url: endpoint, headers: dictionary)
                : AIMCPServer(command: endpoint, args: arguments.components(separatedBy: "\n").filter { !$0.isEmpty }, env: dictionary)
            try tools.saveConfiguration(configuration.formatted)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
