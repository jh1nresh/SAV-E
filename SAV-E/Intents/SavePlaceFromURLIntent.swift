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
        let startedBy = PrivyAuthService.shared.currentUserId
        let generation = PrivyAuthService.shared.sessionGeneration
        let candidates: [PendingReviewCandidate]
        do {
            candidates = try await SocialLinkReviewCandidateService.shared.reviewCandidates(from: url)
        } catch {
            try Self.ensureInitiatingSession(startedBy, generation)
            let record = try SaveLocalVaultService.shared.saveSourceOnly(
                url: url,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                ownerSubject: startedBy
            )
            return .result(dialog: "Saved \(record.displayTitle) as a Savvy source clue. Open Savvy to review it.")
        }

        try Self.ensureInitiatingSession(startedBy, generation)

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
    static func ensureInitiatingSession(_ userId: String?, _ generation: Int) throws {
        let auth = PrivyAuthService.shared
        guard auth.currentUserId == userId, auth.sessionGeneration == generation else {
            throw ReviewCandidateError.sessionChangedAfterCommit
        }
    }
}
