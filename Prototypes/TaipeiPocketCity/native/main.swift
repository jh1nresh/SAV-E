import AppKit
import MapKit
import WebKit
import OSLog

private let fuxing = CLLocationCoordinate2D(latitude: 25.027489, longitude: 121.543674)
private let logger = Logger(subsystem: "local.savvy.pocket-city-apple", category: "MapKit")
private let artDiagnostics = CommandLine.arguments.contains("--debug-art")

private func isTaipei(_ coordinate: CLLocationCoordinate2D) -> Bool {
    (24.94...25.23).contains(coordinate.latitude) && (121.43...121.70).contains(coordinate.longitude)
}

@MainActor
private final class ArtHost: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    enum Status { case bridge, painted, degraded, unavailable }
    typealias Result = (Data?, Error?) -> Void
    private struct Tile {
        let path: MKTileOverlayPath
        let result: Result
    }

    private let web: WKWebView
    private let process = Process()
    private var probe: Timer?
    private var origin: URL?
    private var readyFile: URL?
    private var queued = [Tile]()
    private var active = [UUID: (Tile, DispatchWorkItem)]()
    private var ready = false
    private var stopped = false
    private var showedPaint = false
    private var degraded = false
    var onState: ((Status) -> Void)?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 256, height: 256), configuration: config)
        super.init()
        web.navigationDelegate = self
        web.configuration.userContentController.add(self, name: "pocketCityState")
    }

    func start(root: URL, preferredPort: UInt16) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("pocket-city-port-" + UUID().uuidString)
        readyFile = file
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", "-B", root.appendingPathComponent("native/art-server.py").path,
            "--root", root.path, "--port", String(preferredPort), "--ready", file.path,
            "--parent", String(ProcessInfo.processInfo.processIdentifier),
        ]
        do {
            try process.run()
        } catch {
            fail()
            return
        }
        let limit = Date().addingTimeInterval(8)
        probe = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                if self.origin == nil,
                   let value = try? String(contentsOf: file, encoding: .utf8),
                   let bound = UInt16(value), bound > 0 {
                    let base = URL(string: "http://127.0.0.1:\(bound)")!
                    self.origin = base
                    self.web.load(URLRequest(url: base.appendingPathComponent("native/art-host.html")))
                }
                if !self.process.isRunning || Date() > limit {
                    self.fail()
                }
            }
        }
    }

    private func fail() {
        stop()
        onState?(.unavailable)
    }

    private func reportDegraded() {
        guard !stopped, !degraded else { return }
        degraded = true
        onState?(.degraded)
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        probe?.invalidate()
        probe = nil
        web.stopLoading()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "pocketCityState")
        if process.isRunning { process.terminate() }
        if let readyFile { try? FileManager.default.removeItem(at: readyFile) }
        let waiting = queued
        queued.removeAll()
        let running = Array(active.values)
        active.removeAll()
        for tile in waiting { tile.result(nil, nil) }
        for (tile, timeout) in running {
            timeout.cancel()
            tile.result(nil, nil)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.name == "pocketCityState", !stopped,
              let origin, let from = message.frameInfo.request.url, let state = message.body as? String,
              from.scheme == origin.scheme, from.host == origin.host,
              from.port == origin.port, from.path == "/native/art-host.html" else { return }
        switch state {
        case "bridge" where !ready:
            probe?.invalidate()
            probe = nil
            ready = true
            onState?(.bridge)
            drain()
        case "degraded" where ready:
            reportDegraded()
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let target = action.request.url
        let allowed = target?.scheme == "http" && target?.host == origin?.host &&
            target?.port == origin?.port && target?.path == "/native/art-host.html"
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if !stopped { fail() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if !stopped { fail() }
    }

    func request(_ path: MKTileOverlayPath, result: @escaping Result) {
        if artDiagnostics {
            logger.notice("Artwork request z=\(path.z) x=\(path.x) y=\(path.y) scale=\(Double(path.contentScaleFactor))")
        }
        guard !stopped, (16...22).contains(path.z) else { result(nil, nil); return }
        if queued.count >= 48 { queued.removeFirst().result(nil, nil) }
        queued.append(Tile(path: path, result: result))
        drain()
    }

    private func drain() {
        guard ready, !stopped else { return }
        while !queued.isEmpty && active.count < 3 {
            let tile = queued.removeFirst()
            let id = UUID()
            let timeout = DispatchWorkItem { [weak self] in
                self?.reportDegraded()
                self?.finish(id, nil)
            }
            active[id] = (tile, timeout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
            let path = tile.path
            let checkPaint = !showedPaint || artDiagnostics
            Task { [weak self] in
                guard let self, !self.stopped else { return }
                do {
                    let response = try await self.web.callAsyncJavaScript(
                        "return await pocketCityTile(x, y, z, scale, checkPaint)",
                        arguments: ["x": path.x, "y": path.y, "z": path.z,
                                    "scale": Double(path.contentScaleFactor), "checkPaint": checkPaint],
                        in: nil, contentWorld: .page
                    ) as? [String: Any]
                    let data = (response?["png"] as? String).flatMap { value in
                        value.count <= 3_000_000 ? Data(base64Encoded: value) : nil
                    }
                    let image = data.flatMap { data in
                        data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) ? data : nil
                    }
                    if response != nil && image == nil { self.reportDegraded() }
                    self.finish(id, image, painted: response?["painted"] as? Bool == true)
                } catch {
                    self.reportDegraded()
                    self.finish(id, nil)
                }
            }
        }
    }

    private func finish(_ id: UUID, _ data: Data?, painted: Bool = false) {
        guard let (tile, timeout) = active.removeValue(forKey: id) else { return }
        timeout.cancel()
        tile.result(data, nil)
        if artDiagnostics {
            logger.notice("Artwork response z=\(tile.path.z) x=\(tile.path.x) y=\(tile.path.y) bytes=\(data?.count ?? 0) painted=\(painted)")
        }
        if data != nil, painted, !showedPaint {
            showedPaint = true
            if !degraded { onState?(.painted) }
        }
        drain()
    }
}

private final class ArtworkOverlay: MKTileOverlay, @unchecked Sendable {
    private weak var host: ArtHost?

    init(host: ArtHost) {
        self.host = host
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 16
        maximumZ = 22
        canReplaceMapContent = false
        isGeometryFlipped = false
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let host = self?.host else { result(nil, nil); return }
            host.request(path, result: result)
        }
    }
}

@MainActor
private final class Preview: NSObject, NSApplicationDelegate, NSWindowDelegate, MKMapViewDelegate {
    private let root: URL
    private let port: UInt16
    private let map = MKMapView()
    private var art: ArtHost?
    private let background: Bool
    private let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 740),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
    private let artStatus = NSTextField(labelWithString: "正在準備本機插畫…")
    private let poiStatus = NSTextField(labelWithString: "正在查找附近地點…")
    private let retryArt = NSButton()
    private let retryPlaces = NSButton()
    private let placeQuery = NSSearchField()
    private var query = ""
    private var search: MKLocalSearch?
    private var debounce: Timer?
    private var pins = [MKMapItemAnnotation]()
    private var lastSearchedRegion: MKCoordinateRegion?
    private var overlay: ArtworkOverlay?
    private var shuttingDown = false

    init(root: URL, port: UInt16, background: Bool) {
        self.root = root
        self.port = port
        self.background = background
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let quit = NSMenuItem(title: "結束 Savvy Pocket City", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenu = NSMenu()
        appMenu.addItem(quit)
        let item = NSMenuItem()
        item.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(item)
        NSApp.mainMenu = menu

        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
        config.pointOfInterestFilter = .includingAll
        map.preferredConfiguration = config
        map.showsUserLocation = false
        map.showsZoomControls = true
        map.showsCompass = true
        map.showsScale = true
        map.setAccessibilityLabel("臺北 Apple 地圖")
        map.delegate = self

        placeQuery.placeholderString = "搜尋附近的 Apple 地點"
        placeQuery.setAccessibilityLabel("搜尋附近的 Apple 地點")
        placeQuery.sendsSearchStringImmediately = false
        placeQuery.sendsWholeSearchString = true
        placeQuery.target = self
        placeQuery.action = #selector(submitPlaceQuery)
        placeQuery.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        retryPlaces.title = "重新查找地點"
        retryPlaces.bezelStyle = .inline
        retryPlaces.target = self
        retryPlaces.action = #selector(retryPlaceSearch)
        retryPlaces.isHidden = true
        let searchBar = NSStackView(views: [placeQuery, poiStatus, retryPlaces])
        searchBar.spacing = 14
        let osmCredit = NSButton(title: "© OpenStreetMap contributors", target: self,
                                 action: #selector(showOSMLicense))
        osmCredit.bezelStyle = .inline
        osmCredit.contentTintColor = .linkColor
        retryArt.title = "重新載入插畫"
        retryArt.bezelStyle = .inline
        retryArt.target = self
        retryArt.action = #selector(loadArtwork)
        retryArt.isHidden = true
        let taipeiCredit = NSTextField(labelWithString: "臺北市開放資料")
        let credits = NSStackView(views: [artStatus, retryArt, taipeiCredit, osmCredit])
        credits.spacing = 8
        let header = NSStackView(views: [searchBar, credits])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 5
        header.edgeInsets = NSEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)
        header.setHuggingPriority(.required, for: .vertical)
        let content = NSStackView(views: [map, header])
        content.orientation = .vertical
        content.spacing = 0
        content.alignment = .width
        window.contentView = content
        window.title = "Savvy Pocket City · Apple 地圖"
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = CGSize(width: 540, height: 420)
        window.delegate = self
        window.collectionBehavior.insert(.moveToActiveSpace)
        if background {
            window.center()
            window.orderBack(nil)
        } else {
            showPreviewWindow(center: true)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.shuttingDown else { return }
            self.window.contentView?.layoutSubtreeIfNeeded()
            self.map.setRegion(MKCoordinateRegion(center: fuxing, latitudinalMeters: 440, longitudinalMeters: 650), animated: false)
            if artDiagnostics {
                let mapSize = self.map.bounds.size
                let span = self.map.region.span
                logger.notice("Artwork initial map \(Double(mapSize.width))x\(Double(mapSize.height)) span \(span.latitudeDelta),\(span.longitudeDelta)")
            }
            self.loadArtwork()
            self.schedulePlaces()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreviewWindow()
        return false
    }

    private func showPreviewWindow(center: Bool = false) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        let screens = NSScreen.screens
        let cursor = NSEvent.mouseLocation
        if let screen = screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main,
           !window.styleMask.contains(.fullScreen),
           center || window.screen?.frame != screen.frame {
            let area = screen.visibleFrame
            let size = CGSize(width: min(window.frame.width, area.width), height: min(window.frame.height, area.height))
            window.setFrame(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                   width: size.width, height: size.height), display: true)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func loadArtwork() {
        if let overlay { map.removeOverlay(overlay) }
        overlay = nil
        art?.stop()
        let host = ArtHost()
        art = host
        artStatus.stringValue = "正在準備本機插畫…"
        retryArt.isHidden = true
        host.onState = { [weak self, weak host] state in
            guard let self, let host, self.art === host else { return }
            switch state {
            case .bridge:
                let overlay = ArtworkOverlay(host: host)
                self.overlay = overlay
                // Keep Apple's labels, shields and POI icons above the artwork.
                self.map.addOverlay(overlay, level: .aboveRoads)
                self.artStatus.stringValue = "放大臺北街區以顯示插畫"
            case .painted:
                self.artStatus.stringValue = "Pocket City 插畫"
            case .degraded:
                self.artStatus.stringValue = "部分插畫暫時無法載入"
                self.retryArt.isHidden = false
            case .unavailable:
                if let overlay = self.overlay { self.map.removeOverlay(overlay) }
                self.overlay = nil
                self.artStatus.stringValue = "插畫暫時無法載入"
                self.retryArt.isHidden = false
            }
        }
        host.start(root: root, preferredPort: port)
    }

    func mapView(_ mapView: MKMapView, rendererFor mapOverlay: any MKOverlay) -> MKOverlayRenderer {
        guard let tile = mapOverlay as? ArtworkOverlay else { return MKOverlayRenderer(overlay: mapOverlay) }
        let renderer = MKTileOverlayRenderer(tileOverlay: tile)
        renderer.alpha = 0.88
        return renderer
    }

    // On macOS, nearby search supplies the real map items; built-in label
    // selection (selectableMapFeatures) is only exposed by the SDK on iOS.
    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        guard let place = annotation as? MKMapItemAnnotation else { return nil }
        let marker = mapView.dequeueReusableAnnotationView(withIdentifier: "nearby-place") as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: place, reuseIdentifier: "nearby-place")
        marker.annotation = place
        marker.markerTintColor = NSColor(calibratedRed: 0.18, green: 0.41, blue: 0.34, alpha: 1)
        marker.canShowCallout = true
        marker.setAccessibilityLabel(place.mapItem.name)
        return marker
    }

    func mapView(_ mapView: MKMapView, selectionAccessoryFor annotation: any MKAnnotation) -> MKSelectionAccessory? {
        guard annotation is MKMapItemAnnotation else { return nil }
        return .mapItemDetail(.callout(.full))
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { schedulePlaces() }

    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) { schedulePlaces() }

    @objc private func showOSMLicense() {
        NSWorkspace.shared.open(URL(string: "https://www.openstreetmap.org/copyright")!)
    }

    @objc private func submitPlaceQuery() {
        query = placeQuery.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        lastSearchedRegion = nil
        debounce?.invalidate()
        for pin in map.selectedAnnotations { map.deselectAnnotation(pin, animated: false) }
        findPlaces()
    }

    @objc private func retryPlaceSearch() {
        lastSearchedRegion = nil
        debounce?.invalidate()
        findPlaces()
    }

    private func schedulePlaces() {
        guard !shuttingDown else { return }
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.findPlaces() }
        }
    }

    private func findPlaces() {
        guard map.selectedAnnotations.isEmpty else { return }
        let region = map.region
        let center = region.center
        guard isTaipei(center), max(region.span.latitudeDelta, region.span.longitudeDelta) < 0.032 else {
            search?.cancel()
            search = nil
            lastSearchedRegion = nil
            map.removeAnnotations(pins)
            pins.removeAll()
            poiStatus.stringValue = "放大臺北街區以查看 Apple 地點"
            retryPlaces.isHidden = true
            return
        }
        if let previous = lastSearchedRegion {
            let delta = hypot(center.latitude - previous.center.latitude, center.longitude - previous.center.longitude)
            let step = max(region.span.latitudeDelta, region.span.longitudeDelta)
            if delta < step * 0.18 && abs(region.span.longitudeDelta - previous.span.longitudeDelta) < step * 0.22 {
                return
            }
        }
        search?.cancel()
        let stale = pins.filter { !contains($0.coordinate, in: region) }
        map.removeAnnotations(stale)
        pins.removeAll { !contains($0.coordinate, in: region) }
        guard query.isEmpty else {
            startTextSearch(query, in: region)
            return
        }
        let nearby = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        nearby.pointOfInterestFilter = .includingAll
        startSearch(MKLocalSearch(request: nearby), in: region, mayUseTextFallback: true)
    }

    private func contains(_ location: CLLocationCoordinate2D, in region: MKCoordinateRegion) -> Bool {
        abs(location.latitude - region.center.latitude) <= region.span.latitudeDelta / 2 &&
            abs(location.longitude - region.center.longitude) <= region.span.longitudeDelta / 2
    }

    private func startTextSearch(_ text: String, in region: MKCoordinateRegion, isRestaurantFallback: Bool = false) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = region
        request.regionPriority = .required
        request.resultTypes = .pointOfInterest
        startSearch(MKLocalSearch(request: request), in: region, mayUseTextFallback: false,
                    emptyStatus: isRestaurantFallback ? "這個範圍沒有 Apple 餐廳結果" : "這個範圍沒有 Apple 地點結果")
    }

    private func startSearch(_ next: MKLocalSearch, in region: MKCoordinateRegion, mayUseTextFallback: Bool,
                             emptyStatus: String = "這個範圍沒有 Apple 地點結果") {
        search = next
        poiStatus.stringValue = "正在查找附近地點…"
        retryPlaces.isHidden = true
        next.start { [weak self, weak next] response, error in
            DispatchQueue.main.async {
                guard let self, let next, self.search === next, !self.shuttingDown else { return }
                self.search = nil
                guard self.map.selectedAnnotations.isEmpty else { return }
                let locations = (response?.mapItems ?? []).compactMap { MKMapItemAnnotation(mapItem: $0) }
                    .filter { self.contains($0.coordinate, in: region) && self.contains($0.coordinate, in: self.map.region) }
                if let error = error as NSError? {
                    logger.error("Place search failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
                }
                let throttled = (error as? MKError)?.code == .loadingThrottled
                if mayUseTextFallback && locations.isEmpty && !throttled {
                    // Some providers do not return browse-by-region results. One bounded
                    // category search can still return native map items at this same view.
                    self.startTextSearch("餐廳", in: region, isRestaurantFallback: true)
                    return
                }
                self.map.removeAnnotations(self.pins)
                self.pins = Array(locations.prefix(70))
                self.map.addAnnotations(self.pins)
                if error != nil {
                    self.lastSearchedRegion = nil
                    self.poiStatus.stringValue = "附近地點暫時無法載入"
                    self.retryPlaces.isHidden = false
                } else {
                    self.lastSearchedRegion = region
                    self.poiStatus.stringValue = self.pins.isEmpty ? emptyStatus : "點選標記查看 Apple 地點"
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        shuttingDown = true
        debounce?.invalidate()
        search?.cancel()
        art?.stop()
    }
}

MainActor.assumeIsolated {
let arguments = CommandLine.arguments
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let bundledRoot = Bundle.main.url(forResource: "preview-root", withExtension: "txt")
    .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
let explicitRoot = arguments.dropFirst().first { $0.hasPrefix("/") }
guard let rootPath = explicitRoot ?? bundledRoot,
      FileManager.default.fileExists(atPath: rootPath + "/native/art-host.html"),
      FileManager.default.fileExists(atPath: rootPath + "/data/city170/index.json") else {
    let alert = NSAlert()
    alert.messageText = "找不到口袋城市的本機資料"
    alert.informativeText = "請在原型目錄還原地圖資料後，再執行 bash native/run.sh。"
    alert.runModal()
    exit(2)
}
let port = arguments.count >= 3 ? UInt16(arguments[2]) ?? 0 : 0
let preview = Preview(root: URL(fileURLWithPath: rootPath, isDirectory: true),
                      port: port, background: arguments.contains("--background"))
app.delegate = preview
app.run()
}
