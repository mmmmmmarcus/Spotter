import Foundation
import Combine

@MainActor
final class ClipboardSemanticSearch: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var status = "Off"
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var isPreparing = false
    @Published private(set) var isSearching = false
    @Published private(set) var error: String?
    var onApplyMatches: ((String, [UUID]) -> Void)?

    private let store: ClipboardStore
    private let root: URL
    private let index: ClipboardSemanticIndex
    private let client: ClipboardEmbeddingClient
    private let defaults: UserDefaults
    private let consentKey: String
    private var preparation: Task<Void, Never>?
    private var indexing: Task<Void, Never>?
    private var searching: Task<Void, Never>?
    private var cleanup: Task<Void, Never>?
    private var generation = UUID()
    private var indexRun = UUID()
    private var searchRun = UUID()
    private var ready = false
    private var needsReconcile = false
    private var activeQuery = ""
    private var lastQueryVector: (query: String, vector: [Float])?
    var canImportModels: Bool { isEnabled && !ready && !isPreparing }

    init(store: ClipboardStore, directory: URL? = nil, defaults: UserDefaults = .standard, executable: URL? = nil) {
        self.store = store
        self.defaults = defaults
        let bundleID = Bundle.main.bundleIdentifier ?? "com.spotter.app1"
        consentKey = bundleID + ".clipboard.semantic-search.enabled"
        isEnabled = defaults.bool(forKey: consentKey)
        root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID).appendingPathComponent("ClipboardSemanticSearch")
        index = ClipboardSemanticIndex(directory: root.appendingPathComponent("Index"))
        client = ClipboardEmbeddingClient(executable: executable ?? Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/spotter-embed"), models: root.appendingPathComponent("Models"))
    }

    func start() {
        guard isEnabled, preparation == nil else { return }
        prepare()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: consentKey)
        generation = UUID()
        preparation?.cancel()
        indexing?.cancel()
        searching?.cancel()
        preparation = nil
        indexing = nil
        searching = nil
        ready = false
        isPreparing = false
        isSearching = false
        downloadProgress = nil
        error = nil
        lastQueryVector = nil
        applyMatches(query: "", ids: [])
        if enabled { prepare() }
        else {
            status = "Off"
            let index = index, root = root
            let previousCleanup = cleanup
            cleanup = Task {
                await previousCleanup?.value
                do {
                    try await index.clear()
                    try await Task.detached(priority: .utility) {
                        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
                    }.value
                } catch {
                    AppLog.error("Clipboard semantic search", "Could not remove the local search cache: \(error.localizedDescription)")
                }
            }
        }
    }

    func retry() {
        guard isEnabled else { return }
        error = nil
        if ready { historyDidChange() }
        else if preparation == nil { prepare() }
    }

    func importModels(from source: URL) {
        guard canImportModels else { return }
        error = nil
        prepare(source: source)
    }

    private func prepare(source: URL? = nil) {
        let token = generation
        isPreparing = true
        status = "Preparing local search…"
        preparation = Task { [weak self] in
            guard let self else { return }
            let scoped = source?.startAccessingSecurityScopedResource() ?? false
            defer {
                if scoped { source?.stopAccessingSecurityScopedResource() }
                if generation == token { preparation = nil; isPreparing = false; downloadProgress = nil }
            }
            do {
                await cleanup?.value
                try check(token)
                #if !arch(arm64)
                throw ClipboardEmbeddingError.unsupported
                #else
                guard FileManager.default.isExecutableFile(atPath: client.executable.path) else {
                    throw ClipboardEmbeddingError.unavailable
                }
                try FileManager.default.createDirectory(at: client.models, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                configuration.httpCookieStorage = nil
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 1_800
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                var completed: Int64 = 0
                let total = ClipboardSemanticModels.files.reduce(Int64(0)) { $0 + $1.bytes }
                for file in ClipboardSemanticModels.files {
                    try check(token)
                    let destination = client.models.appendingPathComponent(file.name)
                    let valid = try await ClipboardSemanticModels.validate(destination, file: file)
                    try check(token)
                    if !valid {
                        if let source {
                            status = "Verifying imported model…"
                            let original = source.appendingPathComponent(file.name)
                            let staged = client.models.appendingPathComponent(UUID().uuidString + ".partial")
                            defer { try? FileManager.default.removeItem(at: staged) }
                            try await Task.detached(priority: .utility) {
                                try FileManager.default.copyItem(at: original, to: staged)
                            }.value
                            try check(token)
                            let verified = try await ClipboardSemanticModels.validate(staged, file: file)
                            try check(token)
                            guard verified else { throw ClipboardEmbeddingError.invalidReply }
                            if FileManager.default.fileExists(atPath: destination.path) {
                                try FileManager.default.removeItem(at: destination)
                            }
                            try FileManager.default.moveItem(at: staged, to: destination)
                            completed += file.bytes
                            continue
                        }
                        status = "Downloading local model…"
                        let base = completed
                        let progress = ClipboardModelDownloadProgress(maximumBytes: file.bytes) { [weak self] received in
                            Task { @MainActor in
                                guard let self, self.isEnabled, self.generation == token else { return }
                                self.downloadProgress = min(1, Double(base + received) / Double(total))
                            }
                        }
                        let (temporary, response) = try await session.download(from: file.url, delegate: progress)
                        defer { try? FileManager.default.removeItem(at: temporary) }
                        try check(token)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                            throw URLError(.badServerResponse)
                        }
                        status = "Verifying local model…"
                        let verified = try await ClipboardSemanticModels.validate(temporary, file: file)
                        try check(token)
                        guard verified else { throw ClipboardEmbeddingError.invalidReply }
                        if FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.removeItem(at: destination)
                        }
                        try FileManager.default.moveItem(at: temporary, to: destination)
                    }
                    completed += file.bytes
                }
                try check(token)
                ready = true
                historyDidChange()
                search(activeQuery, force: true)
                #endif
            } catch {
                guard isEnabled, generation == token, !Task.isCancelled else { return }
                report(error, status: "Local model unavailable")
            }
        }
    }

    func historyDidChange() {
        guard isEnabled, ready else { return }
        needsReconcile = true
        guard indexing == nil else { return }
        let token = generation
        indexRun = UUID()
        let run = indexRun
        indexing = Task { [weak self] in
            guard let self else { return }
            defer { if generation == token, indexRun == run { indexing = nil } }
            do {
                await cleanup?.value
                while needsReconcile {
                    needsReconcile = false
                    try check(token)
                    let candidates = store.historyPage(limit: ClipboardSemanticEngine.maximumItems)
                        .filter { $0.kind == .text || $0.kind == .image }
                    let scan = Task.detached(priority: .utility) {
                        var fingerprints: [UUID: String] = [:]
                        for item in candidates {
                            try Task.checkCancellation()
                            fingerprints[item.id] = ClipboardSemanticIndex.fingerprint(text: item.text, imagePath: item.imagePath)
                        }
                        return fingerprints
                    }
                    let fingerprints = try await withTaskCancellationHandler {
                        try await scan.value
                    } onCancel: { scan.cancel() }
                    try check(token)
                    try await index.reconcile(fingerprints)
                    try check(token)
                    let indexed = await index.indexed()
                    let pending = candidates.filter { fingerprints[$0.id] != nil && indexed[$0.id] != fingerprints[$0.id] }
                    var completed = indexed.count
                    var failed = 0
                    for start in stride(from: 0, to: pending.count, by: ClipboardSemanticEngine.batchSize) {
                        try check(token)
                        // An interactive query gets the GPU before the next background batch.
                        while isSearching {
                            try await Task.sleep(for: .milliseconds(150))
                            try check(token)
                        }
                        status = "Indexing \(completed) of \(fingerprints.count) entries…"
                        let batch = Array(pending[start..<min(pending.count, start + ClipboardSemanticEngine.batchSize)])
                        let groupedInputs = batch.map { item -> [ClipboardEmbeddingInput] in
                            if let text = item.text {
                                return ClipboardSemanticEngine.documents(text).map { ClipboardEmbeddingInput(value: $0, isImage: false) }
                            }
                            return [ClipboardEmbeddingInput(value: item.imagePath ?? "", isImage: true)]
                        }
                        let vectors = try await client.embed(groupedInputs.flatMap { $0 })
                        try check(token)
                        var offset = 0
                        for (item, inputs) in zip(batch, groupedInputs) {
                            let slice = vectors[offset..<(offset + inputs.count)]
                            offset += inputs.count
                            guard let current = store.historyItem(id: item.id), current.text == item.text,
                                current.imagePath == item.imagePath, let fingerprint = fingerprints[item.id] else { continue }
                            let valid = slice.compactMap { $0 }
                            guard !valid.isEmpty, valid.count == inputs.count else { failed += 1; continue }
                            try await index.save(ClipboardSemanticEntry(id: item.id, fingerprint: fingerprint, vectors: valid))
                            try check(token)
                            if store.historyItem(id: item.id) == nil { await index.remove(item.id) }
                            completed += 1
                        }
                        if let cached = lastQueryVector, cached.query == activeQuery {
                            let ids = await index.search(cached.vector)
                            try check(token)
                            if activeQuery == cached.query { applyMatches(query: cached.query, ids: ids) }
                        }
                    }
                    status = "\(completed) entries indexed" + (failed > 0 ? " · \(failed) unavailable" : "")
                    if failed > 0 { error = "Some entries could not be indexed. Retry after restoring access to their files." }
                    search(activeQuery, force: true)
                }
            } catch {
                guard isEnabled, generation == token, !Task.isCancelled else { return }
                report(error, status: "Indexing paused")
            }
        }
    }

    func remove(_ id: UUID) {
        Task { await index.remove(id) }
    }

    func clear() {
        indexRun = UUID()
        searchRun = UUID()
        indexing?.cancel()
        searching?.cancel()
        indexing = nil
        searching = nil
        isSearching = false
        lastQueryVector = nil
        applyMatches(query: "", ids: [])
        let previousCleanup = cleanup
        cleanup = Task {
            await previousCleanup?.value
            try? await index.clear()
        }
        if isEnabled { status = "0 entries indexed" }
    }

    func search(_ query: String, force: Bool = false) {
        let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
        guard force || query != activeQuery else { return }
        activeQuery = query
        searchRun = UUID()
        let run = searchRun
        searching?.cancel()
        searching = nil
        isSearching = false
        if !force { applyMatches(query: query, ids: []) }
        guard isEnabled, ready, query.count >= 2 else { return }
        let token = generation
        isSearching = true
        searching = Task { [weak self] in
            guard let self else { return }
            defer { if searchRun == run, generation == token { isSearching = false } }
            do {
                try await Task.sleep(for: .milliseconds(350))
                try check(token)
                let vector: [Float]
                if let cached = lastQueryVector, cached.query == query { vector = cached.vector }
                else {
                    let response = try await client.embed([ClipboardEmbeddingInput(value: ClipboardSemanticEngine.query(query), isImage: false, isQuery: true)])
                    try check(token)
                    guard let result = response.first, let result else { throw ClipboardEmbeddingError.invalidReply }
                    vector = result
                    lastQueryVector = (query, vector)
                }
                let ids = await index.search(vector)
                try check(token)
                guard activeQuery == query else { return }
                applyMatches(query: query, ids: ids)
            } catch {
                guard isEnabled, generation == token, activeQuery == query, !Task.isCancelled else { return }
                report(error, status: "Semantic search unavailable")
            }
        }
    }

    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard isEnabled, generation == token else { throw CancellationError() }
    }

    private func applyMatches(query: String, ids: [UUID]) {
        if let onApplyMatches { onApplyMatches(query, ids) }
        else { store.setSemanticMatches(query: query, ids: ids) }
    }

    private func report(_ failure: Error, status: String) {
        self.status = status
        error = failure.localizedDescription
        AppLog.error("Clipboard semantic search", failure.localizedDescription)
    }
}

private final class ClipboardModelDownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let maximumBytes: Int64
    let update: @Sendable (Int64) -> Void
    init(maximumBytes: Int64, update: @escaping @Sendable (Int64) -> Void) {
        self.maximumBytes = maximumBytes
        self.update = update
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= maximumBytes else { downloadTask.cancel(); return }
        update(totalBytesWritten)
    }
}
