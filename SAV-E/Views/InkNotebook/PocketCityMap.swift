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
    var isSaved = false
    var publicVenueID: String?
    var category: String?
    var address: String?

    var payload: [String: Any] {
        var value: [String: Any] = ["id": id, "name": name, "label": label,
            "point": [longitude, latitude], "kind": kind.rawValue, "selected": selected,
            "isSaved": isSaved || kind == .saved || kind == .visited]
        value["publicVenueID"] = publicVenueID
        value["address"] = address
        value["category"] = category
        return value
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

struct PocketCityRoute: Equatable {
    let points: [[Double]]

    init?(_ polyline: MKPolyline) {
        guard polyline.pointCount >= 2 else { return nil }
        let mapPoints = UnsafeBufferPointer(start: polyline.points(), count: polyline.pointCount)
        let coordinates = mapPoints.map(\.coordinate)
        guard coordinates.allSatisfy(CLLocationCoordinate2DIsValid) else { return nil }
        points = coordinates.map { [$0.longitude, $0.latitude] }
    }
}

struct PocketCityPresentation: Equatable {
    enum Weather: String, CaseIterable { case day, cloudy, drizzle, rain }
    var weather: Weather = .day
    var metro = false
    var showsPublicPins = true

    var payload: [String: Any] {
        ["weather": weather.rawValue, "metro": metro,
         "showsPublicPins": showsPublicPins]
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

/// Account and post ownership remain native. The bundled page sends only the
/// currently selected atlas branch's public, displayable information.
struct PocketCityPlaceDetail: Equatable {
    struct Photo: Equatable {
        let file: URL
        let alternative: String
        let credit: String
        let original: URL
    }
    struct Cover: Equatable {
        let url: URL
        let expiresAt: Date
    }
    struct Post: Identifiable, Equatable {
        var id: URL { url }
        let platform: String
        let title: String
        let author: String
        let url: URL
        let expiresAt: Date
        let cover: Cover?
    }

    let serial: Int
    let name: String
    let kind: String
    let address: String
    let directions: URL?
    let website: URL?
    let websiteLabel: String
    let photo: Photo?
    let posts: [Post]
    let choices: [String]
    let savedActionLabel: String?
    let friendAction: Bool

    private static func https(_ raw: Any?) -> URL? {
        guard let string = raw as? String, let url = URL(string: string), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.port == nil else { return nil }
        return url
    }

    init?(_ data: [String: Any]) {
        guard let serial = data["serial"] as? Int, serial > 0,
              let name = data["name"] as? String, !name.isEmpty else { return nil }
        self.serial = serial
        self.name = name
        kind = data["kind"] as? String ?? ""
        address = data["address"] as? String ?? ""
        directions = Self.https(data["directions"]).flatMap { url in
            guard url.host == "maps.apple.com", url.path == "/" || url.path.isEmpty,
                  let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  query.count == 1, query[0].name == "daddr",
                  let values = query[0].value?.components(separatedBy: ","), values.count == 2,
                  let lat = Double(values[0]), let lng = Double(values[1]), lat.isFinite, lng.isFinite,
                  abs(lat) <= 90, abs(lng) <= 180 else { return nil }
            return url
        }
        website = Self.https(data["website"])
        websiteLabel = data["websiteLabel"] as? String ?? ""
        choices = data["choices"] as? [String] ?? []
        savedActionLabel = (data["savedActionLabel"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        friendAction = data["friendAction"] as? Bool == true
        photo = (data["photo"] as? [String: Any]).flatMap { raw in
            guard let name = raw["file"] as? String,
                  ["raohe-pepper-bun.jpg", "fu-hang-soy-milk.jpg", "ay-chung-ximen.jpg", "mei-36.jpg",
                   "mei-47.jpg", "din-tai-fung-xinyi.jpg", "tianjin.jpg", "yong-kang.jpg",
                   "fubon-museum.jpg"].contains(name),
                  let file = Bundle.main.url(forResource: name, withExtension: nil,
                                             subdirectory: "PocketCity/assets/place-photos"),
                  let alternative = raw["alt"] as? String, !alternative.isEmpty,
                  let credit = raw["credit"] as? String, !credit.isEmpty, let original = Self.https(raw["url"]),
                  original.host == "commons.wikimedia.org", original.path.hasPrefix("/wiki/File:")
            else { return nil }
            return Photo(file: file, alternative: alternative, credit: credit, original: original)
        }
        let now = Date()
        let sourceExpiry = (data["sourceExpiry"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        posts = (data["posts"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let platform = raw["platform"] as? String, let url = Self.https(raw["url"]),
                  url.query == nil, url.fragment == nil, let millis = raw["expiresAt"] as? Double, millis.isFinite
            else { return nil }
            let expiry = min(Date(timeIntervalSince1970: millis / 1000), sourceExpiry ?? .distantFuture)
            guard expiry > now else { return nil }
            let isIG = platform == "instagram" && url.host == "www.instagram.com"
                && url.path.range(of: #"^/(p|reel|tv)/[a-zA-Z0-9_-]+/?$"#, options: .regularExpression) != nil
            let isThreads = platform == "threads" && url.host == "www.threads.com"
                && url.path.range(of: #"^/@[a-zA-Z0-9_.]+/post/[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil
            guard isIG || isThreads else { return nil }
            let cover: Cover? = (raw["cover"] as? [String: Any]).flatMap { value in
                guard let permission = value["permission"] as? String, ["author", "provider"].contains(permission),
                      let coverURL = Self.https(value["url"]), let host = coverURL.host?.lowercased(),
                      ["cdninstagram.com", "fbcdn.net"].contains(where: { host == $0 || host.hasSuffix("." + $0) }),
                      let millis = value["expiresAt"] as? Double, millis.isFinite else { return nil }
                let deadline = min(expiry, Date(timeIntervalSince1970: millis / 1000))
                return deadline > now ? Cover(url: coverURL, expiresAt: deadline) : nil
            }
            return Post(platform: isIG ? "Instagram" : "Threads", title: raw["title"] as? String ?? "",
                        author: raw["author"] as? String ?? "", url: url, expiresAt: expiry, cover: cover)
        }
    }
}

@MainActor
final class PocketCityPlaceDrawer: ObservableObject {
    @Published private(set) var detail: PocketCityPlaceDetail?
    private var send: ((String, Int?) -> Void)?

    func present(_ next: PocketCityPlaceDetail, send: @escaping (String, Int?) -> Void) {
        self.send = send
        if detail != next { detail = next }
    }

    func dismiss() {
        send = nil
        if detail != nil { detail = nil }
    }

    func action(_ action: String, serial: Int, index: Int? = nil) {
        guard detail?.serial == serial else { return }
        send?(action, index)
    }
}

struct PocketCityMap: UIViewRepresentable {
    var pins: [PocketCityPin]
    var viewport: PocketCityViewport?
    var userDot: PocketCityUserDot? = nil
    var routes: [PocketCityRoute] = []
    var presentation: PocketCityPresentation? = nil
    var creditsRequest = 0
    var pageVisible = true
    var onPlaceSheet: (Bool) -> Void = { _ in }
    var placeDrawer: PocketCityPlaceDrawer? = nil
    var allowsRemoteTiles = true
    var onSelect: ([String]) -> Void
    var onMove: (MKCoordinateRegion) -> Void = { _ in }
    var onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "pocketMap")
        if !allowsRemoteTiles, placeDrawer != nil {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "window.savvyNativePlaceSheet = true;",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.allowsLinkPreview = false
        view.accessibilityIdentifier = "pocket.city.map"
        context.coordinator.start(view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let creditsChanged = context.coordinator.screen.creditsRequest != creditsRequest
        let leftPage = context.coordinator.screen.pageVisible && !pageVisible
        context.coordinator.screen = self
        context.coordinator.sync()
        if creditsChanged { context.coordinator.showMapCredits() }
        if leftPage { context.coordinator.dismissPlaceSheet() }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "pocketMap")
        view.stopLoading()
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var screen: PocketCityMap
        private let allowsRemoteTiles: Bool
        private weak var web: WKWebView?
        private var server: PocketCityAssetServer?
        private var page: URL?
        private var ready = false
        private var pendingMapCredits = false
        private var sentPins: [PocketCityPin]?
        private var sentDot: PocketCityUserDot?
        private var sentViewport: PocketCityViewport?
        private var sentRoutes: [PocketCityRoute] = []
        private var sentPresentation: PocketCityPresentation?
        private var watchdog: Task<Void, Never>?
        private var pageGeneration = 0
        private var lastRecovery: TimeInterval?
        private var viewportSerial = 0
        private var lastCamera: [Double]?
        private var cameraToRestore: [Double]?
        private var viewportBeforeRecovery: PocketCityViewport?

        init(_ screen: PocketCityMap) {
            self.screen = screen
            allowsRemoteTiles = screen.allowsRemoteTiles
        }

        func start(_ web: WKWebView) {
            self.web = web
            startWatchdog()
            guard let root = Bundle.main.url(forResource: "PocketCity", withExtension: nil) else {
                Task { self.fail() }
                return
            }
            let server = PocketCityAssetServer(root: root, allowsRemoteTiles: allowsRemoteTiles)
            self.server = server
            server.start { [weak self] url in
                guard let self, let web = self.web else { return }
                guard let url else { self.fail(); return }
                self.page = url
                web.load(URLRequest(url: url))
            }
        }

        private func startWatchdog() {
            watchdog?.cancel()
            watchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(35))
                if !Task.isCancelled { self?.fail() }
            }
        }

        private func recoverContentProcess(_ view: WKWebView) {
            guard web === view, let page else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard lastRecovery.map({ now - $0 > 60 }) ?? true else {
                // The process notification and a failed bridge call can describe the same exit.
                if ready { fail() }
                return
            }
            lastRecovery = now
            screen.placeDrawer?.dismiss()
            screen.onPlaceSheet(false)
            pendingMapCredits = false
            cameraToRestore = lastCamera
            viewportBeforeRecovery = sentViewport
            pageGeneration += 1
            ready = false
            sentPins = nil
            sentDot = nil
            sentViewport = nil
            sentPresentation = nil
            sentRoutes = []
            startWatchdog()
            view.load(URLRequest(url: page))
        }

        func stop() {
            watchdog?.cancel()
            web = nil
            pendingMapCredits = false
            ready = false
            server?.stop()
            server = nil
        }

        private func fail() {
            guard web != nil else { return }
            screen.placeDrawer?.dismiss()
            screen.onPlaceSheet(false)
            stop()
            screen.onFailure()
        }

        func dismissPlaceSheet() {
            pendingMapCredits = false
            guard ready, let web else { return }
            web.evaluateJavaScript("window.savvyDismissPlaceSheet?.()")
        }

        func showMapCredits() {
            guard let web else { return }
            guard ready else {
                pendingMapCredits = true
                return
            }
            pendingMapCredits = false
            web.evaluateJavaScript("window.savvyShowMapCredits?.()")
        }

        func sync() {
            guard ready, let web else { return }
            let pinsChanged = screen.pins != sentPins
            let viewportChanged = screen.viewport != sentViewport
            let dotChanged = screen.userDot != sentDot
            let routes = allowsRemoteTiles ? [] : screen.routes
            let routesChanged = routes != sentRoutes
            let presentationChanged = screen.presentation != sentPresentation
            guard pinsChanged || viewportChanged || dotChanged || routesChanged || presentationChanged else { return }
            var args: [String: Any] = [:]
            if pinsChanged { args["pins"] = screen.pins.map(\.payload) }
            if viewportChanged {
                lastCamera = nil
                viewportSerial += 1
                args["bounds"] = screen.viewport.map { $0.bounds as Any } ?? NSNull()
            }
            args["viewportSerial"] = viewportSerial
            if routesChanged { args["routes"] = routes.map(\.points) }
            if presentationChanged, let presentation = screen.presentation {
                args["presentation"] = presentation.payload
            }
            if dotChanged {
                if let dot = screen.userDot { args["user"] = ["point": [dot.longitude, dot.latitude], "label": dot.label] as [String: Any] }
                else { args["user"] = NSNull() }
                sentDot = screen.userDot
            }
            if let cameraToRestore, viewportBeforeRecovery == screen.viewport {
                args["restoreCamera"] = cameraToRestore
            }
            cameraToRestore = nil
            sentPins = screen.pins
            sentViewport = screen.viewport
            sentRoutes = routes
            sentPresentation = screen.presentation
            let generation = pageGeneration
            web.callAsyncJavaScript("window.savvyPocketHost.update(state)", arguments: ["state": args],
                                    in: nil, in: .page) { [weak self] result in
                guard let self, self.pageGeneration == generation, case .failure(let error) = result else { return }
                let failure = error as NSError
                if failure.domain == WKError.errorDomain, failure.code == WKError.webContentProcessTerminated.rawValue {
                    self.recoverContentProcess(web)
                } else {
                    self.fail()
                }
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

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { recoverContentProcess(webView) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            let failure = error as NSError
            if failure.domain == NSURLErrorDomain, failure.code == NSURLErrorCancelled { return }
            fail()
        }

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
                if pendingMapCredits { showMapCredits() }
            case "failure": fail()
            case "placeDetail" where ready:
                guard screen.pageVisible, let drawer = screen.placeDrawer,
                      let data = body["detail"] as? [String: Any], let detail = PocketCityPlaceDetail(data)
                else { return }
                let serial = detail.serial
                drawer.present(detail) { [weak self] action, index in
                    guard let self, let web = self.web, self.ready, self.screen.pageVisible,
                          self.screen.placeDrawer?.detail?.serial == serial else { return }
                    web.callAsyncJavaScript("window.savvyPlaceSheetAction(serial, action, index)",
                        arguments: ["serial": serial, "action": action, "index": index.map { $0 as Any } ?? NSNull()],
                        in: nil, in: .page, completionHandler: nil)
                }
                screen.onPlaceSheet(true)
            case "placeSheet" where ready:
                guard let open = body["open"] as? Bool else { return }
                if !open { screen.placeDrawer?.dismiss() }
                if screen.pageVisible { screen.onPlaceSheet(open) }
                else if open { dismissPlaceSheet() }
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
                guard (body["viewportSerial"] as? Int ?? 0) == viewportSerial else { return }
                if let camera = body["camera"] as? [Double], camera.count == 5, camera.allSatisfy(\.isFinite),
                   (-180...180).contains(camera[0]), (-90...90).contains(camera[1]),
                   (-2...21.6).contains(camera[2]), (-180...180).contains(camera[3]), (0...65).contains(camera[4]) {
                    lastCamera = camera
                }
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
    var routes: [PocketCityRoute] = []
    var presentation: PocketCityPresentation? = nil
    var creditsRequest = 0
    var pageVisible = true
    var onPlaceSheet: (Bool) -> Void = { _ in }
    var placeDrawer: PocketCityPlaceDrawer? = nil
    var allowsRemoteTiles = true
    var onSelect: (String) -> Void
    var onMove: (MKCoordinateRegion) -> Void = { _ in }
    var onFailure: () -> Void
    @State private var choices: [String] = []
    @State private var showingChoices = false

    var body: some View {
        PocketCityMap(pins: pins, viewport: viewport, userDot: userDot, routes: routes, presentation: presentation,
                      creditsRequest: creditsRequest, pageVisible: pageVisible, onPlaceSheet: onPlaceSheet,
                      placeDrawer: placeDrawer, allowsRemoteTiles: allowsRemoteTiles, onSelect: { ids in
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
