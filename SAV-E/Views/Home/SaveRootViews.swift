import SwiftUI

struct SaveHomeView: View {
    @ObservedObject var store: TripPackStore
    @ObservedObject var mapViewModel: MapViewModel
    let onCapture: () -> Void
    let onOpenSavedPlace: (Place) -> Void
    let onOpenSaves: () -> Void
    let onOpenTrips: () -> Void
    let onOpenTrip: (UUID) -> Void
    let onOpenPassport: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        HomeAtlasScreen()
        .environment(\.atlasPresentation, atlasPresentation)
        .task(id: missingPhotoPlaceIDs) {
            guard !ReviewDemo.isOfflineUITestMode else { return }
            await mapViewModel.enrichMissingHomePlacePhotos()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.root")
    }

    private var missingPhotoPlaceIDs: [UUID] {
        mapViewModel.places
            .filter { $0.businessPhotoURLStrings.isEmpty }
            .prefix(6)
            .map(\.id)
    }

    private var atlasPresentation: AtlasPresentation {
        var presentation = SaveAtlasPresentationFactory.root(
            store: store,
            mapViewModel: mapViewModel,
            onCapture: onCapture,
            onReviewAll: onOpenSaves,
            onOpenTrip: onOpenTrip,
            onOpenTrips: onOpenTrips,
            onOpenSaves: onOpenSaves,
            onOpenPlace: onOpenSavedPlace,
            onOpenReview: { _ in onOpenSaves() },
            onOpenPassport: onOpenPassport
        )
        if !SaveAtlasRuntime.usesParityFixture {
            presentation.tripsBetaLabel = languageSettings.localized(
                english: "BETA",
                traditionalChinese: "測試版"
            )
        }
        return presentation
    }
}

struct SaveLibraryView: View {
    let places: [Place]
    let reviewCandidates: [PlaceReviewCandidate]
    let onOpenCapture: () -> Void
    let onOpenReviewCandidate: (PlaceReviewCandidate) -> Void
    let onOpenSavedPlace: (Place) -> Void
    let onOpenPassport: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedMode: SaveLibraryMode?

    var body: some View {
        Group {
            if SaveAtlasRuntime.usesParityFixture {
                SavesPocketScreen()
                    .environment(\.atlasPresentation, atlasPresentation)
            } else {
                // Pushed outside ReferenceViewport (#157): real safe area +
                // system back chrome already apply. Do not re-add the old
                // root-tab status-bar band or the header sits too low.
                savesContent
            }
        }
        // ContentView shows the navigation bar for back + "Saves"/"收藏".
        // Hiding it here fought that chrome and left a brand header with no
        // back control when the child's toolbar modifier won.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saves.root")
    }

    private var atlasPresentation: AtlasPresentation {
        SaveAtlasPresentationFactory.library(
            places: places,
            candidates: reviewCandidates,
            onCapture: onOpenCapture,
            onReviewAll: {
                selectedMode = .review
            },
            onOpenPlace: onOpenSavedPlace,
            onOpenReview: onOpenReviewCandidate,
            onSelectReview: {
                selectedMode = .review
            },
            onSelectMapStamps: {
                selectedMode = .mapStamps
            },
            onOpenPassport: onOpenPassport
        )
    }

    private var savesContent: some View {
        VStack(spacing: 0) {
            SaveAtlasBrandHeader(onOpenPassport: onOpenPassport) {
                Button(action: onOpenCapture) {
                    Image(systemName: "link")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            SaveAtlasPalette.coral.opacity(0.92),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(SaveAtlasPalette.line.opacity(0.38), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel(localized("Paste or share link", "貼上／分享連結"))
                .accessibilityIdentifier("root.capture")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            titleBlock
                .padding(.horizontal, 16)

            modePicker
                .padding(.horizontal, 14)
                .padding(.top, 4)

            ScrollView(showsIndicators: false) {
                Group {
                    switch effectiveMode {
                    case .review:
                        reviewContent
                    case .mapStamps:
                        savedPlacesContent
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                // No floating Atlas tab bar on this pushed route — only clear
                // the home indicator with a modest inset.
                .padding(.bottom, Self.pushedListBottomInset)
            }
        }
        .background(SaveDottedBackground())
    }

    private var titleBlock: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(localized("YOUR PLACE MEMORY", "你的地點記憶"))
                    .font(SaveAtlasType.strong(11))
                    .tracking(1.1)
                    .foregroundStyle(SaveAtlasPalette.muted)
                // Page title lives on the system navigation bar so this
                // block only carries the eyebrow + state-language subtitle.
                Text(localized(
                    "Clues you’ve saved from links and notes.",
                    "從連結與筆記留下的地點線索。"
                ))
                .font(SaveAtlasType.body(15))
                .foregroundStyle(SaveAtlasPalette.muted)
                .lineLimit(2)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
            SavePostcardMemoPeek(width: 82)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 72)
    }

    private var modePicker: some View {
        HStack(spacing: 10) {
            SaveAtlasPocketCount(
                label: localized("Review", "待確認"),
                value: reviewCandidates.count,
                tint: SaveAtlasPalette.coral.opacity(0.56),
                isSelected: effectiveMode == .review
            ) {
                withAnimation(SaveTheme.Motion.standardSpring) {
                    selectedMode = .review
                }
            }
            .accessibilityIdentifier("saves.segment.review")

            SaveAtlasPocketCount(
                label: localized("Map Stamps", "地圖章"),
                value: places.count,
                tint: SaveAtlasPalette.mint,
                isSelected: effectiveMode == .mapStamps
            ) {
                withAnimation(SaveTheme.Motion.standardSpring) {
                    selectedMode = .mapStamps
                }
            }
            .accessibilityIdentifier("saves.segment.mapStamps")
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var reviewContent: some View {
        VStack(spacing: 0) {
            if sortedCandidates.isEmpty {
                VStack(spacing: 8) {
                    MemoMascotMark(size: 72, framed: false)
                    Text(localized("No clues waiting", "沒有待確認線索"))
                        .font(SaveAtlasType.strong(21))
                        .foregroundStyle(SaveAtlasPalette.forest)
                    Text(localized(
                        "Share a link whenever you find a place worth remembering.",
                        "看到值得記住的地點時，分享連結給 Savvy。"
                    ))
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    Button(action: onOpenCapture) {
                        Label(
                            localized("Paste a link", "貼上連結"),
                            systemImage: "link.badge.plus"
                        )
                        .font(SaveAtlasType.strong(15))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(
                            SaveAtlasPalette.honey,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .saveAtlasPaper(radius: 18)
                .accessibilityIdentifier("saves.review.empty")
            } else {
                VStack(spacing: -6) {
                    ForEach(firstViewportCandidates) { candidate in
                        reviewTicket(candidate)
                    }
                }

                SavePostcardPocketFooter(
                    title: localized("Full review queue", "完整待確認佇列"),
                    subtitle: localized("Decide what is worth saving", "決定哪些值得保存"),
                    count: sortedCandidates.count,
                    countLabel: localized("need your review", "等待確認"),
                    tint: SaveAtlasPalette.coral
                )
                .padding(.top, -18)
                .zIndex(4)
                .accessibilityIdentifier("saves.pocket.reviewFooter")

                if !remainingCandidates.isEmpty {
                    VStack(spacing: -6) {
                        ForEach(remainingCandidates) { candidate in
                            reviewTicket(candidate)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    @ViewBuilder
    private var savedPlacesContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sortedPlaces.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        localized("No confirmed places yet", "還沒有已確認地點"),
                        systemImage: "mappin.slash"
                    )
                    .font(SaveAtlasType.strong(19))
                    .foregroundStyle(SaveAtlasPalette.forest)

                    Text(localized(
                        "Add a link first. Savvy keeps uncertain clues in Review instead of placing guesses on your map.",
                        "先加入連結。Savvy 會把不確定的線索留在待確認，不會把猜測直接放上地圖。"
                    ))
                    .font(SaveAtlasType.body(14))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                    Button(action: onOpenCapture) {
                        Label(localized("Paste or share link", "貼上／分享連結"), systemImage: "link.badge.plus")
                            .font(SaveAtlasType.strong(16))
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .background(
                                SaveAtlasPalette.honey,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .saveAtlasPaper(radius: 20)
            } else {
                LazyVStack(spacing: -6) {
                    ForEach(firstViewportPlaces) { place in
                        mapStampTicket(place)
                    }
                }

                SavePostcardPocketFooter(
                    title: localized("Your saved postcards", "你的收藏明信片"),
                    subtitle: localized("Confirmed Map Stamps", "已確認地圖章"),
                    count: sortedPlaces.count,
                    countLabel: localized("saved postcards", "收藏明信片"),
                    tint: SaveAtlasPalette.forest
                )
                .padding(.top, -18)
                .zIndex(4)
                .accessibilityIdentifier("saves.pocket.mapStampFooter")

                if !remainingPlaces.isEmpty {
                    LazyVStack(spacing: -6) {
                        ForEach(remainingPlaces) { place in
                            mapStampTicket(place)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    private var effectiveMode: SaveLibraryMode {
        if SaveAtlasRuntime.usesParityFixture {
            return .review
        }
        return selectedMode ?? (reviewCandidates.isEmpty ? .mapStamps : .review)
    }

    private var sortedPlaces: [Place] {
        places.sorted { $0.createdAt > $1.createdAt }
    }

    private var firstViewportPlaces: [Place] {
        Array(sortedPlaces.prefix(Self.firstViewportTicketLimit))
    }

    private var remainingPlaces: [Place] {
        Array(sortedPlaces.dropFirst(Self.firstViewportTicketLimit))
    }

    private var sortedCandidates: [PlaceReviewCandidate] {
        reviewCandidates.sorted { $0.createdAt > $1.createdAt }
    }

    private var firstViewportCandidates: [PlaceReviewCandidate] {
        Array(sortedCandidates.prefix(Self.firstViewportTicketLimit))
    }

    private var remainingCandidates: [PlaceReviewCandidate] {
        Array(sortedCandidates.dropFirst(Self.firstViewportTicketLimit))
    }

    private static let firstViewportTicketLimit = 3
    /// Bottom inset for the pushed Saves list. Must stay well below the old
    /// root-tab clearance (108) so tickets are not stranded above empty space.
    private static let pushedListBottomInset: CGFloat = 24

    private func reviewTicket(_ candidate: PlaceReviewCandidate) -> some View {
        Button {
            onOpenReviewCandidate(candidate)
        } label: {
            SaveAtlasReviewTicket(
                candidate: candidate,
                detail: candidateDetail(candidate),
                kind: candidateKind(candidate),
                actionTitle: candidateActionTitle(candidate)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(candidateKindTitle(candidate)), \(candidate.name), \(candidateDetail(candidate))"
        )
        .accessibilityHint(localized(
            "Open this clue in Review",
            "在待確認中打開這個線索"
        ))
        .accessibilityIdentifier("saves.reviewCandidate.\(candidate.id.uuidString)")
    }

    private func mapStampTicket(_ place: Place) -> some View {
        Button {
            onOpenSavedPlace(place)
        } label: {
            SaveAtlasMapStampTicket(place: place)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("saves.place.\(place.id.uuidString)")
    }

    private func candidateKind(_ candidate: PlaceReviewCandidate) -> SaveAtlasReviewTicketKind {
        candidate.status == "source_only" || !candidate.hasReliableCoordinates
            ? .sourceClue
            : .reviewCandidate
    }

    private func candidateActionTitle(_ candidate: PlaceReviewCandidate) -> String {
        candidateKind(candidate) == .sourceClue
            ? localized("Find exact", "找出地點")
            : localized("Review", "確認")
    }

    private func candidateKindTitle(_ candidate: PlaceReviewCandidate) -> String {
        candidateKind(candidate) == .sourceClue
            ? localized("Source Clue", "來源線索")
            : localized("Review Candidate", "待確認地點")
    }

    private func candidateDetail(_ candidate: PlaceReviewCandidate) -> String {
        if candidateKind(candidate) == .sourceClue {
            return localized("Missing exact place", "缺少精確地點")
        }

        let source = ReviewSourceReceiptPresentation(candidate: candidate)
        if let handle = candidate.sourceHandle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !handle.isEmpty {
            return localized("From \(handle)", "來自 \(handle)")
        }
        if let handle = source.handle {
            return localized("From \(handle)", "來自 \(handle)")
        }
        if source.sourcePlatform != .other {
            return localized(
                "From \(source.sourcePlatform.displayName)",
                "來自 \(source.sourcePlatform.displayName)"
            )
        }
        if let city = candidate.city?.trimmingCharacters(in: .whitespacesAndNewlines),
           !city.isEmpty {
            return city
        }
        let address = candidate.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty
            ? localized("Shared link", "分享連結")
            : address
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

struct SaveMapRootView: View {
    @ObservedObject var mapViewModel: MapViewModel
    let shouldFocusOnUserLocation: Bool
    var hidesCommandShelf: Bool = false
    let onOpenSearch: () -> Void
    let onOpenSavedPlace: (Place) -> Void
    let onPlanAroundPlace: (Place) -> Void
    let onOpenPassport: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        Group {
            if SaveAtlasRuntime.usesParityFixture {
                RootAtlasMapScreen()
                    .environment(\.atlasPresentation, atlasPresentation)
            } else {
                SaveAtlasInteractiveRootMap(
                    mapViewModel: mapViewModel,
                    shouldFocusOnUserLocation: shouldFocusOnUserLocation,
                    hidesCommandShelf: hidesCommandShelf,
                    presentation: atlasPresentation,
                    onClearSelection: mapViewModel.clearSelectedMapObject,
                    onPlanAroundPlace: onPlanAroundPlace
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitest-map-place-selected"),
               mapViewModel.selectedPlace == nil,
               let firstPlace = mapViewModel.places.first {
                mapViewModel.selectedPlace = firstPlace
            }
#endif
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.root")
    }

    private var atlasPresentation: AtlasPresentation {
        SaveAtlasPresentationFactory.map(
            mapViewModel: mapViewModel,
            onOpenAssistant: onOpenSearch,
            onOpenPlace: onOpenSavedPlace,
            onOpenPassport: onOpenPassport
        )
    }
}

struct SaveGlobalCaptureToolbarButton: View {
    let action: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        Button(action: action) {
            Image(systemName: "link.badge.plus")
        }
        .accessibilityLabel(languageSettings.localized(
            english: "Paste or share link",
            traditionalChinese: "貼上／分享連結"
        ))
        .accessibilityIdentifier("root.capture")
    }
}

private enum SaveLibraryMode {
    case review
    case mapStamps
}

private struct SaveAtlasBrandHeader<Trailing: View>: View {
    let onOpenPassport: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onOpenPassport) {
                HStack(spacing: 9) {
                    Image("SavvyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text("Savvy")
                        .font(SaveAtlasType.strong(24, relativeTo: .title3))
                        .tracking(1.1)
                        .foregroundStyle(SaveAtlasPalette.forest)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Savvy Passport")
            .accessibilityIdentifier("root.passport")

            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 48)
    }
}

private struct SaveAtlasPocketCount: View {
    let label: String
    let value: Int
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .lineLimit(1)
                Text("\(value)")
                    .font(SaveAtlasType.strong(15))
                    .monospacedDigit()
                    .frame(width: 25, height: 25)
                    .background(tint, in: Circle())
            }
            .font(SaveAtlasType.display(14))
            .foregroundStyle(SaveAtlasPalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                isSelected
                    ? tint.opacity(0.38)
                    : SaveAtlasPalette.paper,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isSelected
                            ? SaveAtlasPalette.forest.opacity(0.44)
                            : SaveAtlasPalette.line.opacity(0.30),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private enum SaveAtlasReviewTicketKind: Equatable {
    case reviewCandidate
    case sourceClue
}

private struct SaveAtlasReviewTicket: View {
    let candidate: PlaceReviewCandidate
    let detail: String
    let kind: SaveAtlasReviewTicketKind
    let actionTitle: String
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        SavePostcardTicket(
            eyebrow: kindTitle,
            title: candidate.name.isEmpty
                ? localized("Untitled clue", "未命名線索")
                : candidate.name,
            detail: detail,
            actionTitle: actionTitle,
            style: kind == .sourceClue ? .sourceClue : .review
        )
    }

    private var kindTitle: String {
        kind == .sourceClue
            ? localized("Source Clue", "來源線索")
            : localized("Review Candidate", "待確認地點")
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct SaveAtlasMapStampTicket: View {
    let place: Place
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        SavePostcardTicket(
            eyebrow: localized("Confirmed Map Stamp", "已確認地圖章"),
            title: place.name,
            detail: detail,
            actionTitle: localized("Open", "打開"),
            style: .confirmed
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(place.name), \(detail)")
        .accessibilityHint(localized(
            "Open the lifted saved postcard",
            "打開收藏明信片詳情"
        ))
        .accessibilityIdentifier("saves.mapStamp.postcard")
    }

    private var detail: String {
        let area = place.shareAreaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = area.isEmpty
            ? place.address.trimmingCharacters(in: .whitespacesAndNewlines)
            : area
        let source = place.sourcePlatform == .other
            ? localized("Saved memory", "已保存記憶")
            : localized(
                "From \(place.sourcePlatform.displayName)",
                "來自 \(place.sourcePlatform.displayName)"
            )
        return location.isEmpty ? source : "\(location) · \(source)"
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct SaveAtlasReviewPocket: View {
    let count: Int
    let title: String
    let countLabel: String
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SaveAtlasPalette.kraft.opacity(0.72),
                    SaveAtlasPalette.kraft,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            SaveAtlasPocketStitch()
            .stroke(
                SaveAtlasPalette.line.opacity(0.54),
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
            )

            HStack(spacing: 14) {
                SaveAtlasPostmark()

                VStack(spacing: 7) {
                    Text(title)
                        .font(SaveAtlasType.editorial(19))
                        .foregroundStyle(SaveAtlasPalette.ink)

                    Rectangle()
                        .fill(SaveAtlasPalette.line.opacity(0.5))
                        .frame(height: 1)

                    Text(count == 0
                        ? localized("All caught up", "全部完成")
                        : localized("Open Review", "打開待確認")
                    )
                        .font(SaveAtlasType.display(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }

                VStack(spacing: -2) {
                    Text("\(count)")
                        .font(SaveAtlasType.editorial(28))
                        .monospacedDigit()
                    Text(countLabel)
                        .font(SaveAtlasType.regular(10))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .foregroundStyle(SaveAtlasPalette.coral)
                .frame(width: 66, height: 66)
                .background(SaveAtlasPalette.paper.opacity(0.34), in: SaveAtlasSealShape())
                .overlay {
                    SaveAtlasSealShape()
                        .stroke(SaveAtlasPalette.coral.opacity(0.52), lineWidth: 1)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(minHeight: 126)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.38), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) \(countLabel)")
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct SaveAtlasPocketStitch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let edgeY = rect.minY + rect.height * 0.16
        let centerY = rect.minY + rect.height * 0.30
        let controlY = rect.minY + rect.height * 0.56
        path.move(to: CGPoint(x: rect.minX, y: edgeY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: centerY),
            control: CGPoint(x: rect.minX + rect.width * 0.25, y: controlY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: edgeY),
            control: CGPoint(x: rect.minX + rect.width * 0.75, y: controlY)
        )
        return path
    }
}

private struct SaveAtlasPostmark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(SaveAtlasPalette.line.opacity(0.66), lineWidth: 1)
                .frame(width: 48, height: 48)
            Image(systemName: "airplane")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(SaveAtlasPalette.line)
        }
        .overlay(alignment: .trailing) {
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(SaveAtlasPalette.line.opacity(0.58))
                        .frame(width: 28, height: 1)
                }
            }
            .offset(x: 22)
        }
        .frame(width: 68)
    }
}

private struct SaveAtlasPerforatedMedallion: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(SaveAtlasPalette.ink)
            .frame(width: 49, height: 49)
            .background(tint, in: SaveAtlasSealShape())
            .overlay {
                SaveAtlasSealShape()
                    .stroke(SaveAtlasPalette.ink.opacity(0.16), lineWidth: 1)
            }
    }
}

private struct SaveAtlasScallopedRectangle: Shape {
    var depth: CGFloat = 4
    var pitch: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = pitch / 2
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY + depth))

        var x = rect.minX + radius
        while x < rect.maxX - radius {
            path.addQuadCurve(
                to: CGPoint(x: x + pitch, y: rect.minY + depth),
                control: CGPoint(x: x + radius, y: rect.minY - depth)
            )
            x += pitch
        }

        path.addLine(to: CGPoint(x: rect.maxX - depth, y: rect.minY + radius))
        var y = rect.minY + radius
        while y < rect.maxY - radius {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - depth, y: y + pitch),
                control: CGPoint(x: rect.maxX + depth, y: y + radius)
            )
            y += pitch
        }

        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY - depth))
        x = rect.maxX - radius
        while x > rect.minX + radius {
            path.addQuadCurve(
                to: CGPoint(x: x - pitch, y: rect.maxY - depth),
                control: CGPoint(x: x - radius, y: rect.maxY + depth)
            )
            x -= pitch
        }

        path.addLine(to: CGPoint(x: rect.minX + depth, y: rect.maxY - radius))
        y = rect.maxY - radius
        while y > rect.minY + radius {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + depth, y: y - pitch),
                control: CGPoint(x: rect.minX - depth, y: y - radius)
            )
            y -= pitch
        }

        path.closeSubpath()
        return path
    }
}

private struct SaveAtlasSealShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2 - 2
        let steps = 96
        var path = Path()

        for step in 0...steps {
            let angle = CGFloat(step) / CGFloat(steps) * .pi * 2 - .pi / 2
            let radius = baseRadius + cos(angle * 16) * 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
