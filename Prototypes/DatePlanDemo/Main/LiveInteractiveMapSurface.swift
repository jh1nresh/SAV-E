#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Combine
import MapKit
import SwiftUI

/// Native feature selection and custom annotation buttons intentionally use separate paths.
@MainActor
struct LiveInteractiveMapSurface: View {
    @Binding var position: MapCameraPosition
    let pins: [LiveMapPlace]
    let isInteractive: Bool
    let routes: [MKRoute]
    let activePinID: String?
    let friends: [LiveFriendMapPlace]
    let publicVenues: [LivePublicDiscoveryVenue]
    let ownerSubject: String
    let sessionGeneration: Int
    let onSelect: (LiveMapPlace) -> Void
    let onCameraSettled: (MapCamera, MKCoordinateRegion) -> Void
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedFeature: MapFeature?
    @State private var cameraDistance: Double
    @State private var itemRequest: MKMapItemRequest?
    @State private var requestTask: Task<Void, Never>?
    @State private var revision = 0
    @State private var isLoading = false
    @State private var hasError = false
    @State private var isMounted = false
    @State private var pinGroupSelection: LiveExplorePinGroup?

    init(position: Binding<MapCameraPosition>, pins: [LiveMapPlace], routes: [MKRoute], isInteractive: Bool = true,
         activePinID: String?, friends: [LiveFriendMapPlace] = [], publicVenues: [LivePublicDiscoveryVenue] = [],
         ownerSubject: String, sessionGeneration: Int,
         onSelect: @escaping (LiveMapPlace) -> Void,
         onCameraSettled: @escaping (MapCamera, MKCoordinateRegion) -> Void) {
        _position = position
        self.pins = pins
        self.isInteractive = isInteractive
        self.routes = routes
        self.activePinID = activePinID
        self.friends = friends
        self.publicVenues = publicVenues
        self.ownerSubject = ownerSubject
        self.sessionGeneration = sessionGeneration
        self.onSelect = onSelect
        self.onCameraSettled = onCameraSettled
        _cameraDistance = State(initialValue: position.wrappedValue.camera?.distance ?? .infinity)
    }

    var body: some View {
        let friendsByPinID = Dictionary(uniqueKeysWithValues: LiveFriendMapPlace.groupedByVenue(friends).compactMap { group in
            group.first.map { ($0.pin.id, group) }
        })
        let publicByPinID = Dictionary(uniqueKeysWithValues: publicVenues.map { ("public:\($0.id)", $0) })
        let now = Date()
        let topicPins = Set(publicByPinID.compactMap { id, venue in
            venue.recentTopicAccountCount(at: now).map { _ in id }
        })
        let groups = LiveExplorePinGroup.group(pins)
        return Map(position: $position, interactionModes: .all, selection: $selectedFeature) {
            ForEach(groups) { group in
                let pin = group.pins[0]
                Annotation(pin.place.name, coordinate: pin.coordinate, anchor: .bottom) {
                    if group.pins.count > 1 {
                        groupedPin(group, hasRecentTopic: group.pins.contains { topicPins.contains($0.id) })
                    } else {
                        LiveInteractivePinButton(pin: pin, showsDetails: cameraDistance < 20_000,
                                                 isActive: activePinID == pin.id,
                                                 friends: friendsByPinID[pin.id] ?? [], publicVenue: publicByPinID[pin.id],
                                                 isRecentTopic: topicPins.contains(pin.id),
                                                 ownerSubject: ownerSubject, sessionGeneration: sessionGeneration) {
                            select(pin)
                        }
                    }
                }.annotationTitles(.hidden)
            }
            ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                MapPolyline(route.polyline).stroke(DateTheme.blue, lineWidth: 5)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .all, showsTraffic: false))
        .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest }
        .mapControls { MapCompass() }
        .onMapCameraChange(frequency: .onEnd) { context in
            guard isMounted, isInteractive, sessionIsCurrent else { return }
            cameraDistance = context.camera.distance
            onCameraSettled(context.camera, context.region)
        }
        .onChange(of: selectedFeature) { _, feature in
            if let feature { resolve(feature) }
            else { cancelRequest(clearSelection: false) }
        }
        .onChange(of: activePinID) { _, id in
            if id != nil { invalidateInteraction() }
        }
        .onChange(of: pins.map(\.id)) { _, _ in invalidateInteraction() }
        .onChange(of: isInteractive) { _, enabled in
            if !enabled { invalidateInteraction() }
        }
        .onChange(of: ownerSubject) { _, _ in invalidateInteraction() }
        .onChange(of: sessionGeneration) { _, _ in invalidateInteraction() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { invalidateInteraction() }
        }
        .onReceive(Publishers.CombineLatest(PrivyAuthService.shared.$authState,
                                           PrivyAuthService.shared.$sessionGeneration)) { state, generation in
#if targetEnvironment(simulator)
            if usesIsolatedVenueFixture { return }
#endif
            // Published values arrive before the singleton's stored values are updated.
            guard case .authenticated(let owner) = state,
                  owner == ownerSubject, generation == sessionGeneration else {
                invalidateInteraction()
                return
            }
        }
        .onAppear { isMounted = true }
        .onDisappear { isMounted = false; invalidateInteraction() }
        .confirmationDialog(copy("Choose a place", "選擇地點"), isPresented: pinGroupPresented,
                            titleVisibility: .visible, presenting: pinGroupSelection) { group in
            ForEach(group.pins) { option in
                Button(group.selectionTitle(for: option)) {
                    guard let current = pins.first(where: { $0.id == option.id }),
                          current.coordinate.latitude == option.coordinate.latitude,
                          current.coordinate.longitude == option.coordinate.longitude else { return }
                    select(current)
                }
            }
        }
        .overlay { requestStatus }
        .accessibilityIdentifier("live.map")
    }

    private var pinGroupPresented: Binding<Bool> {
        Binding(get: { pinGroupSelection != nil }, set: { if !$0 { pinGroupSelection = nil } })
    }

    private func invalidateInteraction() {
        pinGroupSelection = nil
        cancelRequest(clearSelection: true)
    }

    private func groupedPin(_ group: LiveExplorePinGroup, hasRecentTopic: Bool) -> some View {
        Button {
            guard isMounted, isInteractive, sessionIsCurrent else { return }
            cancelRequest(clearSelection: true)
            pinGroupSelection = group
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hasRecentTopic ? "flame.fill" : "text.bubble.fill")
                Text(group.pins.count, format: .number)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(hasRecentTopic ? DateTheme.actionInk : DateTheme.ink)
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(hasRecentTopic ? DateTheme.action : DateTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(DateTheme.blue, lineWidth: 1.5))
            .frame(minWidth: 44, minHeight: 44, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copy("\(group.pins.count) places at this spot", "這裡有 \(group.pins.count) 個地點"))
        .accessibilityValue(hasRecentTopic ? copy("Includes a recent topic", "包含近期話題店") : "")
        .accessibilityIdentifier("live.map.pin.group.\(group.id)")
    }

    private func select(_ pin: LiveMapPlace) {
        guard isMounted, isInteractive, sessionIsCurrent else { return }
        invalidateInteraction()
        onSelect(pin)
    }

#if targetEnvironment(simulator)
    private var usesIsolatedVenueFixture: Bool {
        LivePlanningReviewFixture.reviewedVenuePostsAreCurrent
            && LivePlanningReviewFixture.shared.isCurrent
            && LivePlanningReviewFixture.shared.ownerSubject == ownerSubject
            && LivePlanningReviewFixture.shared.sessionGeneration == sessionGeneration
    }
#endif

    private var sessionIsCurrent: Bool {
#if targetEnvironment(simulator)
        if usesIsolatedVenueFixture { return true }
#endif
        let auth = PrivyAuthService.shared
        guard case .authenticated(let owner) = auth.authState else { return false }
        return owner == ownerSubject && auth.sessionGeneration == sessionGeneration
    }

    private func resolve(_ feature: MapFeature) {
        cancelRequest(clearSelection: false)
        guard isMounted, isInteractive, sessionIsCurrent else { selectedFeature = nil; return }
        let ticket = revision
        let request = MKMapItemRequest(feature: feature)
        itemRequest = request
        isLoading = true
        requestTask = Task { @MainActor in
            do {
                let item = try await request.mapItem
                try Task.checkCancellation()
                guard ticket == revision, isMounted, isInteractive, sessionIsCurrent,
                      selectedFeature == feature else { return }
                guard let pin = LiveMapPlace.search(item) else {
                    itemRequest = nil; requestTask = nil; isLoading = false; hasError = true
                    return
                }
                itemRequest = nil; requestTask = nil; isLoading = false
                selectedFeature = nil
                onSelect(pin)
            } catch {
                guard !Task.isCancelled, ticket == revision, isMounted, isInteractive,
                      sessionIsCurrent, selectedFeature == feature else { return }
                itemRequest = nil; requestTask = nil; isLoading = false; hasError = true
            }
        }
    }

    private func cancelRequest(clearSelection: Bool) {
        revision &+= 1
        itemRequest?.cancel(); itemRequest = nil
        requestTask?.cancel(); requestTask = nil
        isLoading = false; hasError = false
        if clearSelection { selectedFeature = nil }
    }

    @ViewBuilder private var requestStatus: some View {
        if isLoading || hasError {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    ProgressView(copy("Opening Apple Maps place…", "正在取得 Apple Maps 地點…"))
                } else {
                    Label(copy("This place could not be opened. Try again.", "暫時無法取得這個地點，請重試。"),
                          systemImage: "exclamationmark.circle")
                    if let feature = selectedFeature {
                        Button(copy("Retry", "重試")) { resolve(feature) }
                            .frame(minHeight: 44).accessibilityIdentifier("live.map.poi.retry")
                    }
                }
                Button(copy("Cancel", "取消")) { cancelRequest(clearSelection: true) }
                    .frame(minHeight: 44).accessibilityIdentifier("live.map.poi.cancel")
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(DateTheme.ink).tint(DateTheme.blue)
            .padding(16).frame(maxWidth: 300, alignment: .leading)
            .background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(16).accessibilityIdentifier("live.map.poi.status")
        }
    }

    private func copy(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

@MainActor
private struct LiveInteractivePinButton: View {
    let pin: LiveMapPlace
    let showsDetails: Bool
    let isActive: Bool
    let friends: [LiveFriendMapPlace]
    let publicVenue: LivePublicDiscoveryVenue?
    let isRecentTopic: Bool
    let ownerSubject: String
    let sessionGeneration: Int
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguageSettings) private var language
    @State private var tapSequence = 0
    private static let selectionSpring = Spring(response: 0.36, dampingRatio: 0.64)
    private static let selectedPhotoDiameter: CGFloat = 62
    private static let selectedSymbolDiameter: CGFloat = 36

    var body: some View {
        Button {
            tapSequence &+= 1
            onTap()
        } label: {
            if reduceMotion {
                artwork
            } else {
                // Triggered only by this pin's click, never a repeating timeline/camera effect.
                artwork.phaseAnimator([0.0, -1.0, 0.6, 0.0], trigger: tapSequence) { view, phase in
                    view.scaleEffect(1 + abs(phase) * 0.08, anchor: .bottom)
                        .rotationEffect(.degrees(phase * 5), anchor: .bottom)
                } animation: { _ in .spring(Self.selectionSpring) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pin.place.name), \(friends.isEmpty ? sourceTitle : friends.map { $0.statusTitle(language.language) }.joined(separator: ", "))")
        .accessibilityValue(isRecentTopic
                            ? language.localized(english: "Recent topic", traditionalChinese: "近期話題") : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("live.map.pin.\(pin.id)")
    }

    private var artwork: some View {
        VStack(spacing: showsDetails ? 5 : 0) {
            if let publicVenue {
                if showsDetails {
                    ZStack(alignment: .bottomTrailing) {
                        if let post = publicVenue.posts.first(where: { $0.cover != nil }) {
                            LivePublicPostCover(post: post, ownerSubject: ownerSubject, sessionGeneration: sessionGeneration)
                                .frame(width: 46, height: 46).clipped().clipShape(Circle())
                        } else {
                            Image(systemName: "text.bubble.fill").foregroundStyle(DateTheme.blue)
                                .frame(width: 46, height: 46).background(DateTheme.soft, in: Circle())
                        }
                        HStack(spacing: 2) {
                            if isRecentTopic { Image(systemName: "flame.fill") }
                            Text(publicVenue.posts.count, format: .number)
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DateTheme.actionInk).padding(4).background(DateTheme.action, in: Circle())
                    }
                    .overlay(Circle().stroke(DateTheme.surface, lineWidth: 2))
                    Text(pin.place.name).font(.system(size: 11, weight: .semibold))
                        .lineLimit(1).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(DateTheme.surface, in: Capsule())
                } else {
                    Image(systemName: isRecentTopic ? "flame.fill" : "text.bubble.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(isRecentTopic ? DateTheme.actionInk : DateTheme.ink)
                        .frame(width: 28, height: 28)
                        .background(isRecentTopic ? DateTheme.action : DateTheme.surface, in: Circle())
                        .overlay(Circle().stroke(DateTheme.blue, lineWidth: 1.5))
                }
            } else if !friends.isEmpty {
                LiveBusinessPhoto(place: pin.place)
                    .frame(width: 46, height: 46).clipShape(Circle())
                    .overlay(Circle().stroke(DateTheme.blue.opacity(isActive ? 1 : 0.55), lineWidth: 2))
                    .scaleEffect(isActive ? Self.selectedPhotoDiameter / 46 : 1, anchor: .bottom)
                    .animation(reduceMotion ? nil : .spring(Self.selectionSpring), value: isActive)
                ForEach(Array(friends.prefix(2))) { friend in
                    LiveFriendPinBadge(friend: friend)
                }
                if friends.count > 2 {
                    Text(language.localized(english: "+\(friends.count - 2) more", traditionalChinese: "另有 \(friends.count - 2) 人"))
                        .font(.caption2).foregroundStyle(DateTheme.muted)
                }
                Text(pin.place.name).font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 9))
            } else if showsDetails {
                LiveBusinessPhoto(place: pin.place)
                    .frame(width: 46, height: 46).clipShape(Circle())
                    .overlay(Circle().stroke(DateTheme.blue.opacity(isActive ? 1 : 0.55), lineWidth: 2))
                    .scaleEffect(isActive ? Self.selectedPhotoDiameter / 46 : 1, anchor: .bottom)
                    .animation(reduceMotion ? nil : .spring(Self.selectionSpring), value: isActive)
                VStack(spacing: 2) {
                    Text(pin.place.name).font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text(sourceTitle).font(.system(size: 9, design: .rounded)).foregroundStyle(DateTheme.muted)
                }
                .lineLimit(1).padding(.horizontal, 9).padding(.vertical, 5)
                .background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 11))
            } else {
                Image(systemName: pin.origin == .saved ? "bookmark.fill" : "questionmark")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(width: 26, height: 26).background(DateTheme.surface, in: Circle())
                    .overlay(Circle().stroke(DateTheme.blue.opacity(0.65), lineWidth: 1.5))
                    .scaleEffect(isActive ? Self.selectedSymbolDiameter / 26 : 1, anchor: .bottom)
                    .animation(reduceMotion ? nil : .spring(Self.selectionSpring), value: isActive)
            }
        }
        .frame(width: showsDetails || !friends.isEmpty ? 140 : 44, alignment: .bottom)
        .frame(minHeight: 44, alignment: .bottom)
        .foregroundStyle(DateTheme.ink).contentShape(Rectangle())
        .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
    }

    private var sourceTitle: String {
        switch pin.origin {
        case .saved: language.localized(english: "Saved", traditionalChinese: "已收藏")
        case .search: language.localized(english: "Search result · not saved", traditionalChinese: "搜尋結果候選")
        case .shared: pin.sourceLabel == "朋友已分享"
            ? language.localized(english: "Shared by friends", traditionalChinese: "朋友已分享")
            : language.localized(english: "Group candidate", traditionalChinese: "隊伍候選")
        case .publicPost: language.localized(english: "Public post · not saved", traditionalChinese: "公開貼文 · 尚未收藏")
        }
    }
}
#endif
