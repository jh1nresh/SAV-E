import SwiftUI

struct SaveSearchResultsComponent: View {
    let response: SaveSearchResponse
    var onSelectResult: (SaveSearchResult) -> Void = { _ in }
    var onSearchNearby: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let assistantMessage = response.assistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !assistantMessage.isEmpty {
                SaveSearchAssistantMessage(text: assistantMessage)
            }

            ForEach(renderedSections) { section in
                sectionView(section)
            }
        }
    }

    private var renderedSections: [SaveSearchSection] {
        ([response.fromYourSave] + response.additionalSections + [response.newRecommendations])
            .filter { !$0.results.isEmpty || $0.emptyMessage != nil || $0.showsNearbySearchAction }
    }

    @ViewBuilder
    private func sectionView(_ section: SaveSearchSection) -> some View {
        let label = section.label ?? (section.id == "from-your-save" ? "FROM YOUR SAV-E" : "NEW / UNSAVED")
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(label.contains("UNSAVED") ? Color.saveSky.opacity(0.72) : Color.saveMint.opacity(0.72))
                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                    .clipShape(Capsule())

                Spacer(minLength: 0)

                Text("\(section.results.count)")
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.saveHoney)
                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.headline.weight(.black))
                    .foregroundColor(.saveInk)
                Text(section.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if section.results.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text(section.emptyMessage ?? "No results yet.")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.saveCocoa)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if section.showsNearbySearchAction {
                        Button(action: onSearchNearby) {
                            Label("Search nearby unsaved candidates", systemImage: "location.magnifyingglass")
                                .saveSearchActionPill(isPrimary: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.saveNotebookPage.opacity(0.50))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(section.results) { result in
                        SaveSearchResultNotebookRow(result: result, onSelectResult: onSelectResult)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.saveNotebookPage.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SaveSearchAssistantMessage: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 34, height: 34)
                .background(Color.saveMint.opacity(0.82))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1.1))

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.saveNotebookPage.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.9), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SaveSearchResultNotebookRow: View {
    let result: SaveSearchResult
    var onSelectResult: (SaveSearchResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                onSelectResult(result)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    resultThumbnail

                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.title)
                            .font(.subheadline.weight(.black))
                            .foregroundColor(.saveInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(result.subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.saveMutedText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: canOpenDetails ? "chevron.right" : "circle.dotted")
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveCocoa.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
            .disabled(!canOpenDetails)

            HStack(spacing: 6) {
                SaveSearchStateChip(text: result.objectType.displayName, fill: typeFill)
                SaveSearchStateChip(text: result.userState.displayName, fill: result.userState == .unsaved ? .saveSky : .saveMint)
                if let category = result.category {
                    SaveSearchStateChip(text: category.displayName, fill: .saveSignal)
                }
                if let distanceLabel = result.distanceLabel {
                    SaveSearchStateChip(text: distanceLabel, fill: .saveHoney)
                }
            }

            if !result.evidence.isEmpty || !result.missingInfo.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(result.evidence.prefix(3)), id: \.self) { evidence in
                        Label(evidence, systemImage: "doc.text.magnifyingglass")
                            .lineLimit(2)
                    }
                    if !result.missingInfo.isEmpty {
                        Label("Missing: \(result.missingInfo.prefix(2).joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                            .lineLimit(2)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
            }

            primaryActionLabel
            shareLink
        }
        .padding(12)
        .background(Color.saveCream.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var resultThumbnail: some View {
        if result.objectType == .mapVisibleUnsavedPlace,
           let url = result.businessPhotoURLStrings.first.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackIcon
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.5)
            )
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: iconName)
            .font(.subheadline.weight(.black))
            .foregroundColor(.saveInk)
            .frame(width: 36, height: 36)
            .background(iconFill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var shareLink: some View {
        if let url = result.saveShareURL {
            ShareLink(item: url, subject: Text(result.shareSubject), message: Text(result.shareText)) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .saveSearchActionPill(isPrimary: false)
            }
        } else {
            ShareLink(item: result.shareText, subject: Text(result.shareSubject)) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .saveSearchActionPill(isPrimary: false)
            }
        }
    }

    @ViewBuilder
    private var primaryActionLabel: some View {
        switch result.objectType {
        case .savedPlace, .triedMemory:
            Label("Open Map Stamp", systemImage: "map.fill")
                .saveSearchActionPill(isPrimary: true)
        case .pendingCandidate:
            Label("Needs confirmation", systemImage: "checklist.unchecked")
                .saveSearchActionPill(isPrimary: false)
        case .sourceOnlyClue:
            Label("Needs exact place", systemImage: "sparkle.magnifyingglass")
                .saveSearchActionPill(isPrimary: false)
        case .mapVisibleUnsavedPlace:
            Label("Unsaved candidate", systemImage: "bookmark.badge.plus")
                .saveSearchActionPill(isPrimary: false)
        case .newRecommendation:
            Label("Recommendation only", systemImage: "sparkle.magnifyingglass")
                .saveSearchActionPill(isPrimary: false)
        case .review:
            Label("View review evidence", systemImage: "text.bubble")
                .saveSearchActionPill(isPrimary: false)
        case .tripStop:
            Label("Use trip stop", systemImage: "route")
                .saveSearchActionPill(isPrimary: false)
        }
    }

    private var canOpenDetails: Bool {
        result.objectType == .savedPlace ||
            result.objectType == .triedMemory ||
            result.objectType == .mapVisibleUnsavedPlace
    }

    private var iconName: String {
        switch result.objectType {
        case .savedPlace: return "map.fill"
        case .pendingCandidate: return "checklist.unchecked"
        case .sourceOnlyClue: return "link"
        case .triedMemory: return "checkmark.seal.fill"
        case .review: return "text.bubble.fill"
        case .tripStop: return "route.fill"
        case .mapVisibleUnsavedPlace: return "mappin.and.ellipse"
        case .newRecommendation: return "sparkle.magnifyingglass"
        }
    }

    private var iconFill: Color {
        switch result.objectType {
        case .savedPlace, .triedMemory: return .saveMint
        case .pendingCandidate, .sourceOnlyClue: return .saveHoney
        case .review, .mapVisibleUnsavedPlace: return .saveSignal
        case .tripStop: return .saveSky
        case .newRecommendation: return .saveSky.opacity(0.72)
        }
    }

    private var typeFill: Color {
        switch result.objectType {
        case .savedPlace, .triedMemory: return .saveMint
        case .pendingCandidate, .sourceOnlyClue: return .saveHoney
        case .mapVisibleUnsavedPlace, .newRecommendation: return .saveSky
        case .review, .tripStop: return .saveSignal
        }
    }
}

private struct SaveSearchStateChip: View {
    let text: String
    let fill: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.black))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fill.opacity(0.82))
            .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1.1))
            .clipShape(Capsule())
    }
}

private extension View {
    func saveSearchActionPill(isPrimary: Bool) -> some View {
        font(.caption2.weight(.black))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isPrimary ? Color.saveHoney : Color.saveNotebookPage)
            .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1.1))
            .clipShape(Capsule())
    }
}
