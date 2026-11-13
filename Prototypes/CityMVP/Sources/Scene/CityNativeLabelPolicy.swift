#if SAVVY_CITY_MVP
import MapKit
import SwiftUI

/// Whole-view MapKit POI filtering follows the authored district, not selection.
/// The dead band avoids repeatedly changing native configuration near its edge.
enum CityNativeLabelPolicy: String {
    case native, district

    func updated(camera: MapCamera, registration: CityDistrictRegistration?, style: CityDistrictMapStyle,
                 sceneReady: Bool, projectionAvailable: Bool, settled: Bool, contextLabels: Bool = false) -> Self {
        guard sceneReady, let registration, style == .city,
              CLLocationCoordinate2DIsValid(camera.centerCoordinate), camera.distance.isFinite,
              camera.distance > 0 else { return .native }
        guard settled else { return self }
        let point = CityDistrictCamera.world(registration.sceneCoordinate(camera.centerCoordinate))
        let edge = max(abs(point.x), abs(point.z))
        let reach = 700 + min(1_000, camera.distance * 0.65)
        let enter = contextLabels ? min(1_300, reach - 200) : 650
        let exit = contextLabels ? min(1_500, reach - 100) : 850
        switch self {
        case .native:
            return projectionAvailable && edge <= enter && camera.distance <= 8_500 ? .district : .native
        case .district:
            // A native configuration/lighting update can momentarily interrupt
            // conversion. Keep an already prepared district quiet through that
            // gap; geography, zoom and actual scene failure still restore POIs.
            return edge >= exit || camera.distance >= 9_000 ? .native : .district
        }
    }
}
#endif
