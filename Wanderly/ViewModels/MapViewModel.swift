import Foundation
import MapKit
import SwiftUI

enum ReviewCandidateError: LocalizedError {
    case needsReliableCoordinates

    var errorDescription: String? {
        switch self {
        case .needsReliableCoordinates:
            return "This candidate needs Google Places refinement or a map link before it can be saved."
        }
    }
}

@MainActor
final class MapViewModel: ObservableObject {
    @Published var places: [Place] = []
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
    @Published var reviewCandidates: [PlaceReviewCandidate] = []

    private let supabaseService: SupabaseServiceProtocol
    private let authService: PrivyAuthService
    private let pendingImportService: PendingPlaceImportService
    private let locationService: LocationService
    private let googlePlacesService: GooglePlacesServiceProtocol
    private let socialLinkReviewCandidateService: SocialLinkReviewCandidateService
    private let saveLocalVaultService: SaveLocalVaultService
    private var importedPendingKeys: Set<String> = []
    private var didRequestInitialLocation = false

    init(
        supabaseService: SupabaseServiceProtocol = SupabaseService.shared,
        pendingImportService: PendingPlaceImportService = .shared,
        locationService: LocationService? = nil,
        googlePlacesService: GooglePlacesServiceProtocol = GooglePlacesService.shared,
        socialLinkReviewCandidateService: SocialLinkReviewCandidateService = .shared,
        saveLocalVaultService: SaveLocalVaultService = .shared
    ) {
        self.supabaseService = supabaseService
        self.authService = PrivyAuthService.shared
        self.pendingImportService = pendingImportService
        self.locationService = locationService ?? .shared
        self.googlePlacesService = googlePlacesService
        self.socialLinkReviewCandidateService = socialLinkReviewCandidateService
        self.saveLocalVaultService = saveLocalVaultService
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
            reviewCandidates = []
            return
        }

        do {
            places = try await supabaseService.fetchPlaces(for: userId)
            try await importPendingReviewCandidates(for: userId)
            do {
                try await refreshReviewCandidates()
            } catch {
                print("MapViewModel: failed to fetch review candidates: \(error)")
            }
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
                mirrorToLocalVault(place)
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

    private func importPendingReviewCandidates(for userId: String) async throws {
        let pending = pendingImportService.consumePendingReviewCandidates()
        guard !pending.isEmpty else { return }

        var failedCandidates: [PendingReviewCandidate] = []

        for candidate in pending {
            let refinedCandidate = await socialLinkReviewCandidateService.refineCandidate(candidate)
            mirrorToLocalVault(refinedCandidate)
            do {
                let captureId = try await supabaseService.createMemoryCapture(from: refinedCandidate, userId: userId)
                try await supabaseService.createPlaceCandidate(refinedCandidate, captureId: captureId, userId: userId)
            } catch {
                failedCandidates.append(candidate)
                print("MapViewModel: failed to import review candidate \(candidate.candidateName): \(error)")
            }
        }

        pendingImportService.restorePendingReviewCandidates(failedCandidates)
    }

    func refreshReviewCandidates() async throws {
        let candidates = try await supabaseService.fetchReviewCandidates()
        reviewCandidates = candidates.filter { candidate in
            candidate.status == "review" || candidate.status == "confirmed"
        }
    }

    func importURLAsReviewCandidates(_ url: URL) async throws -> Int {
        guard let userId = authService.currentUserId else {
            throw SupabaseError.notAuthenticated
        }

        try? saveLocalVaultService.saveSourceOnly(url: url)
        let candidates = try await socialLinkReviewCandidateService.reviewCandidates(from: url)
        for candidate in candidates {
            mirrorToLocalVault(candidate)
            let captureId = try await supabaseService.createMemoryCapture(from: candidate, userId: userId)
            try await supabaseService.createPlaceCandidate(candidate, captureId: captureId, userId: userId)
        }
        try await refreshReviewCandidates()
        return candidates.count
    }

    func confirmReviewCandidate(_ candidate: PlaceReviewCandidate) async throws {
        try await supabaseService.updatePlaceCandidateStatus(candidate.id, status: "confirmed", placeId: nil)
        updateLocalCandidate(candidate.id, status: "confirmed")
    }

    func rejectReviewCandidate(_ candidate: PlaceReviewCandidate) async throws {
        try await supabaseService.updatePlaceCandidateStatus(candidate.id, status: "rejected", placeId: nil)
        reviewCandidates.removeAll { $0.id == candidate.id }
    }

    func saveReviewCandidateAsPlace(_ candidate: PlaceReviewCandidate) async throws {
        guard let userId = authService.currentUserId else {
            throw SupabaseError.notAuthenticated
        }

        let refinedMatch = try await refinedMatchIfNeeded(for: candidate)
        let place = Place.from(candidate, refinedMatch: refinedMatch)

        guard place.latitude != 0 || place.longitude != 0 else {
            throw ReviewCandidateError.needsReliableCoordinates
        }

        try await supabaseService.savePlace(place, userId: userId)
        try await supabaseService.updatePlaceCandidateStatus(candidate.id, status: "saved", placeId: place.id)
        mirrorToLocalVault(place)
        places = [place] + places
        reviewCandidates.removeAll { $0.id == candidate.id }
        revealImportedPlaces([place])
    }

    private func refinedMatchIfNeeded(for candidate: PlaceReviewCandidate) async throws -> GooglePlaceMatch? {
        guard !candidate.hasReliableCoordinates else { return nil }

        let query = candidate.refinementQuery
        guard !query.isEmpty else {
            throw ReviewCandidateError.needsReliableCoordinates
        }

        guard let match = try await googlePlacesService.searchPlace(query: query, near: nil).first else {
            throw ReviewCandidateError.needsReliableCoordinates
        }
        return match
    }

    private func updateLocalCandidate(_ candidateId: UUID, status: String) {
        guard let index = reviewCandidates.firstIndex(where: { $0.id == candidateId }) else { return }
        reviewCandidates[index].status = status
    }

    private func mirrorToLocalVault(_ candidate: PendingReviewCandidate) {
        do {
            _ = try saveLocalVaultService.saveReviewCandidate(candidate)
        } catch {
            print("MapViewModel: failed to mirror pending candidate to local vault: \(error)")
        }
    }

    private func mirrorToLocalVault(_ candidate: PlaceReviewCandidate) {
        do {
            _ = try saveLocalVaultService.saveReviewCandidate(candidate)
        } catch {
            print("MapViewModel: failed to mirror review candidate to local vault: \(error)")
        }
    }

    private func mirrorToLocalVault(_ place: Place) {
        do {
            _ = try saveLocalVaultService.saveConfirmedPlace(place)
        } catch {
            print("MapViewModel: failed to mirror confirmed place to local vault: \(error)")
        }
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

    func deletePlace(_ place: Place) async throws {
        let previousPlaces = places
        places.removeAll { $0.id == place.id }
        if selectedPlace?.id == place.id {
            selectedPlace = nil
        }
        activeFilter?.remove(place.id)
        routeCoordinates.removeAll()
        calculatedRoute = nil

        do {
            try await supabaseService.deletePlace(place.id)
        } catch {
            places = previousPlaces
            selectedPlace = place
            throw error
        }
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
