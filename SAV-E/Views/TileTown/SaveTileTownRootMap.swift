import CoreLocation
import SwiftUI

/// Product Map uses normal MapKit geography with Nearby / Saved / Friends
/// lenses. The surrounding memory UI retains the pixel presentation.
struct SaveTileTownRootMap: View {
    @ObservedObject var mapViewModel: MapViewModel
    let shouldFocusOnUserLocation: Bool
    let presentation: AtlasPresentation
    let onClearSelection: () -> Void
    let onPlanAroundPlace: (Place) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject private var locationService = LocationService.shared
    @State private var lens: SaveTileTownMapLens = .saved
    @State private var didPrepareInitialCamera = false

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
                    MapView(
                        viewModel: mapViewModel,
                        shouldFocusOnUserLocationOnLaunch: false,
                        displayedPlaces: visiblePlaces,
                        showsSocialPins: lens == .friends,
                        tracksVisibleRegion: true,
                        bottomOverlayClearance: mapViewModel.selectedPlace == nil ? 28 : 164
                    )

                    if let place = mapViewModel.selectedPlace {
                        Button {
                            presentation.onOpenPlace(place.id.uuidString)
                        } label: {
                            SaveTileTownPeekCard(
                                title: place.name,
                                subtitle: place.createdAt.formatted(date: .abbreviated, time: .omitted),
                                photoURL: HomePlaceCardArt.photoURL(for: place),
                                category: place.category.rawValue,
                                artworkDetail: place.note ?? ""
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
                .clipShape(SaveKraftTicketShape())
                .overlay {
                    SaveKraftTicketShape()
                        .stroke(SaveAtlasPalette.line.opacity(0.22), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 12)
                // Reserve the collapsed command shelf as well as the root tab bar.
                .padding(.bottom, 160)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !didPrepareInitialCamera else { return }
            didPrepareInitialCamera = true
            // Preserve a search/review focus or the user's last panned viewport.
            guard mapViewModel.visibleMapRegion == nil,
                  !mapViewModel.cameraPosition.positionedByUser,
                  mapViewModel.selectedReviewCandidate == nil,
                  mapViewModel.selectedMapCandidate == nil,
                  mapViewModel.selectedSocialPlace == nil else { return }
            if shouldAutomaticallyLocate && mapViewModel.selectedPlace == nil {
                // Existing permission only. The explicit locate button owns prompts.
                await mapViewModel.focusOnUserLocationOnLaunch()
            } else if let place = (mapViewModel.selectedPlace.map { [$0] } ?? visiblePlaces)
                .first(where: \.isMapKitMappable) {
                mapViewModel.focusRegion(latitude: place.latitude, longitude: place.longitude)
            }
        }
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
                        SavePixelChromeIcon(kind: .rootSymbol(item.systemImage), pointSize: 24)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.lensRail")
    }

    private var shouldAutomaticallyLocate: Bool {
        shouldFocusOnUserLocation &&
            [.authorizedAlways, .authorizedWhenInUse].contains(locationService.authorizationStatus)
    }

    private var visiblePlaces: [Place] {
        switch lens {
        case .saved:
            return mapViewModel.filteredPlaces
        case .nearby:
            return SaveMapIntentFilter.places(
                mapViewModel.filteredPlaces,
                categories: [],
                intents: [.nearby],
                nearbyAnchor: locationService.currentLocation?.coordinate
                    ?? mapViewModel.nearbyFilterAnchor
            )
        case .friends:
            // Social pins retain their unsaved state and selection action in MapView.
            return []
        }
    }

}
