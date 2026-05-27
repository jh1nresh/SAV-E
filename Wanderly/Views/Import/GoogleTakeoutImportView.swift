import SwiftUI
import UniformTypeIdentifiers

struct GoogleTakeoutImportView: View {
    let existingPlaces: [Place]
    let onSave: ([ImportedPlaceDraft]) async throws -> GoogleTakeoutSaveSummary

    @Environment(\.dismiss) private var dismiss
    @State private var isFileImporterPresented = false
    @State private var isParsing = false
    @State private var isSaving = false
    @State private var parseError: String?
    @State private var saveError: String?
    @State private var result: GoogleTakeoutImportResult?
    @State private var selectedDraftIds: Set<UUID> = []
    @State private var saveSummary: GoogleTakeoutSaveSummary?

    private let importService = GoogleTakeoutImportService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let result {
                    preview(result)
                } else {
                    emptyState
                }
            }
            .background(SaveDottedBackground())
            .navigationTitle("Import Google Takeout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    .disabled(isParsing || isSaving)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: false
            ) { response in
                Task { await handleFileImporter(response) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 44))
                .foregroundColor(.saveCocoa)

            VStack(spacing: 8) {
                Text("Import Google Takeout")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.saveInk)

                Text("Choose a historical Takeout export. Saved-list links still go through Share Sheet or clipboard review.")
                    .font(.subheadline)
                    .foregroundColor(.saveMutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                isFileImporterPresented = true
            } label: {
                HStack(spacing: 8) {
                    if isParsing {
                        ProgressView().tint(.saveInk)
                    } else {
                        Image(systemName: "doc.badge.plus")
                    }
                    Text(isParsing ? "Reading export..." : "Choose .zip, .json, .geojson, or .kml")
                }
                .font(.subheadline)
                .fontWeight(.black)
                .foregroundColor(.saveInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.saveHoney)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 1.6)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isParsing)
            .padding(.horizontal, 24)

            if let parseError {
                Text(parseError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
    }

    private func preview(_ result: GoogleTakeoutImportResult) -> some View {
        VStack(spacing: 0) {
            importSummary(result)

            List {
                let ready = readyDrafts(result)
                if !ready.isEmpty {
                    Section {
                        ForEach(ready) { draft in
                            draftRow(draft, selectable: true)
                        }
                    } header: {
                        Text("Ready to save")
                    } footer: {
                        Text("These places have coordinates from the export and can be saved to your Railway-backed places.")
                    }
                }

                let review = result.reviewDrafts
                if !review.isEmpty {
                    Section {
                        ForEach(review) { draft in
                            draftRow(draft, selectable: false)
                        }
                    } header: {
                        Text("Needs review")
                    } footer: {
                        Text("These stay as review drafts because the export did not include reliable coordinates. SAV-E will not create fake pins.")
                    }
                }
            }
            .scrollContentBackground(.hidden)

            saveBar(result)
        }
    }

    private func importSummary(_ result: GoogleTakeoutImportResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.fileName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.saveInk)
                        .lineLimit(1)
                    Text("\(result.readyDrafts.count) ready · \(result.reviewDrafts.count) review drafts")
                        .font(.caption)
                        .foregroundColor(.saveMutedText)
                }

                Spacer()

                Button("Select all") {
                    selectedDraftIds = Set(readyDrafts(result).map(\.id))
                }
                .font(.caption)
                .foregroundColor(.saveCocoa)
            }

            if let saveSummary {
                Text("Saved \(saveSummary.saved). Skipped \(saveSummary.skippedDuplicates) duplicates. \(saveSummary.reviewDrafts) left for review.")
                    .font(.caption)
                    .foregroundColor(.saveMutedText)
            }

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(16)
    }

    private func draftRow(_ draft: ImportedPlaceDraft, selectable: Bool) -> some View {
        Button {
            guard selectable else { return }
            if selectedDraftIds.contains(draft.id) {
                selectedDraftIds.remove(draft.id)
            } else {
                selectedDraftIds.insert(draft.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectable ? (selectedDraftIds.contains(draft.id) ? "checkmark.circle.fill" : "circle") : "exclamationmark.triangle")
                    .foregroundColor(selectable ? .saveCocoa : .saveHoney)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.saveInk)

                    if !draft.address.isEmpty {
                        Text(draft.address)
                            .font(.caption)
                            .foregroundColor(.saveMutedText)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        Text(draft.sourceFormat.uppercased())
                        if let latitude = draft.latitude, let longitude = draft.longitude {
                            Text(String(format: "%.4f, %.4f", latitude, longitude))
                        } else if case .needsReview(let reason) = draft.reviewState {
                            Text(reason)
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.saveMutedText)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func saveBar(_ result: GoogleTakeoutImportResult) -> some View {
        VStack(spacing: 10) {
            Button {
                Task { await saveSelected(result) }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.saveInk)
                    } else {
                        Image(systemName: "tray.and.arrow.down.fill")
                    }
                    Text(isSaving ? "Saving..." : "Save selected places")
                }
                .font(.subheadline)
                .fontWeight(.black)
                .foregroundColor(selectedDraftIds.isEmpty ? .saveMutedText : .saveInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selectedDraftIds.isEmpty ? Color.saveDisabled : Color.saveHoney)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(selectedDraftIds.isEmpty ? 0.42 : 1), lineWidth: 1.6)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(selectedDraftIds.isEmpty || isSaving)
        }
        .padding(16)
        .background(Color.saveNotebookPage)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.saveNotebookLine)
                .frame(height: 2)
        }
    }

    private var allowedContentTypes: [UTType] {
        [
            .zip,
            .json,
            UTType(filenameExtension: "geojson") ?? .json,
            UTType(filenameExtension: "kml") ?? .xml,
        ]
    }

    private func readyDrafts(_ result: GoogleTakeoutImportResult) -> [ImportedPlaceDraft] {
        result.readyDrafts.filter { !existingPlaces.map(\.importDeduplicationKey).contains($0.deduplicationKey) }
    }

    private func handleFileImporter(_ response: Result<[URL], Error>) async {
        parseError = nil
        saveError = nil
        saveSummary = nil

        do {
            guard let url = try response.get().first else { return }
            isParsing = true
            defer { isParsing = false }

            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }

            let parsed = try await importService.parse(fileAt: url)
            result = parsed
            selectedDraftIds = Set(readyDrafts(parsed).map(\.id))
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func saveSelected(_ result: GoogleTakeoutImportResult) async {
        saveError = nil
        isSaving = true
        defer { isSaving = false }

        let selected = result.readyDrafts.filter { selectedDraftIds.contains($0.id) }
        do {
            let summary = try await onSave(selected)
            saveSummary = summary
            selectedDraftIds.removeAll()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
