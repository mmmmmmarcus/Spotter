import Combine
import UIKit

/// The iOS app's single owner, as `AppCore` is on the Mac: it holds the shared Note store and folder sync manager and drives them through the app's lifecycle.
@MainActor
final class NotesModel: ObservableObject {
    let store: NoteStore
    let sync: NoteFolderSyncManager

    /// How sync wording names this device, where the Mac says "this Mac".
    static var device: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "this iPad" : "this iPhone"
    }

    private var activation = 0
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    init() {
        store = NoteStore()
        sync = NoteFolderSyncManager(
            store: store, location: .bookmark(defaults: .standard),
            io: NoteFolderIO(trash: Self.trash),
            device: Self.device)
        sweepEmptyNotes(keeping: nil)
    }

    /// Re-resolves the folder, reopens its security scope, restores the watcher and runs a pass.
    func activate() {
        activation += 1
        endBackgroundTask()
        sync.start()
    }

    /// iOS requires file presenters gone while suspended, so the last edits are flushed and synced first, then the watcher and the folder's security scope are released.
    func suspend() {
        activation += 1
        let suspended = activation
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Notes sync") { [weak self] in
            self?.finishSuspending(suspended)
        }
        Task {
            await store.flush()
            await sync.syncNow()
            finishSuspending(suspended)
        }
    }

    /// The store selects what it creates, which is what puts a new Note on screen.
    func createNote() {
        store.createNote()
        store.requestEditorFocus()
    }

    /// The store edits its selected Note, so the Note on screen is selected before its text is written.
    func update(_ content: String, for id: UUID) {
        if store.selectedID != id { store.selectedID = id }
        store.updateSelectedContent(content)
    }

    /// Whitespace-only Notes are removed as normal deletions once nothing is showing them, as closing the Notes window does on the Mac.
    func sweepEmptyNotes(keeping open: UUID?) {
        for note in store.notes where note.id != open && NoteEngine.isEmptyDraft(note.content) {
            store.delete(note)
        }
    }

    private func finishSuspending(_ suspended: Int) {
        // A return to the foreground before the flush finished already restarted sync; it must not be stopped again.
        guard suspended == activation else { return }
        sync.stop()
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// A folder whose volume has no Trash keeps the file rather than deleting it outright; every other Trash failure stays an error.
    private static let trash: @Sendable (URL) throws -> Void = { url in
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch let error as CocoaError where error.code == .featureUnsupported {
            throw NoteFolderIO.TrashUnavailable()
        }
    }
}
