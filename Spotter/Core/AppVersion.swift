import Foundation

struct AppVersion: Equatable, Sendable {
    let short: String
    let build: String

    init(short: String?, build: String?) {
        self.short = short?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "—"
        self.build = build?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "—"
    }

    init(bundle: Bundle) {
        self.init(
            short: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }

    var aboutLabel: String { "Version \(short) (\(build))" }

    static let current = AppVersion(bundle: .main)
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
