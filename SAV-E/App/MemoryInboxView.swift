import SwiftUI

struct SaveInboxSnapshot {
    let needsReview: [PlaceReviewCandidate]
    let sourceOnly: [PlaceReviewCandidate]
    let recentPlaces: [Place]

    init(
        reviewCandidates: [PlaceReviewCandidate],
        places: [Place],
        recentPlaceLimit: Int = 8
    ) {
        needsReview = reviewCandidates
            .filter { $0.status != "source_only" }
            .sorted { $0.createdAt > $1.createdAt }
        sourceOnly = reviewCandidates
            .filter { $0.status == "source_only" }
            .sorted { $0.createdAt > $1.createdAt }
        recentPlaces = Array(
            places
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(max(0, recentPlaceLimit))
        )
    }
}

struct MemoryInboxView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let places: [Place]
    let reviewCandidates: [PlaceReviewCandidate]
    let isLoading: Bool
    let onOpenCandidate: (PlaceReviewCandidate) -> Void
    let onOpenPlace: (Place) -> Void
    let onOpenMap: () -> Void
    let onAsk: () -> Void
    let onCapture: () -> Void

    private var snapshot: SaveInboxSnapshot {
        SaveInboxSnapshot(reviewCandidates: reviewCandidates, places: places)
    }

    var body: some View {
        ZStack {
            inboxBackground
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header
                    captureButton
                    statusStrip

                    if isLoading && places.isEmpty && reviewCandidates.isEmpty {
                        loadingState
                    } else {
                        reviewSections
                        recentPlacesSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .frame(maxWidth: 960, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomNavigation
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("memory-inbox-root")
    }

    private var inboxBackground: Color {
        colorScheme == .dark ? Color(hex: "111318") : Color(hex: "F5F6F7")
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "1C2027") : .white
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : Color(hex: "17181A")
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.66) : Color(hex: "666A70")
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            MemoMascotMark(size: 44)

            VStack(alignment: .leading, spacing: 1) {
                Text("SAV-E")
                    .font(.title3.weight(.black))
                    .foregroundStyle(primaryText)
                Text(languageSettings.localized(
                    english: "Memory Inbox",
                    traditionalChinese: "記憶收件匣"
                ))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(secondaryText)
            }

            Spacer()

            Button(action: onAsk) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(primaryText)
                    .frame(width: 44, height: 44)
                    .background(cardBackground)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(dividerColor, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageSettings.localized(english: "Ask SAV-E", traditionalChinese: "詢問 SAV-E"))
            .accessibilityIdentifier("memory-inbox-header-ask")
        }
    }

    private var captureButton: some View {
        Button(action: onCapture) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "17181A"))
                    .frame(width: 34, height: 34)
                    .background(Color.saveHoney)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(languageSettings.localized(
                    english: "Add a link or note",
                    traditionalChinese: "加入連結或筆記"
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryText)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 56)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(dividerColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("memory-inbox-add")
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            InboxMetric(
                value: snapshot.needsReview.count,
                label: languageSettings.localized(english: "Review", traditionalChinese: "待確認"),
                color: .saveCoral,
                foreground: primaryText,
                secondary: secondaryText
            )
            InboxMetric(
                value: snapshot.sourceOnly.count,
                label: languageSettings.localized(english: "Sources", traditionalChinese: "來源"),
                color: .saveSky,
                foreground: primaryText,
                secondary: secondaryText
            )
            InboxMetric(
                value: places.count,
                label: languageSettings.localized(english: "Stamps", traditionalChinese: "地圖章"),
                color: .saveMint,
                foreground: primaryText,
                secondary: secondaryText
            )
        }
    }

    @ViewBuilder
    private var reviewSections: some View {
        if snapshot.needsReview.isEmpty && snapshot.sourceOnly.isEmpty {
            InboxEmptyReviewState(
                foreground: primaryText,
                secondary: secondaryText,
                background: cardBackground,
                border: dividerColor,
                action: onCapture
            )
        } else {
            if !snapshot.needsReview.isEmpty {
                candidateSection(
                    title: languageSettings.localized(english: "Needs Review", traditionalChinese: "需要確認"),
                    count: snapshot.needsReview.count,
                    candidates: snapshot.needsReview,
                    sourceOnly: false
                )
            }

            if !snapshot.sourceOnly.isEmpty {
                candidateSection(
                    title: languageSettings.localized(english: "Saved Sources", traditionalChinese: "已保存來源"),
                    count: snapshot.sourceOnly.count,
                    candidates: snapshot.sourceOnly,
                    sourceOnly: true
                )
            }
        }
    }

    private func candidateSection(
        title: String,
        count: Int,
        candidates: [PlaceReviewCandidate],
        sourceOnly: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: title, count: count)

            VStack(spacing: 0) {
                ForEach(Array(candidates.prefix(5).enumerated()), id: \.element.id) { index, candidate in
                    Button {
                        onOpenCandidate(candidate)
                    } label: {
                        InboxCandidateRow(
                            candidate: candidate,
                            sourceOnly: sourceOnly,
                            foreground: primaryText,
                            secondary: secondaryText
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("memory-inbox-candidate-\(candidate.id.uuidString)")

                    if index < min(candidates.count, 5) - 1 {
                        Divider()
                            .overlay(dividerColor)
                            .padding(.leading, 60)
                    }
                }
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(dividerColor, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var recentPlacesSection: some View {
        if !snapshot.recentPlaces.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: languageSettings.localized(english: "Recent Map Stamps", traditionalChinese: "最近的地圖章"),
                    count: places.count
                )

                LazyVGrid(
                    columns: recentPlaceColumns,
                    spacing: 10
                ) {
                    ForEach(snapshot.recentPlaces) { place in
                        Button {
                            onOpenPlace(place)
                        } label: {
                            InboxPlaceCard(
                                place: place,
                                foreground: primaryText,
                                secondary: secondaryText,
                                background: cardBackground,
                                border: dividerColor
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("memory-inbox-place-\(place.id.uuidString)")
                    }
                }
            }
        }
    }

    private var recentPlaceColumns: [GridItem] {
        let minimumWidth: CGFloat = horizontalSizeClass == .regular ? 190 : 148
        return [GridItem(.adaptive(minimum: minimumWidth, maximum: 240), spacing: 10)]
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(primaryText)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryText)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(languageSettings.localized(english: "Loading your memory", traditionalChinese: "正在載入你的記憶"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var bottomNavigation: some View {
        HStack(spacing: 0) {
            InboxNavigationButton(
                title: languageSettings.localized(english: "Inbox", traditionalChinese: "收件匣"),
                systemImage: "tray.full.fill",
                selected: true,
                action: {}
            )
            .accessibilityIdentifier("memory-inbox-tab")

            InboxNavigationButton(
                title: languageSettings.localized(english: "Map", traditionalChinese: "地圖"),
                systemImage: "map",
                selected: false,
                action: onOpenMap
            )
            .accessibilityIdentifier("memory-inbox-map")

            InboxNavigationButton(
                title: languageSettings.localized(english: "Ask", traditionalChinese: "詢問"),
                systemImage: "sparkles",
                selected: false,
                action: onAsk
            )
            .accessibilityIdentifier("memory-inbox-ask")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
        }
    }
}

private struct InboxMetric: View {
    let value: Int
    let label: String
    let color: Color
    let foreground: Color
    let secondary: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text("\(value)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(foreground)
            }
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(minHeight: 66)
        .background(color.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InboxCandidateRow: View {
    @Environment(\.appLanguageSettings) private var languageSettings

    let candidate: PlaceReviewCandidate
    let sourceOnly: Bool
    let foreground: Color
    let secondary: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(statusColor.opacity(0.18))
                PlatformIcon(platform: sourcePlatform, size: 19)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(candidate.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(foreground)
                        .lineLimit(1)

                    Text(statusLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(foreground.opacity(0.78))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.20))
                        .clipShape(Capsule())
                }

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(secondary.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    private var sourcePlatform: SourcePlatform {
        SourcePlatform.from(urlString: sourceURLString)
    }

    private var sourceURLString: String? {
        for line in candidate.evidence {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let range = trimmed.range(of: "Source URL:", options: .caseInsensitive) else { continue }
            let value = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private var statusColor: Color {
        sourceOnly ? .saveSky : .saveCoral
    }

    private var statusLabel: String {
        sourceOnly
            ? languageSettings.localized(english: "SOURCE", traditionalChinese: "來源")
            : languageSettings.localized(english: "REVIEW", traditionalChinese: "確認")
    }

    private var detailText: String {
        if !candidate.address.isEmpty { return candidate.address }
        if let city = candidate.city, !city.isEmpty { return city }
        if let missing = candidate.missingInfo.first, !missing.isEmpty { return missing }
        return languageSettings.localized(
            english: "Needs another clue",
            traditionalChinese: "還需要一個線索"
        )
    }
}

private struct InboxPlaceCard: View {
    let place: Place
    let foreground: Color
    let secondary: Color
    let background: Color
    let border: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            placeImage
                .aspectRatio(1.45, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: place.category.iconName)
                        .font(.caption2.weight(.bold))
                    Text(place.category.displayName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(secondary)

                Text(place.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(foreground)
                    .lineLimit(2)
                    .frame(minHeight: 38, alignment: .topLeading)
            }
            .padding(10)
        }
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var placeImage: some View {
        if let url = place.businessPhotoURLStrings.first.flatMap(URL.init(string:)) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    imagePlaceholder
                }
            }
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        ZStack {
            Color.categoryColor(for: place.category).opacity(0.18)
            Image(systemName: place.category.iconName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.saveInk.opacity(0.72))
        }
    }
}

private struct InboxEmptyReviewState: View {
    @Environment(\.appLanguageSettings) private var languageSettings

    let foreground: Color
    let secondary: Color
    let background: Color
    let border: Color
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Color.saveMint)

            VStack(alignment: .leading, spacing: 3) {
                Text(languageSettings.localized(english: "Inbox clear", traditionalChinese: "收件匣已清空"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(foreground)
                Text(languageSettings.localized(english: "No places waiting for your decision", traditionalChinese: "目前沒有等待你確認的地點"))
                    .font(.caption)
                    .foregroundStyle(secondary)
            }

            Spacer()

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(foreground)
                    .frame(width: 36, height: 36)
                    .background(Color.saveHoney.opacity(0.82))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageSettings.localized(english: "Add a link", traditionalChinese: "加入連結"))
        }
        .padding(14)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
    }
}

private struct InboxNavigationButton: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: selected ? .bold : .medium))
                Text(title)
                    .font(.caption2.weight(selected ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.saveInk : Color.saveMutedText)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MemoryInboxView(
        places: ReviewDemoSeed.places(),
        reviewCandidates: [],
        isLoading: false,
        onOpenCandidate: { _ in },
        onOpenPlace: { _ in },
        onOpenMap: {},
        onAsk: {},
        onCapture: {}
    )
    .environment(\.appLanguageSettings, AppLanguageSettings())
}
