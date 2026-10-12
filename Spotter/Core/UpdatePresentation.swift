import Foundation

enum UpdateStatus: Equatable, Sendable {
    case idle, checking, upToDate
    case available(UpdateRelease)
    case installing
    case failed(String)

    var isBusy: Bool { self == .checking || self == .installing }
}

enum UpdateInstallProgress: Equatable, Sendable {
    case downloading(Double?)
    case unpacking, verifying, installing, relaunching

    var fraction: Double? {
        guard case .downloading(let value) = self else { return nil }
        return value
    }

    var title: String {
        switch self {
        case .downloading: "Downloading…"
        case .unpacking: "Unpacking…"
        case .verifying: "Verifying Signature…"
        case .installing: "Installing…"
        case .relaunching: "Relaunching…"
        }
    }

    private var order: Int {
        switch self {
        case .downloading: 0
        case .unpacking: 1
        case .verifying: 2
        case .installing: 3
        case .relaunching: 4
        }
    }

    func accepts(_ next: Self) -> Bool {
        if next.order != order { return next.order > order }
        guard case .downloading(let value) = next else { return true }
        guard let value else { return fraction == nil }
        return value.isFinite && (0...1).contains(value) && value >= (fraction ?? 0)
    }

    static func download(written: Int64, expected: Int64) -> Self {
        .downloading(expected > 0 ? min(1, Double(max(0, written)) / Double(expected)) : nil)
    }
}

enum UpdatePaletteAction: String, Sendable {
    case upgrade, check
}

struct UpdatePresentation {
    let status: UpdateStatus
    let release: UpdateRelease?
    let progress: UpdateInstallProgress?

    var actions: [UpdatePaletteAction] { status == .checking || status == .upToDate || release == nil ? [.check] : [.upgrade] }

    func action(at index: Int) -> UpdatePaletteAction {
        actions[min(max(index, 0), actions.count - 1)]
    }

    func primaryTitle(at index: Int) -> String? {
        guard !status.isBusy, status != .upToDate else { return nil }
        return action(at: index) == .check ? "Check for Updates" : (release?.zipAssetURL == nil ? "View Release" : "Install Update")
    }

    var checkDetail: String? {
        switch status {
        case .checking: "Checking GitHub…"
        case .upToDate: "You're on the latest version."
        case .failed(let message): message
        default: nil
        }
    }

    var title: String {
        switch status {
        case .checking: return "Checking…"
        case .upToDate: return "You’re on the latest version"
        case .installing: return progress?.title ?? "Installing…"
        default: return action(at: 0) == .upgrade
            ? (release?.zipAssetURL == nil ? "View Release" : "Download and Install Update") : "Check for Updates"
        }
    }

    func detail(currentVersion: String) -> String? {
        if case .failed(let message) = status { return message }
        guard action(at: 0) == .upgrade, let release else { return nil }
        let versions = "\(currentVersion) → \(release.version.description)"
        if let fraction = progress?.fraction, status == .installing { return versions + " · \(Int(fraction * 100))%" }
        return versions
    }

    func selection(after previous: [UpdatePaletteAction], index: Int) -> Int {
        0
    }
}
