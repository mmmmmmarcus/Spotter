import Combine
import Foundation

struct BackgroundTaskItem: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
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
    fileprivate(set) var detail: String
    fileprivate(set) var progress: Double?
    fileprivate(set) var state: State

    var isDismissible: Bool { state.isDismissible }
}

/// Owns the launcher-visible lifetime and progress snapshot while each feature manager keeps owning its work.
@MainActor
final class BackgroundTaskStore: ObservableObject {
    @Published private(set) var tasks: [BackgroundTaskItem] = []

    @discardableResult
    func begin(
        title: String, detail: String = "Starting…", systemImage: String = "gearshape.2",
        id: UUID = UUID()
    ) -> UUID {
        tasks.insert(
            BackgroundTaskItem(
                id: id, title: title, systemImage: systemImage, detail: detail,
                progress: nil, state: .running),
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
        tasks.removeAll { $0.id == id }
    }

    private func finish(id: UUID, detail: String, state: BackgroundTaskItem.State) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
            tasks[index].state == .running
        else { return }
        tasks[index].detail = detail
        tasks[index].progress = state == .done ? 1 : nil
        tasks[index].state = state
    }
}
