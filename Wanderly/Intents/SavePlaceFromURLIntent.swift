import AppIntents
import Foundation

struct SavePlaceFromURLIntent: AppIntent {
    static var title: LocalizedStringResource = "Save URL to SAV-E"
    static var description = IntentDescription("Save a place, event, or social URL into SAV-E local memory for later review.")
    static var openAppWhenRun = false

    @Parameter(title: "URL")
    var url: URL

    @Parameter(title: "Note", default: "")
    var note: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let candidates: [PendingReviewCandidate]
        do {
            candidates = try await SocialLinkReviewCandidateService.shared.reviewCandidates(from: url)
        } catch {
            let record = try SaveLocalVaultService.shared.saveSourceOnly(
                url: url,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return .result(dialog: "Saved \(record.displayTitle) as a SAV-E source clue. Open SAV-E to review it.")
        }

        var savedCount = 0
        var failedCount = 0
        for candidate in candidates {
            do {
                _ = try SaveLocalVaultService.shared.saveReviewCandidate(candidate)
                savedCount += 1
            } catch {
                failedCount += 1
            }
        }

        if failedCount == 0 {
            let countLabel = candidates.count == 1 ? "1 review candidate" : "\(candidates.count) review candidates"
            return .result(dialog: "Saved \(countLabel) to SAV-E Review.")
        }

        if savedCount > 0 {
            return .result(dialog: "Saved \(savedCount) review candidates to SAV-E Review. \(failedCount) could not be saved.")
        }

        return .result(dialog: "SAV-E found review candidates but could not save them. Open SAV-E and try again.")
    }
}
