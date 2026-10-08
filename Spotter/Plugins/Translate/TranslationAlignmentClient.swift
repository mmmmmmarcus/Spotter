import Foundation

@MainActor
enum TranslationAlignmentClient {
    static func align(source: [TranslationWord], target: [TranslationWord], router: OpenRouterStore) async throws -> [TranslationWordLink] {
        try Task.checkCancellation()
        guard router.isReady else { throw TranslationWordAlignment.AlignmentError.unavailable }
        let prompt = try TranslationWordAlignment.prompt(source: source, target: target)
        var response = ""
        var overflow = false
        try await router.chat(messages: [(role: "system", content: TranslationWordAlignment.instructions),
            (role: "user", content: prompt)], model: TranslationWordAlignment.model, webSearch: false, imageDataURLs: [:], completionLimit: 12_000) { delta in
            if response.utf8.count + delta.utf8.count <= 100_000 { response += delta } else { overflow = true }
        }
        try Task.checkCancellation()
        guard !overflow else { throw TranslationWordAlignment.AlignmentError.invalidResponse }
        return try TranslationWordAlignment.decode(response, sourceCount: source.count, targetCount: target.count)
    }
}
