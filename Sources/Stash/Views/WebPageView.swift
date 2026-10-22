import AppKit
import SwiftUI
import WebKit

// MARK: - A web page on the canvas

/// Right-click a link on the canvas ▸ Show Page Here: the page itself, live, right on the canvas — scroll it,
/// click around, log in, play its videos (a course, a tutorial, any site, not only YouTube).
///
/// Safety: only web pages (http/https) load inside. Links to anything else go through Swiss's usual check, pop-up
/// windows open in the same card, downloads go to your browser, and the page can't reach Swiss or your files.
/// Logins are remembered like in a browser (Swiss's own, separate from Safari's).
@MainActor
final class WebPages {
    static let shared = WebPages()

    /// One live page per card, kept while the card shows it — so moving, zooming or redrawing the canvas never
    /// reloads the page or stops its video.
    private var pages: [UUID: WebPage] = [:]

    func page(for id: UUID, url: URL) -> WebPage {
        if let page = pages[id] { return page }
        let page = WebPage(url: url)
        pages[id] = page
        return page
    }

    func existing(_ id: UUID) -> WebPage? { pages[id] }

    /// The canvas opened: a page that's empty (its web process was stopped while Swiss sat in the background,
    /// or it never got to load) loads again instead of staying white.
    func wakeAll() {
        for page in pages.values { page.wake() }
    }

    /// The canvas closed: videos and sounds on its pages stop (they'd play on with nothing on screen to stop them).
    func pauseAll() {
        for page in pages.values { page.web.pauseAllMediaPlayback() }
    }

    /// Pages whose card is gone (deleted, cleared, back to a plain link) are closed.
    func keepOnly(_ ids: Set<UUID>) {
        for id in pages.keys where !ids.contains(id) {
            pages[id]?.close()
            pages[id] = nil
        }
    }
}

@MainActor
final class WebPage: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let web: WKWebView
    /// The link's own address: where the page starts, and where it starts again if it went blank.
    private let home: URL
    private var stopped = false
    @Published private(set) var canGoBack = false
    @Published private(set) var loading = false

    init(url: URL) {
        home = url
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // logins stay (Swiss's own, apart from Safari)
        config.preferences.isElementFullscreenEnabled = true // a video's full-screen button works
        config.mediaTypesRequiringUserActionForPlayback = .audio // like Safari: nothing with sound starts until you press play
        // Says it's Safari (it is Safari's engine): some video players and course sites won't play for an unknown browser.
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        web = WKWebView(frame: .zero, configuration: config)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.allowsMagnification = true
        if Safety.isWebURL(url) { web.load(URLRequest(url: url)) }
    }

    func wake() {
        guard stopped || web.url == nil, Safety.isWebURL(home), !web.isLoading else { return }
        stopped = false
        web.load(URLRequest(url: web.url ?? home))
        if TestMode.isOn { FileHandle.standardError.write("page loads again: \(web.url?.host ?? home.host ?? "-")\n".data(using: .utf8)!) }
    }

    // macOS stopped the page's web process (memory, a crash): it would stay white. Load it again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        stopped = true
        if TestMode.isOn { FileHandle.standardError.write("page process stopped (on screen: \(webView.window != nil))\n".data(using: .utf8)!) }
        if webView.window != nil { wake() } // on screen: right away; otherwise when the canvas next opens
    }

    func goBack() { web.goBack() }
    func reload() { web.reload() }
    var currentURL: URL? { web.url }

    func close() {
        web.stopLoading()
        web.pauseAllMediaPlayback()
        web.navigationDelegate = nil
        web.uiDelegate = nil
        web.removeFromSuperview()
    }

    // Web pages stay inside; anything else (mailto:, another app's link…) is Swiss's usual question.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        let inFrame = action.targetFrame?.isMainFrame == false // a page's own parts (players, embeds)
        if ["http", "https"].contains(scheme) || (inFrame && ["about", "blob", "data"].contains(scheme)) || url.absoluteString == "about:blank" {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated { Safety.openLink(url) }
    }

    // Something the page can't show (a file to download): your browser gets it.
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        if response.canShowMIMEType || !response.isForMainFrame { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if let url = response.response.url, Safety.isWebURL(url) { NSWorkspace.shared.open(url) }
    }

    // "Open in a new window" links open right here.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, Safety.isWebURL(url) { webView.load(URLRequest(url: url)) }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { refresh() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refresh() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { refresh() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { refresh() }

    private func refresh() {
        canGoBack = web.canGoBack
        loading = web.isLoading
    }
}

/// The live page inside a card. The page is drawn at the canvas's zoom, so zooming the canvas zooms the page too.
struct WebPageView: NSViewRepresentable {
    let page: WebPage
    let zoom: CGFloat

    func makeNSView(context: Context) -> NSView {
        let box = NSView()
        place(in: box)
        page.web.pageZoom = max(0.3, min(3, zoom)) // at the canvas's zoom from the start
        page.wake()
        return box
    }

    func updateNSView(_ box: NSView, context: Context) {
        if page.web.superview !== box { place(in: box) }
        let z = max(0.3, min(3, zoom))
        if abs(page.web.pageZoom - z) > 0.01 { page.web.pageZoom = z }
    }

    private func place(in box: NSView) {
        page.web.removeFromSuperview()
        page.web.frame = box.bounds
        page.web.autoresizingMask = [.width, .height]
        box.addSubview(page.web)
    }
}
