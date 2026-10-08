import AppKit
import SwiftUI

struct RaycastExtensionsSettingsView: View {
    let core: AppCore
    @ObservedObject private var coordinator: ExtensionCoordinator
    @State private var query = ""
    @State private var source = ""
    @State private var results: [ExtensionListing] = []
    @State private var status: String?
    @State private var busy = false
    @State private var operationID = UUID()
    @State private var operationTask: Task<Void, Never>?
    @State private var expanded: String?
    @State private var error: String?

    init(core: AppCore) {
        self.core = core
        coordinator = core.extensionCoordinator
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Raycast Extensions", isOn: Binding(get: { coordinator.enabled }, set: { coordinator.setEnabled($0) }))
                Toggle("Show in Launcher", isOn: Binding(get: { core.extensions.showsInLauncher }, set: { core.extensions.setShowsInLauncher($0); UserDefaults.standard.set($0, forKey: "raycast-extensions.show-in-launcher") }))
                    .disabled(!coordinator.enabled)
            } footer: {
                Text("Extensions run locally using JavaScriptCore. Third-party extensions may access files, run commands and contact their own services.")
            }
            if coordinator.enabled {
                Section("Install") {
                    HStack {
                        TextField("Search Raycast Store", text: $query).onSubmit { search() }
                        Button("Search") { search() }.disabled(busy)
                    }
                    ForEach(results) { result in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(result.title)
                                Text(result.author + " · " + result.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Button(core.extensions.extensionNamed(result.name) == nil ? "Install" : "Reinstall") {
                                perform(successMessage: "Installed \(result.title).") {
                                    let id = operationID
                                    try await core.extensions.install(result) { progress in
                                        Task { @MainActor in
                                            guard busy, operationID == id else { return }
                                            status = progress.message
                                        }
                                    }
                                    expanded = result.name
                                }
                            }.disabled(busy)
                        }
                    }
                    HStack {
                        TextField("GitHub extension URL", text: $source)
                        Button("Install from Source") {
                            guard let value = ExtensionGitHubSource(source) else { error = "Enter a GitHub URL to an extension folder."; return }
                            perform(successMessage: "Extension installed.") {
                                let id = operationID
                                let installed = try await core.extensions.install(value, packageManager: coordinator.packageManager, additionalSearchPaths: coordinator.customSearchPaths.split(separator: "\n").map(String.init)) { progress in
                                    Task { @MainActor in
                                        guard busy, operationID == id else { return }
                                        status = progress.message
                                    }
                                }
                                expanded = installed.id
                            }
                        }.disabled(busy)
                    }
                    Text("Source installs run the extension’s build scripts using your local Node.js and package manager.").font(.caption).foregroundStyle(.secondary)
                    Picker("Package Manager", selection: $coordinator.packageManager) {
                        ForEach(ExtensionPackageManager.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Additional executable search paths (one per line)", text: $coordinator.customSearchPaths, axis: .vertical)
                    HStack {
                        Button("Import Built Extension…") { importLocal() }
                        Button("Import from Raycast…") {
                            perform {
                                let candidates = await core.extensions.raycastImportCandidates().filter { !$0.isInstalled }
                                guard !candidates.isEmpty else { status = "No new built extensions found in Raycast."; return }
                                let alert = NSAlert()
                                alert.messageText = "Import \(candidates.count) extensions?"
                                alert.informativeText = candidates.map { $0.installed.title }.joined(separator: ", ")
                                alert.addButton(withTitle: "Cancel")
                                alert.addButton(withTitle: "Import")
                                guard alert.runModal() == .alertSecondButtonReturn else { return }
                                let failed = await core.extensions.importAllFromRaycast(candidates.map(\.installed))
                                status = failed.isEmpty ? "Import complete." : "Could not import: " + failed.joined(separator: ", ")
                            }
                        }
                    }.disabled(busy)
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                    if busy { ProgressView().controlSize(.small) }
                    if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
                Section("Maintenance") {
                    Button("Clean Unused Extension Data…") {
                        perform {
                            let installed = Set(core.extensions.installed.map(\.id))
                            let roots = ExtensionCleanup.defaultRoots()
                            let report = await Task.detached { ExtensionCleanup.reclaimable(installed: installed, in: roots) }.value
                            guard !report.isEmpty else { status = "No unused extension data."; return }
                            let alert = NSAlert()
                            alert.messageText = "Remove unused extension data?"
                            alert.informativeText = "Removes \(report.items) unused items (\(ExtensionCleanup.formatted(bytes: report.bytes))). Installed extensions and their data are retained."
                            alert.addButton(withTitle: "Cancel")
                            alert.addButton(withTitle: "Clean")
                            guard alert.runModal() == .alertSecondButtonReturn else { return }
                            let removed = await Task.detached { ExtensionCleanup.clean(installed: installed, in: roots) }.value
                            status = "Removed \(removed.items) unused items."
                        }
                    }.disabled(busy)
                }
                Section("Installed Extensions") {
                    HStack {
                        Button("Check for Updates") { perform { await core.extensions.checkForUpdates() } }
                        if !core.extensions.updates.isEmpty {
                            Button("Update All") { perform { let failures = await core.extensions.update(Array(core.extensions.updates.keys)); error = failures.isEmpty ? nil : failures.joined(separator: "\n") } }
                        }
                    }.disabled(busy)
                    ForEach(core.extensions.installed) { owner in
                        DisclosureGroup(isExpanded: Binding(get: { expanded == owner.id }, set: { expanded = $0 ? owner.id : nil })) {
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
                        } label: {
                            Button(owner.title) { expanded = expanded == owner.id ? nil : owner.id }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: coordinator.enabled) {
            if !coordinator.enabled {
                operationID = UUID()
                operationTask?.cancel()
                busy = false
                status = nil
                results = []
            }
        }
        .task { if coordinator.enabled { await core.extensions.refresh() } }
    }

    private func search() {
        perform { results = try await core.extensions.searchStore(query) }
    }

    private func perform(successMessage: String? = nil, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        operationID = UUID()
        let id = operationID
        busy = true
        error = nil
        status = nil
        operationTask = Task { @MainActor in
            defer { if operationID == id { busy = false } }
            do {
                try await operation()
                try Task.checkCancellation()
                guard operationID == id else { return }
                if let successMessage { status = successMessage }
            } catch {
                guard operationID == id else { return }
                status = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }

    private func importLocal() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        perform(successMessage: "Extension imported.") { try await core.extensions.install(from: url) }
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
