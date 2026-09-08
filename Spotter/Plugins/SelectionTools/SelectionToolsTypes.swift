import Foundation

/// Search has nothing to show when it works — the browser does — so its palette screen only ever
/// reports what went wrong on the way there.
enum SelectionToolsState: Equatable, Sendable {
    case idle
    case failed(String)
}
