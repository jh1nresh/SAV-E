import Foundation

@MainActor
final class SavePetCompanionStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case needsSelection
        case ready
        case unavailable
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var profile: UserProfile?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSaving = false

    private let service: SupabaseServiceProtocol
    private var loadedUserID: String?

    init(service: SupabaseServiceProtocol = SupabaseService.shared) {
        self.service = service
    }

    func phase(for userID: String) -> Phase {
        loadedUserID == userID ? phase : .idle
    }

    func load(userID: String) async {
        guard loadedUserID != userID || phase == .idle else { return }
        loadedUserID = userID
        phase = .loading
        errorMessage = nil

        do {
            profile = try await service.fetchProfile(for: userID)
            phase = profile?.petPreset == nil ? .needsSelection : .ready
        } catch is CancellationError {
            loadedUserID = nil
            phase = .idle
            return
        } catch {
            errorMessage = error.localizedDescription
            phase = .unavailable
        }
    }

    func select(preset: SavePetPreset, name: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Pet name cannot be empty."
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            profile = try await service.selectPet(preset: preset, name: trimmedName)
            phase = .ready
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
