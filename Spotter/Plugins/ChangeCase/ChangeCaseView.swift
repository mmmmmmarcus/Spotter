import SwiftUI

struct ChangeCaseView: View {
    @ObservedObject var store: ChangeCaseStore
    let targetApp: NSRunningApplication?

    private struct CaseSection: Identifiable {
        let title: String
        let kinds: [ChangeCaseKind]
        var id: String { title }
    }

    private var sections: [CaseSection] {
        let query = store.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let kinds = store.enabledKinds
        if !query.isEmpty {
            return [CaseSection(title: "Results", kinds: kinds.filter { $0.title.localizedCaseInsensitiveContains(query) })]
        }
        let pinned = kinds.filter(store.pinned.contains)
        let recent = store.recent.filter { kinds.contains($0) && !store.pinned.contains($0) }
        let remaining = kinds.filter { !store.pinned.contains($0) && !recent.contains($0) }
        return [
            CaseSection(title: "Pinned", kinds: pinned),
            CaseSection(title: "Recent", kinds: recent),
            CaseSection(title: "All Cases", kinds: remaining),
        ].filter { !$0.kinds.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Input").font(Theme.Typography.sectionHeader).foregroundStyle(.secondary)
                TextEditor(text: $store.input)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.md)
                    .frame(height: 104)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.cardFill))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.Colors.cardStroke))
                TextField("Filter cases…", text: $store.query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(Theme.Spacing.xl)
            Divider()
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(sections) { section in
                        HStack {
                            Text(section.title).font(Theme.Typography.sectionHeader).foregroundStyle(.secondary)
                            Spacer()
                            if section.title == "Pinned" { Button("Clear") { store.clearPinned() }.buttonStyle(.plain).font(.caption) }
                            if section.title == "Recent" { Button("Clear") { store.clearRecent() }.buttonStyle(.plain).font(.caption) }
                        }
                        .padding(.top, Theme.Spacing.sm)
                        ForEach(section.kinds) { kind in row(kind) }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
            .overlayScroller()
        }
        .frame(minWidth: 620, minHeight: 460)
    }

    private func row(_ kind: ChangeCaseKind) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: kind.systemImage).foregroundStyle(.purple).frame(width: 24)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(kind.title).font(.headline)
                Text(store.output(for: kind)).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button { store.togglePinned(kind) } label: {
                Image(systemName: store.pinned.contains(kind) ? "pin.fill" : "pin")
            }.buttonStyle(.plain).help(store.pinned.contains(kind) ? "Unpin" : "Pin")
            Button("Copy") { use(kind, paste: false) }
            Button("Paste") { use(kind, paste: true) }
        }
        .padding(Theme.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.Colors.cardStroke))
        .contextMenu {
            Button(store.pinned.contains(kind) ? "Unpin Case" : "Pin Case") { store.togglePinned(kind) }
            if store.recent.contains(kind) { Button("Remove from Recent") { store.removeRecent(kind) } }
        }
    }

    private func use(_ kind: ChangeCaseKind, paste: Bool) {
        let output = store.output(for: kind)
        guard !output.isEmpty else { return }
        store.record(kind)
        if paste { Paster.pasteString(output, previousApp: targetApp) }
        else { Paster.copyPlainText(output) }
    }
}
