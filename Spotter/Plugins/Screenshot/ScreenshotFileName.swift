import Foundation

/// Names a capture after the app it was taken from. The name is also the only marker that says a
/// clipboard entry is a Spotter screenshot: deriving that from the file name keeps improving the
/// rule a code change rather than a column, a migration and a backfill.
enum ScreenshotFileName {
    static let marker = "SpotterScreenshot"

    /// `Claude_SpotterScreenshot_2608041812` — app, marker, then `yyMMddHHmm`, which sorts
    /// chronologically as plain text and stays short enough to read in a Save dialog.
    static func name(
        forApp appName: String?, at date: Date, timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyMMddHHmm"
        let stamp = formatter.string(from: date)
        guard let app = sanitized(appName) else { return "\(marker)_\(stamp)" }
        return "\(app)_\(marker)_\(stamp)"
    }

    /// Whether a file name was written by this scheme. Matched on the marker alone, so a capture
    /// with no app name, or one renamed around its marker, still reads as a screenshot.
    static func isScreenshot(fileName: String) -> Bool {
        fileName.contains(marker)
    }

    /// App names carry spaces and the odd separator; a file name should carry neither.
    private static func sanitized(_ appName: String?) -> String? {
        guard let appName else { return nil }
        let cleaned = appName.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "."
        }
        let name = String(String.UnicodeScalarView(cleaned))
        return name.isEmpty ? nil : name
    }
}
