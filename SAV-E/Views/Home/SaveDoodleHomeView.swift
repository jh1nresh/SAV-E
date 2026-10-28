import CoreLocation
import SwiftUI
import UIKit

/// Doodle v1 Home: nearby Eat/Go list and city switcher. No map component
/// (founder option B / DESIGN v2, 2026-10-24; HoP 290-5 / H-1 / H-4).
struct SaveDoodleHomeView: View {
    @Environment(\.atlasPresentation) private var presentation
    @Environment(\.appLanguageSettings) private var languageSettings
    @EnvironmentObject private var session: SaveDoodleSession
    @ObservedObject var locationService: LocationService
    var onOpenCollectedPassport: () -> Void = {}
    var headerTopPadding: CGFloat = AtlasMetrics.statusBarHeight + SaveSpace.xs
    var collectionReady = false

    @State private var showsCityPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: SaveLayout.minTap)
                .padding(.horizontal, SaveLayout.screenMargin)
                .padding(.top, headerTopPadding)
                .zIndex(2)

            ZStack(alignment: .trailing) {
                citySwitcher
                if presentation.reviewCount == 0 {
                    savesButton
                }
            }
            .padding(.horizontal, SaveLayout.screenMargin)
            .padding(.top, SaveSpace.tight)

            cluesLine
                .padding(.horizontal, SaveLayout.screenMargin)
                .padding(.top, SaveSpace.xs)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if showsLocationPrompt {
                        locationPrompt
                            .padding(.top, SaveSpace.md)
                    }

                    if showsEmptyHome {
                        emptyHome
                            .padding(.top, SaveSpace.md)
                    }

                    if showsLensEmpty {
                        lensEmpty
                            .padding(.top, SaveSpace.md)
                    } else if !showsEmptyHome {
                        placeList
                            .padding(.top, SaveSpace.md)
                    }

                    // City X/Y is independent of Eat/Go. A lens with no rows
                    // must not hide Collected (HoP 2026-10-21).
                    if !collectedPlaces.isEmpty {
                        collectedStrip
                            .padding(.top, SaveSpace.md)
                    }
                }
                .padding(.horizontal, SaveLayout.screenMargin)
                .padding(.bottom, AtlasTabBarMetrics.height)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.savedPlaces")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SaveDottedBackground())
        .sheet(isPresented: $showsCityPicker) {
            cityPicker
        }
        .onAppear { syncPersistedCitySelection() }
        .onChange(of: resolvedSelection) { _, _ in
            syncPersistedCitySelection()
        }
        .onChange(of: allPlaces.count) { _, _ in
            syncPersistedCitySelection()
        }
        .onChange(of: collectionReady) { _, _ in
            syncPersistedCitySelection()
        }
    }

    /// Persist a replacement when the selected city's last save disappeared
    /// so the picker check and header do not keep a stale ID. Empty
    /// `allPlaces` on cold launch is "not loaded yet", not a deletion.
    private func syncPersistedCitySelection() {
        let next = SaveDoodleHomeCatalog.persistedCityAfterCollectionChange(
            current: session.city,
            places: allPlaces,
            locationDenied: locationService.isAuthorizationDenied,
            collectionReady: collectionReady
        )
        guard session.city != next else { return }
        session.city = next
    }

    /// A visible production route, also available when there are no waiting clues.
    private var savesButton: some View {
        Button(action: presentation.onReviewAll) {
            Label(localized("Saves", "收藏"), systemImage: "bookmark")
                .font(SaveAtlasType.body(15))
                .foregroundStyle(SaveAtlasPalette.ink)
                .padding(.horizontal, SaveSpace.xs)
                .frame(minWidth: SaveLayout.minTap, minHeight: SaveLayout.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.saves")
        .accessibilityLabel(localized("Open Saves", "開啟收藏"))
    }

    private var header: some View {
        HStack(spacing: SaveSpace.xs) {
            Button(action: presentation.onOpenPassport) {
                HStack(alignment: .center, spacing: SaveSpace.xs) {
                    SaveDisplayTitle(
                        text: "Savvy",
                        pointSize: 34,
                        relativeTo: .largeTitle,
                        locksPointSize: true
                    )
                    MemoMascotMark(size: 28, framed: false)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Open Savvy Passport", "開啟 Savvy 護照"))
            .accessibilityIdentifier("home.passport")

            Spacer(minLength: SaveSpace.xs)

            eatGoRow
        }
        .frame(minHeight: SaveLayout.minTap)
    }

    private var eatGoRow: some View {
        HStack(spacing: SaveSpace.xs) {
            ForEach(SaveDoodleLens.allCases) { lens in
                eatGoChip(lens)
            }
        }
        .frame(minHeight: SaveLayout.chipHeight)
    }

    private func eatGoChip(_ lens: SaveDoodleLens) -> some View {
        let selected = session.lens == lens
        return Button {
            SaveHaptics.select()
            session.lens = lens
        } label: {
            Text(lens.title(language: languageSettings.language))
                .font(SaveAtlasType.strong(15))
                .foregroundStyle(selected ? Color.white : SaveAtlasPalette.ink)
                .padding(.horizontal, SaveSpace.md)
                .frame(minWidth: SaveLayout.minTap)
                .frame(height: SaveLayout.chipHeight)
                .background(
                    selected ? SaveAtlasPalette.coral : Color.clear,
                    in: SaveDoodleInkCapsule()
                )
                .overlay {
                    SaveDoodleInkCapsule()
                        .stroke(selected ? Color.clear : SaveAtlasPalette.ink, lineWidth: SaveAtlasPalette.strokeWidth)
                }
                .frame(minHeight: SaveLayout.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lens.title(language: languageSettings.language))
        .accessibilityIdentifier(lens.accessibilityIdentifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var citySwitcher: some View {
        Button { showsCityPicker = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: SaveSpace.tight) {
                if showsNearYouPrefix {
                    SaveDisplayTitle(
                        text: localized("Near you", "附近"),
                        pointSize: 20,
                        relativeTo: .title3,
                        locksPointSize: true
                    )
                    Text("·")
                        .font(SaveAtlasType.body(17))
                        .foregroundStyle(SaveAtlasPalette.forest)
                }
                VStack(alignment: .leading, spacing: 0) {
                    SaveDisplayTitle(
                        text: cityTitle,
                        pointSize: 20,
                        relativeTo: .title3,
                        locksPointSize: true
                    )
                    Capsule()
                        .fill(SaveAtlasPalette.coral)
                        .frame(height: 2)
                        .padding(.top, 1)
                }
                .padding(.trailing, 4)
                .fixedSize(horizontal: true, vertical: false)
                Text("▾")
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.forest)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("Choose city", "選擇城市") + ", " + citySwitcherSpoken)
        .accessibilityIdentifier("home.citySwitcher")
    }

    private var cluesLine: some View {
        let copy = SaveDoodleHomeHint.copy(
            clueCount: presentation.reviewCount,
            at: SaveUITestClock.now,
            language: languageSettings.language
        )
        return HStack(alignment: .center, spacing: SaveSpace.tight) {
            ViewThatFits(in: .horizontal) {
                Text(copy.leadingFull)
                Text(copy.leadingShort)
            }
            .font(SaveAtlasType.body(13))
            .foregroundStyle(SaveAtlasPalette.muted)
            .lineLimit(1)

            if let review = copy.review {
                Button(action: presentation.onReviewAll) {
                    Text(review)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.homeReviewAction)
                        .frame(minHeight: SaveLayout.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.review.action")
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: SaveLayout.minTap, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(copy.spoken)
        .accessibilityIdentifier("home.review")
    }

    private var locationPrompt: some View {
        HStack(spacing: SaveSpace.md) {
            Image(systemName: "location.north.circle")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(SaveAtlasPalette.ink)
                .frame(width: SaveLayout.stickerBox, height: SaveLayout.stickerBox)
                .accessibilityHidden(true)
            Text(localized(
                "Allow location to see what is nearby",
                "允許定位，看看附近有什麼"
            ))
            .font(SaveAtlasType.body(15))
            .foregroundStyle(SaveAtlasPalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: allowLocation) {
                Text(localized("Allow", "允許"))
                    .font(SaveAtlasType.strong(15))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .padding(.horizontal, SaveSpace.md)
                    .frame(minHeight: SaveLayout.chipHeight)
                    .overlay {
                        SaveDoodleInkCapsule()
                            .stroke(SaveAtlasPalette.ink, lineWidth: SaveAtlasPalette.strokeWidth)
                    }
                    .frame(minHeight: SaveLayout.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: SaveLayout.minTap)
            .accessibilityIdentifier("home.locationAllow")
        }
            .padding(SaveLayout.cardPadding)
            .background(
                SaveAtlasPalette.paper,
                in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                    .stroke(SaveAtlasPalette.line, lineWidth: SaveAtlasPalette.strokeWidth)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.locationPrompt")
    }

    private var placeList: some View {
        // Derive once for this render. Re-reading listedPlaces inside each
        // row repeats the entire city's filtering and distance sort N times.
        let rows = listedPlaces
        let latestVisits = SaveDoodleVisitStore().latestVisits(for: rows.map(\.id))
        let now = SaveUITestClock.now
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                placeRow(item, visitedAt: latestVisits[item.id], now: now)
                if index < rows.count - 1 {
                    SaveDoodleDashedDivider()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.placeList")
    }

    private func placeRow(_ item: SaveDoodleListedPlace, visitedAt: Date?, now: Date) -> some View {
        let metadata = SaveDoodleHomeCatalog.rowMetaText(
            distance: item.distance,
            place: item.place,
            visitedAt: visitedAt,
            now: now,
            language: languageSettings.language
        )
        return Button { presentation.onOpenPlace(item.place.id.uuidString) } label: {
            HStack(alignment: .center, spacing: 0) {
                Text("\(item.index)")
                    .font(SaveAtlasType.strong(24))
                    .foregroundStyle(SaveAtlasPalette.coral)
                    .frame(width: SaveLayout.numberBadge, alignment: .center)
                    .padding(.trailing, SaveSpace.xs)
                    .accessibilityHidden(true)

                SaveDoodleSticker(
                    category: item.place.category,
                    placeName: item.place.name,
                    visited: item.place.status == .visited
                )
                    .frame(width: SaveLayout.stickerBox, height: SaveLayout.stickerBox)
                    .padding(.trailing, SaveLayout.stickerToText)

                VStack(alignment: .leading, spacing: SaveLayout.titleToMeta) {
                    Text(item.place.name)
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(metadata)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, SaveLayout.rowVerticalPadding)
            .frame(minHeight: SaveLayout.rowMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.index), \(item.place.name), \(metadata)")
        .accessibilityIdentifier("home.place.\(item.place.id.uuidString)")
    }

    private var collectedStrip: some View {
        Button(action: onOpenCollectedPassport) {
            HStack(spacing: SaveSpace.xs) {
                Text(collectedText)
                    .font(SaveAtlasType.strong(15))
                    .foregroundStyle(SaveAtlasPalette.ink)
                Text("›")
                    .font(SaveAtlasType.body(15))
                    .foregroundStyle(SaveAtlasPalette.ink)
                Spacer(minLength: SaveSpace.xs)
                HStack(spacing: SaveSpace.xs) {
                    ForEach(collectedStamps) { place in
                        SaveDoodleCollectedMark(category: place.category, placeName: place.name)
                    }
                }
            }
            .padding(.horizontal, SaveSpace.md)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(SaveAtlasPalette.kraft, in: SaveDoodlePaperStrip())
            .overlay {
                SaveDoodlePaperStrip()
                    .stroke(SaveDoodle.pencil, lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collectedText)
        .accessibilityIdentifier("home.collected")
    }

    private var emptyHome: some View {
        VStack(spacing: SaveSpace.md) {
            SaveDoodleEmptyPlate()
                .frame(height: 160)
                .padding(.top, SaveSpace.xxl)
                .accessibilityHidden(true)

            SaveDisplayTitle(
                text: localized("Nothing saved near here yet", "這附近還沒有存過地方"),
                pointSize: 24,
                relativeTo: .title2
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Button(action: presentation.onCapture) {
                Text(localized("+ Save your first place", "+ 存第一個地方"))
                    .font(SaveAtlasType.strong(17))
                    .foregroundStyle(SaveAtlasPalette.coral)
                    .frame(maxWidth: .infinity, minHeight: SaveLayout.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(localized("+ Save your first place", "+ 存第一個地方"))
            .accessibilityIdentifier("home.empty.capture")

            if let latest = latestOtherSave {
                Button { presentation.onOpenPlace(latest.place.id.uuidString) } label: {
                    Text(latestSaveText(latest))
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .frame(maxWidth: .infinity, minHeight: SaveLayout.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(latestSaveText(latest))
                .accessibilityIdentifier("home.empty.nearest")
            }
        }
        .padding(.bottom, SaveSpace.xxl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.savedPlaces.empty")
    }

    /// City still has saves; the current Eat/Go list does not. Not the
    /// first-save empty plate — Collected stays visible with the city X/Y.
    private var lensEmpty: some View {
        let lens = session.lens.title(language: languageSettings.language)
        return Text(localized("No \(lens) saves here", "這裡還沒有\(lens)的收藏"))
            .font(SaveAtlasType.body(15))
            .foregroundStyle(SaveAtlasPalette.muted)
            .frame(maxWidth: .infinity, minHeight: SaveLayout.minTap, alignment: .leading)
            .accessibilityIdentifier("home.lensEmpty")
    }

    private var cityPicker: some View {
        NavigationStack {
            List {
                if !locationService.isAuthorizationDenied {
                    Button {
                        session.city = .nearYou
                        showsCityPicker = false
                    } label: {
                        HStack {
                            Text(localized("Near you (current location)", "附近（目前位置）"))
                            Spacer()
                            if case .nearYou = session.city {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SaveAtlasPalette.coral)
                            }
                        }
                    }
                    .accessibilityIdentifier("home.city.nearYou")
                }
                ForEach(cityGroups) { group in
                    Button {
                        session.city = .city(group.id)
                        showsCityPicker = false
                    } label: {
                        HStack {
                            Text("\(group.displayName(language: languageSettings.language)) \(group.count)")
                            Spacer()
                            if case .city(let id) = resolvedSelection, id == group.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SaveAtlasPalette.coral)
                            }
                        }
                    }
                    .accessibilityIdentifier("home.city.\(group.id)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SaveAtlasPalette.paper)
            .navigationTitle(localized("City", "城市"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Close", "關閉")) { showsCityPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var allPlaces: [Place] {
        var places: [Place] = []
        for saved in presentation.savedPlaces {
            if let place = saved.searchPlace {
                places.append(place)
            }
        }
        return places
    }

    private var resolvedSelection: SaveDoodleCitySelection {
        SaveDoodleHomeCatalog.resolvedSelection(
            session.city,
            places: allPlaces,
            locationDenied: locationService.isAuthorizationDenied
        )
    }

    private var listedPlaces: [SaveDoodleListedPlace] {
        SaveDoodleHomeCatalog.listedPlaces(
            from: allPlaces,
            lens: session.lens,
            selection: session.city,
            location: locationService.isAuthorizationDenied ? nil : locationService.currentLocation,
            locationDenied: locationService.isAuthorizationDenied
        )
    }

    private var cityGroups: [SaveDoodleCityGroup] {
        SaveDoodleHomeCatalog.cityGroups(from: allPlaces)
    }

    private var showsEmptyHome: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-empty-home") {
            return true
        }
#endif
        if allPlaces.isEmpty { return true }
        if needsLocationToResolveNearYou { return false }
        if showsLensEmpty { return false }
        if SaveDoodleHomeCatalog.isNearbyEmpty(
            places: allPlaces,
            lens: session.lens,
            selection: session.city,
            location: locationService.currentLocation,
            locationDenied: locationService.isAuthorizationDenied
        ) {
            return true
        }
        return listedPlaces.isEmpty && collectedPlaces.isEmpty
    }

    /// Selected city has saves, but none match the current Eat/Go lens.
    private var showsLensEmpty: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-empty-home") {
            return false
        }
#endif
        guard !needsLocationToResolveNearYou else { return false }
        return listedPlaces.isEmpty && !collectedPlaces.isEmpty
    }

    /// Near you with no fix must not invent a worldwide nearby list.
    private var needsLocationToResolveNearYou: Bool {
        session.city == .nearYou
            && !locationService.isAuthorizationDenied
            && locationService.currentLocation == nil
            && !allPlaces.isEmpty
    }

    private var showsLocationPrompt: Bool {
        // Denied recovery must stay available on the empty plate. Hiding
        // it with `!showsEmptyHome` left no Home route to Settings.
        if locationService.isAuthorizationDenied {
            return true
        }
        return needsLocationToResolveNearYou
    }

    private var showsNearYouPrefix: Bool {
        !locationService.isAuthorizationDenied && session.city == .nearYou
    }

    private var cityTitle: String {
        switch resolvedSelection {
        case .nearYou:
            if let name = SaveDoodleHomeCatalog.nearYouCityName(
                from: allPlaces,
                location: locationService.isAuthorizationDenied ? nil : locationService.currentLocation,
                language: languageSettings.language
            ) {
                return name
            }
            return localized("Nearby", "附近")
        case .city(let id):
            if let group = cityGroups.first(where: { $0.id == id }) {
                return group.displayName(language: languageSettings.language)
            }
            return SaveHomeSearch.cityLabel(
                for: id,
                traditionalChinese: languageSettings.language == .traditionalChinese
            ) ?? id
        }
    }

    private var citySwitcherSpoken: String {
        if showsNearYouPrefix {
            return localized("Near you", "附近") + " · " + cityTitle
        }
        return cityTitle
    }

    private var collectedPlaces: [Place] {
        SaveDoodleHomeCatalog.collectedScopePlaces(
            from: allPlaces,
            selection: session.city,
            location: locationService.isAuthorizationDenied ? nil : locationService.currentLocation,
            locationDenied: locationService.isAuthorizationDenied
        )
    }

    private var collectedProgress: (visited: Int, saved: Int, goal: Int) {
        SaveDoodleHomeCatalog.collectedProgress(in: collectedPlaces)
    }

    private var collectedStamps: [Place] {
        SaveDoodleHomeCatalog.collectedStamps(in: collectedPlaces)
    }

    private var collectedText: String {
        let progress = collectedProgress
        return localized(
            "Collected \(progress.visited)/\(progress.saved)",
            "已收集 \(progress.visited)/\(progress.saved)"
        )
    }

    private var latestOtherSave: (place: Place, distance: CLLocationDistance?)? {
        SaveDoodleHomeCatalog.nearestOtherSave(
            in: allPlaces,
            excluding: listedPlaces.map(\.place),
            location: locationService.currentLocation
        )
    }

    private func latestSaveText(_ latest: (place: Place, distance: CLLocationDistance?)) -> String {
        let city = SaveDoodleHomeCatalog.cityDisplayName(
            for: latest.place,
            language: languageSettings.language
        ) ?? latest.place.name
        if let meters = latest.distance {
            return localized(
                "Latest save: \(city) · \(SaveDoodleHomeCatalog.distanceText(meters)) ›",
                "最近的收藏：\(city) · \(SaveDoodleHomeCatalog.distanceText(meters)) ›"
            )
        }
        return localized("Latest save: \(city) ›", "最近的收藏：\(city) ›")
    }

    private func allowLocation() {
        if locationService.isAuthorizationDenied,
           let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
            return
        }
        Task { _ = await locationService.requestCurrentLocation() }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

enum SaveDoodleOfficialSticker: String, CaseIterable {
    case duck, noodle, coffee, temple, lantern, elephant

    var title: String { rawValue.capitalized }

    /// Place marks only. The brand elephant lives in the header, never here.
    static let placeCases: [SaveDoodleOfficialSticker] = [
        .duck, .noodle, .coffee, .temple, .lantern
    ]

    func imageName(visited: Bool, pointSize: CGFloat = 64) -> String {
        if visited {
            return pointSize <= 48
                ? "DoodleSticker\(title)Color48"
                : "DoodleSticker\(title)Color"
        }
        return "DoodleSticker\(title)Outline"
    }

    /// Never returns `.elephant`. Place names that mention an elephant still
    /// use the category mark.
    static func named(
        for category: PlaceCategory,
        placeName: String = ""
    ) -> SaveDoodleOfficialSticker {
        let hint = placeName.lowercased()
        let mapped: SaveDoodleOfficialSticker
        if hint.contains("duck") || hint.contains("烤鴨") || hint.contains("烤鸭") {
            mapped = .duck
        } else if hint.contains("noodle") || hint.contains("ramen") || hint.contains("麵")
            || hint.contains("拉面") || hint.contains("面条") {
            mapped = .noodle
        } else if hint.contains("coffee") || hint.contains("cafe") || hint.contains("咖啡") {
            mapped = .coffee
        } else if hint.contains("temple") || hint.contains("寺") || hint.contains("天壇") || hint.contains("天坛") {
            mapped = .temple
        } else if hint.contains("lantern") || hint.contains("燈") || hint.contains("灯") {
            mapped = .lantern
        } else {
            switch category {
            case .food: mapped = .duck
            case .cafe: mapped = .coffee
            case .bar: mapped = .lantern
            case .attraction: mapped = .temple
            case .stay: mapped = .temple
            case .shopping: mapped = .lantern
            }
        }
        return placeCases.contains(mapped) ? mapped : .temple
    }
}

struct SaveDoodleSticker: View {
    let category: PlaceCategory
    var placeName: String = ""
    let visited: Bool
    var pointSize: CGFloat = SaveLayout.stickerArt
    var boxSize: CGFloat = SaveLayout.stickerBox

    var body: some View {
        let sticker = SaveDoodleOfficialSticker.named(for: category, placeName: placeName)
        Image(sticker.imageName(visited: visited, pointSize: boxSize))
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: pointSize, height: pointSize)
            .frame(width: boxSize, height: boxSize)
            .accessibilityHidden(true)
    }
}

struct SaveDoodleCollectedMark: View {
    let category: PlaceCategory
    var placeName: String = ""

    var body: some View {
        ZStack {
            SaveDoodleInkOval()
                .stroke(SaveDoodle.stampRed, lineWidth: 1.1)
            SaveDoodleCategorySeal(category: category)
                .stroke(SaveDoodle.stampRed, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                .padding(5)
        }
        .frame(width: 24, height: 24)
        .rotationEffect(.degrees(-4))
        .accessibilityHidden(true)
    }
}

struct SaveDoodleDashedDivider: View {
    var color: Color = SaveAtlasPalette.line

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay {
                Rectangle()
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                    )
            }
            .allowsHitTesting(false)
    }
}

struct SaveDoodleEmptyPlate: View {
    var body: some View {
        ZStack {
            Ellipse()
                .stroke(SaveAtlasPalette.ink, lineWidth: 1.5)
                .frame(width: 168, height: 56)
                .offset(y: 18)
            Ellipse()
                .stroke(SaveAtlasPalette.line, lineWidth: 1)
                .frame(width: 128, height: 36)
                .offset(y: 18)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Home light") {
    SaveDoodleHomePreview(empty: false)
        .preferredColorScheme(.light)
}

#Preview("Home dark") {
    SaveDoodleHomePreview(empty: false)
        .preferredColorScheme(.dark)
}

#Preview("Home empty") {
    SaveDoodleHomePreview(empty: true)
        .preferredColorScheme(.light)
}

private struct SaveDoodleHomePreview: View {
    let empty: Bool

    var body: some View {
        SaveDoodleHomeView(
            locationService: LocationService.shared
        )
        .environment(\.atlasPresentation, previewPresentation)
        .environmentObject(SaveDoodleSession(defaults: UserDefaults(suiteName: "save.doodle.preview") ?? .standard))
    }

    private var previewPresentation: AtlasPresentation {
        var presentation = AtlasPresentation.reference
        if empty {
            presentation.savedPlaces = []
            presentation.reviewCount = 0
        } else {
            presentation.reviewCount = 2
        }
        return presentation
    }
}
