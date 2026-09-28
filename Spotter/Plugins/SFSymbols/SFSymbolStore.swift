import Combine
import Foundation

@MainActor
final class SFSymbolStore: ObservableObject {
    typealias Search = @Sendable (URL, String) async throws -> [SFSymbolEntry]
    @Published private(set) var results: [SFSymbolEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var executable: URL?
    private var searchTask: Task<Void, Never>?
    private var queryObserver: AnyCancellable?
    private let searchOperation: Search

    init(search: @escaping Search = { try await SFSymbolCLI.search(executable: $0, query: $1) }) {
        searchOperation = search
    }

    func start(executable: URL?) {
        stop()
        results = []
        errorMessage = nil
        self.executable = executable
        guard executable != nil else {
            errorMessage = "Update SF Symbols to version 27 or later in System Settings → Software Update, then reopen this page."
            return
        }
        search("")
    }

    func observe(_ queries: some Publisher<String, Never>) {
        queryObserver = queries.sink { [weak self] in self?.search($0) }
    }

    func search(_ query: String) {
        searchTask?.cancel()
        guard let executable else { return }
        isLoading = true
        errorMessage = nil
        searchTask = Task { [weak self, searchOperation] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                _ = try SFSymbolCatalog.searchArguments(query)
                let entries = try await searchOperation(executable, query)
                guard !Task.isCancelled, let self else { return }
                results = entries
                isLoading = false
                searchTask = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                results = []
                errorMessage = error.localizedDescription
                isLoading = false
                searchTask = nil
            }
        }
    }

    func stop() {
        searchTask?.cancel()
        searchTask = nil
        queryObserver = nil
        executable = nil
        isLoading = false
    }

    func entry(id: String) -> SFSymbolEntry? { results.first { $0.id == id } }
}
