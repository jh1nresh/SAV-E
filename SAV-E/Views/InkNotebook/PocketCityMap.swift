import MapKit
import SwiftUI
import WebKit

/// Only the fields a button on the map needs. Source posts, notes, account IDs
/// and location history stay with the native screen that owns the selection.
struct PocketCityPin: Equatable {
    let id: String
    let name: String
    let label: String
    let latitude: Double
    let longitude: Double
    enum Kind: String { case saved, visited, post, search, shared }
    var kind: Kind
    var selected = false

    var payload: [String: Any] {
        ["id": id, "name": name, "label": label, "point": [longitude, latitude],
         "kind": kind.rawValue, "selected": selected]
    }
}

struct PocketCityUserDot: Equatable {
    let longitude: Double
    let latitude: Double
    let label: String

    init?(_ coordinate: CLLocationCoordinate2D?, label: String) {
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        longitude = coordinate.longitude
        latitude = coordinate.latitude
        self.label = label
    }
}

struct PocketCityViewport: Equatable {
    let longitude: Double
    let latitude: Double
    let width: Double
    let height: Double
    let requestID: Int

    init?(_ region: MKCoordinateRegion?, requestID: Int = 0) {
        guard let region, CLLocationCoordinate2DIsValid(region.center),
              region.span.latitudeDelta.isFinite, region.span.longitudeDelta.isFinite,
              region.span.latitudeDelta > 0, region.span.longitudeDelta > 0 else { return nil }
        longitude = region.center.longitude
        latitude = region.center.latitude
        width = min(360, region.span.longitudeDelta)
        height = min(170, region.span.latitudeDelta)
        self.requestID = requestID
    }

    var bounds: [Double] {
        [longitude - width / 2, min(85, max(-85, latitude - height / 2)),
         longitude + width / 2, max(-85, min(85, latitude + height / 2))]
    }
}

struct PocketCityMap: UIViewRepresentable {
    var pins: [PocketCityPin]
    var viewport: PocketCityViewport?
    var userDot: PocketCityUserDot? = nil
    var onSelect: ([String]) -> Void
    var onMove: (MKCoordinateRegion) -> Void = { _ in }
    var onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "pocketMap")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.allowsLinkPreview = false
        view.accessibilityIdentifier = "pocket.city.map"
        context.coordinator.start(view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.screen = self
        context.coordinator.sync()
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "pocketMap")
        view.stopLoading()
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var screen: PocketCityMap
        private weak var web: WKWebView?
        private var server: PocketCityAssetServer?
        private var page: URL?
        private var ready = false
        private var sentPins: [PocketCityPin]?
        private var sentDot: PocketCityUserDot?
        private var sentViewport: PocketCityViewport?
        private var watchdog: Task<Void, Never>?

        init(_ screen: PocketCityMap) { self.screen = screen }

        func start(_ web: WKWebView) {
            self.web = web
            watchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(35))
                if !Task.isCancelled { self?.fail() }
            }
            guard let root = Bundle.main.url(forResource: "PocketCity", withExtension: nil) else {
                Task { self.fail() }
                return
            }
            let server = PocketCityAssetServer(root: root)
            self.server = server
            server.start { [weak self] url in
                guard let self, let web = self.web else { return }
                guard let url else { self.fail(); return }
                self.page = url
                web.load(URLRequest(url: url))
            }
        }

        func stop() {
            watchdog?.cancel()
            web = nil
            ready = false
            server?.stop()
            server = nil
        }

        private func fail() {
            guard web != nil else { return }
            stop()
            screen.onFailure()
        }

        func sync() {
            guard ready, let web else { return }
            let pinsChanged = screen.pins != sentPins
            let viewportChanged = screen.viewport != sentViewport
            let dotChanged = screen.userDot != sentDot
            guard pinsChanged || viewportChanged || dotChanged else { return }
            var args: [String: Any] = [:]
            if pinsChanged { args["pins"] = screen.pins.map(\.payload) }
            if viewportChanged { args["bounds"] = screen.viewport.map { $0.bounds as Any } ?? NSNull() }
            if dotChanged {
                if let dot = screen.userDot { args["user"] = ["point": [dot.longitude, dot.latitude], "label": dot.label] as [String: Any] }
                else { args["user"] = NSNull() }
                sentDot = screen.userDot
            }
            sentPins = screen.pins
            sentViewport = screen.viewport
            web.callAsyncJavaScript("window.savvyPocketHost.update(state)", arguments: ["state": args],
                                    in: nil, in: .page) { [weak self] result in
                if case .failure = result { self?.fail() }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.targetFrame?.isMainFrame == true, action.request.url == page {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                if action.navigationType == .linkActivated, action.sourceFrame.isMainFrame,
                   action.sourceFrame.request.url == page, let url = action.request.url, url.scheme == "https" {
                    UIApplication.shared.open(url)
                }
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) { fail() }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard web != nil, message.frameInfo.isMainFrame, let page,
                  let url = message.frameInfo.request.url,
                  url.scheme == page.scheme, url.host == page.host, url.port == page.port,
                  url.path == page.path, let body = message.body as? [String: Any] else { return }
            switch body["event"] as? String {
            case "ready":
                watchdog?.cancel()
                ready = true
                sync()
            case "failure": fail()
            case "select" where ready:
                guard let ids = body["ids"] as? [String] else { return }
                let requested = Set(ids)
                let current = screen.pins.map(\.id).filter(requested.contains)
                if !current.isEmpty { screen.onSelect(current) }
            case "move" where ready:
                guard let values = body["region"] as? [Double], values.count == 4,
                      values.allSatisfy(\.isFinite), (-180...180).contains(values[0]),
                      (-85...85).contains(values[1]), (0...360).contains(values[2]),
                      (0...180).contains(values[3]), values[2] > 0, values[3] > 0 else { return }
                screen.onMove(.init(center: .init(latitude: values[1], longitude: values[0]),
                                    span: .init(latitudeDelta: values[3], longitudeDelta: values[2])))
            default: break
            }
        }
    }
}

/// The same coordinate can belong to several stores. Recheck the selected ID
/// against the latest visible pins after the chooser returns.
struct PocketCitySurface: View {
    @Environment(\.appLanguageSettings) private var language
    var pins: [PocketCityPin]
    var viewport: PocketCityViewport?
    var userDot: PocketCityUserDot? = nil
    var onSelect: (String) -> Void
    var onMove: (MKCoordinateRegion) -> Void = { _ in }
    var onFailure: () -> Void
    @State private var choices: [String] = []
    @State private var showingChoices = false

    var body: some View {
        PocketCityMap(pins: pins, viewport: viewport, userDot: userDot, onSelect: { ids in
            if ids.count == 1, let id = ids.first { onSelect(id) }
            else { choices = ids; showingChoices = true }
        }, onMove: onMove, onFailure: onFailure)
        .confirmationDialog(language.localized(english: "Choose a place", traditionalChinese: "選擇地點"),
                            isPresented: $showingChoices, titleVisibility: .visible) {
            ForEach(pins.filter { choices.contains($0.id) }, id: \.id) { pin in
                Button(pin.label) { onSelect(pin.id) }
            }
        }
    }
}
