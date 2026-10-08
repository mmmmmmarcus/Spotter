import Foundation

enum NavigationMode: String, Sendable {
    case windows
    case menus
}

struct NavigationResult: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let appName: String
    let bundlePath: String?
    let processIdentifier: Int32
    let locator: [String]
}

enum NavigationResults {
    static func matching(_ results: [NavigationResult], query: String) -> [NavigationResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return results }
        return results.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.subtitle.localizedCaseInsensitiveContains(needle)
                || $0.appName.localizedCaseInsensitiveContains(needle)
        }
    }

    static func windowIndex(locator: [String], titles: [String]) -> Int? {
        guard let title = locator.last else { return nil }
        if locator.count == 2, let index = Int(locator[0]), titles.indices.contains(index), titles[index] == title {
            return index
        }
        return titles.firstIndex(of: title)
    }
}
