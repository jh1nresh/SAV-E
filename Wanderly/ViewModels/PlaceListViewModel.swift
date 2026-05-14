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
    @Published var places: [Place] = Place.mockList
    @Published var filter: PlaceFilter = .all
    @Published var sort: PlaceSort = .recent
    @Published var selectedCategories: Set<PlaceCategory> = []
    @Published var searchText: String = ""
    @Published var isLoading = false
    @Published var deleteError: String?

    private let supabaseService: SupabaseServiceProtocol
    private let authService: PrivyAuthService
    private let pendingImportService: PendingPlaceImportService
    private var importedPendingKeys: Set<String> = []

    init(
        supabaseService: SupabaseServiceProtocol = SupabaseService.shared,
        pendingImportService: PendingPlaceImportService = .shared
    ) {
        self.supabaseService = supabaseService
        self.authService = PrivyAuthService.shared
        self.pendingImportService = pendingImportService
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

    func markVisited(_ place: Place) async {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index].status = .visited
        do {
            try await supabaseService.updatePlace(places[index])
        } catch {
            print("Failed to update place: \(error)")
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
