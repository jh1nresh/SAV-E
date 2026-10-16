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
    @ObservedObject private var locationService = LocationService.shared
    @State private var lens: SaveTileTownMapLens = .saved

    var body: some View {
        ZStack(alignment: .top) {
            SaveAtlasPalette.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                SavePixelDisplayText(text: "Savvy", pointSize: 34)
                    .padding(.horizontal, 16)
                    .padding(.top, AtlasMetrics.statusBarHeight)
                    .accessibilityIdentifier("map.wordmark")

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
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("map.peek.card")
                        .accessibilityLabel(languageSettings.localized(
                            english: "Open \(place.name)",
                            traditionalChinese: "開啟 \(place.name)"
                        ))
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
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
                    .contentShape(SaveKraftTicketShape())
                    .background(
                        SaveAtlasPalette.kraft.opacity(lens == item ? 0.72 : 0.30),
                        in: SaveKraftTicketShape()
                    )
                    .overlay {
                        SaveKraftTicketShape()
                            .stroke(
                                lens == item ? SaveAtlasPalette.forest : SaveAtlasPalette.line.opacity(0.65),
                                style: StrokeStyle(lineWidth: 1, dash: lens == item ? [] : [3, 2])
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.accessibilityIdentifier)
                .accessibilityAddTraits(lens == item ? .isSelected : [])
            }
        }
        .accessibilityIdentifier("map.lensRail")
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

}
