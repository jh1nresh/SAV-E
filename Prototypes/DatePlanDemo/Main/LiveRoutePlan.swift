#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Combine
import MapKit

@MainActor
final class LiveRoutePlan: ObservableObject {
    @Published private(set) var stops: [LiveMapPlace] = []
    @Published private(set) var routes: [MKRoute] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var started = false
    @Published private(set) var currentIndex = 0
    @Published var beginsAt = Date()
    @Published var dwellMinutes = 60
    private let owner: String
    private let generation: Int
    private var revision = 0
    private var activeDirections: MKDirections?

    init(ownerSubject: String, sessionGeneration: Int) {
        owner = ownerSubject; generation = sessionGeneration
    }

    func cancel() {
        revision += 1; activeDirections?.cancel(); activeDirections = nil
        stops = []; routes = []; started = false; currentIndex = 0
        isLoading = false; error = nil
    }

    func build(_ values: [LiveMapPlace]) async {
        cancel()
        guard (2...6).contains(values.count), sessionIsCurrent else { return }
        let ticket = revision
        isLoading = true
        var found: [MKRoute] = []
        do {
            for index in 1..<values.count {
                try Task.checkCancellation()
                guard ticket == revision, sessionIsCurrent else { throw CancellationError() }
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: values[index - 1].coordinate))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: values[index].coordinate))
                request.transportType = .walking
                let directions = MKDirections(request: request)
                activeDirections = directions
                let response = try await directions.calculate()
                try Task.checkCancellation()
                guard ticket == revision, sessionIsCurrent else { throw CancellationError() }
                guard let route = response.routes.first else { throw MKError(.directionsNotFound) }
                found.append(route)
            }
            guard ticket == revision, sessionIsCurrent else { return }
            activeDirections = nil; stops = values; routes = found; isLoading = false
        } catch {
            guard ticket == revision else { return }
            activeDirections = nil; isLoading = false
            if !(error is CancellationError) && sessionIsCurrent {
                self.error = "暫時取得不到步行路線，請重試或使用導航。"
            }
        }
    }

    func arrival(at index: Int) -> Date {
        let travel = routes.prefix(index).reduce(0) { $0 + $1.expectedTravelTime }
        return beginsAt.addingTimeInterval(Double(index * dwellMinutes * 60) + travel)
    }

    func start() {
        guard sessionIsCurrent, !stops.isEmpty, routes.count == stops.count - 1 else { return }
        started = true; currentIndex = 0
    }

    func advance() {
        guard sessionIsCurrent, started, currentIndex < stops.count else { return }
        currentIndex += 1
    }

    private var sessionIsCurrent: Bool {
        let auth = PrivyAuthService.shared
        guard case .authenticated = auth.authState else { return false }
        return auth.currentUserId == owner && auth.sessionGeneration == generation
    }
}
#endif
