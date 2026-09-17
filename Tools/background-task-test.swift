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
        var startedCalledOff = false
        store.begin(
            title: "Uninstalling Figma", id: started, queued: true,
            onCancel: { startedCalledOff = true })
        store.markRunning(id: started, detail: "Removing…")
        check("a queued row can take its turn", store.tasks.first?.state == .running)
        check("a row keeps its call-off until its feature retires it", store.canCancel(id: started))
        store.dropCancellation(id: started)
        check("work past the point of no return offers nothing", !store.canCancel(id: started))
        check("retiring the call-off leaves the row running", store.tasks.first?.state == .running)
        check("and it can no longer be called off", {
            store.cancel(id: started)
            return !startedCalledOff
        }())
        store.fail(id: started, detail: "Mole couldn't remove Figma")
        check("a failed run reports how it ended", store.tasks.first?.state == .failed)
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
            store.tasks.map(\.id) == [localRunning])
        check("old completed sync rows are ignored", !store.tasks.contains { $0.id == remoteDone.id })
        let encoded = try! JSONEncoder().encode(store.syncTasks)
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

        let notifications = BackgroundTaskStore(defaults: defaults)
        var opened = false
        var cancelledLive = false
        let live = notifications.begin(title: "Live", onOpen: { opened = true }, onCancel: { cancelledLive = true })
        let queued = notifications.begin(title: "Queued", queued: true)
        let shown = notifications.begin(title: "Shown success")
        let unseen = notifications.begin(title: "Unseen success")
        let failed = notifications.begin(title: "Failure")
        let staleLiveSnapshot = notifications.syncTasks
        notifications.complete(id: shown, detail: "Done")
        notifications.complete(id: unseen, detail: "Done")
        notifications.fail(id: failed, detail: "Error")
        check("only queued and running rows are exported", Set(notifications.syncTasks.map(\.id)) == [live, queued])
        let remoteRunning = BackgroundTaskItem(
            id: UUID(), title: "Remote live", systemImage: "gear", detail: "Working",
            progress: nil, state: .running, ownerID: UUID())
        let remoteFailed = BackgroundTaskItem(
            id: UUID(), title: "Old failure", systemImage: "gear", detail: "Error",
            progress: nil, state: .failed, ownerID: UUID())
        notifications.replace(tasks: [remoteDone, remoteFailed, remoteRunning])
        check("local success survives unrelated sync", notifications.tasks.contains { $0.id == unseen && $0.state == .done })
        check("local failure survives unrelated sync", notifications.tasks.contains { $0.id == failed && $0.state == .failed })
        check("remote live progress is imported", notifications.tasks.contains { $0.id == remoteRunning.id })
        check("terminal remote notifications never import", !notifications.tasks.contains { $0.id == remoteDone.id || $0.id == remoteFailed.id })
        notifications.open(id: live)
        notifications.cancel(id: live)
        check("sync preserves live callbacks", opened && cancelledLive)
        notifications.dismissSeenCompletions()
        check("closing before seeing a success keeps it", notifications.tasks.contains { $0.id == shown })
        notifications.markCompletionsSeen(ids: [shown, failed, live, queued])
        notifications.dismissSeenCompletions()
        check("closing dismisses the seen success", !notifications.tasks.contains { $0.id == shown })
        check("closing preserves unseen success", notifications.tasks.contains { $0.id == unseen })
        check("closing preserves failure and live work", Set(notifications.tasks.map(\.id)).isSuperset(of: [failed, live, queued]))
        notifications.replace(tasks: staleLiveSnapshot + [remoteDone, remoteFailed])
        check("stale sync cannot revive a dismissed completion", !notifications.tasks.contains { $0.id == shown })
        check("stale running snapshot cannot overwrite completion", notifications.tasks.first { $0.id == unseen }?.state == .done)
        notifications.dismiss(id: unseen)
        notifications.replace(tasks: staleLiveSnapshot)
        check("manual dismissal also survives stale sync", !notifications.tasks.contains { $0.id == unseen })
        check("interrupted failures do not re-export", afterQuit.syncTasks.isEmpty)
        afterQuit.dismiss(id: orphanedQueue)
        afterQuit.replace(tasks: orphanedSnapshot)
        check("dismissed interruption cannot return in this process", afterQuit.tasks.isEmpty)

        print(failures == 0 ? "\nBackground tasks: ALL PASSED" : "\n\(failures) FAILED")
        if failures > 0 { exit(1) }
    }
}
