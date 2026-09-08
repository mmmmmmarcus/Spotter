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

        // Queued rows: live work the feature has not started, and only the feature calls it off.
        let waiting = UUID()
        var calledOff: [UUID] = []
        store.begin(
            title: "Uninstalling Zoom", detail: "Queued · next in line", id: waiting, queued: true,
            onCancel: { calledOff.append(waiting) })
        check("a queued row reads as queued", store.tasks.first?.state == .queued)
        check("a queued row cannot be dismissed", {
            store.dismiss(id: waiting)
            return store.tasks.contains { $0.id == waiting }
        }())
        check("a queued row offers cancellation", store.canCancel(id: waiting))
        check("progress belongs to running work only", {
            store.update(id: waiting, detail: "Halfway", progress: 0.5)
            return store.tasks.first?.progress == nil && store.tasks.first?.detail != "Halfway"
        }())
        check("the line can be renumbered in place", {
            store.markQueued(id: waiting, detail: "Queued · #2 in line")
            return store.tasks.first?.detail == "Queued · #2 in line"
        }())
        check("cancelling hands off to the feature, not the store", {
            store.cancel(id: waiting)
            return calledOff == [waiting] && store.tasks.contains { $0.id == waiting }
        }())
        check("the feature's discard is what removes the row", {
            store.discard(id: waiting)
            return !store.tasks.contains { $0.id == waiting }
        }())

        let started = UUID()
        store.begin(title: "Uninstalling Figma", id: started, queued: true, onCancel: {})
        store.markRunning(id: started, detail: "Removing…")
        check("a queued row can take its turn", store.tasks.first?.state == .running)
        check("a running row still offers cancellation", store.canCancel(id: started))
        store.fail(id: started, detail: "Stopped before it finished")
        check("a stopped run reports how it ended", store.tasks.first?.state == .failed)
        check("a finished row is past cancelling", !store.canCancel(id: started))
        check("a finished row never restarts", {
            store.markRunning(id: started, detail: "Again")
            return store.tasks.first?.state == .failed
        }())
        store.dismiss(id: started)

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

        let orphanedQueue = UUID()
        let queuedOwner = BackgroundTaskStore(defaults: defaults)
        queuedOwner.begin(title: "Uninstalling Slack", id: orphanedQueue, queued: true)
        let orphanedSnapshot = try! JSONDecoder().decode(
            [BackgroundTaskItem].self, from: try! JSONEncoder().encode(queuedOwner.tasks))
        let afterQuit = BackgroundTaskStore(defaults: defaults)
        afterQuit.replace(tasks: orphanedSnapshot)
        check(
            "a queued promise this Mac can no longer keep is retired too",
            afterQuit.tasks.first(where: { $0.id == orphanedQueue })?.state == .failed)

        print(failures == 0 ? "\nBackground tasks: ALL PASSED" : "\n\(failures) FAILED")
        if failures > 0 { exit(1) }
    }
}
