import CoreLocation
import SwiftUI

/// Product Map tab: full-pixel tile-town base with Nearby / Saved / Friends
/// lenses. Drawer search and Trip MapKit stay elsewhere.
struct SaveTileTownRootMap: View {
    @ObservedObject var mapViewModel: MapViewModel
    let presentation: AtlasPresentation
    let onClearSelection: () -> Void
    let onPlanAroundPlace: (Place) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @EnvironmentObject private var session: SaveDoodleSession
    @ObservedObject private var locationService = LocationService.shared
    @State private var lens: SaveTileTownMapLens = .saved

    var body: some View {
        ZStack(alignment: .top) {
            SaveAtlasPalette.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        SaveDisplayTitle(text: "Savvy", pointSize: 28)
                            .accessibilityIdentifier("map.wordmark")
                        Text(cityTitle)
                            .font(SaveAtlasType.body(13))
                            .foregroundStyle(SaveAtlasPalette.muted)
                            .accessibilityIdentifier("map.city")
                    }
                    Spacer(minLength: 8)
                    eatGoRail
                }
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: lens) { _, newLens in
            if newLens == .friends {
                mapViewModel.selectSocialLens(.forYou)
            }
        }
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

    private var eatGoRail: some View {
        HStack(spacing: 8) {
            ForEach(SaveDoodleLens.allCases) { item in
                let selected = session.lens == item
                Button {
                    SaveHaptics.select()
                    session.lens = item
                } label: {
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
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.mapAccessibilityIdentifier)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityIdentifier("map.eatGo")
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
            return SaveHomeSearch.cityLabel(
                for: id,
                traditionalChinese: languageSettings.language == .traditionalChinese
            ) ?? id
        }
    }

    private var visiblePlaces: [Place] {
        switch lens {
        case .saved:
            return sessionPlaces(from: mapViewModel.places)
        case .nearby:
            return sessionPlaces(
                from: SaveMapIntentFilter.places(
                    mapViewModel.places,
                    categories: [],
                    intents: [.nearby],
                    nearbyAnchor: locationService.currentLocation?.coordinate
                        ?? mapViewModel.nearbyFilterAnchor
                )
            )
        case .friends:
            let social = mapViewModel.visibleSocialPlaces
            return social.isEmpty ? mapViewModel.socialPlaces : social
        }
    }

    private func sessionPlaces(from places: [Place]) -> [Place] {
        SaveDoodleHomeCatalog.visiblePlaces(
            from: places,
            lens: session.lens,
            selection: session.city,
            location: locationService.isAuthorizationDenied ? nil : locationService.currentLocation,
            locationDenied: locationService.isAuthorizationDenied
        )
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

}
