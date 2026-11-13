#if SAVVY_CITY_MVP
import MapKit
import SwiftUI
import simd

enum CityDistrictMapStyle: String {
    case globe, city

    static let quietNativeLabels = CityContextPlace.enabled
        || (CityDistrictTrace.enabled && ProcessInfo.processInfo.arguments.contains("--verify-quiet-native-labels"))

    func updated(for distance: Double) -> Self {
        guard distance.isFinite, distance > 0 else { return self }
        switch self {
        case .globe: return distance <= 2_500_000 ? .city : self
        case .city: return distance >= 3_500_000 ? .globe : self
        }
    }

    func observing(distance: Double, settled: Bool, hasDestination: Bool) -> Self {
        guard settled, !hasDestination else { return self }
        return updated(for: distance)
    }
}

struct CityDistrictCamera: Equatable {
    static let cloudHandoffEnabled = CityMVPPreviewConfiguration.enabled || ["--verify-xinyi", "--verify-opaque-reveal", "--verify-material-tone", "--verify-cloud-handoff"]
        .allSatisfy { ProcessInfo.processInfo.arguments.contains($0) }
    static let space = "cityMVP.viewport"
    static let overviewDistance = 2_900.0
    static let contextPinDistance = 3_800.0
    nonisolated static let groundHalfExtent = 700.0
    nonisolated static let groundFeather = 150.0
    // The bundled extract stops at the north side of City Hall, inside
    // the wider scene texture. At Songgao, Apple Maps owns the junction.
    nonisolated static let northernGroundLimit = -568.0
    nonisolated static let northernOpaqueLimit = -518.0
    private static let streetDistance = 2_150.0
    private static let fadeOutDistance = 4_150.0
    private static let prewarmDistance = 5_200.0
    private static let cloudPeakDistance = 3_900.0
    private static let cloudClearDistance = 1_650.0
    private static let maximumFitError = 8.0

    static func cloudHandoffTone(distance: Double) -> Double {
        guard distance.isFinite, distance > 0 else { return 0 }
        return fade((9_000 - distance) / 4_500)
    }

    struct CloudPatch: Equatable {
        let center: CGPoint
        let east: CGVector
        let south: CGVector
        let mirrorsContour: Bool

        var radius: CGFloat { hypot(east.dx, east.dy) }
    }

    struct SceneBlend {
        let center: CGPoint
        let innerRadius: CGFloat
        let outerRadius: CGFloat
        let layerOpacity: Double
        let outerStrength: Double

        func opacity(at point: CGPoint) -> Double {
            let radius = hypot(point.x - center.x, point.y - center.y)
            let fraction = min(1, max(0, (radius - innerRadius) / (outerRadius - innerRadius)))
            return layerOpacity * (1 + (outerStrength - 1) * fraction)
        }
    }

    struct Projection: Equatable {
        let eye: SIMD3<Double>
        let target: SIMD3<Double>
        let up: SIMD3<Double>
        let focalLength: Double
        let principalPoint: CGPoint
        let error: Double

        func visibleGroundFraction(in viewport: CGSize) -> Double {
            let width = Double(viewport.width), height = Double(viewport.height)
            guard width.isFinite, height.isFinite, width > 0, height > 0 else { return 0 }
            let forward = simd_normalize(target - eye)
            let right = simd_cross(forward, up)
            let edge = CityDistrictCamera.groundHalfExtent - CityDistrictCamera.groundFeather
            let north = CityDistrictCamera.northernOpaqueLimit
            var polygon = [SIMD3(-edge, 0, north), SIMD3(edge, 0, north),
                           SIMD3(edge, 0, edge), SIMD3(-edge, 0, edge)].map { world in
                let delta = world - eye
                let depth = simd_dot(forward, delta)
                return SIMD3(principalPoint.x * depth + focalLength * simd_dot(right, delta),
                             principalPoint.y * depth - focalLength * simd_dot(up, delta), depth)
            }

            // Clip the ground in homogeneous screen space before dividing by
            // depth. Corners behind the camera can still enclose visible ground.
            let planes: [SIMD4<Double>] = [
                .init(0, 0, 1, -2), .init(1, 0, 0, 0), .init(-1, 0, width, 0),
                .init(0, 1, 0, 0), .init(0, -1, height, 0),
            ]
            for plane in planes {
                guard var previous = polygon.last else { return 0 }
                var previousDistance = simd_dot(plane, SIMD4(previous, 1))
                var clipped: [SIMD3<Double>] = []
                for current in polygon {
                    let distance = simd_dot(plane, SIMD4(current, 1))
                    if (distance >= 0) != (previousDistance >= 0) {
                        clipped.append(previous + (current - previous) * (previousDistance / (previousDistance - distance)))
                    }
                    if distance >= 0 { clipped.append(current) }
                    previous = current
                    previousDistance = distance
                }
                polygon = clipped
            }

            let points = polygon.map { SIMD2($0.x / $0.z, $0.y / $0.z) }
            guard points.count >= 3, var previous = points.last else { return 0 }
            var twiceArea = 0.0
            for current in points {
                twiceArea += previous.x * current.y - previous.y * current.x
                previous = current
            }
            return min(1, abs(twiceArea) / (2 * width * height))
        }

        func point(at world: SIMD3<Double>) -> CGPoint? {
            let forward = simd_normalize(target - eye)
            let right = simd_cross(forward, up)
            let delta = world - eye
            let depth = simd_dot(forward, delta)
            guard depth > 2 else { return nil }
            return CityDistrictCamera.finitePoint(.init(
                x: principalPoint.x + focalLength * simd_dot(right, delta) / depth,
                y: principalPoint.y - focalLength * simd_dot(up, delta) / depth
            ))
        }
    }

    struct Pin: Equatable {
        let id: String
        let latitude: Double
        let longitude: Double
        let modelContact: SIMD3<Double>?

        init(id: String, coordinate: CLLocationCoordinate2D, modelContact: SIMD3<Double>? = nil) {
            self.id = id
            latitude = coordinate.latitude
            longitude = coordinate.longitude
            self.modelContact = modelContact
        }

        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    struct PinPlacement: Equatable {
        let point: CGPoint
        let contactOpacity: Double
    }

    private struct ContextAnchor: Equatable {
        let pin: Pin
        let point: CGPoint?
    }

    let style: CityDistrictMapStyle
    let styleRevision: Int
    let viewport: CGSize
    let latitude: Double
    let longitude: Double
    let distance: Double
    let heading: Double
    let pitch: Double
    let projection: Projection?
    private let fittedOpacity: Double
    private var sceneReady = true
    let cloudHandoff: Bool
    var projectionCutoff: Double { cloudHandoff ? 9_000 : Self.prewarmDistance }
    // Native MapKit owns far pins on its presentation clock. Conversion gaps
    // inside the modeled range never change this geographic owner.
    var usesGeographicPinOverlay: Bool { !cloudHandoff || distance < projectionCutoff }
    var opacity: Double { sceneReady ? fittedOpacity : 0 }
    var sceneBlend: SceneBlend? {
        guard viewport.width > 0, viewport.height > 0,
              let center = projection?.point(at: SIMD3(0, 125, -95)) else { return nil }
        // Concentrate the overlap near the edges during zoom. A side pan
        // at street scale keeps the existing geographic coverage fade.
        let zoomWeight = Self.fade((distance - Self.overviewDistance) / 220)
        let contrast = fittedOpacity * (1 - fittedOpacity) * zoomWeight
        let coreOpacity = fittedOpacity + contrast
        let edgeStrength = coreOpacity > 0 ? (fittedOpacity - contrast) / coreOpacity : 1
        let radius = viewport.width * (0.33 + 0.17 * fittedOpacity)
        return SceneBlend(center: center, innerRadius: radius, outerRadius: radius + viewport.width * 0.45,
                          layerOpacity: sceneReady ? coreOpacity : 0, outerStrength: edgeStrength)
    }
    var sceneLayerOpacity: Double { sceneBlend?.layerOpacity ?? opacity }
    var showsStreetDetail: Bool { opacity > 0.5 && distance <= Self.streetDistance }
    var cloudOpacity: Double { sceneReady || cloudHandoff ? fittedCloudOpacity : 0 }
    let cloudPatches: [CloudPatch]
    private let fittedCloudOpacity: Double
    let requestedOpacity: Double
    let shouldPrewarm: Bool
    let landmarkPoint: CGPoint?
    let cameraCenterPoint: CGPoint?
    /// Public landmark-only observation. Never used by the renderer or camera.
    struct RegistrationInspection: Equatable {
        let latitudeOffset: Double
        let longitudeOffset: Double
        let provenance: String
        let sourcePoint: CGPoint?
        let registeredPoint: CGPoint?
    }
    let registrationInspection: RegistrationInspection?
    private let registration: CityDistrictRegistration?
    private let eyeInsideLandmark: Bool
    private let hiddenContact: SIMD3<Double>?
    private let selectedPin: Pin?
    private let selectedPoint: CGPoint?
    private let cityHallPin: Pin?
    private let cityHallPoint: CGPoint?
    private let contextAnchors: [ContextAnchor]

    func withSceneReadiness(_ ready: Bool) -> Self {
        var frame = self
        frame.sceneReady = ready
        return frame
    }

    var needsProjectionRefresh: Bool {
        if shouldPrewarm && projection == nil && !eyeInsideLandmark { return true }
        // MapProxy may briefly lose conversions after a native camera change.
        // Outside model preparation there is no fitted projection to trigger
        // the existing retry, but the geographic clouds and selected pin still
        // need a fresh native sample. The caller schedules only one retry.
        // A partial conversion gap drops one bank just as an all-nil sample
        // drops every bank; both need the same bounded recovery.
        return cloudHandoff && style == .city && registration != nil
            && ((selectedPin != nil && selectedPoint == nil)
                || contextAnchors.contains(where: { $0.point == nil })
                || (fittedCloudOpacity > 0 && cloudPatches.count < Self.boundaryCloudPatches.count))
    }
    var hasRegistration: Bool { registration != nil }

    var mapCamera: MapCamera {
        MapCamera(centerCoordinate: .init(latitude: latitude, longitude: longitude),
                  distance: distance, heading: heading, pitch: pitch)
    }

    @MainActor
    init(camera: MapCamera, registration: CityDistrictRegistration?, style: CityDistrictMapStyle = .city,
         styleRevision: Int = 0, viewport: CGSize = .zero, selectedPin: Pin? = nil, cityHallPin: Pin? = nil,
         contextPins: [Pin] = [], traceCameraCenter: Bool = false, inspectRegistration: Bool = false,
         cloudHandoff: Bool = CityDistrictCamera.cloudHandoffEnabled, project: (CLLocationCoordinate2D) -> CGPoint?) {
        self.cloudHandoff = cloudHandoff
        self.style = style
        self.styleRevision = styleRevision
        self.viewport = viewport
        latitude = camera.centerCoordinate.latitude
        longitude = camera.centerCoordinate.longitude
        distance = camera.distance
        heading = camera.heading
        pitch = camera.pitch
        self.registration = registration
        if inspectRegistration, let registration {
            let origin = Self.coordinate(x: 0, z: 0)
            registrationInspection = RegistrationInspection(
                latitudeOffset: registration.latitudeOffset, longitudeOffset: registration.longitudeOffset,
                provenance: registration.provenance.rawValue,
                sourcePoint: Self.finitePoint(project(origin)),
                registeredPoint: Self.finitePoint(project(registration.mapCoordinate(origin))))
        } else {
            registrationInspection = nil
        }
        let target = Self.world(registration?.sceneCoordinate(camera.centerCoordinate) ?? camera.centerCoordinate)
        let edge = max(abs(target.x), abs(target.z))
        let hasViewport = viewport.width > 0 && viewport.height > 0
        let outerReach = Self.groundHalfExtent + min(1_000, distance * 0.65)
        let reachFade = Self.fade((outerReach - edge) / 200)
        let prewarm = cloudHandoff ? 9_000 : Self.prewarmDistance
        let canSeePastCenter = hasViewport && distance < (cloudHandoff ? prewarm : Self.fadeOutDistance) && reachFade > 0
        shouldPrewarm = style == .city && registration != nil && distance < prewarm
            && (edge < 850 || canSeePastCenter)
        // Use the modeled skyline at the existing Taipei overview. Keep a
        // longer blend outside it so the gray native building yields sooner.
        let zoom = Self.fade((Self.fadeOutDistance - distance) / (Self.fadeOutDistance - Self.overviewDistance))
        let centerCoverage = Self.fade((680 - edge) / 230)
        let shouldFit = shouldPrewarm && (centerCoverage > 0 || canSeePastCenter)
        let cloudStart = cloudHandoff ? 10_000 : Self.prewarmDistance
        let cloudPeak = cloudHandoff ? 8_000 : Self.cloudPeakDistance
        let cloudCoverage = cloudHandoff ? reachFade : centerCoverage
        let canShowClouds = cloudHandoff
            ? style == .city && registration != nil && distance < cloudStart : shouldPrewarm
        if canShowClouds, let registration, distance > Self.cloudClearDistance, cloudCoverage > 0, hasViewport {
            let approach = Self.fade((cloudStart - distance) / (cloudStart - cloudPeak))
            let reveal = Self.fade((distance - Self.cloudClearDistance) /
                                   (cloudPeak - Self.cloudClearDistance))
            fittedCloudOpacity = (cloudHandoff ? 0.98 : 0.42) * approach * reveal * cloudCoverage
            cloudPatches = Self.projectCloudPatches(registration: registration, viewport: viewport,
                                                    opening: 1 - reveal, boundaryBanks: cloudHandoff, project: project)
        } else {
            fittedCloudOpacity = 0
            cloudPatches = []
        }
        let landmark = shouldPrewarm ? registration.flatMap {
            Self.finitePoint(project($0.mapCoordinate(Self.coordinate(x: 0, z: 0))))
        } : nil
        landmarkPoint = landmark
        cameraCenterPoint = traceCameraCenter && distance < 5_500
            ? Self.finitePoint(project(camera.centerCoordinate)) : nil
        if shouldFit, let registration,
           let fit = Self.fit(camera: camera, target: target, project: { project(registration.mapCoordinate($0)) }),
           fit.error < Self.maximumFitError,
           Self.matchesVisibleLandmark(landmark, fit: fit, viewport: viewport) {
            // Let the terrain feather handle the boundary while a readable
            // portion of the district is still in view.
            let visibleCoverage = centerCoverage < 1 && canSeePastCenter
                ? Self.fade(fit.visibleGroundFraction(in: viewport) / 0.12) * reachFade : 0
            requestedOpacity = zoom * max(centerCoverage, visibleCoverage)
            eyeInsideLandmark = CityLandmark101.containsInterior(fit.eye)
            fittedOpacity = eyeInsideLandmark ? 0 : requestedOpacity
            projection = eyeInsideLandmark ? nil : fit
        } else {
            // Ask for the normal projection refresh while a nearby viewport
            // might still overlap the district.
            requestedOpacity = shouldFit ? zoom * max(centerCoverage, 0.01) : 0
            eyeInsideLandmark = false
            projection = nil
            fittedOpacity = 0
        }
        hiddenContact = projection.flatMap {
            CityLandmark101.hidesPinContact(from: $0.eye) ? CityLandmark101.pinContact : nil
        }
        self.selectedPin = selectedPin
        selectedPoint = Self.pinPoint(selectedPin, registration: registration, style: style,
                                      projection: projection, project: project)
        self.cityHallPin = cityHallPin
        cityHallPoint = fittedOpacity > 0
            ? Self.pinPoint(cityHallPin, registration: registration, style: style, projection: projection, project: project)
            : nil
        // Sample the native and modeled positions together before publishing this frame.
        contextAnchors = contextPins.map { pin in
            ContextAnchor(pin: pin, point: Self.finitePoint(project(pin.coordinate)))
        }
    }

    static func contextPinReveal(distance: Double, sceneOpacity: Double, primary: Bool) -> Double {
        let zoom = fade((contextPinDistance - distance) / 400)
        return primary ? zoom : zoom * fade((sceneOpacity - 0.5) / 0.35)
    }

    func selectedOverlayPoint(for pin: Pin) -> CGPoint? {
        selectedPlacement(for: pin)?.point
    }

    func selectedPlacement(for pin: Pin) -> PinPlacement? {
        guard pin == selectedPin else { return nil }
        return placement(for: pin, nativePoint: selectedPoint)
    }

    func cityHallOverlayPoint(for pin: Pin) -> CGPoint? {
        guard pin == cityHallPin else { return nil }
        return placement(for: pin, nativePoint: cityHallPoint)?.point
    }

    func ownsSelectedPin(_ pin: Pin) -> Bool {
        pin == selectedPin && (hasModelContact(for: pin) || selectedOverlayPoint(for: pin) != nil)
    }

    func ownsCityHallPin(_ pin: Pin) -> Bool {
        pin == cityHallPin && (hasModelContact(for: pin) || cityHallOverlayPoint(for: pin) != nil)
    }

    private func hasModelContact(for pin: Pin) -> Bool {
        opacity > 0 && pin.modelContact != nil && projection != nil
    }

    func ownsContextPin(_ pin: Pin) -> Bool {
        guard let anchor = contextAnchors.first(where: { $0.pin == pin }) else { return false }
        return hasModelContact(for: pin) || placement(for: pin, nativePoint: anchor.point) != nil
    }

    func contextPlacement(for pin: Pin) -> PinPlacement? {
        if pin == cityHallPin {
            return placement(for: pin, nativePoint: cityHallPoint)
        }
        guard let anchor = contextAnchors.first(where: { $0.pin == pin }) else { return nil }
        return placement(for: pin, nativePoint: anchor.point)
    }

    private func placement(for pin: Pin, nativePoint: CGPoint?) -> PinPlacement? {
        if hasModelContact(for: pin), let contact = pin.modelContact, let projection {
            // A roof behind the camera stays hidden instead of moving to the ground.
            guard let surface = projection.point(at: contact) else { return nil }
            let native = Self.finitePoint(nativePoint) ?? surface
            let reveal = sceneBlend?.opacity(at: surface) ?? opacity
            let point = CGPoint(x: native.x + (surface.x - native.x) * reveal,
                                y: native.y + (surface.y - native.y) * reveal)
            // Keep the same overlay owner when its model contact moves outside the viewport.
            return PinPlacement(point: point, contactOpacity: hiddenContact == contact ? 0 : reveal)
        }
        return Self.visiblePoint(Self.finitePoint(nativePoint), in: viewport).map {
            PinPlacement(point: $0, contactOpacity: 0)
        }
    }

    func canRetainProjection(for sample: Self) -> Bool {
        projection != nil && sample.needsProjectionRefresh
            && styleRevision == sample.styleRevision && style == sample.style && cloudHandoff == sample.cloudHandoff
            && viewport == sample.viewport && registration == sample.registration
            && latitude == sample.latitude && longitude == sample.longitude && distance == sample.distance
            && heading == sample.heading && pitch == sample.pitch
            && selectedPin == sample.selectedPin && cityHallPin == sample.cityHallPin
            && contextAnchors.map(\.pin) == sample.contextAnchors.map(\.pin)
    }

    private static func pinPoint(_ pin: Pin?, registration: CityDistrictRegistration?, style: CityDistrictMapStyle,
                                 projection: Projection?, project: (CLLocationCoordinate2D) -> CGPoint?) -> CGPoint? {
        guard style == .city, let pin else { return nil }
        if let point = finitePoint(project(pin.coordinate)) { return point }
        guard let registration, let projection else { return nil }
        let world = Self.world(registration.sceneCoordinate(pin.coordinate))
        guard max(abs(world.x), abs(world.z)) < 850 else { return nil }
        return projection.point(at: world)
    }

    private static func matchesVisibleLandmark(_ point: CGPoint?, fit: Projection, viewport: CGSize) -> Bool {
        guard let point = visiblePoint(point, in: viewport) else { return true }
        guard let predicted = fit.point(at: .zero) else { return false }
        return hypot(point.x - predicted.x, point.y - predicted.y) < 8
    }

    private static func visiblePoint(_ point: CGPoint?, in viewport: CGSize) -> CGPoint? {
        guard let point, CGRect(origin: .zero, size: viewport).contains(point) else { return nil }
        return point
    }

    private static func finitePoint(_ point: CGPoint?) -> CGPoint? {
        guard let point, point.x.isFinite, point.y.isFinite else { return nil }
        return point
    }

    static func world(_ coordinate: CLLocationCoordinate2D) -> SIMD3<Double> {
        SIMD3((coordinate.longitude - CityScenePlace.originLongitude) * 100_850,
              0, -(coordinate.latitude - CityScenePlace.originLatitude) * 111_195)
    }

    static func coordinate(x: Double, z: Double) -> CLLocationCoordinate2D {
        .init(latitude: CityScenePlace.originLatitude - z / 111_195,
              longitude: CityScenePlace.originLongitude + x / 100_850)
    }

    private static func fade(_ fraction: Double) -> Double {
        let x = min(1, max(0, fraction))
        return x * x * (3 - 2 * x)
    }

    private static let boundaryCloudPatches: [(x: Double, z: Double, radius: Double)] = [
        // Cover the join with the surrounding map, leaving the center
        // readable. Three central clouds exposed every road endpoint.
        (-650, -550, 430), (0, -570, 420), (650, -550, 440),
        (-710, 0, 430), (710, 0, 430),
        (-650, 650, 440), (0, 710, 420), (650, 650, 430),
    ]

    private static func projectCloudPatches(registration: CityDistrictRegistration, viewport: CGSize, opening: Double, boundaryBanks: Bool,
                                            project: (CLLocationCoordinate2D) -> CGPoint?) -> [CloudPatch] {
        func screenPoint(x: Double, z: Double) -> CGPoint? {
            finitePoint(project(registration.mapCoordinate(coordinate(x: x, z: z))))
        }
        // Keep the haze on the district as the native camera pans or rotates.
        let patches: [(x: Double, z: Double, radius: Double)] = boundaryBanks ? boundaryCloudPatches : [
            (-290, -360, 490),
            (260, -130, 530),
            (-210, 220, 400),
        ]
        // Move the clouds away from the district center as the viewer
        // approaches. Project both the drift and shape in map coordinates.
        let spread = 1 + 0.95 * opening
        let widthLimit = viewport.width * (0.72 - 0.23 * opening)
        return patches.compactMap { patch in
            let x = patch.x * spread, z = patch.z * spread
            let worldRadius = patch.radius * (1 - 0.28 * opening)
            guard let center = screenPoint(x: x, z: z),
                  let eastPoint = screenPoint(x: x + worldRadius, z: z) else { return nil }
            let east = CGVector(dx: eastPoint.x - center.x, dy: eastPoint.y - center.y)
            let eastLength = hypot(east.dx, east.dy)
            guard eastLength > 1 else { return nil }
            let fallback = CGVector(dx: -east.dy * 0.62, dy: east.dx * 0.62)
            let south = screenPoint(x: x, z: z + worldRadius * 0.78).map { point in
                let axis = CGVector(dx: point.x - center.x, dy: point.y - center.y)
                return east.dx * axis.dy - east.dy * axis.dx > 1 ? axis : fallback
            } ?? fallback
            let scale = min(1, widthLimit / max(eastLength, hypot(south.dx, south.dy)))
            return CloudPatch(center: center, east: CGVector(dx: east.dx * scale, dy: east.dy * scale),
                              south: CGVector(dx: south.dx * scale, dy: south.dy * scale),
                              mirrorsContour: patch.x > 0)
        }
    }

    private struct Sample {
        let offset: SIMD3<Double>
        let right: Double
        let up: Double
        let towardEye: Double
        let pixel: SIMD2<Double>
    }

    private static func measuredProjection(samples: [Sample], step: Double, target: SIMD3<Double>,
                                           right: SIMD3<Double>, down: SIMD3<Double>,
                                           reportedPitch: Double, reportedDistance: Double) -> Projection? {
        guard reportedPitch >= 12 * .pi / 180,
              let center = samples.first(where: { $0.offset == .zero })?.pixel else { return nil }
        // The two ground axes share a perspective denominator. The ratio of
        // their screen scales gives cos(pitch), without trusting the reported tilt.
        var normal = simd_double3x3(columns: (.zero, .zero, .zero))
        var values = SIMD3<Double>.zero
        func accumulate(_ row: SIMD3<Double>, _ value: Double) {
            normal.columns.0 += row * row.x
            normal.columns.1 += row * row.y
            normal.columns.2 += row * row.z
            values += row * value
        }
        for sample in samples {
            let u = sample.right / step, v = simd_dot(down, sample.offset) / step
            let pixel = sample.pixel - center
            accumulate(.init(u, 0, pixel.x * v), pixel.x)
            accumulate(.init(0, v, pixel.y * v), pixel.y)
        }
        guard abs(simd_determinant(normal)) > 1e-9 else { return nil }
        let coefficients = simd_inverse(normal) * values
        let cosine = coefficients.y / coefficients.x
        guard coefficients.x > 0, coefficients.z > 0,
              cosine > 0, cosine < 1 else { return nil }
        let pitch = acos(cosine)
        guard abs(pitch - reportedPitch) <= 18 * .pi / 180 else { return nil }
        let distance = sin(pitch) * step / coefficients.z
        let focalLength = coefficients.x * distance / step
        guard distance >= 0.5 * reportedDistance, distance <= 2 * reportedDistance,
              focalLength > 50, focalLength < 10_000 else { return nil }
        let towardEye = down * sin(pitch) + SIMD3(0, cos(pitch), 0)
        return Projection(eye: target + towardEye * distance, target: target,
                          up: simd_cross(towardEye, right), focalLength: focalLength,
                          principalPoint: .init(x: center.x, y: center.y), error: .infinity)
    }

    private static func measuredPose(samples: [Sample], step: Double, target: SIMD3<Double>,
                                     reportedDistance: Double) -> Projection? {
        guard let center = samples.first(where: { $0.offset == .zero })?.pixel else { return nil }
        // Opposite ground probes share a line through the center. Their
        // harmonic scale removes perspective so we can measure the real turn
        // while MapKit's reported heading already names the destination.
        func axis(_ offset: SIMD3<Double>) -> (slope: SIMD2<Double>, perspective: Double)? {
            guard let positive = samples.first(where: { $0.offset == offset })?.pixel,
                  let negative = samples.first(where: { $0.offset == -offset })?.pixel else { return nil }
            let a = positive - center, b = negative - center
            let near = simd_length(a), far = simd_length(b)
            guard min(near, far) > 1, simd_dot(a, b) < 0 else { return nil }
            return ((a * far - b * near) / (near + far), (near - far) / (near + far))
        }
        guard let x = axis(.init(step, 0, 0)), let z = axis(.init(0, 0, step)) else { return nil }
        let horizontalScale = hypot(x.slope.x, z.slope.x)
        guard horizontalScale > 1 else { return nil }
        let cosine = hypot(x.slope.y, z.slope.y) / horizontalScale
        guard cosine > 0, cosine <= 1.001 else { return nil }
        let heading = atan2(z.slope.x, x.slope.x)
        let pitch = acos(min(1, cosine))
        let right = SIMD3(cos(heading), 0, sin(heading))
        let down = SIMD3(-sin(heading), 0, cos(heading))
        let perspective = x.perspective * down.x + z.perspective * down.z
        let distance: Double
        if pitch < 4 * .pi / 180 {
            // Ground probes cannot separate focal length and distance at zero tilt.
            distance = reportedDistance
        } else {
            guard perspective > 0 else { return nil }
            distance = sin(pitch) * step / perspective
        }
        let focalLength = horizontalScale * distance / step
        guard distance >= 0.5 * reportedDistance, distance <= 2 * reportedDistance,
              focalLength > 50, focalLength < 10_000 else { return nil }
        let towardEye = down * sin(pitch) + SIMD3(0, cos(pitch), 0)
        return Projection(eye: target + towardEye * distance, target: target,
                          up: simd_cross(towardEye, right), focalLength: focalLength,
                          principalPoint: .init(x: center.x, y: center.y), error: .infinity)
    }

    private static func fit(camera: MapCamera, target: SIMD3<Double>,
                            project: (CLLocationCoordinate2D) -> CGPoint?) -> Projection? {
        guard camera.distance.isFinite, camera.distance > 0,
              camera.heading.isFinite, camera.pitch.isFinite else { return nil }
        let heading = camera.heading * .pi / 180
        let pitch = camera.pitch * .pi / 180
        let right = SIMD3(cos(heading), 0, sin(heading))
        let towardEye = SIMD3(-sin(heading) * sin(pitch), cos(pitch), cos(heading) * sin(pitch))
        let up = simd_cross(towardEye, right)
        let step = max(12, min(140, camera.distance * 0.13))
        let traceProbes = CityDistrictTrace.enabled && camera.distance < 900
        var probes: [String] = []
        var finalError: Double?
        func groundPoint(_ offset: SIMD3<Double>) -> CGPoint? {
            let point = project(coordinate(x: target.x + offset.x, z: target.z + offset.z))
            if traceProbes {
                probes.append("\(offset.x),\(offset.z),\(point?.x ?? .nan),\(point?.y ?? .nan)")
            }
            return point
        }
        defer {
            if traceProbes {
                CityDistrictTrace.write("fit-probes\t\(camera.distance)\t\(camera.heading)\t\(camera.pitch)\t\(finalError ?? .nan)\t\(probes.joined(separator: ";"))")
            }
        }
        var samples: [Sample] = []
        for x in [-step, 0, step] {
            for z in [-step, 0, step] {
                let offset = SIMD3(x, 0, z)
                guard let pixel = groundPoint(offset),
                      pixel.x.isFinite, pixel.y.isFinite else { continue }
                samples.append(Sample(offset: offset, right: simd_dot(right, offset), up: simd_dot(up, offset),
                                      towardEye: simd_dot(towardEye, offset), pixel: SIMD2(Double(pixel.x), Double(pixel.y))))
            }
        }
        guard samples.count >= 5 else { return nil }

        func evaluate(_ distance: Double) -> Projection? {
            var projected: [SIMD2<Double>] = []
            var mean = SIMD2<Double>.zero
            var meanPixel = SIMD2<Double>.zero
            for sample in samples {
                let depth = distance - sample.towardEye
                guard depth > 2 else { return nil }
                let point = SIMD2(sample.right / depth, -sample.up / depth)
                projected.append(point)
                mean += point
                meanPixel += sample.pixel
            }
            mean /= Double(samples.count)
            meanPixel /= Double(samples.count)
            var covariance = 0.0
            var variance = 0.0
            for (point, sample) in zip(projected, samples) {
                let delta = point - mean
                covariance += simd_dot(delta, sample.pixel - meanPixel)
                variance += simd_length_squared(delta)
            }
            guard variance > 1e-9 else { return nil }
            let focalLength = covariance / variance
            guard focalLength > 50, focalLength < 10_000 else { return nil }
            let center = meanPixel - focalLength * mean
            let error = zip(projected, samples).map { simd_length(center + focalLength * $0.0 - $0.1.pixel) }.max() ?? .infinity
            return Projection(eye: target + towardEye * distance, target: target, up: up,
                              focalLength: focalLength, principalPoint: .init(x: center.x, y: center.y), error: error)
        }

        // At zero tilt, distance and focal length are interchangeable on the
        // ground plane. Use the native distance to keep elevated geometry stable.
        var low = camera.distance * 0.50
        var high = camera.distance * 2.0
        if abs(camera.pitch) < 4 {
            low = camera.distance
            high = camera.distance
        } else {
            for _ in 0..<18 {
                let a = (2 * low + high) / 3
                let b = (low + 2 * high) / 3
                if (evaluate(a)?.error ?? .infinity) < (evaluate(b)?.error ?? .infinity) {
                    high = b
                } else {
                    low = a
                }
            }
        }
        var validation = samples.map { (offset: $0.offset, pixel: $0.pixel) }
        for offset in [SIMD3(step * 0.63, 0, -step * 1.16),
                       SIMD3(-step * 1.16, 0, step * 0.63)] {
            guard let point = groundPoint(offset), point.x.isFinite, point.y.isFinite else { return nil }
            validation.append((offset, SIMD2(Double(point.x), Double(point.y))))
        }
        func validate(_ fit: Projection) -> Projection? {
            var error = 0.0
            for probe in validation {
                guard let point = fit.point(at: target + probe.offset) else { return nil }
                error = max(error, hypot(point.x - probe.pixel.x, point.y - probe.pixel.y))
            }
            return Projection(eye: fit.eye, target: fit.target, up: fit.up, focalLength: fit.focalLength,
                              principalPoint: fit.principalPoint, error: error)
        }
        let reported = evaluate((low + high) / 2).flatMap(validate)
        finalError = reported?.error
        if let reported, reported.error < maximumFitError { return reported }
        let down = SIMD3(-sin(heading), 0, cos(heading))
        if let measured = measuredProjection(samples: samples, step: step, target: target, right: right, down: down,
                                             reportedPitch: pitch, reportedDistance: camera.distance),
           let validated = validate(measured), validated.error < maximumFitError {
            if traceProbes {
                CityDistrictTrace.write("fit-pitch-recovery\t\(camera.distance)\t\(camera.pitch)\t\(reported?.error ?? .nan)\t\(validated.error)")
            }
            return validated
        }
        guard let measured = measuredPose(samples: samples, step: step, target: target,
                                          reportedDistance: camera.distance),
              let validated = validate(measured), validated.error < maximumFitError else { return reported }
        if traceProbes {
            CityDistrictTrace.write("fit-heading-recovery\t\(camera.distance)\t\(camera.heading)\t\(reported?.error ?? .nan)\t\(validated.error)")
        }
        return validated
    }
}
#endif
