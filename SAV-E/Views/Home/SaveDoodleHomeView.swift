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

            citySwitcher
                .padding(.horizontal, SaveLayout.screenMargin)
                .padding(.top, SaveSpace.tight)

            if presentation.reviewCount > 0 {
                cluesLine
                    .padding(.horizontal, SaveLayout.screenMargin)
                    .padding(.top, SaveSpace.xs)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if showsLocationPrompt {
                        locationPrompt
                            .padding(.top, SaveSpace.md)
                    }

                    if showsEmptyHome {
                        emptyHome
                            .padding(.top, SaveSpace.md)
                    } else {
                        miniMap
                            .padding(.top, SaveSpace.md)
                        placeList
                            .padding(.top, SaveSpace.md)
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
        .overlay(alignment: .topLeading) {
            hiddenSavesRoute
        }
        .sheet(isPresented: $showsCityPicker) {
            cityPicker
        }
    }

    /// Always-on Home → Saves handoff. Review (`home.review`) is the visible
    /// entry when N>0; this keeps Saves reachable when the clues line is
    /// omitted. Identifier is `home.openSaves`, not the retired library row.
    /// 44pt in the status-bar corner so UI tests can tap it; Color.clear is
    /// not hittable, so the fill is paper at vanishing opacity.
    private var hiddenSavesRoute: some View {
        Button(action: presentation.onReviewAll) {
            SaveAtlasPalette.paper.opacity(0.01)
                .frame(width: SaveLayout.minTap, height: SaveLayout.minTap)
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

            HStack(spacing: SaveSpace.xs) {
                ForEach(SaveDoodleLens.allCases) { lens in
                    eatGoChip(lens)
                }
            }
        }
        .frame(minHeight: SaveLayout.minTap)
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

                SaveDoodleSticker(category: item.place.category, visited: item.place.status == .visited)
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
                        SaveDoodleCollectedMark(category: place.category)
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
        if SaveDoodleHomeCatalog.isNearbyEmpty(
            places: allPlaces,
            lens: session.lens,
            selection: session.city,
            location: locationService.currentLocation,
            locationDenied: locationService.isAuthorizationDenied
        ) {
            return true
        }
        return listedPlaces.isEmpty
    }

    private var showsLocationPrompt: Bool {
        locationService.isAuthorizationDenied && !showsEmptyHome
    }

    private var showsNearYouPrefix: Bool {
        !locationService.isAuthorizationDenied && session.city == .nearYou
    }

    private var cityTitle: String {
        switch resolvedSelection {
        case .nearYou:
            if let first = listedPlaces.first,
               let name = SaveDoodleHomeCatalog.cityDisplayName(
                for: first.place,
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
        switch resolvedSelection {
        case .nearYou:
            return listedPlaces.map(\.place)
        case .city(let id):
            return allPlaces.filter { SaveDoodleHomeCatalog.cityID(for: $0) == id }
        }
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
            "Collected \(progress.visited)/\(progress.goal)",
            "已收集 \(progress.visited)/\(progress.goal)"
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

    private static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.012),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.012)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

struct SaveDoodleSticker: View {
    let category: PlaceCategory
    let visited: Bool

    var body: some View {
        SaveDoodleStickerShape(category: category)
            .stroke(
                visited ? SaveAtlasPalette.ink : SaveDoodle.pencil,
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 40, height: 40)
            .frame(width: SaveLayout.stickerBox, height: SaveLayout.stickerBox)
            .accessibilityHidden(true)
    }

    static func symbolName(for category: PlaceCategory) -> String {
        switch category {
        case .food: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .bar: return "wineglass"
        case .attraction: return "leaf"
        case .stay: return "bed.double"
        case .shopping: return "bag"
        }
    }
}

nonisolated struct SaveDoodleStickerShape: Shape {
    let category: PlaceCategory

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        switch category {
        case .food:
            path.addEllipse(in: CGRect(x: w * 0.08, y: h * 0.62, width: w * 0.84, height: h * 0.28))
            path.move(to: CGPoint(x: w * 0.22, y: h * 0.58))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.78, y: h * 0.52),
                control: CGPoint(x: w * 0.48, y: h * 0.18)
            )
            path.addQuadCurve(
                to: CGPoint(x: w * 0.28, y: h * 0.58),
                control: CGPoint(x: w * 0.86, y: h * 0.78)
            )
            path.move(to: CGPoint(x: w * 0.70, y: h * 0.30))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.88, y: h * 0.22),
                control: CGPoint(x: w * 0.82, y: h * 0.38)
            )
        case .cafe:
            path.addRoundedRect(
                in: CGRect(x: w * 0.22, y: h * 0.32, width: w * 0.46, height: h * 0.40),
                cornerSize: CGSize(width: w * 0.08, height: h * 0.08)
            )
            path.move(to: CGPoint(x: w * 0.68, y: h * 0.40))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.68, y: h * 0.62),
                control: CGPoint(x: w * 0.86, y: h * 0.51)
            )
            path.addEllipse(in: CGRect(x: w * 0.16, y: h * 0.70, width: w * 0.60, height: h * 0.16))
            path.move(to: CGPoint(x: w * 0.34, y: h * 0.12))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.38, y: h * 0.28),
                control: CGPoint(x: w * 0.22, y: h * 0.20)
            )
            path.move(to: CGPoint(x: w * 0.48, y: h * 0.10))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.52, y: h * 0.28),
                control: CGPoint(x: w * 0.38, y: h * 0.18)
            )
        case .bar:
            path.move(to: CGPoint(x: w * 0.30, y: h * 0.12))
            path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.12))
            path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.42))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.42, y: h * 0.42),
                control: CGPoint(x: w * 0.50, y: h * 0.58)
            )
            path.closeSubpath()
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.50))
            path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.78))
            path.move(to: CGPoint(x: w * 0.32, y: h * 0.88))
            path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.88))
        case .attraction:
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.90))
            path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.42))
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.48))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.16, y: h * 0.62),
                control: CGPoint(x: w * 0.22, y: h * 0.22)
            )
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.42))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.86, y: h * 0.58),
                control: CGPoint(x: w * 0.78, y: h * 0.16)
            )
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.28))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.28, y: h * 0.18),
                control: CGPoint(x: w * 0.42, y: h * 0.06)
            )
        case .stay:
            path.move(to: CGPoint(x: w * 0.14, y: h * 0.62))
            path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.38))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.38, y: h * 0.22),
                control: CGPoint(x: w * 0.16, y: h * 0.18)
            )
            path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.22))
            path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.62))
            path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.62))
            path.move(to: CGPoint(x: w * 0.14, y: h * 0.62))
            path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.82))
            path.move(to: CGPoint(x: w * 0.86, y: h * 0.62))
            path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.82))
            path.move(to: CGPoint(x: w * 0.10, y: h * 0.82))
            path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.82))
        case .shopping:
            path.move(to: CGPoint(x: w * 0.22, y: h * 0.36))
            path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.88))
            path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.88))
            path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.36))
            path.closeSubpath()
            path.move(to: CGPoint(x: w * 0.34, y: h * 0.36))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.66, y: h * 0.36),
                control: CGPoint(x: w * 0.50, y: h * 0.08)
            )
        }
        return path
    }
}

struct SaveDoodleCollectedMark: View {
    let category: PlaceCategory

    var body: some View {
        ZStack {
            Circle()
                .stroke(SaveDoodle.stampRed, lineWidth: 1.5)
                .frame(width: 24, height: 24)
            Image(systemName: SaveDoodleSticker.symbolName(for: category))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(SaveDoodle.stampRed)
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

struct SaveDoodleElephant: View {
    var size: CGFloat = 28

    var body: some View {
        SaveDoodleElephantShape()
            .stroke(SaveAtlasPalette.forest, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

nonisolated struct SaveDoodleElephantShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.22, y: h * 0.62))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.62, y: h * 0.38),
            control: CGPoint(x: w * 0.18, y: h * 0.18)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.86, y: h * 0.42),
            control: CGPoint(x: w * 0.80, y: h * 0.22)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.72, y: h * 0.62),
            control: CGPoint(x: w * 0.96, y: h * 0.52)
        )
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.86))
        path.move(to: CGPoint(x: w * 0.38, y: h * 0.62))
        path.addLine(to: CGPoint(x: w * 0.34, y: h * 0.86))
        path.move(to: CGPoint(x: w * 0.52, y: h * 0.62))
        path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.86))
        path.move(to: CGPoint(x: w * 0.86, y: h * 0.42))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.92, y: h * 0.72),
            control: CGPoint(x: w * 1.02, y: h * 0.52)
        )
        return path
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
