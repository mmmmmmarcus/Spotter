import Foundation

@main
@MainActor
struct BackgroundTaskTests {
    static func main() {
        var failures = 0
        func check(_ message: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message)")
            }
        }

        let suiteName = "spotter.background-task.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BackgroundTaskStore(defaults: defaults)
        let first = UUID()
        let second = UUID()
        store.begin(title: "First", id: first)
        store.begin(title: "Second", id: second)
        check("new tasks appear first", store.tasks.map(\.id) == [second, first])
        check("running tasks cannot be dismissed", {
            store.dismiss(id: second)
            return store.tasks.count == 2
        }())

        store.update(id: first, detail: "Halfway", progress: 1.4)
        check("progress is clamped", store.tasks.last?.progress == 1)
        check("progress detail updates", store.tasks.last?.detail == "Halfway")

        store.complete(id: second, detail: "Finished")
        check("completion stays visible", store.tasks.first?.state == .done)
        check("completion reaches full progress", store.tasks.first?.progress == 1)
        store.dismiss(id: second)
        check("completed tasks dismiss", store.tasks.map(\.id) == [first])

        store.fail(id: first, detail: "Nope")
        check("failures stay visible", store.tasks.first?.state == .failed)
        check("failures are indeterminate", store.tasks.first?.progress == nil)
        store.dismiss(id: first)
        check("failed tasks dismiss", store.tasks.isEmpty)

        let cancelled = UUID()
        store.begin(title: "Cancelled", id: cancelled)
        store.discard(id: cancelled)
        check("feature cancellation discards a running task", store.tasks.isEmpty)

        let localRunning = UUID()
        store.begin(title: "Still running here", id: localRunning)
        let remoteDone = BackgroundTaskItem(
            id: UUID(), title: "Remote task", systemImage: "checkmark",
            detail: "Finished elsewhere", progress: 1, state: .done)
        store.replace(tasks: [remoteDone])
        check(
            "sync preserves a locally executing task",
            store.tasks.map(\.id) == [localRunning, remoteDone.id])
        let encoded = try! JSONEncoder().encode(store.tasks)
        let decoded = try! JSONDecoder().decode([BackgroundTaskItem].self, from: encoded)
        check("task rows round-trip through sync JSON", decoded == store.tasks)

        let relaunched = BackgroundTaskStore(defaults: defaults)
        relaunched.replace(tasks: decoded)
        check(
            "a relaunched owner marks orphaned work failed",
            relaunched.tasks.first(where: { $0.id == localRunning })?.state == .failed)

        print(failures == 0 ? "\nBackground tasks: ALL PASSED" : "\n\(failures) FAILED")
        if failures > 0 { exit(1) }
    }
}
