import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let openSFSymbols = standard(pluginID: .sfSymbols, actionID: "open", title: "SF Symbols")
}

@MainActor
enum SFSymbolPlugin {
    static var applicationURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.SFSymbols") }

    static var executableURL: URL? {
        guard let url = applicationURL?.appendingPathComponent("Contents/Executables/sfsymbols"),
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openSFSymbols() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Search SF Symbols by name, keyword, or category…",
            canvas: { [weak core] context in
                guard let core, context.snapshot.errorMessage == nil,
                      !context.snapshot.items.isEmpty else { return nil }
                return AnyView(SFSymbolBrowserView(store: core.sfSymbols, context: context))
            },
            snapshot: { [weak core] _ in
                guard let store = core?.sfSymbols else {
                    return PluginPaletteSnapshot(sectionTitle: "SF Symbols", items: [], emptyMessage: "Unavailable")
                }
                return PluginPaletteSnapshot(
                    sectionTitle: "SF Symbols · \(store.results.count)" + (store.results.count == SFSymbolCatalog.resultLimit ? " · Refine to see more" : ""),
                    items: store.results.map {
                        PluginPaletteItem(id: $0.id, title: $0.name, subtitle: nil, icon: .symbol($0.name), primaryActionTitle: "Copy Name")
                    }, isLoading: store.isLoading, loadingMessage: "Loading local SF Symbols…",
                    errorMessage: store.errorMessage, emptyMessage: "No matching symbols")
            },
            performPrimaryAction: { [weak core] in core?.copySFSymbol(id: $0) },
            performSecondaryAction: { [weak core] in core?.copySFSymbolImage(id: $0) },
            actions: { [weak core] id in
                guard let core, let entry = core.sfSymbols.entry(id: id) else { return nil }
                return PopoverMenuContent(header: entry.name, items: [
                    PopoverMenuItem(title: "Copy Name", systemImage: "doc.on.doc", shortcut: "↵") { core.copySFSymbol(id: id) },
                    PopoverMenuItem(title: "Copy SwiftUI Code", systemImage: "chevron.left.forwardslash.chevron.right") {
                        core.copySFSymbol(id: id, swiftUI: true)
                    },
                    PopoverMenuItem(title: "Copy PNG", systemImage: "photo", shortcut: "⌘↵") { core.copySFSymbolImage(id: id) },
                    PopoverMenuItem(title: "Copy SVG Template", systemImage: "doc.text") { core.copySFSymbolImage(id: id, format: "svg") },
                    PopoverMenuItem(title: "Open SF Symbols App", systemImage: "arrow.up.forward.app") { openApplication() },
                ])
            },
            onOpen: { [weak core] in
                guard let core else { return }
                core.sfSymbols.start(executable: executableURL)
                core.sfSymbols.observe(core.palette.$query)
            },
            onClose: { [weak core] in core?.sfSymbols.stop() },
            observeChanges: { [weak core] invalidate in
                core?.sfSymbols.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })
        return PluginRegistration(
            metadata: PluginMetadata(id: .sfSymbols, name: "SF Symbols", summary: "Search, preview, and copy Apple's local symbol catalog.",
                systemImage: "square.on.circle", tint: .blue),
            shortcutActions: [PluginActionRegistration(key: .openSFSymbols, perform: open)],
            launcherCommands: [PluginCommandRegistration(id: "command:sf-symbols", name: "SF Symbols",
                systemImage: "square.on.circle", actionKey: .openSFSymbols, perform: open)],
            parameterizedCommand: { [weak core] query in
                guard let argument = SFSymbolCatalog.argument(query) else { return nil }
                return PluginCommandRegistration(id: "command:sf-symbols", name: "SF Symbols: \(argument)",
                    systemImage: "square.on.circle", actionKey: .openSFSymbols, parameterIdentity: argument) {
                    core?.openSFSymbols(query: argument)
                }
            },
            paletteScreen: screen,
            settingsView: { AnyView(SFSymbolSettingsView(open: open)) })
    }

    static func openApplication() {
        guard let url = applicationURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

extension AppCore {
    func openSFSymbols(query: String = "") {
        showPalette(mode: .plugin(.sfSymbols))
        palette.query = query
    }

    func copySFSymbol(id: String, swiftUI: Bool = false) {
        guard let entry = sfSymbols.entry(id: id) else { return }
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(swiftUI ? entry.swiftUI : entry.name)
        hud.show(title: swiftUI ? "SwiftUI Code Copied" : "Symbol Name Copied", symbol: "doc.on.doc")
    }

    func copySFSymbolImage(id: String, format: String = "png") {
        guard let entry = sfSymbols.entry(id: id), let executable = SFSymbolPlugin.executableURL else { return }
        hidePalette(restoreFocus: false)
        Task {
            do {
                let data = try await SFSymbolCLI.export(executable: executable, name: entry.name, format: format)
                if format == "svg" {
                    guard let source = String(data: data, encoding: .utf8) else {
                        throw SFSymbolCatalog.Failure(message: "SF Symbols returned invalid SVG text.")
                    }
                    Paster.copyPlainText(source)
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    guard pasteboard.setData(data, forType: .png) else {
                        throw SFSymbolCatalog.Failure(message: "Could not write the symbol to the clipboard.")
                    }
                }
                hud.show(title: format == "svg" ? "SVG Template Copied" : "Symbol PNG Copied", symbol: "doc.on.doc")
            } catch {
                AppLog.error("sf-symbols", "Export failed: \(error.localizedDescription)")
                hud.show(title: "SF Symbol Export Failed", symbol: "exclamationmark.triangle", isNoOp: true)
            }
        }
    }
}
