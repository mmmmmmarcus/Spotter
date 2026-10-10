import AppKit
import WebKit

@main
@MainActor
struct MarkdownTests {
    static func main() async throws {
        _ = NSApplication.shared
        let workspace = URL(fileURLWithPath: "/tmp/spotter-workspace")
        precondition(AIChatLinkTarget.resolve("https://example.com/a", workspace: workspace) == .web(URL(string: "https://example.com/a")!))
        precondition(AIChatLinkTarget.resolve("javascript:alert(1)", workspace: workspace) == nil)
        precondition(AIChatLinkTarget.resolve("data:text/html,x", workspace: workspace) == nil)
        precondition(AIChatLinkTarget.resolve("file://remote/tmp/a", workspace: workspace) == nil)
        precondition(AIChatLinkTarget.resolve("/tmp/My File.swift:12:3", workspace: workspace) == .file(URL(fileURLWithPath: "/tmp/My File.swift"), line: 12))
        precondition(AIChatLinkTarget.resolve("src/main.swift#L20", workspace: workspace) == .file(workspace.appendingPathComponent("src/main.swift"), line: 20))
        precondition(AIChatLinkTarget.resolve("file:///tmp/code.swift#L7", workspace: workspace) == .file(URL(fileURLWithPath: "/tmp/code.swift"), line: 7))
        let probe = Probe()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(probe, name: "markdown")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 1000), configuration: config)
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Spotter/Resources/AIChatMarkdown")
        web.loadFileURL(base.appendingPathComponent("index.html"), allowingReadAccessTo: base)
        for _ in 0..<1000 { if probe.ready { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(probe.ready, "bundled renderer must load under its actual content security policy")
        let source = """
        ## Links
        [OpenAI](https://openai.com) and https://example.com
        [File](/tmp/test.swift:12)
        - **bold**
          - nested
        - [x] done

        | A | B |
        | --- | ---: |
        | 1 | 2 |

        ```swift
        let value = 1
        ```

        $$\\frac{1}{2}$$

        ```mermaid
        graph TD; A-->B
        ```

        <script>window.pwned = true</script>
        ![image](https://example.com/never-load.png)
        """
        let style = Theme.ChatMarkdown.styles(appearance: NSAppearance(named: .aqua)!)
        _ = try await web.callAsyncJavaScript("await window.spotterRender(text, style, false, true)", arguments: ["text": source, "style": style], in: nil, contentWorld: .page)
        let result = try await web.evaluateJavaScript("({ links: document.querySelectorAll('a').length, table: !!document.querySelector('table'), math: !!document.querySelector('.katex'), diagram: !!document.querySelector('.diagram svg'), code: !!document.querySelector('.hljs-keyword'), unsafe: !!window.pwned, images: document.querySelectorAll('img').length, height: document.getElementById('reply').getBoundingClientRect().height })") as! [String: Any]
        precondition(result["table"] as? Bool == true && result["math"] as? Bool == true && result["diagram"] as? Bool == true && result["code"] as? Bool == true, "all rich blocks render in WebKit: \(result)")
        precondition(result["unsafe"] as? Bool == false && result["images"] as? Int == 0)
        precondition((result["height"] as? Double ?? 0) > 100)
        _ = try await web.evaluateJavaScript("document.querySelector('a').click(); document.querySelector('[data-copy]').click()")
        for _ in 0..<100 { if probe.links.count == 1 && probe.copies.count == 1 { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(probe.links == ["https://openai.com"] && probe.copies == ["let value = 1\n"], "link and copy bridge preserve destinations and source")
        _ = try await web.callAsyncJavaScript("await window.spotterRender(text, style, true, true)", arguments: ["text": "```swift\nlet pending", "style": style], in: nil, contentWorld: .page)
        let pending = try await web.evaluateJavaScript("document.querySelector('code').textContent") as? String
        precondition(pending == "let pending")
        _ = try await web.callAsyncJavaScript("await window.spotterRender(text, style, false, true)", arguments: ["text": "Finished **reply**", "style": Theme.ChatMarkdown.styles(appearance: NSAppearance(named: .darkAqua)!)], in: nil, contentWorld: .page)
        let finished = try await web.evaluateJavaScript("document.querySelector('strong').textContent") as? String
        precondition(finished == "reply")
        let grammar = "```json\n{\"corrected\":\"I am here.\",\"issues\":[{\"original\":\"I is\",\"suggestion\":\"I am\",\"message\":\"Agreement\"}]}\n```"
        _ = try await web.callAsyncJavaScript("await window.spotterRender(text, style, false, true, true)", arguments: ["text": grammar, "style": style], in: nil, contentWorld: .page)
        let grammarRendered = try await web.evaluateJavaScript("!!document.querySelector('.grammar-result') && !document.querySelector('.code-block')") as? Bool
        precondition(grammarRendered == true)
        _ = try await web.callAsyncJavaScript("await window.spotterRender(text, style, false, true, false)", arguments: ["text": grammar, "style": style], in: nil, contentWorld: .page)
        let ordinaryJSON = try await web.evaluateJavaScript("!!document.querySelector('.code-block')") as? Bool
        precondition(ordinaryJSON == true)
        let longText = String(repeating: "A paragraph that wraps when the conversation is narrow. ", count: 12)
        _ = try await web.callAsyncJavaScript("await window.spotterRender(text, style, false, true)", arguments: ["text": longText, "style": style], in: nil, contentWorld: .page)
        let wideHeight = try await web.evaluateJavaScript("document.getElementById('reply').getBoundingClientRect().height") as! Double
        web.setFrameSize(CGSize(width: 220, height: 1000))
        try await Task.sleep(for: .milliseconds(50))
        let narrowHeight = try await web.evaluateJavaScript("document.getElementById('reply').getBoundingClientRect().height") as! Double
        precondition(narrowHeight > wideHeight, "sidebar/window resizing recomputes the transcript height")
        print("PASS actual WebKit assets, CSP, Markdown, Mermaid, KaTeX, code highlighting, link/copy events, incomplete streaming and local link resolution")
    }
}

@MainActor
final class Probe: NSObject, WKScriptMessageHandler {
    var ready = false
    var links: [String] = []
    var copies: [String] = []
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if body["kind"] as? String == "ready" { ready = true }
        if body["kind"] as? String == "link", let value = body["value"] as? String { links.append(value) }
        if body["kind"] as? String == "copy", let value = body["value"] as? String { copies.append(value) }
    }
}
