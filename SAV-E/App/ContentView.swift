import SwiftUI

struct ContentView: View {
    @StateObject private var mapVM = MapViewModel()
    @StateObject private var drawerVM = AIDrawerViewModel()
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenMapTour") private var hasSeenMapTour = false
    @State private var drawerDetent: PresentationDetent = .height(88)
    @State private var mapDetailDrawerItem: MapDetailDrawerItem?

    var body: some View {
        MapView(viewModel: mapVM)
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
            .sheet(isPresented: .constant(true)) {
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
            .onChange(of: drawerVM.mapAction) { _, action in
                if let action { mapVM.apply(action) }
            }
            .onChange(of: mapVM.selectedPlace) { _, place in
                guard let place else { return }
                drawerVM.returnToCommands()
                mapDetailDrawerItem = .savedPlace(place)
                withAnimation(.spring(duration: 0.3)) {
                    drawerDetent = .fraction(0.34)
                }
            }
            .onChange(of: mapVM.selectedReviewCandidate) { _, candidate in
                guard let candidate else { return }
                drawerVM.returnToCommands()
                mapDetailDrawerItem = .reviewCandidate(candidate)
                withAnimation(.spring(duration: 0.3)) {
                    drawerDetent = .fraction(0.34)
                }
            }
            .onChange(of: mapVM.selectedMapCandidate) { _, candidate in
                guard let candidate else { return }
                drawerVM.returnToCommands()
                mapDetailDrawerItem = .unsavedCandidate(candidate)
                withAnimation(.spring(duration: 0.3)) {
                    drawerDetent = .fraction(0.34)
                }
            }
            .onChange(of: mapVM.selectedSocialPlace) { _, place in
                guard let place else { return }
                drawerVM.returnToCommands()
                mapDetailDrawerItem = .socialPlace(place)
                withAnimation(.spring(duration: 0.3)) {
                    drawerDetent = .fraction(0.34)
                }
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

    /// First-run gate: the guided tour shows once, the first time the user is
    /// actually on the map (this view only renders post-auth). Setting
    /// `hasSeenMapTour` true on dismissal keeps it from ever showing again.
    private var shouldShowMapTour: Binding<Bool> {
        Binding(
            get: { !hasSeenMapTour },
            set: { if !$0 { hasSeenMapTour = true } }
        )
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
