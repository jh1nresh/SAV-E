#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Combine
import MapKit

@MainActor
protocol LiveWalkingDirections {
    func route() async throws -> MKRoute
    func cancel()
}

@MainActor
private final class LiveAppleWalkingDirections: LiveWalkingDirections {
    private let directions: MKDirections
    init(request: MKDirections.Request) { directions = MKDirections(request: request) }
    func route() async throws -> MKRoute {
        guard let route = try await directions.calculate().routes.first else { throw MKError(.directionsNotFound) }
        return route
    }
    func cancel() { directions.cancel() }
}

@MainActor
final class LiveRoutePlan: ObservableObject {
    @Published private(set) var stops: [LiveMapPlace] = []
    @Published private(set) var routes: [MKRoute] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var started = false
    @Published private(set) var currentIndex = 0
    @Published private(set) var listID: UUID?
    @Published private(set) var isAccessValidated = false
    @Published var beginsAt = Date()
    @Published var dwellMinutes = 60
    private var revision = 0
    private var activeDirections: (any LiveWalkingDirections)?
    private let makeDirections: @MainActor (MKDirections.Request) -> any LiveWalkingDirections
    private let currentSession: @MainActor () -> Bool
    private var authObservation: AnyCancellable?

    convenience init(ownerSubject: String, sessionGeneration: Int) {
        self.init(ownerSubject: ownerSubject, sessionGeneration: sessionGeneration,
                  makeDirections: { LiveAppleWalkingDirections(request: $0) }) {
            let auth = PrivyAuthService.shared
            guard case .authenticated = auth.authState else { return false }
            return auth.currentUserId == ownerSubject && auth.sessionGeneration == sessionGeneration
        }
        let auth = PrivyAuthService.shared
        authObservation = Publishers.CombineLatest(auth.$authState, auth.$sessionGeneration)
            .sink { [weak self] state, generation in
                guard case .authenticated(let owner) = state,
                      owner == ownerSubject, generation == sessionGeneration else {
                    self?.cancel(); return
                }
            }
    }

    init(ownerSubject: String, sessionGeneration: Int,
         makeDirections: @escaping @MainActor (MKDirections.Request) -> any LiveWalkingDirections,
         sessionIsCurrent: @escaping @MainActor () -> Bool) {
        self.makeDirections = makeDirections; currentSession = sessionIsCurrent
    }

    func cancel() {
        revision += 1; activeDirections?.cancel(); activeDirections = nil
        stops = []; routes = []; started = false; currentIndex = 0
        isLoading = false; error = nil; listID = nil; isAccessValidated = false
    }

    /// Retain only an already-completed plan in this account-bound instance.
    /// Nothing may display or advance until the list is revalidated on return.
    func suspendForNavigation() {
        guard sessionIsCurrent else { cancel(); return }
        revision += 1; activeDirections?.cancel(); activeDirections = nil
        isLoading = false; error = nil; isAccessValidated = false
    }

    func reconcile(listID: UUID?, places: [LiveMapPlace]) {
        guard sessionIsCurrent, let listID, self.listID == listID, !stops.isEmpty,
              routes.count == stops.count - 1,
              stops.allSatisfy({ stop in
                  let matches = places.filter { $0.id == stop.id }
                  guard matches.count == 1, let current = matches.first else { return false }
                  return current.place.name == stop.place.name && current.place.address == stop.place.address
                      && current.place.category == stop.place.category
                      && current.coordinate.latitude == stop.coordinate.latitude
                      && current.coordinate.longitude == stop.coordinate.longitude
              }) else { cancel(); return }
        isAccessValidated = true
    }

    func build(_ values: [LiveMapPlace], listID: UUID) async {
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
                let directions = makeDirections(request)
                activeDirections = directions
                let route = try await directions.route()
                try Task.checkCancellation()
                guard ticket == revision, sessionIsCurrent else { throw CancellationError() }
                found.append(route)
            }
            guard ticket == revision, sessionIsCurrent else { return }
            activeDirections = nil; stops = values; routes = found; isLoading = false
            self.listID = listID; isAccessValidated = true
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
        guard sessionIsCurrent, isAccessValidated, !stops.isEmpty, routes.count == stops.count - 1 else { return }
        started = true; currentIndex = 0
    }

    func advance() {
        guard sessionIsCurrent, isAccessValidated, started, currentIndex < stops.count else { return }
        currentIndex += 1
    }

    private var sessionIsCurrent: Bool {
        currentSession()
    }
}

/// A new shared snapshot must be reconciled before it can reveal an old plan.
@MainActor
struct LiveGuideAccess {
    private var reconciledSnapshot: UInt64?

    mutating func invalidate() { reconciledSnapshot = nil }

    mutating func reconcile(plan: LiveRoutePlan, outing: LiveOutingModel, places: [LiveMapPlace]) {
        plan.reconcile(listID: outing.selectedListID, places: places)
        reconciledSnapshot = outing.snapshotRevision
    }

    func permits(plan: LiveRoutePlan, outing: LiveOutingModel) -> Bool {
        reconciledSnapshot == outing.snapshotRevision && plan.isAccessValidated
            && plan.listID == outing.selectedListID && !outing.isLoading && !outing.isWorking
    }
}
#endif
