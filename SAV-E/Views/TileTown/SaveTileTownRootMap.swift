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
    @State private var showsCityPicker = false

    var body: some View {
        let followsHomeFilter = session.mapFollowsHomeFilter
        let visitResidue = session.mapVisitResidueID
        return ZStack(alignment: .top) {
            SaveAtlasPalette.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                header(followsHomeFilter: followsHomeFilter)
                    .id(visitResidue)
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
        .onAppear {
            applyMiniMapHandoff()
        }
        .onChange(of: session.mapVisitResidueID) { _, _ in
            applyMiniMapHandoff()
        }
        .onChange(of: session.lens) { _, _ in
            onClearSelection()
        }
        .onChange(of: session.city) { _, _ in
            onClearSelection()
        }
        .sheet(isPresented: $showsCityPicker) {
            cityPicker
        }
    }

    /// Reused Map skips `onAppear`. Residue from `beginMiniMapHandoff` remounts
    /// Eat/Go and drops leftover lens / city-picker / selected-pin chrome.
    private func applyMiniMapHandoff() {
        session.consumeMiniMapHandoff()
        lens = .saved
        showsCityPicker = false
    }

    @ViewBuilder
    private func header(followsHomeFilter: Bool) -> some View {
        if followsHomeFilter {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    SaveDisplayTitle(text: "Savvy", pointSize: 28)
                        .accessibilityIdentifier("map.wordmark")
                    Button { showsCityPicker = true } label: {
                        HStack(spacing: 4) {
                            Text(cityTitle)
                                .font(SaveAtlasType.body(13))
                                .foregroundStyle(SaveAtlasPalette.muted)
                            Text("▾")
                                .font(SaveAtlasType.body(11))
                                .foregroundStyle(SaveAtlasPalette.muted)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(languageSettings.localized(
                        english: "Choose city",
                        traditionalChinese: "選擇城市"
                    ) + ", " + cityTitle)
                    .accessibilityIdentifier("map.city")
                }
                Spacer(minLength: 8)
                eatGoRail
            }
        } else {
            SaveDisplayTitle(text: "Savvy", pointSize: 28)
                .accessibilityIdentifier("map.wordmark")
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
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        // Parent id without contain overwrote each chip as map.eatGo (Q5 CI tree).
        .accessibilityElement(children: .contain)
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

    private var cityGroups: [SaveDoodleCityGroup] {
        SaveDoodleHomeCatalog.cityGroups(from: mapViewModel.places)
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
                        showsCityPicker = false
                    } label: {
                        HStack {
                            Text("\(group.displayName(language: languageSettings.language)) \(group.count)")
                            Spacer()
                            if case .city(let id) = SaveDoodleHomeCatalog.resolvedSelection(
                                session.city,
                                places: mapViewModel.places,
                                locationDenied: locationService.isAuthorizationDenied
                            ), id == group.id {
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

    private func sessionPlaces(from places: [Place]) -> [Place] {
        guard session.mapFollowsHomeFilter else { return places }
        return SaveDoodleHomeCatalog.visiblePlaces(
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
