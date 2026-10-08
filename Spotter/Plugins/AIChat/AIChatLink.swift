import Foundation

enum AIChatLinkTarget: Equatable {
    case web(URL)
    case file(URL, line: Int?)

    static func resolve(_ value: String, workspace: URL) -> Self? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("#"), !value.contains("\n") else { return nil }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased() {
            if ["https", "http"].contains(scheme), url.host != nil { return .web(url) }
            if scheme == "mailto" { return .web(url) }
            if scheme == "file" {
                guard url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
                return fileTarget(url.path + (url.fragment.map { "#" + $0 } ?? ""), workspace: workspace)
            }
            // A relative filename may end in Codex's :line[:column] notation.
            guard value.range(of: #"^[^:]+:\d+(?::\d+)?$"#, options: .regularExpression) != nil else { return nil }
        }
        return fileTarget(value.removingPercentEncoding ?? value, workspace: workspace)
    }

    private static func fileTarget(_ value: String, workspace: URL) -> Self? {
        var path = value
        var line: Int?
        if let range = path.range(of: #"(?::\d+(?::\d+)?|#L\d+(?:C\d+)?(?:-L?\d+(?:C\d+)?)?)$"#, options: .regularExpression) {
            let suffix = String(path[range])
            let digits = suffix.drop { !$0.isNumber }.prefix { $0.isNumber }
            line = Int(digits).flatMap { $0 > 0 ? $0 : nil }
            path.removeSubrange(range)
        }
        guard !path.isEmpty, !path.contains("\0") else { return nil }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : workspace.appendingPathComponent(path)
        return .file(url.standardizedFileURL, line: line)
    }
}
