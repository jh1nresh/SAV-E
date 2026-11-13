#if SAVVY_CITY_MVP
import SwiftUI
import MapKit

/// A separate experiment: UIKit owns this map. No normal app map, registration,
/// location service, custom geometry or snapshots participate in the result.
struct CityUIKitBuildingsProbe: View {
    @StateObject private var model = CityUIKitBuildingsProbeModel()
    @State private var counter = 0

    var body: some View {
        VStack(spacing: 8) {
            Text("UIKit buildings experiment").font(.headline)
            Text("Historical native camera fixture · not live registration")
                .font(.caption).multilineTextAlignment(.center)
            CityUIKitBuildingsMap(model: model, counter: counter)
                .accessibilityIdentifier("uikitBuildings.map")
            HStack {
                Button("Buildings on") { model.setBuildings(true) }
                    .accessibilityIdentifier("uikitBuildings.on")
                Button("Buildings off") { model.setBuildings(false) }
                    .accessibilityIdentifier("uikitBuildings.off")
            }.buttonStyle(.bordered)
            HStack {
                Button("1450 m") { model.setDistance(1450) }
                    .accessibilityIdentifier("uikitBuildings.near")
                Button("4692 m") { model.setDistance(4692) }
                    .accessibilityIdentifier("uikitBuildings.far")
                Button("Update \(counter)") { counter += 1 }
                    .accessibilityIdentifier("uikitBuildings.update")
            }.buttonStyle(.bordered)
            Text(verbatim: model.status).font(.caption2)
                .accessibilityIdentifier("uikitBuildings.metadata")
                .accessibilityValue(Text(verbatim: model.metadata))
            Text("Readback alone does not prove building visibility.")
                .font(.caption2)
        }.padding(.vertical, 4)
    }
}

private struct CityUIKitBuildingsMap: UIViewRepresentable {
    let model: CityUIKitBuildingsProbeModel
    let counter: Int
    func makeUIView(context: Context) -> MKMapView { model.makeMap() }
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Intentionally no configuration, camera or buildings assignment here.
        model.wrapperUpdated(counter: counter)
    }
}

@MainActor
private final class CityUIKitBuildingsProbeModel: NSObject, ObservableObject, MKMapViewDelegate {
    // Captured public MapKit camera, native-overlay-20261111/frames-r2/
    // BEF27B0E-CDCB-4742-A168-371FEC97F050.txt (phase ready, resolver mapkit).
    private static let landmark = CLLocationCoordinate2D(latitude: 25.030941, longitude: 121.568341)
    @Published var metadata = "{}"
    @Published var status = "Waiting for native map"
    private weak var map: MKMapView?
    private var requestedBuildings = true
    private var requestedDistance = 1450.0
    private var flagWrites = 0
    private var configurationWrites = 0
    private var mapTypeWrites = 0
    private let usesLegacyMapType = ProcessInfo.processInfo.arguments.contains("--verify-uikit-legacy-maptype")
    private var cameraWrites = 0
    private var revision = 0
    private var counter = -1
    private var initialRender = false
    private var renderCount = 0
    private var observationRenderBaseline = 0
    private var lastMapLoadFailure: [String: Any]?
    private var phase = "waiting"
    private var records: [[String: Any]] = []
    private var settle: Task<Void, Never>?
    private var deadline: Task<Void, Never>?

    func makeMap() -> MKMapView {
        precondition(map == nil, "Probe must retain one map instance")
        let view = MKMapView(frame: .zero)
        map = view
        view.delegate = self
        view.showsUserLocation = false
        if usesLegacyMapType {
            // Final discriminator: no preferredConfiguration assignment on this route.
            view.mapType = .standard
            mapTypeWrites += 1
            view.pointOfInterestFilter = .excludingAll
            view.showsTraffic = false
        } else {
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
            configuration.pointOfInterestFilter = .excludingAll
            configuration.showsTraffic = false
            view.preferredConfiguration = configuration
            configurationWrites += 1
        }
        view.showsBuildings = requestedBuildings
        flagWrites += 1
        view.setCamera(MKMapCamera(lookingAtCenter: Self.landmark,
                                  fromDistance: requestedDistance, pitch: 35, heading: 20), animated: false)
        cameraWrites += 1
        beginObservation()
        return view
    }

    func setBuildings(_ value: Bool) {
        guard let map else { return }
        requestedBuildings = value
        map.showsBuildings = value
        flagWrites += 1
        beginObservation()
    }

    func setDistance(_ value: Double) {
        guard let map else { return }
        requestedDistance = value
        initialRender = false
        map.setCamera(MKMapCamera(lookingAtCenter: Self.landmark,
                                 fromDistance: value, pitch: 35, heading: 20), animated: false)
        cameraWrites += 1
        beginObservation()
    }

    func wrapperUpdated(counter value: Int) {
        guard value != counter else { return }
        counter = value
        // Observe through another settled frame without mutating MKMapView.
        beginObservation()
        record("wrapper-update")
    }

    private func beginObservation() {
        revision += 1
        observationRenderBaseline = renderCount
        phase = "settling"
        let token = revision
        record("immediate")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.revision == token else { return }
            self.record("next-main-loop")
            self.scheduleSettle()
        }
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.revision == token, self.phase != "ready" else { return }
            self.phase = self.initialRender ? "camera-timeout" : "environment-render-timeout"
            self.record("deadline")
        }
    }

    private func cameraMatches() -> Bool {
        guard let map else { return false }
        let c = map.camera
        return abs(c.centerCoordinate.latitude - Self.landmark.latitude) < 0.00000001
            && abs(c.centerCoordinate.longitude - Self.landmark.longitude) < 0.00000001
            && abs(c.centerCoordinateDistance - requestedDistance) < 0.1
            && abs(c.pitch - 35) < 0.01 && abs(c.heading - 20) < 0.01
            && map.bounds.width > 0 && map.bounds.height > 0
    }

    private func scheduleSettle() {
        settle?.cancel()
        let token = revision
        settle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.revision == token else { return }
            if self.initialRender && self.cameraMatches() { self.phase = "ready" }
            self.record("settled")
            // Re-read the live property after the screenshot observation window,
            // even when MapKit emits no further rendering or camera callbacks.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self.revision == token else { return }
            self.record("settled-plus-two-seconds")
        }
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { scheduleSettle() }
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { scheduleSettle() }
    func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
        if fullyRendered {
            renderCount += 1
            if cameraMatches() { initialRender = true }
        }
        record(fullyRendered ? "fully-rendered" : "partial-render")
        scheduleSettle()
    }
    func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
        // No arbitrary error payloads or network URLs in the public fixture report.
        let failure = error as NSError
        lastMapLoadFailure = ["domain": failure.domain, "code": failure.code]
        phase = "environment-map-load-failed"
        record("map-load-failed")
    }

    private func record(_ event: String) {
        guard let map else { return }
        let c = map.camera
        let configuration = map.preferredConfiguration
        let p = map.convert(Self.landmark, toPointTo: map)
        let roundtrip = map.convert(p, toCoordinateFrom: map)
        let finite = p.x.isFinite && p.y.isFinite
            && roundtrip.latitude.isFinite && roundtrip.longitude.isFinite
        let projection: [String: Any] = finite ? [
            "x": Double(p.x), "y": Double(p.y),
            "roundtripLatitudeError": abs(roundtrip.latitude - Self.landmark.latitude),
            "roundtripLongitudeError": abs(roundtrip.longitude - Self.landmark.longitude)
        ] : ["unavailable": true]
        var row: [String: Any] = [
            "event": event, "revision": revision, "phase": phase,
            "fixture": "historical-native-overlay-20261111", "mapIdentity": String(describing: ObjectIdentifier(map)),
            "requestedBuildings": requestedBuildings, "actualBuildings": map.showsBuildings,
            "appWriteCount": flagWrites, "configurationWriteCount": configurationWrites,
            "mapTypeWriteCount": mapTypeWrites, "mapType": map.mapType.rawValue,
            "initializationRoute": usesLegacyMapType ? "legacy-maptype" : "preferred-configuration",
            "cameraWriteCount": cameraWrites, "wrapperCounter": counter,
            "initialFullyRendered": initialRender, "fullyRenderedCount": renderCount,
            "observationRenderBaseline": observationRenderBaseline,
            "fullyRenderedSinceObservation": renderCount > observationRenderBaseline,
            "cameraMatches": cameraMatches(), "requestedDistance": requestedDistance,
            "camera": ["latitude": c.centerCoordinate.latitude, "longitude": c.centerCoordinate.longitude,
                       "distance": c.centerCoordinateDistance, "heading": c.heading, "pitch": Double(c.pitch)],
            "configuration": String(describing: type(of: configuration)),
            "elevation": configuration.elevationStyle == .flat ? "flat" : "realistic",
            "projection": projection
        ]
        if let lastMapLoadFailure { row["lastMapLoadFailure"] = lastMapLoadFailure }
        if let standard = configuration as? MKStandardMapConfiguration {
            row["emphasis"] = standard.emphasisStyle == .default ? "default" : "muted"
        }
        records.append(row)
        if records.count > 32 { records.removeFirst(records.count - 32) }
        row["events"] = records
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        let summary = "\(phase) · requested \(requestedBuildings) / actual \(map.showsBuildings) · writes \(flagWrites)"
        // makeUIView/updateUIView/delegate callbacks may occur in a SwiftUI update.
        DispatchQueue.main.async { [weak self] in
            self?.metadata = json
            self?.status = summary
        }
    }
}
#endif
