import AppKit
import Combine
import Foundation

/// Backs the music card: what Apple Music is playing, its artwork, and the three transport controls.
///
/// Everything here goes through one Apple Event, run as an `osascript` subprocess off the main actor
/// exactly like `Core/FinderSelection` — macOS's own Automation prompt is the gate, and a refused
/// grant reads as "nothing playing" rather than an error. Music is never launched: the store checks
/// that it is already running first, because `tell application "Music"` would start it.
@MainActor
final class DashboardMusicStore: ObservableObject {
    @Published private(set) var snapshot: DashboardMusicSnapshot = .idle
    @Published private(set) var artwork: NSImage?

    static let musicBundleIdentifier = "com.apple.Music"
    /// Slow enough not to spawn a subprocess every tick, often enough that a track change the
    /// notification missed still lands within a glance.
    private static let pollInterval: TimeInterval = 3

    private var timer: Timer?
    private var notificationToken: NotificationToken?
    private var isRefreshing = false
    private var artworkTrackID: String?
    private var isVisible = false

    private let artworkURL: URL = {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.spotter.app1"
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("music-artwork.dat")
    }()

    isolated deinit {
        timer?.invalidate()
    }

    /// Called when the strip appears. Polling only while the launcher is on screen is the whole
    /// budget for this card: a closed palette asks Music nothing.
    func start() {
        guard !isVisible else { return }
        isVisible = true
        observePlayerInfo()
        refresh()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        isVisible = false
        timer?.invalidate()
        timer = nil
        notificationToken = nil
    }

    func playPause() {
        control("playpause")
    }

    func nextTrack() {
        control("next track")
    }

    func previousTrack() {
        // Music's own "previous" restarts the track a few seconds in, which is what the button means
        // in every player; leave that behaviour to Music rather than second-guessing it here.
        control("previous track")
    }

    private func control(_ command: String) {
        guard Self.isMusicRunning else { return }
        Task {
            _ = await Self.runScript("tell application \"Music\" to \(command)")
            // Music applies the change asynchronously; one short beat before re-reading avoids
            // drawing the state the user just left.
            try? await Task.sleep(for: .milliseconds(180))
            refresh()
        }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        guard Self.isMusicRunning else {
            snapshot = .idle
            artwork = nil
            artworkTrackID = nil
            return
        }
        isRefreshing = true
        Task { [weak self] in
            let output = await Self.runScript(DashboardMusicScripts.reader)
            guard let self else { return }
            isRefreshing = false
            let fresh = output.map(DashboardMusicEngine.snapshot(fromScriptOutput:))
                ?? DashboardMusicSnapshot(isRunning: true, state: .stopped, track: nil)
            snapshot = fresh
            await refreshArtwork(for: fresh.track)
        }
    }

    /// Artwork is re-read only when the track itself changes: it is the one expensive part of this
    /// card, and it cannot change under a track that hasn't.
    private func refreshArtwork(for track: DashboardTrack?) async {
        guard let track else {
            artwork = nil
            artworkTrackID = nil
            return
        }
        guard track.id != artworkTrackID else { return }
        artworkTrackID = track.id
        let url = artworkURL
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard runScriptSync(DashboardMusicScripts.artwork, arguments: [url.path]) == "ok",
                let data = try? Data(contentsOf: url)
            else { return nil }
            return NSImage(data: data)
        }.value
        // A slower artwork read must not overwrite the track that replaced it mid-flight.
        guard artworkTrackID == track.id else { return }
        artwork = image
    }

    /// Music posts this on every track and state change, so the card reacts immediately and the
    /// poll only has to cover what a missed notification would leave stale.
    private func observePlayerInfo() {
        guard notificationToken == nil else { return }
        let center = DistributedNotificationCenter.default()
        notificationToken = NotificationToken(
            center.addObserver(
                forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            center: center)
    }

    private static var isMusicRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == musicBundleIdentifier
        }
    }

    private static func runScript(_ source: String, arguments: [String] = []) async -> String? {
        await Task.detached(priority: .userInitiated) {
            runScriptSync(source, arguments: arguments)
        }.value
    }


}

/// Off the main actor by construction — every caller hops off first. A refused Automation grant
/// exits non-zero, which reads here as no answer at all.
private nonisolated func runScriptSync(_ source: String, arguments: [String] = []) -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", source] + arguments
    process.standardOutput = output
    process.standardError = Pipe()
    guard (try? process.run()) != nil else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    // Trimmed here rather than at each call site: osascript always answers with a trailing newline,
    // and a caller comparing the answer to a bare "ok" would never match.
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// The two Apple Events this card sends, held outside the actor so a detached run can read them.
private enum DashboardMusicScripts {
    static let reader = """
        tell application "Music"
            set sep to (character id 31)
            set stateText to (player state as text)
            if stateText is "stopped" then return "stopped"
            try
                set currentSong to current track
            on error
                return "stopped"
            end try
            set answer to stateText & sep & (persistent ID of currentSong)
            set answer to answer & sep & (name of currentSong)
            set answer to answer & sep & (artist of currentSong)
            set answer to answer & sep & (album of currentSong)
            set answer to answer & sep & ((duration of currentSong) as text)
            return answer
        end tell
        """

    /// Writes the current track's artwork bytes to the path it is handed. AppleScript is the only
    /// way to reach them; returning them through stdout would mean encoding binary as text.
    static let artwork = """
        on run argv
            set outPath to item 1 of argv
            tell application "Music"
                if player state is stopped then return "none"
                try
                    set artworkData to raw data of artwork 1 of current track
                on error
                    return "none"
                end try
            end tell
            try
                set f to open for access (POSIX file outPath) with write permission
                set eof f to 0
                write artworkData to f
                close access f
            on error
                try
                    close access (POSIX file outPath)
                end try
                return "none"
            end try
            return "ok"
        end run
        """
}
