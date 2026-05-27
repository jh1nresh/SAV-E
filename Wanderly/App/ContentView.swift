import SwiftUI

struct ContentView: View {
    @StateObject private var mapVM = MapViewModel()
    @StateObject private var drawerVM = AIDrawerViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var drawerDetent: PresentationDetent = .height(72)
    @State private var mapDetailDrawerItem: MapDetailDrawerItem?

    var body: some View {
        MapView(viewModel: mapVM)
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
                    onConfirmCandidate: { candidate in
                        try await mapVM.confirmReviewCandidate(candidate)
                    },
                    onRejectCandidate: { candidate in
                        try await mapVM.rejectReviewCandidate(candidate)
                    },
                    onSaveCandidate: { candidate in
                        try await mapVM.saveReviewCandidateAsPlace(candidate)
                    },
                    onSaveMapCandidate: { candidate in
                        try await mapVM.saveMapCandidateAsPlace(candidate)
                    },
                    onUpdatePlaceVisibility: { place, visibility in
                        try await mapVM.updatePlaceVisibility(place, visibility: visibility)
                    },
                    onImportURLAsReviewCandidates: { url in
                        try await mapVM.importURLAsReviewCandidates(url)
                    },
                    onPrepareMapSearch: { query in
                        await mapVM.prepareMapCandidatesForDrawerQuery(query)
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
                    selectedCategories: mapVM.selectedCategories,
                    onToggleCategory: { category in
                        mapVM.toggleCategory(category)
                    },
                    onDismissMapDetail: {
                        mapVM.clearSelectedMapObject()
                    }
                )
                    .presentationDetents([.height(72), .height(88), .fraction(0.34), .fraction(0.38), .medium, .large], selection: $drawerDetent)
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
                    drawerDetent = .height(88)
                }
            }
            .onChange(of: mapVM.selectedReviewCandidate) { _, candidate in
                guard let candidate else { return }
                drawerVM.returnToCommands()
                mapDetailDrawerItem = .reviewCandidate(candidate)
                withAnimation(.spring(duration: 0.3)) {
                    drawerDetent = .height(88)
                }
            }
            .onChange(of: mapVM.selectedMapCandidate) { _, candidate in
                guard let candidate else { return }
                drawerVM.returnToCommands()
                mapDetailDrawerItem = .unsavedCandidate(candidate)
                withAnimation(.spring(duration: 0.3)) {
                    drawerDetent = .height(88)
                }
            }
            .onChange(of: mapVM.selectedSocialPlace) { _, place in
                guard let place else { return }
                drawerVM.returnToCommands()
                mapDetailDrawerItem = .socialPlace(place)
                withAnimation(.spring(duration: 0.3)) {
                    drawerDetent = .height(88)
                }
            }
            .onChange(of: mapVM.places) { _, places in
                drawerVM.places = places
            }
            .onChange(of: mapVM.mapCandidates) { _, candidates in
                drawerVM.mapCandidates = candidates
            }
            .onReceive(NotificationCenter.default.publisher(for: SaveCollaborativeListNotification.didJoin)) { _ in
                mapVM.reloadCollaborativeLists()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await mapVM.handleSceneDidBecomeActive() }
            }
            .task {
                drawerVM.places = mapVM.places
                drawerVM.mapCandidates = mapVM.mapCandidates
                await mapVM.loadPlaces()
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppLanguageSettings())
}
