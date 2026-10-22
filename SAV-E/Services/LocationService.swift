import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?

    private let manager = CLLocationManager()
    private var pendingContinuation: CheckedContinuation<CLLocation?, Never>?

#if DEBUG
    /// Deterministic denied-state for UI tests — springboard permission
    /// alerts are too flaky to drive the spec P4 recovery path.
    private let simulatesDeniedAuthorization = ProcessInfo.processInfo.arguments
        .contains("--uitest-location-denied")
    /// Deterministic allowed-state so Home can show Near you without a
    /// springboard permission alert. The Codex Tiantan face uses the
    /// Tiantan fix; other UI tests keep the Taipei fix.
    private let simulatesTiantanFix = ProcessInfo.processInfo.arguments
        .contains("--uitest-location-tiantan")
        || ProcessInfo.processInfo.arguments.contains("--uitest-doodle-parity-face")
    private let simulatesAllowedAuthorization = ProcessInfo.processInfo.arguments
        .contains("--uitest-location-allowed") || simulatesTiantanFix
    private static let uiTestTaipei = CLLocation(latitude: 25.0330, longitude: 121.5654)
    /// Codex / spec §8 Tiantan face: 450 m / 800 m / 1.1 km from the three Eat rows.
    private static let uiTestTiantan = CLLocation(latitude: 39.882192, longitude: 116.4066)
#else
    private let simulatesDeniedAuthorization = false
    private let simulatesAllowedAuthorization = false
#endif

    /// Spec P4: a denied/restricted locate tap must surface a recovery
    /// affordance instead of failing silently.
    var isAuthorizationDenied: Bool {
        if simulatesDeniedAuthorization { return true }
        if simulatesAllowedAuthorization { return false }
        switch manager.authorizationStatus {
        case .denied, .restricted: return true
        default: return false
        }
    }

    override init() {
        if simulatesDeniedAuthorization {
            authorizationStatus = .denied
        } else if simulatesAllowedAuthorization {
            authorizationStatus = .authorizedWhenInUse
        } else {
            authorizationStatus = manager.authorizationStatus
        }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
#if DEBUG
        if simulatesAllowedAuthorization {
            currentLocation = simulatesTiantanFix ? Self.uiTestTiantan : Self.uiTestTaipei
        }
#endif
    }

    func requestCurrentLocation() async -> CLLocation? {
        if simulatesDeniedAuthorization {
            return nil
        }
        if simulatesAllowedAuthorization {
            return currentLocation
        }
        if let currentLocation {
            return currentLocation
        }

        guard pendingContinuation == nil else {
            return currentLocation
        }

        return await withCheckedContinuation { continuation in
            pendingContinuation = continuation

            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                finish(with: nil)
            @unknown default:
                finish(with: nil)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if simulatesDeniedAuthorization || simulatesAllowedAuthorization { return }
        authorizationStatus = manager.authorizationStatus

        guard pendingContinuation != nil else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: nil)
        case .notDetermined:
            break
        @unknown default:
            finish(with: nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationService: failed to resolve current location: \(error)")
        finish(with: nil)
    }

    private func finish(with location: CLLocation?) {
        if let location {
            currentLocation = location
        }
        pendingContinuation?.resume(returning: location)
        pendingContinuation = nil
    }
}
