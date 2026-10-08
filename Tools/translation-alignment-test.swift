import Foundation

@MainActor
final class OpenRouterStore {
    var isReady = true
    var reply = #"{"links":[{"source":[0],"target":[1]}]}"#
    var callCount = 0
    func chat(messages: [(role: String, content: String)], model: String, webSearch: Bool,
        imageDataURLs: [Int: [String]], completionLimit: Int, onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws {
        precondition(model == TranslationWordAlignment.model && !webSearch && imageDataURLs.isEmpty)
        precondition(messages.count == 2 && completionLimit == 12_000)
        callCount += 1
        onDelta(reply)
    }
}

@main
struct AlignmentTests {
    @MainActor static func main() async throws {
        let original = "The cat likes the cat. 🐈"
        let words = TranslationWordAlignment.tokenize(original)
        precondition(words.filter { $0.text == "cat" }.count == 2)
        for word in words { precondition((original as NSString).substring(with: word.range) == word.text) }
        let chinese = "我喜欢绿茶。"
        let target = TranslationWordAlignment.tokenize(chinese)
        precondition(!target.isEmpty)
        for word in target { precondition((chinese as NSString).substring(with: word.range) == word.text) }
        let links = try TranslationWordAlignment.decode(#"{"links":[{"source":[1,2],"target":[0]}]}"#, sourceCount: words.count, targetCount: target.count)
        let forward = TranslationWordAlignment.ranges(hovered: 1, source: true, sourceWords: words, targetWords: target, links: links)
        let reverse = TranslationWordAlignment.ranges(hovered: 0, source: false, sourceWords: words, targetWords: target, links: links)
        precondition(forward.source == reverse.source && forward.target == reverse.target)
        precondition(forward.source.count == 2 && forward.target.count == 1)
        precondition(TranslationWordAlignment.ranges(hovered: nil, source: true, sourceWords: words, targetWords: target, links: links).source.isEmpty)
        for invalid in [#"{"links":[{"source":[-1],"target":[0]}]}"#,
            #"{"links":[{"source":[0,0],"target":[0]}]}"#, #"{"links":[{"source":[0],"target":[99]}]}"#,
            #"{"links":[{"source":[],"target":[0]}]}"#, "not JSON"] {
            do { _ = try TranslationWordAlignment.decode(invalid, sourceCount: 3, targetCount: 3); fatalError("Invalid indices accepted") } catch {}
        }
        let repeated = [TranslationWordLink(source: [4], target: [0])]
        precondition(TranslationWordAlignment.ranges(hovered: 1, source: true, sourceWords: words, targetWords: target, links: repeated).target.isEmpty)
        precondition(TranslationWordAlignment.ranges(hovered: 4, source: true, sourceWords: words, targetWords: target, links: repeated).target.count == 1)
        let router = OpenRouterStore()
        let received = try await TranslationAlignmentClient.align(source: words, target: target, router: router)
        precondition(received.count == 1 && router.callCount == 1)
        router.isReady = false
        do { _ = try await TranslationAlignmentClient.align(source: words, target: target, router: router); fatalError("Missing key accepted") } catch {}
        precondition(router.callCount == 1)
        router.isReady = true
        let cancelled = Task { try await TranslationAlignmentClient.align(source: words, target: target, router: router) }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancelled alignment completed") } catch {}
        precondition(router.callCount == 1)
        let tooLong = Array(repeating: words[0], count: 601)
        do { _ = try TranslationWordAlignment.prompt(source: tooLong, target: target); fatalError("Budget ignored") } catch {}
        print("PASS token offsets, Chinese segmentation, bidirectional multiword matching, invalid links, key gate and request bounds")
    }
}
