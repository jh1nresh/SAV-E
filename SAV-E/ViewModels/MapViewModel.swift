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

protocol MapCandidateSearchServiceProtocol {
    func searchCandidates(
        near coordinate: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        excluding savedPlaces: [Place],
        categories: Set<PlaceCategory>
    ) async -> [SaveMapCandidate]

    func searchCandidates(
        matching query: String,
        near coordinate: CLLocationCoordinate2D?,
        span: MKCoordinateSpan?,
        excluding savedPlaces: [Place]
    ) async -> [SaveMapCandidate]
}

struct MapCandidateSearchService: MapCandidateSearchServiceProtocol {
    private struct SearchSeed {
        let query: String
        let category: PlaceCategory
    }

    private let categorySeeds: [PlaceCategory: [SearchSeed]] = [
        .cafe: [
            SearchSeed(query: "coffee", category: .cafe),
            SearchSeed(query: "cafe", category: .cafe),
            SearchSeed(query: "coffee shop", category: .cafe),
            SearchSeed(query: "bakery cafe", category: .cafe),
        ],
        .food: [
            SearchSeed(query: "restaurant", category: .food),
            SearchSeed(query: "food", category: .food),
            SearchSeed(query: "lunch dinner", category: .food),
            SearchSeed(query: "brunch", category: .food),
        ],
        .bar: [
            SearchSeed(query: "bar", category: .bar),
            SearchSeed(query: "cocktail bar", category: .bar),
            SearchSeed(query: "wine bar", category: .bar),
        ],
        .attraction: [
            SearchSeed(query: "museum", category: .attraction),
            SearchSeed(query: "park attraction", category: .attraction),
            SearchSeed(query: "things to do", category: .attraction),
        ],
        .stay: [
            SearchSeed(query: "hotel", category: .stay),
            SearchSeed(query: "lodging", category: .stay),
        ],
        .shopping: [
            SearchSeed(query: "shop", category: .shopping),
            SearchSeed(query: "shopping", category: .shopping),
            SearchSeed(query: "mall", category: .shopping),
        ],
    ]
    private let googlePlacesService: GooglePlacesServiceProtocol

    init(googlePlacesService: GooglePlacesServiceProtocol = GooglePlacesService.shared) {
        self.googlePlacesService = googlePlacesService
    }

    func searchCandidates(
        near coordinate: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        excluding savedPlaces: [Place],
        categories: Set<PlaceCategory> = []
    ) async -> [SaveMapCandidate] {
        let region = MKCoordinateRegion(center: coordinate, span: span)
        var candidates: [SaveMapCandidate] = []
        var seenKeys: Set<String> = []

        for seed in seeds(for: categories) {
            let googleResults = await googleSearch(seed: seed, near: coordinate)
            let appleResults = await search(seed: seed, region: region)
            let results = googleResults + appleResults
            for candidate in results where !isAlreadySaved(candidate, in: savedPlaces) && categoryAllowed(candidate, categories: categories) {
                let key = dedupeKey(for: candidate)
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                candidates.append(candidate)
            }
        }

        return Array(candidates.prefix(categories.isEmpty ? 48 : 60))
    }

    func searchCandidates(
        matching query: String,
        near coordinate: CLLocationCoordinate2D? = nil,
        span: MKCoordinateSpan? = nil,
        excluding savedPlaces: [Place]
    ) async -> [SaveMapCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let seed = SearchSeed(query: trimmed, category: PlaceCategory.inferred(from: trimmed))
        let googleResults = await googleSearch(seed: seed, near: coordinate)
        let appleResults: [SaveMapCandidate]
        if googleResults.isEmpty {
            let region = coordinate.map {
                MKCoordinateRegion(
                    center: $0,
                    span: span ?? MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                )
            }
            appleResults = await search(seed: seed, region: region)
        } else {
            appleResults = []
        }

        var candidates: [SaveMapCandidate] = []
        var seenKeys: Set<String> = []
        for candidate in googleResults + appleResults where !isAlreadySaved(candidate, in: savedPlaces) {
            let key = dedupeKey(for: candidate)
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            candidates.append(candidate)
        }
        return Array(candidates.prefix(12))
    }

    private func search(seed: SearchSeed, region: MKCoordinateRegion?) async -> [SaveMapCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = seed.query
        if let region {
            request.region = region
        }
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems
                .prefix(20)
                .compactMap { makeCandidate(from: $0, seed: seed, searchCenter: region?.center) }
        } catch {
            print("MapCandidateSearchService: failed to search \(seed.query): \(error)")
            return []
        }
    }

    private func googleSearch(seed: SearchSeed, near coordinate: CLLocationCoordinate2D?) async -> [SaveMapCandidate] {
        do {
            let matches = try await googlePlacesService.searchPlace(query: seed.query, near: coordinate)
            return matches.compactMap { makeCandidate(from: $0, seed: seed, searchCenter: coordinate) }
        } catch {
            return []
        }
    }

    private func makeCandidate(from item: MKMapItem, seed: SearchSeed, searchCenter: CLLocationCoordinate2D?) -> SaveMapCandidate? {
        let title = (item.name ?? item.placemark.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let coordinate = item.placemark.coordinate
        let subtitle = subtitle(for: item.placemark)
        var evidence = [
            "Apple Maps result",
            "Search: \(seed.query)"
        ]
        let distance = searchCenter.map { distanceMeters(from: $0, to: coordinate) }
        if let distance {
            evidence.append("Distance: \(distanceLabel(distance))")
        }
        if !subtitle.isEmpty {
            evidence.append("Address: \(subtitle)")
        }
        let poiCategory = item.pointOfInterestCategory?.rawValue
        if let pointOfInterestCategory = poiCategory {
            evidence.append("POI: \(pointOfInterestCategory)")
        }

        return SaveMapCandidate(
            title: title,
            subtitle: subtitle.isEmpty ? "Nearby unsaved place" : subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: PlaceCategory.inferredMapCategory(
                title: title,
                subtitle: subtitle,
                pointOfInterestCategory: poiCategory,
                fallback: seed.category
            ),
            sourceURL: appleMapsURL(title: title, coordinate: coordinate),
            sourcePlatform: .other,
            distanceMeters: distance,
            evidence: evidence
        )
    }

    private func makeCandidate(from match: GooglePlaceMatch, seed: SearchSeed, searchCenter: CLLocationCoordinate2D?) -> SaveMapCandidate {
        let coordinate = CLLocationCoordinate2D(latitude: match.latitude, longitude: match.longitude)
        let photoURL = match.photoReference.flatMap { googlePlacesService.photoURL(reference: $0, maxWidth: 900)?.absoluteString }
        var evidence = [
            "Google Places result",
            "Search: \(seed.query)"
        ]
        let distance = searchCenter.map { distanceMeters(from: $0, to: coordinate) }
        if let distance {
            evidence.append("Distance: \(distanceLabel(distance))")
        }
        if let rating = match.rating {
            evidence.append(String(format: "Google rating: %.1f", rating))
        }

        return SaveMapCandidate(
            id: match.id,
            title: match.name,
            subtitle: match.address.isEmpty ? "Nearby unsaved place" : match.address,
            latitude: match.latitude,
            longitude: match.longitude,
            category: PlaceCategory.from(googleTypes: match.types) ?? PlaceCategory.inferred(from: "\(match.name) \(match.address)", fallback: seed.category),
            rating: match.rating,
            reviewCount: match.reviewCount,
            sourceURL: googleMapsURL(title: match.name, placeID: match.id, coordinate: coordinate),
            sourcePlatform: .googleMaps,
            photoURL: photoURL,
            businessPhotoURLs: photoURL.map { [$0] },
            distanceMeters: distance,
            evidence: evidence
        )
    }

    private func subtitle(for placemark: MKPlacemark) -> String {
        var pieces: [String] = []
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !street.isEmpty {
            pieces.append(street)
        }
        if let locality = placemark.locality?.trimmedNonEmpty {
            pieces.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea?.trimmedNonEmpty {
            pieces.append(administrativeArea)
        }
        return pieces.joined(separator: ", ")
    }

    private func appleMapsURL(title: String, coordinate: CLLocationCoordinate2D) -> String? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: title),
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
        ]
        return components?.url?.absoluteString
    }

    private func googleMapsURL(title: String, placeID: String, coordinate: CLLocationCoordinate2D) -> String? {
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "\(title) \(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "query_place_id", value: placeID),
        ]
        return components?.url?.absoluteString
    }

    private func dedupeKey(for candidate: SaveMapCandidate) -> String {
        let normalizedTitle = candidate.title
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let lat = Int((candidate.latitude * 10_000).rounded())
        let lon = Int((candidate.longitude * 10_000).rounded())
        return "\(normalizedTitle)-\(lat)-\(lon)"
    }

    private func isAlreadySaved(_ candidate: SaveMapCandidate, in savedPlaces: [Place]) -> Bool {
        let candidateLocation = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        return savedPlaces.contains { place in
            let savedLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let sameNearbyPlace = candidateLocation.distance(from: savedLocation) < 80
            let sameName = place.name.localizedCaseInsensitiveCompare(candidate.title) == .orderedSame
            return sameNearbyPlace || sameName
        }
    }

    private func seeds(for categories: Set<PlaceCategory>) -> [SearchSeed] {
        if categories.isEmpty {
            return PlaceCategory.allCases.compactMap { categorySeeds[$0]?.first }
        }
        return categories.flatMap { categorySeeds[$0] ?? [] }
    }

    private func categoryAllowed(_ candidate: SaveMapCandidate, categories: Set<PlaceCategory>) -> Bool {
        guard !categories.isEmpty else { return true }
        guard let category = candidate.category else { return false }
        return categories.contains(category)
    }

    private func distanceMeters(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }

    private func distanceLabel(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km away", meters / 1_000)
        }
        return "\(Int(meters.rounded())) m away"
    }
}

private extension String {
    var trimmedForDraft: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class MapViewModel: ObservableObject {
    private static let pendingReviewImportBatchLimit = 4

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
    @Published var selectedReviewCandidate: PlaceReviewCandidate?
    @Published var mapCandidates: [SaveMapCandidate] = []
    @Published var selectedMapCandidate: SaveMapCandidate?
    @Published var selectedMapFeature: MapFeature?
    @Published var isLoadingMapCandidates = false
    @Published var collaborativeLists: [SaveCollaborativeList] = []
    @Published var socialLens: SaveSocialLens = .forYou
    @Published var socialPlaces: [Place] = []
    @Published var selectedSocialPlace: Place?

    private let supabaseService: SupabaseServiceProtocol
    private let authService: PrivyAuthService
    private let pendingImportService: PendingPlaceImportService
    private let locationService: LocationService
    private let googlePlacesService: GooglePlacesServiceProtocol
    private let socialLinkReviewCandidateService: SocialLinkReviewCandidateService
    private let saveLocalVaultService: SaveLocalVaultService
    private let mapCandidateSearchService: MapCandidateSearchServiceProtocol
    private let saveSearchController: SaveSearchController
    private let saveSearchIntentParser: SaveSearchIntentParser
    private let collaborativeListStore: SaveCollaborativeListStore
    private var importedPendingKeys: Set<String> = []
    private var didRequestInitialLocation = false
    private var isLoadingPlaces = false
    private var hasLoadedPlaces = false

    init(
        supabaseService: SupabaseServiceProtocol = SupabaseService.shared,
        pendingImportService: PendingPlaceImportService = .shared,
        locationService: LocationService? = nil,
        googlePlacesService: GooglePlacesServiceProtocol = GooglePlacesService.shared,
        socialLinkReviewCandidateService: SocialLinkReviewCandidateService = .shared,
        saveLocalVaultService: SaveLocalVaultService = .shared,
        mapCandidateSearchService: MapCandidateSearchServiceProtocol = MapCandidateSearchService(),
        saveSearchController: SaveSearchController = SaveSearchController(),
        saveSearchIntentParser: SaveSearchIntentParser = SaveSearchIntentParser(),
        collaborativeListStore: SaveCollaborativeListStore = .shared
    ) {
        self.supabaseService = supabaseService
        self.authService = PrivyAuthService.shared
        self.pendingImportService = pendingImportService
        self.locationService = locationService ?? .shared
        self.googlePlacesService = googlePlacesService
        self.socialLinkReviewCandidateService = socialLinkReviewCandidateService
        self.saveLocalVaultService = saveLocalVaultService
        self.mapCandidateSearchService = mapCandidateSearchService
        self.saveSearchController = saveSearchController
        self.saveSearchIntentParser = saveSearchIntentParser
        self.collaborativeListStore = collaborativeListStore
        self.collaborativeLists = collaborativeListStore.load()
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

    var reviewCandidatesOnMap: [PlaceReviewCandidate] {
        reviewCandidates.filter(\.hasReliableCoordinates)
    }

    var visibleMapCandidates: [SaveMapCandidate] {
        guard !selectedCategories.isEmpty else { return mapCandidates }
        return mapCandidates.filter { candidate in
            guard let category = candidate.category else { return false }
            return selectedCategories.contains(category)
        }
    }

    var visibleSocialPlaces: [Place] {
        var result = socialPlaces.filter { place in
            guard let signal = place.socialSignal else { return false }
            return socialLens == .forYou || signal.lens == socialLens
        }
        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.category) }
        }
        return result
    }

    // MARK: - Actions

    func loadPlaces(force: Bool = false) async {
        guard !isLoadingPlaces else { return }
        guard force || !hasLoadedPlaces else { return }

        isLoadingPlaces = true
        isLoading = true
        defer {
            isLoadingPlaces = false
            isLoading = false
            hasLoadedPlaces = true
        }

        guard let userId = authService.currentUserId else {
            places = mergeRemotePlaces([], withLocalPlaces: localConfirmedPlaces())
            importPendingPlacesForLocalUse()
            reviewCandidates = []
            socialPlaces = []
            return
        }

        do {
            let remotePlaces = try await supabaseService.fetchPlaces(for: userId)
            places = mergeRemotePlaces(remotePlaces, withLocalPlaces: localConfirmedPlaces())
            await completeReferralHandoffIfNeeded()
            try await importPendingReviewCandidates(for: userId, runSourceRecovery: false)
            do {
                try await refreshReviewCandidates()
            } catch {
                print("MapViewModel: failed to fetch review candidates: \(error)")
            }
            try await importPendingPlaces(for: userId)
            await refreshSocialSignals()
        } catch {
            print("MapViewModel: failed to load places: \(error)")
            if places.isEmpty {
                places = localConfirmedPlaces()
            }
            importPendingPlacesForLocalUse()
            await refreshSocialSignals()
        }
    }

    func handleSceneDidBecomeActive() async {
        guard hasLoadedPlaces else {
            await loadPlaces()
            return
        }
        guard !isLoadingPlaces else { return }

        guard let userId = authService.currentUserId else {
            importPendingPlacesForLocalUse()
            socialPlaces = []
            return
        }

        isLoadingPlaces = true
        defer { isLoadingPlaces = false }

        do {
            await completeReferralHandoffIfNeeded()
            try await importPendingReviewCandidates(for: userId, runSourceRecovery: false)
            try await importPendingPlaces(for: userId)
            try await refreshReviewCandidates()
            await refreshSocialSignals()
        } catch {
            print("MapViewModel: failed to process scene activation imports: \(error)")
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

    private func localConfirmedPlaces() -> [Place] {
        do {
            return try saveLocalVaultService.confirmedPlaces(limit: 500)
        } catch {
            print("MapViewModel: failed to load local confirmed places: \(error)")
            return []
        }
    }

    private func mergeRemotePlaces(_ remotePlaces: [Place], withLocalPlaces localPlaces: [Place]) -> [Place] {
        guard !localPlaces.isEmpty else { return remotePlaces }
        var merged = remotePlaces
        for localPlace in localPlaces where !merged.contains(where: { $0.id == localPlace.id || $0.matches(localPlace) }) {
            merged.append(localPlace)
        }
        return merged.sorted { $0.createdAt > $1.createdAt }
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

    private func importPendingReviewCandidates(for userId: String, runSourceRecovery: Bool) async throws {
        let pending = pendingImportService.consumePendingReviewCandidates()
        guard !pending.isEmpty else { return }

        let currentBatch = Array(pending.prefix(Self.pendingReviewImportBatchLimit))
        var failedCandidates = Array(pending.dropFirst(Self.pendingReviewImportBatchLimit))

        for candidate in currentBatch {
            let refinedCandidate = await socialLinkReviewCandidateService.refineCandidate(candidate)
            mirrorToLocalVault(refinedCandidate)
            do {
                let captureId = try await supabaseService.createMemoryCapture(from: refinedCandidate, userId: userId)
                try await supabaseService.createPlaceCandidate(refinedCandidate, captureId: captureId, userId: userId)
                if runSourceRecovery && refinedCandidate.isSourceOnly {
                    _ = try? await supabaseService.recoverSourceOnlyReviewCandidates(captureId: captureId)
                }
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

        _ = try? saveLocalVaultService.saveSourceOnly(url: url)
        let candidates = try await socialLinkReviewCandidateService.reviewCandidates(from: url)
        var importedCount = candidates.count
        for candidate in candidates {
            mirrorToLocalVault(candidate)
            let captureId = try await supabaseService.createMemoryCapture(from: candidate, userId: userId)
            try await supabaseService.createPlaceCandidate(candidate, captureId: captureId, userId: userId)
            if candidate.isSourceOnly {
                let recovered = try? await supabaseService.recoverSourceOnlyReviewCandidates(captureId: captureId)
                importedCount += recovered?.count ?? 0
            }
        }
        try await refreshReviewCandidates()
        return importedCount
    }

    func confirmReviewCandidate(_ candidate: PlaceReviewCandidate) async throws {
        try await supabaseService.updatePlaceCandidateStatus(candidate.id, status: "confirmed", placeId: nil)
        updateLocalCandidate(candidate.id, status: "confirmed")
    }

    func rejectReviewCandidate(_ candidate: PlaceReviewCandidate) async throws {
        try await supabaseService.updatePlaceCandidateStatus(candidate.id, status: "rejected", placeId: nil)
        reviewCandidates.removeAll { $0.id == candidate.id }
        if selectedReviewCandidate?.id == candidate.id {
            selectedReviewCandidate = nil
        }
    }

    func saveReviewCandidateAsPlace(_ candidate: PlaceReviewCandidate, nameOverride: String? = nil) async throws {
        guard let userId = authService.currentUserId else {
            throw SupabaseError.notAuthenticated
        }

        let refinedMatch = try await refinedMatchIfNeeded(for: candidate)
        let place = Place.from(candidate, refinedMatch: refinedMatch, nameOverride: nameOverride)

        guard place.latitude != 0 || place.longitude != 0 else {
            throw ReviewCandidateError.needsReliableCoordinates
        }

        try await supabaseService.savePlace(place, userId: userId)
        try await supabaseService.updatePlaceCandidateStatus(candidate.id, status: "saved", placeId: place.id)
        mirrorToLocalVault(place)
        places = [place] + places
        reviewCandidates.removeAll { $0.id == candidate.id }
        if selectedReviewCandidate?.id == candidate.id {
            selectedReviewCandidate = nil
        }
        revealImportedPlaces([place])
    }

    func saveMapCandidateAsPlace(_ candidate: SaveMapCandidate) async throws {
        let draft = SavePlaceDraft(
            title: candidate.title,
            address: candidate.subtitle.trimmedForDraft,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            category: candidate.category,
            sourceURL: candidate.sourceURL,
            sourcePlatform: candidate.sourcePlatform,
            evidence: candidate.evidence,
            externalRating: candidate.rating,
            externalReviewCount: candidate.reviewCount
        )
        var place = try await saveSearchController.saveMapCandidate(draft)
        place.sourceImageUrl = candidate.photoURL
        place.businessPhotoUrls = candidate.businessPhotoURLStrings

        if let userId = authService.currentUserId {
            do {
                try await supabaseService.savePlace(place, userId: userId)
            } catch {
                print("MapViewModel: failed to sync saved map candidate \(place.name): \(error)")
            }
        }

        mirrorToLocalVault(place)
        if !places.contains(where: { $0.matches(place) }) {
            places = [place] + places
        }
        mapCandidates.removeAll { $0.id == candidate.id }
        selectedMapCandidate = nil
        revealImportedPlaces([place])
    }

    @discardableResult
    func saveSocialPlaceToMySave(_ socialPlace: Place) async throws -> Place {
        if let existing = places.first(where: { place in
            place.matchesMapFeature(title: socialPlace.name, coordinate: socialPlace.coordinate) ||
                place.name.localizedCaseInsensitiveCompare(socialPlace.name) == .orderedSame
        }) {
            selectedPlace = existing
            selectedSocialPlace = nil
            return existing
        }

        let place = Place(
            id: UUID(),
            name: socialPlace.name,
            address: socialPlace.address,
            latitude: socialPlace.latitude,
            longitude: socialPlace.longitude,
            googlePlaceId: socialPlace.googlePlaceId,
            category: socialPlace.category,
            status: .wantToGo,
            rating: socialPlace.rating,
            note: socialPlace.note,
            sourceUrl: socialPlace.sourceUrl,
            sourcePlatform: socialPlace.sourcePlatform,
            sourceImageUrl: socialPlace.sourceImageUrl,
            businessPhotoUrls: socialPlace.businessPhotoUrls,
            extractedDishes: socialPlace.extractedDishes,
            priceRange: socialPlace.priceRange,
            recommender: socialPlace.socialSignal?.sourceLabel ?? socialPlace.recommender,
            googleRating: socialPlace.googleRating,
            googlePriceLevel: socialPlace.googlePriceLevel,
            openingHours: socialPlace.openingHours,
            createdAt: Date(),
            visibility: .privateMemory,
            socialSignal: nil
        )

        if let userId = authService.currentUserId {
            do {
                try await supabaseService.savePlace(place, userId: userId)
            } catch {
                print("MapViewModel: failed to sync social place \(place.name): \(error)")
            }
        }

        mirrorToLocalVault(place)
        places = [place] + places
        socialPlaces.removeAll { $0.id == socialPlace.id }
        selectedSocialPlace = nil
        revealImportedPlaces([place])
        return place
    }

    @discardableResult
    func createCollaborativeList(title: String, note: String?) -> SaveCollaborativeList {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = SaveCollaborativeList(
            title: trimmedTitle.isEmpty ? "Untitled SAV-E list" : trimmedTitle,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedForDraft
        )
        collaborativeLists.insert(list, at: 0)
        persistCollaborativeLists()
        return list
    }

    func addPlace(_ place: Place, toListID listID: UUID) throws {
        try updateCollaborativeList(listID) { list in
            list.add(.from(place: place))
        }
    }

    func shareURL(for list: SaveCollaborativeList, role: SaveListRole) -> URL? {
        collaborativeLists.first(where: { $0.id == list.id })?.shareURL(role: role) ?? list.shareURL(role: role)
    }

    @discardableResult
    func joinCollaborativeList(from url: URL) throws -> SaveCollaborativeList {
        let list = try collaborativeListStore.join(from: url)
        reloadCollaborativeLists()
        return list
    }

    func reloadCollaborativeLists() {
        collaborativeLists = collaborativeListStore.load()
    }

    func selectSocialLens(_ lens: SaveSocialLens) {
        socialLens = lens
        if selectedSocialPlace?.socialSignal?.lens != lens {
            selectedSocialPlace = nil
        }
        Task { await refreshSocialSignals() }
    }

    @discardableResult
    func saveListItemAsPlace(_ item: SaveListItem) async throws -> Place {
        if let existing = places.first(where: { place in
            place.matchesMapFeature(title: item.title, coordinate: item.coordinate) ||
                place.name.localizedCaseInsensitiveCompare(item.title) == .orderedSame
        }) {
            selectPlace(existing)
            return existing
        }

        let place = item.asPlace()
        if let userId = authService.currentUserId {
            do {
                try await supabaseService.savePlace(place, userId: userId)
            } catch {
                print("MapViewModel: failed to sync list item \(place.name): \(error)")
            }
        }

        mirrorToLocalVault(place)
        places = [place] + places
        revealImportedPlaces([place])
        return place
    }

    func planCollaborativeList(_ list: SaveCollaborativeList) async {
        let routePlaces = list.items
            .filter(\.isMappable)
            .map { $0.asPlace(createdAt: $0.addedAt) }
        guard !routePlaces.isEmpty else { return }

        routeCoordinates = routePlaces.map(\.coordinate)
        calculatedRoute = nil

        let savedIDs = list.items.compactMap { item -> UUID? in
            guard item.source == .savedPlace else { return nil }
            return UUID(uuidString: item.sourceID)
        }
        activeFilter = savedIDs.isEmpty ? nil : Set(savedIDs)

        if let region = regionContaining(routePlaces) {
            cameraPosition = .region(region)
        }
        await calculateRoute(for: routePlaces)
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
        if selectedReviewCandidate?.id == candidateId {
            selectedReviewCandidate = reviewCandidates[index]
        }
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

    private func updateCollaborativeList(
        _ listID: UUID,
        update: (inout SaveCollaborativeList) -> Void
    ) throws {
        guard let index = collaborativeLists.firstIndex(where: { $0.id == listID }) else {
            throw SaveCollaborativeListError.listNotFound
        }
        guard collaborativeLists[index].canEdit else {
            throw SaveCollaborativeListError.viewerCannotEdit
        }
        update(&collaborativeLists[index])
        collaborativeLists.sort { $0.updatedAt > $1.updatedAt }
        persistCollaborativeLists()
    }

    private func persistCollaborativeLists() {
        collaborativeListStore.save(collaborativeLists)
    }

    private func revealImportedPlaces(_ importedPlaces: [Place]) {
        guard let first = importedPlaces.first else { return }
        activeFilter = nil
        selectedCategories.removeAll()
        selectedPlace = first
        selectedSocialPlace = nil
        selectedMapCandidate = nil
        if first.latitude != 0 || first.longitude != 0 {
            cameraPosition = .region(MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            ))
        }
    }

    private func completeReferralHandoffIfNeeded() async {
        guard let handoff = SaveReferralHandoffStore.shared.load(),
              authService.currentUserId != nil
        else { return }

        do {
            try await supabaseService.followProfile(
                referralCode: handoff.referralCode,
                lens: handoff.lens,
                source: .appClipHandoff
            )
            SaveReferralHandoffStore.shared.clear()
            socialLens = handoff.lens
        } catch {
            print("MapViewModel: failed to complete referral follow: \(error)")
        }
    }

    func followReferral(_ rawValue: String) async throws {
        guard authService.currentUserId != nil else {
            throw SupabaseError.notAuthenticated
        }
        guard let target = SaveReferralLink.target(from: rawValue), target.isValid else {
            throw SupabaseError.recordNotFound
        }

        try await supabaseService.followProfile(target: target, source: .manual)
        socialLens = target.lens
        await refreshSocialSignals()
    }

    private func refreshSocialSignals() async {
        guard authService.currentUserId != nil else {
            socialPlaces = []
            return
        }

        do {
            let signals = try await supabaseService.fetchSocialSignals(lens: socialLens)
            socialPlaces = signals.filter { seed in
                !places.contains { saved in
                    saved.matchesMapFeature(title: seed.name, coordinate: seed.coordinate) ||
                        saved.name.localizedCaseInsensitiveCompare(seed.name) == .orderedSame
                }
            }
        } catch {
            print("MapViewModel: failed to refresh social signals: \(error)")
            socialPlaces = socialPlaces.filter { seed in
                !places.contains { saved in
                    saved.matchesMapFeature(title: seed.name, coordinate: seed.coordinate) ||
                        saved.name.localizedCaseInsensitiveCompare(seed.name) == .orderedSame
                }
            }
        }
    }

    func refreshMapCandidates(
        near coordinate: CLLocationCoordinate2D? = nil,
        span: MKCoordinateSpan? = nil,
        categories: Set<PlaceCategory> = []
    ) async {
        guard !isLoadingMapCandidates else { return }
        let searchCenter = coordinate ?? mapCandidateSearchCenter()
        let searchSpan = span ?? MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
        isLoadingMapCandidates = true
        defer { isLoadingMapCandidates = false }

        let candidates = await mapCandidateSearchService.searchCandidates(
            near: searchCenter,
            span: searchSpan,
            excluding: places,
            categories: categories
        )
        mapCandidates = candidates
        if let selectedMapCandidate, !candidates.contains(where: { $0.id == selectedMapCandidate.id }) {
            self.selectedMapCandidate = nil
        }
    }

    func prepareMapCandidatesForDrawerQuery(_ query: String) async -> [SaveMapCandidate] {
        guard saveSearchController.shouldPrepareMapCandidates(for: query) else { return mapCandidates }
        if let exactQuery = saveSearchController.exactMapCandidateQuery(for: query) {
            let candidates = await mapCandidateSearchService.searchCandidates(
                matching: exactQuery,
                near: nil,
                span: nil,
                excluding: places
            )
            mapCandidates = candidates
            selectedMapCandidate = candidates.first
            return candidates
        }

        let searchCenter: CLLocationCoordinate2D?
        let shouldUseCurrentLocation = saveSearchIntentParser.parse(query)?.mustMatchLocation == true ||
            !saveSearchController.mapCandidateCategories(for: query).isEmpty
        if shouldUseCurrentLocation {
            guard let currentLocationCenter = await currentLocationSearchCenter() else {
                mapCandidates = []
                return []
            }
            searchCenter = currentLocationCenter
        } else {
            searchCenter = nil
        }
        if let specialtyQuery = saveSearchController.specialtyMapCandidateQuery(for: query) {
            let candidates = await mapCandidateSearchService.searchCandidates(
                matching: specialtyQuery,
                near: searchCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06),
                excluding: places
            )
            mapCandidates = candidates
            selectedMapCandidate = candidates.first
            return candidates
        }
        let categories = saveSearchController.mapCandidateCategories(for: query)
        if !categories.isEmpty {
            selectedCategories = categories
            activeFilter = nil
        }
        await refreshMapCandidates(
            near: searchCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06),
            categories: categories
        )
        if !categories.isEmpty {
            mapCandidates = mapCandidates.filter { candidate in
                guard let category = candidate.category else { return false }
                return categories.contains(category)
            }
        }
        return mapCandidates
    }

    private func currentLocationSearchCenter() async -> CLLocationCoordinate2D? {
        let currentLocation = await locationService.requestCurrentLocation()
        return currentLocation?.coordinate
    }

    private func mapCandidateSearchCenter() -> CLLocationCoordinate2D {
        if let selectedPlace, selectedPlace.latitude != 0 || selectedPlace.longitude != 0 {
            return selectedPlace.coordinate
        }
        if let firstPlace = places.first(where: { $0.latitude != 0 || $0.longitude != 0 }) {
            return firstPlace.coordinate
        }
        return CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    }

    func selectPlace(_ place: Place) {
        selectedPlace = place
        selectedReviewCandidate = nil
        selectedMapCandidate = nil
        selectedSocialPlace = nil
        selectedMapFeature = nil
        guard place.businessPhotoURLStrings.count < 2 || place.googleRating == nil || place.priceRange == nil || place.openingHours == nil else { return }
        Task {
            await enrichSelectedPlacePhoto(place)
        }
    }

    private func enrichSelectedPlacePhoto(_ place: Place) async {
        guard let update = await businessDetails(for: place) else { return }
        guard selectedPlace?.id == place.id else { return }

        var updatedPlace = place
        if !update.photoURLs.isEmpty {
            let urls = update.photoURLs.map(\.absoluteString)
            updatedPlace.sourceImageUrl = updatedPlace.sourceImageUrl ?? urls.first
            updatedPlace.businessPhotoUrls = urls
        }
        updatedPlace.googleRating = updatedPlace.googleRating ?? update.rating
        updatedPlace.priceRange = updatedPlace.priceRange ?? update.priceRange
        updatedPlace.openingHours = updatedPlace.openingHours ?? update.openingHours
        selectedPlace = updatedPlace
        if let index = places.firstIndex(where: { $0.id == place.id }) {
            places[index] = updatedPlace
        }
        mirrorToLocalVault(updatedPlace)

        if let userId = authService.currentUserId {
            do {
                try await supabaseService.savePlace(updatedPlace, userId: userId)
            } catch {
                print("MapViewModel: failed to sync business photo for \(place.name): \(error)")
            }
        }
    }

    private func businessDetails(for place: Place) async -> (photoURLs: [URL], rating: Double?, priceRange: String?, openingHours: String?)? {
        let details: GooglePlaceDetails?
        let fallbackMatch: GooglePlaceMatch?
        if let googlePlaceId = place.googlePlaceId {
            details = try? await googlePlacesService.getPlaceDetails(placeId: googlePlaceId)
            fallbackMatch = nil
        } else {
            guard let match = await bestGoogleMatch(for: place) else { return nil }
            details = try? await googlePlacesService.getPlaceDetails(placeId: match.id)
            fallbackMatch = match
        }

        let photoReferences = details?.photoReferences?.isEmpty == false
            ? details?.photoReferences ?? []
            : [fallbackMatch?.photoReference].compactMap { $0 }
        let photoURLs = photoReferences
            .prefix(6)
            .compactMap { googlePlacesService.photoURL(reference: $0, maxWidth: 900) }
        let priceLevel = details?.priceLevel ?? fallbackMatch?.priceLevel
        let hasDetails = !photoURLs.isEmpty || details?.rating != nil || fallbackMatch?.rating != nil || priceLevel != nil || details?.openingHours?.isEmpty == false
        guard hasDetails else { return nil }

        return (
            photoURLs,
            details?.rating ?? fallbackMatch?.rating,
            priceLevel.map { String(repeating: "$", count: max(1, $0)) },
            details?.openingHours?.first
        )
    }

    private func bestGoogleMatch(for place: Place) async -> GooglePlaceMatch? {
        for query in googleMatchQueries(for: place) {
            do {
                let matches = try await googlePlacesService.searchPlace(
                    query: query,
                    near: place.coordinate
                )
                let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                if let match = matches.first(where: { match in
                    let matchLocation = CLLocation(latitude: match.latitude, longitude: match.longitude)
                    let sameArea = placeLocation.distance(from: matchLocation) < 250
                    let sameName = match.name.localizedCaseInsensitiveContains(place.name) ||
                        place.name.localizedCaseInsensitiveContains(match.name) ||
                        match.name.localizedCaseInsensitiveContains(place.businessLookupName) ||
                        place.businessLookupName.localizedCaseInsensitiveContains(match.name)
                    return sameArea || sameName
                }) {
                    return match
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func googleMatchQueries(for place: Place) -> [String] {
        var seen: Set<String> = []
        return [
            "\(place.name) \(place.address)",
            "\(place.businessLookupName) \(place.address)",
            place.businessLookupName,
            place.address,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
    }

    func selectReviewCandidate(_ candidate: PlaceReviewCandidate) {
        selectedReviewCandidate = candidate
        selectedPlace = nil
        selectedMapCandidate = nil
        selectedSocialPlace = nil
        selectedMapFeature = nil
    }

    func selectMapCandidate(_ candidate: SaveMapCandidate) {
        selectedMapCandidate = candidate
        selectedPlace = nil
        selectedReviewCandidate = nil
        selectedSocialPlace = nil
        selectedMapFeature = nil
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: candidate.latitude, longitude: candidate.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        enrichSelectedMapCandidateAfterSelection(candidate)
    }

    func selectSocialPlace(_ place: Place) {
        selectedSocialPlace = place
        selectedPlace = nil
        selectedReviewCandidate = nil
        selectedMapCandidate = nil
        selectedMapFeature = nil
        cameraPosition = .region(MKCoordinateRegion(
            center: place.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    func clearSelectedMapObject() {
        selectedPlace = nil
        selectedReviewCandidate = nil
        selectedMapCandidate = nil
        selectedSocialPlace = nil
        selectedMapFeature = nil
    }

    func clearMapSearchResults() {
        mapCandidates = []
        selectedMapCandidate = nil
        selectedMapFeature = nil
        selectedCategories = []
        activeFilter = nil
        routeCoordinates = []
        calculatedRoute = nil
    }

    func selectMapFeature(_ feature: MapFeature?) {
        guard let feature else { return }
        guard feature.kind == .pointOfInterest else {
            selectedMapFeature = nil
            return
        }
        selectMapPOI(
            title: feature.title,
            coordinate: feature.coordinate,
            pointOfInterestCategory: feature.pointOfInterestCategory?.rawValue
        )
    }

    func selectMapPOI(
        title rawTitle: String?,
        coordinate: CLLocationCoordinate2D,
        pointOfInterestCategory: String?
    ) {
        let title = (rawTitle ?? "Map place").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            selectedMapFeature = nil
            return
        }

        if let savedPlace = places.first(where: { $0.matchesMapFeature(title: title, coordinate: coordinate) }) {
            selectSavedPlaceFromMapFeature(savedPlace)
            return
        }

        var evidence = ["Apple Maps POI"]
        if let pointOfInterestCategory {
            evidence.append("POI: \(pointOfInterestCategory)")
        }

        let candidate = SaveMapCandidate(
            title: title,
            subtitle: "Selected on map",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: PlaceCategory.inferredMapCategory(
                title: title,
                subtitle: "Selected on map",
                pointOfInterestCategory: pointOfInterestCategory,
                fallback: .attraction
            ),
            sourceURL: appleMapsURL(title: title, coordinate: coordinate),
            sourcePlatform: .other,
            evidence: evidence
        )

        selectedMapCandidate = candidate
        selectedPlace = nil
        selectedReviewCandidate = nil
        selectedSocialPlace = nil
        enrichSelectedMapCandidateAfterSelection(candidate)
    }

    private func selectSavedPlaceFromMapFeature(_ place: Place) {
        selectedPlace = place
        selectedReviewCandidate = nil
        selectedMapCandidate = nil
        selectedSocialPlace = nil
        guard place.businessPhotoURLStrings.count < 2 || place.googleRating == nil || place.priceRange == nil || place.openingHours == nil else { return }
        Task {
            await enrichSelectedPlacePhoto(place)
        }
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

    func updatePlaceVisibility(_ place: Place, visibility: PlaceVisibility) async throws {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        let previousPlace = places[index]

        places[index].visibility = visibility
        if selectedPlace?.id == place.id {
            selectedPlace = places[index]
        }

        do {
            try await supabaseService.updatePlaceVisibility(visibility, for: place.id)
            await refreshSocialSignals()
        } catch {
            places[index] = previousPlace
            if selectedPlace?.id == place.id {
                selectedPlace = previousPlace
            }
            throw error
        }
    }

    func updatePlace(_ place: Place) async throws {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        let previousPlace = places[index]

        places[index] = place
        if selectedPlace?.id == place.id {
            selectedPlace = place
        }

        do {
            try await supabaseService.updatePlace(place)
            mirrorToLocalVault(place)
        } catch {
            places[index] = previousPlace
            if selectedPlace?.id == place.id {
                selectedPlace = previousPlace
            }
            throw error
        }
    }

    private func hydrateSelectedMapCandidateDistance(_ candidate: SaveMapCandidate) async {
        guard candidate.distanceMeters == nil else { return }
        guard selectedMapCandidate?.id == candidate.id else { return }
        guard let center = await currentLocationSearchCenter() else { return }

        var updatedCandidate = selectedMapCandidate ?? candidate
        let coordinate = CLLocationCoordinate2D(latitude: updatedCandidate.latitude, longitude: updatedCandidate.longitude)
        let distance = CLLocation(latitude: center.latitude, longitude: center.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        updatedCandidate.distanceMeters = distance
        if !updatedCandidate.evidence.contains(where: { $0.localizedCaseInsensitiveContains("Distance:") }) {
            updatedCandidate.evidence.append("Distance: \(mapCandidateDistanceLabel(distance))")
        }

        selectedMapCandidate = updatedCandidate
        if let index = mapCandidates.firstIndex(where: { $0.id == updatedCandidate.id }) {
            mapCandidates[index] = updatedCandidate
        }
    }

    private func mapCandidateDistanceLabel(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km away", meters / 1_000)
        }
        return "\(Int(meters.rounded())) m away"
    }

    private func enrichSelectedMapCandidateAfterSelection(_ candidate: SaveMapCandidate) {
        Task {
            await hydrateSelectedMapCandidateDistance(candidate)
            await enrichSelectedMapCandidate(candidate)
        }
    }

    private func enrichSelectedMapCandidate(_ candidate: SaveMapCandidate) async {
        guard let update = await businessDetails(for: candidate) else { return }
        guard selectedMapCandidate?.id == candidate.id else { return }

        var updatedCandidate = selectedMapCandidate ?? candidate
        if !update.photoURLs.isEmpty {
            let urls = update.photoURLs.map(\.absoluteString)
            updatedCandidate.photoURL = updatedCandidate.photoURL ?? urls.first
            updatedCandidate.businessPhotoURLs = urls
        }
        updatedCandidate.rating = updatedCandidate.rating ?? update.rating
        updatedCandidate.reviewCount = updatedCandidate.reviewCount ?? update.reviewCount
        if let category = update.category {
            updatedCandidate.category = category
        }
        if let priceRange = update.priceRange,
           !updatedCandidate.evidence.contains(where: { $0.localizedCaseInsensitiveContains("Price:") }) {
            updatedCandidate.evidence.append("Price: \(priceRange)")
        }
        if let openingHours = update.openingHours,
           !updatedCandidate.evidence.contains(where: { $0.localizedCaseInsensitiveContains("Hours:") }) {
            updatedCandidate.evidence.append("Hours: \(openingHours)")
        }

        selectedMapCandidate = updatedCandidate
        if let index = mapCandidates.firstIndex(where: { $0.id == candidate.id }) {
            mapCandidates[index] = updatedCandidate
        }
    }

    private func businessDetails(for candidate: SaveMapCandidate) async -> (photoURLs: [URL], rating: Double?, reviewCount: Int?, priceRange: String?, openingHours: String?, category: PlaceCategory?)? {
        do {
            let coordinate = CLLocationCoordinate2D(latitude: candidate.latitude, longitude: candidate.longitude)
            let matches = try await googlePlacesService.searchPlace(query: "\(candidate.title) \(candidate.subtitle)", near: coordinate)
            let candidateLocation = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
            guard let match = matches.first(where: { match in
                let matchLocation = CLLocation(latitude: match.latitude, longitude: match.longitude)
                let sameArea = candidateLocation.distance(from: matchLocation) < 250
                let sameName = match.name.localizedCaseInsensitiveContains(candidate.title) ||
                    candidate.title.localizedCaseInsensitiveContains(match.name)
                return sameArea || sameName
            }) else { return nil }

            let details = try? await googlePlacesService.getPlaceDetails(placeId: match.id)
            let photoReferences = details?.photoReferences?.isEmpty == false
                ? details?.photoReferences ?? []
                : [match.photoReference].compactMap { $0 }
            let photoURLs = photoReferences
                .prefix(6)
                .compactMap { googlePlacesService.photoURL(reference: $0, maxWidth: 900) }
            let priceLevel = details?.priceLevel ?? match.priceLevel
            let hasDetails = !photoURLs.isEmpty || details?.rating != nil || match.rating != nil || match.reviewCount != nil || priceLevel != nil || details?.openingHours?.isEmpty == false
            guard hasDetails else { return nil }

            return (
                photoURLs,
                details?.rating ?? match.rating,
                match.reviewCount,
                priceLevel.map { String(repeating: "$", count: max(1, $0)) },
                details?.openingHours?.first,
                PlaceCategory.from(googleTypes: details?.types ?? match.types)
            )
        } catch {
            return nil
        }
    }

    private func appleMapsURL(title: String, coordinate: CLLocationCoordinate2D) -> String? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: title),
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
        ]
        return components?.url?.absoluteString
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
            if let candidate = mapCandidate(nearLatitude: lat, longitude: lng) {
                selectMapCandidate(candidate)
            }
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

    private func mapCandidate(nearLatitude latitude: Double, longitude: Double) -> SaveMapCandidate? {
        let target = CLLocation(latitude: latitude, longitude: longitude)
        guard let nearest = mapCandidates.min(by: { lhs, rhs in
            let lhsDistance = target.distance(from: CLLocation(latitude: lhs.latitude, longitude: lhs.longitude))
            let rhsDistance = target.distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
            return lhsDistance < rhsDistance
        }) else { return nil }

        let distance = target.distance(from: CLLocation(latitude: nearest.latitude, longitude: nearest.longitude))
        return distance < 80 ? nearest : nil
    }

}
