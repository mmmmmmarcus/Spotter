import AppKit
import SwiftUI

struct RaycastExtensionsSettingsView: View {
    let core: AppCore
    let extensionID: String
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        if let owner = core.extensions.extensionNamed(extensionID) {
            SettingsPane(title: owner.title) {
                Section("Extension") {
                    Button("Check for Updates") { perform { await core.extensions.checkForUpdates() } }.disabled(busy)
                if core.extensions.updates[owner.id] != nil {
                    Button("Update") { perform {
                        let failures = await core.extensions.update([owner.id])
                        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
                    } }.disabled(busy)
                }
                preferences(owner)
                ForEach(owner.manifest.commands, id: \.name) { command in
                    let reference = ExtensionCommandRef(extensionName: owner.id, commandName: command.name)
                    HStack {
                        Text(command.title)
                        Spacer()
                        if command.mode == .menuBar {
                            Toggle("Menu Bar", isOn: Binding(get: { core.extensions.menuBarIsEnabled(reference) }, set: { core.extensions.setMenuBarEnabled($0, reference: reference) })).labelsHidden()
                        }
                        ShortcutRecorder(action: .plugin(RaycastExtensionsPlugin.key(reference, title: command.title)))
                        Button("Run") {
                            guard let entry = core.extensions.launcherEntry(forEntryID: reference.entryID) else { return }
                            core.extensionCoordinator.runExtensionCommand(entry)
                        }
                    }
                    if ExtensionRefreshPolicy.isSchedulable(mode: command.mode, interval: command.interval) {
                        Toggle("Background Refresh", isOn: Binding(
                            get: { core.extensions.backgroundInfo(extension: owner.id, command: command.name).backgroundEnabled },
                            set: { core.extensions.setBackgroundEnabled($0, extension: owner.id, command: command.name) }))
                    }
                }
                Button("Uninstall…", role: .destructive) {
                    let alert = NSAlert()
                    alert.messageText = "Uninstall \(owner.title)?"
                    alert.informativeText = "Removes this extension and its local preferences, cache and support files."
                    alert.addButton(withTitle: "Cancel")
                    alert.addButton(withTitle: "Uninstall")
                    if alert.runModal() == .alertSecondButtonReturn { perform { await core.extensions.uninstall(owner) } }
                }

                }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
        } else { EmptyResults(text: "This extension is no longer installed.") }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() }
            catch { self.error = error.localizedDescription }
        }
    }

    private func preferences(_ owner: InstalledExtension) -> some View {
        let schemas = owner.manifest.preferences + owner.manifest.commands.flatMap(\.preferences)
        var seen = Set<String>()
        let unique = schemas.filter { seen.insert($0.name).inserted }
        return ForEach(unique, id: \.name) { schema in
            RaycastPreferenceField(schema: schema, name: owner.id, storage: core.extensions.storage)
        }
    }
}

private struct RaycastPreferenceField: View {
    let schema: ExtensionPreferenceSchema
    let name: String
    let storage: ExtensionStorage
    private var value: ExtensionPreferenceValue { storage.preference(extension: name, key: schema.name) ?? schema.effectiveDefault }
    private var text: Binding<String> {
        Binding(get: { value.stringValue }, set: { storage.setPreference(extension: name, key: schema.name, value: schema.kind == .appPicker ? .application($0) : .string($0)) })
    }
    var body: some View {
        Group {
            switch schema.kind {
            case .checkbox:
                Toggle(schema.displayTitle, isOn: Binding(get: { value.boolValue }, set: { storage.setPreference(extension: name, key: schema.name, value: .bool($0)) }))
            case .password:
                SecureField(schema.displayTitle, text: text)
            case .dropdown:
                Picker(schema.displayTitle, selection: text) {
                    ForEach(schema.options, id: \.value) { Text($0.title).tag($0.value) }
                }
            case .file, .directory, .appPicker:
                HStack {
                    TextField(schema.displayTitle, text: text)
                    Button("Choose…") {
                        let picker = NSOpenPanel()
                        picker.canChooseDirectories = schema.kind == .directory
                        picker.canChooseFiles = schema.kind != .directory
                        if schema.kind == .appPicker { picker.allowedContentTypes = [.applicationBundle] }
                        if picker.runModal() == .OK, let path = picker.url?.path { text.wrappedValue = path }
                    }
                }
            case .textfield: TextField(schema.displayTitle, text: text)
            }
        }.help(schema.description ?? "")
    }
}

struct RaycastSupportSettings: View {
    let core: AppCore
    @ObservedObject private var coordinator = AppCore.shared.extensionCoordinator

    var body: some View {
        Section("Raycast Extension") {
            Toggle("Enable Raycast Extensions", isOn: Binding(get: { coordinator.enabled }, set: { coordinator.setEnabled($0) }))
            Toggle("Show Commands in Launcher", isOn: Binding(get: { core.extensions.showsInLauncher }, set: {
                core.extensions.setShowsInLauncher($0)
                UserDefaults.standard.set($0, forKey: "raycast-extensions.show-in-launcher")
            }))
            Picker("Package Manager", selection: $coordinator.packageManager) {
                ForEach(ExtensionPackageManager.allCases) { Text($0.title).tag($0) }
            }
            TextField("Additional executable search paths (one per line)", text: $coordinator.customSearchPaths, axis: .vertical)
        }
    }
}
