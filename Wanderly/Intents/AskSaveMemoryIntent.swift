import AppIntents
import Foundation

struct AskSaveMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask SAV-E Memory"
    static var description = IntentDescription("Ask SAV-E for a short summary of recent Map Stamps and source clues.")
    static var openAppWhenRun = false

    @Parameter(title: "Question", default: "What did I save recently?")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let records = try SaveLocalVaultService.shared.recentRecords(limit: 5)
        guard !records.isEmpty else {
            return .result(dialog: "SAV-E has no Map Stamps or source clues yet. Share or save a place URL first.")
        }

        let summary = records
            .map { "\($0.displayTitle) [\($0.state.displayName)]" }
            .joined(separator: ", ")
        return .result(dialog: "Recent SAV-E state: \(summary).")
    }
}
