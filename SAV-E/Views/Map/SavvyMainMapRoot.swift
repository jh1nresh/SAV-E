#if SAVVY_MAIN_APP && SAVVY_CITY_MVP
import CryptoKit
import Foundation
import SwiftUI

/// Account identity is private path material. A session generation invalidates
/// a displayed root, but never changes the account's durable directory.
enum SavvyMainMapNamespace {
    nonisolated enum PurgeFailure: Error, Equatable, LocalizedError {
        case invalidOwner
        case documentsUnavailable
        case unsafeDirectory

        var errorDescription: String? {
            switch self {
            case .invalidOwner: "The account identity is unavailable for local cleanup."
            case .documentsUnavailable: "The private documents directory is unavailable for local cleanup."
            case .unsafeDirectory: "The account directory cannot be safely cleaned up."
            }
        }
    }

    nonisolated static func accountDirectory(ownerSubject: String, documentsDirectory: URL?) -> URL? {
        guard !ownerSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let documentsDirectory, documentsDirectory.isFileURL else { return nil }
        let digest = SHA256.hash(data: Data(ownerSubject.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return documentsDirectory
            .appendingPathComponent("Savvy", isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
    }

    /// The account-deletion owner calls this before completing its existing
    /// cleanup journal. Failures propagate so that cleanup remains retryable.
    /// Only this account's private sidecar directory is removed; legacy stores
    /// and other accounts remain owned by their existing cleanup routines.
    nonisolated static func purgeAccountSidecars(
        ownerSubject: String,
        documentsDirectory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    ) throws {
        guard !ownerSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PurgeFailure.invalidOwner
        }
        guard let documentsDirectory, documentsDirectory.isFileURL,
              !documentsDirectory.path.isEmpty else { throw PurgeFailure.documentsUnavailable }
        guard !documentsDirectory.pathComponents.contains(".."),
              !documentsDirectory.pathComponents.contains(".") else { throw PurgeFailure.unsafeDirectory }
        let manager = FileManager.default
        guard try isRealDirectory(documentsDirectory, manager: manager) else {
            throw PurgeFailure.documentsUnavailable
        }
        guard let account = accountDirectory(ownerSubject: ownerSubject, documentsDirectory: documentsDirectory) else {
            throw PurgeFailure.documentsUnavailable
        }
        // Check each appended component before inspecting the next one. Never
        // descend through an account or namespace symlink, even a dangling one.
        let namespace = documentsDirectory.appendingPathComponent("Savvy", isDirectory: true)
        let accounts = namespace.appendingPathComponent("Accounts", isDirectory: true)
        for directory in [namespace, accounts, account] {
            guard try isRealDirectory(directory, manager: manager) else { return }
        }
        try manager.removeItem(at: account)
    }

    private nonisolated static func isRealDirectory(_ url: URL, manager: FileManager) throws -> Bool {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try manager.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.fileReadNoSuchFile.rawValue { return false }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw PurgeFailure.unsafeDirectory
        }
        return true
    }

    nonisolated static func matchesSession(
        ownerSubject: String, sessionGeneration: Int,
        currentOwner: String?, currentGeneration: Int
    ) -> Bool {
        !ownerSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && currentOwner == ownerSubject && currentGeneration == sessionGeneration
    }
}

/// SaveApp's verified account gate owns this root. Its parent must key the view
/// identity by owner and generation so StateObjects are replaced per session.
struct SavvyMainMapRoot: View {
    let ownerSubject: String
    let sessionGeneration: Int
    @Binding private var incomingPlaceReceipt: SharedPlaceReceiptDestination?
    @Binding private var requiresShareConfirmation: Bool
    @Binding private var requiresListConfirmation: Bool
    @Binding private var pendingClipListSave: SaveCollaborativeList?
    @Binding private var pendingOnboardingClue: String
    @EnvironmentObject private var authService: PrivyAuthService
    @Environment(\.appLanguageSettings) private var language
    @AppStorage(CityMVPStyle.nightPreference) private var night = false
    @StateObject private var captureDraft: CityMVPCaptureDraftStore
    @StateObject private var recommendations: CityMVPRecommendationStore

    init(
        ownerSubject: String,
        sessionGeneration: Int,
        incomingPlaceReceipt: Binding<SharedPlaceReceiptDestination?>,
        requiresShareConfirmation: Binding<Bool>,
        requiresListConfirmation: Binding<Bool>,
        pendingClipListSave: Binding<SaveCollaborativeList?>,
        pendingOnboardingClue: Binding<String>
    ) {
        self.ownerSubject = ownerSubject
        self.sessionGeneration = sessionGeneration
        _incomingPlaceReceipt = incomingPlaceReceipt
        _requiresShareConfirmation = requiresShareConfirmation
        _requiresListConfirmation = requiresListConfirmation
        _pendingClipListSave = pendingClipListSave
        _pendingOnboardingClue = pendingOnboardingClue
        let directory = SavvyMainMapNamespace.accountDirectory(
            ownerSubject: ownerSubject,
            documentsDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        )
        let isCurrentSession: () -> Bool = {
            let auth = PrivyAuthService.shared
            return SavvyMainMapNamespace.matchesSession(ownerSubject: ownerSubject,
                sessionGeneration: sessionGeneration, currentOwner: auth.currentUserId,
                currentGeneration: auth.sessionGeneration)
        }
        _captureDraft = StateObject(wrappedValue: CityMVPCaptureDraftStore(
            documentsDirectory: directory, isCurrentSession: isCurrentSession))
        _recommendations = StateObject(wrappedValue: CityMVPRecommendationStore(
            documentsDirectory: directory, isCurrentSession: isCurrentSession))
    }

    var body: some View {
        Group {
            if isCurrentAccount {
                ContentView(
                    incomingPlaceReceipt: $incomingPlaceReceipt,
                    requiresShareConfirmation: $requiresShareConfirmation,
                    requiresListConfirmation: $requiresListConfirmation,
                    pendingClipListSave: $pendingClipListSave,
                    pendingOnboardingClue: $pendingOnboardingClue,
                    storageScope: .production
                )
                .environmentObject(captureDraft)
                .environmentObject(recommendations)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(night ? .dark : .light)
        .alert(language.localized(english: "Capture draft", traditionalChinese: "線索草稿"),
               isPresented: Binding(
                get: { isCurrentAccount && captureDraft.failure != nil },
                set: { if !$0 && isCurrentAccount { captureDraft.dismissFailure() } }
               )) {
            Button(language.localized(english: "OK", traditionalChinese: "知道了")) {
                if isCurrentAccount { captureDraft.dismissFailure() }
            }
        } message: {
            Text(captureDraft.failure?.message(english: language.language != .traditionalChinese) ?? "")
        }
    }

    private var isCurrentAccount: Bool {
        guard case .authenticated = authService.authState else { return false }
        return SavvyMainMapNamespace.matchesSession(
            ownerSubject: ownerSubject, sessionGeneration: sessionGeneration,
            currentOwner: authService.currentUserId, currentGeneration: authService.sessionGeneration
        )
    }
}
#endif
