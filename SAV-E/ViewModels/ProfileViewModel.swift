import Foundation
import UIKit
import CryptoKit

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: UserProfile = .empty
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isDeletingAccount = false
    @Published var errorMessage: String?
    @Published private(set) var localAvatarData: Data?

    private let supabaseService: SupabaseServiceProtocol
    private let authService: PrivyAuthService
    private let accountDeletionService: AccountDeletionProviding
    private let avatarStore: ProfileAvatarStore
    private var loadedUserID: String?

    init(
        supabaseService: SupabaseServiceProtocol = SupabaseService.shared,
        accountDeletionService: AccountDeletionProviding = SupabaseService.shared,
        avatarStore: ProfileAvatarStore = .shared
    ) {
        self.supabaseService = supabaseService
        self.accountDeletionService = accountDeletionService
        self.avatarStore = avatarStore
        self.authService = PrivyAuthService.shared
    }

    var isAuthenticated: Bool { authService.isAuthenticated }

    func resetForCurrentSession() {
        let userID = authService.isReviewerDemo ? nil : authService.currentUserId
        guard loadedUserID != userID || userID == nil else { return }
        loadedUserID = userID
        profile = .empty
        localAvatarData = nil
        errorMessage = nil
    }

    func loadProfile() async {
        resetForCurrentSession()
        if authService.isReviewerDemo {
            errorMessage = nil
            return
        }
        guard let userId = authService.currentUserId else { return }
        localAvatarData = avatarStore.load(for: userId)
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let profile = try await supabaseService.fetchProfile(for: userId) {
                guard !Task.isCancelled, authService.currentUserId == userId, !authService.isReviewerDemo else { return }
                self.profile = profile
                if localAvatarData == nil {
                    localAvatarData = try? avatarStore.migrateLegacyAvatarIfNeeded(
                        from: profile.avatarUrl,
                        for: userId
                    )
                }
            }
        } catch is CancellationError {
            // View lifecycle cancelled the profile load; do not surface as a user-facing error.
        } catch {
            if (error as? URLError)?.code == .cancelled {
                // URLSession cancellation is expected when the view task is torn down.
                return
            }
            guard authService.currentUserId == userId, !authService.isReviewerDemo else { return }
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

        guard let savingUserID = authService.currentUserId, !authService.isReviewerDemo else { return false }
        let previousProfile = profile
        let pendingAvatarData: Data?
        do {
            pendingAvatarData = try avatarData.map(normalizedAvatarData)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        // A Passport photo has no cloud representation. Persist it before any
        // profile API request so an offline name update cannot discard it.
        do {
            if let pendingAvatarData {
                try avatarStore.save(pendingAvatarData, for: savingUserID)
            }
            guard authService.currentUserId == savingUserID, !authService.isReviewerDemo else {
                resetForCurrentSession()
                return false
            }
            if let pendingAvatarData {
                localAvatarData = pendingAvatarData
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        guard trimmedName != previousProfile.displayName else { return true }

        var updatedProfile = previousProfile
        updatedProfile.displayName = trimmedName
        // Device files are not cloud avatar URLs. A name update is the only
        // remaining reason to write this profile row, so omit the old value.
        if updatedProfile.avatarUrl.flatMap(URL.init(string:))?.isFileURL == true {
            updatedProfile.avatarUrl = nil
        }
        profile = updatedProfile

        do {
            try await supabaseService.updateProfile(updatedProfile)
            guard authService.currentUserId == savingUserID, !authService.isReviewerDemo else {
                resetForCurrentSession()
                return false
            }
            return true
        } catch {
            guard authService.currentUserId == savingUserID, !authService.isReviewerDemo else {
                resetForCurrentSession()
                return false
            }
            profile = previousProfile
            if pendingAvatarData != nil {
                errorMessage = "Photo saved on this device. Couldn’t update your Passport name: \(error.localizedDescription)"
                return true
            }
            errorMessage = error.localizedDescription
            print("Failed to update profile: \(error)")
            return false
        }
    }

    func signOut() async {
        await authService.signOut()
        resetForCurrentSession()
    }

    func deleteAccount() async -> Bool {
        guard !authService.isReviewerDemo, let deletingUserID = authService.currentUserId else { return false }
        isDeletingAccount = true
        errorMessage = nil
        defer { isDeletingAccount = false }

        do {
            try await accountDeletionService.deleteAccount()
            try? avatarStore.remove(for: deletingUserID)
            guard authService.currentUserId == deletingUserID, !authService.isReviewerDemo else { return true }
            try? SaveLocalVaultService.shared.deleteAllRecords()
            try? KeychainAccountReferenceStore.shared.clear()
            await authService.signOut()
            resetForCurrentSession()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func normalizedAvatarData(_ data: Data) throws -> Data {
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

        return jpegData
    }
}

/// Keeps a chosen Passport photo on this device, scoped to the authenticated
/// account. It deliberately has no URL representation to send to Supabase.
final class ProfileAvatarStore {
    static let shared = ProfileAvatarStore()

    private let fileManager: FileManager
    private let baseDirectory: URL

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Profile/Avatars", isDirectory: true)
    }

    func load(for userID: String) -> Data? {
        try? Data(contentsOf: fileURL(for: userID))
    }

    func save(_ data: Data, for userID: String) throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: userID), options: .atomic)
    }

    func remove(for userID: String) throws {
        let url = fileURL(for: userID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Imports only the old app-owned avatar file into one account's local
    /// store. Arbitrary file URLs must never become Passport photos.
    func migrateLegacyAvatarIfNeeded(from avatarURLString: String?, for userID: String) throws -> Data? {
        if let existing = load(for: userID) { return existing }
        guard !fileManager.fileExists(atPath: fileURL(for: userID).path),
              let avatarURLString,
              let legacyReference = URL(string: avatarURLString),
              legacyReference.isFileURL,
              legacyReference.standardizedFileURL == legacyAvatarURL.standardizedFileURL
        else { return nil }

        let data = try Data(contentsOf: legacyAvatarURL)
        guard !data.isEmpty else { return nil }
        try save(data, for: userID)
        return data
    }

    var legacyAvatarURL: URL {
        baseDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("profile-avatar.jpg")
    }

    private func fileURL(for userID: String) -> URL {
        let digest = SHA256.hash(data: Data(userID.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return baseDirectory.appendingPathComponent("\(filename).jpg")
    }
}

private enum ProfileImageError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Couldn’t use that photo. Choose another image."
        }
    }
}
