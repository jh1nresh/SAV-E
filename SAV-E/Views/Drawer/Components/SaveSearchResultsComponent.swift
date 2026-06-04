import SwiftUI

struct SaveSearchResultsComponent: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let response: SaveSearchResponse
    var onSelectResult: (SaveSearchResult) -> Void = { _ in }
    var onSearchNearby: () -> Void = {}
    @State private var showsSupportingPlaces = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let assistantMessage = response.assistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !assistantMessage.isEmpty {
                SaveSearchAssistantMessage(text: assistantMessage)
            }

            if hasAssistantAnswer {
                supportingPlacesDisclosure
                ForEach(separateContextSections) { section in
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

    private var saveUsedEvidenceSections: [SaveSearchSection] {
        response.saveUsedEvidenceSections
            .filter { !$0.results.isEmpty }
    }

    private var separateContextSections: [SaveSearchSection] {
        (response.farSavedSections + response.publicDiscoverySections)
            .filter { !$0.results.isEmpty || $0.emptyMessage != nil || $0.showsNearbySearchAction }
    }

    private var hasAssistantAnswer: Bool {
        response.assistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    @ViewBuilder
    private var supportingPlacesDisclosure: some View {
        if saveUsedEvidenceSections.isEmpty {
            EmptyView()
        } else {
            DisclosureGroup(isExpanded: $showsSupportingPlaces) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(saveUsedEvidenceSections) { section in
                        sectionView(section)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.caption.weight(.black))
                    Text(languageSettings.localized(english: "Show SAV-E memory used", traditionalChinese: "顯示 SAV-E 使用的記憶"))
                        .font(.caption.weight(.black))
                    Spacer(minLength: 0)
                    Text("\(supportingResultCount)")
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.saveHoney)
                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                        .clipShape(Capsule())
                }
                .foregroundColor(.saveInk)
                .padding(12)
                .background(Color.saveNotebookPage.opacity(0.68))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(0.86), lineWidth: 1.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var supportingResultCount: Int {
        saveUsedEvidenceSections.reduce(0) { $0 + $1.results.count }
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
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isPublicSection ? Color.saveSky.opacity(0.72) : Color.saveMint.opacity(0.72))
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
            default:
                return label
            }
        }

        if section.id == "from-your-save" {
            return languageSettings.localized(english: "FROM YOUR SAV-E", traditionalChinese: "來自你的 SAV-E")
        }
        return languageSettings.localized(english: "PUBLIC DISCOVERY", traditionalChinese: "公開探索")
    }
}

private struct SaveSearchAssistantMessage: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
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

            VStack(alignment: .leading, spacing: 4) {
                Text(languageSettings.localized(english: "SAV-E answer", traditionalChinese: "SAV-E 回答"))
                    .font(.caption2.weight(.black))
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
    @EnvironmentObject private var languageSettings: AppLanguageSettings
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
                SaveSearchStateChip(text: result.objectType.displayName(language: languageSettings.language), fill: typeFill)
                SaveSearchStateChip(text: result.userState.displayName(language: languageSettings.language), fill: result.userState == .unsaved ? .saveSky : .saveMint)
                if let category = result.category {
                    SaveSearchStateChip(text: category.displayName(language: languageSettings.language), fill: .saveSignal)
                }
                if let distanceLabel = result.distanceLabel {
                    SaveSearchStateChip(text: distanceLabel, fill: .saveHoney)
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

    private var compactReason: String? {
        if let distanceLabel = result.distanceLabel {
            return distanceLabel
        }
        if result.objectType == .pendingCandidate {
            return languageSettings.localized(english: "Review before saving", traditionalChinese: "保存前請先確認")
        }
        if result.objectType == .sourceOnlyClue {
            return languageSettings.localized(english: "Needs exact place", traditionalChinese: "需要精確地點")
        }
        if result.objectType == .mapVisibleUnsavedPlace {
            return languageSettings.localized(english: "Public result, not saved yet", traditionalChinese: "公開結果，尚未保存")
        }
        return nil
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
