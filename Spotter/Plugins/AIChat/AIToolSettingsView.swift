import SwiftUI

struct AIToolSettingsSection: View {
    @ObservedObject private var tools = AppCore.shared.aiTools
    @ObservedObject private var router = AppCore.shared.openRouter
    @State private var showsConsent = false
    @State private var showsEditor = false

    var body: some View {
        Section("MCP & Computer Use · Experimental") {
            SettingsRow(title: "Allow AI Tools", subtitle: "Connect only during chat requests. Each tool call asks before running.") {
                Toggle("", isOn: Binding(get: { tools.isEnabled }, set: { enabled in
                    if enabled { showsConsent = true } else { tools.setEnabled(false) }
                }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(!tools.isEnabled && (!router.isReady || tools.serverCount == 0))
            }
            SettingsRow(title: "MCP Servers", subtitle: "\(tools.serverCount) configured · \(tools.status)") {
                Button("Configure…") { showsEditor = true }.controlSize(.small)
            }
            SettingsRow(title: "Computer Use with Cua", subtitle: "Install Cua Driver, then add its preset in Configure. Cua manages its own macOS permissions.") {
                Link("Setup Guide", destination: URL(string: "https://cua.ai/docs/how-to-guides/driver/connect-your-agent")!)
                    .font(.callout)
            }
        }
        .alert("Allow MCP and Cua tools?", isPresented: $showsConsent) {
            Button("Cancel", role: .cancel) {}
            Button("Allow Tools") { tools.setEnabled(true) }
        } message: {
            Text(tools.consentMessage)
        }
        .sheet(isPresented: $showsEditor) { AIMCPConfigurationSheet() }
    }
}

private struct AIMCPConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tools = AppCore.shared.aiTools
    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("MCP Servers").font(.headline)
            Text("Use mcpServers JSON with command / args / env for local stdio servers, or url / headers for Streamable HTTP. Configuration stays on this Mac and is excluded from sync.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .frame(minHeight: 260)
                .border(Theme.Colors.border)
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            Text("Only configure servers you trust. Local commands run as your macOS user; headers and environment values are stored with these settings. Saving turns tool access off until you enable it again.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Add Cua") {
                    do { draft = try tools.addingCua(to: draft); error = nil }
                    catch { self.error = error.localizedDescription }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do { try tools.saveConfiguration(draft); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 600)
        .onAppear { draft = tools.configurationText }
    }
}
