#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import SwiftUI
import MapKit

enum LiveMapMode: String, CaseIterable {
    case explore = "探索", outing = "朋友", personal = "我的"
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
    @StateObject private var outing: LiveOutingModel
    @StateObject private var plan: LiveRoutePlan
    @StateObject private var discovery: LivePublicDiscoveryModel
    @State private var destination = DemoDestination.map
    @State private var mode: LiveMapMode = .explore
    @State private var discoveryReload = 0
    @State private var camera = MapCameraPosition.region(MKCoordinateRegion(
        center: .init(latitude: 25.04, longitude: 121.54), span: .init(latitudeDelta: 0.07, longitudeDelta: 0.07)))
    @State private var searchRegion = MKCoordinateRegion(center: .init(latitude: 25.04, longitude: 121.54),
                                                       span: .init(latitudeDelta: 0.07, longitudeDelta: 0.07))
    @State private var didFitFriends = false
    @State private var friendsVisitedOnly = false
    @State private var didFitSaved = false
    @State private var searchPresented = false
    @State private var selected: LiveMapPlace?
    @State private var pendingSavedDetail: UUID?
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.scenePhase) private var scenePhase

    init(mapVM: MapViewModel, ownerSubject: String, sessionGeneration: Int,
         onOpenSaved: @escaping (Place) -> Void, onOpenAccount: @escaping () -> Void,
         onCapture: @escaping () -> Void) {
        self.mapVM = mapVM; self.ownerSubject = ownerSubject; self.sessionGeneration = sessionGeneration
        self.onOpenSaved = onOpenSaved; self.onOpenAccount = onOpenAccount; self.onCapture = onCapture
        _outing = StateObject(wrappedValue: LiveOutingModel(ownerSubject: ownerSubject, sessionGeneration: sessionGeneration))
        _plan = StateObject(wrappedValue: LiveRoutePlan(ownerSubject: ownerSubject, sessionGeneration: sessionGeneration))
        _discovery = StateObject(wrappedValue: LivePublicDiscoveryModel(ownerSubject: ownerSubject, sessionGeneration: sessionGeneration))
    }

    private var saved: [LiveMapPlace] { mapVM.places.compactMap(LiveMapPlace.saved) }
    private var groupPlaces: [LiveMapPlace] {
        guard let id = outing.selectedListID else { return [] }
        return outing.items.compactMap { LiveMapPlace.shared($0, listID: id) }
    }
    private var friendEntries: [LiveFriendMapPlace] {
        LiveFriendMapPlace.projections(posts: outing.posts)
            .filter { !friendsVisitedOnly || $0.hasVisited }
    }
    private var friendPlaces: [LiveMapPlace] { LiveFriendMapPlace.groupedByVenue(friendEntries).compactMap { $0.first?.pin } }
    private var pins: [LiveMapPlace] {
        let values: [LiveMapPlace]
        switch mode {
        case .personal: values = saved
        case .explore: values = discovery.page?.venues.compactMap(LiveMapPlace.discovery) ?? []
        case .outing: values = friendPlaces + groupPlaces.filter { groupPin in
                !friendPlaces.contains { $0.place.matches(groupPin.place) }
            }
        }
        return values + [searchPin].compactMap { $0 }.filter { pin in !values.contains(where: { $0.id == pin.id }) }
    }
    private var sessionIsCurrent: Bool {
        let auth = PrivyAuthService.shared
        guard case .authenticated = auth.authState else { return false }
        return auth.currentUserId == ownerSubject && auth.sessionGeneration == sessionGeneration
    }
    private var shouldRefreshOuting: Bool { isMounted && scenePhase == .active && mode == .outing }
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
        guard isMounted, scenePhase == .active, destination == .map, mode == .explore,
              let viewport = discoveryViewport else { return "inactive" }
        return "\(viewport.queryValue):\(discoveryReload)"
    }
    private var canShowPlan: Bool {
        shouldRefreshOuting && sessionIsCurrent && guideAccess.permits(plan: plan, outing: outing)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                realMap.opacity(destination == .map ? 1 : 0)
                    .allowsHitTesting(destination == .map).accessibilityHidden(destination != .map)
                if destination != .map { DateTheme.canvas.ignoresSafeArea() }
                VStack(spacing: 12) {
                    if destination != .map { header }
                    if destination == .map {
                        modeControl
                        Spacer(minLength: 0)
                        HStack {
                            Spacer()
                            LiveMapLocationControl(position: $camera, ownerSubject: ownerSubject,
                                                   sessionGeneration: sessionGeneration)
                        }
                        if mode == .outing {
                            outingPanel.frame(maxHeight: (groupPlaces.isEmpty && !canShowPlan)
                                              ? min(240, geometry.size.height * 0.35)
                                              : (canShowPlan
                                                 ? min(geometry.size.height * 0.64, max(0, geometry.size.height - 260))
                                                 : geometry.size.height * 0.51)).demoCard()
                        } else if mode == .explore {
                            LivePublicDiscoverySummary(model: discovery,
                                onRetry: { discoveryReload &+= 1 }, onMore: { Task { await discovery.loadMore() } }).demoCard()
                        } else {
                            personalSummary.demoCard()
                        }
                    } else if destination == .saved {
                        savedPage
                    } else {
                        passport
                    }
                    dock
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
            }.foregroundStyle(DateTheme.ink)
        }
        .onAppear {
            isMounted = true
            if ProcessInfo.processInfo.arguments.contains("--preview-tab-saved") { destination = .saved }
            if ProcessInfo.processInfo.arguments.contains("--preview-tab-passport")
                || ProcessInfo.processInfo.arguments.contains("--preview-account") { destination = .passport }
            fitSavedIfNeeded()
            if ProcessInfo.processInfo.arguments.contains("--map-mode-group") { mode = .outing }
            if ProcessInfo.processInfo.arguments.contains("--map-mode-personal") { mode = .personal }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--preview-account") {
                await Task.yield()
                guard !Task.isCancelled, sessionIsCurrent else { return }
                onOpenAccount()
            }
        }
        .onChange(of: saved.map(\.id)) { _, _ in fitSavedIfNeeded() }
        .onChange(of: mode) { _, next in
            lifecycleRevision &+= 1
            guideAccess.invalidate()
            selected = nil; pendingSavedDetail = nil; searchPin = nil; selectedStops = []; stopSelectionListID = nil
            planOperation?.cancel(); plan.cancel(); outing.deactivate()
            discovery.clear()
            if next == .outing { didFitFriends = false }
            if next == .personal { fitSavedIfNeeded() }
        }
        .onChange(of: outing.snapshotRevision) { _, _ in
            reconcilePlan()
            if selected?.origin == .shared { selected = nil }
            if !groupPlaces.isEmpty { fit(groupPlaces) }
        }
        .onChange(of: outing.error) { _, value in
            if value != nil, shouldRefreshOuting, outing.selectedListID == nil { plan.cancel() }
        }
        .onChange(of: outing.posts) { _, _ in
            if selected?.origin == .shared { selected = nil }
            if mode == .outing, !didFitFriends, !friendPlaces.isEmpty {
                didFitFriends = true
                if outing.selectedListID == nil { fit(friendPlaces) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { suspendPlanning() }
        }
        .onDisappear { isMounted = false; suspendPlanning(); saveOperation?.cancel() }
        .task(id: discoveryQuery) {
            guard discoveryQuery != "inactive", let viewport = discoveryViewport, sessionIsCurrent else {
                discovery.clear(); return
            }
            await discovery.refresh(viewport)
        }
        .onChange(of: discovery.page?.indexRevision) { _, _ in
            if selected?.origin == .publicPost { selected = nil }
        }
        .task(id: shouldRefreshOuting) {
            guard shouldRefreshOuting, !Task.isCancelled, sessionIsCurrent else { return }
            outing.resumeAfterNavigation()
            let previousSnapshot = outing.snapshotRevision
            await outing.refresh()
            guard !Task.isCancelled, shouldRefreshOuting, sessionIsCurrent else { return }
            if outing.snapshotRevision == previousSnapshot { plan.cancel(); selectedStops = [] }
        }
        .tint(DateTheme.blue)
        .sheet(isPresented: $searchPresented) {
            LiveMapSearch(region: searchRegion) { pin in
                guard sessionIsCurrent else { return }
                destination = .map
                searchPin = pin
                camera = .region(.init(center: pin.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))
            }.presentationDetents([.large]).presentationBackground(DateTheme.canvas)
        }
        .sheet(item: $selected, onDismiss: openPendingSavedDetail) { pin in
            placeCard(pin).presentationDetents([.fraction(0.58), .large]).presentationDragIndicator(.visible).presentationBackground(DateTheme.canvas)
        }
        .onChange(of: selected?.id) { _, _ in saveError = nil }
        .sheet(isPresented: $teamPresented) { teamSheet.presentationDetents([.large]).presentationBackground(DateTheme.canvas) }
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

    private var realMap: some View {
        LiveInteractiveMapSurface(
            position: $camera, pins: pins, routes: canShowPlan ? plan.routes : [], isInteractive: mapCanSelect,
            activePinID: selected?.id, friends: mode == .outing ? friendEntries : [],
            publicVenues: mode == .explore ? (discovery.page?.venues ?? []) : [],
            ownerSubject: ownerSubject, sessionGeneration: sessionGeneration,
            onSelect: { pin in
                guard sessionIsCurrent, mapCanSelect else { return }
                let resolved = pin.origin == .publicPost ? pin : (pin.existingSavedProjection(in: mapVM.places) ?? pin)
                if resolved.origin == .search { searchPin = resolved }
                selected = resolved
            },
            onCameraSettled: { _, region in searchRegion = region }
        ).ignoresSafeArea().accessibilityIdentifier("live.map")
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(destinationTitle).font(.title2.weight(.bold))
            Spacer()
            if destination == .saved {
                Text("\(mapVM.places.count)").font(.subheadline.weight(.semibold))
                    .foregroundStyle(DateTheme.muted)
            }
        }.padding(.horizontal, 4).frame(minHeight: 44)
    }

    private var modeControl: some View {
        HStack(spacing: 0) {
            ForEach(LiveMapMode.allCases, id: \.self) { value in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { mode = value }
                } label: {
                    Label(modeTitle(value), systemImage: value == .explore ? "globe.asia.australia" : (value == .personal ? "bookmark.fill" : "person.2.fill"))
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(mode == value ? DateTheme.ink : DateTheme.muted)
                        .background {
                            if mode == value {
                                Capsule().fill(DateTheme.surface)
                                    .shadow(color: DateTheme.blue.opacity(0.12), radius: 6, y: 2)
                            }
                        }
                }.buttonStyle(.plain).accessibilityIdentifier(value == .explore ? "live.mode.explore" : (value == .personal ? "live.mode.personal" : "live.mode.group"))
                    .accessibilityAddTraits(mode == value ? .isSelected : [])
            }
        }.padding(4).background(DateTheme.canvas.opacity(0.96), in: Capsule())
            .overlay(Capsule().stroke(DateTheme.ink.opacity(0.06)))
            .frame(maxWidth: 300).frame(maxWidth: .infinity)
    }

    private var personalSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { destination = .saved } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark.fill").foregroundStyle(DateTheme.blue)
                        .frame(width: 38, height: 38).background(DateTheme.soft, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(copy("My places", "我的收藏")).font(.subheadline.weight(.semibold))
                        Text(copy("\(mapVM.places.count) places", "\(mapVM.places.count) 個地方")).font(.caption).foregroundStyle(DateTheme.muted)
                    }
                    Spacer()
                    if mapVM.isLoading { ProgressView() }
                    else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DateTheme.muted) }
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !mapVM.isLoading, mapVM.places.isEmpty {
                Text(copy("Search for a place, or save one from a post.", "搜尋想去的地方，或從貼文加入收藏。")).font(.caption).foregroundStyle(DateTheme.muted)
            }
            if mapVM.places.count > saved.count {
                Text(copy("\(mapVM.places.count - saved.count) unlocated places remain in your collection", "\(mapVM.places.count - saved.count) 筆未定位，保留於收藏清單"))
                    .font(.caption).foregroundStyle(DateTheme.muted)
            }
        }
    }

    private var savedPage: some View {
        LivePlanningLibraryView(places: mapVM.places, isLoading: mapVM.isLoading, onOpen: { place in
            if let pin = LiveMapPlace.saved(place) { selected = pin }
            else { onOpenSaved(place) }
        }, onCapture: onCapture)
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
                    Text(copy("\(outing.unmappedItemCount + outing.items.count - groupPlaces.count) places have no supported map coordinates and remain in the list.", "\(outing.unmappedItemCount + outing.items.count - groupPlaces.count) 筆地點尚無可顯示的 Apple Maps 座標，仍保留於共同清單。"))
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
        HStack(spacing: 12) {
            Button { searchPresented = true } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 21, weight: .medium)).frame(width: 54, height: 54)
                    .background(DateTheme.surface, in: Circle()).shadow(color: .black.opacity(0.09), radius: 10, y: 4)
            }.buttonStyle(.plain).accessibilityLabel(copy("Search Apple Maps", "搜尋 Apple Maps")).accessibilityIdentifier("live.search")
            DemoDock(selection: $destination)
        }.padding(.horizontal, 12)
    }

    @ViewBuilder private func placeCard(_ pin: LiveMapPlace) -> some View {
        if pin.origin == .publicPost,
           let venue = discovery.page?.venues.first(where: { "public:\($0.id)" == pin.id }) {
            LivePublicDiscoveryDetail(venue: venue, ownerSubject: ownerSubject, sessionGeneration: sessionGeneration,
                alreadySaved: pin.existingSavedProjection(in: mapVM.places) != nil,
                isSaving: savingPinID != nil, saveError: saveError,
                onSave: { save(pin) }, onDirections: {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
                    item.name = pin.place.name
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                }, onClose: { selected = nil })
        } else if pin.origin != .publicPost {
          LivePlaceDetail(
            pin: pin, isSaving: savingPinID != nil, saveError: saveError,
            ownerSubject: ownerSubject, sessionGeneration: sessionGeneration,
            onSave: pin.confirmationCandidate == nil ? nil : { save(pin) },
            onOpenSaved: pin.origin == .saved ? {
                pendingSavedDetail = pin.place.id
                selected = nil
            } : nil,
            onDirections: {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
                item.name = pin.place.name
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
            },
            onAddToOuting: mode == .outing && outing.selectedListID != nil ? {
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

    private func openPendingSavedDetail() {
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
                }.listRowBackground(DateTheme.surface)
                if outing.selectedListID != nil {
                    Section(copy("Members", "已加入成員")) {
                        ForEach(outing.members) { member in
                            Label(member.displayName, systemImage: member.role == .owner ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        }
                        if outing.canInviteSelected {
                            Button(copy("Create an invite", "產生共同加店邀請")) { performOutingAction { await outing.makeInvite() } }.disabled(outing.isWorking)
                        }
                        if let url = outing.shareURL { ShareLink(copy("Share invite link", "分享邀請連結"), item: url) }
                    }.listRowBackground(DateTheme.surface)
                }
                Section(copy("Create a shared list", "建立新的出遊清單")) {
                    TextField(copy("For example: Saturday afternoon", "例如：週六下午"), text: $newListTitle)
                    Button(copy("Create list", "建立清單")) { performOutingAction { await outing.createList(title: newListTitle) } }
                        .disabled(newListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || outing.isWorking)
                }.listRowBackground(DateTheme.surface)
                Section(copy("Join with an invite code", "用朋友給的邀請碼加入")) {
                    TextField(copy("Invite code", "邀請碼"), text: $joinCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(copy("Join list", "加入清單")) { performOutingAction { await outing.join(code: joinCode) } }
                        .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || outing.isWorking)
                }.listRowBackground(DateTheme.surface)
                Text(copy("Places sync to the shared list. You arrange this route; it does not cast votes for friends.", "共同清單會同步地點；此版本由你安排路線，不會代替朋友投票。"))
                    .font(.caption).foregroundStyle(.secondary)
            }.scrollContentBackground(.hidden).background(DateTheme.canvas)
                .toolbarBackground(DateTheme.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
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
    private var destinationTitle: String {
        switch destination {
        case .saved: copy("Saved", "收藏")
        case .map: copy("Map", "地圖")
        case .passport: "Passport"
        }
    }
    private func modeTitle(_ value: LiveMapMode) -> String {
        switch value {
        case .explore: copy("Explore", "探索")
        case .personal: copy("Mine", "我的")
        case .outing: copy("Friends", "朋友")
        }
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
    private func fitSavedIfNeeded() {
        guard mode == .personal, !didFitSaved, !saved.isEmpty else { return }
        didFitSaved = true
        if mode == .personal { fit(saved) }
    }
    private func fit(_ values: [LiveMapPlace]) {
        if let region = SaveInkMapCamera.region(around: values.map(\.coordinate), user: nil, focused: nil) { camera = .region(region) }
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
                if searching { ProgressView(copy("Searching Apple Maps…", "搜尋 Apple Maps…")).listRowBackground(DateTheme.surface) }
                if let error { Text(error).foregroundStyle(DateTheme.muted).listRowBackground(DateTheme.surface) }
                ForEach(values) { pin in
                    Button { onPick(pin); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(pin.place.name).font(.headline)
                            Text(pin.place.address).font(.caption).foregroundStyle(.secondary)
                            Text(copy("View on map · not saved", "在地圖查看 · 尚未收藏")).font(.caption2)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7).contentShape(Rectangle())
                    }.buttonStyle(.plain).listRowBackground(DateTheme.surface)
                }
            }.scrollContentBackground(.hidden).background(DateTheme.canvas)
                .toolbarBackground(DateTheme.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: copy("Search places, restaurants or addresses", "搜尋地點、餐廳或地址"))
                .onSubmit(of: .search, search)
                .navigationTitle(copy("Search Apple Maps", "搜尋 Apple Maps")).navigationBarTitleDisplayMode(.inline)
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
#endif
