import Foundation

@main
struct SearchBenchmark {
    static func main() {
        let fields = (0..<600).map { index in
            SearchFields(
                names: ["Application \(index)", "Document Editor \(index)"],
                userAlias: index % 7 == 0 ? "Work Tool \(index)" : nil,
                alternateNames: ["Productivity \(index)"],
                bundleID: "com.vendor.application\(index)",
                executableName: "Application\(index)")
        }
        let queries = [
            "app", "doc", "ae", "work", "zz", "PRODUCT", "Application 220", "文档", "\u{200E}app",
        ]
        var checksum = 0
        let start = ContinuousClock.now
        for _ in 0..<30 {
            for query in queries {
                #if OPTIMIZED
                    let prepared = FuzzyMatch.Query(query)
                    for field in fields {
                        checksum &+= SearchRelevance.score(query: prepared, fields: field) ?? 0
                    }
                #else
                    for field in fields {
                        checksum &+= SearchRelevance.score(query: query, fields: field) ?? 0
                    }
                #endif
            }
        }
        print("\(start.duration(to: .now)) checksum=\(checksum)")
    }
}
