#if SAVVY_CITY_MVP
import SwiftUI
import MapKit

/// Shared saved-place identity, separate from illustrative building geometry.
@MainActor
enum CityMVPPlaceBridge {
    private static let highlightedWays = [137077760, CitySceneData.att4FunWayID, 226945262]
    static let landmarkID = "landmark-101"
    static let cityHallID = "way/142113976"
    static let cityHallCoordinate = CityDistrictCamera.coordinate(x: -5.1, z: -397.5)
    static let context = CityScenePlace.contextPlaces()
    private static let sampledContext = context.filter { place in
        place.id == landmarkID || highlightedWays.contains { place.id == "way/\($0)" }
    }
    private static let modelContacts: [String: SIMD3<Double>] = {
        let ids = Set(highlightedWays + [CityCivicArchitecture.wayID])
        let heights: [String: Double] = (CitySceneData.elements ?? []).reduce(into: [:]) { heights, way in
            guard let id = way["id"] as? Int, ids.contains(id),
                  let tags = way["tags"] as? [String: String], tags["building"] != nil else { return }
            heights["way/\(id)"] = CitySceneData.buildingHeight(tags, way: id)
        }
        var contacts = ["landmark-101": CityLandmark101.pinContact]
        for place in context {
            guard let height = heights[place.id] else { continue }
            contacts[place.id] = SIMD3(place.x, height, place.z)
        }
        return contacts
    }()
    private static let landmarkSource = "https://www.openstreetmap.org/?mlat=25.033968&mlon=121.564468#map=18/25.033968/121.564468"

    static func isPrimaryContextPin(_ id: String) -> Bool {
        id == landmarkID || id == cityHallID
    }

    static func showsContextPin(_ id: String, in frame: CityDistrictCamera) -> Bool {
        guard frame.distance < CityDistrictCamera.contextPinDistance else { return false }
        return isPrimaryContextPin(id) || (frame.opacity > 0.5 && highlightedWays.contains { id == "way/\($0)" })
    }

    static func hasBundledCoordinate(_ place: Place) -> Bool {
        guard inScene(place), let url = place.sourceUrl else { return false }
        return url == landmarkSource || url.hasPrefix("https://www.openstreetmap.org/way/")
    }

    static func projectsSavedPin(_ place: Place, in frame: CityDistrictCamera,
                                 registration: CityDistrictRegistration) -> Bool {
        guard inScene(place), let source = place.sourceUrl else { return false }
        if source == "https://www.openstreetmap.org/\(cityHallID)" {
            // City Hall has a dedicated native annotation when the frame cannot draw it.
            return showsContextPin(cityHallID, in: frame)
        }
        guard let context = sampledContext.first(where: { sourceURL(for: $0) == source }),
              showsContextPin(context.id, in: frame) else { return false }
        return frame.ownsContextPin(contextPin(for: applying(place, to: context), registration: registration))
    }

    static func sourceURL(for place: CityScenePlace) -> String {
        if place.id.hasPrefix("way/") { return "https://www.openstreetmap.org/\(place.id)" }
        return landmarkSource
    }
    static func savedMatch(for place: CityScenePlace, in saved: [Place]) -> Place? {
        if place.id.hasPrefix("saved:"), let id = UUID(uuidString: String(place.id.dropFirst(6))) {
            return saved.first { $0.id == id }
        }
        // Never join branches merely by name or proximity.
        return saved.first { $0.sourceUrl == sourceURL(for: place) }
    }

    static func contextID(for place: Place) -> String? {
        guard let source = place.sourceUrl else { return nil }
        return context.first { sourceURL(for: $0) == source }?.id
    }

    static func cityHallPlace(in saved: [Place]) -> CityScenePlace? {
        guard let cityHall = context.first(where: { $0.id == cityHallID }) else { return nil }
        guard let match = savedMatch(for: cityHall, in: saved.filter(inScene)) else { return cityHall }
        return applying(match, to: cityHall)
    }

    static func contextPins(in saved: [Place], registration: CityDistrictRegistration) -> [CityDistrictCamera.Pin] {
        let visibleSaved = saved.filter(inScene)
        return sampledContext.map { place in
            let displayed = savedMatch(for: place, in: visibleSaved).map { applying($0, to: place) } ?? place
            return contextPin(for: displayed, registration: registration)
        }
    }

    static func contextPin(for place: CityScenePlace, registration: CityDistrictRegistration) -> CityDistrictCamera.Pin {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        return .init(id: place.id, coordinate: registration.mapCoordinate(coordinate),
                     modelContact: modelContact(for: place.id, at: coordinate))
    }

    static func modelContact(for id: String?, at coordinate: CLLocationCoordinate2D) -> SIMD3<Double>? {
        guard let id, let contact = modelContacts[id], let place = context.first(where: { $0.id == id }) else { return nil }
        let point = CityDistrictCamera.world(coordinate)
        guard hypot(point.x - place.x, point.z - place.z) <= 1 else { return nil }
        return contact
    }

    static func select(_ place: CityScenePlace, in viewModel: MapViewModel) {
        if let saved = savedMatch(for: place, in: viewModel.places) {
            viewModel.selectPlace(saved, enrichPhoto: false)
        } else {
            viewModel.clearSelectedMapObject()
            viewModel.selectedMapCandidate = candidate(for: place)
        }
    }

    static func inScene(_ place: Place) -> Bool {
        place.isMapKitMappable && abs((place.longitude - 121.564468) * 100850) < 650
            && abs((place.latitude - 25.033968) * 111195) < 650
    }
    static func places(context: [CityScenePlace], saved: [Place]) -> [CityScenePlace] {
        let visibleSaved = saved.filter(inScene)
        var used = Set<UUID>()
        let mapped = context.map { place -> CityScenePlace in
            guard let match = savedMatch(for: place, in: visibleSaved) else { return place }
            used.insert(match.id)
            return applying(match, to: place)
        }
        return mapped + visibleSaved.filter { !used.contains($0.id) }.map {
            CityScenePlace(id: "saved:\($0.id.uuidString)", title: $0.name, category: $0.category.rawValue,
                           address: $0.address, latitude: $0.latitude, longitude: $0.longitude, isSaved: true)
        }
    }

    private static func applying(_ match: Place, to place: CityScenePlace) -> CityScenePlace {
        CityScenePlace(id: place.id, title: match.name, category: match.category.rawValue,
                       address: match.address, latitude: match.latitude, longitude: match.longitude, isSaved: true)
    }
    static func candidate(for place: CityScenePlace) -> SaveMapCandidate {
        SaveMapCandidate(
            id: "city-mvp:\(place.id)", title: place.title,
            subtitle: place.address.isEmpty ? "Taipei · address not provided by source" : place.address,
            latitude: place.latitude, longitude: place.longitude,
            category: place.id == "landmark-101" ? .attraction : PlaceCategory.inferred(from: place.category + " " + place.title),
            sourceURL: sourceURL(for: place), sourcePlatform: .other,
            evidence: ["Local test · not saved until you confirm.",
                       place.id == "landmark-101" ? "Taipei 101: simplified model with a manual map anchor." : "OpenStreetMap \(place.id): estimated point from the building footprint; position and entrance unverified.",
                       "Building height and entrance are not verified. Check the source before saving."]
        )
    }
}

struct CityMVPSelectedPin {
    let anchor: CityDistrictCamera.Pin
    let contextID: String?
    let title: String
    let isSaved: Bool

    @MainActor
    init?(viewModel: MapViewModel, registration: CityDistrictRegistration?) {
        if let place = viewModel.selectedPlace, place.isMapKitMappable {
            let coordinate = CityMVPPlaceBridge.hasBundledCoordinate(place)
                ? registration?.mapCoordinate(place.coordinate) ?? place.coordinate : place.coordinate
            contextID = CityMVPPlaceBridge.contextID(for: place)
            anchor = .init(id: place.id.uuidString, coordinate: coordinate,
                           modelContact: CityMVPPlaceBridge.modelContact(for: contextID, at: place.coordinate))
            title = place.name
            isSaved = true
        } else if let candidate = viewModel.selectedMapCandidate, candidate.hasTrustworthyCoordinate {
            contextID = candidate.id.hasPrefix("city-mvp:") ? String(candidate.id.dropFirst(9)) : nil
            let coordinate = contextID != nil
                ? registration?.mapCoordinate(candidate.coordinate) ?? candidate.coordinate : candidate.coordinate
            anchor = .init(id: candidate.id, coordinate: coordinate,
                           modelContact: CityMVPPlaceBridge.modelContact(for: contextID, at: candidate.coordinate))
            title = candidate.title
            isSaved = false
        } else {
            return nil
        }
    }

    func artwork(contactOpacity: Double = 0, titleAbove: Bool = false,
                 browsePhotoDiameter: CGFloat = CityPinArtwork.photoDiameter) -> some View {
        CityPinArtwork(id: contextID, title: title, symbol: isSaved ? "bookmark.fill" : "mappin",
                       saved: isSaved, selected: true, contactOpacity: contactOpacity,
                       browsePhotoDiameter: browsePhotoDiameter)
            .id(anchor.id)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(isSaved ? "Map Stamp" : "Unsaved place")
            .accessibilityIdentifier("cityMVP.selectedGroundPin")
            .overlay(alignment: .top) {
                // The label can move out of the card's way without moving the photo or its anchor.
                Color.clear.frame(height: 0)
                    .overlay(alignment: titleAbove ? .bottom : .top) {
                        CityPinArtwork.Title(text: title, selected: true)
                            .offset(y: titleAbove ? -5 : CityPinArtwork.height + 5)
                            .accessibilityIdentifier("cityMVP.selectedGroundPinTitle")
                            .accessibilityHidden(!CityDistrictTrace.enabled)
                    }
            }
            .transaction { $0.animation = nil }
    }
}

struct CityMVPMapSurface<AppleMap: View>: View {
    @ObservedObject var viewModel: MapViewModel
    let frame: CityDistrictCamera?
    let registration: CityDistrictRegistration?
    let selectedPin: CityMVPSelectedPin?
    @Binding var sceneReady: Bool
    let registrationFailed: Bool
    let retryRegistration: () -> Void
    let navigate: (MapCamera, Animation?) -> Void
    let appleMap: () -> AppleMap
    @AppStorage(CityMVPStyle.nightPreference) private var night = false
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var city = City.taipei
    @State private var sceneRequested = false
    @State private var scenePreparationFailed = false
    @State private var sceneGeneration = 0
    @State private var showsAgent = false
    @State private var showsPlaces = false
    @State private var showsFriends = false
    @State private var query = ""
    @State private var expandedPanelHeight: CGFloat = 240
    @State private var compactPanelHeight = CityMVPPlacePanel.minimumCompactHeight
    @State private var verifyOverviewRequested = false
    @State private var verifyLaunchFinished = false
    enum City: String, CaseIterable { case taipei = "Taipei 台北", shanghai = "Shanghai 上海" }
    private static var panelBottomInset: CGFloat { 122 }

    private var places: [CityScenePlace] {
        CityMVPPlaceBridge.places(context: CityMVPPlaceBridge.context, saved: viewModel.places)
    }
    private var showsStreetDetail: Bool { frame?.showsStreetDetail == true }
    private var verifyAtOverview: Bool {
        guard verifyOverviewRequested, !verifyLaunchFinished, let frame else { return false }
        return frame.style == .city && abs(frame.distance - CityMVPCameras.taipei.distance) < 160
    }

    private var isNearTaipei: Bool {
        guard let camera = frame?.mapCamera else { return false }
        return camera.distance < 30_000 && abs(camera.centerCoordinate.latitude - 25.034) < 0.3
            && abs(camera.centerCoordinate.longitude - 121.564) < 0.3
    }

    private var sceneRevealAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.22) }

    var body: some View {
        ZStack(alignment: .top) {
            if city == .shanghai {
                shanghaiPlaceholder
            } else {
                appleMap()
                if sceneRequested || frame?.shouldPrewarm == true {
                    CitySceneView(projection: frame?.projection, sceneOpacity: frame?.opacity ?? 0,
                                  sceneBlend: frame?.sceneBlend, night: night,
                                  landmarkPoint: CityDistrictTrace.enabled ? frame?.landmarkPoint : nil,
                                  nativeDistance: frame?.distance ?? .infinity,
                                  onReady: { ready in
                                      sceneReady = ready
                                      scenePreparationFailed = !ready
                                      CityDistrictTrace.write("scene-ready\t\(ready)")
                                  })
                        .id(sceneGeneration)
                        .mask {
                            Group {
                                if let frame { CityDistrictSceneMask(frame: frame) } else { Color.clear }
                            }
                            .mask { CityMVPAttributionMask() }
                        }
                        .opacity(frame?.sceneLayerOpacity ?? 0)
                        .animation(sceneRevealAnimation, value: sceneReady)
                        .onAppear {
                            sceneRequested = true
                            sceneReady = false
                            scenePreparationFailed = false
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if let frame, !frame.cloudPatches.isEmpty {
                    CityDistrictCloudVeil(patches: frame.cloudPatches, night: night)
                        .opacity(frame.cloudOpacity)
                        .animation(sceneRevealAnimation, value: sceneReady)
                        .mask { CityMVPAttributionMask() }
                }
                placePins.animation(sceneRevealAnimation, value: sceneReady)
            }
            mapChrome
        }
        .coordinateSpace(name: CityDistrictCamera.space)
        .onChange(of: city) { _, value in
            if value == .shanghai { sceneReady = false }
        }
        .task(id: registration) {
            guard registration != nil, CityDistrictTrace.opensDistrictOnLaunch, !verifyOverviewRequested else { return }
            do {
                try await Task.sleep(for: .milliseconds(700))
                verifyOverviewRequested = true
                openAppleMap(at: registeredTaipei)
            } catch { return }
        }
        .task(id: verifyAtOverview) {
            guard verifyAtOverview else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
                if CityDistrictTrace.selectsLandmarkOnLaunch {
                    select(CityMVPPlaceBridge.landmarkID)
                    try await Task.sleep(for: .milliseconds(350))
                }
            } catch { return }
            verifyLaunchFinished = true
            if CityDistrictTrace.opensOverviewOnly { return }
            if CityDistrictTrace.opensCityHallOnLaunch {
                openCorner(CityMVPPlaceBridge.cityHallCoordinate, heading: 180)
            } else if CityDistrictTrace.opensCornerOnLaunch {
                openCorner(CityStreetDetail.songzhi)
            } else {
                zoomToDistrict(true, centered: true)
            }
        }
        .overlay(alignment: .top) {
            if CityDistrictTrace.enabled {
                Color.clear
                    .frame(width: 220, height: 220)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Map pinch area")
                    .accessibilityValue(frame.map { String(Int($0.heading.rounded())) } ?? "")
                    .accessibilityIdentifier("cityMVP.pinchArea")
                    .allowsHitTesting(false)
                    .padding(.top, 160)
            }
        }
        .onChange(of: frame) { _, sample in
            guard CityDistrictTrace.enabled, let sample else { return }
            let landmarkSelection = selectedPin?.contextID == CityMVPPlaceBridge.landmarkID ? selectedPin : nil
            CityDistrictTrace.record(sample, landmarkSelection: landmarkSelection?.anchor)
        }
        .background(CityMVPStyle.canvas)
        .overlay(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if let place = viewModel.selectedPlace {
                    CityMVPPlacePanel(name: place.name, detail: place.address, saved: place, candidate: nil,
                                      photoCredit: CityPinArtwork.photo(for: selectedContextID),
                                      onSave: { _ in }, onClose: viewModel.clearSelectedMapObject,
                                      compact: shouldCompactPanel,
                                      onExpandedHeight: { expandedPanelHeight = $0 },
                                      onCompactHeight: { compactPanelHeight = $0 })
                        .id(place.id)
                } else if let candidate = viewModel.selectedMapCandidate {
                    CityMVPPlacePanel(name: candidate.title, detail: candidate.subtitle, saved: nil, candidate: candidate,
                                      photoCredit: CityPinArtwork.photo(for: selectedContextID),
                                      onSave: { candidate in
                        let place = try await viewModel.saveMapCandidateAsPlace(candidate)
                        viewModel.selectPlace(place, enrichPhoto: false)
                    }, onClose: viewModel.clearSelectedMapObject,
                                      compact: shouldCompactPanel,
                                      onExpandedHeight: { expandedPanelHeight = $0 },
                                      onCompactHeight: { compactPanelHeight = $0 })
                        .id(candidate.id)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, Self.panelBottomInset)
        }
        .sheet(isPresented: $showsAgent) {
            CityMVPAgentSheet(places: viewModel.places, onOpen: openAgentPlace)
                .tint(CityMVPStyle.blue)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsFriends) {
            CityMVPFriendsSheet()
        }
        .sheet(isPresented: $showsPlaces) {
            NavigationStack {
                List {
                    Section("Your saved places · 本地收藏") {
                        if places.filter(\.isSaved).isEmpty { Text("No saved places in this scene yet.") }
                        ForEach(places.filter { $0.isSaved && matches($0) }) { row($0) }
                    }
                    Section("Map context · 未收藏") {
                        ForEach(places.filter { !$0.isSaved && matches($0) }) { row($0) }
                    }
                }
                .searchable(text: $query, prompt: "Search map places")
                .navigationTitle("Taipei 101")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsPlaces = false } } }
            }
        }
    }
    private var mapChrome: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                cityMenu
                Button { showsFriends = true } label: {
                    Image(systemName: "person.2.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .cityMVPGlass(in: Circle())
                .accessibilityLabel("朋友推薦 Friends")
                .accessibilityIdentifier("cityMVP.friends")
                Spacer(minLength: 4)
                HStack(spacing: 0) {
                    if city == .taipei { modeButton }
                    lightingButton
                }
                .buttonStyle(.plain)
                .cityMVPGlass(in: Capsule())
            }
            if city == .taipei, let frame, frame.opacity > 0 {
                Text(CityScenePlace.contextDataAvailable
                     ? "© OpenStreetMap contributors · ODbL"
                     : "Street data unavailable · 101 model only")
                    .font(.system(size: 9))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(CityMVPStyle.panel.opacity(0.96), in: Capsule())
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(CityMVPStyle.ink)
        .padding(.horizontal, 16).padding(.top, 62)
    }

    private var cityMenu: some View {
        Menu {
            Button("世界 World", systemImage: "globe") { openAppleMap(at: CityMVPCameras.world) }
            Button("台北 Taipei", systemImage: "building.2") { openAppleMap(at: registeredTaipei) }
            Button("上海 Shanghai", systemImage: "building.columns") {
                viewModel.clearSelectedMapObject()
                city = .shanghai
            }
            if city == .taipei {
                Section("Taipei 3D") {
                    Button("臺北市政府 Taipei City Hall", systemImage: "building.columns") {
                        openCorner(CityMVPPlaceBridge.cityHallCoordinate, heading: 180)
                    }
                    .disabled(registration == nil)
                    Button("市府路 × 信義路", systemImage: "tree") { openCorner(CityStreetDetail.cityHall) }
                        .disabled(registration == nil)
                    Button("松智路 × 信義路", systemImage: "tree") { openCorner(CityStreetDetail.songzhi) }
                        .disabled(registration == nil)
                }
            }
            Section {
                if city == .taipei && showsStreetDetail {
                    Button("Places 地點", systemImage: "list.bullet") { showsPlaces = true }
                }
                Button("SAV-E Agent", systemImage: "sparkles") { showsAgent = true }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.system(size: 14, weight: .semibold))
                Text(city == .shanghai ? "Shanghai" : isNearTaipei ? "Taipei" : "Explore")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 12).frame(height: 44)
        }
        .cityMVPGlass(in: Capsule())
        .accessibilityIdentifier("cityMVP.city")
    }

    private var modeButton: some View {
        Button {
            if registration == nil {
                retryRegistration()
                return
            }
            // Retry preparation only when the user taps.
            if scenePreparationFailed {
                scenePreparationFailed = false
                sceneGeneration += 1
            }
            zoomToDistrict(!showsStreetDetail)
        } label: {
            Text(registrationFailed || scenePreparationFailed ? "Retry" : showsStreetDetail ? "Map" : "3D")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(registrationFailed ? "Retry map alignment" : scenePreparationFailed ? "Retry 3D street scene" : showsStreetDetail ? "Back to Taipei overview" : "Explore Taipei 101 at street level")
        .accessibilityIdentifier("cityMVP.mode")
        .accessibilityValue(modeValue)
        .disabled(registration == nil && !registrationFailed)
    }

    private var lightingButton: some View {
        Button { night.toggle() } label: {
            Image(systemName: night ? "moon.stars.fill" : "sun.max.fill")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(language.localized(english: "Map lighting", traditionalChinese: "地圖光線"))
        .accessibilityValue(night
            ? language.localized(english: "Night", traditionalChinese: "夜晚")
            : language.localized(english: "Day", traditionalChinese: "白天"))
        .accessibilityIdentifier("cityMVP.lighting")
    }

    private var modeValue: String {
        guard registration != nil else { return registrationFailed ? "Alignment unavailable" : "Aligning map" }
        let hasModeledOverview = (frame?.opacity ?? 0) > 0.5
        let mode = showsStreetDetail ? "District" : hasModeledOverview ? "Overview" : "Map"
        guard CityDistrictTrace.enabled, let frame else { return mode }
        return "\(mode) \(Int(frame.distance)) \(Int((frame.opacity * 100).rounded()))%"
    }

    private struct OverlayPin: Identifiable {
        let id: String
        let contextID: String?
        let title: String
        let symbol: String
        let saved: Bool
        let selected: Bool
        let placement: CityDistrictCamera.PinPlacement
        let reveal: Double
    }

    private func contextPins(in frame: CityDistrictCamera) -> [OverlayPin] {
        guard registration != nil, frame.distance < CityDistrictCamera.contextPinDistance else { return [] }
        return places.compactMap { place in
            guard place.id != selectedContextID, CityMVPPlaceBridge.showsContextPin(place.id, in: frame),
                  let placement = contextPlacement(for: place, in: frame) else { return nil }
            let reveal = pinReveal(for: place.id, saved: place.isSaved, in: frame)
            return OverlayPin(id: place.id, contextID: place.id, title: place.title,
                              symbol: place.id == CityMVPPlaceBridge.cityHallID ? "building.columns" : contextSymbol(place.category),
                              saved: place.isSaved, selected: false, placement: placement, reveal: reveal)
        }
    }

    private func pinReveal(for contextID: String?, saved: Bool, in frame: CityDistrictCamera) -> Double {
        guard !saved, let contextID else { return 1 }
        return CityDistrictCamera.contextPinReveal(
            distance: frame.distance, sceneOpacity: frame.opacity,
            primary: CityMVPPlaceBridge.isPrimaryContextPin(contextID)
        )
    }

    private var placePins: some View {
        GeometryReader { _ in
            if let frame {
                let context = contextPins(in: frame)
                let photoDiameter = CityPinArtwork.zoomPhotoDiameter(distance: frame.distance)
                let selection = selectedPin.flatMap { pin in
                    frame.selectedPlacement(for: pin.anchor).map { (pin: pin, placement: $0) }
                }
                let compactTop = frame.viewport.height - Self.panelBottomInset - compactPanelHeight
                let titleAbove = selection.map { $0.placement.point.y + CityPinArtwork.selectedTitleClearance > compactTop } ?? false
                let reserved: [CGRect] = selection.map { selection in
                    let point = selection.placement.point
                    let hasPhoto = CityPinArtwork.photo(for: selection.pin.contextID) != nil
                    return [
                        CityPinLabelLayout.badge(at: point, diameter: hasPhoto ? CityPinArtwork.selectedPhotoDiameter : 60,
                                                 selected: true),
                        CityPinLabelLayout.title(selection.pin.title, at: point, selected: true, above: titleAbove),
                    ]
                } ?? []
                let entries = context.map { pin in
                    let point = pin.placement.point
                    let diameter = CityPinArtwork.photo(for: pin.id) == nil ? 32 : photoDiameter
                    let scale = CityPinArtwork.visibleScale(reveal: pin.reveal, reduceMotion: reduceMotion)
                    return CityPinLabelLayout.Entry(
                        id: pin.id,
                        badge: CityPinLabelLayout.badge(at: point, diameter: diameter * scale),
                        title: CityPinLabelLayout.title(pin.title, at: point),
                        reveal: pin.reveal,
                        priority: pin.saved ? 2 : CityMVPPlaceBridge.isPrimaryContextPin(pin.id) ? 1 : 0
                    )
                }
                let titles = CityPinLabelLayout.titleOpacities(entries, selectedBounds: reserved)
                let pins = context + (selection.map { selection in
                    [OverlayPin(id: selection.pin.contextID ?? selection.pin.anchor.id,
                                contextID: selection.pin.contextID, title: selection.pin.title,
                                symbol: selection.pin.isSaved ? "bookmark.fill" : "mappin",
                                saved: selection.pin.isSaved, selected: true,
                                placement: selection.placement, reveal: 1)]
                } ?? [])
                ForEach(pins) { pin in
                    let placement = pin.placement
                    let sourceReveal = pinReveal(for: pin.contextID, saved: pin.saved, in: frame)
                    let sourceScale = CityPinArtwork.visibleScale(reveal: sourceReveal, reduceMotion: reduceMotion)
                    Button { select(pin.id) } label: {
                        CityPinArtwork(id: pin.contextID, title: pin.title, symbol: pin.symbol,
                                       saved: pin.saved, selected: pin.selected,
                                       contactOpacity: placement.contactOpacity,
                                       browsePhotoDiameter: photoDiameter * (pin.selected ? sourceScale : 1),
                                       zoomReveal: pin.reveal, titleOpacity: titles[pin.id] ?? 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(pin.title)
                    .accessibilityValue(pin.saved ? "Map Stamp" : "Unsaved place")
                    .accessibilityIdentifier(pin.selected ? "cityMVP.selectedGroundPin" : "cityMVP.groundPin.\(pin.id)")
                    .opacity(pin.reveal)
                    .allowsHitTesting(!pin.selected && pin.reveal >= 0.45)
                    .accessibilityHidden(pin.reveal < 0.45)
                    .overlay(alignment: .top) {
                        if pin.selected {
                            Color.clear.frame(height: 0)
                                .overlay(alignment: titleAbove ? .bottom : .top) {
                                    CityPinArtwork.Title(text: pin.title, selected: true)
                                        .offset(y: titleAbove ? -5 : CityPinArtwork.height + 5)
                                        .accessibilityIdentifier("cityMVP.selectedGroundPinTitle")
                                        .accessibilityHidden(!CityDistrictTrace.enabled)
                                }
                                .allowsHitTesting(false)
                        }
                    }
                    .zIndex(pin.selected ? 1 : 0)
                    .position(x: placement.point.x, y: placement.point.y - CityPinArtwork.height / 2)
                    .transaction { $0.animation = nil }
                }
            }
        }
        .clipped()
    }

    // Shrink the drawer rather than moving either the camera or selected anchor.
    // Its expanded size is retained while compact to avoid a layout feedback loop.
    private var shouldCompactPanel: Bool {
        guard let frame, let selectedPin,
              let point = frame.selectedOverlayPoint(for: selectedPin.anchor),
              CGRect(origin: .zero, size: frame.viewport).contains(point) else { return false }
        return point.y + 36 > frame.viewport.height - Self.panelBottomInset - expandedPanelHeight
    }

    private var selectedContextID: String? {
        selectedPin?.contextID
    }

    private func contextPlacement(for place: CityScenePlace, in frame: CityDistrictCamera) -> CityDistrictCamera.PinPlacement? {
        guard let registration else { return nil }
        let pin = CityMVPPlaceBridge.contextPin(for: place, registration: registration)
        return frame.contextPlacement(for: pin)
    }

    private func contextSymbol(_ category: String) -> String {
        switch category {
        case "公園": "tree.fill"
        case "購物": "bag.fill"
        case "咖啡": "cup.and.saucer.fill"
        case "住宿": "bed.double.fill"
        default: "mappin"
        }
    }

    private var registeredTaipei: MapCamera {
        let camera = CityMVPCameras.taipei
        let coordinate = registration?.mapCoordinate(camera.centerCoordinate) ?? camera.centerCoordinate
        return MapCamera(centerCoordinate: coordinate, distance: camera.distance, heading: camera.heading, pitch: camera.pitch)
    }

    private func openAppleMap(at camera: MapCamera) {
        city = .taipei
        navigate(camera, SaveTheme.Motion.standardSpring)
    }

    private func openCorner(_ coordinate: CLLocationCoordinate2D, heading: Double = 0) {
        guard let registration else { return }
        city = .taipei
        navigate(MapCamera(centerCoordinate: registration.mapCoordinate(coordinate), distance: 550,
                           heading: heading, pitch: 49), .easeInOut(duration: 0.55))
    }

    private func zoomToDistrict(_ closer: Bool, centered: Bool = false) {
        guard let registration else { return }
        let current = frame?.mapCamera ?? registeredTaipei
        let offset = CityDistrictCamera.world(registration.sceneCoordinate(current.centerCoordinate))
        let isLocal = current.distance < 30_000 && max(abs(offset.x), abs(offset.z)) < 450
        let camera = centered || (closer && !isLocal) ? registeredTaipei : current
        let next = MapCamera(centerCoordinate: camera.centerCoordinate,
                             distance: closer ? 1_450 : CityDistrictCamera.overviewDistance,
                             heading: camera.heading, pitch: camera.pitch)
        navigate(next, .easeInOut(duration: 0.55))
    }

    private func openAgentPlace(_ place: Place) {
        city = .taipei
        if place.isMapKitMappable {
            let coordinate = CityMVPPlaceBridge.hasBundledCoordinate(place)
                ? registration?.mapCoordinate(place.coordinate) ?? place.coordinate
                : place.coordinate
            navigate(MapCamera(centerCoordinate: coordinate, distance: 900, heading: 0, pitch: 30), nil)
        }
        viewModel.selectPlace(place, enrichPhoto: false)
    }

    private func matches(_ place: CityScenePlace) -> Bool {
        query.isEmpty || place.title.localizedCaseInsensitiveContains(query)
    }
    private func row(_ place: CityScenePlace) -> some View {
        Button { showsPlaces = false; select(place.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.title).foregroundStyle(CityMVPStyle.ink)
                Text(place.isSaved ? "Map Stamp · 已收藏" : "Unsaved · check source before saving")
                    .font(.caption).foregroundStyle(CityMVPStyle.muted)
            }.frame(minHeight: 44)
        }.accessibilityIdentifier("cityMVP.place.\(place.id)")
    }
    private func select(_ id: String) {
        guard let place = places.first(where: { $0.id == id }) else { return }
        CityMVPPlaceBridge.select(place, in: viewModel)
    }
    private var shanghaiPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "map").font(.system(size: 38)).foregroundStyle(CityMVPStyle.ink)
            Text("Shanghai · 上海").font(.title2.bold())
            Text("Amap not connected · 高德尚未連線").font(.headline)
            Text(amapMessage).font(.subheadline).multilineTextAlignment(.center)
            Text("Jing’an Temple 3D will appear after the map connection and model alignment are verified.")
                .font(.caption).foregroundStyle(CityMVPStyle.muted).multilineTextAlignment(.center)
            Button("Explore Taipei 101") {
                city = .taipei
                zoomToDistrict(true, centered: true)
            }
                .buttonStyle(.borderedProminent).tint(CityMVPStyle.ink)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("cityMVP.amap.pending")
    }
    private var amapMessage: String {
        switch CityMVPConfiguration.amapStatus {
        case .missingKey: "This test build has no Amap iOS key. Taipei remains available."
        case .bundleMismatch: "The local configuration does not match this test app. No connection was attempted."
        case .sdkNotConnected: "A local key is configured. Native SDK integration and account permissions still need verification."
        }
    }
}

private struct CityMVPAttributionMask: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                verticalFade(clearance: 118, height: 28)
                // The two native attribution areas keep their full original
                // clearance. Extend the scene only through the middle.
                if geometry.size.width >= 360, geometry.size.height >= 600 {
                    verticalFade(clearance: 64, height: 48)
                        .mask {
                            HStack(spacing: 0) {
                                Color.clear.frame(width: 120)
                                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 34)
                                Color.black
                                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 34)
                                Color.clear.frame(width: 120)
                            }
                        }
                }
            }
        }
    }

    private func verticalFade(clearance: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: height)
            Color.clear.frame(height: clearance)
        }
    }
}
#endif
