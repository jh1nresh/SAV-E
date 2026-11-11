#if SAVVY_CITY_MVP
import MapKit

/// Aligns a small WGS84 district model with the active MapKit basemap.
struct CityDistrictRegistration: Equatable, Sendable {
    let latitudeOffset: Double
    let longitudeOffset: Double

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
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "台北101"
        request.region = MKCoordinateRegion(center: CityDistrictCamera.coordinate(x: 0, z: 0),
                                            latitudinalMeters: 1_900, longitudinalMeters: 1_900)
        let search = MKLocalSearch(request: request)
        CityDistrictTrace.write("registration\tstart")
        let registration = await firstResult(timeout: .seconds(10), start: { finish in
            search.start { response, _ in
                finish(response?.mapItems.lazy.compactMap { item in
                    fromSearchResult(name: item.name, coordinate: item.placemark.coordinate)
                }.first)
            }
        }, cancel: { search.cancel() })
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
