import MapKit
import SwiftUI

struct SaveHomeView: View {
    @ObservedObject var store: TripPackStore
    @ObservedObject var mapViewModel: MapViewModel
    let onOpenDrawer: (DrawerLaunchTarget, UUID?) -> Void
    let onOpenSavedPlace: (Place) -> Void
    let onOpenSaves: () -> Void
    let onOpenTrips: () -> Void
    let onOpenTrip: (UUID) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var resolvedHomeHero: AtlasHomeHeroPresentation?

    var body: some View {
        HomeAtlasScreen()
        .environment(\.atlasPresentation, atlasPresentation)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.root")
        .task {
            await resolveHomeHero()
        }
    }

    private var atlasPresentation: AtlasPresentation {
        var presentation = SaveAtlasPresentationFactory.root(
            store: store,
            mapViewModel: mapViewModel,
            onCapture: { onOpenDrawer(.addLink, nil) },
            onReviewAll: { onOpenDrawer(.review, nil) },
            onOpenTrip: onOpenTrip,
            onOpenSaves: onOpenSaves,
            onOpenPlace: onOpenSavedPlace,
            onOpenReview: { _ in onOpenDrawer(.review, nil) }
        )
        if !SaveAtlasRuntime.usesParityFixture {
            presentation.homeHero = resolvedHomeHero ?? savedPlaceHero ?? .neutral
        }
        return presentation
    }

    private var savedPlaceHero: AtlasHomeHeroPresentation? {
        guard let place = mapViewModel.places.max(by: { $0.createdAt < $1.createdAt }) else {
            return nil
        }
        let area = place.shareAreaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return .savedPlace(
            title: area.isEmpty ? localized("Recent Map Stamp", "最近的地圖章") : area,
            subtitle: localized(
                "Based on \(place.name)",
                "依據 \(place.name)"
            ),
            latitude: place.latitude,
            longitude: place.longitude
        )
    }

    private func resolveHomeHero() async {
        guard !SaveAtlasRuntime.usesParityFixture else { return }

        if let fixture = homeHeroFixture {
            resolvedHomeHero = fixture
            return
        }

        guard let location = await LocationService.shared.requestCurrentLocation() else {
            return
        }

        let placemark = try? await CLGeocoder()
            .reverseGeocodeLocation(location, preferredLocale: Locale.current)
            .first
        let countryCode = placemark?.isoCountryCode
        let title = [
            placemark?.locality,
            placemark?.subAdministrativeArea,
            placemark?.administrativeArea,
            placemark?.country,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty })
            ?? localized("Around you", "你附近")

        let subtitleParts = [
            placemark?.administrativeArea,
            placemark?.country,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && $0.localizedCaseInsensitiveCompare(title) != .orderedSame }

        let subtitle = uniqueStrings(subtitleParts).joined(separator: " · ")
        resolvedHomeHero = .currentRegion(
            title: title,
            subtitle: subtitle.isEmpty
                ? localized("Your current region", "你目前所在區域")
                : subtitle,
            countryCode: countryCode,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    private var homeHeroFixture: AtlasHomeHeroPresentation? {
        let fixtures: [String: AtlasHomeHeroPresentation] = [
            "--uitest-home-region-taipei": .currentRegion(
                title: "Taipei",
                subtitle: "Taiwan",
                countryCode: "TW",
                latitude: 25.033,
                longitude: 121.5654
            ),
            "--uitest-home-region-new-york": .currentRegion(
                title: "New York",
                subtitle: "United States",
                countryCode: "US",
                latitude: 40.7128,
                longitude: -74.0060
            ),
            "--uitest-home-region-shanghai": .currentRegion(
                title: "Shanghai",
                subtitle: "China",
                countryCode: "CN",
                latitude: 31.2304,
                longitude: 121.4737
            ),
            "--uitest-home-region-seoul": .currentRegion(
                title: "Seoul",
                subtitle: "South Korea",
                countryCode: "KR",
                latitude: 37.5665,
                longitude: 126.9780
            ),
            "--uitest-home-region-tustin": .currentRegion(
                title: "Tustin",
                subtitle: "California · United States",
                countryCode: "US",
                latitude: 33.7459,
                longitude: -117.8265
            ),
            "--uitest-home-region-san-francisco": .currentRegion(
                title: "San Francisco",
                subtitle: "California · United States",
                countryCode: "US",
                latitude: 37.7749,
                longitude: -122.4194
            ),
        ]
        let arguments = ProcessInfo.processInfo.arguments
        return fixtures.first { arguments.contains($0.key) }?.value
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    private var homeContent: some View {
        VStack(spacing: 0) {
            SaveAtlasBrandHeader {
                Button {
                    onOpenDrawer(.addLink, nil)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "link")
                            .font(.system(size: 14, weight: .semibold))
                        Text(localized("Paste a link", "貼上連結"))
                            .font(SaveAtlasType.display(13))
                    }
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 38)
                    .background(SaveAtlasPalette.paper, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(SaveAtlasPalette.line.opacity(0.42), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.capture")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            SaveAtlasMapPreview(
                places: recentPlaces,
                isLoading: mapViewModel.isLoading
            )
            .frame(height: 214)

            reviewCard
                .padding(.horizontal, 10)
                .padding(.top, -22)

            tripSection
                .padding(.horizontal, 14)
                .padding(.top, 10)

            recentSavesSection
                .padding(.horizontal, 14)
                .padding(.top, 8)
        }
        .padding(.bottom, 14)
    }

    private var reviewCard: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(reviewHeadline)
                    .font(SaveAtlasType.strong(24, relativeTo: .title2))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .multilineTextAlignment(.center)

                Text(localized(
                    "Review and decide what’s worth saving.",
                    "確認線索，再決定哪些值得收藏。"
                ))
                .font(SaveAtlasType.body(13))
                .foregroundStyle(SaveAtlasPalette.muted)
                .multilineTextAlignment(.center)
            }

            Button {
                onOpenDrawer(.review, nil)
            } label: {
                HStack {
                    Spacer()
                    Text(localized("Review clues", "確認線索"))
                        .font(SaveAtlasType.strong(16))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.trailing, 4)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 42)
                .background(
                    LinearGradient(
                        colors: [
                            SaveAtlasPalette.coral,
                            SaveAtlasPalette.coral.opacity(0.88),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(mapViewModel.isLoading)
            .opacity(mapViewModel.isLoading ? 0.62 : 1)
            .accessibilityIdentifier("home.review")

            HStack(spacing: 0) {
                SaveAtlasHomeMetric(
                    value: mapViewModel.isLoading ? "–" : "\(mapViewModel.reviewCandidates.count)",
                    label: localized("to review", "待確認"),
                    systemName: "timer",
                    tint: SaveAtlasPalette.lavender
                )

                Rectangle()
                    .fill(SaveAtlasPalette.line.opacity(0.30))
                    .frame(width: 1, height: 38)
                    .padding(.horizontal, 7)

                Button(action: onOpenSaves) {
                    SaveAtlasHomeMetric(
                        value: mapViewModel.isLoading ? "–" : "\(mapViewModel.places.count)",
                        label: localized("Map Stamps", "地圖章"),
                        systemName: "arrow.up.right",
                        tint: SaveAtlasPalette.mint
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.saves")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .saveAtlasPaper(radius: 22, shadow: true)
    }

    @ViewBuilder
    private var tripSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(localized("NEXT UP", "下一站"))
                .font(SaveAtlasType.strong(11))
                .tracking(1.1)
                .foregroundStyle(SaveAtlasPalette.muted)

            if store.isLoading {
                SaveAtlasLoadingRow(
                    title: localized("Loading your Trip Packs…", "正在載入行程包…")
                )
            } else if let errorMessage = store.errorMessage {
                Button {
                    Task { await store.load() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("Couldn’t load Trips", "無法載入行程"))
                                .font(SaveAtlasType.strong(17))
                            Text(errorMessage)
                                .font(SaveAtlasType.regular(12))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 54)
                }
                .buttonStyle(.plain)
            } else if let trip = store.suggestedTrip {
                Button {
                    store.selectTrip(trip.id)
                    onOpenTrip(trip.id)
                } label: {
                    SaveHomeTripCard(trip: trip)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.trip.\(trip.id.uuidString)")
            } else {
                Button(action: onOpenTrips) {
                    HStack(spacing: 14) {
                        Image(systemName: "suitcase.rolling.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(SaveAtlasPalette.forest)
                            .frame(width: 38, height: 38)
                            .background(SaveAtlasPalette.mint, in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("Start a Trip Pack", "建立 Trip Pack"))
                                .font(SaveAtlasType.strong(17))
                                .foregroundStyle(SaveAtlasPalette.forest)
                            Text(localized(
                                "Plan only when your confirmed places are ready.",
                                "等已確認地點準備好，再開始規劃。"
                            ))
                            .font(SaveAtlasType.regular(12))
                            .foregroundStyle(SaveAtlasPalette.muted)
                            .lineLimit(2)
                        }

                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundStyle(SaveAtlasPalette.muted)
                    }
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.openTrips")
            }
        }
    }

    @ViewBuilder
    private var recentSavesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(localized("Recent Map Stamps", "最近地圖章"))
                    .font(SaveAtlasType.strong(11))
                    .tracking(1.1)
                    .foregroundStyle(SaveAtlasPalette.muted)
                Spacer()
                if !recentPlaces.isEmpty {
                    Button(localized("See all", "查看全部"), action: onOpenSaves)
                        .font(SaveAtlasType.display(12))
                        .foregroundStyle(SaveAtlasPalette.ink)
                }
            }

            if mapViewModel.isLoading {
                SaveAtlasLoadingRow(
                    title: localized("Loading Map Stamps…", "正在載入地圖章…")
                )
            } else if recentPlaces.isEmpty {
                Text(localized(
                    "Confirmed places will appear here after Review.",
                    "完成確認後，收藏地點會出現在這裡。"
                ))
                .font(SaveAtlasType.body(13))
                .foregroundStyle(SaveAtlasPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 48)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentPlaces.enumerated()), id: \.element.id) { index, place in
                        SaveRootPlaceRow(place: place) {
                            onOpenSavedPlace(place)
                        }

                        if index < recentPlaces.count - 1 {
                            Divider()
                                .overlay(SaveAtlasPalette.line.opacity(0.22))
                                .padding(.leading, 45)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("home.recentSaves")
    }

    private var recentPlaces: [Place] {
        Array(mapViewModel.places.sorted { $0.createdAt > $1.createdAt }.prefix(2))
    }

    private var reviewHeadline: String {
        if mapViewModel.isLoading {
            return localized("Loading your place memory…", "正在載入地點記憶…")
        }
        let count = mapViewModel.reviewCandidates.count
        if count == 0 {
            return localized("You’re all caught up", "所有線索都確認完了")
        }
        return localized(
            "\(count) \(count == 1 ? "clue needs" : "clues need") your help",
            "\(count) 個線索等你確認"
        )
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

struct SaveLibraryView: View {
    let places: [Place]
    let reviewCandidates: [PlaceReviewCandidate]
    let onOpenCapture: () -> Void
    let onOpenReview: () -> Void
    let onOpenReviewCandidate: (PlaceReviewCandidate) -> Void
    let onOpenSavedPlace: (Place) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedMode: SaveLibraryMode?

    var body: some View {
        Group {
            if SaveAtlasRuntime.usesParityFixture {
                SavesPocketScreen()
                    .environment(\.atlasPresentation, atlasPresentation)
            } else {
                savesContent
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saves.root")
    }

    private var atlasPresentation: AtlasPresentation {
        SaveAtlasPresentationFactory.library(
            places: places,
            candidates: reviewCandidates,
            onCapture: onOpenCapture,
            onReviewAll: onOpenReview,
            onOpenPlace: onOpenSavedPlace,
            onOpenReview: onOpenReviewCandidate,
            onSelectReview: {
                selectedMode = .review
            },
            onSelectMapStamps: {
                selectedMode = .mapStamps
            }
        )
    }

    private var savesContent: some View {
        VStack(spacing: 0) {
            SaveAtlasBrandHeader {
                Button(action: onOpenCapture) {
                    Image(systemName: "link")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .frame(width: 42, height: 42)
                        .background(
                            SaveAtlasPalette.honey.opacity(0.82),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(SaveAtlasPalette.line.opacity(0.38), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
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
                .padding(.bottom, 22)
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
                Text(localized("Saves", "收藏"))
                    .font(SaveAtlasType.strong(34, relativeTo: .largeTitle))
                    .foregroundStyle(SaveAtlasPalette.forest)
                Text(localized(
                    "Clues you’ve saved from links and notes.",
                    "從連結與筆記留下的地點線索。"
                ))
                .font(SaveAtlasType.body(15))
                .foregroundStyle(SaveAtlasPalette.muted)
                .lineLimit(2)
            }

            Spacer(minLength: 0)
            MemoMascotMark(size: 82, framed: false)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 100)
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
        VStack(spacing: 8) {
            if sortedCandidates.isEmpty {
                VStack(spacing: 8) {
                    MemoMascotMark(size: 72, framed: false)
                    Text(localized("No clues waiting", "沒有待確認線索"))
                        .font(SaveAtlasType.strong(21))
                        .foregroundStyle(SaveAtlasPalette.forest)
                    Text(localized(
                        "Share a link whenever you find a place worth remembering.",
                        "看到值得記住的地點時，分享連結給 SAV-E。"
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
                ForEach(sortedCandidates) { candidate in
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
            }
        }
    }

    @ViewBuilder
    private var savedPlacesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localized("MAP STAMPS", "地圖章"))
                    .font(SaveAtlasType.strong(11))
                    .tracking(1.1)
                    .foregroundStyle(SaveAtlasPalette.muted)
                Spacer()
                Label(
                    localized("\(places.count) confirmed", "\(places.count) 個已確認"),
                    systemImage: "checkmark.seal.fill"
                )
                .font(SaveAtlasType.display(12))
                .foregroundStyle(SaveAtlasPalette.forest)
            }

            if sortedPlaces.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        localized("No confirmed places yet", "還沒有已確認地點"),
                        systemImage: "mappin.slash"
                    )
                    .font(SaveAtlasType.strong(19))
                    .foregroundStyle(SaveAtlasPalette.forest)

                    Text(localized(
                        "Add a link first. SAV-E keeps uncertain clues in Review instead of placing guesses on your map.",
                        "先加入連結。SAV-E 會把不確定的線索留在待確認，不會把猜測直接放上地圖。"
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
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedPlaces.enumerated()), id: \.element.id) { index, place in
                        SaveRootPlaceRow(place: place) {
                            onOpenSavedPlace(place)
                        }
                        .accessibilityIdentifier("saves.place.\(place.id.uuidString)")

                        if index < sortedPlaces.count - 1 {
                            Divider()
                                .overlay(SaveAtlasPalette.line.opacity(0.22))
                                .padding(.leading, 60)
                        }
                    }
                }
                .padding(.vertical, 4)
                .saveAtlasPaper(radius: 20)
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

    private var sortedCandidates: [PlaceReviewCandidate] {
        reviewCandidates.sorted { $0.createdAt > $1.createdAt }
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
    let onOpenSearch: () -> Void
    let onOpenSavedPlace: (Place) -> Void
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
                    presentation: atlasPresentation,
                    onClearSelection: mapViewModel.clearSelectedMapObject
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
            onOpenPlace: onOpenSavedPlace
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
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            MemoMascotMark(size: 38, framed: false)

            Text("SAV-E")
                .font(SaveAtlasType.strong(24, relativeTo: .title3))
                .tracking(1.1)
                .foregroundStyle(SaveAtlasPalette.forest)

            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 48)
    }
}

private struct SaveAtlasMapPreview: View {
    let places: [Place]
    let isLoading: Bool
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        ZStack(alignment: .bottom) {
            if let anchor = places.first {
                Map(
                    initialPosition: .region(region(centeredOn: anchor)),
                    interactionModes: []
                ) {
                    ForEach(visiblePlaces(around: anchor)) { place in
                        Annotation("", coordinate: place.coordinate, anchor: .bottom) {
                            VStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(SaveAtlasPalette.forest)
                                    .frame(width: 34, height: 34)
                                    .background(SaveAtlasPalette.mint, in: Circle())
                                    .overlay {
                                        Circle()
                                            .stroke(SaveAtlasPalette.paper, lineWidth: 3)
                                    }

                                Text(place.name)
                                    .font(SaveAtlasType.strong(11))
                                    .foregroundStyle(SaveAtlasPalette.ink)
                                    .lineLimit(1)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(SaveAtlasPalette.paper.opacity(0.94), in: Capsule())
                            }
                        }
                    }
                }
                .mapStyle(.standard)
                .id(anchor.id)
                .accessibilityHidden(true)
            } else {
                SaveDottedBackground()

                if isLoading {
                    ProgressView()
                        .tint(SaveAtlasPalette.forest)
                        .accessibilityLabel(localized(
                            "Loading map preview",
                            "正在載入地圖預覽"
                        ))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.system(size: 30, weight: .regular))
                        Text(localized(
                            "Your first Map Stamp will begin this atlas.",
                            "第一個地圖章會從這本圖冊開始。"
                        ))
                            .font(SaveAtlasType.body(14))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .padding(.horizontal, 32)
                }
            }

            LinearGradient(
                colors: [.clear, SaveAtlasPalette.canvas.opacity(0.84)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 54)
            .allowsHitTesting(false)

            HStack {
                Text(localized("YOUR PLACE ATLAS", "你的地點圖冊"))
                    .font(SaveAtlasType.strong(11))
                    .tracking(1.1)
                Spacer()
                if let cityLabel {
                    Text(cityLabel)
                        .font(SaveAtlasType.display(12))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(SaveAtlasPalette.ink)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            MemoMascotMark(size: 76, framed: false)
                .offset(x: 3, y: 18)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            places.isEmpty
                ? localized(
                    "Place atlas, no Map Stamps yet",
                    "地點圖冊，目前還沒有地圖章"
                )
                : localized(
                    "Place atlas, \(places.count) recent Map Stamps",
                    "地點圖冊，\(places.count) 個最近地圖章"
                )
        )
    }

    private var cityLabel: String? {
        guard let address = places.first?.address else { return nil }
        let parts = address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.count >= 2 ? parts[parts.count - 2] : parts.first
    }

    private func region(centeredOn place: Place) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: place.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.16)
        )
    }

    private func visiblePlaces(around anchor: Place) -> [Place] {
        let origin = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        return Array(places.filter { place in
            origin.distance(from: CLLocation(
                latitude: place.latitude,
                longitude: place.longitude
            )) <= 60_000
        }.prefix(3))
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct SaveAtlasHomeMetric: View {
    let value: String
    let label: String
    let systemName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SaveAtlasPalette.ink)
                .frame(width: 37, height: 37)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: -2) {
                Text(value)
                    .font(SaveAtlasType.strong(22, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(SaveAtlasPalette.forest)
                Text(label)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SaveAtlasLoadingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(SaveAtlasPalette.forest)
            Text(title)
                .font(SaveAtlasType.body(14))
                .foregroundStyle(SaveAtlasPalette.muted)
            Spacer()
        }
        .frame(minHeight: 54)
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

    private var tint: Color {
        kind == .sourceClue
            ? SaveAtlasPalette.coral.opacity(0.42)
            : SaveAtlasPalette.sky
    }

    var body: some View {
        HStack(spacing: 11) {
            SaveAtlasPerforatedMedallion(
                systemName: kind == .sourceClue ? "magnifyingglass" : "camera",
                tint: tint
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(kindTitle.uppercased())
                    .font(SaveAtlasType.strong(10))
                    .tracking(0.6)
                    .foregroundStyle(
                        kind == .sourceClue
                            ? SaveAtlasPalette.coral
                            : Color.saveBlueInk
                    )

                Text(candidate.name.isEmpty
                    ? localized("Untitled clue", "未命名線索")
                    : candidate.name
                )
                    .font(SaveAtlasType.strong(18, relativeTo: .headline))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .lineLimit(1)

                Text(detail)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(actionTitle)
                .font(SaveAtlasType.display(13))
                .foregroundStyle(SaveAtlasPalette.ink)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(minHeight: 38)
                .background(tint.opacity(0.84), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SaveAtlasPalette.ink.opacity(0.22), lineWidth: 1)
                }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(SaveAtlasPalette.paper)
        .padding(5)
        .background(
            SaveAtlasScallopedRectangle(depth: 3, pitch: 10)
                .fill(tint.opacity(0.94))
        )
        .shadow(color: SaveAtlasPalette.ink.opacity(0.06), radius: 4, y: 2)
        .contentShape(Rectangle())
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

private struct SaveHomeTripCard: View {
    let trip: Trip
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(width: 38, height: 38)
                .background(SaveAtlasPalette.mint, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(trip.name)
                    .font(SaveAtlasType.strong(19, relativeTo: .headline))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .lineLimit(1)
                Text(languageSettings.localized(
                    english: "\(trip.places.count) stops planned",
                    traditionalChinese: "已規劃 \(trip.places.count) 站"
                ))
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
            }

            Spacer()

            if !trip.city.isEmpty {
                Text(trip.city)
                    .font(SaveAtlasType.display(11))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 28)
                    .background(SaveAtlasPalette.lavender, in: Capsule())
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(SaveAtlasPalette.muted)
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

private struct SaveRootPlaceRow: View {
    let place: Place
    let action: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SaveAtlasPlaceThumbnail(place: place)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(SaveAtlasType.strong(15))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .lineLimit(1)
                    Text(addressText)
                        .font(SaveAtlasType.regular(11))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(place.status.memoryCardLabel(language: languageSettings.language))
                        .font(SaveAtlasType.display(10))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 24)
                        .background(SaveAtlasPalette.mint, in: Capsule())

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(place.name), \(addressText)")
        .accessibilityHint(languageSettings.localized(
            english: "Open Map Stamp details",
            traditionalChinese: "打開地圖章詳情"
        ))
    }

    private var addressText: String {
        let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty
            ? languageSettings.localized(english: "Selected on map", traditionalChinese: "從地圖選取")
            : address
    }
}

private struct SaveAtlasPlaceThumbnail: View {
    let place: Place

    var body: some View {
        Group {
            if let urlString = place.businessPhotoURLStrings.first,
               let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                            .tint(SaveAtlasPalette.forest)
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 44, height: 44)
        .background(SaveAtlasPalette.mint.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.28), lineWidth: 1)
        }
    }

    private var fallback: some View {
        Image(systemName: place.category.iconName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(SaveAtlasPalette.forest)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
