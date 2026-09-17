import Foundation

@MainActor
final class AppResourceMonitor {
    private var timer: Timer?
    private var lastReportedCount: Int?

    func start() {
        guard timer == nil else { return }
        do {
            let limits = try AppFileResources.prepare()
            AppLog.info("file-resources", "Descriptor soft limit: \(limits.rlim_cur); hard limit: \(limits.rlim_max)")
        } catch {
            AppLog.error("file-resources", "Could not raise descriptor limit: \(error.localizedDescription)")
        }
        record()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.record() }
        }
        timer?.tolerance = 10
    }

    func record() {
        guard let snapshot = AppFileResources.snapshot() else { return }
        let previous = lastReportedCount
        guard previous == nil || abs(snapshot.count - previous!) >= 64 else { return }
        lastReportedCount = snapshot.count
        if UInt64(snapshot.count) >= snapshot.limit - snapshot.limit / 4 {
            AppLog.error("file-resources", snapshot.summary)
        } else {
            AppLog.info("file-resources", snapshot.summary)
        }
    }

    isolated deinit { timer?.invalidate() }
}
