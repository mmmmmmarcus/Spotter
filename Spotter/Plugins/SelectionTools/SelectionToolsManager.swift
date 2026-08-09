import Combine

/// The remaining Selection Tools state is only the explicit failure surface for browser search.
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
