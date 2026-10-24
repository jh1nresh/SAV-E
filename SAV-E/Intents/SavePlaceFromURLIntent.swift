import AppIntents
import Foundation

struct SavePlaceFromURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Save URL to Savvy"
    static let description = IntentDescription("Save a place, event, or social URL into Savvy local memory for later review.")
    static let openAppWhenRun = false

    @Parameter(title: "URL")
    var url: URL

    @Parameter(title: "Note", default: "")
    var note: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let auth = PrivyAuthService.shared
        let snapshot = try await auth.resolvedActiveOwner()
        let startedBy = snapshot.ownerSubject
        let candidates: [PendingReviewCandidate]
        do {
            candidates = try await SocialLinkReviewCandidateService.shared.reviewCandidates(from: url)
        } catch {
            try auth.revalidateActiveOwner(snapshot)
            try Self.ensureInitiatingSession(snapshot)
            let record = try SaveLocalVaultService.shared.saveSourceOnly(
                url: url,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                ownerSubject: startedBy
            )
            return .result(dialog: "Saved \(record.displayTitle) as a Savvy source clue. Open Savvy to review it.")
        }

        try auth.revalidateActiveOwner(snapshot)
        try Self.ensureInitiatingSession(snapshot)

        var savedCount = 0
        var failedCount = 0
        for var candidate in candidates {
            do {
                if candidate.ownerSubject == nil {
                    candidate.ownerSubject = startedBy
                }
                _ = try SaveLocalVaultService.shared.saveReviewCandidate(candidate)
                savedCount += 1
            } catch {
                failedCount += 1
            }
        }

        if failedCount == 0 {
            let countLabel = candidates.count == 1 ? "1 review candidate" : "\(candidates.count) review candidates"
            return .result(dialog: "Saved \(countLabel) to Savvy Review.")
        }

        if savedCount > 0 {
            return .result(dialog: "Saved \(savedCount) review candidates to Savvy Review. \(failedCount) could not be saved.")
        }

        return .result(dialog: "Savvy found review candidates but could not save them. Open Savvy and try again.")
    }

    /// A late analysis result must not persist into a different signed-in account.
    /// Reuse the resolved snapshot; do not re-bind a pre-restore generation.
    @MainActor
    static func ensureInitiatingSession(_ snapshot: SaveActiveOwnerSnapshot) throws {
        do {
            try PrivyAuthService.shared.revalidateActiveOwner(snapshot)
        } catch {
            throw ReviewCandidateError.sessionChangedAfterCommit
        }
    }
}
