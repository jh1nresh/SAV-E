#if SAVVY_CITY_MVP
import SwiftUI
import MapKit

/// Explicit native-only experiment. It does not instantiate the normal map,
/// SceneKit, snapshot backing, clouds or custom annotations. Native building
/// defaults stay untouched in polygon modes. The explicit buildings-off mode
/// alone tests the live public showsBuildings flag, with original-value restore.
struct CityNativeOverlayProbe: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case none, roadsAlpha001 = "roads-alpha001", roadsOpaque = "roads-opaque", labelsOpaque = "labels-opaque"
        case buildingsOff = "buildings-off"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: "None"
            case .roadsAlpha001: "Roads .01"
            case .roadsOpaque: "Roads 1"
            case .labelsOpaque: "Labels 1"
            case .buildingsOff: "Buildings off"
            }
        }
    }
    private enum Phase: String {
        case resolving, registrationFailed = "registration-failed", waiting = "camera-wait"
        case settling, ready, cameraFailed = "camera-failed"
    }
    private struct Observation {
        let latitude: Double
        let longitude: Double
        let distance: Double
        let heading: Double
        let pitch: Double
        init(_ camera: MapCamera) {
            latitude = camera.centerCoordinate.latitude
            longitude = camera.centerCoordinate.longitude
            distance = camera.distance
            heading = camera.heading
            pitch = camera.pitch
        }
        var fields: [String: Double] {
            ["latitude": latitude, "longitude": longitude, "distance": distance, "heading": heading, "pitch": pitch]
        }
        func same(as other: Self) -> Bool {
            abs(latitude - other.latitude) < 0.00000001 && abs(longitude - other.longitude) < 0.00000001
                && abs(distance - other.distance) < 0.01 && abs(pitch - other.pitch) < 0.001
                && Self.angle(heading, other.heading) < 0.001
        }
        static func angle(_ a: Double, _ b: Double) -> Double {
            let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
            return min(difference, 360 - difference)
        }
    }

    @State private var registration: CityDistrictRegistration?
    @State private var attempt = 0
    @State private var attemptsMade = 0
    @State private var resolver = "not-started"
    @State private var mode = Mode.none
    @State private var distance = 1450.0
    @State private var position = MapCameraPosition.automatic
    @State private var phase = Phase.resolving
    @State private var observed: Observation?
    @State private var ended: Observation?
    @State private var revision = 0
    @State private var settle: Task<Void, Never>?
    @State private var deadline: Task<Void, Never>?
    @State private var buildingRecord: CityNativeBuildingSettingRecord?
    @State private var bindingGeneration: Int?
    @State private var activeHostGeneration: Int?
    @State private var acceptedBindingGeneration: Int?
    @State private var completedRevision: Int?
    @State private var buildingFailure = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            if let registration {
                Map(position: $position, interactionModes: []) {
                    if mode == .roadsAlpha001 || mode == .roadsOpaque {
                        MapPolygon(coordinates: podium(registration))
                            .foregroundStyle(Color.gray.opacity(mode == .roadsAlpha001 ? 0.01 : 1))
                            .mapOverlayLevel(level: .aboveRoads)
                    } else if mode == .labelsOpaque {
                        MapPolygon(coordinates: podium(registration))
                            .foregroundStyle(Color.gray)
                            .mapOverlayLevel(level: .aboveLabels)
                    }
                }
                // SwiftUI calls its ordinary/non-muted emphasis .automatic;
                // UIKit's MKStandardMapEmphasisStyle uses the name .default.
                .mapStyle(.standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .excludingAll))
                .mapControls {}
                .background {
                    CityNativeBuildingSettingProbe(off: mode == .buildingsOff, cameraReady: phase == .ready,
                                                   revision: revision, onRecord: acceptBuildingRecord)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .ignoresSafeArea()
                .onMapCameraChange(frequency: .continuous) { context in
                    let sample = Observation(context.camera)
                    observed = sample
                    if let ended, !sample.same(as: ended), phase == .ready || phase == .settling {
                        let wasReady = capturePhase == "ready"
                        invalidate()
                        phase = .waiting
                        if wasReady { armDeadline() }
                    }
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    let sample = Observation(context.camera)
                    observed = sample
                    ended = sample
                    guard phase != .cameraFailed else { return }
                    if matches(sample) { beginSettle() }
                    else { invalidate(); phase = .waiting }
                }
                .accessibilityIdentifier("nativeOverlayProbe.map")
            } else {
                Color(uiColor: .systemBackground).ignoresSafeArea()
            }
            controls.padding(.horizontal, 12).padding(.bottom, 44)
        }
        .task(id: attempt) {
            let requestedAttempt = attempt
            attemptsMade += 1
            phase = .resolving
            let result: CityDistrictRegistration?
            if requestedAttempt == 0 && ProcessInfo.processInfo.arguments.contains("--probe-registration-fails-once") {
                resolver = "fixture-failure"
                result = nil // Explicit fixture: no lookup or guessed offset.
            } else {
                resolver = "mapkit"
                result = await CityDistrictRegistration.resolve()
            }
            guard !Task.isCancelled, requestedAttempt == attempt else { return }
            guard let result else { phase = .registrationFailed; return }
            registration = result
            requestCamera()
        }
        .onDisappear { invalidate(); deadline?.cancel() }
    }

    private var controls: some View {
        VStack(spacing: 7) {
            Text(statusLabel).font(.caption.weight(.semibold))
                .accessibilityIdentifier("nativeOverlayProbe.status")
                .accessibilityValue(Text(verbatim: "\(capturePhase)|mode=\(mode.rawValue)|distance=\(Int(distance))|revision=\(revision)"))
            Text(cameraLabel).font(.system(size: 10, design: .monospaced))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("nativeOverlayProbe.camera")
                .accessibilityValue(cameraJSON)
            HStack(spacing: 4) {
                ForEach([Mode.none, .roadsAlpha001, .roadsOpaque, .labelsOpaque]) { choice in
                    Button { chooseMode(choice) } label: {
                        Text(choice.title).font(.caption2)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("nativeOverlayProbe.mode.\(choice.rawValue)")
                    .accessibilityAddTraits(mode == choice ? .isSelected : [])
                }
            }.disabled(registration == nil)
            HStack(spacing: 12) {
                ForEach([1450, 4692], id: \.self) { meters in
                    Button {
                        let sameDistance = distance == Double(meters)
                        distance = Double(meters)
                        if sameDistance, let ended, let observed, ended.same(as: observed), matches(ended) {
                            armDeadline()
                            beginSettle()
                        }
                        else { requestCamera() }
                    } label: {
                        Text("\(meters) m").frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("nativeOverlayProbe.distance.\(meters)")
                    .disabled(registration == nil)
                }
                Button { chooseMode(.buildingsOff) } label: {
                    Text("Buildings off").font(.caption).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("nativeOverlayProbe.mode.buildings-off")
                .accessibilityAddTraits(mode == .buildingsOff ? .isSelected : [])
                .disabled(registration == nil)
            }
            if phase == .registrationFailed || phase == .cameraFailed {
                    Button {
                        if registration == nil { attempt += 1 }
                        else { requestCamera() }
                    } label: {
                        Text("Retry").frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("nativeOverlayProbe.retry")
            }
            Text("Native-only overlay experiment · silhouettes require visual assessment")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var capturePhase: String {
        guard phase == .ready else { return phase.rawValue }
        guard let buildingRecord, buildingRecord.hostGeneration == activeHostGeneration, buildingRecord.bindingGeneration == bindingGeneration, buildingRecord.revision == revision,
              buildingRecord.requestOff == (mode == .buildingsOff) else { return "building-readback" }
        return buildingMatches(buildingRecord) ? "ready" : "building-mismatch"
    }
    private func buildingMatches(_ record: CityNativeBuildingSettingRecord) -> Bool {
        guard record.bound, !record.invalidated, record.hostGeneration == activeHostGeneration, record.bindingGeneration == bindingGeneration, record.revision == revision, record.requestOff == (mode == .buildingsOff),
              let original = record.original, let actual = record.actual else { return false }
        let expected = mode == .buildingsOff ? false : original
        return record.requested == expected && actual == expected && record.configuration == "standard"
            && record.elevation == "flat" && record.emphasis == "default"
    }
    private func acceptBuildingRecord(_ record: CityNativeBuildingSettingRecord) {
        if let activeHostGeneration, record.hostGeneration < activeHostGeneration { return }
        let changedHost = activeHostGeneration.map { $0 != record.hostGeneration } ?? false
        if !changedHost, let bindingGeneration, record.bindingGeneration < bindingGeneration { return }
        let changed = changedHost || (bindingGeneration.map { $0 != record.bindingGeneration } ?? false)
        activeHostGeneration = record.hostGeneration
        bindingGeneration = record.bindingGeneration
        // Binding invalidations are relevant even when captured before the
        // latest camera revision. Old-generation reads have already been rejected.
        if changed {
            let hadCompletedReady = completedRevision == revision
            buildingRecord = record
            ended = nil
            invalidate()
            if phase == .cameraFailed { return }
            if hadCompletedReady {
                buildingFailure = "binding-changed-after-ready"
                phase = .cameraFailed
                deadline?.cancel()
            } else {
                // Preserve the active initial deadline. A new onEnd or explicit
                // Retry is required; an old map's ended camera is never reused.
                phase = .waiting
            }
            return
        }
        guard phase != .cameraFailed else { return }
        if record.invalidated {
            buildingRecord = record
            if completedRevision == revision {
                buildingFailure = "binding-invalidated-after-ready"
                ended = nil
                invalidate()
                phase = .cameraFailed
                deadline?.cancel()
            }
            return // Initial binding may keep its already observed matching end.
        }
        guard record.revision == revision, record.requestOff == (mode == .buildingsOff) else { return }
        buildingRecord = record
        if phase == .ready, buildingMatches(record) {
            acceptedBindingGeneration = record.bindingGeneration
            completedRevision = revision
            deadline?.cancel()
        } else if completedRevision == revision {
            buildingFailure = "live-readback-invalid-after-ready"
            ended = nil
            invalidate()
            phase = .cameraFailed
            deadline?.cancel()
        }
    }
    private func chooseMode(_ choice: Mode) {
        buildingFailure = ""
        mode = choice
        armDeadline()
        // Content/settings-only changes need not emit a new camera end.
        if let ended, let observed, ended.same(as: observed), matches(ended) { beginSettle() }
        else { requestCamera() }
    }

    private var requested: MapCamera? {
        guard let registration else { return nil }
        return MapCamera(centerCoordinate: registration.mapCoordinate(CityDistrictCamera.coordinate(x: 0, z: 0)),
                         distance: distance, heading: 20, pitch: 35)
    }
    private func podium(_ registration: CityDistrictRegistration) -> [CLLocationCoordinate2D] {
        CityLandmark101.podiumFootprint.map {
            registration.mapCoordinate(CityDistrictCamera.coordinate(x: $0.x, z: -$0.y))
        }
    }
    private func matches(_ sample: Observation) -> Bool {
        guard let requested else { return false }
        let center = CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
        return abs(sample.distance - distance) <= distance * 0.02
            && Observation.angle(sample.heading, 20) <= 1 && abs(sample.pitch - 35) <= 1
            && MKMapPoint(center).distance(to: MKMapPoint(requested.centerCoordinate)) <= 5
    }
    private func invalidate() {
        revision += 1
        settle?.cancel()
        settle = nil
    }
    private func requestCamera() {
        guard let requested else { return }
        buildingFailure = ""
        invalidate()
        ended = nil
        phase = .waiting
        position = .camera(requested)
        armDeadline()
    }
    private func beginSettle() {
        invalidate()
        let expectedRevision = revision
        phase = .settling
        settle = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled, revision == expectedRevision,
                  let ended, let observed, ended.same(as: observed), matches(ended) else { return }
            phase = .ready
            // Readback is scheduled by the adapter AFTER this ready layout.
            // Capture stays blocked until that revision's actual getter matches.
        }
    }
    private func armDeadline() {
        deadline?.cancel()
        deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(28)) } catch { return }
            guard !Task.isCancelled, capturePhase != "ready" else { return }
            buildingFailure = "initial-camera-or-readback-deadline"
            invalidate()
            phase = .cameraFailed
        }
    }
    private var statusLabel: String {
        switch phase {
        case .resolving: "Resolving native 101 alignment"
        case .registrationFailed: "Alignment unavailable · Retry required"
        case .waiting: "Waiting for matching camera end"
        case .settling: "Matching camera · settling for 2 seconds"
        case .ready: capturePhase == "ready" ? "Ready · \(mode.title) · \(Int(distance)) m" : "Camera settled · \(capturePhase)"
        case .cameraFailed: "Camera or live setting did not meet fixture · inspect record, then Retry"
        }
    }
    private var cameraLabel: String {
        let actual = observed.map { String(format: "observed %.2fm / h%.3f / p%.3f", $0.distance, $0.heading, $0.pitch) } ?? "observed unavailable"
        return "requested \(Int(distance))m / h20 / p35\n\(actual)"
    }
    private var cameraJSON: String {
        var record: [String: Any] = ["mode": mode.rawValue, "phase": capturePhase,
                                     "resolutionAttempts": attemptsMade, "resolver": resolver, "revision": revision,
                                     "buildingFailure": buildingFailure]
        if let bindingGeneration { record["bindingGeneration"] = bindingGeneration }
        if let activeHostGeneration { record["activeHostGeneration"] = activeHostGeneration }
        if let acceptedBindingGeneration { record["acceptedBindingGeneration"] = acceptedBindingGeneration }
        if let buildingRecord { record["buildingSetting"] = buildingRecord.fields }
        if let requested { record["requested"] = Observation(requested).fields }
        if let observed { record["observed"] = observed.fields }
        if let ended { record["ended"] = ended.fields }
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "camera record unavailable" }
        return text
    }
}
#endif
