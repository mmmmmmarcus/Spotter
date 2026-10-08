import AppKit
import SwiftUI
import WebKit

struct AIChatMarkdownText: View {
    let text: String
    var isStreaming = false
    @State private var height: CGFloat = 24
    @State private var failed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if failed {
                Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                AIChatMarkdownWebView(text: text, isStreaming: isStreaming, reduceMotion: reduceMotion,
                    height: $height, failed: $failed)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct AIChatMarkdownWebView: NSViewRepresentable {
    let text: String
    let isStreaming: Bool
    let reduceMotion: Bool
    @Binding var height: CGFloat
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "markdown")
        let view = MarkdownWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.appearanceChanged = { [weak coordinator = context.coordinator] in coordinator?.render() }
        context.coordinator.webView = view
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "AIChatMarkdown") else {
            DispatchQueue.main.async { failed = true }
            return view
        }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render()
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.renderTask?.cancel()
        view.stopLoading()
        view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "markdown")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: AIChatMarkdownWebView
        weak var webView: WKWebView?
        var ready = false
        var renderTask: Task<Void, Never>?
        private var lastInput: String?

        init(_ parent: AIChatMarkdownWebView) { self.parent = parent }

        func render() {
            guard ready, let webView, renderTask == nil else { return }
            let style = Theme.ChatMarkdown.styles(appearance: webView.effectiveAppearance)
            let signature = parent.text + style + "\(parent.isStreaming)-\(parent.reduceMotion)"
            guard signature != lastInput else { return }
            renderTask = Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                if parent.isStreaming {
                    do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
                }
                guard let webView, !Task.isCancelled else { return }
                let style = Theme.ChatMarkdown.styles(appearance: webView.effectiveAppearance)
                let text = parent.text, streaming = parent.isStreaming, reducedMotion = parent.reduceMotion
                lastInput = text + style + "\(streaming)-\(reducedMotion)"
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "await window.spotterRender(text, style, streaming, reducedMotion)",
                        arguments: ["text": text, "style": style, "streaming": streaming, "reducedMotion": reducedMotion],
                        in: nil, contentWorld: .page)
                } catch {
                    guard !Task.isCancelled else { return }
                    AppLog.error("ai-chat", "Markdown rendering failed: \(error.localizedDescription)")
                    parent.failed = true
                }
                renderTask = nil
                if !parent.failed { render() }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                let payload = message.body as? [String: Any], let kind = payload["kind"] as? String else { return }
            switch kind {
            case "ready": ready = true; render()
            case "height":
                if let value = payload["value"] as? Double, value.isFinite, value >= 0 {
                    let measured = max(1, CGFloat(value))
                    if abs(parent.height - measured) > 0.5 { parent.height = measured }
                }
            case "copy":
                if let value = payload["value"] as? String { Paster.copyPlainText(value) }
            case "link":
                if let value = payload["value"] as? String { Self.open(value) }
            case "scroll":
                if let top = payload["value"] as? Double, let webView {
                    let y = webView.isFlipped ? top : webView.bounds.height - top - 24
                    webView.scrollToVisible(CGRect(x: 0, y: y, width: 1, height: 24))
                }
            default: break
            }
        }

        static func open(_ value: String) {
            let workspace = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.spotter.app1")
                .appendingPathComponent("AIChat/Workspace")
            guard let target = AIChatLinkTarget.resolve(value, workspace: workspace) else { return }
            switch target {
            case .web(let url): NSWorkspace.shared.open(url)
            case .file(let url, let line):
                guard FileManager.default.fileExists(atPath: url.path) else {
                    AppLog.error("ai-chat", "A linked file is unavailable: \(url.path)")
                    return
                }
                let editor = NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
                if let line, editor == "com.apple.dt.Xcode" {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/xed")
                    process.arguments = ["--line", String(line), url.path]
                    try? process.run()
                } else if let line, let editor, ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92"].contains(editor) {
                    var destination = URLComponents()
                    destination.scheme = editor == "com.microsoft.VSCode" ? "vscode" : "cursor"
                    destination.host = "file"
                    destination.path = url.path + ":\(line)"
                    if let destination = destination.url { NSWorkspace.shared.open(destination) }
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                if let url = action.request.url { Self.open(url.absoluteString) }
                decisionHandler(.cancel)
            } else {
                decisionHandler(action.request.url?.isFileURL == true ? .allow : .cancel)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { parent.failed = true }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !ready else { return }
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                let loaded = try? await webView.evaluateJavaScript("typeof window.spotterRender === 'function'")
                if loaded as? Bool == true { ready = true; render() }
                else { parent.failed = true }
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.failed = true
        }
    }
}

private final class MarkdownWebView: WKWebView {
    var appearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }
}
