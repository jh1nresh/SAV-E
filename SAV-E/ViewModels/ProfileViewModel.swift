import Foundation
import UIKit

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: UserProfile = .empty
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isDeletingAccount = false
    @Published var errorMessage: String?

    private let supabaseService: SupabaseServiceProtocol
    private let authService: PrivyAuthService
    private let accountDeletionService: AccountDeletionProviding

    init(
        supabaseService: SupabaseServiceProtocol = SupabaseService.shared,
        accountDeletionService: AccountDeletionProviding = SupabaseService.shared
    ) {
        self.supabaseService = supabaseService
        self.accountDeletionService = accountDeletionService
        self.authService = PrivyAuthService.shared
    }

    func loadProfile() async {
        if authService.isReviewerDemo {
            errorMessage = nil
            return
        }
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
        await updateProfile(displayName: displayName, avatarData: nil)
    }

    func updateProfile(displayName: String, avatarData: Data?) async -> Bool {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name cannot be empty."
            return false
        }

        let previousProfile = profile
        profile.displayName = trimmedName
        if let avatarData {
            do {
                profile.avatarUrl = try saveAvatarImage(avatarData)
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
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

    func deleteAccount() async -> Bool {
        guard !authService.isReviewerDemo else { return false }
        isDeletingAccount = true
        errorMessage = nil
        defer { isDeletingAccount = false }

        do {
            try await accountDeletionService.deleteAccount()
            try? SaveLocalVaultService.shared.deleteAllRecords()
            try? KeychainAccountReferenceStore.shared.clear()
            await authService.signOut()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func saveAvatarImage(_ data: Data) throws -> String {
        guard let image = UIImage(data: data) else {
            throw ProfileImageError.invalidImage
        }

        let maxDimension: CGFloat = 512
        let scale = min(maxDimension / max(image.size.width, image.size.height), 1)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let jpegData = resized.jpegData(compressionQuality: 0.84) else {
            throw ProfileImageError.invalidImage
        }

        let directory = try avatarDirectory()
        let fileURL = directory.appendingPathComponent("profile-avatar.jpg")
        try jpegData.write(to: fileURL, options: .atomic)
        return fileURL.absoluteString
    }

    private func avatarDirectory() throws -> URL {
        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = supportDirectory.appendingPathComponent("Profile", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum ProfileImageError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "Couldn’t use that photo. Choose another image."
    }
}
