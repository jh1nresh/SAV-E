import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Doodle v1 Home: nearby Eat/Go list, city switcher, and a native MapKit
/// mini-map. Replaces the tile-town Home peek (spec §7.1, HoP D2/D3).
struct SaveDoodleHomeView: View {
    @Environment(\.atlasPresentation) private var presentation
    @Environment(\.appLanguageSettings) private var languageSettings
    @EnvironmentObject private var session: SaveDoodleSession
    @ObservedObject var locationService: LocationService
    let onOpenMap: () -> Void

    @State private var showsCityPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: SaveLayout.minTap)
                .padding(.horizontal, SaveLayout.screenMargin)
                .padding(.top, AtlasMetrics.statusBarHeight + SaveSpace.xs)
                .zIndex(2)

            ZStack(alignment: .trailing) {
                citySwitcher
                if presentation.reviewCount == 0 {
                    savesButton
                }
            }
            .padding(.horizontal, SaveLayout.screenMargin)
            .padding(.top, SaveSpace.tight)

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

                    if presentation.reviewCount > 0 {
                        cluesLine
                            .padding(.top, SaveSpace.xs)
                    }

                    if showsLensEmpty {
                        lensEmpty
                            .padding(.top, SaveSpace.md)
                    } else if !showsEmptyHome {
                        miniMap
                            .padding(.top, SaveSpace.md)
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
    }

    /// A visible production route, also available when there are no waiting clues.
    private var savesButton: some View {
        Button(action: presentation.onReviewAll) {
            Label(localized("Saves", "收藏"), systemImage: "bookmark")
                .font(SaveAtlasType.body(15))
                .foregroundStyle(SaveAtlasPalette.ink)
                .padding(.horizontal, SaveSpace.xs)
                .frame(minWidth: SaveLayout.minTap, minHeight: SaveLayout.minTap)
                .padding(.vertical, 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.openSaves")
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
                    SaveDoodleElephant(size: 28)
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
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(selected ? Color.clear : SaveAtlasPalette.ink, lineWidth: SaveAtlasPalette.strokeWidth)
                }
                .contentShape(Capsule())
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
        Button(action: presentation.onReviewAll) {
            HStack(spacing: SaveSpace.tight) {
                Text(cluesText)
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                Text("·")
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                Text(localized("Review", "確認"))
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                Text("›")
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: SaveLayout.minTap, alignment: .leading)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cluesText)
        .accessibilityIdentifier("home.review")
        .accessibilityAddTraits(.isButton)
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
                        Capsule()
                            .stroke(SaveAtlasPalette.ink, lineWidth: SaveAtlasPalette.strokeWidth)
                    }
                    .contentShape(Capsule())
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

    private var miniMap: some View {
        SaveDoodleMiniMap(
            places: listedPlaces,
            userLocation: locationService.currentLocation
        )
        .id(listedPlaces.map(\.place.id))
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                .stroke(SaveAtlasPalette.line, lineWidth: SaveAtlasPalette.strokeWidth)
                .allowsHitTesting(false)
        }
        .overlay {
            Button(action: onOpenMap) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(localized("Open map", "打開地圖"))
            .accessibilityIdentifier("home.miniMap")
        }
    }

    private var placeList: some View {
        VStack(spacing: 0) {
            ForEach(Array(listedPlaces.enumerated()), id: \.element.id) { index, item in
                placeRow(item)
                if index < listedPlaces.count - 1 {
                    SaveDoodleDashedDivider()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.placeList")
    }

    private func placeRow(_ item: SaveDoodleListedPlace) -> some View {
        Button { presentation.onOpenPlace(item.place.id.uuidString) } label: {
            HStack(alignment: .center, spacing: 0) {
                Text("\(item.index)")
                    .font(SaveAtlasType.strong(13))
                    .foregroundStyle(Color.white)
                    .frame(width: SaveLayout.numberBadge, height: SaveLayout.numberBadge)
                    .background(SaveAtlasPalette.coral, in: Circle())
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
                    Text(metaText(for: item))
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, SaveLayout.rowVerticalPadding)
            .frame(minHeight: SaveLayout.rowMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.index), \(item.place.name), \(metaText(for: item))")
        .accessibilityIdentifier("home.place.\(item.place.id.uuidString)")
    }

    private var collectedStrip: some View {
        Button(action: presentation.onOpenPassport) {
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
            .background(SaveAtlasPalette.kraft, in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous))
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
                }
                .buttonStyle(.plain)
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
        presentation.savedPlaces.compactMap(\.searchPlace)
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

    private var cluesText: String {
        let count = presentation.reviewCount
        return languageSettings.language == .traditionalChinese
            ? "\(count) 個線索等待確認"
            : (count == 1 ? "1 clue waiting" : "\(count) clues waiting")
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

    private func metaText(for item: SaveDoodleListedPlace) -> String {
        let lens = session.lens.title(language: languageSettings.language)
        if let meters = item.distance {
            return "\(lens) · \(SaveDoodleHomeCatalog.distanceText(meters))"
        }
        if let area = SaveDoodleHomeCatalog.cityDisplayName(
            for: item.place,
            language: languageSettings.language
        ) {
            return "\(lens) · \(area)"
        }
        return lens
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

struct SaveDoodleMiniMap: View {
    let places: [SaveDoodleListedPlace]
    let userLocation: CLLocation?

    var body: some View {
        Map(initialPosition: camera, interactionModes: []) {
            ForEach(places) { item in
                if item.place.isMapKitMappable {
                    Marker(
                        item.place.name,
                        monogram: Text("\(item.index)"),
                        coordinate: CLLocationCoordinate2D(
                            latitude: item.place.latitude,
                            longitude: item.place.longitude
                        )
                    )
                    .tint(item.place.status == .visited ? SaveDoodle.stampRed : SaveAtlasPalette.coral)
                }
            }
        }
        .mapStyle(.standard(emphasis: .automatic))
        .allowsHitTesting(false)
    }

    private var camera: MapCameraPosition {
        let coords = places.compactMap { item -> CLLocationCoordinate2D? in
            guard item.place.isMapKitMappable else { return nil }
            return CLLocationCoordinate2D(latitude: item.place.latitude, longitude: item.place.longitude)
        }
        if coords.count == 1 {
            return .region(MKCoordinateRegion(
                center: coords[0],
                latitudinalMeters: 1_400,
                longitudinalMeters: 1_400
            ))
        }
        if coords.count > 1 {
            return .region(Self.region(fitting: coords))
        }
        if let userLocation {
            return .region(MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 2_000,
                longitudinalMeters: 2_000
            ))
        }
        return .automatic
    }

    static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        let originLon = coordinates[0].longitude
        var minLon = originLon
        var maxLon = originLon
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            let lon = unwrappedLongitude(coordinate.longitude, around: originLon)
            minLon = min(minLon, lon)
            maxLon = max(maxLon, lon)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: normalizedLongitude((minLon + maxLon) / 2)
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.012),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.012)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Pins at 179.99 and -179.99 are neighbors, not a 360° world span.
    private static func unwrappedLongitude(_ longitude: Double, around origin: Double) -> Double {
        var value = longitude
        while value - origin > 180 { value -= 360 }
        while value - origin < -180 { value += 360 }
        return value
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var value = longitude
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }
}

enum SaveDoodleOfficialSticker: String, CaseIterable {
    case duck, noodle, coffee, temple, lantern, elephant

    var title: String { rawValue.capitalized }

    /// Place marks only. `.elephant` is brand-only (wordmark / empty Home).
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
        SaveDoodleSticker(
            category: category,
            placeName: placeName,
            visited: true,
            pointSize: 20,
            boxSize: 24
        )
        .overlay {
            Circle()
                .stroke(SaveDoodle.stampRed, lineWidth: 1.2)
        }
        .rotationEffect(.degrees(-4))
        .accessibilityHidden(true)
    }
}

struct SaveDoodleDashedDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay {
                Rectangle()
                    .stroke(
                        SaveAtlasPalette.line,
                        style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                    )
            }
            .allowsHitTesting(false)
    }
}

/// Brand elephant. Not a place sticker — wordmark and empty Home only.
struct SaveDoodleElephant: View {
    var size: CGFloat = 28

    var body: some View {
        Image(SaveDoodleOfficialSticker.elephant.imageName(visited: true, pointSize: size))
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
            SaveDoodleElephant(size: 44)
                .offset(x: 52, y: -8)
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
            locationService: LocationService.shared,
            onOpenMap: {}
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
