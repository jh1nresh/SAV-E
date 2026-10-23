import CoreLocation
import Foundation

/// Home's 3 km Near-you filter must not keep a first-fix forever after travel
/// or a resume. Callers still show the last known location while a refresh
/// is in flight.
enum SaveLocationFreshness {
    static let maxAge: TimeInterval = 5 * 60

    static func shouldRefresh(
        cached: CLLocation?,
        at now: Date = Date(),
        maxAge: TimeInterval = maxAge
    ) -> Bool {
        guard let cached else { return true }
        return now.timeIntervalSince(cached.timestamp) >= maxAge
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?

    private let manager = CLLocationManager()
    private var pendingContinuations: [CheckedContinuation<CLLocation?, Never>] = []

#if DEBUG
    /// Deterministic denied-state for UI tests — springboard permission
    /// alerts are too flaky to drive the spec P4 recovery path.
    private let simulatesDeniedAuthorization = ProcessInfo.processInfo.arguments
        .contains("--uitest-location-denied")
    /// Deterministic allowed-state with a Taipei fix so Home can show
    /// Near you without a springboard permission alert.
    private let simulatesTiantanFix = ProcessInfo.processInfo.arguments
        .contains("--uitest-location-tiantan")
    private let simulatesAllowedAuthorization = ProcessInfo.processInfo.arguments
        .contains("--uitest-location-allowed")
        || ProcessInfo.processInfo.arguments.contains("--uitest-location-tiantan")
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
        await requestCurrentLocation(forceRefresh: false)
    }

    func requestCurrentLocation(forceRefresh: Bool) async -> CLLocation? {
        if simulatesDeniedAuthorization {
            return nil
        }
        if simulatesAllowedAuthorization {
            return currentLocation
        }
        if !forceRefresh,
           let currentLocation,
           !SaveLocationFreshness.shouldRefresh(cached: currentLocation) {
            return currentLocation
        }

        return await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
            guard pendingContinuations.count == 1 else { return }
            startRequest()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if simulatesDeniedAuthorization || simulatesAllowedAuthorization { return }
        authorizationStatus = manager.authorizationStatus

        guard !pendingContinuations.isEmpty else { return }

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

    private func startRequest() {
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

    private func finish(with location: CLLocation?) {
        if let location {
            currentLocation = location
        }
        let waiters = pendingContinuations
        pendingContinuations = []
        let result = location ?? currentLocation
        waiters.forEach { $0.resume(returning: result) }
    }
}
