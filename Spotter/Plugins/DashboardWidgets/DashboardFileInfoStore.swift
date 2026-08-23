import AppKit
import Combine

/// The Finder selection as the launcher last read it. Owned by `AppCore` and refreshed only when the
/// palette is summoned, so nothing polls and nothing runs while the palette is closed.
@MainActor
final class DashboardFileInfoStore: ObservableObject {
    @Published private(set) var snapshot = DashboardFileInfoSnapshot()

    /// Bumped by every refresh so a read that lands after a newer one is discarded, not applied.
    private var readToken = 0

    /// `frontmost` is the app the palette would return focus to. Only the Finder's own selection is
    /// current, so any other app clears the card instead of leaving yesterday's file on screen.
    func refresh(frontmost: NSRunningApplication?) {
        guard frontmost?.bundleIdentifier == "com.apple.finder" else {
            clear()
            return
        }
        readToken += 1
        let token = readToken
        // The previous snapshot stays up while the read runs: the Finder is still frontmost, so it is
        // almost always the same selection, and clearing first would flash the card away and back.
        Task { [weak self] in
            let snapshot = await DashboardFileInfoReader.read()
            guard let self, token == self.readToken else { return }
            self.snapshot = snapshot
        }
    }

    func clear() {
        readToken += 1
        guard !snapshot.isEmpty else { return }
        snapshot = DashboardFileInfoSnapshot()
    }
}
