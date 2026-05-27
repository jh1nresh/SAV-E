import SwiftUI

struct ContentView: View {
    @StateObject private var mapVM = MapViewModel()
    @StateObject private var drawerVM = AIDrawerViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var drawerDetent: PresentationDetent = .height(72)

    var body: some View {
        MapView(viewModel: mapVM)
            .sheet(isPresented: .constant(true)) {
                AIDrawerView(
                    viewModel: drawerVM,
                    drawerDetent: $drawerDetent,
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
                    onAddMapCandidateToList: { candidate, listID in
                        try mapVM.addMapCandidate(candidate, toListID: listID)
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
                    selectedCategories: mapVM.selectedCategories,
                    onToggleCategory: { category in
                        mapVM.toggleCategory(category)
                    }
                )
                    .presentationDetents([.height(72), .fraction(0.34), .medium, .large], selection: $drawerDetent)
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
                if let place { drawerVM.showPlace(place) }
            }
            .onChange(of: mapVM.selectedReviewCandidate) { _, candidate in
                if let candidate { drawerVM.showReviewCandidate(candidate) }
            }
            .onChange(of: mapVM.selectedMapCandidate) { _, candidate in
                if let candidate { drawerVM.showMapCandidate(candidate) }
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
