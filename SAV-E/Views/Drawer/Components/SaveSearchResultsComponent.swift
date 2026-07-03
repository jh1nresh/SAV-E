import SwiftUI

struct SaveSearchResultsComponent: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let response: SaveSearchResponse
    var onSelectResult: (SaveSearchResult) -> Void = { _ in }
    var onSelectFollowUpChoice: (SaveSearchFollowUpChoice) -> Void = { _ in }
    var onSearchNearby: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let assistantMessage = response.assistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !assistantMessage.isEmpty {
                SaveSearchAssistantMessage(text: assistantMessage)
            }

            if !response.followUpChoices.isEmpty {
                SaveSearchFollowUpChoiceGrid(
                    choices: response.followUpChoices,
                    onSelect: onSelectFollowUpChoice
                )
            }

            if hasAssistantAnswer {
                ForEach(primaryAnswerSections) { section in
                    sectionView(section)
                }
                ForEach(contextSections) { section in
                    sectionView(section, isVisuallySecondary: true)
                }
            } else {
                ForEach(renderedSections) { section in
                    sectionView(section)
                }
            }
        }
    }

    private var renderedSections: [SaveSearchSection] {
        ([response.fromYourSave] + response.additionalSections + [response.newRecommendations])
            .filter { !$0.results.isEmpty || $0.emptyMessage != nil || $0.showsNearbySearchAction }
    }

    private var primaryAnswerSections: [SaveSearchSection] {
        response.primaryAnswerDisplaySections
    }

    private var contextSections: [SaveSearchSection] {
        response.contextDisplaySections
    }

    private var hasAssistantAnswer: Bool {
        response.assistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    @ViewBuilder
    private func sectionView(_ section: SaveSearchSection, isVisuallySecondary: Bool = false) -> some View {
        let label = sectionLabel(for: section)
        let isPublicSection = section.id.contains("public") ||
            section.id.contains("recommendation") ||
            section.label == "PUBLIC DISCOVERY"
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isPublicSection ? Color.saveSky.opacity(0.72) : Color.saveMint.opacity(0.72))
                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                    .clipShape(Capsule())

                Spacer(minLength: 0)

                Text("\(section.results.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.saveHoney)
                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.saveInk)
                Text(section.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if section.results.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text(section.emptyMessage ?? languageSettings.localized(english: "No results yet.", traditionalChinese: "目前沒有結果。"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.saveCocoa)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if section.showsNearbySearchAction {
                        Button(action: onSearchNearby) {
                            Label(
                                languageSettings.localized(english: "Search nearby unsaved candidates", traditionalChinese: "搜尋附近未保存地點"),
                                systemImage: "location.magnifyingglass"
                            )
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
        .background(Color.saveNotebookPage.opacity(isVisuallySecondary ? 0.54 : 0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    Color.saveNotebookLine.opacity(isVisuallySecondary ? 0.78 : 1),
                    lineWidth: isVisuallySecondary ? 1.4 : 2
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionLabel(for section: SaveSearchSection) -> String {
        if let label = section.label {
            switch label {
            case "FROM YOUR SAV-E":
                return languageSettings.localized(english: label, traditionalChinese: "來自你的 SAV-E")
            case "PUBLIC DISCOVERY":
                return languageSettings.localized(english: label, traditionalChinese: "公開探索")
            case "REVIEW CANDIDATES":
                return languageSettings.localized(english: label, traditionalChinese: "待確認")
            case "SAVED, FAR":
                return languageSettings.localized(english: label, traditionalChinese: "已保存但較遠")
            default:
                return label
            }
        }

        if section.id.hasPrefix("from-your-save") {
            return languageSettings.localized(english: "FROM YOUR SAV-E", traditionalChinese: "來自你的 SAV-E")
        }
        return languageSettings.localized(english: "PUBLIC DISCOVERY", traditionalChinese: "公開探索")
    }
}

struct SaveSearchFollowUpChoiceGrid: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    var title: String? = nil
    let choices: [SaveSearchFollowUpChoice]
    var onSelect: (SaveSearchFollowUpChoice) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "square.grid.2x2")
                    .font(.caption.weight(.bold))
                Text(title ?? languageSettings.localized(english: "Narrow with one tap", traditionalChinese: "點一下繼續縮小"))
                    .font(.caption.weight(.bold))
                Spacer(minLength: 0)
            }
            .foregroundColor(.saveCocoa.opacity(0.82))

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(choices) { choice in
                    Button {
                        onSelect(choice)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: choice.systemImage)
                                .font(.caption.weight(.bold))
                                .frame(width: 18, height: 18)
                            Text(choice.label)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Color.saveHoney.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.label)
                }
            }
        }
        .padding(12)
        .background(Color.saveNotebookPage.opacity(0.66))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.82), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SaveSearchAssistantMessage: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.saveInk)
                .frame(width: 34, height: 34)
                .background(Color.saveMint.opacity(0.82))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1.1))

            VStack(alignment: .leading, spacing: 4) {
                Text(languageSettings.localized(english: "SAV-E answer", traditionalChinese: "SAV-E 回答"))
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.saveCocoa)
                    .textCase(.uppercase)

                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
    @Environment(\.appLanguageSettings) private var languageSettings
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
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.saveInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(result.subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.saveMutedText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: canOpenDetails ? "chevron.right" : "circle.dotted")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.saveCocoa.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
            .disabled(!canOpenDetails)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    SaveSearchStateChip(text: result.objectType.displayName(language: languageSettings.language), fill: typeFill)
                    SaveSearchStateChip(text: result.userState.displayName(language: languageSettings.language), fill: result.userState == .unsaved ? .saveSky : .saveMint)
                    if let category = result.category {
                        SaveSearchStateChip(text: category.displayName(language: languageSettings.language), fill: .saveSignal)
                    }
                }

                if hasPlaceMetadata {
                    HStack(spacing: 6) {
                        if let ratingLabel {
                            SaveSearchStateChip(text: ratingLabel, fill: .saveHoney)
                        }
                        if let reviewsLabel {
                            SaveSearchStateChip(text: reviewsLabel, fill: .saveNotebookPage)
                        }
                        if let distanceLabel = result.distanceLabel {
                            SaveSearchStateChip(text: distanceLabel, fill: .saveHoney)
                        }
                    }
                }
            }

            if let compactReason {
                Label(compactReason, systemImage: compactReasonIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.saveCocoa)
                    .lineLimit(1)
            }
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
            CachedAsyncImage(url: url) { phase in
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
            .font(.subheadline.weight(.bold))
            .foregroundColor(.saveInk)
            .frame(width: 36, height: 36)
            .background(iconFill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var compactReason: String? {
        if let placeMetadataSummary {
            return placeMetadataSummary
        }
        if result.objectType == .pendingCandidate {
            return languageSettings.localized(english: "Review before saving", traditionalChinese: "保存前請先確認")
        }
        if result.objectType == .sourceOnlyClue {
            if result.sourcePlatform == .xiaohongshu {
                return languageSettings.localized(
                    english: "Needs caption, screenshot, or map link",
                    traditionalChinese: "需要 caption、截圖或地圖連結"
                )
            }
            return languageSettings.localized(english: "Needs exact place", traditionalChinese: "需要精確地點")
        }
        if result.objectType == .mapVisibleUnsavedPlace {
            return languageSettings.localized(english: "Public result, not saved yet", traditionalChinese: "公開結果，尚未保存")
        }
        return nil
    }

    private var hasPlaceMetadata: Bool {
        ratingLabel != nil || reviewsLabel != nil || result.distanceLabel != nil
    }

    private var ratingLabel: String? {
        result.rating.map { String(format: "★ %.1f", $0) }
    }

    private var reviewsLabel: String? {
        guard let reviewCount = result.reviewCount else { return nil }
        let compactCount = reviewCount >= 1_000
            ? String(format: "%.1fk", Double(reviewCount) / 1_000)
            : "\(reviewCount)"
        return languageSettings.localized(
            english: "\(compactCount) reviews",
            traditionalChinese: "\(compactCount) 則評論"
        )
    }

    private var placeMetadataSummary: String? {
        let parts = [ratingLabel, reviewsLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var compactReasonIcon: String {
        switch result.objectType {
        case .pendingCandidate: return "checklist.unchecked"
        case .sourceOnlyClue: return "sparkle.magnifyingglass"
        case .mapVisibleUnsavedPlace, .newRecommendation: return "location.magnifyingglass"
        default: return "location"
        }
    }

    private var canOpenDetails: Bool {
        result.objectType == .savedPlace ||
            result.objectType == .triedMemory ||
            result.objectType == .pendingCandidate ||
            result.objectType == .sourceOnlyClue ||
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
            .font(.caption2.weight(.bold))
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
        font(.caption2.weight(.bold))
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
