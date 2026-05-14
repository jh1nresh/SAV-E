import Foundation
import MapKit
import SwiftUI

@MainActor
final class MapViewModel: ObservableObject {
    @Published var places: [Place] = Place.mockList
    @Published var selectedPlace: Place?
    @Published var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
    @Published var selectedCategories: Set<PlaceCategory> = []
    @Published var activeFilter: Set<UUID>?       // nil = show all
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var isLoading = false
    @Published var isLocatingUser = false
    @Published var calculatedRoute: MKPolyline?

    private let supabaseService: SupabaseServiceProtocol
    private let authService: PrivyAuthService
    private let pendingImportService: PendingPlaceImportService
    private let locationService: LocationService
    private var importedPendingKeys: Set<String> = []
    private var didRequestInitialLocation = false

    init(
        supabaseService: SupabaseServiceProtocol = SupabaseService.shared,
        pendingImportService: PendingPlaceImportService = .shared,
        locationService: LocationService? = nil
    ) {
        self.supabaseService = supabaseService
        self.authService = PrivyAuthService.shared
        self.pendingImportService = pendingImportService
        self.locationService = locationService ?? .shared
    }

    // MARK: - Computed

    var filteredPlaces: [Place] {
        var result = places
        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.category) }
        }
        if let filter = activeFilter {
            result = result.filter { filter.contains($0.id) }
        }
        return result
    }

    var routePolyline: MKPolyline? {
        guard let polyline = calculatedRoute else {
            // Fallback to straight lines if no calculated route
            guard routeCoordinates.count >= 2 else { return nil }
            return MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
        }
        return polyline
    }

    // MARK: - Actions

    func loadPlaces() async {
        isLoading = true
        defer { isLoading = false }

        guard let userId = authService.currentUserId else {
            importPendingPlacesForLocalUse()
            return
        }

        do {
            places = try await supabaseService.fetchPlaces(for: userId)
            try await importPendingPlaces(for: userId)
        } catch {
            print("MapViewModel: failed to load places: \(error)")
            importPendingPlacesForLocalUse()
        }
    }

    func importPendingPlacesForLocalUse() {
        let pending = pendingImportService.consumePendingPlaces()
        guard !pending.isEmpty else { return }

        let importedPlaces = pending.compactMap { pendingPlace -> Place? in
            let key = pendingPlace.deduplicationKey
            guard !importedPendingKeys.contains(key),
                  !places.contains(where: { $0.matches(pendingPlace) }) else {
                return nil
            }
            importedPendingKeys.insert(key)
            return Place.from(pendingPlace)
        }

        if !importedPlaces.isEmpty {
            places = importedPlaces + places
            revealImportedPlaces(importedPlaces)
        }

        pendingImportService.restorePendingPlaces(pending)
    }

    private func importPendingPlaces(for userId: String) async throws {
        let pending = pendingImportService.consumePendingPlaces()
        guard !pending.isEmpty else { return }

        var importedPlaces: [Place] = []
        var failedImports: [PendingSharedPlace] = []

        for pendingPlace in pending {
            let place = Place.from(pendingPlace)

            do {
                try await supabaseService.savePlace(place, userId: userId)
                importedPlaces.append(place)
            } catch {
                failedImports.append(pendingPlace)
                importedPlaces.append(place)
                print("MapViewModel: failed to import shared place \(pendingPlace.name): \(error)")
            }
        }

        if !importedPlaces.isEmpty {
            let newImports = importedPlaces.filter { place in
                let key = place.pendingDeduplicationKey
                guard !importedPendingKeys.contains(key),
                      !places.contains(where: { $0.matches(place) }) else {
                    return false
                }
                importedPendingKeys.insert(key)
                return true
            }
            places = newImports + places
            revealImportedPlaces(newImports)
        }
        pendingImportService.restorePendingPlaces(failedImports)
    }

    private func revealImportedPlaces(_ importedPlaces: [Place]) {
        guard let first = importedPlaces.first else { return }
        activeFilter = nil
        selectedCategories.removeAll()
        selectedPlace = first
        if first.latitude != 0 || first.longitude != 0 {
            cameraPosition = .region(MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            ))
        }
    }

    func selectPlace(_ place: Place) {
        selectedPlace = place
    }

    func focusOnUserLocationOnLaunch() async {
        guard !didRequestInitialLocation else { return }
        didRequestInitialLocation = true
        await focusOnUserLocation()
    }

    func focusOnUserLocation() async {
        guard !isLocatingUser else { return }
        isLocatingUser = true
        defer { isLocatingUser = false }

        guard let location = await locationService.requestCurrentLocation() else { return }

        cameraPosition = .region(MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        ))
    }

    func toggleCategory(_ category: PlaceCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    func saveImportedPlaces(_ drafts: [ImportedPlaceDraft]) async throws -> GoogleTakeoutSaveSummary {
        guard let userId = authService.currentUserId else {
            throw SupabaseError.notAuthenticated
        }

        let existingKeys = Set(places.map(\.importDeduplicationKey))
        var batchKeys: Set<String> = []
        var savedPlaces: [Place] = []
        var skippedDuplicates = 0
        var reviewDrafts = 0

        for draft in drafts {
            guard let place = draft.toPlace() else {
                reviewDrafts += 1
                continue
            }

            let key = draft.deduplicationKey
            guard !existingKeys.contains(key), !batchKeys.contains(key) else {
                skippedDuplicates += 1
                continue
            }

            try await supabaseService.savePlace(place, userId: userId)
            batchKeys.insert(key)
            savedPlaces.append(place)
        }

        if !savedPlaces.isEmpty {
            places = savedPlaces + places
        }

        return GoogleTakeoutSaveSummary(
            saved: savedPlaces.count,
            skippedDuplicates: skippedDuplicates,
            reviewDrafts: reviewDrafts
        )
    }

    // MARK: - Apply AI map action

    func apply(_ action: MapActionData) {
        switch action.type {
        case .filterPins:
            let ids = Set((action.placeIds ?? []).compactMap { UUID(uuidString: $0) })
            activeFilter = ids.isEmpty ? nil : ids

        case .focusRegion:
            guard let lat = action.lat, let lng = action.lng else { return }
            let span = action.span ?? 0.03
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            ))

        case .showRoute:
            let orderedIds = action.placeIds ?? []
            let idToPlace = Dictionary(uniqueKeysWithValues: places.map { ($0.id.uuidString, $0) })
            let routePlaces = orderedIds.compactMap { idToPlace[$0] }
            routeCoordinates = routePlaces.map { $0.coordinate }
            activeFilter = Set(routePlaces.map { $0.id })
            if let region = regionContaining(routePlaces) {
                cameraPosition = .region(region)
            }
            Task { await calculateRoute(for: routePlaces) }

        case .resetPins:
            activeFilter = nil
            routeCoordinates = []
            calculatedRoute = nil
        }
    }

    // MARK: - Route Calculation

    private func calculateRoute(for places: [Place]) async {
        guard places.count >= 2 else { return }
        calculatedRoute = nil

        var allCoordinates: [CLLocationCoordinate2D] = []

        // Calculate route segments between consecutive places
        for i in 0..<(places.count - 1) {
            let source = MKMapItem(placemark: MKPlacemark(coordinate: places[i].coordinate))
            let destination = MKMapItem(placemark: MKPlacemark(coordinate: places[i + 1].coordinate))

            let request = MKDirections.Request()
            request.source = source
            request.destination = destination
            request.transportType = .walking

            do {
                let directions = MKDirections(request: request)
                let response = try await directions.calculate()
                if let route = response.routes.first {
                    let points = route.polyline.points()
                    let count = route.polyline.pointCount
                    for j in 0..<count {
                        allCoordinates.append(points[j].coordinate)
                    }
                }
            } catch {
                print("Route calculation failed for segment \(i): \(error)")
                // Fallback: add straight line for this segment
                allCoordinates.append(places[i].coordinate)
                allCoordinates.append(places[i + 1].coordinate)
            }
        }

        guard allCoordinates.count >= 2 else { return }
        calculatedRoute = MKPolyline(coordinates: allCoordinates, count: allCoordinates.count)
    }

    // MARK: - Helpers

    private func regionContaining(_ places: [Place]) -> MKCoordinateRegion? {
        guard !places.isEmpty else { return nil }
        let lats = places.map { $0.latitude }
        let lngs = places.map { $0.longitude }
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.01),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.4, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

}
