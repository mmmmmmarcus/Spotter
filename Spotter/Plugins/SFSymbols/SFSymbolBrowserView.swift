import SwiftUI

struct SFSymbolBrowserView: View {
    @ObservedObject var store: SFSymbolStore
    let context: PluginPaletteCanvasContext

    private var selected: SFSymbolEntry? {
        context.selectedID.flatMap { store.entry(id: $0) } ?? store.results.first
    }

    var body: some View {
        HStack(spacing: 0) {
            PluginPaletteList(sectionTitle: context.snapshot.sectionTitle, items: context.snapshot.items,
                selectedID: context.selectedID, scroll: context.scroll,
                onActivate: { context.activate($0.id) }, onActions: { context.actions($0.id) },
                emptyMessage: context.snapshot.emptyMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Theme.Colors.separator).frame(width: 1)
            VStack(spacing: Theme.Spacing.xl) {
                if let selected {
                    if let image = NSImage(systemSymbolName: selected.name, accessibilityDescription: selected.name) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .symbolRenderingMode(.monochrome)
                            .frame(width: 96, height: 96)
                            .accessibilityLabel(selected.name)
                    } else {
                        Image(systemName: "questionmark.square.dashed").font(.largeTitle)
                        Text("Preview requires a newer macOS version.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(selected.name).font(.callout.monospaced()).multilineTextAlignment(.center)
                    if let version = selected.minimumMacOS {
                        Text("macOS " + version + "+").font(.caption).foregroundStyle(.secondary)
                    }
                    if let codepoint = selected.codepoint {
                        Text(codepoint).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Text("↵ Copy Name\n⌘↵ Copy PNG\n⌘K More Actions")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else {
                    Image(systemName: "square.on.circle").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Select a symbol").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(Theme.Spacing.xl)
            .frame(width: 200, height: nil)
            .frame(maxHeight: .infinity)
        }
    }
}

struct SFSymbolSettingsView: View {
    let open: () -> Void

    var body: some View {
        SettingsPane(title: "SF Symbols") {
            Section {
                SettingsRow(title: "Command-Line Tool", subtitle: SFSymbolPlugin.executableURL?.path ?? "Requires SF Symbols 27 or later") {
                    Text(SFSymbolPlugin.executableURL == nil ? "Update Required" : "Available")
                        .foregroundStyle(.secondary)
                }
                SettingsRow(title: "Browse Symbols") { Button("Open in Spotter", action: open) }
                SettingsRow(title: "SF Symbols App") {
                    Button("Open", action: SFSymbolPlugin.openApplication)
                        .disabled(SFSymbolPlugin.applicationURL == nil)
                }
            } footer: {
                Text("Uses Apple's installed sfsymbols CLI for search and export. Return copies the name; Actions offers SwiftUI code, transparent PNG, and an SVG template. Previews use symbols available on this macOS version.")
            }
            Section {
                Link("Download SF Symbols from Apple", destination: URL(string: "https://developer.apple.com/sf-symbols/")!)
            }
        }
    }
}
