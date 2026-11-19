#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import SwiftUI
import WebKit

@MainActor
struct LiveSourcePostView: View {
    let source: LiveSourcePostURL
    let expiresAt: Date
    let isCurrent: @MainActor () -> Bool
    let onClose: () -> Void
    @StateObject private var model = LiveSourcePostModel()
    @State private var attempt = 0
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(source.platform.displayName).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: close) {
                    Text(copy("Done", "完成")).font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("live.sourcePost.close")
            }

            if canRead(), let html = model.html, let renderID = model.renderID {
                LiveSourcePostWebView(html: html, source: source, restrictToOriginalEmbed: true,
                    isCurrent: canRead, onRevoked: close,
                    onFailure: { model.rendererFailed(renderID: renderID, isCurrent: canRead) })
                    .id(renderID)
                    .accessibilityIdentifier("live.sourcePost.web")
            } else {
                if model.state == .failed {
                    Text(copy("This post is unavailable here.", "暫時無法顯示此貼文。"))
                        .accessibilityIdentifier("live.sourcePost.unavailable")
                    Button(copy("Try again", "再試一次")) { attempt &+= 1 }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("live.sourcePost.retry")
                } else {
                    ProgressView(copy("Loading original post…", "正在載入原始貼文…"))
                }
                Spacer()
            }

            Button {
                guard canRead() else { close(); return }
                openURL(source.originalURL)
            } label: {
                Label(copy("Open original link", "開啟原始連結"), systemImage: "arrow.up.right")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("live.sourcePost.original")
        }
        .padding(16).background(DateTheme.canvas.ignoresSafeArea())
        .foregroundStyle(DateTheme.ink).tint(DateTheme.blue)
        .task(id: attempt) {
            guard canRead() else { close(); return }
            await model.load(source: source, isCurrent: canRead)
        }
        .task(id: expiresAt) {
            do { try await Task.sleep(for: .seconds(max(0, expiresAt.timeIntervalSinceNow))) }
            catch { return }
            close()
        }
        .onChange(of: isCurrent()) { _, allowed in if !allowed { close() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { close() } }
        .onDisappear { model.cancel() }
    }

    private func canRead() -> Bool { Date() < expiresAt && isCurrent() }
    private func close() { onClose(); model.cancel() }

    private func copy(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

/// Navigation is restricted; provider-driven HTTPS subresources are intentionally allowed.
/// This is an unprivileged nonpersistent web view, not an app-data or JavaScript bridge.
enum LiveSourcePostWebPolicy {
    static func hosts(_ platform: LiveSourcePostPlatform) -> Set<String> {
        switch platform {
        case .instagram: return ["instagram.com", "www.instagram.com"]
        case .threads: return ["threads.com", "www.threads.com", "threads.net", "www.threads.net"]
        }
    }

    static func allowsNavigation(_ url: URL?, platform: LiveSourcePostPlatform,
                                 allowInitialBlank: Bool = false) -> Bool {
        guard let url else { return false }
        if url.absoluteString == "about:blank" { return allowInitialBlank }
        return url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
            && url.port == nil && hosts(platform).contains(url.host?.lowercased() ?? "")
    }

    static func baseURL(_ platform: LiveSourcePostPlatform) -> URL {
        URL(string: platform == .instagram ? "https://www.instagram.com/" : "https://www.threads.com/")!
    }

    static func embedURL(for source: LiveSourcePostURL) -> URL {
        switch source.platform {
        case .instagram: return URL(string: source.canonicalURL.absoluteString + "/embed/captioned/")!
        case .threads: return URL(string: "https://www.threads.com/t/\(source.canonicalURL.lastPathComponent)/embed/")!
        }
    }

    static func allowsOriginalEmbed(_ url: URL?, source: LiveSourcePostURL) -> Bool {
        guard let url, allowsNavigation(url, platform: source.platform),
              let actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let expected = URLComponents(url: embedURL(for: source), resolvingAgainstBaseURL: false) else { return false }
        let path = actual.percentEncodedPath
        return path == expected.percentEncodedPath || path + "/" == expected.percentEncodedPath
    }

    static func document(_ html: String, platform: LiveSourcePostPlatform) -> String {
        let frames = hosts(platform).sorted().map { "https://\($0)" }.joined(separator: " ")
        let policy = "default-src 'none'; script-src \(frames) https://platform.instagram.com; style-src 'unsafe-inline' https:; img-src https: data:; font-src https: data:; connect-src https:; media-src https: blob:; frame-src \(frames); object-src 'none'; base-uri 'none'; form-action 'none'; upgrade-insecure-requests"
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><meta http-equiv="Content-Security-Policy" content="\(policy)"><style>html,body{margin:0;padding:0;background:transparent;color-scheme:light dark;color:CanvasText;font:-apple-system-body;}iframe,blockquote{max-width:100%!important;margin-left:auto!important;margin-right:auto!important;}</style></head><body>\(html)</body></html>
        """
    }
}

@MainActor
struct LiveSourcePostWebView: UIViewRepresentable {
    let html: String
    let source: LiveSourcePostURL
    let restrictToOriginalEmbed: Bool
    let isCurrent: @MainActor () -> Bool
    let onRevoked: () -> Void
    let onFailure: () -> Void

    init(html: String, source: LiveSourcePostURL, restrictToOriginalEmbed: Bool = false,
         isCurrent: @escaping @MainActor () -> Bool,
         onRevoked: @escaping () -> Void, onFailure: @escaping () -> Void = {}) {
        self.html = html; self.source = source; self.isCurrent = isCurrent
        self.restrictToOriginalEmbed = restrictToOriginalEmbed
        self.onRevoked = onRevoked; self.onFailure = onFailure
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(source: source, restrictToOriginalEmbed: restrictToOriginalEmbed,
                                      isCurrent: isCurrent, onRevoked: onRevoked, onFailure: onFailure)
        return coordinator
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false; view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.allowsLinkPreview = false
        context.coordinator.render(html, in: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.isCurrent = isCurrent
        context.coordinator.onRevoked = onRevoked
        context.coordinator.render(html, in: view)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stop(view)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let source: LiveSourcePostURL
        private let restrictToOriginalEmbed: Bool
        var isCurrent: @MainActor () -> Bool
        var onRevoked: () -> Void
        private let onFailure: () -> Void
        private weak var renderedView: WKWebView?
        private var mainNavigation: WKNavigation?
        private var renderGeneration = UUID()
        private var renderedHTML: String?
        private var hasRevoked = false
        private var isBootstrapping = true
        private var embedDeadline: Task<Void, Never>?

        private var loadsThreadsEmbedDirectly: Bool {
            restrictToOriginalEmbed && source.platform == .threads
        }

        init(source: LiveSourcePostURL, restrictToOriginalEmbed: Bool = false,
             isCurrent: @escaping @MainActor () -> Bool,
             onRevoked: @escaping () -> Void, onFailure: @escaping () -> Void = {}) {
            self.source = source; self.isCurrent = isCurrent; self.onRevoked = onRevoked
            self.restrictToOriginalEmbed = restrictToOriginalEmbed
            self.onFailure = onFailure
        }

        func render(_ html: String, in view: WKWebView) {
            guard isCurrent() else { revoke(view); return }
            guard !hasRevoked, renderedHTML != html,
                  renderedView == nil || renderedView === view else { return }
            renderedView = view
            renderedHTML = html
            renderGeneration = UUID()
            isBootstrapping = true
            embedDeadline?.cancel()
            // The official blockquote markup creates the frame asynchronously via embed.js.
            if restrictToOriginalEmbed {
                let ticket = renderGeneration
                embedDeadline = Task { @MainActor [weak self, weak view] in
                    do { try await Task.sleep(for: .seconds(10)) }
                    catch { return }
                    guard let self, let view, self.renderGeneration == ticket else { return }
                    self.rendererFailed(view)
                }
            }
            if loadsThreadsEmbedDirectly {
                // The tokenless quote can contain only a link card. Visit its exact
                // publisher embed in this isolated reader to show the original body.
                mainNavigation = view.load(URLRequest(url: LiveSourcePostWebPolicy.embedURL(for: source)))
            } else {
                mainNavigation = view.loadHTMLString(LiveSourcePostWebPolicy.document(html, platform: source.platform),
                                    baseURL: LiveSourcePostWebPolicy.baseURL(source.platform))
            }
        }

        func stop(_ view: WKWebView) {
            guard renderedView == nil || renderedView === view else { return }
            let wasStopped = hasRevoked
            hasRevoked = true; renderedHTML = nil; mainNavigation = nil; renderedView = nil
            embedDeadline?.cancel()
            embedDeadline = nil
            renderGeneration = UUID()
            guard !wasStopped else { return }
            view.stopLoading(); view.navigationDelegate = nil; view.uiDelegate = nil
            view.loadHTMLString("", baseURL: nil)
        }

        private func revoke(_ view: WKWebView) {
            guard !hasRevoked, renderedView == nil || renderedView === view else { return }
            stop(view)
            let ticket = renderGeneration
            // Both coordinator teardown and the view's renderID fence a queued close.
            Task { @MainActor [weak self, onRevoked] in
                guard let self, self.renderGeneration == ticket else { return }
                onRevoked()
            }
        }

        func allowsNavigation(_ url: URL?, isMainFrame: Bool) -> Bool {
            guard !hasRevoked, isCurrent() else { return false }
            if loadsThreadsEmbedDirectly {
                return isBootstrapping && isMainFrame && LiveSourcePostWebPolicy.allowsOriginalEmbed(url, source: source)
            }
            if restrictToOriginalEmbed {
                if isMainFrame {
                    return isBootstrapping && (url?.absoluteString == "about:blank"
                        || url == LiveSourcePostWebPolicy.baseURL(source.platform))
                }
                return LiveSourcePostWebPolicy.allowsOriginalEmbed(url, source: source)
            }
            return LiveSourcePostWebPolicy.allowsNavigation(url, platform: source.platform,
                    allowInitialBlank: isBootstrapping && isMainFrame)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard !hasRevoked, isCurrent() else { revoke(webView); decisionHandler(.cancel); return }
            let allowed = navigationAction.navigationType != .formSubmitted
                && navigationAction.navigationType != .formResubmitted
                && allowsNavigation(navigationAction.request.url,
                    isMainFrame: navigationAction.targetFrame?.isMainFrame == true)
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
            guard !hasRevoked, isCurrent() else { revoke(webView); decisionHandler(.cancel); return }
            let allowed = allowsNavigation(navigationResponse.response.url, isMainFrame: navigationResponse.isForMainFrame)
            if restrictToOriginalEmbed, allowed, navigationResponse.isForMainFrame == loadsThreadsEmbedDirectly,
               let response = navigationResponse.response as? HTTPURLResponse {
                guard (200..<300).contains(response.statusCode), navigationResponse.canShowMIMEType else {
                    decisionHandler(.cancel)
                    rendererFailed(webView)
                    return
                }
                embedDeadline?.cancel()
                embedDeadline = nil
            }
            decisionHandler(allowed ? .allow : .cancel)
        }

        // WebKit reports didStartProvisionalNavigation for the main frame only.
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            guard !hasRevoked, renderedView === webView, isCurrent(), let navigation else { return }
            mainNavigation = navigation
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) { isBootstrapping = false }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            navigationFailed(navigation, in: webView, error: error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            navigationFailed(navigation, in: webView, error: error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { rendererFailed(webView) }


        private func navigationFailed(_ navigation: WKNavigation?, in view: WKWebView, error: Error) {
            guard let navigation, navigation === mainNavigation, !(error is CancellationError) else { return }
            let error = error as NSError
            // Explicit stops and rejected navigation are not display failures.
            guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled),
                  !(error.domain == "WebKitErrorDomain" && error.code == 102) else { return }
            rendererFailed(view)
        }

        private func rendererFailed(_ view: WKWebView) {
            guard !hasRevoked, renderedView === view, renderedHTML != nil else { return }
            stop(view)
            let ticket = renderGeneration
            // Fence dismantling/revocation before notifying SwiftUI outside its update pass.
            // The model additionally checks the bound attempt before revalidating access.
            Task { @MainActor [weak self, onFailure] in
                guard let self, self.renderGeneration == ticket else { return }
                onFailure()
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}


#endif
