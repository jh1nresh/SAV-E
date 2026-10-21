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
            ZStack {
                SaveDottedBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            postalHeader

                            if let result {
                                preview(result)
                            } else {
                                emptyState
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, result == nil ? 36 : 18)
                    }

                    if let result {
                        saveBar(result)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        SaveHaptics.tap()
                        dismiss()
                    }
                    .font(SaveAtlasType.strong(15))
                    .foregroundStyle(SaveAtlasPalette.forest)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        SaveHaptics.tap()
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .frame(width: 38, height: 38)
                            .background(SaveAtlasPalette.mint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(SaveAtlasPalette.forest.opacity(0.26), lineWidth: 1)
                            }
                    }
                    .disabled(isParsing || isSaving)
                    .accessibilityIdentifier("takeout.import.folder")
                }
            }
            .toolbarBackground(SaveAtlasPalette.canvas.opacity(0.96), for: .navigationBar)
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: false
            ) { response in
                Task { await handleFileImporter(response) }
            }
        }
        .accessibilityIdentifier("takeout.import.root")
    }

    private var postalHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("POSTAL IMPORT")
                    .font(SaveAtlasType.strong(11))
                    .tracking(0.8)
                    .foregroundStyle(SaveAtlasPalette.coral)

                Text("Bulk delivery")
                    .font(SaveAtlasType.strong(34, relativeTo: .largeTitle))
                    .foregroundStyle(SaveAtlasPalette.forest)

                Text("Bring historical places into Savvy without inventing coordinates.")
                    .font(SaveAtlasType.body(15))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(SaveAtlasPalette.mint)
                Circle()
                    .stroke(SaveAtlasPalette.forest.opacity(0.28), lineWidth: 1)
                Image(systemName: "shippingbox.and.arrow.backward.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(SaveAtlasPalette.forest)
            }
            .frame(width: 68, height: 68)
            .accessibilityHidden(true)
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                SavePostcardPerforatedMedallion(
                    systemName: "tray.and.arrow.down.fill",
                    tint: SaveAtlasPalette.honey,
                    edge: SaveAtlasPalette.coral
                )
                .scaleEffect(1.28)
                .frame(width: 72, height: 72)

                Text("Deliver an export")
                    .font(SaveAtlasType.strong(23, relativeTo: .title2))
                    .foregroundStyle(SaveAtlasPalette.forest)

                Text("Choose a Takeout .zip, .json, .geojson, or .kml. Saved-list links still enter through Share Sheet or link review.")
                    .font(SaveAtlasType.body(14))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    SaveHaptics.tap()
                    isFileImporterPresented = true
                } label: {
                    HStack(spacing: 9) {
                        if isParsing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "doc.badge.plus")
                        }
                        Text(isParsing ? "Reading export…" : "Choose delivery file")
                    }
                    .font(SaveAtlasType.strong(17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(SaveAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isParsing)
                .accessibilityIdentifier("takeout.import.chooseFile")
            }
            .padding(22)
            .background {
                SavePostcardScallopedRectangle(depth: 4, pitch: 12)
                    .fill(SaveAtlasPalette.paper)
            }
            .overlay {
                SavePostcardScallopedRectangle(depth: 4, pitch: 12)
                    .stroke(SaveAtlasPalette.line.opacity(0.42), lineWidth: 1)
            }

            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 0)
                    .fill(SaveAtlasPalette.honey.opacity(0.46))

                VStack(spacing: 5) {
                    Text("HISTORICAL PLACE MAIL")
                        .font(SaveAtlasType.strong(12))
                        .tracking(0.7)
                    Text("Coordinates are accepted only when the export supplies them.")
                        .font(SaveAtlasType.body(12))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(SaveAtlasPalette.ink)
                .padding(18)

                Image(systemName: "airplane")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(SaveAtlasPalette.coral.opacity(0.72))
                    .padding(16)
                    .accessibilityHidden(true)
            }
            .frame(height: 112)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22,
                    topTrailingRadius: 0
                )
            )

            Button {
                SaveHaptics.tap()
                isFileImporterPresented = true
            } label: {
                Label("Supported file types", systemImage: "info.circle")
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .padding(.top, 12)

            if let parseError {
                Text(parseError)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(Color.saveError)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
        }
        .padding(.top, 4)
    }

    private func preview(_ result: GoogleTakeoutImportResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            importSummary(result)

            let ready = readyDrafts(result)
            if !ready.isEmpty {
                postalSection(
                    title: "READY TO SAVE",
                    subtitle: "Coordinates came from the export.",
                    tint: SaveAtlasPalette.mint
                ) {
                    ForEach(ready) { draft in
                        draftRow(draft, selectable: true)
                    }
                }
            }

            let review = result.reviewDrafts
            if !review.isEmpty {
                postalSection(
                    title: "NEEDS REVIEW",
                    subtitle: "No fake pins: these drafts still need a real location.",
                    tint: SaveAtlasPalette.kraft
                ) {
                    ForEach(review) { draft in
                        draftRow(draft, selectable: false)
                    }
                }
            }
        }
    }

    private func importSummary(_ result: GoogleTakeoutImportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DELIVERY RECEIPT")
                .font(SaveAtlasType.strong(11))
                .tracking(0.75)
                .foregroundStyle(SaveAtlasPalette.coral)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.fileName)
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .lineLimit(1)
                    Text("\(result.readyDrafts.count) ready · \(result.reviewDrafts.count) review drafts")
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }

                Spacer()

                Button("Select all") {
                    SaveHaptics.select()
                    selectedDraftIds = Set(readyDrafts(result).map(\.id))
                }
                .font(SaveAtlasType.strong(12))
                .foregroundStyle(SaveAtlasPalette.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(SaveAtlasPalette.mint, in: Capsule())
            }

            if let saveSummary {
                Text("Saved \(saveSummary.saved). Skipped \(saveSummary.skippedDuplicates) duplicates. \(saveSummary.reviewDrafts) left for review.")
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }

            if let saveError {
                Text(saveError)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(Color.saveError)
            }
        }
        .padding(16)
        .background(SaveAtlasPalette.paper.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.36), lineWidth: 1)
        }
        .accessibilityIdentifier("takeout.import.summary")
    }

    private func postalSection<Content: View>(
        title: String,
        subtitle: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SaveAtlasType.strong(13))
                        .tracking(0.65)
                        .foregroundStyle(SaveAtlasPalette.forest)
                    Text(subtitle)
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }
                Spacer()
                Circle()
                    .fill(tint)
                    .frame(width: 12, height: 12)
            }

            VStack(spacing: 10) {
                content()
            }
        }
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
                SavePostcardPerforatedMedallion(
                    systemName: selectable
                        ? (selectedDraftIds.contains(draft.id) ? "checkmark" : "mappin")
                        : "questionmark",
                    tint: selectable ? SaveAtlasPalette.mint : SaveAtlasPalette.kraft,
                    edge: selectable ? SaveAtlasPalette.forest : SaveAtlasPalette.coral
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.name)
                        .font(SaveAtlasType.strong(16))
                        .foregroundStyle(SaveAtlasPalette.forest)

                    if !draft.address.isEmpty {
                        Text(draft.address)
                            .font(SaveAtlasType.body(12))
                            .foregroundStyle(SaveAtlasPalette.muted)
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
                    .font(SaveAtlasType.body(10))
                    .foregroundStyle(SaveAtlasPalette.muted)
                }

                Spacer(minLength: 4)

                if selectable {
                    Text(selectedDraftIds.contains(draft.id) ? "SELECTED" : "SELECT")
                        .font(SaveAtlasType.strong(10))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(SaveAtlasPalette.mint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(14)
            .background {
                SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                    .fill(SaveAtlasPalette.paper)
            }
            .overlay {
                SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                    .stroke(
                        (selectable ? SaveAtlasPalette.forest : SaveAtlasPalette.coral).opacity(0.46),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .accessibilityIdentifier("takeout.import.draft.\(draft.id.uuidString)")
    }

    private func saveBar(_ result: GoogleTakeoutImportResult) -> some View {
        VStack(spacing: 0) {
            Button {
                SaveHaptics.stamp()
                Task { await saveSelected(result) }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    Text(isSaving ? "Saving…" : "Accept delivery")
                }
                .font(SaveAtlasType.strong(18))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .background(
                    selectedDraftIds.isEmpty
                        ? SaveAtlasPalette.coral.opacity(0.42)
                        : SaveAtlasPalette.coral,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedDraftIds.isEmpty || isSaving)
            .accessibilityIdentifier("takeout.import.save")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(SaveAtlasPalette.canvas.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SaveAtlasPalette.line.opacity(0.28))
                .frame(height: 1)
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
