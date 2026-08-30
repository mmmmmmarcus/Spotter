import SwiftUI

struct OnePasswordSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var manager = AppCore.shared.onePassword
    @State private var pathDraft = AppCore.shared.onePassword.binaryPathOverride
    @AppStorage(OnePasswordManager.primaryActionKey) private var primaryActionRaw =
        OnePasswordItemAction.view.rawValue
    @AppStorage(OnePasswordManager.clearClipboardKey) private var clearClipboard = true
    @AppStorage(OnePasswordManager.passwordLengthKey) private var passwordLength = 20
    @AppStorage(OnePasswordManager.passwordDigitsKey) private var passwordDigits = true
    @AppStorage(OnePasswordManager.passwordSymbolsKey) private var passwordSymbols = true

    var body: some View {
        SettingsPane(
            title: "1Password",
            subtitle: "Search your 1Password items from the launcher through the 1Password CLI."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "1Password",
                    subtitle: "Open, copy or paste 1Password items without leaving the keyboard.",
                    systemImage: "key.fill", tint: .blue
                ) {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            if !manager.isInstalled {
                SettingsCallout(
                    title: "1Password CLI not found",
                    message:
                        "Install it with `brew install 1password-cli`, then turn on "
                        + "Settings ▸ Developer ▸ Integrate with 1Password CLI in the 1Password app.",
                    systemImage: "exclamationmark.triangle",
                    tint: .orange)
            }

            SettingsCard(header: "Command Line Tool") {
                SettingsRow(
                    title: "Binary Path",
                    subtitle: manager.binaryPath.map { "Using \($0)" }
                        ?? "Searched Homebrew's usual locations and found nothing.",
                    systemImage: "terminal", tint: .blue
                ) {
                    TextField("/opt/homebrew/bin/op", text: $pathDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit { manager.setBinaryPathOverride(pathDraft) }
                        .onChange(of: pathDraft) { manager.setBinaryPathOverride(pathDraft) }
                }
            }

            SettingsCard(header: "Behavior") {
                SettingsRow(
                    title: "Primary Action",
                    subtitle: "What ↵ does on a login item; categories that can't fall back to View Item.",
                    systemImage: "return", tint: .blue
                ) {
                    Picker("", selection: $primaryActionRaw) {
                        ForEach(OnePasswordItemAction.allCases, id: \.rawValue) { action in
                            Text(action.title).tag(action.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Clear Copied Secrets",
                    subtitle: "Remove a copied secret from the clipboard after 90 seconds unless something replaced it.",
                    systemImage: "timer", tint: .blue
                ) {
                    Toggle("", isOn: $clearClipboard)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Generated Passwords") {
                SettingsRow(
                    title: "Length",
                    subtitle: "Characters in a password from the Generate Password command.",
                    systemImage: "textformat.123", tint: .blue
                ) {
                    Picker("", selection: $passwordLength) {
                        ForEach([12, 16, 20, 24, 32, 48, 64], id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Digits",
                    subtitle: "Include 0–9.",
                    systemImage: "number", tint: .blue
                ) {
                    Toggle("", isOn: $passwordDigits)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Symbols",
                    subtitle: "Include !@.-_* and friends.",
                    systemImage: "asterisk", tint: .blue
                ) {
                    Toggle("", isOn: $passwordSymbols)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Shortcuts") {
                SettingsRow(
                    title: "Search 1Password",
                    subtitle: "Open your 1Password items in the Spotter palette.",
                    systemImage: "keyboard", tint: .blue
                ) {
                    ShortcutRecorder(action: .plugin(.openOnePassword))
                }
                SettingsDivider()
                SettingsRow(
                    title: "Generate Password",
                    subtitle: "Copy a fresh password without opening 1Password.",
                    systemImage: "wand.and.stars", tint: .blue
                ) {
                    ShortcutRecorder(action: .plugin(.generateOnePasswordPassword))
                }
            }

            SettingsCallout(
                title: "Secrets stay in 1Password.",
                message:
                    "Spotter lists item names through the 1Password CLI and fetches a secret only "
                    + "when you run a copy or paste action, with 1Password's own authorization prompt "
                    + "as the gate. Copies are marked concealed, never enter clipboard history, and "
                    + "nothing 1Password returns is written to disk.",
                systemImage: "hand.raised",
                tint: .blue)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { plugins.isEnabled(.onePassword) },
            set: { plugins.setEnabled($0, for: .onePassword) })
    }
}
