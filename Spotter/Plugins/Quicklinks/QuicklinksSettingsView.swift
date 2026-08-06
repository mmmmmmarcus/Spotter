import AppKit
import SwiftUI

struct QuicklinksSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject var store: QuicklinkStore
    @ObservedObject var appIndex: AppIndex
    @State private var editor: QuicklinkEditorTarget?
    @State private var pendingDeletion: Quicklink?

    var body: some View {
        SettingsPane(
            title: "Quicklinks",
            subtitle: "Save links, files and deep links as launcher entries you can open by name."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Quicklinks",
                    subtitle: "Show your saved links in the launcher and in their own search screen.",
                    systemImage: "link",
                    tint: .blue
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.quicklinks) },
                            set: { plugins.setEnabled($0, for: .quicklinks) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsCallout(
                title: "Placeholders make one link reusable.",
                message:
                    "Write {argument} anywhere in a link and Spotter asks for the value before "
                    + "opening it. Name it with {argument name=\"City\"} or offer fixed choices "
                    + "with {argument options=\"day,week,month\"}.",
                systemImage: "curlybraces",
                tint: .blue)

            SettingsCard(header: "Saved Quicklinks") {
                if store.sorted.isEmpty {
                    SettingsRow(
                        title: "No quicklinks",
                        subtitle: "Add a name and the link it should open.",
                        systemImage: "link.badge.plus",
                        tint: .secondary
                    ) { EmptyView() }
                } else {
                    ForEach(Array(store.sorted.enumerated()), id: \.element.id) { index, quicklink in
                        if index > 0 { SettingsDivider() }
                        QuicklinkSettingsRow(
                            quicklink: quicklink,
                            onTogglePin: { store.togglePinned(id: quicklink.id) },
                            onEdit: { editor = QuicklinkEditorTarget(quicklink: quicklink) },
                            onDelete: { pendingDeletion = quicklink })
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: "Add Quicklink",
                    subtitle: "Create another named link.",
                    systemImage: "plus.circle",
                    tint: .blue
                ) {
                    Button("Add…") { editor = QuicklinkEditorTarget(quicklink: nil) }
                        .controlSize(.small)
                }
            }
        }
        .sheet(item: $editor) { target in
            QuicklinkEditorSheet(store: store, appIndex: appIndex, quicklink: target.quicklink)
        }
        .alert(item: $pendingDeletion) { quicklink in
            Alert(
                title: Text("Delete “\(quicklink.name)”?"),
                message: Text("This quicklink will no longer appear in the launcher."),
                primaryButton: .destructive(Text("Delete")) { store.delete(id: quicklink.id) },
                secondaryButton: .cancel())
        }
    }
}

/// The icon of the app a quicklink opens with, falling back to a symbol when nothing claims it.
private struct QuicklinkIcon: View {
    let quicklink: Quicklink

    var body: some View {
        Group {
            if let path = QuicklinkManager.openerBundlePath(for: quicklink) {
                Image(nsImage: IconCache.icon(forFile: path)).resizable()
            } else {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
    }
}

private struct QuicklinkSettingsRow: View {
    let quicklink: Quicklink
    let onTogglePin: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            QuicklinkIcon(quicklink: quicklink)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(quicklink.name).font(.body).lineLimit(1)
                Text(quicklink.link)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(quicklink.link)
            }

            Spacer(minLength: Theme.Spacing.lg)
            Button(action: onTogglePin) {
                Image(systemName: quicklink.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(quicklink.isPinned ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help(quicklink.isPinned ? "Unpin" : "Pin to the top")
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .help("Edit Quicklink")
            Button(action: onDelete) {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Quicklink")
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}

private struct QuicklinkEditorTarget: Identifiable {
    let id = UUID()
    let quicklink: Quicklink?
}

private struct QuicklinkEditorSheet: View {
    @ObservedObject var store: QuicklinkStore
    @ObservedObject var appIndex: AppIndex
    let quicklink: Quicklink?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var link: String
    @State private var openWithBundleID: String

    init(store: QuicklinkStore, appIndex: AppIndex, quicklink: Quicklink?) {
        self.store = store
        self.appIndex = appIndex
        self.quicklink = quicklink
        _name = State(initialValue: quicklink?.name ?? "")
        _link = State(initialValue: quicklink?.link ?? "")
        _openWithBundleID = State(initialValue: quicklink?.openWithBundleID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                QuicklinkIcon(quicklink: draft)
                Text(quicklink == nil ? "Add Quicklink" : "Edit Quicklink")
                    .font(.title2.weight(.bold))
            }

            field("Name") {
                TextField("Search GitHub", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            field("Link") {
                TextField("https://github.com/search?q={argument}", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }

            // A `Menu` of buttons, not a `Picker`: a macOS picker renders its rows as plain text and
            // drops the `Label` icon, which is the whole point of showing the app here.
            field("Open With") {
                Menu {
                    Button { openWithBundleID = "" } label: {
                        Label("Default App", systemImage: "link")
                    }
                    ForEach(openers, id: \.id) { app in
                        Button { openWithBundleID = app.bundleID ?? "" } label: {
                            appLabel(app.name, iconPath: app.url.path)
                        }
                    }
                } label: {
                    if let app = selectedOpener {
                        appLabel(app.name, iconPath: app.url.path)
                    } else {
                        Label("Default App", systemImage: "link")
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !argumentNames.isEmpty {
                Text("Asks for: " + argumentNames.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.textReplacementEditorWidth)
    }

    @ViewBuilder
    private func field<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title).font(.callout.weight(.medium))
            content()
        }
    }

    /// `IconCache` hands back a 48pt bitmap sized for launcher rows; a menu row needs it at text size.
    @ViewBuilder
    private func appLabel(_ name: String, iconPath: String) -> some View {
        Label {
            Text(name)
        } icon: {
            Image(nsImage: IconCache.icon(forFile: iconPath))
                .resizable()
                .frame(width: 16, height: 16)
        }
    }

    /// Every app the launcher itself indexes — the same scopes as Settings → Search Scopes, so
    /// anything you can launch by name is also something you can open a link with.
    private var openers: [AppEntry] {
        appIndex.apps
            .filter { $0.kind == .application && $0.bundleID != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedOpener: AppEntry? {
        guard !openWithBundleID.isEmpty else { return nil }
        return openers.first { $0.bundleID == openWithBundleID }
    }

    /// The live edit, so the sheet's icon tracks the Open With choice as it changes.
    private var draft: Quicklink {
        Quicklink(
            id: quicklink?.id ?? UUID(),
            name: name,
            link: link,
            openWithBundleID: openWithBundleID.isEmpty ? nil : openWithBundleID,
            pinnedAt: quicklink?.pinnedAt,
            createdAt: quicklink?.createdAt ?? Date())
    }

    private var argumentNames: [String] {
        QuicklinkTemplate.arguments(in: link).map(\.name)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        var saved = draft
        saved.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if quicklink == nil {
            store.add(saved)
        } else {
            store.update(saved)
        }
        dismiss()
    }
}
