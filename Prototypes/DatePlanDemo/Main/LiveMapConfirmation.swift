#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation

/// Keeps the explicit confirmation bound through token-provider suspension and
/// every request made by the canonical save. The caller still owns UI state.
@MainActor
enum LiveMapConfirmation {
    static func save(_ candidate: SaveMapCandidate, using map: MapViewModel,
                     ownerSubject: String, sessionGeneration: Int) async throws -> Place {
        try Task.checkCancellation()
        func requireSession() throws {
            let auth = PrivyAuthService.shared
            guard case .authenticated(let owner) = auth.authState else {
                throw ReviewCandidateError.signInRequired
            }
            guard owner == ownerSubject, auth.currentUserId == ownerSubject,
                  auth.sessionGeneration == sessionGeneration else {
                throw ReviewCandidateError.sessionChangedAfterCommit
            }
        }
        try requireSession()
        return try await SAVEPendingImportSessionScope.$current.withValue(
            (generation: sessionGeneration, owner: ownerSubject)
        ) {
            try Task.checkCancellation()
            try requireSession()
            do {
                let saved = try await map.saveMapCandidateAsPlace(candidate)
                try Task.checkCancellation()
                try requireSession()
                return saved
            } catch {
                // A canonical save can translate transport cancellation while
                // unwinding. Prefer the existing account-boundary error when
                // the requested session has changed, and never return stale UI.
                try requireSession()
                throw error
            }
        }
    }
}
#endif
