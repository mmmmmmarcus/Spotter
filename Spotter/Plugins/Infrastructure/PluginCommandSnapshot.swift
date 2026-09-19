import Foundation

// Keep the displayed target stable until the user changes the query or reopens the palette.
struct PluginCommandSnapshot<Value> {
    private var query: String?
    private var entries: [Value] = []

    mutating func resolve(query: String, build: () -> [Value]) -> [Value] {
        if self.query == query { return entries }
        entries = build()
        self.query = query
        return entries
    }

    mutating func reset() {
        query = nil
        entries = []
    }
}
