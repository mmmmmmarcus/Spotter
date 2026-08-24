import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        AppIdentityMigration.runForCurrentApp()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCore.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The Hyper Key's HID-level caps remap outlives the process; give the key back.
        AppCore.shared.hyperKeyTap.prepareForTermination()
        // The uptime tallies are coalesced between timer ticks; write the last few seconds out.
        AppCore.shared.uptime.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }
}
