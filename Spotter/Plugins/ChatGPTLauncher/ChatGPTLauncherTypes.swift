import Foundation

enum ChatGPTPrompt {
    static let appBundleIdentifier = "com.openai.codex"

    static func prepared(_ rawValue: String) -> String? {
        let prompt = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.isEmpty ? nil : prompt
    }

    static func deepLink(for rawValue: String) -> URL? {
        guard let prompt = prepared(rawValue) else { return nil }
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "new"
        components.queryItems = [URLQueryItem(name: "prompt", value: prompt)]
        return components.url
    }

    static func matchesDraft(_ accessibilityValue: String, prompt: String) -> Bool {
        normalized(accessibilityValue).trimmingCharacters(in: .newlines)
            == normalized(prompt)
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

enum ChatGPTComposerMode {
    static func isChat(pressedStates: [Bool]) -> Bool {
        pressedStates == [true, false]
    }
}
