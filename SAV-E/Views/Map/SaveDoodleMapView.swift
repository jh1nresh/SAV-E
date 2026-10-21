import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Founder lock 2026-10-20: coral numbered markers on the product Map.
/// Outline lollipops match the DESIGN golden (paper fill, coral stroke).
/// Flip `current` to `.appleDefault` for unstyled Apple pins without
/// rewriting the Map surface, header, or place sheet.
enum SaveDoodleMapPinStyle {
    enum Kind: String {
        case coralNumbered
        case appleDefault
    }

    static var current: Kind = .coralNumbered
}

/// Product Map tab: default Apple MapKit with Doodle chrome (city, Eat/Go,
/// paper place sheet, 我來過了). No muted emphasis, paper overlay, custom
/// tiles, or tile-town.
struct SaveDoodleMapView: View {
    @ObservedObject var mapViewModel: MapViewModel
    let presentation: AtlasPresentation
    let onClearSelection: () -> Void
    let onPlanAroundPlace: (Place) -> Void

    @Environment(\.appLanguageSettings) private var languageSettings
    @EnvironmentObject private var session: SaveDoodleSession
    @ObservedObject private var locationService = LocationService.shared
    @StateObject private var checkIns = SaveDoodleCheckInStore()
    @State private var showsCityPicker = false
    @State private var stampPulse = false

    var body: some View {
        let followsHomeFilter = session.mapFollowsHomeFilter
        let visitResidue = session.mapVisitResidueID
        return VStack(spacing: 0) {
            header(followsHomeFilter: followsHomeFilter)
                .id(visitResidue)
                .padding(.horizontal, SaveLayout.screenMargin)
                .padding(.top, AtlasMetrics.statusBarHeight + SaveSpace.xs)
                .padding(.bottom, SaveSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SaveAtlasPalette.paper)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("map.headerBand")

            ZStack(alignment: .top) {
                mapCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if mapViewModel.showsLocationDeniedNotice {
                    SaveLocationDeniedNotice(
                        onOpenSettings: openSystemSettings,
                        onDismiss: {
                            withAnimation(SaveTheme.Motion.standardSpring) {
                                mapViewModel.showsLocationDeniedNotice = false
                            }
                        }
                    )
                    .padding(.top, SaveSpace.sm)
                    .padding(.horizontal, SaveLayout.screenMargin)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .top)
        .background(SaveAtlasPalette.paper)
        .overlay(alignment: .bottom) {
            VStack(spacing: SaveSpace.md) {
                Spacer(minLength: 0)
                if mapViewModel.selectedPlace == nil {
                    HStack {
                        Spacer(minLength: 0)
                        locateButton
                    }
                    .padding(.horizontal, SaveLayout.screenMargin)
                }

                if let place = mapViewModel.selectedPlace {
                    placeSheet(place)
                        .padding(.horizontal, SaveLayout.screenMargin)
                }
            }
            .padding(.bottom, bottomChromeClearance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            _ = onPlanAroundPlace
            applyMiniMapHandoff()
            selectParityPlaceIfNeeded()
            fitVisiblePlaces()
        }
        .onChange(of: session.mapVisitResidueID) { _, _ in
            applyMiniMapHandoff()
            selectParityPlaceIfNeeded()
            fitVisiblePlaces()
        }
        .onChange(of: mapViewModel.places.map(\.id)) { _, _ in
            selectParityPlaceIfNeeded()
            fitVisiblePlaces()
        }
        .onChange(of: mapViewModel.selectedPlace?.id) { _, _ in
            fitVisiblePlaces()
        }
        .onChange(of: session.lens) { _, _ in
            if followsHomeFilter {
                onClearSelection()
            }
            fitVisiblePlaces()
        }
        .onChange(of: session.city) { _, _ in
            if followsHomeFilter {
                onClearSelection()
            }
            fitVisiblePlaces()
        }
        .onChange(of: session.mapFollowsHomeFilter) { _, follows in
            if follows {
                onClearSelection()
            }
            fitVisiblePlaces()
        }
        .onChange(of: mapViewModel.selectedMapFeature) { _, feature in
            mapViewModel.selectMapFeature(feature)
        }
        .sheet(isPresented: $showsCityPicker) {
            cityPicker
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Mini-map residue remounts Eat/Go on a reused Map tab identity.
    private func applyMiniMapHandoff() {
        session.consumeMiniMapHandoff()
        showsCityPicker = false
    }

    private var mapCanvas: some View {
        Map(position: $mapViewModel.cameraPosition, selection: $mapViewModel.selectedMapFeature) {
            UserAnnotation()

            if SaveDoodleMapPinStyle.current == .appleDefault {
                ForEach(displayedListedPlaces) { item in
                    if item.place.isMapKitMappable {
                        Marker(item.place.name, coordinate: item.place.coordinate)
                    }
                }
            } else {
                ForEach(displayedListedPlaces) { item in
                    if item.place.isMapKitMappable {
                        Annotation("", coordinate: item.place.coordinate, anchor: .bottom) {
                            SaveDoodleCoralPin(
                                index: item.index,
                                title: item.place.name,
                                visited: item.place.status == .visited,
                                isSelected: mapViewModel.selectedPlace?.id == item.place.id,
                                dimmed: mapViewModel.selectedPlace != nil
                                    && mapViewModel.selectedPlace?.id != item.place.id
                            ) {
                                mapViewModel.selectPlace(item.place)
                            }
                            .accessibilityLabel(
                                mapViewModel.selectedPlace?.id == item.place.id
                                    ? "Selected Map Stamp, \(item.place.name)"
                                    : "\(item.place.status == .visited ? "Visited Map Stamp" : "Map Stamp"), \(item.place.name)"
                            )
                            .accessibilityIdentifier("map.tilePin.\(item.place.id.uuidString)")
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }

            if let polyline = mapViewModel.routePolyline {
                MapPolyline(polyline)
                    .stroke(
                        SaveAtlasPalette.ink.opacity(0.76),
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [7, 5]
                        )
                    )
            }
        }
        .mapStyle(.standard)
        .mapFeatureSelectionDisabled { feature in
            feature.kind != .pointOfInterest
        }
        .mapControls {
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            mapViewModel.updateVisibleMapRegion(context.region)
        }
        .accessibilityIdentifier("map.liveSurface")
    }

    @ViewBuilder
    private func header(followsHomeFilter: Bool) -> some View {
        VStack(alignment: .leading, spacing: SaveSpace.sm) {
            Button { showsCityPicker = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: SaveSpace.tight) {
                    VStack(alignment: .leading, spacing: 0) {
                        SaveDisplayTitle(
                            text: cityTitle,
                            pointSize: 32,
                            relativeTo: .title
                        )
                        Capsule()
                            .fill(SaveAtlasPalette.coral)
                            .frame(height: 2)
                            .padding(.top, 1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    Text("▾")
                        .font(SaveAtlasType.body(16))
                        .foregroundStyle(SaveAtlasPalette.forest)
                }
                .frame(minHeight: SaveLayout.minTap, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                languageSettings.localized(english: "Choose city", traditionalChinese: "選擇城市")
                    + ", " + cityTitle
            )
            .accessibilityIdentifier("map.city")
            .accessibilityAddTraits(.isButton)

            HStack {
                Spacer(minLength: 0)
                eatGoRail
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityValue(followsHomeFilter ? "filtered" : "all")
    }

    private var eatGoRail: some View {
        HStack(spacing: SaveSpace.xs) {
            ForEach(SaveDoodleLens.allCases) { item in
                let selected = session.lens == item
                Button {
                    SaveHaptics.select()
                    let reselecting = session.lens == item
                    session.lens = item
                    session.mapFollowsHomeFilter = true
                    if reselecting {
                        onClearSelection()
                        fitVisiblePlaces()
                    }
                } label: {
                    Text(item.title(language: languageSettings.language))
                        .font(SaveAtlasType.strong(15))
                        .foregroundStyle(selected ? Color.white : SaveAtlasPalette.ink)
                        .frame(minWidth: SaveLayout.minTap, minHeight: SaveLayout.chipHeight)
                        .padding(.horizontal, SaveSpace.md)
                        .background(
                            selected ? SaveAtlasPalette.coral : Color.clear,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    selected ? Color.clear : SaveAtlasPalette.ink,
                                    lineWidth: SaveAtlasPalette.strokeWidth
                                )
                        }
                        .frame(minHeight: SaveLayout.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: SaveLayout.minTap)
                .accessibilityIdentifier(item.mapAccessibilityIdentifier)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.eatGo")
    }

    private func placeSheet(_ place: Place) -> some View {
        let listed = displayedListedPlaces.first(where: { $0.place.id == place.id })
        let visited = place.status == .visited || checkIns.visitCount(for: place.id) > 0
        let checkedInToday = checkIns.hasCheckedInToday(placeID: place.id)
        return VStack(spacing: 0) {
            Capsule()
                .fill(SaveAtlasPalette.line)
                .frame(width: 36, height: 5)
                .padding(.top, SaveSpace.xs)
                .padding(.bottom, SaveSpace.md)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: SaveLayout.stickerToText) {
                Button {
                    presentation.onOpenPlace(place.id.uuidString)
                    onClearSelection()
                } label: {
                    HStack(alignment: .center, spacing: SaveLayout.stickerToText) {
                        ZStack {
                            SaveDoodleSticker(
                                category: place.category,
                                placeName: place.name,
                                visited: visited,
                                pointSize: SaveLayout.passportSlot,
                                boxSize: SaveLayout.passportSlot
                            )
                            if visited {
                                Circle()
                                    .stroke(SaveDoodle.stampRed, lineWidth: 2)
                                    .frame(
                                        width: SaveLayout.passportSlot,
                                        height: SaveLayout.passportSlot
                                    )
                                    .rotationEffect(.degrees(stampAngle(for: place.id)))
                                    .scaleEffect(stampPulse ? 1 : 0.82)
                            }
                        }
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: SaveLayout.titleToMeta) {
                            Text(place.name)
                                .font(SaveAtlasType.strong(20, relativeTo: .title3))
                                .foregroundStyle(SaveAtlasPalette.ink)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("map.peek.name")
                            Text(metaText(for: place, listed: listed))
                                .font(SaveAtlasType.body(13))
                                .foregroundStyle(SaveAtlasPalette.muted)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("map.peek.subtitle")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(place.name)
                .accessibilityIdentifier("map.peek.card")
            }

            HStack(spacing: SaveSpace.sm) {
                Button {
                    SaveHaptics.tap()
                    NavigationService.navigate(to: place.coordinate, name: place.name, mode: .walking)
                } label: {
                    Text(languageSettings.localized(english: "Directions", traditionalChinese: "導航"))
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: SaveLayout.buttonHeight)
                        .background(SaveAtlasPalette.coral, in: RoundedRectangle(
                            cornerRadius: SaveAtlasPalette.cardRadius,
                            style: .continuous
                        ))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.directions")

                if checkedInToday {
                    Button {
                        undoCheckIn(place)
                    } label: {
                        Text(languageSettings.localized(english: "Undo visit", traditionalChinese: "撤銷打卡"))
                            .font(SaveAtlasType.strong(17))
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .frame(maxWidth: .infinity, minHeight: SaveLayout.buttonHeight)
                            .background(
                                SaveAtlasPalette.paper,
                                in: RoundedRectangle(
                                    cornerRadius: SaveAtlasPalette.cardRadius,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: SaveAtlasPalette.cardRadius,
                                    style: .continuous
                                )
                                .stroke(SaveAtlasPalette.ink, lineWidth: SaveAtlasPalette.strokeWidth)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(checkIns.isPersisting(placeID: place.id))
                    .accessibilityIdentifier("map.checkIn.undo")
                } else {
                    Button {
                        performCheckIn(place)
                    } label: {
                        Text(languageSettings.localized(english: "I've been here", traditionalChinese: "我來過了"))
                            .font(SaveAtlasType.strong(17))
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .frame(maxWidth: .infinity, minHeight: SaveLayout.buttonHeight)
                            .background(
                                SaveAtlasPalette.paper,
                                in: RoundedRectangle(
                                    cornerRadius: SaveAtlasPalette.cardRadius,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: SaveAtlasPalette.cardRadius,
                                    style: .continuous
                                )
                                .stroke(SaveAtlasPalette.ink, lineWidth: SaveAtlasPalette.strokeWidth)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(checkIns.isPersisting(placeID: place.id))
                    .accessibilityIdentifier("map.checkIn")
                }
            }
            .padding(.top, SaveSpace.md)
        }
        .padding(.horizontal, SaveLayout.screenMargin)
        .padding(.bottom, SaveSpace.md)
        .background(
            SaveAtlasPalette.paper,
            in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                .stroke(SaveAtlasPalette.line, lineWidth: SaveAtlasPalette.strokeWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.placeSheet")
    }

    private var locateButton: some View {
        Button {
            SaveHaptics.tap()
            Task { await mapViewModel.focusOnUserLocation() }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(width: 48, height: 48)
                .background(SaveAtlasPalette.paper, in: Circle())
                .overlay {
                    Circle().stroke(SaveAtlasPalette.line, lineWidth: SaveAtlasPalette.strokeWidth)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(languageSettings.localized(
            english: "Center map on current location",
            traditionalChinese: "將地圖移到目前位置"
        ))
        .accessibilityIdentifier("map.currentLocation")
    }

    private var cityPicker: some View {
        NavigationStack {
            List {
                if !locationService.isAuthorizationDenied {
                    Button {
                        session.city = .nearYou
                        session.mapFollowsHomeFilter = true
                        showsCityPicker = false
                    } label: {
                        HStack {
                            Text(languageSettings.localized(
                                english: "Near you (current location)",
                                traditionalChinese: "附近（目前位置）"
                            ))
                            Spacer()
                            if case .nearYou = session.city {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SaveAtlasPalette.coral)
                            }
                        }
                    }
                    .accessibilityIdentifier("map.city.nearYou")
                }
                ForEach(cityGroups) { group in
                    Button {
                        session.city = .city(group.id)
                        session.mapFollowsHomeFilter = true
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
                    .accessibilityIdentifier("map.city.\(group.id)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SaveAtlasPalette.paper)
            .navigationTitle(languageSettings.localized(english: "City", traditionalChinese: "城市"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageSettings.localized(english: "Close", traditionalChinese: "關閉")) {
                        showsCityPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var displayedListedPlaces: [SaveDoodleListedPlace] {
        if session.mapFollowsHomeFilter {
            return SaveDoodleHomeCatalog.listedPlaces(
                from: mapViewModel.places,
                lens: session.lens,
                selection: session.city,
                location: locationService.isAuthorizationDenied ? nil : locationService.currentLocation,
                locationDenied: locationService.isAuthorizationDenied
            )
        }
        return mapViewModel.places
            .filter(\.isMapKitMappable)
            .enumerated()
            .map { index, place in
                SaveDoodleListedPlace(
                    place: place,
                    index: index + 1,
                    distance: locationService.currentLocation.flatMap {
                        SaveDoodleHomeCatalog.distance(from: $0, to: place)
                    }
                )
            }
    }

    private var resolvedSelection: SaveDoodleCitySelection {
        SaveDoodleHomeCatalog.resolvedSelection(
            session.city,
            places: mapViewModel.places,
            locationDenied: locationService.isAuthorizationDenied
        )
    }

    private var cityGroups: [SaveDoodleCityGroup] {
        SaveDoodleHomeCatalog.cityGroups(from: mapViewModel.places)
    }

    private var cityTitle: String {
        switch resolvedSelection {
        case .nearYou:
            return languageSettings.localized(english: "Near you", traditionalChinese: "附近")
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

    private var bottomChromeClearance: CGFloat {
        if mapViewModel.selectedPlace != nil {
            // Search shelf is hidden. Sit the paper sheet on the 62pt tab bar.
            return AtlasTabBarMetrics.height + SaveSpace.md
        }
        // Locate must stay above the collapsed 64pt search shelf (test: maxY
        // <= shelf.minY - 4). Original clearance 160 clears that band.
        return 160
    }

    private func selectParityPlaceIfNeeded() {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--uitest-map-place-selected") else { return }
        guard mapViewModel.selectedPlace == nil else { return }
        let taipei = mapViewModel.places.first { place in
            abs(place.latitude - 25.04) < 0.35 && abs(place.longitude - 121.56) < 0.35
        }
        mapViewModel.selectedPlace = taipei ?? mapViewModel.places.first
#endif
    }

    private func metaText(for place: Place, listed: SaveDoodleListedPlace?) -> String {
        let lens = SaveDoodleHomeCatalog.lens(for: place.category)
            .title(language: languageSettings.language)
        if let meters = listed?.distance {
            return "\(lens) · \(SaveDoodleHomeCatalog.distanceText(meters))"
        }
        if let area = SaveDoodleHomeCatalog.cityDisplayName(
            for: place,
            language: languageSettings.language
        ) {
            return "\(lens) · \(area)"
        }
        return lens
    }

    private func performCheckIn(_ place: Place) {
        var updated = place
        updated.status = .visited
        Task {
            let accepted = await checkIns.applyCheckIn(
                placeID: place.id,
                priorStatus: place.status
            ) {
                try await mapViewModel.updatePlace(updated)
            }
            guard accepted else { return }
            SaveHaptics.stamp()
            stampPulse = false
            withAnimation(SaveTheme.Motion.stampSpring) {
                stampPulse = true
            }
        }
    }

    private func undoCheckIn(_ place: Place) {
        Task {
            let accepted = await checkIns.applyUndo(placeID: place.id) { restoreStatus in
                guard place.status != restoreStatus else { return }
                var updated = place
                updated.status = restoreStatus
                try await mapViewModel.updatePlace(updated)
            }
            guard accepted else { return }
            stampPulse = false
        }
    }

    private func stampAngle(for id: UUID) -> Double {
        var hasher = Hasher()
        hasher.combine(id)
        return Double(abs(hasher.finalize()) % 13) - 6
    }

    private func fitVisiblePlaces() {
        // Show-on-Map for a collaborative list already aimed the camera at
        // `routePolyline`. Do not snap back to personal city stamps.
        if mapViewModel.routePolyline != nil {
            return
        }
        if let selected = mapViewModel.selectedPlace, selected.isMapKitMappable {
            mapViewModel.cameraPosition = .region(
                MKCoordinateRegion(
                    center: selected.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                )
            )
            return
        }
        let pins = cityOpeningPins()
        if !pins.isEmpty {
            mapViewModel.cameraPosition = .region(Self.region(fitting: pins))
            return
        }
        if let fallback = cityOpeningFallback() {
            mapViewModel.cameraPosition = .region(
                MKCoordinateRegion(
                    center: fallback,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            )
        }
    }

    /// Pins in the current city (or nearby, when Near you has a fix).
    /// Never fits the worldwide set — that opens over Europe/Africa.
    private func cityOpeningPins() -> [CLLocationCoordinate2D] {
        let denied = locationService.isAuthorizationDenied
        let location = denied ? nil : locationService.currentLocation
        var selection = SaveDoodleHomeCatalog.resolvedSelection(
            session.city,
            places: mapViewModel.places,
            locationDenied: denied
        )
        if case .nearYou = selection, location == nil {
            let newest = mapViewModel.places.sorted(by: SaveDoodleHomeCatalog.moreRecent).first
            if let newest, let id = SaveDoodleHomeCatalog.cityID(for: newest) {
                selection = .city(id)
            }
        }
        let lenses: [SaveDoodleLens] = session.mapFollowsHomeFilter
            ? [session.lens]
            : Array(SaveDoodleLens.allCases)
        var coords: [CLLocationCoordinate2D] = []
        for lens in lenses {
            for place in SaveDoodleHomeCatalog.visiblePlaces(
                from: mapViewModel.places,
                lens: lens,
                selection: selection,
                location: location,
                locationDenied: denied
            ) where place.isMapKitMappable {
                coords.append(place.coordinate)
            }
        }
        return coords
    }

    private func cityOpeningFallback() -> CLLocationCoordinate2D? {
        let denied = locationService.isAuthorizationDenied
        let selection = SaveDoodleHomeCatalog.resolvedSelection(
            session.city,
            places: mapViewModel.places,
            locationDenied: denied
        )
        let cityID: String?
        switch selection {
        case .city(let id):
            cityID = id
        case .nearYou:
            cityID = mapViewModel.places.compactMap { SaveDoodleHomeCatalog.cityID(for: $0) }.first
        }
        if let cityID {
            let inCity = mapViewModel.places.first {
                SaveDoodleHomeCatalog.cityID(for: $0) == cityID && $0.isMapKitMappable
            }
            if let inCity {
                return inCity.coordinate
            }
        }
        return locationService.currentLocation?.coordinate
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
            latitudeDelta: min(max((maxLat - minLat) * 1.6, 0.012), 0.45),
            longitudeDelta: min(max((maxLon - minLon) * 1.6, 0.012), 0.45)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

struct SaveDoodleCoralPin: View {
    let index: Int
    let title: String
    let visited: Bool
    let isSelected: Bool
    let dimmed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                ZStack {
                    SaveDoodleLollipopShape()
                        .fill(SaveAtlasPalette.paper)
                    SaveDoodleLollipopShape()
                        .stroke(pinColor, lineWidth: 2)
                    Text("\(index)")
                        .font(SaveAtlasType.strong(13))
                        .foregroundStyle(pinColor)
                        .offset(y: -stemHeight / 2)
                }
                .frame(width: headDiameter, height: pinHeight)

                if isSelected {
                    Text(title)
                        .font(SaveAtlasType.strong(13))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .padding(.horizontal, SaveSpace.xs)
                        .padding(.vertical, SaveSpace.tight)
                        .background(SaveAtlasPalette.kraft, in: Capsule())
                        .lineLimit(1)
                        .offset(y: -(pinHeight + SaveSpace.tight))
                }
            }
            .opacity(dimmed ? 0.6 : 1)
            .animation(SaveTheme.Motion.standardSpring, value: isSelected)
        }
        .buttonStyle(.plain)
        .frame(minWidth: SaveLayout.minTap, minHeight: SaveLayout.minTap, alignment: .bottom)
        .contentShape(Rectangle())
    }

    private var pinColor: Color {
        visited ? SaveDoodle.stampRed : SaveAtlasPalette.coral
    }

    private var headDiameter: CGFloat {
        isSelected ? 32 : 26
    }

    private var stemHeight: CGFloat {
        isSelected ? 12 : 10
    }

    private var pinHeight: CGFloat {
        headDiameter + stemHeight
    }
}

/// DESIGN golden pin: numbered circle on a short stem — outline, not a fill.
struct SaveDoodleLollipopShape: Shape {
    func path(in rect: CGRect) -> Path {
        let stemWidth = max(2.5, rect.width * 0.14)
        let stemHeight = max(8, rect.height * 0.28)
        let headDiameter = min(rect.width, rect.height - stemHeight)
        let radius = headDiameter / 2
        let center = CGPoint(x: rect.midX, y: radius)
        let halfStem = stemWidth / 2
        let attach = min(radius - 0.5, max(0, sqrt(max(0, radius * radius - halfStem * halfStem))))
        let start = Angle.radians(Double.pi - asin(Double(min(1, halfStem / max(radius, 0.1)))))
        let end = Angle.radians(asin(Double(min(1, halfStem / max(radius, 0.1)))))
        var path = Path()
        path.move(to: CGPoint(x: center.x - halfStem, y: rect.maxY))
        path.addLine(to: CGPoint(x: center.x - halfStem, y: center.y + attach))
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        path.addLine(to: CGPoint(x: center.x + halfStem, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
