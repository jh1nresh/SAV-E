import CoreLocation
import SwiftUI

struct SaveHomeView: View {
    @ObservedObject var store: TripPackStore
    @ObservedObject var mapViewModel: MapViewModel
    let onCapture: () -> Void
    let onOpenSavedPlace: (Place) -> Void
    let onOpenSaves: () -> Void
    let onOpenTrips: () -> Void
    let onOpenMap: () -> Void
    let onOpenTrip: (UUID) -> Void
    let onOpenPassport: () -> Void
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
            onCapture: onCapture,
            onReviewAll: onOpenSaves,
            onOpenTrip: onOpenTrip,
            onOpenTrips: onOpenTrips,
            onOpenSaves: onOpenSaves,
            onOpenPlace: onOpenSavedPlace,
            onOpenReview: { _ in onOpenSaves() },
            onOpenPassport: onOpenPassport
        )
        let hero = SaveAtlasRuntime.usesParityFixture
            ? presentation.homeHero
            : resolvedHomeHero ?? savedPlaceHero ?? .neutral
        presentation.homeHero = hero
        if !SaveAtlasRuntime.usesParityFixture {
            let tripPriority = store.homeTripPriority(matchingStoryCity: hero.storyCity)
            presentation.homePriority = SaveAtlasPresentationFactory.homePriority(
                tripPriority: tripPriority,
                mapStampCount: mapViewModel.places.count
            )
            presentation.tripsBetaLabel = languageSettings.localized(
                english: "BETA",
                traditionalChinese: "測試版"
            )
            presentation.onOpenHomePriority = {
                guard let tripID = tripPriority?.trip.id else { return }
                onOpenTrip(tripID)
            }
        }
        presentation.onOpenHomeHero = {
            openMap(for: hero)
        }
        return presentation
    }

    private func openMap(for hero: AtlasHomeHeroPresentation) {
        if let latitude = hero.latitude, let longitude = hero.longitude {
            mapViewModel.focusRegion(latitude: latitude, longitude: longitude)
        }
        onOpenMap()
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
            "--uitest-home-region-beijing": .currentRegion(
                title: "Beijing",
                subtitle: "China",
                countryCode: "CN",
                latitude: 39.9042,
                longitude: 116.4074
            ),
            "--uitest-home-region-guangzhou": .currentRegion(
                title: "Guangzhou",
                subtitle: "China",
                countryCode: "CN",
                latitude: 23.1291,
                longitude: 113.2644
            ),
            "--uitest-home-region-shenzhen": .currentRegion(
                title: "Shenzhen",
                subtitle: "China",
                countryCode: "CN",
                latitude: 22.5431,
                longitude: 114.0579
            ),
            "--uitest-home-region-chengdu": .currentRegion(
                title: "Chengdu",
                subtitle: "China",
                countryCode: "CN",
                latitude: 30.5728,
                longitude: 104.0668
            ),
            "--uitest-home-region-chongqing": .currentRegion(
                title: "Chongqing",
                subtitle: "China",
                countryCode: "CN",
                latitude: 29.5630,
                longitude: 106.5516
            ),
            "--uitest-home-region-tianjin": .currentRegion(
                title: "Tianjin",
                subtitle: "China",
                countryCode: "CN",
                latitude: 39.0851,
                longitude: 117.1994
            ),
            "--uitest-home-region-hangzhou": .currentRegion(
                title: "Hangzhou",
                subtitle: "China",
                countryCode: "CN",
                latitude: 30.2741,
                longitude: 120.1551
            ),
            "--uitest-home-region-nanjing": .currentRegion(
                title: "Nanjing",
                subtitle: "China",
                countryCode: "CN",
                latitude: 32.0603,
                longitude: 118.7969
            ),
            "--uitest-home-region-wuhan": .currentRegion(
                title: "Wuhan",
                subtitle: "China",
                countryCode: "CN",
                latitude: 30.5928,
                longitude: 114.3055
            ),
            "--uitest-home-region-xian": .currentRegion(
                title: "Xi'an",
                subtitle: "China",
                countryCode: "CN",
                latitude: 34.3416,
                longitude: 108.9398
            ),
            "--uitest-home-region-suzhou": .currentRegion(
                title: "Suzhou",
                subtitle: "China",
                countryCode: "CN",
                latitude: 31.2989,
                longitude: 120.5853
            ),
            "--uitest-home-region-qingdao": .currentRegion(
                title: "Qingdao",
                subtitle: "China",
                countryCode: "CN",
                latitude: 36.0671,
                longitude: 120.3826
            ),
            "--uitest-home-region-xiamen": .currentRegion(
                title: "Xiamen",
                subtitle: "China",
                countryCode: "CN",
                latitude: 24.4798,
                longitude: 118.0894
            ),
            "--uitest-home-region-changsha": .currentRegion(
                title: "Changsha",
                subtitle: "China",
                countryCode: "CN",
                latitude: 28.2282,
                longitude: 112.9388
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

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
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
                savesContent
                    // ReferenceViewport ignores the safe area; the prototype
                    // screen above draws its own status-bar band, but this
                    // flow layout must reserve it or the header renders under
                    // the clock.
                    .padding(.top, AtlasMetrics.statusBarHeight)
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
                // Clear the floating Atlas tab bar so the last ticket stays
                // reachable.
                .padding(.bottom, 108)
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
            SavePostcardMemoPeek(width: 82)
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
        VStack(spacing: 0) {
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
                // Same mark, size, and person badge as the prototype
                // BrandHeader so every tab's profile entry matches.
                HStack(spacing: 9) {
                    MemoMascotMark(size: 40, framed: false)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(SaveAtlasPalette.forest)
                                .frame(width: 17, height: 17)
                                .background(SaveAtlasPalette.mint, in: Circle())
                                .overlay {
                                    Circle().stroke(SaveAtlasPalette.paper, lineWidth: 1.5)
                                }
                                .offset(x: 3, y: 2)
                        }

                    Text("SAV-E")
                        .font(SaveAtlasType.strong(24, relativeTo: .title3))
                        .tracking(1.1)
                        .foregroundStyle(SaveAtlasPalette.forest)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open SAV-E Passport")
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

