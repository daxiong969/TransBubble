import SwiftUI
import WebKit

@MainActor
final class WebViewModel: ObservableObject {
    @Published var urlString = "https://www.apple.com/cn/"
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    weak var webView: WKWebView?

    func load() {
        var address = urlString.trimmingCharacters(in: .whitespaces)
        if address.isEmpty { return }
        if !address.contains("://") { address = "https://" + address }
        guard let url = URL(string: address) else { return }
        webView?.load(URLRequest(url: url))
    }

    func reload() { webView?.reload() }
    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    /// 抓取当前页面文字：优先取用户选中的文字，否则取整页正文（去脚本样式，最长 2 万字）
    func extractPageText() async -> String {
        guard let webView else { return "" }
        let js = """
        (function() {
            try {
                var sel = String(window.getSelection ? window.getSelection() : '');
                if (sel && sel.trim().length > 0) {
                    return sel.trim().substring(0, 20000);
                }
                var t = document.body ? document.body.innerText : '';
                return t.replace(/\\n{3,}/g, '\\n\\n').trim().substring(0, 20000);
            } catch (e) { return ''; }
        })();
        """
        let result = try? await webView.evaluateJavaScript(js)
        return (result as? String) ?? ""
    }
}

struct BrowserView: UIViewRepresentable {
    @ObservedObject var viewModel: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 注：现代 WebKit SDK 已移除 javaScriptEnabled 开关，JavaScript 默认开启
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        viewModel.webView = webView
        if let url = URL(string: viewModel.urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(viewModel) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let viewModel: WebViewModel
        init(_ viewModel: WebViewModel) { self.viewModel = viewModel }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            viewModel.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.isLoading = false
            viewModel.canGoBack = webView.canGoBack
            viewModel.canGoForward = webView.canGoForward
            if let absolute = webView.url?.absoluteString {
                viewModel.urlString = absolute
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModel.isLoading = false
        }
    }
}
