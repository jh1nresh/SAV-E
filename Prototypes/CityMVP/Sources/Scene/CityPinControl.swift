#if SAVVY_CITY_MVP
import SwiftUI
import UIKit
import MapKit

/// Bounded opt-in inspection; identifiers only, never place/source text.
@MainActor
enum CityPinSelectionObservation {
    private(set) static var events: [[String: String]] = []
    static func record(_ source: String, id: String) {
        guard CityMVPPreviewConfiguration.inspectsPreview else { return }
        events.append(["source": source, "id": id])
        if events.count > 8 { events.removeFirst(events.count - 8) }
    }
}

/// Native annotation geography and artwork, with all physical touches on MapKit.
/// A SwiftUI Button here can treat one finger of a pinch as its own activation.
struct CityNativeSavedPin: View {
    let place: Place
    let onTap: () -> Void
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        CityPinArtwork(id: CityMVPPlaceBridge.contextID(for: place), title: place.name,
                       symbol: place.category.mapMarkerSymbol, saved: true, selected: false,
                       visited: place.status == .visited)
            .accessibilityHidden(true)
            .overlay(alignment: .bottom) {
                CityPinControl(title: language.localized(english: "\(place.name) Map Stamp", traditionalChinese: "\(place.name) 地圖章"),
                    value: place.status == .visited ? "Saved · visited" : "Saved · want to go",
                    identifier: "map.pin.saved.\(place.id.uuidString)", selected: false, enabled: true) {
                        SaveHaptics.select()
                        onTap()
                    }
                    .frame(width: 44, height: 44)
                    .offset(y: -3)
                    .allowsHitTesting(false)
            }
            .allowsHitTesting(false)
    }
}

/// A semantic target at the same projected point as the SceneKit photo.
/// Physical touches stay on the native map rather than a sibling control.
struct CityPinControl: UIViewRepresentable {
    let title: String
    let value: String
    let identifier: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    func makeUIView(context: Context) -> CityPinControlHost {
        CityPinControlHost(frame: .zero)
    }
    func updateUIView(_ host: CityPinControlHost, context: Context) {
        host.action = action
        host.accessibilityLabel = title
        host.accessibilityValue = value
        host.accessibilityIdentifier = identifier
        host.accessibilityTraits = selected ? [.button, .selected] : .button
        host.selected = selected
        host.available = enabled
        host.setNeedsLayout()
    }
    static func dismantleUIView(_ host: CityPinControlHost, coordinator: ()) {
        host.detachInput()
    }
}

/// Noninteractive host: it must never steal either finger from MapKit's canvas.
final class CityPinControlHost: UIView {
    var action: () -> Void = {}
    var selected = false
    private var router: CityMapPinTapRouter?
    var available = true {
        didSet { isAccessibilityElement = available }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = true
    }
    override func accessibilityActivate() -> Bool {
        guard available else { return false }
        action()
        return true
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { detachInput() }
        else { synchronizeInput() }
        traceLifecycle("window")
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        synchronizeInput()
        traceLifecycle("layout")
    }
    func detachInput() {
        traceLifecycle("detach")
        router?.remove(self)
        router = nil
    }
    private func synchronizeInput() {
        guard window != nil else { return }
        if router?.map?.window !== window || router?.map == nil {
            var ancestor = superview
            var found: MKMapView?
            while let view = ancestor, found == nil {
                found = Self.findMap(in: view)
                ancestor = view.superview
            }
            guard let found else { return }
            detachInput()
            router = CityMapPinTapRouter.router(for: found)
            router?.add(self)
            traceLifecycle("bound")
        }
    }
    private func traceLifecycle(_ event: String) {
        guard CityPinInputDiagnostics.acceptsLifecycle,
              selected || accessibilityIdentifier == "cityMVP.groundPin.landmark-101" else { return }
        var ancestor = superview
        var fresh: MKMapView?
        while let view = ancestor, fresh == nil {
            fresh = Self.findMap(in: view)
            ancestor = view.superview
        }
        let cached = router?.map
        let rect = cached.map { convert(bounds, to: $0) }
        let hit = window.flatMap { window in
            window.hitTest(convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window), with: nil)
        }
        var hitAncestor = hit
        var hitMap: MKMapView?
        var hitHasControl = false
        while let view = hitAncestor {
            if let map = view as? MKMapView { hitMap = map; break }
            if view is UIControl { hitHasControl = true }
            hitAncestor = view.superview
        }
        let hitInsideCached = cached.map { map in hit?.isDescendant(of: map) == true } ?? false
        let fields = "event=\(event) host=\(CityPinInputDiagnostics.identity(self)) kind=\(selected ? "selected" : "ordinary101") "
            + "freshMap=\(CityPinInputDiagnostics.identity(fresh)) hostWindow=\(window != nil) mapWindow=\(cached?.window != nil) "
            + "windowMatch=\(cached?.window === window) available=\(available) selected=\(selected) "
            + "bounds=\(rect.map(CityPinInputDiagnostics.rect) ?? "nil") \(router?.diagnosticState ?? "router=nil map=nil") "
            + "hitObservation=\(event == "layout" ? "last-layout-not-tap-time" : "lifecycle-not-tap-time") hitMap=\(CityPinInputDiagnostics.identity(hitMap)) "
            + "hitCacheMatch=\(hitMap != nil && hitMap === cached) hasControl=\(hitHasControl) hitInsideCachedMap=\(hitInsideCached)"
        CityPinInputDiagnostics.lifecycle(host: self, fields: fields)
    }
    private static func findMap(in view: UIView) -> MKMapView? {
        if let map = view as? MKMapView { return map }
        for child in view.subviews {
            if let map = findMap(in: child) { return map }
        }
        return nil
    }
}

/// One observer per public map. Native gestures receive their original touches;
/// the one-finger tap observer fails on movement or a second finger. It does not
/// cancel touches or prevent MapKit recognizers from running simultaneously.
final class CityMapPinTapRouter: NSObject, UIGestureRecognizerDelegate {
    private struct Entry {
        weak var host: CityPinControlHost?
        let order: Int
    }
    private static let routers = NSMapTable<MKMapView, CityMapPinTapRouter>.weakToWeakObjects()
    private(set) weak var map: MKMapView?
    private var entries: [Entry] = []
    private var nextOrder = 0
    private let target: CityMapPinTapTarget
    private let tap: UITapGestureRecognizer

    static func router(for map: MKMapView) -> CityMapPinTapRouter {
        if let existing = routers.object(forKey: map) { return existing }
        let router = CityMapPinTapRouter(map: map)
        routers.setObject(router, forKey: map)
        return router
    }
    private init(map: MKMapView) {
        let target = CityMapPinTapTarget()
        self.target = target
        tap = UITapGestureRecognizer(target: target, action: #selector(CityMapPinTapTarget.recognized(_:)))
        self.map = map
        super.init()
        target.router = self
        tap.numberOfTouchesRequired = 1
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        for recognizer in Self.recognizers(in: map) {
            if let multipleTap = recognizer as? UITapGestureRecognizer, multipleTap.numberOfTapsRequired > 1 {
                tap.require(toFail: multipleTap)
            }
        }
        map.addGestureRecognizer(tap)
        CityDistrictTrace.write("pin-input\ttap-observer-installed")
    }
    func add(_ host: CityPinControlHost) {
        guard !entries.contains(where: { $0.host === host }) else { return }
        entries.append(Entry(host: host, order: nextOrder))
        nextOrder += 1
    }
    func remove(_ host: CityPinControlHost) {
        entries.removeAll { $0.host == nil || $0.host === host }
        if entries.isEmpty, let map {
            map.removeGestureRecognizer(tap)
            Self.routers.removeObject(forKey: map)
        }
    }
    fileprivate var diagnosticState: String {
        "router=\(CityPinInputDiagnostics.identity(self)) map=\(CityPinInputDiagnostics.identity(map)) "
            + "attached=\(map?.gestureRecognizers?.contains(where: { $0 === tap }) == true) "
            + "tapViewMatch=\(tap.view === map) enabled=\(tap.isEnabled) state=\(tap.state.rawValue)"
    }
    func recognized(_ tap: UITapGestureRecognizer) {
        CityPinInputDiagnostics.event("recognized-entry state=\(tap.state.rawValue) point=\(CityPinInputDiagnostics.point(tap.location(in: map))) \(diagnosticState)")
        guard tap.state == .ended else {
            CityPinInputDiagnostics.event("recognized-return reason=noended state=\(tap.state.rawValue)")
            return
        }
        guard let map else {
            CityPinInputDiagnostics.event("recognized-return reason=missingmap")
            return
        }
        let point = tap.location(in: map)
        let usableMap = map.bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 32, right: 0))
        guard usableMap.contains(point) else {
            CityPinInputDiagnostics.event("recognized-return reason=\(map.bounds.contains(point) ? "footer" : "outside-map") point=\(CityPinInputDiagnostics.point(point)) usable=\(CityPinInputDiagnostics.rect(usableMap))")
            return
        }
        let hits = entries.compactMap { entry -> (host: CityPinControlHost, order: Int)? in
            guard let host = entry.host, host.available, host.window === map.window,
                  host.convert(host.bounds, to: map).contains(point) else { return nil }
            return (host, entry.order)
        }
        let topmost = hits.max {
            $0.host.selected == $1.host.selected ? $0.order < $1.order : !$0.host.selected
        }
        if CityPinInputDiagnostics.acceptsEvents {
            let live = entries.compactMap(\.host)
            let eligible = live.filter { $0.available && $0.window === map.window }
            let ordinary = live.first { $0.accessibilityIdentifier == "cityMVP.groundPin.landmark-101" }
            let ordinaryRect = ordinary.map { $0.convert($0.bounds, to: map) }
            CityPinInputDiagnostics.event("recognized-hit live=\(live.count) eligible=\(eligible.count) hits=\(hits.count) matched=\(topmost != nil) "
                + "ordinary101=\(ordinaryRect.map(CityPinInputDiagnostics.rect) ?? "nil") ordinaryAvailable=\(ordinary?.available == true) "
                + "ordinaryWindowMatch=\(ordinary?.window === map.window)")
        }
        guard let host = topmost?.host else {
            CityPinInputDiagnostics.event("recognized-return reason=miss")
            return
        }
        CityPinInputDiagnostics.event("recognized-dispatch selected=\(host.selected) available=\(host.available)")
        CityDistrictTrace.write("pin-input\tmap-tap")
        CityPinSelectionObservation.record("projected-map-tap", id: host.accessibilityIdentifier ?? "")
        host.action()
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let map else {
            CityPinInputDiagnostics.event("receive reason=missingmap point=\(CityPinInputDiagnostics.point(touch.location(in: nil))) touchControl=\(touch.view is UIControl) \(diagnosticState)")
            return false
        }
        // Receive both fingers, even when only the first is over a pin. Filtering
        // the second out would misread a rotation as a one-finger tap.
        var view = touch.view
        while let current = view, current !== map {
            if current is UIControl {
                CityPinInputDiagnostics.event("receive reason=controlancestor point=\(CityPinInputDiagnostics.point(touch.location(in: map))) "
                    + "touchControl=\(touch.view is UIControl) touchInMap=\(touch.view?.isDescendant(of: map) == true) \(diagnosticState)")
                return false
            }
            view = current.superview
        }
        let allowed = view === map
        CityPinInputDiagnostics.event("receive reason=\(allowed ? "allowed" : "outsideancestry") point=\(CityPinInputDiagnostics.point(touch.location(in: map))) "
            + "touchControl=\(touch.view is UIControl) touchInMap=\(touch.view?.isDescendant(of: map) == true) \(diagnosticState)")
        return allowed
    }
    private static func recognizers(in view: UIView) -> [UIGestureRecognizer] {
        (view.gestureRecognizers ?? []) + view.subviews.flatMap { recognizers(in: $0) }
    }
}

final class CityMapPinTapTarget: NSObject {
    weak var router: CityMapPinTapRouter?
    @objc func recognized(_ gesture: UITapGestureRecognizer) { router?.recognized(gesture) }
}

struct CityPinCaptionAccessibility: UIViewRepresentable {
    let title: String
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityTraits = .staticText
        view.accessibilityIdentifier = "cityMVP.selectedGroundPinTitle"
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { view.accessibilityLabel = title }
}
/// Opt-in diagnostics only. Layout chatter cannot consume the event budget.
@MainActor
private enum CityPinInputDiagnostics {
    static let enabled = CityDistrictTrace.enabled && ProcessInfo.processInfo.arguments.contains("--verify-pin-input")
    private static var lifecycleCount = 0
    private static var eventCount = 0
    private static var lastLifecycle: [ObjectIdentifier: String] = [:]
    static var acceptsLifecycle: Bool { enabled && lifecycleCount < 32 }
    static var acceptsEvents: Bool { enabled && eventCount < 96 }

    static func lifecycle(host: CityPinControlHost, fields: String) {
        guard enabled, lifecycleCount < 32 else { return }
        let id = ObjectIdentifier(host)
        guard lastLifecycle[id] != fields else { return }
        lastLifecycle[id] = fields
        lifecycleCount += 1
        CityDistrictTrace.write("pin-input-diag\t\(ProcessInfo.processInfo.systemUptime)\tlifecycle=\(lifecycleCount)/32\t\(fields)")
    }
    static func event(_ fields: @autoclosure () -> String) {
        guard enabled, eventCount < 96 else { return }
        eventCount += 1
        CityDistrictTrace.write("pin-input-diag\t\(ProcessInfo.processInfo.systemUptime)\tevent=\(eventCount)/96\t\(fields())")
    }
    nonisolated static func identity(_ object: AnyObject?) -> String {
        object.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
    }
    nonisolated static func point(_ value: CGPoint) -> String { String(format: "%.2f,%.2f", Double(value.x), Double(value.y)) }
    nonisolated static func rect(_ value: CGRect) -> String {
        String(format: "%.2f,%.2f,%.2f,%.2f", Double(value.minX), Double(value.minY), Double(value.width), Double(value.height))
    }
}
#endif
