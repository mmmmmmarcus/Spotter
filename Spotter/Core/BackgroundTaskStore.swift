import Combine
import Foundation

struct BackgroundTaskItem: Identifiable, Equatable, Codable, Sendable {
    enum State: String, Codable, Equatable, Sendable {
        case running
        case done
        case failed

        var isDismissible: Bool { self != .running }

        var label: String {
            switch self {
            case .running: "Running"
            case .done: "Done"
            case .failed: "Failed"
            }
        }

        var systemImage: String {
            switch self {
            case .running: "hourglass"
            case .done: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }
    }

    let id: UUID
    let title: String
    let systemImage: String
    let ownerID: UUID?
    fileprivate(set) var detail: String
    fileprivate(set) var progress: Double?
    fileprivate(set) var state: State

    var isDismissible: Bool { state.isDismissible }

    init(
        id: UUID, title: String, systemImage: String, detail: String, progress: Double?,
        state: State, ownerID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.ownerID = ownerID
        self.detail = detail
        self.progress = progress
        self.state = state
    }
}

/// Owns the launcher-visible lifetime and progress snapshot while each feature manager keeps owning its work.
@MainActor
final class BackgroundTaskStore: ObservableObject {
    @Published private(set) var tasks: [BackgroundTaskItem] = []
    private let ownerID: UUID
    private var executingIDs: Set<UUID> = []
    /// Where Return sends the user while a row is still running. Process-local by necessity: a
    /// closure cannot be synced, and a row mirrored from another Mac has no local work to open.
    private var activations: [UUID: () -> Void] = [:]

    init(defaults: UserDefaults = .standard) {
        let key = "background-tasks.owner-id"
        if let stored = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) {
            ownerID = stored
        } else {
            let created = UUID()
            ownerID = created
            defaults.set(created.uuidString, forKey: key)
        }
    }

    @discardableResult
    func begin(
        title: String, detail: String = "Starting…", systemImage: String = "gearshape.2",
        id: UUID = UUID(), onOpen: (() -> Void)? = nil
    ) -> UUID {
        executingIDs.insert(id)
        activations[id] = onOpen
        tasks.insert(
            BackgroundTaskItem(
                id: id, title: title, systemImage: systemImage, detail: detail,
                progress: nil, state: .running, ownerID: ownerID),
            at: 0)
        return id
    }

    func update(id: UUID, detail: String, progress: Double?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
            tasks[index].state == .running
        else { return }
        tasks[index].detail = detail
        tasks[index].progress = progress.map { min(max($0, 0), 1) }
    }

    func complete(id: UUID, detail: String) {
        finish(id: id, detail: detail, state: .done)
    }

    func fail(id: UUID, detail: String) {
        finish(id: id, detail: detail, state: .failed)
    }

    func dismiss(id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }), task.isDismissible else { return }
        activations[id] = nil
        tasks.removeAll { $0.id == id }
    }

    func discard(id: UUID) {
        executingIDs.remove(id)
        activations[id] = nil
        tasks.removeAll { $0.id == id }
    }

    /// Return on a running row jumps to whatever surface owns the work. Reports `false` when the row
    /// has no interface to show — a remote row, or a feature whose work has no screen of its own.
    @discardableResult
    func open(id: UUID) -> Bool {
        guard let activation = activations[id] else { return false }
        activation()
        return true
    }

    func canOpen(id: UUID) -> Bool { activations[id] != nil }

    /// A remote snapshot mirrors rows without detaching live work or reviving this Mac's dead executor.
    func replace(tasks newTasks: [BackgroundTaskItem]) {
        let liveLocal = tasks.filter { executingIDs.contains($0.id) }
        let liveIDs = Set(liveLocal.map(\.id))
        let imported = newTasks.filter { !liveIDs.contains($0.id) }.map { task in
            guard task.state == .running, task.ownerID == ownerID else { return task }
            var interrupted = task
            interrupted.detail = "Interrupted when Spotter last quit."
            interrupted.progress = nil
            interrupted.state = .failed
            return interrupted
        }
        tasks = liveLocal + imported
        activations = activations.filter { liveIDs.contains($0.key) }
    }

    private func finish(id: UUID, detail: String, state: BackgroundTaskItem.State) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
            tasks[index].state == .running
        else { return }
        tasks[index].detail = detail
        tasks[index].progress = state == .done ? 1 : nil
        tasks[index].state = state
        executingIDs.remove(id)
        // A finished row's only action is Dismiss; the work it pointed at is over.
        activations[id] = nil
    }
}
