import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @State private var confirmingClear = false
    @State private var showingAppPicker = false
    @ObservedObject private var semanticSearch = AppCore.shared.clipboardSemanticSearch
    @State private var confirmingSemanticSearch = false
    @State private var importingSemanticModels = false

    var body: some View {
        SettingsPane(title: "Clipboard") {
            Section("History") {
                SettingsRow(title: "Keep history for") {
                    Picker("", selection: $settings.clipboardRetention) {
                        ForEach(ClipboardRetention.allCases) { retention in
                            Text(retention.title).tag(retention)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: settings.clipboardRetention) {
                        let store = AppCore.shared.clipboardStore
                        store.maxAge = settings.clipboardRetention.maxAge
                        store.enforceLimits()
                    }
                }
                SettingsRow(
                    title: "Search Text in Images & PDFs",
                    subtitle: "Indexes copied images and PDF files on this Mac with Vision and PDFKit."
                ) {
                    Toggle("", isOn: $settings.clipboardTextSearch)
                        .labelsHidden()
                        .onChange(of: settings.clipboardTextSearch) {
                            AppCore.shared.clipboardTextIndexer.setEnabled(settings.clipboardTextSearch)
                        }
                }
            }

            Section("Semantic Search") {
                SettingsRow(title: "Search Clipboard by Meaning") {
                    Toggle("", isOn: Binding(get: { semanticSearch.isEnabled }, set: { enabled in
                        if enabled { confirmingSemanticSearch = true }
                        else { semanticSearch.setEnabled(false) }
                    }))
                    .labelsHidden()
                    #if !arch(arm64)
                    .disabled(true)
                    #endif
                }
                if semanticSearch.isEnabled {
                    SettingsRow(title: semanticSearch.status, subtitle: semanticSearch.error) {
                        if semanticSearch.isPreparing {
                            RingLoader(progress: semanticSearch.downloadProgress, size: Theme.Size.ringLoaderSmall)
                        } else if semanticSearch.error != nil {
                            Button("Retry") { semanticSearch.retry() }
                        }
                    }
                    if semanticSearch.canImportModels {
                        SettingsRow(title: "Local Model Files") {
                            Button("Import Model…") { importingSemanticModels = true }
                        }
                    }
                }
            }

            Section {
                if settings.clipboardDisabledApps.isEmpty {
                    SettingsRow(title: "No disabled applications") { EmptyView() }
                }
                ForEach(settings.clipboardDisabledApps, id: \.self) { bundleID in
                    DisabledAppRow(bundleID: bundleID) {
                        settings.clipboardDisabledApps.removeAll { $0 == bundleID }
                    }
                }
            } header: {
                Text("Disabled Applications")
            } footer: {
                SettingsListActions {
                    Button {
                        showingAppPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("Add Disabled Application")
                    .accessibilityLabel("Add Disabled Application")
                    .popover(isPresented: $showingAppPicker, arrowEdge: .bottom) {
                        AppPickerPopover(excluded: Set(settings.clipboardDisabledApps)) { bundleID in
                            settings.clipboardDisabledApps.append(bundleID)
                            showingAppPicker = false
                        }
                    }
                }
            }

            Section("Danger Zone") {
                SettingsRow(title: "Clear history") {
                    Button("Clear…", role: .destructive) { confirmingClear = true }
                        .controlSize(.regular)
                }
            }
        }
        .fileImporter(isPresented: $importingSemanticModels, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result { semanticSearch.importModels(from: folder) }
        }
        .confirmationDialog(
            "Enable local semantic search?",
            isPresented: $confirmingSemanticSearch,
            titleVisibility: .visible
        ) {
            Button("Download & Enable") { semanticSearch.setEnabled(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Spotter downloads an 865 MB EmbeddingGemma 2 model from Hugging Face once, then indexes up to 10,000 recent text and image clipboard entries on this Mac. Only model download requests leave your Mac; clipboard content and searches stay local. New copies are indexed automatically. Turning this off removes the model and index. Requires Apple silicon.")
        }
        .confirmationDialog(
            "Clear clipboard history?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                AppCore.shared.clipboardStore.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}

/// One excluded app (icon + name + remove button); the stored value is just a bundle ID, so name/icon resolve on the fly via the app index, else LaunchServices, else a placeholder for uninstalled apps.
private struct DisabledAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    @EnvironmentObject private var appIndex: AppIndex

    var body: some View {
        let (name, icon) = resolve()
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 22, height: 22)
            Text(name)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xl)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func resolve() -> (String, NSImage) {
        if let app = appIndex.apps.first(where: { $0.bundleID == bundleID }) {
            return (app.name, app.icon)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = url.deletingPathExtension().lastPathComponent
            return (name, IconCache.icon(forFile: url.path))
        }
        return (bundleID, NSWorkspace.shared.icon(for: .applicationBundle))
    }
}

/// Searchable list of installed apps (from the launcher's index) used to add a disabled app.
private struct AppPickerPopover: View {
    let excluded: Set<String>
    let onSelect: (String) -> Void

    @EnvironmentObject private var appIndex: AppIndex
    @State private var query = ""

    private var candidates: [AppEntry] {
        (query.isEmpty ? appIndex.apps : appIndex.matches(query))
            .filter { $0.kind == .application }
            .filter { $0.bundleID.map { !excluded.contains($0) } ?? false }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(Theme.Spacing.md)
            Divider()
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(candidates) { app in
                        Button {
                            if let id = app.bundleID { onSelect(id) }
                        } label: {
                            HStack(spacing: Theme.Spacing.lg) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(app.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.sm)
            }
        }
        .frame(width: 280, height: 320)
    }
}
