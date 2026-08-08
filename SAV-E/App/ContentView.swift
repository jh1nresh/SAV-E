import SwiftUI

enum SaveRootTab: Hashable, CaseIterable, Identifiable {
    case home
    case saves
    case trips
    case map

    var id: Self { self }

    var atlasTitle: String {
        switch self {
        case .home: "Home"
        case .saves: "Saves"
        case .trips: "Trips"
        case .map: "Map"
        }
    }

    var atlasIcon: String {
        switch self {
        case .home: "house"
        case .saves: "bookmark"
        case .trips: "briefcase"
        case .map: "globe"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .home:
            return language.localized(english: "Home", traditionalChinese: "首頁")
        case .saves:
            return language.localized(english: "Saves", traditionalChinese: "收藏")
        case .trips:
            return language.localized(english: "Trips", traditionalChinese: "行程")
        case .map:
            return language.localized(english: "Map", traditionalChinese: "地圖")
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .saves: return "bookmark.fill"
        case .trips: return "suitcase.rolling.fill"
        case .map: return "map.fill"
        }
    }
}

enum SaveRootRoute: Hashable {
    case trip(UUID)
}

private enum SaveFullScreenRoute: Identifiable {
    case capture
    case placeDetail(MapDetailDrawerItem)

    var id: String {
        switch self {
        case .capture:
            return "capture"
        case .placeDetail(let item):
            switch item {
            case .savedPlace(let place):
                return "saved-\(place.id.uuidString)"
            case .reviewCandidate(let candidate):
                return "review-\(candidate.id.uuidString)"
            case .unsavedCandidate(let candidate):
                return "map-\(candidate.id)"
            case .socialPlace(let place):
                return "social-\(place.id.uuidString)"
            }
        }
    }
}

enum ContentStorageScope: Equatable {
    case production
    case reviewerDemo

    @MainActor
    func makeMapViewModel() -> MapViewModel {
        switch self {
        case .production:
            return MapViewModel()
        case .reviewerDemo:
            return ReviewDemoStorage.makeMapViewModel()
        }
    }

    @MainActor
    func makeTripPackStore() -> TripPackStore {
        switch self {
        case .production:
            return TripPackStore(
                userID: PrivyAuthService.shared.currentUserId ?? "unavailable",
                persistence: SupabaseService.shared
            )
        case .reviewerDemo:
            return .reviewerDemo()
        }
    }
}

struct ContentView: View {
    @StateObject private var mapVM: MapViewModel
    @StateObject private var tripStore: TripPackStore
    @StateObject private var drawerVM = AIDrawerViewModel()
    @Binding private var incomingPlaceReceipt: SharedPlaceReceiptDestination?
    private let storageScope: ContentStorageScope
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRootSheetPresented: Bool
    @State private var isPassportPresented = false
    @State private var drawerDetent: PresentationDetent
    @State private var mapDetailDrawerItem: MapDetailDrawerItem?
    @State private var pendingReceiptMapDetail: MapDetailDrawerItem?
    @State private var pendingTripAssignmentPlace: Place?
    @State private var isTripAssignmentDialogPresented = false
    @State private var isFullScreenTripAssignmentDialogPresented = false
    @State private var isTransitioningToTripCreation = false
    @State private var isCreatingTripForAssignment = false
    @State private var pendingCaptureTripID: UUID?
    @State private var activeTripID: UUID?
    @State private var drawerLaunchRequest: DrawerLaunchRequest
    @State private var selectedRootTab: SaveRootTab
    @State private var rootPath: [SaveRootRoute]
    @State private var fullScreenRoute: SaveFullScreenRoute?
    @State private var fullScreenCandidateActionID: UUID?
    @State private var fullScreenMapCandidateActionID: String?
    @State private var fullScreenActionError: String?
    @State private var isMapPanelExpanded = false

    init(
        incomingPlaceReceipt: Binding<SharedPlaceReceiptDestination?> = .constant(nil),
        storageScope: ContentStorageScope = .production
    ) {
        _mapVM = StateObject(wrappedValue: storageScope.makeMapViewModel())
        _tripStore = StateObject(wrappedValue: storageScope.makeTripPackStore())
        _incomingPlaceReceipt = incomingPlaceReceipt
        self.storageScope = storageScope
        _isRootSheetPresented = State(initialValue: incomingPlaceReceipt.wrappedValue != nil)
        _drawerDetent = State(initialValue: .large)
        _drawerLaunchRequest = State(initialValue: DrawerLaunchRequest(target: .review))
        _selectedRootTab = State(initialValue: .home)
        _rootPath = State(initialValue: [])
        _fullScreenRoute = State(initialValue: nil)
        _fullScreenCandidateActionID = State(initialValue: nil)
        _fullScreenMapCandidateActionID = State(initialValue: nil)
        _fullScreenActionError = State(initialValue: nil)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            rootTabs
            mapDrawerPanel
        }
        .onChange(of: selectedRootTab) { _, tab in
            if tab != .map, isMapPanelExpanded {
                collapseMapPanel()
            }
        }
        .environment(\.appLanguageSettings, languageSettings)
#if DEBUG
        .task {
            if DebugVaultExporter.isRequested {
                await DebugVaultExporter.run()
            }
            if DebugLegacyMigrator.isRequested {
                await DebugLegacyMigrator.run()
            }
        }
#endif
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
        .sheet(isPresented: $isRootSheetPresented, onDismiss: handleRootSheetDismiss) {
            rootSheetContent
        }
        .fullScreenCover(item: $fullScreenRoute, onDismiss: handleFullScreenDismiss) { route in
            fullScreenContent(for: route)
        }
        .sheet(isPresented: $isPassportPresented) {
            ProfileView(
                savedPlaces: mapVM.places,
                waitingClues: mapVM.reviewCandidates.count,
                collaborativeLists: mapVM.collaborativeLists,
                followedFriends: mapVM.followedFriends,
                isLoadingFollowedFriends: mapVM.isLoadingFollowedFriends,
                hasMoreFollowedFriends: mapVM.hasMoreFollowedFriends,
                onUpdatePlaceVisibility: { place, visibility in
                    try await mapVM.updatePlaceVisibility(place, visibility: visibility)
                },
                onSaveGoogleTakeoutImport: { drafts in
                    try await mapVM.saveImportedPlaces(drafts)
                },
                onCreateList: { title, note in
                    _ = mapVM.createCollaborativeList(title: title, note: note)
                },
                onShareListURL: { list, role in
                    mapVM.shareURL(for: list, role: role)
                },
                onOpenListOnMap: openCollaborativeListOnMap,
                onFollowReferral: { value in
                    try await mapVM.followReferral(value)
                },
                onRefreshFollowedFriends: {
                    await mapVM.refreshFollowedFriends(force: true)
                },
                onSearchFollowedFriends: { query in
                    await mapVM.refreshFollowedFriends(query: query, force: true)
                },
                onLoadMoreFollowedFriends: {
                    await mapVM.loadMoreFollowedFriends()
                },
                onUnfollowFriend: { friend in
                    try await mapVM.unfollowFriend(friend)
                }
            )
            .environment(\.appLanguageSettings, languageSettings)
        }
        .sheet(isPresented: $isCreatingTripForAssignment, onDismiss: finishTripAssignment) {
            NewTripPackView { name, city, startDate, endDate in
                guard let place = pendingTripAssignmentPlace else {
                    finishTripAssignment()
                    return
                }

                if let trip = await tripStore.createTrip(
                    name: name,
                    city: city,
                    startDate: startDate,
                    endDate: endDate
                ) {
                    await addConfirmedPlaceToTrip(place, tripID: trip.id)
                }
                finishTripAssignment()
            }
            .environment(\.appLanguageSettings, languageSettings)
        }
        .confirmationDialog(
            languageSettings.localized(
                english: "Saved. Add it to a Trip?",
                traditionalChinese: "已收藏。要加入行程嗎？"
            ),
            isPresented: $isTripAssignmentDialogPresented,
            titleVisibility: .visible
        ) {
            tripAssignmentActions(dismissFullScreen: false)
        } message: {
            tripAssignmentMessage
        }
        .onChange(of: isTripAssignmentDialogPresented) { _, isPresented in
            guard !isPresented,
                  !isCreatingTripForAssignment,
                  !isTransitioningToTripCreation,
                  pendingTripAssignmentPlace != nil
            else { return }
            finishTripAssignment()
        }
        .onChange(of: isFullScreenTripAssignmentDialogPresented) { _, isPresented in
            guard !isPresented,
                  !isCreatingTripForAssignment,
                  !isTransitioningToTripCreation,
                  pendingTripAssignmentPlace != nil
            else { return }
            finishTripAssignment()
            fullScreenRoute = nil
        }
        .onChange(of: drawerVM.mapAction) { _, action in
            if let action { mapVM.apply(action) }
        }
        .onChange(of: incomingPlaceReceipt?.id) { _, receiptID in
            guard receiptID != nil else { return }
            fullScreenRoute = nil
            pendingReceiptMapDetail = nil
            mapDetailDrawerItem = nil
            mapVM.clearSelectedMapObject()
            drawerVM.returnToCommands()
            withAnimation(SaveTheme.Motion.standardSpring) {
                drawerDetent = .large
            }
            isRootSheetPresented = true
        }
        .onChange(of: mapVM.selectedPlace) { _, place in
            guard let place else { return }
            guard selectedRootTab != .map else { return }
            openMapDetail(.savedPlace(place))
        }
        .onChange(of: mapVM.selectedReviewCandidate) { _, candidate in
            guard let candidate else { return }
            openMapDetail(.reviewCandidate(candidate))
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
            await loadInitialContent()
        }
    }

    @MainActor
    private func loadInitialContent() async {
        drawerVM.places = mapVM.places
        drawerVM.mapCandidates = mapVM.mapCandidates
        if storageScope == .production || !ReviewDemo.isOfflineUITestMode {
            await drawerVM.loadMemoryPreferences()
        }
        await mapVM.loadPlaces()
        await tripStore.load()
        if storageScope == .reviewerDemo {
            await tripStore.seedReviewerDemoIfNeeded(confirmedPlaces: mapVM.places)
        }
        openPostcardDrawerUITestFixtureIfNeeded()
    }

    private var rootTabs: some View {
        NavigationStack(path: $rootPath) {
            ReferenceViewport {
                ZStack(alignment: .topLeading) {
                    Group {
                        switch selectedRootTab {
                        case .home:
                            SaveHomeView(
                                store: tripStore,
                                mapViewModel: mapVM,
                                onCapture: { openDrawer(.addLink, tripID: nil) },
                                onOpenSavedPlace: { openMapDetail(.savedPlace($0)) },
                                onOpenSaves: { selectedRootTab = .saves },
                                onOpenTrips: { selectedRootTab = .trips },
                                onOpenMap: { selectedRootTab = .map },
                                onOpenTrip: { rootPath.append(.trip($0)) },
                                onOpenPassport: openPassport
                            )
                        case .saves:
                            SaveLibraryView(
                                places: mapVM.places,
                                reviewCandidates: mapVM.reviewCandidates,
                                onOpenCapture: { openDrawer(.addLink, tripID: nil) },
                                onOpenReviewCandidate: {
                                    openReviewCandidate($0, tripID: nil)
                                },
                                onOpenSavedPlace: { openMapDetail(.savedPlace($0)) },
                                onOpenPassport: openPassport
                            )
                        case .trips:
                            TripsHomeView(
                                store: tripStore,
                                savedPlaces: mapVM.places,
                                onCapture: { openDrawer(.addLink, tripID: nil) },
                                onOpenAssistant: { openDrawer(.ask, tripID: nil) },
                                onAskSubmit: { query in
                                    openDrawer(.ask, tripID: nil, initialQuery: query)
                                },
                                onOpenTrip: { rootPath.append(.trip($0)) },
                                onOpenPassport: openPassport
                            )
                        case .map:
                            SaveMapRootView(
                                mapViewModel: mapVM,
                                shouldFocusOnUserLocation: true,
                                // The single drawer panel owns the shelf now;
                                // the canvas never draws its own copy.
                                hidesCommandShelf: true,
                                onOpenSearch: { openDrawer(.ask, tripID: nil) },
                                onOpenSavedPlace: { openMapDetail(.savedPlace($0)) },
                                onPlanAroundPlace: openPlanAround,
                                onOpenPassport: openPassport
                            )
                        }
                    }

                    AtlasTabBar(
                        items: SaveRootTab.allCases,
                        selection: selectedRootTab,
                        title: \.atlasTitle,
                        icon: \.atlasIcon,
                        accessibilityPrefix: "root.tab",
                        onSelect: { selectedRootTab = $0 }
                    )
                    .placed(
                        x: 0,
                        y: selectedRootTab == .map ? 788 : 786,
                        width: 402,
                        height: 76
                    )
                }
            }
            .tint(SaveAtlasPalette.forest)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SaveRootRoute.self) { route in
                switch route {
                case .trip(let tripID):
                    TripWorkspaceView(
                        tripID: tripID,
                        store: tripStore,
                        mapViewModel: mapVM,
                        storageScope: storageScope,
                        onOpenSavedPlace: { openMapDetail(.savedPlace($0)) },
                        onActiveTripChange: { activeTripID = $0 }
                    )
                }
            }
        }
    }

    /// The Map tab's single drawer surface (spec P2): the resting shelf and
    /// the expanded ask/search drawer are one morphing container, replacing
    /// the old shelf-in-canvas + presented-sheet pair that stacked two
    /// drawers on screen.
    @ViewBuilder
    private var mapDrawerPanel: some View {
        if isMapPanelExpanded || (selectedRootTab == .map && rootPath.isEmpty) {
            SaveMapDrawerPanel(
                isExpanded: $isMapPanelExpanded,
                mapStampCount: mapVM.places.count,
                showsCollapsedShelf: mapVM.selectedPlace == nil
                    && selectedRootTab == .map
                    && rootPath.isEmpty
                    && incomingPlaceReceipt == nil,
                onExpand: { openDrawer(.ask, tripID: nil) },
                onCollapse: collapseMapPanel
            ) {
                drawerView
            }
        }
    }

    private func collapseMapPanel() {
        isMapPanelExpanded = false
        handleRootSheetDismiss()
    }

    @ViewBuilder
    private var rootSheetContent: some View {
        if let destination = incomingPlaceReceipt {
            FriendShareReceiptView(destination: destination) { receipt in
                let outcome = try await mapVM.saveSharedPlaceReceipt(receipt)
                pendingReceiptMapDetail = .savedPlace(outcome.place)
                return outcome
            }
            .id(destination.id)
            .environment(\.appLanguageSettings, languageSettings)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        } else {
            drawerView
        }
    }

    @ViewBuilder
    private func fullScreenContent(for route: SaveFullScreenRoute) -> some View {
        switch route {
        case .capture:
            SaveCaptureFlowView(
                tripName: captureTripName,
                onImport: { sharedText in
                    try await mapVM.importSharedTextAsReviewCandidates(sharedText)
                },
                onComplete: {
                    fullScreenRoute = nil
                    selectedRootTab = .saves
                },
                onCancel: {
                    fullScreenRoute = nil
                }
            )
            .environment(\.appLanguageSettings, languageSettings)

        case .placeDetail(let item):
            MapDetailDrawerView(
                item: item,
                detent: .constant(.large),
                captureTripName: captureTripName,
                editableLists: mapVM.collaborativeLists.filter(\.canEdit),
                isWorkingReviewCandidateID: fullScreenCandidateActionID,
                isWorkingMapCandidateID: fullScreenMapCandidateActionID,
                onClose: { fullScreenRoute = nil },
                onDeletePlace: { place in
                    try await mapVM.deletePlace(place)
                    fullScreenRoute = nil
                },
                onRecommendOrder: openFoodAnalysis,
                onPlanAroundPlace: openPlanAround,
                onFindExactPlaceCandidate: openExactSearch,
                onSaveCandidate: saveFullScreenCandidate,
                onRejectCandidate: rejectFullScreenCandidate,
                onSaveCandidateAsSourceOnly: keepFullScreenCandidateSourceOnly,
                onMarkCandidateWrongBranch: markFullScreenCandidateWrongBranch,
                onInvestigateCandidateMore: investigateFullScreenCandidate,
                onSaveMapCandidate: saveFullScreenMapCandidate,
                onSaveSocialPlace: saveFullScreenSocialPlace,
                onUpdatePlaceVisibility: { place, visibility in
                    try await mapVM.updatePlaceVisibility(place, visibility: visibility)
                },
                onUpdatePlace: { place in
                    try await mapVM.updatePlace(place)
                },
                onFindRelatedSources: { place in
                    try await mapVM.discoverRelatedSources(for: place)
                },
                onAddPlaceToTrip: requestFullScreenTripAssignment,
                onCreateList: {
                    mapVM.createCollaborativeList(
                        title: languageSettings.localized(english: "New list", traditionalChinese: "新清單"),
                        note: nil
                    )
                },
                onAddPlaceToList: { place, listID in
                    try mapVM.addPlace(place, toListID: listID)
                }
            )
            .environment(\.appLanguageSettings, languageSettings)
            .background(SaveDottedBackground().ignoresSafeArea())
            .alert(
                languageSettings.localized(english: "Couldn’t finish that action", traditionalChinese: "無法完成這個動作"),
                isPresented: Binding(
                    get: { fullScreenActionError != nil },
                    set: { if !$0 { fullScreenActionError = nil } }
                )
            ) {
                Button(languageSettings.text(.ok)) { fullScreenActionError = nil }
            } message: {
                Text(fullScreenActionError ?? "")
            }
            .confirmationDialog(
                languageSettings.localized(
                    english: "Saved. Add it to a Trip?",
                    traditionalChinese: "已收藏。要加入行程嗎？"
                ),
                isPresented: $isFullScreenTripAssignmentDialogPresented,
                titleVisibility: .visible
            ) {
                tripAssignmentActions(dismissFullScreen: true)
            } message: {
                tripAssignmentMessage
            }
        }
    }

    private var drawerView: some View {
        AIDrawerView(
            viewModel: drawerVM,
            drawerDetent: $drawerDetent,
            mapDetailDrawerItem: $mapDetailDrawerItem,
            launchRequest: drawerLaunchRequest,
            captureTripName: captureTripName,
            reviewCandidates: mapVM.reviewCandidates,
            onSaveGoogleTakeoutImport: { drafts in
                try await mapVM.saveImportedPlaces(drafts)
            },
            onDeletePlace: { place in
                try await mapVM.deletePlace(place)
            },
            onSaveCandidate: { candidate, nameOverride in
                let place = try await mapVM.saveReviewCandidateAsPlace(candidate, nameOverride: nameOverride)
                requestTripAssignment(for: place)
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
            onFindRelatedSources: { place in
                try await mapVM.discoverRelatedSources(for: place)
            },
            onImportSharedTextAsReviewCandidates: { sharedText in
                try await mapVM.importSharedTextAsReviewCandidates(sharedText)
            },
            onOpenReview: {
                isRootSheetPresented = false
                selectedRootTab = .saves
            },
            onAddPlaceToTrip: requestTripAssignment,
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
            socialPlaces: mapVM.visibleSocialPlaces,
            followedFriends: mapVM.followedFriends,
            isLoadingFollowedFriends: mapVM.isLoadingFollowedFriends,
            followedFriendsLoadFailed: mapVM.followedFriendsLoadFailed,
            hasMoreFollowedFriends: mapVM.hasMoreFollowedFriends,
            isLoadingMoreFollowedFriends: mapVM.isLoadingMoreFollowedFriends,
            followedFriendsLoadMoreFailed: mapVM.followedFriendsLoadMoreFailed,
            onSelectSocialLens: { lens in
                mapVM.selectSocialLens(lens)
            },
            onSaveSocialPlace: { place in
                _ = try await mapVM.saveSocialPlaceToMySave(place)
            },
            onFollowReferral: { value in
                try await mapVM.followReferral(value)
            },
            onRefreshFollowedFriends: {
                await mapVM.refreshFollowedFriends(force: true)
            },
            onSearchFollowedFriends: { query in
                await mapVM.refreshFollowedFriends(query: query, force: true)
            },
            onLoadMoreFollowedFriends: {
                await mapVM.loadMoreFollowedFriends()
            },
            onUnfollowFriend: { friend in
                try await mapVM.unfollowFriend(friend)
            },
            selectedCategories: mapVM.selectedCategories,
            onToggleCategory: { category in
                mapVM.toggleCategory(category)
            },
            onOpenPassport: openPassport,
            onDismissMapDetailSheet: {
                isRootSheetPresented = false
                // Closing a place detail on the Map tab returns straight to
                // the map: leaving the panel expanded stranded the user on an
                // empty ask/search drawer as an extra step.
                if isMapPanelExpanded {
                    collapseMapPanel()
                }
            },
            onDismissMapDetail: {
                mapVM.clearSelectedMapObject()
            },
            onShowMapCandidatesOnMap: showMapCandidatesOnMap
        )
        .environment(\.appLanguageSettings, languageSettings)
        .presentationDetents([.height(132), .medium, .large], selection: $drawerDetent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationBackground(.clear)
        .presentationCornerRadius(32)
    }

    private func openMapDetail(_ item: MapDetailDrawerItem) {
        guard incomingPlaceReceipt == nil else { return }
        if pendingCaptureTripID == nil {
            pendingCaptureTripID = activeTripID
        }

        guard selectedRootTab == .map || !rootPath.isEmpty else {
            fullScreenRoute = .placeDetail(item)
            return
        }

        drawerVM.returnToCommands()
        // One place, one surface: the detail panel replaces the Atlas place
        // card. Leaving the card selected kept both visible at once.
        mapVM.clearSelectedMapObject()
        mapDetailDrawerItem = item
        if selectedRootTab == .map, rootPath.isEmpty {
            // Root Map owns the single morphing drawer surface.
            drawerDetent = .large
            isMapPanelExpanded = true
        } else {
            // Trip surfaces keep the presented sheet: their close/return
            // semantics (and the UI tests encoding them) expect a modal.
            withAnimation(SaveTheme.Motion.standardSpring) {
                drawerDetent = .medium
            }
            isRootSheetPresented = true
        }
    }

    private func openDrawer(
        _ target: DrawerLaunchTarget,
        tripID: UUID?,
        initialQuery: String? = nil
    ) {
        guard incomingPlaceReceipt == nil else { return }
        pendingCaptureTripID = tripID
        mapDetailDrawerItem = nil
        mapVM.clearSelectedMapObject()
        drawerVM.returnToCommands()

        switch target {
        case .addLink:
            fullScreenRoute = .capture
            return
        case .review, .saved:
            selectedRootTab = .saves
            return
        case .ask:
            rootPath.removeAll()
            // Trips P1: asking from Trips expands the panel in place — the
            // user stays on Trips instead of being bounced to Map.
            if selectedRootTab != .trips {
                selectedRootTab = .map
            }
        }

        drawerLaunchRequest = DrawerLaunchRequest(target: target, initialQuery: initialQuery)
        drawerDetent = .large
        isMapPanelExpanded = true
    }

    private func openPassport() {
        guard !isPassportPresented else { return }
        SaveHaptics.tap()

        if isMapPanelExpanded {
            collapseMapPanel()
        }
        if isRootSheetPresented {
            isRootSheetPresented = false
            Task { @MainActor in
                await Task.yield()
                isPassportPresented = true
            }
        } else {
            isPassportPresented = true
        }
    }

    private func openCollaborativeListOnMap(_ list: SaveCollaborativeList) {
        isPassportPresented = false
        selectedRootTab = .map
        rootPath.removeAll()
        Task {
            await mapVM.planCollaborativeList(list)
        }
    }

    private func openReviewCandidate(_ candidate: PlaceReviewCandidate, tripID: UUID?) {
        pendingCaptureTripID = tripID
        fullScreenRoute = .placeDetail(.reviewCandidate(candidate))
    }

    private func saveFullScreenCandidate(_ candidate: PlaceReviewCandidate, nameOverride: String?) {
        fullScreenCandidateActionID = candidate.id
        Task {
            defer { fullScreenCandidateActionID = nil }
            do {
                let place = try await mapVM.saveReviewCandidateAsPlace(candidate, nameOverride: nameOverride)
                requestFullScreenTripAssignment(for: place)
            } catch {
                fullScreenActionError = error.localizedDescription
            }
        }
    }

    private func rejectFullScreenCandidate(_ candidate: PlaceReviewCandidate) {
        performFullScreenCandidateAction(candidate) {
            try await mapVM.rejectReviewCandidate(candidate)
            fullScreenRoute = nil
        }
    }

    private func keepFullScreenCandidateSourceOnly(_ candidate: PlaceReviewCandidate) {
        performFullScreenCandidateAction(candidate) {
            try await mapVM.saveReviewCandidateAsSourceOnly(candidate)
            fullScreenRoute = nil
        }
    }

    private func markFullScreenCandidateWrongBranch(_ candidate: PlaceReviewCandidate) {
        performFullScreenCandidateAction(candidate) {
            try await mapVM.markReviewCandidateWrongBranch(candidate)
            openExactSearch(candidate)
        }
    }

    private func investigateFullScreenCandidate(_ candidate: PlaceReviewCandidate) {
        performFullScreenCandidateAction(candidate) {
            try await mapVM.investigateReviewCandidateMore(candidate)
            openExactSearch(candidate)
        }
    }

    private func performFullScreenCandidateAction(
        _ candidate: PlaceReviewCandidate,
        action: @escaping () async throws -> Void
    ) {
        fullScreenCandidateActionID = candidate.id
        Task {
            defer { fullScreenCandidateActionID = nil }
            do {
                try await action()
            } catch {
                fullScreenActionError = error.localizedDescription
            }
        }
    }

    private func saveFullScreenMapCandidate(_ candidate: SaveMapCandidate) {
        fullScreenMapCandidateActionID = candidate.id
        Task {
            defer { fullScreenMapCandidateActionID = nil }
            do {
                try await mapVM.saveMapCandidateAsPlace(candidate)
                fullScreenRoute = nil
            } catch {
                fullScreenActionError = error.localizedDescription
            }
        }
    }

    private func saveFullScreenSocialPlace(_ place: Place) {
        Task {
            do {
                _ = try await mapVM.saveSocialPlaceToMySave(place)
                fullScreenRoute = nil
            } catch {
                fullScreenActionError = error.localizedDescription
            }
        }
    }

    /// "Find exact place" lands the user on the map with the candidate pins
    /// focused, instead of stranding them in a drawer list that covers the
    /// map. Any open drawer surface closes; tapping a pin opens its receipt.
    private func showMapCandidatesOnMap() {
        isRootSheetPresented = false
        isMapPanelExpanded = false
        rootPath.removeAll()
        selectedRootTab = .map
        drawerVM.returnToCommands()
    }

    private func openExactSearch(_ candidate: PlaceReviewCandidate) {
        let query = candidate.refinementQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            fullScreenActionError = languageSettings.localized(
                english: "Add a city, address, or map link before searching for the exact place.",
                traditionalChinese: "請先補上城市、地址或地圖連結，再搜尋精確地點。"
            )
            return
        }
        fullScreenRoute = nil
        rootPath.removeAll()
        selectedRootTab = .map
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            let candidates = await mapVM.prepareMapCandidatesForDrawerQuery(query)
            if candidates.isEmpty {
                // No map match: fall back to the guided drawer flow so the
                // user gets the "add another clue" explanation instead of an
                // empty map.
                openDrawer(.ask, tripID: nil, initialQuery: query)
            } else {
                drawerVM.mapCandidates = candidates
                showMapCandidatesOnMap()
            }
        }
    }

    private func openFoodAnalysis(_ place: Place) {
        transitionFromFullScreenToMapDrawer {
            drawerVM.showFoodPlaceAnalysis(
                for: place,
                outputLanguage: languageSettings.language
            )
            drawerDetent = .large
        }
    }

    private func openPlanAround(_ place: Place) {
        transitionFromFullScreenToMapDrawer {
            await drawerVM.showPlanAround(
                anchor: place,
                reviewCandidates: mapVM.reviewCandidates,
                outputLanguage: languageSettings.language
            )
            drawerDetent = .large
        }
    }

    private func transitionFromFullScreenToMapDrawer(
        action: @escaping () async -> Void
    ) {
        fullScreenRoute = nil
        rootPath.removeAll()
        selectedRootTab = .map
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            openDrawer(.ask, tripID: nil)
            await Task.yield()
            await action()
        }
    }

    private func openPostcardDrawerUITestFixtureIfNeeded() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("--uitest-postcard-unsaved") {
            openMapDetail(.unsavedCandidate(SaveMapCandidate(
                id: "postcard-unsaved-fixture",
                title: "Tsukiji Outer Market",
                subtitle: "4 Chome-16-2 Tsukiji, Chuo City, Tokyo",
                latitude: 35.6655,
                longitude: 139.7707,
                category: .food,
                rating: 4.5,
                reviewCount: 18_420,
                sourceURL: "https://maps.apple.com/?q=Tsukiji+Outer+Market",
                sourcePlatform: .appleMaps,
                distanceMeters: 820,
                evidence: [
                    "Apple Maps POI",
                    "Search: Tokyo seafood market",
                    "Hours: 5:00 AM–2:00 PM",
                ]
            )))
            return
        }

        if arguments.contains("--uitest-postcard-social") {
            openMapDetail(.socialPlace(Place(
                id: UUID(uuidString: "7C4BFB3D-BA7C-4D62-B502-78222AD12E14")!,
                name: "Stereoscope Coffee",
                address: "4542 Beach Blvd, Buena Park, CA",
                latitude: 33.8937,
                longitude: -117.9992,
                category: .cafe,
                status: .wantToGo,
                rating: 4.7,
                note: "A calm coffee stop saved by people you follow.",
                sourcePlatform: .other,
                recommender: "Jerry's coffee list",
                googleRating: 4.6,
                createdAt: Date(timeIntervalSince1970: 1_721_865_600),
                visibility: .publicGuide,
                socialSignal: PlaceSocialSignal(
                    kind: .friendSaved,
                    lens: .friends,
                    friendNames: ["Jerry", "Mina"],
                    friendCount: 2,
                    saveCount: 42,
                    trendingRank: nil,
                    categoryRank: 3,
                    sourceLabel: "Jerry's team",
                    referrerId: "postcard-social-fixture",
                    referralCode: nil
                )
            )))
        }
#endif
    }

    private func handleRootSheetDismiss() {
        let pendingDetail = pendingReceiptMapDetail
        pendingReceiptMapDetail = nil
        incomingPlaceReceipt = nil
        if pendingTripAssignmentPlace == nil {
            pendingCaptureTripID = nil
        }
        drawerVM.returnToCommands()
        if pendingTripAssignmentPlace != nil {
            presentTripAssignmentDialog()
        }
        guard let pendingDetail else {
            mapVM.clearSelectedMapObject()
            return
        }

        guard selectedRootTab == .map, rootPath.isEmpty else {
            fullScreenRoute = .placeDetail(pendingDetail)
            return
        }

        mapDetailDrawerItem = pendingDetail

        Task { @MainActor in
            await Task.yield()
            drawerDetent = .medium
            isRootSheetPresented = true
        }
    }

    private func handleFullScreenDismiss() {
        if isTransitioningToTripCreation {
            Task { @MainActor in
                await Task.yield()
                guard pendingTripAssignmentPlace != nil else {
                    isTransitioningToTripCreation = false
                    return
                }
                isCreatingTripForAssignment = true
                isTransitioningToTripCreation = false
            }
            return
        }
        if pendingTripAssignmentPlace != nil {
            presentTripAssignmentDialog()
        }
    }

    private func presentTripAssignmentDialog() {
        Task { @MainActor in
            await Task.yield()
            isTripAssignmentDialogPresented = true
        }
    }

    private var tripAssignmentChoices: [Trip] {
        let availableTrips = tripStore.currentTrips + tripStore.upcomingTrips + tripStore.planningTrips
        var seen = Set<UUID>()
        let uniqueTrips = availableTrips.filter { seen.insert($0.id).inserted }
        guard let pendingCaptureTripID,
              let originTrip = uniqueTrips.first(where: { $0.id == pendingCaptureTripID })
        else { return uniqueTrips }
        return [originTrip] + uniqueTrips.filter { $0.id != pendingCaptureTripID }
    }

    private var captureTripName: String? {
        guard let pendingCaptureTripID else { return nil }
        return tripStore.trips.first(where: { $0.id == pendingCaptureTripID })?.name
    }

    @ViewBuilder
    private func tripAssignmentActions(dismissFullScreen: Bool) -> some View {
        ForEach(tripAssignmentChoices) { trip in
            Button(languageSettings.localized(
                english: "Add to \(trip.name)",
                traditionalChinese: "加入「\(trip.name)」"
            )) {
                guard let place = pendingTripAssignmentPlace else { return }
                finishTripAssignment()
                if dismissFullScreen {
                    fullScreenRoute = nil
                }
                Task { await addConfirmedPlaceToTrip(place, tripID: trip.id) }
            }
        }
        Button(languageSettings.localized(
            english: "Create new Trip and add",
            traditionalChinese: "新增行程並加入"
        )) {
            isTransitioningToTripCreation = true
            if dismissFullScreen {
                isFullScreenTripAssignmentDialogPresented = false
                fullScreenRoute = nil
            } else {
                isTripAssignmentDialogPresented = false
                Task { @MainActor in
                    await Task.yield()
                    guard pendingTripAssignmentPlace != nil else {
                        isTransitioningToTripCreation = false
                        return
                    }
                    isCreatingTripForAssignment = true
                    isTransitioningToTripCreation = false
                }
            }
        }
        .accessibilityIdentifier("saved.addToTrip.create")
        Button(
            languageSettings.localized(
                english: "Keep in SAV-E only",
                traditionalChinese: "只存到 SAV-E"
            ),
            role: .cancel
        ) {
            finishTripAssignment()
            if dismissFullScreen {
                fullScreenRoute = nil
            }
        }
    }

    private var tripAssignmentMessage: Text {
        Text(languageSettings.localized(
            english: tripAssignmentChoices.isEmpty
                ? "This place is in Saved. Create a Trip now, or keep it in Saved only."
                : "Choose the exact Trip, create a new one, or keep the place in Saved only.",
            traditionalChinese: tripAssignmentChoices.isEmpty
                ? "這個地點已收藏；現在建立行程，或只保留在收藏。"
                : "請選擇現有行程、建立新行程，或只保留在收藏。"
        ))
    }

    private func requestFullScreenTripAssignment(for place: Place) {
        pendingTripAssignmentPlace = place
        isFullScreenTripAssignmentDialogPresented = true
    }

    private func requestTripAssignment(for place: Place) {
        pendingTripAssignmentPlace = place
        if fullScreenRoute != nil {
            fullScreenRoute = nil
        } else if isRootSheetPresented {
            isRootSheetPresented = false
        } else {
            presentTripAssignmentDialog()
        }
    }

    private func finishTripAssignment() {
        isTripAssignmentDialogPresented = false
        isFullScreenTripAssignmentDialogPresented = false
        isTransitioningToTripCreation = false
        pendingTripAssignmentPlace = nil
        pendingCaptureTripID = nil
    }

    private func addConfirmedPlaceToTrip(_ place: Place, tripID: UUID) async {
        _ = await tripStore.addConfirmedPlace(place, to: tripID)
    }

    private func refreshSelectedMapDetailPlace(from places: [Place]) {
        if case .savedPlace(let selectedPlace) = mapDetailDrawerItem,
           let updatedPlace = places.first(where: { $0.id == selectedPlace.id }),
           updatedPlace != selectedPlace {
            mapDetailDrawerItem = .savedPlace(updatedPlace)
        }

        if case .placeDetail(.savedPlace(let fullScreenPlace)) = fullScreenRoute,
           let updatedFullScreenPlace = places.first(where: { $0.id == fullScreenPlace.id }),
           updatedFullScreenPlace != fullScreenPlace {
            fullScreenRoute = .placeDetail(.savedPlace(updatedFullScreenPlace))
        }
    }
}

private struct SaveCaptureFlowView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let tripName: String?
    let onImport: (String) async throws -> [UUID]
    let onComplete: () -> Void
    let onCancel: () -> Void
    @State private var sharedText = ""
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SaveDottedBackground().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(localized("CAPTURE A CLUE", "收下一個線索"))
                                    .font(SaveAtlasType.strong(11))
                                    .tracking(1.0)
                                    .foregroundStyle(SaveAtlasPalette.muted)
                                Text(localized("Paste or share a link", "貼上或分享連結"))
                                    .font(SaveAtlasType.strong(29, relativeTo: .title))
                                    .foregroundStyle(SaveAtlasPalette.forest)
                                Text(localized(
                                    "SAV-E will analyze it, then place every uncertain result in Review.",
                                    "SAV-E 會先分析；任何不確定結果都只會進入待確認。"
                                ))
                                .font(SaveAtlasType.body(14))
                                .foregroundStyle(SaveAtlasPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                            MemoMascotMark(size: 72, framed: false)
                                .accessibilityHidden(true)
                        }

                        if let tripName {
                            Label(
                                localized("For \(tripName)", "準備加入「\(tripName)」"),
                                systemImage: "suitcase.rolling.fill"
                            )
                            .font(SaveAtlasType.strong(13))
                            .foregroundStyle(SaveAtlasPalette.forest)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(SaveAtlasPalette.mint, in: Capsule())
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text(localized("LINK, CAPTION, OR MESSAGE", "連結、貼文文字或訊息"))
                                .font(SaveAtlasType.strong(10))
                                .tracking(0.9)
                                .foregroundStyle(SaveAtlasPalette.muted)

                            TextEditor(text: $sharedText)
                                .font(SaveAtlasType.body(16))
                                .foregroundStyle(SaveAtlasPalette.ink)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 190)
                                .padding(10)
                                .background(SaveAtlasPalette.paper)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            SaveAtlasPalette.sky.opacity(0.82),
                                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                                        )
                                }
                                .accessibilityIdentifier("capture.input")

                            HStack(spacing: 10) {
                                PasteButton(payloadType: String.self) { values in
                                    if let value = values.first {
                                        sharedText = value
                                    }
                                }
                                .labelStyle(.titleAndIcon)
                                .font(SaveAtlasType.strong(14))
                                .tint(SaveAtlasPalette.forest)
                                .accessibilityIdentifier("capture.paste")

                                Spacer(minLength: 0)

                                Text(localized(
                                    "Nothing is saved before Review.",
                                    "確認前不會建立地圖章。"
                                ))
                                .font(SaveAtlasType.body(11))
                                .foregroundStyle(SaveAtlasPalette.muted)
                            }
                        }
                        .padding(16)
                        .saveAtlasPaper(radius: 20, shadow: true)

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(SaveAtlasType.body(13))
                                .foregroundStyle(SaveAtlasPalette.coral)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("capture.error")
                        }

                        Button(action: analyze) {
                            HStack(spacing: 9) {
                                if isAnalyzing {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(isAnalyzing
                                    ? localized("Analyzing…", "分析中…")
                                    : localized("Analyze into Review", "分析後送進待確認"))
                            }
                            .font(SaveAtlasType.strong(17))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(SaveAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(trimmedText.isEmpty || isAnalyzing)
                        .opacity(trimmedText.isEmpty || isAnalyzing ? 0.48 : 1)
                        .accessibilityIdentifier("capture.analyze")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .padding(.bottom, 30)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .accessibilityLabel(localized("Close capture", "關閉新增線索"))
                }
            }
            .toolbarBackground(SaveAtlasPalette.canvas.opacity(0.96), for: .navigationBar)
        }
        .accessibilityIdentifier("capture.flow")
    }

    private var trimmedText: String {
        sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func analyze() {
        guard !trimmedText.isEmpty, !isAnalyzing else { return }
        isAnalyzing = true
        errorMessage = nil
        Task {
            defer { isAnalyzing = false }
            do {
                let candidateIDs = try await onImport(trimmedText)
                guard !candidateIDs.isEmpty else {
                    errorMessage = localized(
                        "No place clue was found. Add the post caption, city, or a map link and try again.",
                        "沒有找到地點線索。請補上貼文文字、城市或地圖連結後再試。"
                    )
                    return
                }
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct FriendShareReceiptView: View {
    private enum LoadState {
        case loading
        case loaded(SharedPlaceReceipt)
        case failed(SharedPlaceReceiptError)
    }

    private enum SaveState {
        case idle
        case saving
        case saved
        case alreadySaved
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.appLanguageSettings) private var languageSettings
    let destination: SharedPlaceReceiptDestination
    let onSave: (SharedPlaceReceipt) async throws -> SharedPlaceSaveOutcome
    @State private var loadState: LoadState = .loading
    @State private var saveState: SaveState = .idle
    @State private var saveErrorMessage: String?
    @State private var retryCount = 0
    @State private var activeLoadID: UUID?
    @State private var activeSaveID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading:
                    loadingView
                case .loaded(let receipt):
                    receiptView(receipt)
                case .failed(let error):
                    errorView(error)
                }
            }
            .navigationTitle(localized("Shared place", "好友分享"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized("Done", "完成")) { dismiss() }
                        .disabled(saveState == .saving)
                }
            }
        }
        .task(id: "\(destination.id):\(retryCount)") {
            await loadReceipt()
        }
        .onDisappear {
            activeLoadID = nil
            activeSaveID = nil
        }
        .interactiveDismissDisabled(saveState == .saving)
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(localized("Verifying this share receipt…", "正在驗證這張分享收據…"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: SharedPlaceReceiptError) -> some View {
        ContentUnavailableView {
            Label(localized("Could not open this place", "無法打開這個地點"), systemImage: "link.badge.plus")
        } description: {
            Text(localized(error.errorDescription ?? "The link is unavailable.", errorMessage(error)))
        } actions: {
            if case .shortLink = destination {
                Button(localized("Try Again", "再試一次")) {
                    retryCount += 1
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func receiptView(_ receipt: SharedPlaceReceipt) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    if let sender = receipt.verifiedSenderLabel {
                        Label(localized("Shared by \(sender)", "由 \(sender) 分享"), systemImage: "person.crop.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.saveCoral)
                            .accessibilityIdentifier("friendShareReceipt.sender")
                    } else {
                        Label(localized("Shared place", "分享的地點"), systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(receipt.payload.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.saveInk)

                    if !receipt.payload.address.isEmpty {
                        Text(receipt.payload.address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(receipt.payload.category)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.saveHoney.opacity(0.35), in: Capsule())
                }

                if let note = receipt.payload.note, !note.isEmpty {
                    receiptSection(
                        title: receipt.verifiedSenderLabel == nil
                            ? localized("Shared note", "分享備註")
                            : localized("Why they shared it", "為什麼推薦這裡"),
                        value: note,
                        icon: "quote.bubble"
                    )
                }

                receiptSection(
                    title: localized("Original source", "原始來源"),
                    value: receipt.payload.sourceLabel,
                    icon: "link"
                )

                if let sourceURL = receipt.payload.safeSourceURL {
                    Link(destination: sourceURL) {
                        Label(localized("Open original source", "打開原始來源"), systemImage: "arrow.up.right.square")
                    }
                    .font(.subheadline.weight(.semibold))
                }

                if receipt.verifiedSenderLabel != nil {
                    Label(
                        localized("Share record verified by SAV-E. Saving stays private.", "分享紀錄已由 SAV-E 驗證；儲存後仍是私人記憶。"),
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await save(receipt) }
                    } label: {
                        Label(saveButtonTitle, systemImage: saveButtonIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.saveCoral)
                    .controlSize(.large)
                    .disabled(saveState != .idle)
                    .accessibilityIdentifier("friendShareReceipt.save")

                    if let saveErrorMessage {
                        Text(saveErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("friendShareReceipt.saveError")
                    }

                    if let mapsURL = receipt.payload.appleMapsURL {
                        Button {
                            openURL(mapsURL)
                        } label: {
                            Label(localized("Open in Maps", "在地圖中打開"), systemImage: "map")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("friendShareReceipt.openMaps")
                    }
                }
            }
            .padding(24)
        }
        .background(Color.saveCream.ignoresSafeArea())
    }

    private func receiptSection(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(Color.saveInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.savePaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var saveButtonTitle: String {
        switch saveState {
        case .idle: return localized("Save to my SAV-E", "存到我的 SAV-E")
        case .saving: return localized("Saving…", "儲存中…")
        case .saved: return localized("Saved privately", "已私人儲存")
        case .alreadySaved: return localized("Already saved", "已經存過")
        }
    }

    private var saveButtonIcon: String {
        switch saveState {
        case .idle: return "bookmark"
        case .saving: return "hourglass"
        case .saved: return "checkmark.circle.fill"
        case .alreadySaved: return "checkmark.circle"
        }
    }

    @MainActor
    private func loadReceipt() async {
        let loadID = UUID()
        let expectedDestination = destination
        activeLoadID = loadID
        activeSaveID = nil
        saveState = .idle
        saveErrorMessage = nil
        switch expectedDestination {
        case .embedded(let payload):
            guard activeLoadID == loadID else { return }
            loadState = .loaded(.embedded(payload))
        case .malformed:
            guard activeLoadID == loadID else { return }
            loadState = .failed(.malformedLink)
        case .shortLink(let url):
            loadState = .loading
            do {
                let receipt = try await SharedPlaceReceipt.resolve(from: url)
                guard !Task.isCancelled, activeLoadID == loadID else { return }
                loadState = .loaded(receipt)
                if let code = receipt.code {
                    guard !Task.isCancelled, activeLoadID == loadID else { return }
                    try? await SupabaseService.shared.recordFriendShareEvent(
                        code: code,
                        event: .receiptOpened,
                        failureReason: nil
                    )
                }
            } catch is CancellationError {
                return
            } catch let error as SharedPlaceReceiptError {
                guard !Task.isCancelled, activeLoadID == loadID else { return }
                loadState = .failed(error)
                if let code = SharedPlaceData.shortCode(from: url) {
                    guard !Task.isCancelled, activeLoadID == loadID else { return }
                    try? await SupabaseService.shared.recordFriendShareEvent(
                        code: code,
                        event: .openFailed,
                        failureReason: error.eventFailureReason
                    )
                }
            } catch {
                guard !Task.isCancelled, activeLoadID == loadID else { return }
                loadState = .failed(.invalidResponse)
                if let code = SharedPlaceData.shortCode(from: url) {
                    guard !Task.isCancelled, activeLoadID == loadID else { return }
                    try? await SupabaseService.shared.recordFriendShareEvent(
                        code: code,
                        event: .openFailed,
                        failureReason: .unknown
                    )
                }
            }
        }
    }

    @MainActor
    private func save(_ receipt: SharedPlaceReceipt) async {
        guard saveState == .idle,
              case .loaded(let currentReceipt) = loadState,
              currentReceipt.id == receipt.id
        else { return }
        let saveID = UUID()
        activeSaveID = saveID
        saveState = .saving
        saveErrorMessage = nil
        do {
            let outcome = try await onSave(receipt)
            guard !Task.isCancelled,
                  activeSaveID == saveID,
                  case .loaded(let currentReceipt) = loadState,
                  currentReceipt.id == receipt.id
            else { return }
            saveState = outcome.isDuplicate ? .alreadySaved : .saved
        } catch {
            guard !Task.isCancelled,
                  activeSaveID == saveID,
                  case .loaded(let currentReceipt) = loadState,
                  currentReceipt.id == receipt.id
            else { return }
            saveState = .idle
            saveErrorMessage = localized(
                "Couldn't save this verified share. It may have expired; refresh the receipt and try again.",
                "無法儲存這張已驗證的分享。連結可能已過期；請重新載入收據後再試。"
            )
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }

    private func errorMessage(_ error: SharedPlaceReceiptError) -> String {
        switch error {
        case .malformedLink: return "這個分享連結格式不正確。"
        case .missingAPIConfiguration: return "SAV-E 尚未設定好這個分享服務。"
        case .networkUnavailable: return "請檢查網路後再試一次。"
        case .missingOrExpired: return "這個分享連結不存在或已過期。"
        case .serverUnavailable: return "分享收據暫時無法使用。"
        case .invalidResponse: return "SAV-E 無法驗證這張分享收據。"
        }
    }
}

#Preview {
    ContentView()
        .environment(\.appLanguageSettings, AppLanguageSettings())
}
