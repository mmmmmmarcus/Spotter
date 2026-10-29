import AppKit
import Foundation

struct ExtensionOAuthAuthorizeOptions: Sendable {
    let url: URL
    let state: String?
}

struct ExtensionOAuthAuthorizeResult: Sendable {
    let authorizationCode: String
    let accessToken: String?
    let state: String?
}

/// An OAuth 2.0 PKCE session: the browser authorizes and an `oauth` callback completes it.
@MainActor
@Observable
final class ExtensionOAuthSession {
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var expectedState: String?
    private var timeoutTimer: Timer?

    private static weak var activeSession: ExtensionOAuthSession?

    /// True while this session is waiting for the browser to come back.
    var isAuthorizing: Bool {
        continuation != nil
    }

    enum OAuthError: LocalizedError {
        case canceled
        case failed(String)
        case stateMismatch

        var errorDescription: String? {
            switch self {
            case .canceled: return "Authentication was canceled."
            case .failed(let message): return message
            case .stateMismatch: return "OAuth state mismatch. Please try authenticating again."
            }
        }
    }

    /// What a deep link turned out to be, so the caller can tell "not ours" from "too late".
    enum Callback {
        case delivered
        case expired
        case ignored
    }

    /// Deep links from the app delegate, such as `raycast://oauth?code=…`.
    static func handleCallbackURL(_ url: URL) -> Callback {
        guard let scheme = url.scheme?.lowercased(),
            scheme == "spotter" || scheme == "raycast" || scheme == "tinycast" || scheme == "com.raycast"
        else { return .ignored }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        guard
            host == "oauth" || host == "redirect"
                || path == "/oauth" || path == "/redirect"
                || path.hasPrefix("/oauth/") || path.hasPrefix("/redirect/")
        else {
            return .ignored
        }

        // The browser can come back after the session is gone: quit, timed out, or torn down.
        guard let active = activeSession else { return .expired }
        active.receiveCallback(url: url)
        return .delivered
    }

    func authorize(options: ExtensionOAuthAuthorizeOptions) async throws -> ExtensionOAuthAuthorizeResult {
        let params = try await authorize(url: options.url, expectedState: options.state)
        let code = params["code"] ?? ""
        let token = params["access_token"]
        let state = params["state"]
        return ExtensionOAuthAuthorizeResult(authorizationCode: code, accessToken: token, state: state)
    }

    func authorize(
        url: URL,
        expectedState: String? = nil
    ) async throws -> [String: String] {
        if continuation != nil {
            cancel()
        }

        self.expectedState = expectedState
        Self.activeSession = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            self.timeoutTimer?.invalidate()
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finish(error: OAuthError.failed("Authentication timed out."))
                }
            }

            let opened = NSWorkspace.shared.open(url)
            if !opened {
                self.finish(error: OAuthError.failed("Failed to open authorization URL in default browser."))
            }
        }
    }

    private func receiveCallback(url: URL) {
        do {
            finish(result: try Self.validatedCallback(url: url, expectedState: expectedState))
        } catch {
            finish(error: error)
        }
    }

    static func validatedCallback(url: URL, expectedState: String?) throws -> [String: String] {
        let items = callbackItems(url: url)
        let params = parseCallback(url: url)
        if let error = params["error"] {
            let desc = params["error_description"] ?? error
            throw OAuthError.failed(desc)
        }

        if let expected = expectedState {
            let states = items.filter { $0.name == "state" }
            guard states.count == 1, (states[0].value ?? "") == expected else {
                throw OAuthError.stateMismatch
            }
        }

        guard !(params["code"] ?? "").isEmpty || !(params["access_token"] ?? "").isEmpty else {
            throw OAuthError.failed("Sign-in returned no authorization code or access token.")
        }
        return params
    }

    private func finish(result: [String: String]? = nil, error: Error? = nil) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        expectedState = nil

        if Self.activeSession === self {
            Self.activeSession = nil
        }

        if let continuation = self.continuation {
            self.continuation = nil
            if let error {
                continuation.resume(throwing: error)
            } else if let result {
                continuation.resume(returning: result)
            } else {
                continuation.resume(throwing: OAuthError.canceled)
            }
        }
    }

    func cancel() {
        finish(error: OAuthError.canceled)
    }

    // MARK: - URL Parsing

    static func parseCallback(url: URL) -> [String: String] {
        var result: [String: String] = [:]
        for item in callbackItems(url: url) { result[item.name] = item.value ?? "" }
        return result
    }

    private static func callbackItems(url: URL) -> [URLQueryItem] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return []
        }
        var items = components.queryItems ?? []
        // Keep fragments encoded until splitting, and count state across query and fragment together.
        if let fragment = components.percentEncodedFragment, !fragment.isEmpty {
            var fragmentComponents = URLComponents()
            fragmentComponents.percentEncodedQuery = fragment
            items += fragmentComponents.queryItems ?? []
        }
        return items
    }
}
