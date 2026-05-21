import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: UserProfile = .mock
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let supabaseService: SupabaseServiceProtocol
    private let authService: PrivyAuthService

    init(supabaseService: SupabaseServiceProtocol = SupabaseService.shared) {
        self.supabaseService = supabaseService
        self.authService = PrivyAuthService.shared
    }

    func loadProfile() async {
        guard let userId = authService.currentUserId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let profile = try await supabaseService.fetchProfile(for: userId) {
                self.profile = profile
            }
        } catch is CancellationError {
            // View lifecycle cancelled the profile load; do not surface as a user-facing error.
        } catch {
            if (error as? URLError)?.code == .cancelled {
                // URLSession cancellation is expected when the view task is torn down.
                return
            }
            errorMessage = error.localizedDescription
            print("Failed to load profile: \(error)")
        }
    }

    func updateDisplayName(_ displayName: String) async -> Bool {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name cannot be empty."
            return false
        }

        let previousProfile = profile
        profile.displayName = trimmedName
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await supabaseService.updateProfile(profile)
            await loadProfile()
            return true
        } catch {
            profile = previousProfile
            errorMessage = error.localizedDescription
            print("Failed to update profile: \(error)")
            return false
        }
    }

    func signOut() async {
        await authService.signOut()
    }
}
