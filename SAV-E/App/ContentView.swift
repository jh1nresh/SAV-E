import SwiftUI

private enum SaveRootSurface {
    case inbox
    case map
}

struct ContentView: View {
    @StateObject private var mapVM = MapViewModel()
    @StateObject private var drawerVM = AIDrawerViewModel()
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenMapTour") private var hasSeenMapTour = false
    @State private var rootSurface: SaveRootSurface = .inbox
    @State private var drawerDetent: PresentationDetent = .height(88)
    @State private var mapDetailDrawerItem: MapDetailDrawerItem?

    var body: some View {
        Group {
            switch rootSurface {
            case .inbox:
                inboxSurface
            case .map:
                mapSurface
            }
        }
        .environment(\.appLanguageSettings, languageSettings)
        .alert(
            languageSettings.localized(english: "Saved on this phone only", traditionalChinese: "只存在這支手機上"),
            isPresented: Binding(
                get: { mapVM.syncFailedPlaceName != nil },
                set: { if !$0 { mapVM.syncFailedPlaceName = nil } }
            )
        ) {
            Button(languageSettings.text(.ok)) { mapVM.syncFailedPlaceName = nil }
        } message: {
            Text(languageSettings.localized(
                english: "\"\(mapVM.syncFailedPlaceName ?? "")\" couldn't sync to your account — check your connection. It stays saved locally.",
                traditionalChinese: "「\(mapVM.syncFailedPlaceName ?? "")」沒能同步到你的帳號——請檢查網路。它仍保存在本機。"
            ))
        }
        .onChange(of: drawerVM.mapAction) { _, action in
            if let action { mapVM.apply(action) }
        }
        .onChange(of: mapVM.selectedPlace) { _, place in
            guard let place else { return }
            openPlaceFromInbox(place)
        }
        .onChange(of: mapVM.selectedReviewCandidate) { _, candidate in
            guard let candidate else { return }
            openCandidateFromInbox(candidate)
        }
        .onChange(of: mapVM.selectedMapCandidate) { _, candidate in
            guard let candidate else { return }
            openMapDetail(.unsavedCandidate(candidate))
        }
        .onChange(of: mapVM.selectedSocialPlace) { _, place in
            guard let place else { return }
            openMapDetail(.socialPlace(place))
        }
        .onChange(of: mapVM.places) { _, places in
            drawerVM.places = places
            refreshSelectedMapDetailPlace(from: places)
        }
        .onChange(of: mapVM.mapCandidates) { _, candidates in
            drawerVM.mapCandidates = candidates
        }
        .onReceive(NotificationCenter.default.publisher(for: SaveCollaborativeListNotification.didJoin)) { _ in
            mapVM.reloadCollaborativeLists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveMemoryPreferencesDidChange)) { _ in
            Task { await drawerVM.loadMemoryPreferences() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await mapVM.handleSceneDidBecomeActive() }
        }
        .task {
            drawerVM.places = mapVM.places
            drawerVM.mapCandidates = mapVM.mapCandidates
            await drawerVM.loadMemoryPreferences()
            await mapVM.loadPlaces()
        }
        .fullScreenCover(isPresented: shouldShowMapTour) {
            MapCoachmarkTour {
                hasSeenMapTour = true
            }
            .environment(\.appLanguageSettings, languageSettings)
            .presentationBackground(.clear)
        }
    }

    private var inboxSurface: some View {
        MemoryInboxView(
            places: mapVM.places,
            reviewCandidates: mapVM.reviewCandidates,
            isLoading: mapVM.isLoading,
            onOpenCandidate: openCandidateFromInbox,
            onOpenPlace: openPlaceFromInbox,
            onOpenMap: openMap,
            onAsk: openAsk,
            onCapture: openAsk
        )
    }

    private var mapSurface: some View {
        MapView(viewModel: mapVM)
            .environment(\.appLanguageSettings, languageSettings)
            .sheet(isPresented: .constant(true)) {
                drawerView
            }
    }

    private var drawerView: some View {
        AIDrawerView(
            viewModel: drawerVM,
            drawerDetent: $drawerDetent,
            mapDetailDrawerItem: $mapDetailDrawerItem,
            existingPlacesForImport: mapVM.places,
            reviewCandidates: mapVM.reviewCandidates,
            onSaveGoogleTakeoutImport: { drafts in
                try await mapVM.saveImportedPlaces(drafts)
            },
            onDeletePlace: { place in
                try await mapVM.deletePlace(place)
            },
            onSaveCandidate: { candidate, nameOverride in
                try await mapVM.saveReviewCandidateAsPlace(candidate, nameOverride: nameOverride)
            },
            onRejectCandidate: { candidate in
                try await mapVM.rejectReviewCandidate(candidate)
            },
            onSaveCandidateAsSourceOnly: { candidate in
                try await mapVM.saveReviewCandidateAsSourceOnly(candidate)
            },
            onMarkCandidateWrongBranch: { candidate in
                try await mapVM.markReviewCandidateWrongBranch(candidate)
            },
            onInvestigateCandidateMore: { candidate in
                try await mapVM.investigateReviewCandidateMore(candidate)
            },
            onSaveMapCandidate: { candidate in
                try await mapVM.saveMapCandidateAsPlace(candidate)
            },
            onUpdatePlaceVisibility: { place, visibility in
                try await mapVM.updatePlaceVisibility(place, visibility: visibility)
            },
            onUpdatePlace: { place in
                try await mapVM.updatePlace(place)
            },
            onImportURLAsReviewCandidates: { url in
                try await mapVM.importURLAsReviewCandidates(url)
            },
            onPrepareMapSearch: { query in
                await mapVM.prepareMapCandidatesForDrawerQuery(query)
            },
            onClearMapSearchResults: {
                mapVM.clearMapSearchResults()
            },
            collaborativeLists: mapVM.collaborativeLists,
            onCreateList: { title, note in
                mapVM.createCollaborativeList(title: title, note: note)
            },
            onAddPlaceToList: { place, listID in
                try mapVM.addPlace(place, toListID: listID)
            },
            onShareListURL: { list, role in
                mapVM.shareURL(for: list, role: role)
            },
            onSaveListItem: { item in
                _ = try await mapVM.saveListItemAsPlace(item)
            },
            onPlanList: { list in
                await mapVM.planCollaborativeList(list)
            },
            socialLens: mapVM.socialLens,
            socialPlaces: mapVM.visibleSocialPlaces,
            onSelectSocialLens: { lens in
                mapVM.selectSocialLens(lens)
            },
            onSaveSocialPlace: { place in
                _ = try await mapVM.saveSocialPlaceToMySave(place)
            },
            onFollowReferral: { value in
                try await mapVM.followReferral(value)
            },
            selectedCategories: mapVM.selectedCategories,
            onToggleCategory: { category in
                mapVM.toggleCategory(category)
            },
            onOpenInbox: returnToInbox,
            onDismissMapDetail: {
                mapVM.clearSelectedMapObject()
            }
        )
        .environment(\.appLanguageSettings, languageSettings)
        .presentationDetents([.height(88), .height(104), .height(160), .fraction(0.34), .fraction(0.38), .medium, .large], selection: $drawerDetent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled(true)
        .presentationBackground(.clear)
        .presentationCornerRadius(32)
    }

    /// First-run gate: the guided tour shows once, the first time the user is
    /// actually on the map (this view only renders post-auth). Setting
    /// `hasSeenMapTour` true on dismissal keeps it from ever showing again.
    private var shouldShowMapTour: Binding<Bool> {
        Binding(
            get: { rootSurface == .map && !hasSeenMapTour },
            set: { if !$0 { hasSeenMapTour = true } }
        )
    }

    private func openMap() {
        mapDetailDrawerItem = nil
        drawerVM.returnToCommands()
        withAnimation(SaveTheme.Motion.standardSpring) {
            rootSurface = .map
            drawerDetent = .height(88)
        }
    }

    private func openAsk() {
        mapDetailDrawerItem = nil
        drawerVM.returnToCommands()
        withAnimation(SaveTheme.Motion.standardSpring) {
            rootSurface = .map
            drawerDetent = .medium
        }
    }

    private func openCandidateFromInbox(_ candidate: PlaceReviewCandidate) {
        openMapDetail(.reviewCandidate(candidate))
    }

    private func openPlaceFromInbox(_ place: Place) {
        openMapDetail(.savedPlace(place))
    }

    private func openMapDetail(_ item: MapDetailDrawerItem) {
        drawerVM.returnToCommands()
        mapDetailDrawerItem = item
        withAnimation(SaveTheme.Motion.standardSpring) {
            rootSurface = .map
            drawerDetent = .fraction(0.38)
        }
    }

    private func returnToInbox() {
        mapVM.clearSelectedMapObject()
        mapDetailDrawerItem = nil
        drawerVM.returnToCommands()
        withAnimation(SaveTheme.Motion.standardSpring) {
            rootSurface = .inbox
            drawerDetent = .height(88)
        }
    }

    private func refreshSelectedMapDetailPlace(from places: [Place]) {
        guard case .savedPlace(let selectedPlace) = mapDetailDrawerItem,
              let updatedPlace = places.first(where: { $0.id == selectedPlace.id }),
              updatedPlace != selectedPlace
        else { return }

        mapDetailDrawerItem = .savedPlace(updatedPlace)
    }
}

#Preview {
    ContentView()
        .environment(\.appLanguageSettings, AppLanguageSettings())
}
