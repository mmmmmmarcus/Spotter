import AppKit
import Combine

@MainActor
final class RaycastStoreController: ObservableObject {
    unowned let core: AppCore
    @Published private(set) var results: [ExtensionListing] = []
    @Published private(set) var status: String?
    @Published private(set) var busy = false
    @Published private(set) var searching = false
    private var searchTask: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var searchID = UUID()
    private var operationID = UUID()

    init(core: AppCore) { self.core = core }

    func close() {
        searchID = UUID()
        operationID = UUID()
        searchTask?.cancel()
        operation?.cancel()
        searchTask = nil
        operation = nil
        busy = false
        searching = false
    }

    func queryChanged(_ query: String) {
        searchTask?.cancel()
        searchID = UUID()
        let id = searchID
        results = []
        if !busy { status = nil }
        searching = false
        guard core.extensionCoordinator.enabled, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            ExtensionGitHubSource(query) == nil else { return }
        searching = true
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                let found = try await core.extensions.searchStore(query)
                try Task.checkCancellation()
                guard searchID == id else { return }
                results = found
            } catch {
                if searchID == id, !Task.isCancelled { status = error.localizedDescription }
            }
            if searchID == id { searching = false }
        }
    }

    func snapshot(query: String) -> PluginPaletteSnapshot {
        RaycastStorePresentation.snapshot(query: query, enabled: core.extensionCoordinator.enabled,
            busy: busy, searching: searching, status: status, results: results,
            installedNames: Set(core.extensions.installed.map(\.id)))
    }

    func activate(_ id: String, query: String) {
        if id == "cancel" { close(); status = "Installation cancelled."; return }
        guard !busy else { return }
        if id == "enable" { core.extensionCoordinator.setEnabled(true); return }
        guard core.extensionCoordinator.enabled else { return }
        switch id {
        case "source":
            guard let source = ExtensionGitHubSource(query) else { return }
            run {
                let owner = try await self.core.extensions.install(source,
                    packageManager: self.core.extensionCoordinator.packageManager,
                    additionalSearchPaths: self.core.extensionCoordinator.customSearchPaths.split(separator: "\n").map(String.init),
                    onProgress: self.progress())
                self.setStatus("Installed \(owner.title). Settings are in the Raycast Extension sidebar group.")
            }
        case "local":
            let picker = NSOpenPanel()
            picker.canChooseDirectories = true
            picker.canChooseFiles = false
            guard picker.runModal() == .OK, let url = picker.url else { return }
            run { try await self.core.extensions.install(from: url); self.setStatus("Extension imported.") }
        case "raycast":
            run {
                let candidates = await self.core.extensions.raycastImportCandidates().filter { !$0.isInstalled }
                guard !candidates.isEmpty else { self.setStatus("No new built extensions found in Raycast."); return }
                try Task.checkCancellation()
                let alert = NSAlert()
                alert.messageText = "Import \(candidates.count) extensions?"
                alert.informativeText = candidates.map { $0.installed.title }.joined(separator: ", ")
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Import")
                guard alert.runModal() == .alertSecondButtonReturn else { return }
                let failed = await self.core.extensions.importAllFromRaycast(candidates.map(\.installed))
                self.setStatus(failed.isEmpty ? "Import complete." : "Could not import: " + failed.joined(separator: ", "))
            }
        case "updates": run { await self.core.extensions.checkForUpdates(); self.setStatus("\(self.core.extensions.updates.count) updates available.") }
        case "update-all": run {
            let failed = await self.core.extensions.update(Array(self.core.extensions.updates.keys))
            self.setStatus(failed.isEmpty ? "Extensions are up to date." : failed.joined(separator: "\n"))
        }
        case "clean": run {
            let installed = Set(self.core.extensions.installed.map(\.id))
            let roots = ExtensionCleanup.defaultRoots()
            let report = await Task.detached { ExtensionCleanup.reclaimable(installed: installed, in: roots) }.value
            guard !report.isEmpty else { self.setStatus("No unused extension data."); return }
            try Task.checkCancellation()
            let alert = NSAlert()
            alert.messageText = "Remove unused extension data?"
            alert.informativeText = "Removes \(report.items) unused items (\(ExtensionCleanup.formatted(bytes: report.bytes))). Installed extensions are retained."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Clean")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            let removed = await Task.detached { ExtensionCleanup.clean(installed: installed, in: roots) }.value
            self.setStatus("Removed \(removed.items) unused items.")
        }
        default:
            guard let listing = results.first(where: { "listing:" + $0.id == id }) else { return }
            run {
                try await self.core.extensions.install(listing, onProgress: self.progress())
                self.setStatus("Installed \(listing.title). Settings are in the Raycast Extension sidebar group.")
            }
        }
    }

    private func setStatus(_ message: String) {
        guard !Task.isCancelled else { return }
        status = message
    }

    private func progress() -> @Sendable (ExtensionInstaller.Progress) -> Void {
        let id = operationID
        return { [weak self] progress in
            Task { @MainActor in
                guard let self, self.operationID == id, self.busy else { return }
                self.status = progress.message
            }
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        operationID = UUID()
        let id = operationID
        busy = true
        status = "Preparing…"
        operation = Task {
            defer { if operationID == id { busy = false } }
            do { try Task.checkCancellation(); try await work() }
            catch { if operationID == id, !Task.isCancelled { status = error.localizedDescription } }
        }
    }
}
