import Foundation
import CoreLocation

enum PlaceFilter: String, CaseIterable {
    case all = "All"
    case wantToGo = "Want to Go"
    case visited = "Visited"
}

enum PlaceSort: String, CaseIterable {
    case recent = "Recent"
    case nearest = "Nearest"
    case rating = "Rating"
}

@MainActor
final class PlaceListViewModel: ObservableObject {
    private static let pendingReviewImportBatchLimit = 4

    @Published var places: [Place] = Place.mockList
    @Published var filter: PlaceFilter = .all
    @Published var sort: PlaceSort = .recent
    @Published var selectedCategories: Set<PlaceCategory> = []
    @Published var searchText: String = ""
    @Published var isLoading = false
    @Published var deleteError: String?
    @Published var saveCandidateError: String?
    @Published var planAroundResult: SavePlanAroundResult?
    @Published private(set) var savingResultID: String?
    @Published private(set) var mapCandidates: [SaveMapCandidate] = []
    @Published private(set) var localMemoryRecords: [SaveMemoryRecord] = []

    private let supabaseService: SupabaseServiceProtocol
    private let authService: PrivyAuthService
    private let pendingImportService: PendingPlaceImportService
    private let saveLocalVaultService: SaveLocalVaultService
    private let socialLinkReviewCandidateService: SocialLinkReviewCandidateService
    private let searchController: SaveSearchController
    private let planAroundController: SavePlanAroundController
    private var importedPendingKeys: Set<String> = []

    init(
        supabaseService: SupabaseServiceProtocol = SupabaseService.shared,
        pendingImportService: PendingPlaceImportService = .shared,
        saveLocalVaultService: SaveLocalVaultService = .shared,
        socialLinkReviewCandidateService: SocialLinkReviewCandidateService = .shared,
        searchController: SaveSearchController = SaveSearchController(),
        planAroundController: SavePlanAroundController = SavePlanAroundController()
    ) {
        self.supabaseService = supabaseService
        self.authService = PrivyAuthService.shared
        self.pendingImportService = pendingImportService
        self.saveLocalVaultService = saveLocalVaultService
        self.socialLinkReviewCandidateService = socialLinkReviewCandidateService
        self.searchController = searchController
        self.planAroundController = planAroundController
    }

    var filteredPlaces: [Place] {
        var result = places

        // Status filter
        switch filter {
        case .all: break
        case .wantToGo: result = result.filter { $0.status == .wantToGo }
        case .visited: result = result.filter { $0.status == .visited }
        }

        // Category filter
        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.category) }
        }

        // Search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.address.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort
        switch sort {
        case .recent: result.sort { $0.createdAt > $1.createdAt }
        case .rating: result.sort { ($0.googleRating ?? 0) > ($1.googleRating ?? 0) }
        case .nearest: break // TODO: Sort by distance from user location
        }

        return result
    }

    var saveSearchResponse: SaveSearchResponse {
        searchController.search(
            query: searchText,
            places: places,
            localRecords: localMemoryRecords,
            mapCandidates: mapCandidates
        )
    }

    func loadPlaces() async {
        isLoading = true
        defer { isLoading = false }
        loadLocalMemoryRecords()

        guard let userId = authService.currentUserId else {
            importPendingPlacesForLocalUse()
            return
        }

        do {
            places = try await supabaseService.fetchPlaces(for: userId)
            try await importPendingReviewCandidates(for: userId, runSourceRecovery: false)
            try await importPendingPlaces(for: userId)
            loadLocalMemoryRecords()
        } catch {
            print("Failed to load places: \(error)")
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
        }

        pendingImportService.restorePendingPlaces(pending)
    }

    private func importPendingPlaces(for userId: String) async throws {
        let pending = pendingImportService.consumePendingPlaces()
        guard !pending.isEmpty else { return }

        var importedPlaces: [Place] = []
        var failedImports: [PendingSharedPlace] = []
        var processedPendingKeys: Set<String> = []

        for pendingPlace in pending {
            let place = Place.from(pendingPlace)
            let key = place.pendingDeduplicationKey

            guard !processedPendingKeys.contains(key),
                  !places.contains(where: { $0.matches(place) }) else {
                continue
            }

            processedPendingKeys.insert(key)

            do {
                try await supabaseService.savePlace(place, userId: userId)
                _ = try? saveLocalVaultService.saveConfirmedPlace(place)
                importedPendingKeys.insert(key)
                importedPlaces.append(place)
            } catch {
                failedImports.append(pendingPlace)
                importedPlaces.append(place)
                print("PlaceListViewModel: failed to import shared place \(pendingPlace.name): \(error)")
            }
        }

        if !importedPlaces.isEmpty {
            places = importedPlaces + places
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
            do {
                _ = try saveLocalVaultService.saveReviewCandidate(refinedCandidate)
            } catch {
                print("PlaceListViewModel: failed to mirror review candidate to local vault: \(error)")
            }

            do {
                let captureId = try await supabaseService.createMemoryCapture(from: refinedCandidate, userId: userId)
                try await supabaseService.createPlaceCandidate(refinedCandidate, captureId: captureId, userId: userId)
                if runSourceRecovery && refinedCandidate.isSourceOnly {
                    _ = try? await supabaseService.recoverSourceOnlyReviewCandidates(captureId: captureId)
                }
            } catch {
                failedCandidates.append(candidate)
                print("PlaceListViewModel: failed to import review candidate \(candidate.candidateName): \(error)")
            }
        }

        pendingImportService.restorePendingReviewCandidates(failedCandidates)
    }

    func markVisited(_ place: Place) async {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index].status = .visited
        do {
            try await supabaseService.updatePlace(places[index])
        } catch {
            print("Failed to update place: \(error)")
        }
    }

    func updatePlaceVisibility(_ place: Place, visibility: PlaceVisibility) async throws {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        let previousPlace = places[index]
        places[index].visibility = visibility

        do {
            try await supabaseService.updatePlaceVisibility(visibility, for: place.id)
        } catch {
            places[index] = previousPlace
            throw error
        }
    }

    func saveMapCandidate(_ result: SaveSearchResult) async {
        guard let draft = searchController.makeSaveDraft(from: result) else {
            saveCandidateError = SavePlaceDraftError.notSaveableMapCandidate.localizedDescription
            return
        }

        savingResultID = result.id
        saveCandidateError = nil
        defer { savingResultID = nil }

        do {
            let place = try await searchController.saveMapCandidate(draft)
            var syncError: Error?

            if let userId = authService.currentUserId {
                do {
                    try await supabaseService.savePlace(place, userId: userId)
                } catch {
                    syncError = error
                    print("PlaceListViewModel: failed to sync saved map candidate \(place.name): \(error)")
                }
            }

            _ = try? saveLocalVaultService.saveConfirmedPlace(place)
            if !places.contains(where: { $0.matches(place) }) {
                places = [place] + places
            }
            removeMapCandidate(matching: result)
            loadLocalMemoryRecords()

            if let syncError {
                saveCandidateError = "Saved locally. Sync failed: \(syncError.localizedDescription)"
            }
        } catch {
            saveCandidateError = error.localizedDescription
        }
    }

    func planAround(_ result: SaveSearchResult) {
        let savedResponse = searchController.search(query: "", places: places, localRecords: localMemoryRecords)
        let request = SavePlanAroundRequest(
            anchorResultID: result.id,
            duration: .halfDay,
            intent: .balanced
        )
        planAroundResult = planAroundController.planAround(
            anchor: result,
            savedResults: savedResponse.fromYourSave.results,
            mapCandidates: mapCandidates,
            request: request
        )
    }

    private func loadLocalMemoryRecords() {
        do {
            localMemoryRecords = try saveLocalVaultService.recentRecords(limit: 100)
        } catch {
            localMemoryRecords = []
            print("PlaceListViewModel: failed to load local memory records: \(error)")
        }
    }

    private func removeMapCandidate(matching result: SaveSearchResult) {
        mapCandidates.removeAll { candidate in
            "map-candidate-\(candidate.id)" == result.id || (
                candidate.title == result.title &&
                candidate.latitude == result.latitude &&
                candidate.longitude == result.longitude
            )
        }
    }

    func deletePlace(_ place: Place) async throws {
        let previousPlaces = places
        places.removeAll { $0.id == place.id }
        deleteError = nil
        do {
            try await supabaseService.deletePlace(place.id)
        } catch {
            places = previousPlaces
            deleteError = error.localizedDescription
            print("Failed to delete place: \(error)")
            throw error
        }
    }
}
