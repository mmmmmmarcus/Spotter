import Combine
import Foundation

/// Search's whole state: whether the last run failed, and why. The plugin keeps its historical
/// `selection-tools` identity, so the type keeps its name too.
@MainActor
final class SelectionToolsManager: ObservableObject {
    @Published private(set) var state: SelectionToolsState = .idle

    func showFailure(_ message: String) {
        state = .failed(message)
    }

    func reset() {
        state = .idle
    }
}
