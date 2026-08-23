import Foundation

/// The Finder's current selection, read through one Apple Event off the main actor. Only the Finder
/// can answer this, so a refused Automation grant reads as an empty selection rather than an error —
/// every caller already treats "nothing selected" as the ordinary case.
enum FinderSelection {
    private static let script = """
        tell application "Finder" to set selectedItems to selection as alias list
        set output to ""
        repeat with selectedItem in selectedItems
            set output to output & POSIX path of selectedItem & linefeed
        end repeat
        return output
        """

    static func selectedURLs() async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = output
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return [] }
            // Drained before the wait: a few thousand selected paths outrun the pipe buffer, and
            // waiting first would then block on a child that is itself blocked writing.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            return (String(data: data, encoding: .utf8) ?? "")
                .split(whereSeparator: \.isNewline)
                .map { URL(fileURLWithPath: String($0)) }
        }.value
    }
}
