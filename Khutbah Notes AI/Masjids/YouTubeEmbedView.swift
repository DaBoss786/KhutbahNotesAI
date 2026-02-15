import SwiftUI
import WebKit

struct YouTubeEmbedView: UIViewRepresentable {
    let videoId: String
    let sourceURL: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.layer.cornerRadius = 12
        webView.clipsToBounds = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let loadKey = "\(videoId)|\(sourceURL ?? "")"
        guard context.coordinator.currentLoadKey != loadKey else { return }
        context.coordinator.currentLoadKey = loadKey

        guard let request = YouTubeURLParser.embedRequest(for: videoId, sourceURL: sourceURL) else {
            return
        }
        webView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var currentLoadKey: String?
    }
}
