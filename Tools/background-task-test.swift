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

        let store = BackgroundTaskStore()
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

        print(failures == 0 ? "\nBackground tasks: ALL PASSED" : "\n\(failures) FAILED")
        if failures > 0 { exit(1) }
    }
}
