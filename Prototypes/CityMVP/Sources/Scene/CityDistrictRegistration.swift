#if SAVVY_CITY_MVP
import MapKit

/// Aligns a small WGS84 district model with the active MapKit basemap.
struct CityDistrictRegistration: Equatable {
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

    @MainActor
    static func resolve() async -> Self? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "台北101"
        request.region = MKCoordinateRegion(center: CityDistrictCamera.coordinate(x: 0, z: 0),
                                            latitudinalMeters: 1_900, longitudinalMeters: 1_900)
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        let acceptedNames: Set<String> = [
            "taipei101", "taipei101building", "taibei101", "taibei101building",
            "台北101", "臺北101", "台北101大樓", "臺北101大樓",
        ]
        return response.mapItems.lazy.compactMap { item -> Self? in
            let name = item.name?.lowercased().filter { $0.isLetter || $0.isNumber } ?? ""
            guard acceptedNames.contains(name) else { return nil }
            return fromLandmark(item.placemark.coordinate)
        }.first
    }
}
#endif
