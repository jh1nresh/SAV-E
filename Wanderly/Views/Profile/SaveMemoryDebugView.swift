import SwiftUI

struct SaveMemoryDebugView: View {
    @State private var records: [SaveMemoryRecord] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if records.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "No Local Memory Yet",
                    systemImage: "tray",
                    description: Text("Use Share Sheet or Siri Shortcuts to save a source into SAV-E memory.")
                )
            }

            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(record.displayTitle)
                            .font(.headline)
                            .foregroundColor(.saveInk)
                        Spacer()
                        Text(record.state.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.saveCocoa)
                    }

                    if let address = record.address {
                        Text(address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let sourceURL = record.sourceURL, let url = URL(string: sourceURL) {
                        Link(destination: url) {
                            Label("Open source", systemImage: "link")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.saveCocoa)
                        }
                    }

                    if let diagnostic = record.evidenceDiagnostic {
                        evidenceDiagnosticView(diagnostic)
                    } else if !record.evidence.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Evidence")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            EvidenceLinkList(evidence: record.evidence, maxItems: 3)
                        }
                    }

                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Local Memory")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadRecords() }
        .refreshable { loadRecords() }
    }

    private func loadRecords() {
        do {
            records = try SaveLocalVaultService.shared.recentRecords(limit: 50)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func evidenceDiagnosticView(_ diagnostic: SocialPlaceEvidenceDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(diagnostic.statusLabel)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.saveCocoa)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.saveCocoa.opacity(0.12))
                    .cornerRadius(999)
                Text(diagnostic.primaryActionLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }

            diagnosticSection("Found", items: diagnostic.found)
            diagnosticSection("Tried", items: diagnostic.attempts)
            diagnosticSection("Search next", items: diagnostic.suggestedSearchQueries ?? [])
            diagnosticSection("Missing", items: diagnostic.missingFields)

            if !diagnostic.nextBestClue.isEmpty {
                Text("Next best clue: \(diagnostic.nextBestClue)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.saveCocoa)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.saveCocoa.opacity(0.08))
        .cornerRadius(12)
    }

    private func diagnosticSection(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !items.isEmpty {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                EvidenceLinkList(evidence: Array(items.prefix(3)), maxItems: 3)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SaveMemoryDebugView()
    }
}
