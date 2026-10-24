import CoreLocation
import MapKit
import SwiftUI

/// Product Map tab: full-pixel tile-town base with Nearby / Saved / Friends
/// lenses. Drawer search and Trip MapKit stay elsewhere. Home has no
/// mini-map (founder option B, 2026-10-24). Place-detail "View on map"
/// may show Home's current Eat/Go + city; two-way sharing stays with #298.
struct SaveTileTownRootMap: View {
    @ObservedObject var mapViewModel: MapViewModel
    let presentation: AtlasPresentation
    let onClearSelection: () -> Void
    let onPlanAroundPlace: (Place) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @EnvironmentObject private var session: SaveDoodleSession
    @ObservedObject private var locationService = LocationService.shared
    @State private var lens: SaveTileTownMapLens = .saved
    @State private var showsHomeSessionChrome = false

    var body: some View {
        ZStack(alignment: .top) {
            SaveAtlasPalette.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, AtlasMetrics.statusBarHeight)

                lensRail
                    .padding(.horizontal, 16)

                ZStack(alignment: .bottomLeading) {
                    SaveTileTownCanvas(
                        pins: visiblePins,
                        clipsToPaper: false,
                        allowsPan: true,
                        onSelect: selectPin
                    )
                    .accessibilityIdentifier("map.liveSurface")

                    if let place = mapViewModel.selectedPlace {
                        Button {
                            presentation.onOpenPlace(place.id.uuidString)
                        } label: {
                            SaveTileTownPeekCard(
                                title: place.name,
                                subtitle: place.createdAt.formatted(date: .abbreviated, time: .omitted)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .accessibilityIdentifier("map.peek.card")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        lens = .nearby
                        Task { _ = await locationService.requestCurrentLocation() }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(SaveAtlasPalette.forest)
                            .frame(width: 48, height: 48)
                            .background(SaveAtlasPalette.paper, in: Circle())
                            .overlay {
                                Circle().stroke(SaveAtlasPalette.line.opacity(0.22), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(languageSettings.localized(
                        english: "Center map on current location",
                        traditionalChinese: "將地圖移到目前位置"
                    ))
                    .accessibilityIdentifier("map.currentLocation")
                    .padding(.trailing, 14)
                    .padding(.top, 14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(SaveAtlasPalette.line.opacity(0.22), lineWidth: 1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 96)
            }
#if DEBUG
            cameraProbe
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { consumeShowOnMap() }
        .onChange(of: session.pendingShowOnMapPlaceID) { _, _ in
            consumeShowOnMap()
        }
        .onChange(of: lens) { _, newLens in
            if newLens == .friends {
                mapViewModel.selectSocialLens(.forYou)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if showsHomeSessionChrome {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    SaveDisplayTitle(text: "Savvy", pointSize: 28)
                        .accessibilityIdentifier("map.wordmark")
                    Text(cityTitle)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("map.city")
                }
                Spacer(minLength: 8)
                homeSessionRail
            }
        } else {
            SaveDisplayTitle(text: "Savvy", pointSize: 28)
                .accessibilityIdentifier("map.wordmark")
        }
    }

    private var homeSessionRail: some View {
        HStack(spacing: 8) {
            ForEach(SaveDoodleLens.allCases) { item in
                let selected = session.lens == item
                Text(item.title(language: languageSettings.language))
                    .font(SaveAtlasType.strong(13))
                    .foregroundStyle(selected ? Color.white : SaveAtlasPalette.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
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
                    .accessibilityIdentifier("map.\(item.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.eatGo")
    }

    private var lensRail: some View {
        HStack(spacing: 8) {
            ForEach(SaveTileTownMapLens.allCases) { item in
                Button {
                    lens = item
                    if item != .saved, mapViewModel.selectedPlace != nil {
                        onClearSelection()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                        Text(item.title(language: languageSettings.language))
                    }
                    .font(SaveAtlasType.strong(13))
                    .foregroundStyle(lens == item ? SaveAtlasPalette.coral : SaveAtlasPalette.forest)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                    .background(
                        SaveAtlasPalette.paper,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                lens == item ? SaveAtlasPalette.coral.opacity(0.55) : SaveAtlasPalette.kraft.opacity(0.7),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.accessibilityIdentifier)
                .accessibilityAddTraits(lens == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("map.lensRail")
    }

    private var cityTitle: String {
        switch SaveDoodleHomeCatalog.resolvedSelection(
            session.city,
            places: mapViewModel.places,
            locationDenied: locationService.isAuthorizationDenied
        ) {
        case .nearYou:
            return languageSettings.localized(english: "Near you", traditionalChinese: "附近")
        case .city(let id):
            if let group = cityGroups.first(where: { $0.id == id }) {
                return languageSettings.language == .traditionalChinese
                    ? group.chineseName
                    : group.englishName
            }
            return SaveHomeSearch.cityLabel(
                for: id,
                traditionalChinese: languageSettings.language == .traditionalChinese
            ) ?? id
        }
    }

    private var cityGroups: [SaveDoodleCityGroup] {
        SaveDoodleHomeCatalog.cityGroups(from: mapViewModel.places)
    }

    private var visiblePlaces: [Place] {
        switch lens {
        case .saved:
            return mapViewModel.places
        case .nearby:
            return SaveMapIntentFilter.places(
                mapViewModel.places,
                categories: [],
                intents: [.nearby],
                nearbyAnchor: locationService.currentLocation?.coordinate
                    ?? mapViewModel.nearbyFilterAnchor
            )
        case .friends:
            let social = mapViewModel.visibleSocialPlaces
            return social.isEmpty ? mapViewModel.socialPlaces : social
        }
    }

    private var visiblePins: [SaveTileTownPin] {
        visiblePlaces.map { place in
            SaveTileTownPin(
                id: place.id,
                name: place.name,
                isSelected: mapViewModel.selectedPlace?.id == place.id
            )
        }
    }

    private func selectPin(_ id: UUID) {
        if let place = visiblePlaces.first(where: { $0.id == id }) {
            mapViewModel.selectPlace(place)
        }
    }

    private func consumeShowOnMap() {
        guard let id = session.pendingShowOnMapPlaceID else { return }
        session.pendingShowOnMapPlaceID = nil
        showsHomeSessionChrome = true
        lens = .saved
        if let place = mapViewModel.places.first(where: { $0.id == id }) {
            mapViewModel.selectPlace(place)
            mapViewModel.cameraPosition = .region(
                MKCoordinateRegion(
                    center: place.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        }
    }

#if DEBUG
    /// UI-test camera/selection state. Not pixel evidence. Production omits it.
    private var cameraProbe: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityIdentifier("map.camera")
            .accessibilityLabel("Map camera")
            .accessibilityValue(cameraAccessibilityValue)
    }

    private var cameraAccessibilityValue: String {
        if let region = mapViewModel.cameraPosition.region {
            return String(
                format: "%.6f,%.6f,%.5f,%.5f",
                region.center.latitude,
                region.center.longitude,
                region.span.latitudeDelta,
                region.span.longitudeDelta
            )
        }
        if let place = mapViewModel.selectedPlace {
            return String(format: "%.6f,%.6f", place.latitude, place.longitude)
        }
        return ""
    }
#endif

}
