#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import SwiftUI
import MapKit

/// A navigation request carries IDs only; MapViewModel remains the source of truth.
struct LiveReviewInboxRequest: Equatable {
    let id = UUID()
    let candidateIDs: [UUID]
}

/// Runtime boundaries can be replaced by isolated simulator fixtures without
/// changing authentication or reimplementing the root's presentation flow.
@MainActor
struct LivePlanningDependencies {
    let outing: LiveOutingModel
    let plan: LiveRoutePlan
    let discovery: LivePublicDiscoveryModel
    let sessionIsCurrent: @MainActor () -> Bool
}

/// A child of the existing verified account root. The parent owns loading and persistence.
@MainActor
struct LivePlanningMapRoot: View {
    @ObservedObject var mapVM: MapViewModel
    let ownerSubject: String
    let sessionGeneration: Int
    let onOpenSaved: (Place) -> Void
    let onOpenAccount: () -> Void
    let onCapture: () -> Void
    let reviewInboxRequest: LiveReviewInboxRequest?
    let onOpenReview: (UUID) -> Void
    let onClearReviewBatch: () -> Void
    private let currentSession: @MainActor () -> Bool
    private let usesFixtureMap: Bool
    @StateObject private var outing: LiveOutingModel
    @StateObject private var plan: LiveRoutePlan
    @StateObject private var discovery: LivePublicDiscoveryModel
    @State private var destination = DemoDestination.saved
    @State private var previousRootDestination = DemoDestination.saved
    @State private var savedQuery = ""
    @FocusState private var savedSearchFocused: Bool
    @State private var hasOpenedMap = false
    @State private var mapPresentation = PocketCityPresentation()
    @State private var appliedWeatherArea: PocketCityForecast.Area?
    @State private var mapForecast: PocketCityForecast.Result?
    @State private var pocketMapFailed = false
    @State private var showsFriends = false
    @State private var savedOnly = false
    @State private var creditsRequest = 0
    @State private var atlasSheetOpen = false
    @StateObject private var atlasDrawer = PocketCityPlaceDrawer()
    @State private var discoveryReload = 0
    @State private var camera = MapCameraPosition.region(MKCoordinateRegion(
        center: .init(latitude: 25.04, longitude: 121.54), span: .init(latitudeDelta: 0.07, longitudeDelta: 0.07)))
    @State private var cameraRequestID = 0
    @State private var searchRegion = MKCoordinateRegion(center: .init(latitude: 25.04, longitude: 121.54),
                                                       span: .init(latitudeDelta: 0.07, longitudeDelta: 0.07))
    @State private var friendsVisitedOnly = false
    @State private var searchPresented = false
    @State private var selected: LiveMapPlace?
    @State private var pendingSavedDetail: UUID?
    @State private var pendingGuideDestination: LivePublicGuideDestination?
    @State private var guideListToOpen: UUID?
    @State private var savingPinID: String?
    @State private var saveError: String?
    @State private var saveOperation: Task<Void, Never>?
    @State private var searchPin: LiveMapPlace?
    @State private var selectedStops: [String] = []
    @State private var stopSelectionListID: UUID?
    @State private var isMounted = false
    @State private var planOperation: Task<Void, Never>?
    @State private var lifecycleRevision: UInt64 = 0
    @State private var guideAccess = LiveGuideAccess()
    @State private var teamPresented = false
    @State private var newListTitle = ""
    @State private var joinCode = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.scenePhase) private var scenePhase

    init(mapVM: MapViewModel, ownerSubject: String, sessionGeneration: Int,
         onOpenSaved: @escaping (Place) -> Void, onOpenAccount: @escaping () -> Void,
         onCapture: @escaping () -> Void,
         reviewInboxRequest: LiveReviewInboxRequest? = nil,
         onOpenReview: @escaping (UUID) -> Void = { _ in },
         onClearReviewBatch: @escaping () -> Void = {},
         dependencies: LivePlanningDependencies? = nil) {
        self.mapVM = mapVM; self.ownerSubject = ownerSubject; self.sessionGeneration = sessionGeneration
        self.onOpenSaved = onOpenSaved; self.onOpenAccount = onOpenAccount; self.onCapture = onCapture
        usesFixtureMap = dependencies != nil
        self.reviewInboxRequest = reviewInboxRequest
        self.onOpenReview = onOpenReview
        self.onClearReviewBatch = onClearReviewBatch
        _outing = StateObject(wrappedValue: dependencies?.outing
            ?? LiveOutingModel(ownerSubject: ownerSubject, sessionGeneration: sessionGeneration))
        _plan = StateObject(wrappedValue: dependencies?.plan
            ?? LiveRoutePlan(ownerSubject: ownerSubject, sessionGeneration: sessionGeneration))
        _discovery = StateObject(wrappedValue: dependencies?.discovery
            ?? LivePublicDiscoveryModel(ownerSubject: ownerSubject, sessionGeneration: sessionGeneration))
        if let dependencies {
            currentSession = dependencies.sessionIsCurrent
        } else {
            currentSession = { @MainActor in
                let auth = PrivyAuthService.shared
                guard case .authenticated = auth.authState else { return false }
                return auth.currentUserId == ownerSubject && auth.sessionGeneration == sessionGeneration
            }
        }
    }

    private var saved: [LiveMapPlace] { mapVM.places.compactMap(LiveMapPlace.saved) }
    private var groupPlaces: [LiveMapPlace] {
        guard let id = outing.selectedListID else { return [] }
        return outing.items.compactMap { LiveMapPlace.shared($0, listID: id) }
    }
    private var friendEntries: [LiveFriendMapPlace] {
        LiveFriendMapPlace.projections(posts: outing.posts)
            .filter { outing.selectedListID != nil || !friendsVisitedOnly || $0.hasVisited }
    }
    private var friendPlaces: [LiveMapPlace] { LiveFriendMapPlace.groupedByVenue(friendEntries).compactMap { $0.first?.pin } }
    // Membership comes only from the active account. Use exact provider IDs to
    // carry its bookmark onto another representation of the same branch.
    private var savedVenueKeys: Set<LivePublicDiscoveryVenueKey> {
        Set(mapVM.places.compactMap { LivePublicDiscoveryVenueKey(savedPlace: $0) })
    }
    private var pins: [LiveMapPlace] {
        var values = saved
        if !savedOnly {
            values += discovery.page?.venues.compactMap(LiveMapPlace.discovery) ?? []
        }
        if showsFriends {
            let friends = friendPlaces
            let shared = friends + groupPlaces.filter { groupPin in
                !friends.contains { $0.place.matches(groupPin.place) }
            }
            let keys = savedVenueKeys
            values += shared.filter { pin in
                !savedOnly || LivePublicDiscoveryVenueKey(savedPlace: pin.place).map(keys.contains) == true
            }
        }
        if let searchPin, !savedOnly, !values.contains(where: { $0.id == searchPin.id }) {
            values.append(searchPin)
        }
        return values
    }
    private var sessionIsCurrent: Bool {
        currentSession()
    }
    private var shouldRefreshOuting: Bool { isMounted && scenePhase == .active && showsFriends }
    private var weatherArea: PocketCityForecast.Area? {
        guard isMounted, destination == .map, scenePhase == .active,
              !usesFixtureMap, !pocketMapFailed,
              searchRegion.span.latitudeDelta < 4, searchRegion.span.longitudeDelta < 4 else { return nil }
        return .init(latitude: searchRegion.center.latitude, longitude: searchRegion.center.longitude)
    }

    private func followWeather(in area: PocketCityForecast.Area?) async {
        if appliedWeatherArea != area {
            mapPresentation.weather = .day
            mapForecast = nil
            appliedWeatherArea = area
        }
        guard let area else { return }
        do {
            try await Task.sleep(for: .milliseconds(700))
            while !Task.isCancelled {
                let forecast = try await PocketCityForecast.shared.forecast(for: area)
                guard !Task.isCancelled, area == weatherArea else { return }
                let now = Date()
                mapForecast = forecast
                mapPresentation.weather = forecast.current(at: now)
                    .flatMap { PocketCityForecast.weather(for: $0.symbol) } ?? .day
                let nextHour = forecast.upcoming(at: now).first?.time ?? forecast.refreshAfter
                let nextUpdate = min(nextHour, forecast.refreshAfter)
                try await Task.sleep(for: .seconds(max(1, nextUpdate.timeIntervalSinceNow)))
            }
        } catch { /* Map moved or left the foreground. */ }
    }

    private var discoveryViewport: LivePublicDiscoveryViewport? {
        let span = searchRegion.span
        let center = searchRegion.center
        func longitude(_ value: Double) -> Double { (value + 540).truncatingRemainder(dividingBy: 360) - 180 }
        return try? LivePublicDiscoveryViewport(
            west: span.longitudeDelta >= 360 ? -180 : longitude(center.longitude - span.longitudeDelta / 2),
            south: max(-90, center.latitude - span.latitudeDelta / 2),
            east: span.longitudeDelta >= 360 ? 180 : longitude(center.longitude + span.longitudeDelta / 2),
            north: min(90, center.latitude + span.latitudeDelta / 2))
    }
    private var discoveryQuery: String {
        guard isMounted, scenePhase == .active, destination == .map, !savedOnly,
              let viewport = discoveryViewport else { return "inactive" }
        return "\(viewport.queryValue):\(discoveryReload)"
    }
    private var canShowPlan: Bool {
        shouldRefreshOuting && sessionIsCurrent && guideAccess.permits(plan: plan, outing: outing)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DateTheme.canvas.ignoresSafeArea()
                if hasOpenedMap || destination == .map {
                    mapPage(height: geometry.size.height)
                        .transition(reduceMotion ? .identity : .move(edge: .trailing))
                        .offset(x: destination == .saved ? geometry.size.width : 0)
                        .opacity(destination == .passport ? 0 : 1)
                        .allowsHitTesting(destination == .map)
                        .accessibilityHidden(destination != .map)
                }
                savedPage
                    .padding(.horizontal, 24).padding(.top, 62).padding(.bottom, 82)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DateTheme.canvas.ignoresSafeArea())
                    .offset(x: destination == .map ? -geometry.size.width : 0)
                    .opacity(destination == .passport ? 0 : 1)
                    .allowsHitTesting(destination == .saved)
                    .accessibilityHidden(destination != .saved)
                    .simultaneousGesture(pageSwipe)
                if destination == .passport {
                    passport
                        .padding(.horizontal, 24).padding(.top, 62)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DateTheme.canvas.ignoresSafeArea())
                }
                VStack(spacing: 0) {
                    rootHeader.simultaneousGesture(pageSwipe)
                    Spacer(minLength: 0)
                    if destination != .passport && !(destination == .map && atlasSheetOpen) {
                        dock.simultaneousGesture(pageSwipe)
                            .transaction(value: destination) { $0.animation = nil }
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 8)
            }.foregroundStyle(DateTheme.ink)
        }
        .onAppear {
            isMounted = true
            if ProcessInfo.processInfo.arguments.contains("--preview-tab-saved") { destination = .saved }
            if ProcessInfo.processInfo.arguments.contains("--preview-tab-passport")
                || ProcessInfo.processInfo.arguments.contains("--preview-account") { destination = .passport }
            if ProcessInfo.processInfo.arguments.contains("--map-mode-group") { showsFriends = true }
            if ProcessInfo.processInfo.arguments.contains("--map-mode-personal") { savedOnly = true }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--preview-account") {
                await Task.yield()
                guard !Task.isCancelled, sessionIsCurrent else { return }
                onOpenAccount()
            }
        }
        .onChange(of: reviewInboxRequest?.id, initial: true) { _, requestID in
            guard requestID != nil else { return }
            selected = nil
            searchPresented = false
            destination = .saved
        }
        .onChange(of: destination) { old, next in
            if next == .map { hasOpenedMap = true }
            else { atlasSheetOpen = false; atlasDrawer.dismiss() }
            if next == .passport, old != .passport { previousRootDestination = old }
            if next != .saved { savedSearchFocused = false }
        }
        .onChange(of: showsFriends) { _, enabled in
            if !enabled {
                lifecycleRevision &+= 1
                guideAccess.invalidate()
                planOperation?.cancel(); plan.cancel(); outing.deactivate()
                if selected?.origin == .shared { selected = nil }
                selectedStops = []; stopSelectionListID = nil; guideListToOpen = nil
            }
        }
        .onChange(of: savedOnly) { _, enabled in
            if enabled { searchPin = nil }
        }
        .onChange(of: outing.snapshotRevision) { _, _ in
            reconcilePlan()
            if selected?.origin == .shared { selected = nil }
        }
        .onChange(of: outing.error) { _, value in
            if value != nil, shouldRefreshOuting, outing.selectedListID == nil { plan.cancel() }
        }
        .onChange(of: outing.posts) { _, _ in
            if selected?.origin == .shared { selected = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { suspendPlanning() }
        }
        .onDisappear { atlasSheetOpen = false; atlasDrawer.dismiss(); isMounted = false; suspendPlanning(); saveOperation?.cancel() }
        .task(id: weatherArea) { await followWeather(in: weatherArea) }
        .task(id: discoveryQuery) {
            guard discoveryQuery != "inactive", let viewport = discoveryViewport, sessionIsCurrent else {
                discovery.clear(); return
            }
            await discovery.refreshMap(viewport)
        }
        .onChange(of: discovery.page?.indexRevision) { _, _ in
            if selected?.origin == .publicPost { selected = nil }
        }
        .task(id: shouldRefreshOuting) {
            guard shouldRefreshOuting, !Task.isCancelled, sessionIsCurrent else { return }
            outing.resumeAfterNavigation()
            let previousSnapshot = outing.snapshotRevision
            if let listID = guideListToOpen {
                guideListToOpen = nil
                await outing.selectList(listID)
            } else {
                await outing.refresh()
            }
            guard !Task.isCancelled, shouldRefreshOuting, sessionIsCurrent else { return }
            if outing.snapshotRevision == previousSnapshot { plan.cancel(); selectedStops = [] }
        }
        .tint(DateTheme.blue)
        .sheet(isPresented: $searchPresented) {
            LiveMapSearch(region: searchRegion) { pin in
                guard sessionIsCurrent else { return }
                destination = .map
                savedOnly = false
                searchPin = pin
                camera = .region(.init(center: pin.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))
                // Selecting the same result after a pan is a fresh camera request.
                cameraRequestID &+= 1
            }.presentationDetents([.large]).modifier(LivePlaceSheetMaterial())
        }
        .sheet(item: $selected, onDismiss: finishPlaceDismissal) { pin in
            placeCard(pin)
                .presentationDetents([.fraction(0.58), .large])
                .presentationDragIndicator(.visible)
                .modifier(LivePlaceSheetMaterial())
        }
        .onChange(of: selected?.id) { _, _ in saveError = nil }
        .sheet(isPresented: $teamPresented) { teamSheet.presentationDetents([.large]).modifier(LivePlaceSheetMaterial()) }
    }

    private func mapPage(height: CGFloat) -> some View {
        ZStack {
            if usesFixtureMap {
                realMap
            } else if pocketMapFailed {
                VStack(spacing: 12) {
                    Text(copy("Couldn't load Pocket City", "Pocket City 載入失敗"))
                    Button(copy("Try again", "重試")) { pocketMapFailed = false }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("live.map.retry")
                }
                .padding(24)
                .background(DateTheme.canvas)
            } else {
                pocketMap.ignoresSafeArea()
            }
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                if destination == .map && !atlasSheetOpen {
                    HStack {
                        Spacer()
                        mapControls
                    }
                }
                if showsFriends && !atlasSheetOpen {
                    outingPanel.frame(maxHeight: (groupPlaces.isEmpty && !canShowPlan)
                                      ? min(240, height * 0.35)
                                      : (canShowPlan ? min(height * 0.64, max(0, height - 260))
                                                     : height * 0.51))
                        .padding(18)
                        .background { LiveMapPanelGlass() }

                }
            }
            .padding(.horizontal, 24).padding(.top, 64).padding(.bottom, 82)
            if destination == .map, let detail = atlasDrawer.detail {
                LiveAtlasPlaceDrawer(detail: detail, drawer: atlasDrawer, currentSession: currentSession, maxHeight: min(height * 0.56, 530))
                    .padding(.horizontal, 12).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: atlasDrawer.detail != nil)
    }

    private var pageSwipe: some Gesture {
        DragGesture(minimumDistance: 28).onEnded { value in
            let horizontal = value.translation.width
            guard abs(horizontal) > abs(value.translation.height) * 1.5, abs(horizontal) > 55 else { return }
            let next: DemoDestination
            switch destination {
            case .saved where horizontal < 0: next = .map
            case .map where horizontal > 0: next = .saved
            default: return
            }
            navigate(to: next)
        }
    }

    private var mapCanSelect: Bool {
        isMounted && scenePhase == .active && destination == .map && !searchPresented && !teamPresented && selected == nil
    }

    private func suspendPlanning() {
        lifecycleRevision &+= 1
        guideAccess.invalidate()
        planOperation?.cancel(); plan.suspendForNavigation(); outing.suspendForNavigation()
        discovery.clear()
        selected = nil; pendingSavedDetail = nil
        pendingGuideDestination = nil; guideListToOpen = nil
    }

    private func performOutingAction(_ action: @escaping @MainActor () async -> Void,
                                    after: (@MainActor () -> Void)? = nil) {
        let ticket = lifecycleRevision
        Task {
            guard ticket == lifecycleRevision, shouldRefreshOuting, sessionIsCurrent, !Task.isCancelled else { return }
            await action()
            guard ticket == lifecycleRevision, shouldRefreshOuting, sessionIsCurrent, !Task.isCancelled else { return }
            if outing.selectedListID == nil && !outing.isLoading && !outing.isWorking { plan.cancel() }
            after?()
        }
    }

    private func reconcilePlan() {
        guard shouldRefreshOuting, sessionIsCurrent else { return }
        if stopSelectionListID != outing.selectedListID {
            selectedStops = []; stopSelectionListID = outing.selectedListID
        }
        selectedStops = selectedStops.filter { id in groupPlaces.contains { $0.id == id } }
        guideAccess.reconcile(plan: plan, outing: outing, places: groupPlaces)
    }

    private var pocketMap: some View {
        let keys = savedVenueKeys
        var presentation = mapPresentation
        presentation.showsPublicPins = !savedOnly
        return PocketCitySurface(pins: pins.map { pin in
            let kind: PocketCityPin.Kind
            switch pin.origin {
            case .publicPost: kind = .post
            case .saved: kind = pin.place.status == .visited ? .visited : .saved
            case .search: kind = .search
            case .shared: kind = .shared
            }
            let key = LivePublicDiscoveryVenueKey(savedPlace: pin.place)
            let owned = pin.origin == .saved || key.map(keys.contains) == true
            let label = pin.origin == .shared && owned
                ? "\(pin.sourceLabel) · \(copy("Saved", "已收藏"))"
                : (owned ? copy("Saved", "已收藏") : pin.sourceLabel)
            return PocketCityPin(id: pin.id, name: pin.place.name,
                                 label: "\(pin.place.name) · \(label) · \(pin.place.address)",
                                 latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude,
                                 kind: kind, selected: selected?.id == pin.id, isSaved: owned,
                                 publicVenueID: pin.origin == .publicPost ? pin.id : key.map { "public:\($0.provider):\($0.id)" },
                                 category: pin.place.category.rawValue, address: pin.place.address)
        }, viewport: PocketCityViewport(camera.region, requestID: cameraRequestID),
           routes: canShowPlan ? plan.routes.compactMap { PocketCityRoute($0.polyline) } : [],
           presentation: presentation, creditsRequest: creditsRequest, pageVisible: destination == .map,
           onPlaceSheet: { open in
               if destination == .map && sessionIsCurrent { atlasSheetOpen = open }
           }, placeDrawer: atlasDrawer, allowsRemoteTiles: false, onSelect: { id in
            if let pin = pins.first(where: { $0.id == id }) { selectMapPin(pin) }
        }, onMove: { region in
            if sessionIsCurrent && destination == .map { searchRegion = region }
        }, onFailure: {
            camera = .region(searchRegion)
            pocketMapFailed = true
        })
        .id([ownerSubject, String(sessionGeneration)])
        .accessibilityIdentifier("live.map")
    }

    private func selectMapPin(_ pin: LiveMapPlace) {
        guard sessionIsCurrent, mapCanSelect else { return }
        // Preserve the public post or the friend's sharing context when its
        // branch is also in the owner's collection.
        let resolved = pin.origin == .search ? (pin.existingSavedProjection(in: mapVM.places) ?? pin) : pin
        if resolved.origin == .search { searchPin = resolved }
        selected = resolved
    }

    private var realMap: some View {
        LiveInteractiveMapSurface(
            position: $camera, pins: pins, routes: canShowPlan ? plan.routes : [], isInteractive: mapCanSelect,
            activePinID: selected?.id, friends: showsFriends ? friendEntries : [],
            publicVenues: !savedOnly ? (discovery.page?.venues ?? []) : [],
            ownerSubject: ownerSubject, sessionGeneration: sessionGeneration,
            onSelect: selectMapPin,
            onCameraSettled: { _, region in searchRegion = region }
        ).ignoresSafeArea().accessibilityIdentifier("live.map")
    }

    private var rootHeader: some View {
        LiveFloatingGlassGroup {
            HStack(alignment: .center, spacing: 12) {
                if destination == .passport {
                    Button { navigate(to: previousRootDestination) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .liveFloatingGlass(in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel(copy("Back", "返回"))
                        .accessibilityIdentifier("live.passport.back")
                    Spacer(minLength: 8)
                    Text("Passport").font(.headline)
                    Spacer(minLength: 8)
                    Button(action: onOpenAccount) {
                        Image(systemName: "gearshape").frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .liveFloatingGlass(in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel(copy("Account settings", "帳號設定"))
                } else {
                    Button { navigate(to: .passport) } label: {
                        Image(systemName: "person.crop.circle").font(.title3)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .liveFloatingGlass(in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Passport")
                        .accessibilityIdentifier("demo.tab.passport")
                    HStack(spacing: 8) {
                        rootButton(.saved, title: copy("Saved", "收藏"))
                        rootButton(.map, title: copy("Map", "地圖"))
                    }
                    Spacer(minLength: 0)
                    if destination == .map, !usesFixtureMap {
                        LiveMapWeatherCard(area: weatherArea,
                                           forecast: appliedWeatherArea == weatherArea ? mapForecast : nil)
                            .id(weatherArea)
                    }
                }
            }.padding(.horizontal, 4).frame(minHeight: 44)
                .padding(.vertical, 4)
        }
    }

    private func navigate(to value: DemoDestination) {
        guard destination != value else { return }
        let switchesTabs = destination != .passport && value != .passport
        let pageAnimation: Animation? = switchesTabs && !reduceMotion ? .easeInOut(duration: 0.24) : nil
        withAnimation(pageAnimation) { destination = value }
    }

    private func rootButton(_ value: DemoDestination, title: String) -> some View {
        let selected = destination == value
        let isDark = colorScheme == .dark
        let fill = isDark ? SaveBrandUI.darkTabFill : DateTheme.action
        let ink = isDark ? DateTheme.ink : DateTheme.actionInk
        return Button { navigate(to: value) } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 10 : 16)
                .frame(minWidth: 44, minHeight: 45)
                .foregroundStyle(selected ? ink : DateTheme.muted)
                .background(selected ? fill : DateTheme.surface, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(DateTheme.ink.opacity(selected ? 0.12 : 0.07))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("demo.tab.\(value.key)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: selected)
    }

    private var layerControl: some View {
        Menu {
            Toggle(isOn: $showsFriends) {
                Label(copy("Friends", "朋友"), systemImage: "person.2.fill")
            }.accessibilityIdentifier("live.mode.group")
            Toggle(isOn: $savedOnly) {
                Label(copy("Saved only", "只看收藏"), systemImage: "bookmark.fill")
            }.accessibilityIdentifier("live.mode.personal")
            if !usesFixtureMap {
                Divider()
                Toggle(isOn: $mapPresentation.metro) {
                    Label(copy("Taipei Metro", "台北捷運"), systemImage: "tram.fill")
                }
                .accessibilityIdentifier("live.map.metro")
                .disabled(pocketMapFailed)
                Button {
                    creditsRequest &+= 1
                } label: {
                    Label(copy("Map credits", "圖資來源"), systemImage: "info.circle")
                }
                .accessibilityIdentifier("live.map.credits")
                .disabled(pocketMapFailed)
            }
            if !savedOnly {
                if discovery.unavailable || discovery.paginationFailed {
                    Button(copy("Reload posts", "重新載入貼文")) { discoveryReload &+= 1 }
                } else if discovery.page?.nextCursor != nil {
                    Button(copy("More posts", "更多貼文")) { Task { await discovery.loadMore() } }
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(DateTheme.ink)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .liveFloatingGlass(in: Circle())
        }
        .accessibilityLabel(copy("Map layers", "地圖圖層"))
        .accessibilityValue([savedOnly ? copy("Saved only", "只看收藏") : copy("Explore", "探索"),
                             showsFriends ? copy("Friends", "朋友") : nil,
                             mapPresentation.metro ? copy("Taipei Metro", "台北捷運") : nil]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("live.map.layers")
        .menuOrder(.fixed)
    }

    private var mapControls: some View {
        LiveFloatingGlassGroup {
            VStack(spacing: 6) {
                layerControl
                LiveMapLocationControl(position: Binding(
                    get: { camera },
                    set: { position in
                        camera = position
                        cameraRequestID &+= 1
                    }
                ), ownerSubject: ownerSubject, sessionGeneration: sessionGeneration)
            }
        }
    }

    private var savedPage: some View {
        LivePlanningLibraryView(places: mapVM.places, isLoading: mapVM.isLoading, onOpen: { place in
            if let pin = LiveMapPlace.saved(place) { selected = pin }
            else { onOpenSaved(place) }
        }, onCapture: onCapture, reviewCandidates: mapVM.reviewCandidates,
            reviewBatchIDs: reviewInboxRequest?.candidateIDs,
            onOpenReview: { id in
                guard sessionIsCurrent else { return }
                onOpenReview(id)
            }, onClearReviewBatch: onClearReviewBatch, sharedQuery: $savedQuery)
    }

    private var passport: some View {
        LivePlanningPassportView(places: mapVM.places,
                                onOpenLibrary: { destination = .saved }, onOpenAccount: onOpenAccount)
    }

    private var outingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if canShowPlan {
                LiveGuidePanel(title: outing.selectedTitle, plan: plan,
                               onManage: { teamPresented = true }, onSelect: selectGuideStop)
            }
            else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(outing.selectedListID == nil ? copy("Plan together", "一起出遊") : outing.selectedTitle).font(.system(size: 21, weight: .bold))
                        Text(outing.selectedListID == nil ? copy("Choose a shared list and invite friends to add places.", "選擇共同清單，邀朋友一起加入地點。") : copy("\(outing.members.count) members · \(outing.items.count) places", "\(outing.members.count) 位實際加入成員 · \(outing.items.count) 個地點"))
                            .font(.system(size: 11)).foregroundStyle(DateTheme.muted)
                    }
                    Spacer()
                    Button { teamPresented = true } label: { Image(systemName: "person.badge.plus").frame(width: 44, height: 44) }
                        .accessibilityLabel(copy("Shared lists and members", "共同清單與成員")).accessibilityIdentifier("live.team")
                }
                if outing.selectedListID == nil {
                    HStack(spacing: 8) {
                        ForEach([false, true], id: \.self) { visitedOnly in
                            Button { friendsVisitedOnly = visitedOnly } label: {
                                Label(visitedOnly ? copy("Visited", "朋友去過") : copy("Shared", "朋友分享"),
                                      systemImage: visitedOnly ? "checkmark.seal" : "person.2")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(friendsVisitedOnly == visitedOnly ? DateTheme.actionInk : DateTheme.ink)
                                    .background(friendsVisitedOnly == visitedOnly ? DateTheme.action : DateTheme.soft,
                                                in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(friendsVisitedOnly == visitedOnly ? .isSelected : [])
                        }
                    }
                }
                if outing.isLoading || outing.isWorking { ProgressView(copy("Loading shared lists…", "連線共同清單…")) }
                if let error = outing.error {
                    Text(copy("Couldn’t complete this outing action. Try again.", error)).font(.caption).foregroundStyle(DateTheme.coral)
                    Button(copy("Try again", "重新載入")) { performOutingAction { await outing.refresh() } }.frame(minHeight: 44)
                }
                if let notice = outing.notice {
                    Text(copy("Your change was submitted. Reload the shared list to confirm it.", notice)).font(.caption).foregroundStyle(DateTheme.muted)
                    Button(copy("Reload shared list", "重新讀取共同清單")) { performOutingAction { await outing.refresh() } }
                        .disabled(outing.isLoading || outing.isWorking).frame(minHeight: 44)
                }
                if outing.selectedListID == nil, let error = outing.feedError {
                    Text(copy("Couldn’t load friends’ shared places. Try again later.", error)).font(.caption).foregroundStyle(DateTheme.muted)
                }
                if outing.unmappedItemCount + outing.items.count - groupPlaces.count > 0 {
                    Text(copy("\(outing.unmappedItemCount + outing.items.count - groupPlaces.count) places have no supported map coordinates and remain in the list.", "\(outing.unmappedItemCount + outing.items.count - groupPlaces.count) 筆地點尚無可顯示的座標，仍保留於共同清單。"))
                        .font(.caption).foregroundStyle(DateTheme.muted)
                }
                if let error = plan.error { Text(copy("Apple Maps couldn’t find walking routes. Try again or open directions.", error)).font(.caption).foregroundStyle(DateTheme.coral) }
                if plan.isLoading { ProgressView(copy("Finding walking routes…", "向 Apple Maps 查詢步行路線…")) }
                ScrollView {
                    VStack(spacing: 8) {
                        if outing.selectedListID == nil {
                            ForEach(friendEntries) { friend in
                                Button { selected = friend.pin } label: { venueRow(name: friend.pin.place.name, address: friend.pin.place.address, symbol: friend.pin.place.category.iconName, suffix: friend.statusTitle(language.language)) }
                                    .buttonStyle(.plain)
                            }
                            if friendPlaces.isEmpty, !outing.isLoading {
                                Text(friendsVisitedOnly ? copy("No shared visited places yet.", "還沒有朋友分享去過的地點。") : copy("No shared places yet. Create a list or join with an invite code.", "還沒有可顯示的朋友分享。可先建立共同清單。"))
                                    .font(.subheadline).foregroundStyle(DateTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            ForEach(groupPlaces) { pin in
                                HStack {
                                    Button { selected = pin } label: { venueRow(name: pin.place.name, address: pin.place.address, symbol: pin.place.category.iconName, suffix: copy("Group candidate", "隊伍候選")) }
                                        .buttonStyle(.plain)
                                    Button { toggleStop(pin.id) } label: {
                                        Image(systemName: selectedStops.contains(pin.id) ? "checkmark.circle.fill" : "plus.circle")
                                            .font(.system(size: 25)).frame(width: 44, height: 48)
                                    }.buttonStyle(.plain).foregroundStyle(DateTheme.coral).disabled(plan.isLoading)
                                }
                            }
                            if groupPlaces.isEmpty { Text(copy("Add places from your collection or search to start planning.", "這份清單還沒有可放上地圖的地點。可從個人收藏或搜尋結果明確加入。"))
                                .font(.subheadline).foregroundStyle(DateTheme.muted) }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            if plan.stops.isEmpty && !outing.isLoading && !outing.isWorking {
                DemoPrimaryButton(title: selectedStops.isEmpty ? copy("Choose places · up to 6 stops", "選擇出遊地點 · 最多 6 站") : copy("Plan route · \(selectedStops.count) stops", "Guide 排路線 · \(selectedStops.count) 站"),
                                  enabled: selectedStops.count >= 2 && !plan.isLoading) {
                    guard let listID = outing.selectedListID else { return }
                    let values = selectedStops.compactMap { id in groupPlaces.first { $0.id == id } }
                    planOperation?.cancel()
                    planOperation = Task {
                        guard shouldRefreshOuting, !Task.isCancelled, sessionIsCurrent,
                              outing.selectedListID == listID else { return }
                        await plan.build(values, listID: listID)
                        guard shouldRefreshOuting, !Task.isCancelled, sessionIsCurrent else { return }
                        reconcilePlan()
                    }
                }
            }
        }
    }

    private func selectGuideStop(_ pin: LiveMapPlace) {
        guard canShowPlan, mapCanSelect else { return }
        selected = pin
    }

    private var dock: some View {
        let searchTitle = destination == .saved ? copy("Search Saved", "搜尋收藏") : copy("Search map", "搜尋地圖")
        return LiveFloatingGlassGroup {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    if destination == .saved {
                        Button { savedSearchFocused = true } label: {
                            Image(systemName: "magnifyingglass").font(.system(size: 20))
                        }.buttonStyle(.plain).accessibilityHidden(true)
                        TextField(searchTitle, text: $savedQuery)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($savedSearchFocused).submitLabel(.search)
                            .accessibilityIdentifier("live.library.search")
                        if !savedQuery.isEmpty {
                            Button {
                                savedQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(copy("Clear search", "清除搜尋"))
                        }
                    } else {
                        Button { searchPresented = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass").font(.system(size: 20)).accessibilityHidden(true)
                                Text(searchTitle).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("live.search")
                    }
                }
                .font(.subheadline).foregroundStyle(DateTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .padding(.horizontal, 18).contentShape(Capsule()).liveFloatingGlass(in: Capsule())
                Button(action: onCapture) {
                    Image(systemName: "plus").font(.title2.weight(.medium))
                        .frame(width: 62, height: 62)
                        .foregroundStyle(DateTheme.actionInk).contentShape(Circle())
                        .liveFloatingGlass(in: Circle(), prominent: true)
                }.buttonStyle(.plain).accessibilityLabel(copy("Add clue", "新增線索"))
                    .accessibilityIdentifier("live.library.add")
            }
        }
    }

    @ViewBuilder private func placeCard(_ pin: LiveMapPlace) -> some View {
        let key = LivePublicDiscoveryVenueKey(savedPlace: pin.place)
        let owned = pin.origin == .saved ? pin.place : key.flatMap { key in
            mapVM.places.first { LivePublicDiscoveryVenueKey(savedPlace: $0) == key }
        }
        if pin.origin == .publicPost,
           let venue = discovery.page?.venues.first(where: { "public:\($0.id)" == pin.id }) {
            LivePublicDiscoveryDetail(venue: venue, ownerSubject: ownerSubject, sessionGeneration: sessionGeneration,
                alreadySaved: owned != nil,
                isSaving: savingPinID != nil, saveError: saveError,
                onSave: { save(pin) }, onDirections: {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
                    item.name = pin.place.name
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                }, onClose: { selected = nil }, discoveryExpiresAt: discovery.page?.expiresAt,
                onGuideDestination: { target in
                    guard sessionIsCurrent, scenePhase == .active else { return }
                    pendingGuideDestination = target
                    selected = nil
                }, canReadPost: { post in
                    guard sessionIsCurrent, scenePhase == .active,
                          selected?.id == pin.id, let page = discovery.page,
                          Date() < page.expiresAt else { return false }
                    return page.venues.first(where: { $0.id == venue.id })?.posts.contains(post) == true
                })
        } else if pin.origin != .publicPost {
          LivePlaceDetail(
            pin: pin, isSaving: savingPinID != nil, saveError: saveError,
            ownerSubject: ownerSubject, sessionGeneration: sessionGeneration,
            onSave: owned != nil || pin.confirmationCandidate == nil ? nil : { save(pin) },
            onOpenSaved: owned.map { savedPlace in
                {
                    pendingSavedDetail = savedPlace.id
                    selected = nil
                }
            },
            onShowPocketCity: {
                guard sessionIsCurrent else { return }
                selected = nil
                if pin.origin == .search { searchPin = pin }
                destination = .map
                camera = .region(.init(center: pin.coordinate, span: .init(latitudeDelta: 0.008, longitudeDelta: 0.010)))
                cameraRequestID &+= 1
            },
            onDirections: {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
                item.name = pin.place.name
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
            },
            onAddToOuting: showsFriends && outing.selectedListID != nil ? {
                performOutingAction({ await outing.add(pin.listPayload) }, after: { selected = nil })
            } : nil,
            canAddToOuting: outing.canEditSelected && !outing.isWorking,
            onClose: { selected = nil }
        )
        }
    }

    private func save(_ pin: LiveMapPlace) {
        guard sessionIsCurrent, savingPinID == nil,
              let candidate = pin.confirmationCandidate else { return }
        savingPinID = pin.id; saveError = nil
        saveOperation = Task { @MainActor in
            defer { savingPinID = nil; saveOperation = nil }
            do {
                try Task.checkCancellation()
                guard sessionIsCurrent else { throw ReviewCandidateError.signInRequired }
                let place = try await LiveMapConfirmation.save(candidate, using: mapVM,
                    ownerSubject: ownerSubject, sessionGeneration: sessionGeneration)
                guard !Task.isCancelled, sessionIsCurrent, selected?.id == pin.id else { return }
                searchPin = nil
                var projection = LiveMapPlace.saved(place)
                projection?.nativeMapItem = pin.nativeMapItem
                selected = projection
            } catch {
                guard !Task.isCancelled, sessionIsCurrent, selected?.id == pin.id else { return }
                if case ReviewCandidateError.alreadySavedMapStamp = error,
                   let existing = pin.existingSavedProjection(in: mapVM.places) {
                    searchPin = nil
                    selected = existing
                } else {
                    saveError = error.localizedDescription
                }
            }
        }
    }

    private func finishPlaceDismissal() {
        if let target = pendingGuideDestination {
            pendingGuideDestination = nil
            guard sessionIsCurrent, scenePhase == .active else { return }
            destination = .map
            switch target {
            case .list(let id): guideListToOpen = id
            case .manageLists: teamPresented = true
            }
            savedOnly = false
            if showsFriends, let id = guideListToOpen {
                guideListToOpen = nil
                performOutingAction { await outing.selectList(id) }
            }
            showsFriends = true
            return
        }
        guard let id = pendingSavedDetail else { return }
        pendingSavedDetail = nil
        guard sessionIsCurrent, scenePhase == .active,
              let place = mapVM.places.first(where: { $0.id == id }) else { return }
        onOpenSaved(place)
    }

    private var teamSheet: some View {
        NavigationStack {
            Form {
                Section(copy("Shared lists", "共同清單")) {
                    ForEach(outing.lists) { list in
                        Button {
                            teamPresented = false
                            performOutingAction { await outing.selectList(list.id) }
                        } label: { HStack { Text(list.title); Spacer(); Text(copy("\(list.itemCount) places", "\(list.itemCount) 個地點")).foregroundStyle(.secondary) } }
                    }
                    if outing.isLoading { ProgressView() }
                    if let error = outing.error { Text(copy("Couldn’t complete this outing action. Try again.", error)).foregroundStyle(DateTheme.coral) }
                    if let notice = outing.notice { Text(copy("Your change was submitted. Reload the shared list to confirm it.", notice)).foregroundStyle(.secondary) }
                    if outing.error != nil || outing.notice != nil {
                        Button(copy("Reload shared list", "重新讀取共同清單")) { performOutingAction { await outing.refresh() } }
                            .disabled(outing.isLoading || outing.isWorking)
                    }
                }.listRowBackground(DateTheme.ink.opacity(0.04))
                if outing.selectedListID != nil {
                    Section(copy("Members", "已加入成員")) {
                        ForEach(outing.members) { member in
                            Label(member.displayName, systemImage: member.role == .owner ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        }
                        if outing.canInviteSelected {
                            Button(copy("Create an invite", "產生共同加店邀請")) { performOutingAction { await outing.makeInvite() } }.disabled(outing.isWorking)
                        }
                        if let url = outing.shareURL { ShareLink(copy("Share invite link", "分享邀請連結"), item: url) }
                    }.listRowBackground(DateTheme.ink.opacity(0.04))
                }
                Section(copy("Create a shared list", "建立新的出遊清單")) {
                    TextField(copy("For example: Saturday afternoon", "例如：週六下午"), text: $newListTitle)
                    Button(copy("Create list", "建立清單")) { performOutingAction { await outing.createList(title: newListTitle) } }
                        .disabled(newListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || outing.isWorking)
                }.listRowBackground(DateTheme.ink.opacity(0.04))
                Section(copy("Join with an invite code", "用朋友給的邀請碼加入")) {
                    TextField(copy("Invite code", "邀請碼"), text: $joinCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(copy("Join list", "加入清單")) { performOutingAction { await outing.join(code: joinCode) } }
                        .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || outing.isWorking)
                }.listRowBackground(DateTheme.ink.opacity(0.04))
                Text(copy("Places sync to the shared list. You arrange this route; it does not cast votes for friends.", "共同清單會同步地點；此版本由你安排路線，不會代替朋友投票。"))
                    .font(.caption).foregroundStyle(.secondary)
            }.scrollContentBackground(.hidden)
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationTitle(copy("Plan together", "一起出遊")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(copy("Done", "完成")) { teamPresented = false } } }
        }.tint(DateTheme.blue).foregroundStyle(DateTheme.ink)
    }

    private func venueRow(name: String, address: String, symbol: String, suffix: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 21)).frame(width: 42, height: 42)
                .background(DateTheme.soft, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(address).font(.system(size: 11)).foregroundStyle(DateTheme.muted).lineLimit(2)
                Text(suffix).font(.system(size: 10)).foregroundStyle(DateTheme.muted)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(10).background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 17))
    }

    private func copy(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
    private func sourceTitle(_ pin: LiveMapPlace) -> String {
        switch pin.origin {
        case .saved: copy("Saved", "已收藏")
        case .search: copy("Search result · not saved", "搜尋結果候選")
        case .shared: pin.sourceLabel == "朋友已分享" ? copy("Shared by friends", "朋友已分享") : copy("Group candidate", "隊伍候選")
        case .publicPost: copy("Public post · not saved", "公開貼文 · 尚未收藏")
        }
    }

    private func toggleStop(_ id: String) {
        guard !plan.started, !plan.isLoading else { return }
        if selectedStops.contains(id) { selectedStops.removeAll { $0 == id } }
        else if selectedStops.count < 6 { selectedStops.append(id) }
    }

}

@MainActor
struct LiveGuidePanel: View {
    let title: String
    @ObservedObject var plan: LiveRoutePlan
    let onManage: () -> Void
    let onSelect: (LiveMapPlace) -> Void
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Button(action: onManage) {
                    Image(systemName: "person.2").frame(width: 44, height: 44)
                }.buttonStyle(.plain)
                    .accessibilityLabel(language.localized(english: "Shared lists and members", traditionalChinese: "共同清單與成員"))
                    .accessibilityIdentifier("live.team")
            }
            LiveGuideTimeline(plan: plan, onSelect: onSelect)
        }
    }
}

@MainActor
struct LiveGuideTimeline: View {
    @ObservedObject var plan: LiveRoutePlan
    let onSelect: (LiveMapPlace) -> Void
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SAV-E GUIDE").font(.caption.weight(.bold)).tracking(1)
                Spacer()
                if !plan.started {
                    DatePicker(copy("Departure", "出發"), selection: $plan.beginsAt, displayedComponents: .hourAndMinute)
                        .labelsHidden().accessibilityLabel(copy("Departure time", "出發時間"))
                    Button(copy("Replan", "重排")) { plan.cancel() }.frame(minHeight: 44)
                } else {
                    Text(copy("\(min(plan.currentIndex + 1, plan.stops.count)) of \(plan.stops.count)",
                              "第 \(min(plan.currentIndex + 1, plan.stops.count))／\(plan.stops.count) 站"))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(DateTheme.blue)
                }
            }
            Text(copy("Walking routes · \(plan.dwellMinutes) min at each place · budget unconfirmed",
                      "步行路線 · 每站預留 \(plan.dwellMinutes) 分 · 預算待確認"))
                .font(.caption).foregroundStyle(DateTheme.muted).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(plan.stops.enumerated()), id: \.element.id) { index, pin in
                        Button { onSelect(pin) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 6) {
                                    Text(plan.arrival(at: index), style: .time).font(.caption.weight(.semibold))
                                    ZStack {
                                        Circle().fill(plan.started && index == plan.currentIndex ? DateTheme.action : DateTheme.soft)
                                        if plan.started && index < plan.currentIndex { Image(systemName: "checkmark") }
                                        else { Text("\(index + 1)") }
                                    }
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(plan.started && index == plan.currentIndex ? DateTheme.actionInk : DateTheme.blue)
                                    .frame(width: 28, height: 28)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pin.place.name).font(.subheadline.weight(.semibold)).foregroundStyle(DateTheme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(pin.place.address).font(.caption).foregroundStyle(DateTheme.muted).lineLimit(2)
                                    if index > 0, plan.routes.indices.contains(index - 1) {
                                        Label(copy("About \(Int(ceil(plan.routes[index - 1].expectedTravelTime / 60))) min walk",
                                                   "步行約 \(Int(ceil(plan.routes[index - 1].expectedTravelTime / 60))) 分鐘"), systemImage: "figure.walk")
                                            .font(.caption).foregroundStyle(DateTheme.muted)
                                    }
                                    if plan.started && index == plan.currentIndex {
                                        Text(copy("Current stop", "目前這站")).font(.caption.weight(.semibold)).foregroundStyle(DateTheme.blue)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(DateTheme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(DateTheme.blue.opacity(plan.started && index == plan.currentIndex ? 0.6 : 0.08)))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!plan.isAccessValidated)
                    }
                }
            }.scrollIndicators(.hidden)
            if !plan.started {
                DemoPrimaryButton(title: copy("Start this outing", "開始照行程走"), enabled: plan.isAccessValidated) { plan.start() }
            } else if plan.stops.indices.contains(plan.currentIndex) {
                DemoPrimaryButton(title: copy("Finish stop · \(plan.stops[plan.currentIndex].place.name)",
                                              "完成這站 · \(plan.stops[plan.currentIndex].place.name)"), enabled: plan.isAccessValidated) { plan.advance() }
            } else {
                Label(copy("Outing complete", "這次行程已走完"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(DateTheme.blue)
            }
            Text(copy("Progress is manual. Your visited places stay unchanged.", "手動記錄這次進度，不會更改地點的去過紀錄。"))
                .font(.caption).foregroundStyle(DateTheme.muted).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(DateTheme.ink)
    }

    private func copy(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

@MainActor
private struct LiveMapSearch: View {
    let region: MKCoordinateRegion
    let onPick: (LiveMapPlace) -> Void
    @State private var query = ""
    @State private var values: [LiveMapPlace] = []
    @State private var searching = false
    @State private var error: String?
    @State private var request: MKLocalSearch?
    @State private var operation: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var language
    var body: some View {
        NavigationStack {
            List {
                if searching { ProgressView(copy("Searching…", "搜尋中…")).listRowBackground(DateTheme.ink.opacity(0.04)) }
                if let error { Text(error).foregroundStyle(DateTheme.muted).listRowBackground(DateTheme.ink.opacity(0.04)) }
                ForEach(values) { pin in
                    Button { onPick(pin); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(pin.place.name).font(.headline)
                            Text(pin.place.address).font(.caption).foregroundStyle(.secondary)
                            Text(copy("View on map · not saved", "在地圖查看 · 尚未收藏")).font(.caption2)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7).contentShape(Rectangle())
                    }.buttonStyle(.plain).listRowBackground(DateTheme.ink.opacity(0.04))
                }
            }.scrollContentBackground(.hidden)
                .toolbarBackground(.hidden, for: .navigationBar)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: copy("Search places, restaurants or addresses", "搜尋地點、餐廳或地址"))
                .onSubmit(of: .search, search)
                .navigationTitle(copy("Search map", "搜尋地圖")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(copy("Done", "完成")) { dismiss() } } }
        }.tint(DateTheme.blue).foregroundStyle(DateTheme.ink)
            .onDisappear { operation?.cancel(); request?.cancel() }
    }
    private func copy(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
    private func search() {
        operation?.cancel(); request?.cancel(); values = []; error = nil; searching = false
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let input = MKLocalSearch.Request(); input.naturalLanguageQuery = text; input.region = region
        let search = MKLocalSearch(request: input); request = search; searching = true
        operation = Task {
            defer { if !Task.isCancelled { searching = false } }
            do {
                let response = try await search.start()
                guard !Task.isCancelled else { return }
                values = response.mapItems.compactMap(LiveMapPlace.search)
                if values.isEmpty { error = copy("No matching places. Try another name or address.", "沒有找到對應地點，可換個店名或地址。") }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = copy("Search is unavailable right now. Try again.", "目前無法完成搜尋，請稍後重試。")
            }
        }
    }
}
/// One material entry for floating chrome; reading content keeps its opaque surfaces.
/// Leave system sheets on their native Liquid Glass on iOS 26; older
/// systems use an adaptive native material with an opaque accessible fallback.
private struct LivePlaceSheetMaterial: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency { content.presentationBackground(DateTheme.surface) }
        else if #available(iOS 26.0, *) { content }
        else { content.presentationBackground(.regularMaterial) }
    }
}

private struct LiveMapWeatherCard: View {
    let area: PocketCityForecast.Area?
    let forecast: PocketCityForecast.Result?
    @Environment(\.appLanguageSettings) private var language
    @State private var showsForecast = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            let reading = forecast?.current(at: context.date)
            Button { showsForecast = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: reading.map(symbol) ?? "cloud")
                    Text(reading?.celsius.map(degrees) ?? "—")
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
                .liveFloatingGlass(in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(reading?.celsius == nil)
            .accessibilityLabel(copy("Weather", "天氣"))
            .accessibilityValue(reading?.celsius.map(degrees) ?? copy("Unavailable", "暫無資料"))
            .accessibilityHint(copy("Shows the hourly forecast", "查看逐小時預報"))
            .accessibilityIdentifier("live.map.weather")
            .popover(isPresented: $showsForecast, arrowEdge: .top) {
                hourlyForecast(at: context.date)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func hourlyForecast(at now: Date) -> some View {
        let taipeiZone = area.flatMap { value in
            (249...253).contains(value.latitudeTenths) && (1213...1218).contains(value.longitudeTenths)
                ? TimeZone(identifier: "Asia/Taipei") : nil
        }
        let format = Date.FormatStyle(locale: language.locale, timeZone: taipeiZone ?? .autoupdatingCurrent)
            .hour().minute()
        return VStack(alignment: .leading, spacing: 8) {
            Text(copy("Hourly forecast", "逐小時預報")).font(.headline)
            Text(taipeiZone == nil ? copy("Device time", "裝置時間") : copy("Taipei time", "台北時間"))
                .font(.caption).foregroundStyle(DateTheme.muted)
            ForEach(forecast?.upcoming(at: now) ?? []) { hour in
                HStack {
                    Text(hour.time.formatted(format))
                    Spacer()
                    Image(systemName: symbol(hour))
                    Text(hour.celsius.map(degrees) ?? "—").monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            Link(copy("Data from MET Norway", "資料來源 MET Norway"),
                 destination: URL(string: "https://docs.api.met.no/doc/locationforecast/")!)
                .font(.caption)
        }
        .frame(idealWidth: 220)
        .padding(16)
    }

    private func symbol(_ reading: PocketCityForecast.Reading) -> String {
        if reading.symbol.contains("thunder") { return "cloud.bolt.rain.fill" }
        if reading.symbol.contains("snow") || reading.symbol.contains("sleet") { return "cloud.snow.fill" }
        if reading.symbol.contains("fog") { return "cloud.fog.fill" }
        if reading.symbol.hasPrefix("partlycloudy") {
            return reading.isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        }
        switch PocketCityForecast.weather(for: reading.symbol) {
        case .day: return reading.isNight ? "moon.stars.fill" : "sun.max.fill"
        case .rain: return "cloud.rain.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .cloudy: return "cloud.fill"
        default: return "cloud"
        }
    }

    private func degrees(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0))))°"
    }

    private func copy(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

private struct LiveMapPanelGlass: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if reduceTransparency { shape.fill(DateTheme.surface) }
        else if #available(iOS 26.0, *) { Color.clear.glassEffect(.regular, in: shape) }
        else { shape.fill(.regularMaterial) }
    }
}

@MainActor
private struct LiveAtlasPlaceDrawer: View {
    let detail: PocketCityPlaceDetail
    let drawer: PocketCityPlaceDrawer
    let currentSession: @MainActor () -> Bool
    let maxHeight: CGFloat
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var drag: CGFloat = 0
    @AccessibilityFocusState private var headingFocused: Bool
    @State private var now = Date()
    @State private var enlargedPhoto = false
    @State private var headerHeight: CGFloat = 76
    @State private var bodyHeight: CGFloat = 0

    private struct CoverRequest: Equatable {
        let serial: Int
        let post: PocketCityPlaceDetail.Post
    }
    private struct PhotoDisplay {
        let image: UIImage
        let alternative: String
        let credit: String
        let original: URL
        let source: CoverRequest?
    }
    @State private var loadedCover: (request: CoverRequest, image: UIImage)?
    private var coverRequest: CoverRequest? {
        guard scenePhase == .active, currentSession(),
              let post = detail.posts.first(where: {
                  guard let cover = $0.cover, cover.expiresAt > now, $0.expiresAt > now else { return false }
                  return LivePublicDiscoveryCover.validatedURL(cover.url.absoluteString, platform: $0.platform.lowercased()) != nil
              }) else { return nil }
        return CoverRequest(serial: detail.serial, post: post)
    }
    private var photoDisplay: PhotoDisplay? {
        if let expected = coverRequest, let loadedCover, loadedCover.request == expected,
           expected.post.cover.map({ $0.expiresAt > Date() }) == true {
            let post = expected.post
            return PhotoDisplay(image: loadedCover.image, alternative: post.title.isEmpty ? detail.name : post.title,
                                credit: [post.platform, post.author].filter { !$0.isEmpty }.joined(separator: " · "),
                                original: post.url, source: expected)
        }
        guard let photo = detail.photo, let image = UIImage(contentsOfFile: photo.file.path) else { return nil }
        return PhotoDisplay(image: image, alternative: photo.alternative, credit: photo.credit,
                            original: photo.original, source: nil)
    }
    private func openOriginal(_ photo: PhotoDisplay) {
        guard scenePhase == .active, currentSession(), drawer.detail?.serial == detail.serial else { return }
        if let expected = photo.source {
            guard let current = drawer.detail?.posts.first(where: { $0 == expected.post }),
                  current.expiresAt > Date(), current.cover.map({ $0.expiresAt > Date() }) == true else { return }
        } else if drawer.detail?.photo?.original != photo.original { return }
        openURL(photo.original)
    }

    private func copy(_ en: String, _ zh: String) -> String {
        language.localized(english: en, traditionalChinese: zh)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 4) {
                Capsule().fill(.secondary.opacity(0.45)).frame(width: 34, height: 5)
                    .accessibilityHidden(true)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !detail.kind.isEmpty { Text(detail.kind).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                        Text(detail.name).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($headingFocused)
                    }
                    Spacer(minLength: 4)
                    Button { drawer.action("close", serial: detail.serial) } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(copy("Close place", "關閉地點"))
                    .accessibilityIdentifier("pocket.detail.close")
                }
            }
            .padding(.horizontal, 16).padding(.top, 9)
            .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { headerHeight = $0 }
            .contentShape(Rectangle()).simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .updating($drag) { value, state, _ in state = max(0, value.translation.height) }
                    .onEnded { value in
                        if value.translation.height > 45 || value.predictedEndTranslation.height > 95 {
                            drawer.action("close", serial: detail.serial)
                        }
                    })
            ScrollView {
                bodyContents
                    .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { bodyHeight = $0 }
            }
            .id(detail.serial)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(44, maxHeight - headerHeight), bodyHeight > 0 ? bodyHeight : 100))
        }
        .frame(maxWidth: 620, alignment: .leading)
        .foregroundStyle(DateTheme.ink).tint(DateTheme.blue)
        .background { LiveMapPanelGlass() }
        .clipShape(shape)
        .offset(y: min(80, drag))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pocket.detail.drawer")
        .accessibilityAction(.escape) { drawer.action("close", serial: detail.serial) }
        .task(id: detail.serial) {
            enlargedPhoto = false
            await Task.yield()
            headingFocused = true
        }
        .task(id: coverRequest) {
            loadedCover = nil
            guard let expected = coverRequest, let cover = expected.post.cover, cover.expiresAt > Date() else { return }
            do {
                let image = try await LivePublicPostCover.thumbnail(cover.url)
                guard !Task.isCancelled, scenePhase == .active, currentSession(), drawer.detail?.serial == expected.serial,
                      drawer.detail?.posts.contains(expected.post) == true, cover.expiresAt > Date() else { return }
                loadedCover = (expected, image)
            } catch { /* The branch photo remains visible when the permitted post image cannot load. */ }
        }
        .onChange(of: coverRequest) { _, _ in enlargedPhoto = false }
        .task(id: detail.posts) {
            now = Date()
            let deadlines = detail.posts.map(\.expiresAt) + detail.posts.compactMap { $0.cover?.expiresAt }
            for expiry in Set(deadlines).sorted() where expiry > now {
                do { try await Task.sleep(for: .seconds(max(0, expiry.timeIntervalSinceNow))) }
                catch { return }
                now = Date()
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
        .sheet(isPresented: $enlargedPhoto) {
            if let photo = photoDisplay {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(detail.name).font(.headline)
                        Spacer()
                        Button(copy("Done", "完成")) { enlargedPhoto = false }.frame(minHeight: 44)
                    }
                    Image(uiImage: photo.image).resizable().scaledToFit().accessibilityLabel(photo.alternative)
                    Button(photo.credit) { openOriginal(photo) }.font(.caption)
                }
                .padding().presentationDetents([.medium, .large]).modifier(LivePlaceSheetMaterial())
            }
        }
    }

    private var bodyContents: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !detail.address.isEmpty && detail.address != detail.kind {
                Text(detail.address).font(.subheadline).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }
                VStack(alignment: .leading, spacing: 0) { actions }
            }
            if let photo = photoDisplay {
                VStack(alignment: .leading, spacing: 4) {
                    Button { enlargedPhoto = true } label: {
                        Color.clear
                            .frame(height: min(140, maxHeight * 0.34))
                            .overlay { Image(uiImage: photo.image).resizable().scaledToFill() }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain).accessibilityLabel(photo.alternative)
                    .accessibilityHint(copy("Enlarge photo", "查看大圖"))
                    Button(photo.credit) { openOriginal(photo) }
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(detail.choices.enumerated()), id: \.offset) { index, title in
                Button { drawer.action("choice", serial: detail.serial, index: index) } label: {
                    Label(title, systemImage: "mappin").frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            ForEach(detail.posts.filter { $0.expiresAt > now }) { post in
                Button {
                    guard scenePhase == .active, let current = drawer.detail, current.serial == detail.serial,
                          current.posts.contains(where: { $0.url == post.url && $0.expiresAt > Date() }) else { return }
                    openURL(post.url)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            if !post.title.isEmpty { Text(post.title).font(.subheadline.weight(.medium)) }
                            Text([post.platform, post.author].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right").font(.caption)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 14)
    }

    @ViewBuilder private var actions: some View {
        if let directions = detail.directions {
            Link(destination: directions) { Label(copy("Directions", "導航"), systemImage: "arrow.turn.up.right") }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .accessibilityLabel(copy("Directions in Apple Maps", "用 Apple 地圖導航"))
        }
        if let label = detail.savedActionLabel {
            Button { drawer.action("saved", serial: detail.serial) } label: { Label(label, systemImage: "bookmark") }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
        if detail.friendAction {
            Button { drawer.action("friend", serial: detail.serial) } label: {
                Label(copy("Friends", "朋友"), systemImage: "person.2")
            }.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
        if let url = detail.website {
            Link(destination: url) {
                Label(detail.websiteLabel.isEmpty ? copy("Website", "網站") : detail.websiteLabel,
                      systemImage: "arrow.up.right")
            }.font(.subheadline).frame(minHeight: 44)
        }
    }
}

private struct LiveFloatingGlass<GlassShape: Shape>: ViewModifier {
    let shape: GlassShape
    let tint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(
                .regular.tint(tint).interactive(!reduceMotion),
                in: shape)
        } else {
            content
                .background(tint ?? DateTheme.soft, in: shape)
                .overlay(shape.stroke(DateTheme.ink.opacity(0.08), lineWidth: 1))
        }
    }
}

extension View {
    func liveFloatingGlass<GlassShape: Shape>(in shape: GlassShape, prominent: Bool = false) -> some View {
        modifier(LiveFloatingGlass(shape: shape, tint: prominent ? DateTheme.action : nil))
    }
}

/// Local clusters stay separate at rest: the merge threshold is below their 12pt gap.
struct LiveFloatingGlassGroup<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency, !reduceMotion {
            GlassEffectContainer(spacing: 6) { content }
        } else {
            content
        }
    }
}

#endif
