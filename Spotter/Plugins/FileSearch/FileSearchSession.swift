import Combine
import Foundation

/// Owns one debounced, serialized Spotlight search. Nothing is cached, watched or retained between
/// searches: the session holds at most one pending query, runs one search at a time, and drops any
/// result whose query has been superseded or cleared.
@MainActor
final class FileSearchSession: ObservableObject {
    typealias SearchOperation = @Sendable (String, String, URL) async throws -> [FileSearchResult]

    enum State: Equatable {
        case idle
        case searching
        case ready
        case failed
    }

    @Published private(set) var results: [FileSearchResult] = []
    @Published private(set) var state: State = .idle

    private var query = ""
    /// Bumped on every request and on every cancel; a finished search publishes only if it still matches.
    private var revision = 0
    private var pending: Pending?
    private var worker: Task<Void, Never>?
    private var queryObserver: AnyCancellable?
    private let homeDirectory: URL
    private let debounce: Duration
    private let searchOperation: SearchOperation

    private struct Pending {
        let query: String
        let revision: Int
        let earliestStart: ContinuousClock.Instant
    }

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        debounce: Duration = .milliseconds(120),
        searchOperation: SearchOperation? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.debounce = debounce
        self.searchOperation =
            searchOperation
            ?? { query, expression, home in
                try await Task.detached(priority: .userInitiated) {
                    try FileSearchService.search(
                        query: query, expression: expression, homeDirectory: home)
                }.value
            }
    }

    /// The screen drives the session off the palette's own query rather than off `snapshot`, which
    /// runs inside a view update and must not start work.
    func observe(_ queries: some Publisher<String, Never>) {
        queryObserver = queries.sink { [weak self] query in self?.search(query) }
    }

    func stop() {
        queryObserver = nil
        cancel()
    }

    func search(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            cancel()
            return
        }
        // A failed search re-runs on the next keystroke even when the text lands back where it was.
        guard query != self.query || state == .failed else { return }
        revision &+= 1
        self.query = query
        state = .searching
        pending = Pending(
            query: query, revision: revision,
            earliestStart: ContinuousClock.now.advanced(by: debounce))
        guard worker == nil else { return }
        worker = Task { [weak self] in await self?.run() }
    }

    func cancel() {
        revision &+= 1
        pending = nil
        query = ""
        results = []
        state = .idle
    }

    /// One worker for the session's lifetime: typing faster than Spotlight answers coalesces onto the
    /// newest pending query instead of accumulating concurrent searches.
    private func run() async {
        while let request = pending {
            let delay = ContinuousClock.now.duration(to: request.earliestStart)
            if delay > .zero { try? await Task.sleep(for: delay) }
            // Superseded during the debounce: loop back and take the newer request instead.
            guard pending?.revision == request.revision else { continue }
            pending = nil
            guard let expression = FileSearchQuery.expression(for: request.query) else { continue }
            do {
                let found = try await searchOperation(request.query, expression, homeDirectory)
                guard revision == request.revision, query == request.query else { continue }
                results = found
                state = .ready
            } catch {
                guard revision == request.revision, query == request.query else { continue }
                AppLog.error("file-search", "Spotlight query failed: \(error)")
                results = []
                state = .failed
            }
        }
        worker = nil
    }
}
