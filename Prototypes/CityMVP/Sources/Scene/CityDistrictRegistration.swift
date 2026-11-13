#if SAVVY_CITY_MVP
import MapKit

/// Aligns a small WGS84 district model with the active MapKit basemap.
struct CityDistrictRegistration: Equatable, Sendable {
    enum Provenance: String, Sendable { case liveSearch = "live-search", pairedFixture = "paired-fixture" }
    let latitudeOffset: Double
    let longitudeOffset: Double
    let provenance: Provenance

    init(latitudeOffset: Double, longitudeOffset: Double, provenance: Provenance = .liveSearch) {
        self.latitudeOffset = latitudeOffset
        self.longitudeOffset = longitudeOffset
        self.provenance = provenance
    }

    /// Test-only input from the successful control in the same paired test.
    /// This never caches coordinates or changes ordinary startup/search.
    static let pairedAnchorPrefix = "--verify-paired-mapkit-anchor="
    static func pairedFixture(arguments: [String]) -> Self? {
        guard arguments.contains("--verify-xinyi"), arguments.contains("--verify-xinyi-far-render") else { return nil }
        let inputs = arguments.filter { $0.hasPrefix(pairedAnchorPrefix) }
        guard inputs.count == 1 else { return nil }
        let parts = inputs[0].dropFirst(pairedAnchorPrefix.count).split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]),
              let anchor = fromLandmark(.init(latitude: latitude, longitude: longitude)) else { return nil }
        return Self(latitudeOffset: anchor.latitudeOffset, longitudeOffset: anchor.longitudeOffset,
                    provenance: .pairedFixture)
    }

    func mapCoordinate(_ source: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        .init(latitude: source.latitude + latitudeOffset, longitude: source.longitude + longitudeOffset)
    }

    func sceneCoordinate(_ native: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        .init(latitude: native.latitude - latitudeOffset, longitude: native.longitude - longitudeOffset)
    }

    static func fromLandmark(_ native: CLLocationCoordinate2D) -> Self? {
        let offset = CityDistrictCamera.world(native)
        guard CLLocationCoordinate2DIsValid(native), hypot(offset.x, offset.z) < 800 else { return nil }
        return Self(latitudeOffset: native.latitude - CityScenePlace.originLatitude,
                    longitudeOffset: native.longitude - CityScenePlace.originLongitude)
    }

    static func fromSearchResult(name: String?, coordinate: CLLocationCoordinate2D) -> Self? {
        let acceptedNames: Set<String> = [
            "taipei101", "taipei101building", "taibei101", "taibei101building",
            "台北101", "臺北101", "台北101大樓", "臺北101大樓", "台北101大楼",
        ]
        let normalized = name?.lowercased().filter { $0.isLetter || $0.isNumber } ?? ""
        guard acceptedNames.contains(normalized) else { return nil }
        return fromLandmark(coordinate)
    }

    @MainActor
    static func resolve() async -> Self? {
        let arguments = ProcessInfo.processInfo.arguments
        if CityDistrictTrace.enabled, arguments.contains("--verify-xinyi-far-render"),
           arguments.contains(where: { $0.hasPrefix(pairedAnchorPrefix) }) {
            let fixture = pairedFixture(arguments: arguments)
            CityDistrictTrace.write("registration\tpaired-fixture-\(fixture == nil ? "invalid" : "ready")")
            return fixture
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "台北101"
        request.region = MKCoordinateRegion(center: CityDistrictCamera.coordinate(x: 0, z: 0),
                                            latitudinalMeters: 1_900, longitudinalMeters: 1_900)
        let search = MKLocalSearch(request: request)
        let tracesRegistration = CityDistrictTrace.enabled
        CityDistrictTrace.write("registration\tstart")
        let registration = await firstResult(timeout: .seconds(10), start: { finish in
            search.start { response, error in
                let match = response?.mapItems.lazy.compactMap { item in
                    fromSearchResult(name: item.name, coordinate: item.placemark.coordinate)
                }.first
                if tracesRegistration {
                    // Only public error metadata/counts cross to the UI actor;
                    // never transfer MapKit's response or log names/addresses.
                    let event: String
                    if let error = error as NSError? {
                        event = "error\t\(error.domain)\t\(error.code)"
                    } else {
                        event = "response\t\(response?.mapItems.count ?? 0)\t\(match != nil)"
                    }
                    let time = ProcessInfo.processInfo.systemUptime
                    Task { @MainActor in
                        CityDistrictTrace.write("registration-completion\t\(time)\t\(event)")
                    }
                }
                finish(match)
            }
        }, cancel: { search.cancel() })
        if Task.isCancelled { CityDistrictTrace.write("registration\ttask-cancelled") }
        CityDistrictTrace.write("registration\t\(registration == nil ? "unavailable" : "ready")")
        return registration
    }

    /// Completion, timeout and task cancellation race for one result. Late native
    /// callbacks cannot overwrite it, and cancellation never waits for MapKit.
    @MainActor
    static func firstResult(timeout: Duration,
                            start: (@escaping @Sendable (Self?) -> Void) -> Void,
                            cancel: () -> Void) async -> Self? {
        let (stream, continuation) = AsyncStream<Self?>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let deadline = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            CityDistrictTrace.write("registration-race\tdeadline\t\(ProcessInfo.processInfo.systemUptime)")
            continuation.yield(nil)
            continuation.finish()
        }
        defer {
            continuation.finish()
            deadline.cancel()
            cancel()
        }
        start { result in
            continuation.yield(result)
            continuation.finish()
        }
        for await result in stream { return result }
        return nil
    }
}
#endif
