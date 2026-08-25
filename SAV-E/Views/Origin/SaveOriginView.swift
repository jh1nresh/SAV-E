import SwiftUI

struct SaveOriginCapture: Identifiable, Hashable {
    let id: UUID
    let sourceURL: String?
    let rawText: String?
    let title: String?
    let createdAt: Date

    var originalURL: URL? {
        guard let sourceURL,
              let url = URL(string: sourceURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              url.host != nil
        else { return nil }
        return url
    }

    var hasDisplayableSource: Bool {
        rawText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || originalURL != nil
    }
}

struct SaveOriginView: View {
    let captures: [SaveOriginCapture]
    let sourceCandidates: [PlaceReviewCandidate]
    let reviewCandidates: [PlaceReviewCandidate]
    let isLoading: Bool
    let loadError: String?
    let onRefresh: () async -> Void
    let onPlanCandidate: (PlaceReviewCandidate) -> Void
    let onArchiveCandidate: (PlaceReviewCandidate) async throws -> Void
    let onOpenPassport: () -> Void

    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var workingCandidateID: UUID?
    @State private var actionError: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            BrandHeader {
                EmptyView()
            }
            .placed(x: 0, y: 48, width: AtlasMetrics.width, height: 51)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    heading

                    sectionLabel(localized("YOUR SOURCES", "你的來源"), count: visibleCaptures.count)
                    sourceContent

                    if !activeCandidates.isEmpty {
                        sectionLabel(localized("TO REVIEW", "待處理"), count: activeCandidates.count)
                        ForEach(activeCandidates) { candidate in
                            backlogCard(candidate)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 112)
            }
            .placed(x: 0, y: 105, width: AtlasMetrics.width, height: 681)
        }
        .frame(width: AtlasMetrics.width, height: AtlasMetrics.height)
        .environment(\.atlasPresentation, atlasPresentation)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("origin.root")
        .task { await onRefresh() }
        .alert(
            localized("Couldn’t finish that action", "無法完成這個動作"),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button(languageSettings.text(.ok)) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("YOUR PLACE MEMORY", "你的地點記憶"))
                .font(AtlasType.body(11))
                .tracking(1.1)
                .foregroundStyle(SaveAtlasPalette.muted)
            Text(localized("Origin", "來處"))
                .font(AtlasType.display(34))
                .foregroundStyle(SaveAtlasPalette.forest)
            Text(localized(
                "The links and exact words your saved places came from.",
                "保留每個地點原本的連結與文字。"
            ))
            .font(AtlasType.body(15))
            .foregroundStyle(SaveAtlasPalette.muted)
        }
    }

    @ViewBuilder
    private var sourceContent: some View {
        if isLoading && visibleCaptures.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text(localized("Loading your sources…", "正在載入你的來源⋯"))
                    .font(AtlasType.body(14))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .accessibilityIdentifier("origin.loading")
        } else if let loadError, visibleCaptures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(localized("Sources couldn’t load.", "無法載入來源。"))
                    .font(AtlasType.display(17))
                    .foregroundStyle(SaveAtlasPalette.ink)
                Text(loadError)
                    .font(AtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                Button(localized("Try again", "再試一次")) {
                    Task { await onRefresh() }
                }
                .buttonStyle(.bordered)
            }
            .originCardStyle()
            .accessibilityIdentifier("origin.loadError")
        } else if visibleCaptures.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "paperclip")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(SaveAtlasPalette.coral)
                Text(localized("No source saved yet", "還沒有來源"))
                    .font(AtlasType.display(18))
                    .foregroundStyle(SaveAtlasPalette.ink)
                Text(localized(
                    "New links and notes will collect here from now on. Older saves are not guessed.",
                    "之後新增的連結與筆記會收在這裡；既有收藏不會被猜測補齊。"
                ))
                .font(AtlasType.body(13))
                .foregroundStyle(SaveAtlasPalette.muted)
            }
            .originCardStyle()
            .accessibilityIdentifier("origin.empty")
        } else {
            ForEach(visibleCaptures) { capture in
                sourceCard(capture)
            }
        }
    }

    private func sourceCard(_ capture: SaveOriginCapture) -> some View {
        let related = candidatesByCapture[capture.id] ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(capture.title?.trimmingCharacters(in: .whitespacesAndNewlines).originNonEmpty
                     ?? localized("Saved source", "已儲存來源"))
                    .font(AtlasType.display(17))
                    .foregroundStyle(SaveAtlasPalette.ink)
                Spacer(minLength: 8)
                Text(capture.createdAt, style: .date)
                    .font(AtlasType.body(11))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }

            if let rawText = capture.rawText,
               !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(rawText)
                    .font(AtlasType.body(14))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(SaveAtlasPalette.coral.opacity(0.68))
                            .frame(width: 3)
                    }
                    .accessibilityIdentifier("origin.source.verbatim")
            }

            if !related.isEmpty {
                Text(related.map(\.name).joined(separator: " · "))
                    .font(AtlasType.display(12))
                    .foregroundStyle(SaveAtlasPalette.forest)
            }

            if let url = capture.originalURL {
                Link(destination: url) {
                    Label(localized("Open original", "開啟原始連結"), systemImage: "arrow.up.right")
                        .font(AtlasType.display(13))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("origin.source.open")
            }
        }
        .originCardStyle()
        .accessibilityIdentifier("origin.source.\(capture.id.uuidString)")
    }

    private func backlogCard(_ candidate: PlaceReviewCandidate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(candidate.name)
                .font(AtlasType.display(18))
                .foregroundStyle(SaveAtlasPalette.ink)
            if !candidate.address.isEmpty {
                Text(candidate.address)
                    .font(AtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }

            HStack(spacing: 10) {
                Button {
                    onPlanCandidate(candidate)
                } label: {
                    Label(localized("Plan it", "排入行程"), systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SaveAtlasPalette.forest)
                .disabled(workingCandidateID != nil)
                .accessibilityIdentifier("origin.backlog.plan.\(candidate.id.uuidString)")

                Button(role: .destructive) {
                    archive(candidate)
                } label: {
                    if workingCandidateID == candidate.id {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        Label(localized("Archive", "封存"), systemImage: "archivebox")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(workingCandidateID != nil)
                .accessibilityIdentifier("origin.backlog.archive.\(candidate.id.uuidString)")
            }
        }
        .originCardStyle()
        .accessibilityIdentifier("origin.backlog.\(candidate.id.uuidString)")
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text("\(count)")
                .foregroundStyle(SaveAtlasPalette.coral)
        }
        .font(AtlasType.body(11))
        .tracking(1.05)
        .foregroundStyle(SaveAtlasPalette.muted)
        .padding(.top, 4)
    }

    private var visibleCaptures: [SaveOriginCapture] {
        captures.filter(\.hasDisplayableSource)
    }

    private var activeCandidates: [PlaceReviewCandidate] {
        reviewCandidates.filter { $0.status == "review" || $0.status == "needs_more_evidence" }
    }

    private var candidatesByCapture: [UUID: [PlaceReviewCandidate]] {
        Dictionary(grouping: sourceCandidates.compactMap { candidate in
            candidate.captureId.map { ($0, candidate) }
        }, by: { $0.0 }).mapValues { pairs in
            pairs.map { $0.1 }
        }
    }

    private var atlasPresentation: AtlasPresentation {
        var presentation = AtlasPresentation.reference
        presentation.onOpenPassport = onOpenPassport
        return presentation
    }

    private func archive(_ candidate: PlaceReviewCandidate) {
        workingCandidateID = candidate.id
        Task {
            defer { workingCandidateID = nil }
            do {
                try await onArchiveCandidate(candidate)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.language.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private extension View {
    func originCardStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SaveAtlasPalette.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SaveAtlasPalette.line.opacity(0.42), lineWidth: 1)
            }
            .shadow(color: SaveAtlasPalette.ink.opacity(0.04), radius: 5, y: 2)
    }
}

private extension String {
    var originNonEmpty: String? { isEmpty ? nil : self }
}
