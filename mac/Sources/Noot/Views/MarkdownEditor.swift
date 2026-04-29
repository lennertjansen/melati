import AppKit
import SwiftUI
import WebKit

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var readOnly: Bool = false
    var colorScheme: ColorScheme = .light
    var onTextChange: (() -> Void)?
    var onBlur: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "noot")
        config.userContentController = userContent
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "editor")
            ?? Bundle.main.url(forResource: "editor/index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyPendingState()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var parent: MarkdownEditor
        weak var webView: WKWebView?
        private var ready = false
        private var lastSentText: String = ""
        private var lastSentReadOnly: Bool?
        private var lastSentTheme: ColorScheme?

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                _log("[noot.editor] ready")
                ready = true
                applyPendingState()
            case "change":
                let md = body["md"] as? String ?? ""
                lastSentText = md
                if parent.text != md {
                    Task { @MainActor in
                        parent.text = md
                        parent.onTextChange?()
                    }
                }
            case "blur":
                Task { @MainActor in parent.onBlur?() }
            case "error":
                _log("[noot.editor.error] %@:%@:%@ — %@", String(describing: body["source"] ?? ""), String(describing: body["line"] ?? ""), String(describing: body["col"] ?? ""), String(describing: body["message"] ?? ""))
            case "log":
                let level = body["level"] as? String ?? "log"
                let args = (body["args"] as? [String])?.joined(separator: " ") ?? ""
                _log("[noot.editor.%@] %@", level, args)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            _log("[noot.editor] webview didFinish")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            _log("[noot.editor] webview didFailProvisional %@", error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            _log("[noot.editor] webview didFail %@", error.localizedDescription)
        }

        func applyPendingState() {
            guard ready, let webView else { return }
            if parent.text != lastSentText {
                lastSentText = parent.text
                let escaped = jsonEscape(parent.text)
                webView.evaluateJavaScript("window.nootSetContent && window.nootSetContent(\(escaped))", completionHandler: nil)
            }
            if lastSentReadOnly != parent.readOnly {
                lastSentReadOnly = parent.readOnly
                webView.evaluateJavaScript("window.nootSetReadOnly && window.nootSetReadOnly(\(parent.readOnly ? "true" : "false"))", completionHandler: nil)
            }
            if lastSentTheme != parent.colorScheme {
                lastSentTheme = parent.colorScheme
                let theme = parent.colorScheme == .dark ? "dark" : "light"
                webView.evaluateJavaScript("window.nootSetTheme && window.nootSetTheme('\(theme)')", completionHandler: nil)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only allow file:// loads of our bundled editor; block everything else.
            if let url = navigationAction.request.url, url.isFileURL {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

private func _log(_ format: String, _ args: CVarArg...) {
    let msg = String(format: format, arguments: args)
    print(msg)
    fflush(stdout)
}

private func jsonEscape(_ s: String) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])) ?? Data("[\"\"]".utf8)
    let str = String(data: data, encoding: .utf8) ?? "[\"\"]"
    return String(str.dropFirst().dropLast())
}
