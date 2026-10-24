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
    private let saveLocalVaultService: SaveLocalVaultService
    private let pendingPlaceImportService: PendingPlaceImportService
    private let accountReferenceStore: AccountReferenceStoring
    private let updateProfileRemotely: (UserProfile) async throws -> Void
    private let currentUserIDProvider: () -> String?
    private let reviewerDemoProvider: () -> Bool
    private var loadedUserID: String?
    // A live request owns its intent across Profile instances in this process.
    // A process restart naturally has no lease and can recover the durable scope.
    private static var inFlightAccountDeletionIDs = Set<UUID>()

    init(
        supabaseService: SupabaseServiceProtocol = SupabaseService.shared,
        accountDeletionService: AccountDeletionProviding = SupabaseService.shared,
        avatarStore: ProfileAvatarStore = .shared,
        saveLocalVaultService: SaveLocalVaultService = .shared,
        pendingPlaceImportService: PendingPlaceImportService = .shared,
        accountReferenceStore: AccountReferenceStoring = KeychainAccountReferenceStore.shared,
        updateProfileRemotely: ((UserProfile) async throws -> Void)? = nil,
        currentUserIDProvider: @escaping () -> String? = { PrivyAuthService.shared.currentUserId },
        reviewerDemoProvider: @escaping () -> Bool = { PrivyAuthService.shared.isReviewerDemo }
    ) {
        self.supabaseService = supabaseService
        self.accountDeletionService = accountDeletionService
        self.avatarStore = avatarStore
        self.saveLocalVaultService = saveLocalVaultService
        self.pendingPlaceImportService = pendingPlaceImportService
        self.accountReferenceStore = accountReferenceStore
        self.updateProfileRemotely = updateProfileRemotely ?? { profile in
            try await supabaseService.updateProfile(profile)
        }
        self.currentUserIDProvider = currentUserIDProvider
        self.reviewerDemoProvider = reviewerDemoProvider
        self.authService = PrivyAuthService.shared
    }

    var isAuthenticated: Bool { authService.isAuthenticated }

    func resetForCurrentSession() {
        let userID = reviewerDemoProvider() ? nil : currentUserIDProvider()
        guard loadedUserID != userID || userID == nil else { return }
        loadedUserID = userID
        profile = .empty
        localAvatarData = nil
        errorMessage = nil
    }

    func loadProfile() async {
        guard !isDeletingAccount else { return }
        resetForCurrentSession()
        // Recovery is local-only and works even when the deleted identity can no
        // longer sign in. Unknown remote outcomes never trigger an automatic DELETE.
        do {
            if let pending = try saveLocalVaultService.pendingAccountDeletionIntent() {
                guard !Self.inFlightAccountDeletionIDs.contains(pending.id) else { return }
                let generation = authService.sessionGeneration
                Self.inFlightAccountDeletionIDs.insert(pending.id)
                defer { Self.inFlightAccountDeletionIDs.remove(pending.id) }
                try await finishLocalAccountDeletion(pending, sessionGeneration: generation)
                errorMessage = pending.remoteOutcome == .succeeded
                    ? "Previous account’s local cleanup is complete."
                    : "Local cleanup is complete. The remote account deletion result could not be confirmed."
                return
            }
        } catch {
            errorMessage = "Local account cleanup could not finish. Retry to remove the hidden data from this device. \(error.localizedDescription)"
            return
        }
        if reviewerDemoProvider() {
            errorMessage = nil
            return
        }
        guard let userId = currentUserIDProvider() else { return }
        localAvatarData = avatarStore.load(for: userId)
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let profile = try await supabaseService.fetchProfile(for: userId) {
                guard !Task.isCancelled, currentUserIDProvider() == userId, !reviewerDemoProvider() else { return }
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
            guard currentUserIDProvider() == userId, !reviewerDemoProvider() else { return }
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

        guard let savingUserID = currentUserIDProvider(), !reviewerDemoProvider() else { return false }
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
            guard currentUserIDProvider() == savingUserID, !reviewerDemoProvider() else {
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
            try await updateProfileRemotely(updatedProfile)
            guard currentUserIDProvider() == savingUserID, !reviewerDemoProvider() else {
                resetForCurrentSession()
                return false
            }
            return true
        } catch {
            guard currentUserIDProvider() == savingUserID, !reviewerDemoProvider() else {
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
        guard !isDeletingAccount, !reviewerDemoProvider() else { return false }
        isDeletingAccount = true
        errorMessage = nil
        var activeIntentID: UUID?
        defer {
            if let activeIntentID { Self.inFlightAccountDeletionIDs.remove(activeIntentID) }
            isDeletingAccount = false
        }
        var remoteSuccessObserved = false

        do {
            let cleanup: SaveAccountDeletionIntent
            let sessionGeneration = authService.sessionGeneration
            let currentOwner = currentUserIDProvider()
            let isRecovery: Bool
            if let pending = try saveLocalVaultService.pendingAccountDeletionIntent() {
                guard !Self.inFlightAccountDeletionIDs.contains(pending.id) else {
                    errorMessage = "Account deletion is already in progress. Retry after it finishes."
                    return false
                }
                cleanup = pending
                isRecovery = true
            } else {
                guard let deletingUserID = currentOwner else { return false }
                let queueSnapshot = try pendingPlaceImportService.ownerlessQueueSnapshotForAccountDeletion()
                let prepared = try saveLocalVaultService.prepareAccountDeletion(
                    belongingTo: deletingUserID,
                    initialOwnerlessQueueItemKeys: queueSnapshot.ownerlessItemKeys,
                    unreadableQueueFileNames: queueSnapshot.unreadableFileNames
                )
                activeIntentID = prepared.id
                Self.inFlightAccountDeletionIDs.insert(prepared.id)
                isRecovery = false
                do {
                    try await accountDeletionService.deleteAccount(
                        startedBy: deletingUserID, generation: sessionGeneration
                    )
                    remoteSuccessObserved = true
                    cleanup = try saveLocalVaultService.recordRemoteAccountDeletionSuccess(intentID: prepared.id)
                } catch {
                    // Unknown remote outcome stays on the durable intent
                    // (`.awaitingRemoteResult`). Finish the same local
                    // quarantine cleanup as recovery so neither Share
                    // queue remains consumable while A stays signed in.
                    cleanup = prepared
                }
            }
            if activeIntentID == nil {
                activeIntentID = cleanup.id
                Self.inFlightAccountDeletionIDs.insert(cleanup.id)
            }
            try await finishLocalAccountDeletion(cleanup, sessionGeneration: sessionGeneration)
            if cleanup.remoteOutcome != .succeeded {
                errorMessage = "Local cleanup is complete. The remote account deletion result could not be confirmed. Retry only to request account deletion again."
                return false
            }
            if isRecovery, let currentOwner, currentOwner != cleanup.owner {
                errorMessage = "Previous account’s local cleanup is complete. Retry to delete this account."
                return false
            }
            return true
        } catch {
            if remoteSuccessObserved {
                errorMessage = "Account deleted, but local data cleanup failed. Retry to finish removing data from this device. \(error.localizedDescription)"
            } else {
                errorMessage = "Account deletion or local cleanup could not be completed. Any pending local data remains hidden; retry to finish cleanup. \(error.localizedDescription)"
            }
            return false
        }
    }

    private func finishLocalAccountDeletion(
        _ intent: SaveAccountDeletionIntent, sessionGeneration: Int
    ) async throws {
        if intent.remoteOutcome == .succeeded {
            // Invalidate the deleted owner before any fallible vault-record
            // purge so a storage failure cannot leave A able to consume Share
            // queues. Sign out before the queue purge so admitted late writers
            // finish under the same per-file lock, then cannot recreate A.
            if !reviewerDemoProvider() {
                let activeOwner = authService.currentUserId
                if activeOwner == intent.owner,
                   currentUserIDProvider() == intent.owner,
                   authService.sessionGeneration == sessionGeneration {
                    try? accountReferenceStore.clear()
                    await authService.signOut()
                    resetForCurrentSession()
                } else if activeOwner == nil {
                    // Recovery after Privy already reports signed out: the
                    // durable receipt is about to be removed, so the stale
                    // binding must go too. Preserve it only when a different
                    // active account has already replaced the deleted owner.
                    try? accountReferenceStore.clear()
                }
            }
            // The owner may already be signed out or replaced by B. Only remove
            // the deleted owner's stale cache; this synchronous check never clears B.
            if authService.currentUserId != intent.owner,
               SavePlaceLimitHandoff.cachedActiveOwner() == intent.owner {
                SavePlaceLimitHandoff.syncActiveOwner(nil)
            }
        }
        // Quarantine both Share queues before the fallible vault-record purge
        // and before fallible avatar removal. Unknown remote outcomes still
        // finish this local cleanup while A stays signed in.
        try pendingPlaceImportService.purgeAccountDeletionItems(
            belongingTo: intent.owner,
            initialOwnerlessItemKeys: intent.initialOwnerlessQueueItemKeys,
            unreadableFileNames: intent.unreadableQueueFileNames
        )
        if intent.remoteOutcome == .succeeded {
            // SDK identity mismatch or a changed generation may make signOut
            // return without ending A's local session. Queues are already
            // quarantined; keep the durable vault scope for retry.
            guard authService.currentUserId != intent.owner else {
                throw AccountDeletionCleanupError.deletedSessionStillActive
            }
        }
        try saveLocalVaultService.purgeAccountDeletionRecords(intentID: intent.id)
        try avatarStore.remove(for: intent.owner)
        try saveLocalVaultService.completeAccountDeletionCleanup(intentID: intent.id)
    }

    private enum AccountDeletionCleanupError: LocalizedError {
        case deletedSessionStillActive

        var errorDescription: String? {
            "The deleted account’s session is still active. Retry to finish signing out and local cleanup."
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

/// Keeps withdrawal available while the Friends sharing experience is deferred.
@MainActor
final class SharedRestaurantRatingsViewModel: ObservableObject {
    @Published private(set) var ratings: [OwnRestaurantRating] = []
    @Published private(set) var isLoading = false
    @Published private(set) var withdrawingID: UUID?
    @Published private(set) var hasError = false

    private let fetch: () async throws -> [OwnRestaurantRating]
    private let withdraw: (UUID) async throws -> Void
    private let currentSession: () -> Int?
    private let session: Int?
    private var isActive = true

    init(
        fetch: @escaping () async throws -> [OwnRestaurantRating] = {
            try await SupabaseService.shared.fetchOwnRestaurantRatings()
        },
        withdraw: @escaping (UUID) async throws -> Void = {
            try await SupabaseService.shared.withdrawRestaurantRating(placeID: $0)
        },
        currentSession: @escaping () -> Int? = {
            let auth = PrivyAuthService.shared
            return auth.isAuthenticated && !auth.isReviewerDemo ? auth.sessionGeneration : nil
        }
    ) {
        self.fetch = fetch
        self.withdraw = withdraw
        self.currentSession = currentSession
        self.session = currentSession()
    }

    private var canApply: Bool {
        isActive && session != nil && currentSession() == session && !Task.isCancelled
    }

    func load() async {
        guard canApply, !isLoading else { return }
        isLoading = true
        hasError = false
        defer { isLoading = false }
        do {
            let result = try await fetch()
            guard canApply else { invalidate(); return }
            ratings = result.filter(\.shared)
        } catch {
            guard canApply else { invalidate(); return }
            hasError = true
        }
    }

    func stopSharing(_ placeID: UUID) async {
        guard canApply, withdrawingID == nil, ratings.contains(where: { $0.place_id == placeID }) else { return }
        withdrawingID = placeID
        hasError = false
        defer { withdrawingID = nil }
        do {
            try await withdraw(placeID)
            guard canApply else { invalidate(); return }
            ratings.removeAll { $0.place_id == placeID }
        } catch {
            guard canApply else { invalidate(); return }
            hasError = true
        }
    }

    func invalidate() {
        isActive = false
        ratings = []
        hasError = false
    }
}
