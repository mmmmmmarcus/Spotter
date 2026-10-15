import Foundation

// Keep the harness isolated from real diagnostics and app state.
enum AppLog {
    static func info(_ category: String, _ message: String) {}
    static func error(_ category: String, _ message: String) {}
}

final class UpdateHTTPFixture: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 403
        var headers: [String: String] = [:]
        var body = #"{"schemaVersion":1,"channel":"stable","releases":[]}"#
        var delay: TimeInterval = 0
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [Reply] = []
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var urls: [URL] = []
    static var requestedURLs: [URL] { lock.withLock { urls } }
    static var requests: Int { lock.withLock { count } }
    static func reset(_ values: [Reply]) { lock.withLock { replies = values; count = 0; urls = [] } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.lock.withLock {
            Self.count += 1
            Self.urls.append(request.url!)
            return Self.replies.isEmpty ? Reply(status: 500) : Self.replies.removeFirst()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@main
struct UpdateNetworkTests {
    @MainActor static func main() async {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--live" {
            let suite = "Spotter.UpdateLiveTest.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = UpdateStore(defaults: defaults, version: "0.0.0")
            await store.checkNow()
            guard let release = store.availableRelease,
                  release.version.description == CommandLine.arguments[2],
                  !release.releaseNotes.isEmpty,
                  release.zipAssetURL?.host == "github.com"
            else {
                print("FAIL live feed: \(store.status)")
                exit(1)
            }
            print("PASS real UpdateStore anonymously loaded public static feed: \(release.version)")
            return
        }
        var failures = 0
        var checks = 0
        func check(_ title: String, _ value: Bool) {
            checks += 1
            if !value { failures += 1 }
            print("\(value ? "PASS" : "FAIL") \(title)")
        }
        let suite = "Spotter.UpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.protocolClasses = [UpdateHTTPFixture.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func makeStore() -> UpdateStore {
            UpdateStore(defaults: defaults, session: session, now: { now }, version: "1.0.0")
        }
        func response(_ status: Int, _ headers: [String: String] = [:]) -> UpdateFeedError? {
            UpdateCheckPolicy.responseError(HTTPURLResponse(url: URL(string: "https://example.com")!,
                statusCode: status, httpVersion: nil, headerFields: headers)!, now: now)
        }
        let reset = now.addingTimeInterval(3600)
        check("primary limit reads reset", response(403, ["X-RateLimit-Remaining": "0",
            "X-RateLimit-Reset": String(reset.timeIntervalSince1970)]) == .rateLimited(until: reset))
        check("ordinary forbidden is not called a connection failure", response(403) == .http(403))
        check("server failure keeps HTTP status", response(503) == .http(503))
        check("429 without headers backs off", response(429) == .rateLimited(until: now.addingTimeInterval(60)))
        check("secondary limit honors Retry-After", response(403, ["Retry-After": "120"]) == .rateLimited(until: now.addingTimeInterval(120)))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        check("Retry-After HTTP date works", response(429, ["Retry-After": formatter.string(from: reset)]) == .rateLimited(until: reset))
        check("longer reset and retry constraint wins", response(403, ["Retry-After": "120",
            "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": String(reset.timeIntervalSince1970)]) == .rateLimited(until: reset))
        check("invalid dates safely back off", response(429, ["Retry-After": "nan", "X-RateLimit-Reset": "inf"]) == .rateLimited(until: now.addingTimeInterval(60)))
        check("success is not rejected for last available quota", response(200, ["X-RateLimit-Remaining": "0"]) == nil)
        check("timeout gets a specific error", UpdateCheckPolicy.failure(URLError(.timedOut)) == .network(NSURLErrorTimedOut))

        UpdateHTTPFixture.reset([.init(headers: ["X-RateLimit-Remaining": "0",
            "X-RateLimit-Reset": String(reset.timeIntervalSince1970)])])
        defaults.set(now.addingTimeInterval(3600), forKey: (Bundle.main.bundleIdentifier ?? "com.spotter.app1") + ".update.rate-limit-until")
        let store = makeStore()
        check("old GitHub API cooldown cannot block the new host", store.canCheck(at: now))
        store.start()
        await Task.yield()
        check("automatic checks off makes no request", UpdateHTTPFixture.requests == 0)
        for _ in 0..<17 { await store.checkNow(source: .paletteAction) }
        check("17 sequential triggers make exactly one request", UpdateHTTPFixture.requests == 1)
        check("checks contact only the static Pages URL", UpdateHTTPFixture.requestedURLs == [UpdateFeed.url(for: .stable)])
        check("rate limit disables retry until reset", !store.canCheck(at: reset.addingTimeInterval(-1)) && store.canCheck(at: reset))
        if case .failed(let message) = store.status {
            check("user sees rate limit, not connection failure", message.contains("rate limiting") && !message.contains("connection"))
        } else { check("rate limit reports failure", false) }
        let relaunched = makeStore()
        await relaunched.checkNow()
        check("relaunch retains static-feed deadline without requesting", UpdateHTTPFixture.requests == 1 && relaunched.nextCheckDate == reset)
        now = reset
        UpdateHTTPFixture.reset([.init(status: 200)])
        await relaunched.checkNow()
        check("request allowed at reset", UpdateHTTPFixture.requests == 1 && relaunched.status == .upToDate)
        for _ in 0..<17 { await relaunched.checkNow() }
        check("successful checks also coalesce repeated triggers", UpdateHTTPFixture.requests == 1)
        now = now.addingTimeInterval(31)
        UpdateHTTPFixture.reset([.init(status: 200, delay: 0.15)])
        let concurrent = makeStore()
        let first = Task { await concurrent.checkNow() }
        try? await Task.sleep(for: .milliseconds(20))
        await concurrent.checkNow()
        await first.value
        check("overlapping checks share the in-flight gate", UpdateHTTPFixture.requests == 1)

        now = now.addingTimeInterval(31)
        UpdateHTTPFixture.reset([.init(status: 200, body: "not JSON")])
        await concurrent.checkNow()
        check("invalid JSON reports a feed error", concurrent.status == .failed(UpdateFeedError.invalidFeed.localizedDescription))
        for _ in 0..<17 { await concurrent.checkNow() }
        check("malformed responses also cool down", UpdateHTTPFixture.requests == 1)
        now = now.addingTimeInterval(31)
        UpdateHTTPFixture.reset([.init(status: 503)])
        await concurrent.checkNow()
        check("HTTP 503 is distinct from transport failure", concurrent.status == .failed(UpdateFeedError.http(503).localizedDescription))

        now = now.addingTimeInterval(31)
        let release = #"{"schemaVersion":1,"channel":"stable","releases":[{"version":"2.0.0","releaseURL":"https://github.com/mmmmmmarcus/Spotter/releases/tag/v2.0.0","zipURL":"https://github.com/mmmmmmarcus/Spotter/releases/download/v2.0.0/Spotter-2.0.0.zip","dmgURL":"https://github.com/mmmmmmarcus/Spotter/releases/download/v2.0.0/Spotter-2.0.0.dmg","releaseNotes":"A fix"}]}"#
        UpdateHTTPFixture.reset([.init(status: 200, body: release)])
        await concurrent.checkNow()
        check("one static request supplies update and notes without assets API", UpdateHTTPFixture.requests == 1 && concurrent.availableRelease?.version.description == "2.0.0" && concurrent.latestRelease?.releaseNotes == "A fix")
        now = now.addingTimeInterval(31)
        UpdateHTTPFixture.reset([.init(status: 200, body: "{}")])
        await concurrent.checkNow()
        check("invalid manifest never falls back to API", UpdateHTTPFixture.requests == 1 && concurrent.availableRelease == nil)

        now = now.addingTimeInterval(121)
        UpdateHTTPFixture.reset([.init(status: 200, delay: 0.1)])
        let cancelled = makeStore()
        cancelled.setAutoCheck(true)
        try? await Task.sleep(for: .milliseconds(20))
        cancelled.setAutoCheck(false)
        try? await Task.sleep(for: .milliseconds(200))
        check("withdrawing auto consent discards in-flight result", cancelled.status == .idle && cancelled.latestRelease == nil)
        print("\(checks - failures)/\(checks) checks passed")
        if failures > 0 { exit(1) }
    }
}
