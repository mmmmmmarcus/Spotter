import Foundation

enum UpdateFeedError: Error, LocalizedError, Equatable {
    case rateLimited(until: Date)
    case http(Int)
    case invalidResponse
    case invalidFeed
    case network(Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let until):
            "The update server is temporarily rate limiting this network. Try again after \(until.formatted(date: .abbreviated, time: .standard)), or download from Releases."
        case .http(let status): "The update server returned HTTP \(status). Try again later, or download from Releases."
        case .invalidResponse: "The update server returned an invalid response."
        case .invalidFeed: "The update information could not be read. Try again later."
        case .network(let code):
            code == NSURLErrorTimedOut ? "The update check timed out. Try again later."
                : "Couldn’t connect to the update server (network error \(code)). Check your connection, or download from Releases."
        }
    }
}

enum UpdateCheckPolicy {
    static let cooldown: TimeInterval = 30

    static func responseError(_ response: HTTPURLResponse, now: Date) -> UpdateFeedError? {
        guard response.statusCode != 200 else { return nil }
        let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap { value -> Date? in
            if let seconds = Double(value), seconds.isFinite, seconds >= 0 {
                return now.addingTimeInterval(seconds)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            return formatter.date(from: value)
        }
        let exhausted = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
        let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
            .flatMap(Double.init).flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
        if response.statusCode == 429 || (response.statusCode == 403 && (exhausted || retry != nil)) {
            let dates = [retry, exhausted ? reset : nil].compactMap { $0 }
            let until = max(now.addingTimeInterval(60), dates.max() ?? now)
            return .rateLimited(until: until)
        }
        return .http(response.statusCode)
    }

    static func failure(_ error: Error) -> UpdateFeedError {
        if let error = error as? UpdateFeedError { return error }
        if error is DecodingError { return .invalidFeed }
        let error = error as NSError
        return error.domain == NSURLErrorDomain ? .network(error.code) : .invalidFeed
    }
}

enum UpdateCheckSource: String {
    case settings, paletteOpen, paletteAction, automatic
}
