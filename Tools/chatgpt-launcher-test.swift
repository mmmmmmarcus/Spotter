import Foundation

@main
struct ChatGPTLauncherTests {
    static func main() {
        var failures = 0

        func check(_ message: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message)")
            }
        }

        let cases = [
            "hello world",
            "你好，世界",
            "a & b? #tag 100%",
            "first line\nsecond line",
            "emoji 🧭✨ and + plus",
        ]
        for prompt in cases {
            let url = ChatGPTPrompt.deepLink(for: prompt)
            let components = url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)
            }
            let decoded = components?.queryItems?.first(where: { $0.name == "prompt" })?.value
            check("prompt round-trips \(prompt.debugDescription)", decoded == prompt)
            check("deep link uses codex://new", url?.scheme == "codex" && url?.host == "new")
        }

        check("empty prompt is rejected", ChatGPTPrompt.deepLink(for: " \n\t ") == nil)
        let trimmedComponents = ChatGPTPrompt.deepLink(for: " \nkeep internal space\t ")
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let trimmed = trimmedComponents?.queryItems?
            .first(where: { $0.name == "prompt" })?.value
        check("only outer whitespace is trimmed", trimmed == "keep internal space")
        check(
            "matching drafts tolerate accessibility line endings",
            ChatGPTPrompt.matchesDraft("first\r\nsecond\n", prompt: "first\nsecond"))
        check(
            "different drafts never match",
            !ChatGPTPrompt.matchesDraft("send something else", prompt: "expected prompt"))

        print(failures == 0 ? "\nChatGPT Launcher: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
