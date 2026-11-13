#if SAVVY_CITY_MVP
import SwiftUI
import MapKit

/// Shared saved-place identity, separate from illustrative building geometry.
@MainActor
enum CityMVPPlaceBridge {
    private static let roofContactWays = [137077760, CitySceneData.att4FunWayID, 226945262]
    static let landmarkID = "landmark-101"
    static let cityHallID = "way/142113976"
    static let cityHallCoordinate = CityDistrictCamera.coordinate(x: -5.1, z: -397.5)
    static let context = CityScenePlace.contextPlaces()
    private static let contextBySource = Dictionary(uniqueKeysWithValues: context.map { (sourceURL(for: $0), $0) })
    private static let contextByID = Dictionary(uniqueKeysWithValues: context.map { ($0.id, $0) })
    private static let modelContacts: [String: SIMD3<Double>] = {
        let ids = Set(roofContactWays + [CityCivicArchitecture.wayID])
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
        // Public building labels belong to the sourced context layer. Only
        // 101 retains a landmark photo; user saves get their own pin below.
        return id == landmarkID
    }

    static func hasBundledCoordinate(_ place: Place) -> Bool {
        guard let url = place.sourceUrl else { return false }
        if CityContextPlace.enabled, CityContextPlace.bySource[url] != nil { return true }
        guard inScene(place) else { return false }
        return url == landmarkSource || url.hasPrefix("https://www.openstreetmap.org/way/")
    }

    static func projectsSavedPin(_ place: Place, in frame: CityDistrictCamera,
                                 registration: CityDistrictRegistration) -> Bool {
        // Ownership is geographic, not a transient conversion-success test.
        // A missing native point hides this owner until the bounded refresh;
        // it must not mount a second native annotation in the meantime.
        frame.style == .city && frame.usesGeographicPinOverlay && inScene(place)
    }

    static func sourceURL(for place: CityScenePlace) -> String {
        if place.id.hasPrefix("way/") || place.id.hasPrefix("node/") { return "https://www.openstreetmap.org/\(place.id)" }
        return place.id == landmarkID ? landmarkSource : ""
    }
    static func savedMatch(for place: CityScenePlace, in saved: [Place]) -> Place? {
        if place.id.hasPrefix("saved:"), let id = UUID(uuidString: String(place.id.dropFirst(6))) {
            return saved.first { $0.id == id }
        }
        // Never join branches merely by name or proximity.
        return saved.first { $0.sourceUrl == sourceURL(for: place) }
    }

    static func contextID(for place: Place) -> String? {
        guard let source = place.sourceUrl else { return "saved:\(place.id.uuidString)" }
        return contextBySource[source]?.id
            ?? (CityContextPlace.enabled ? CityContextPlace.bySource[source]?.id : nil)
            ?? "saved:\(place.id.uuidString)"
    }

    static func cityHallPlace(in saved: [Place]) -> CityScenePlace? {
        guard let cityHall = context.first(where: { $0.id == cityHallID }) else { return nil }
        guard let match = savedMatch(for: cityHall, in: saved.filter(inScene)) else { return nil }
        return applying(match, to: cityHall)
    }

    static func contextPins(in saved: [Place], registration: CityDistrictRegistration) -> [CityDistrictCamera.Pin] {
        places(context: context, saved: saved)
            .filter { $0.isSaved || $0.id == landmarkID }
            .map { contextPin(for: $0, registration: registration, saved: saved) }
    }

    static func contextPin(for place: CityScenePlace, registration: CityDistrictRegistration,
                           saved: [Place] = []) -> CityDistrictCamera.Pin {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        // Imported provider coordinates already belong to the native map.
        // Only known source-WGS geometry is registered into that map space.
        let match = savedMatch(for: place, in: saved)
        let usesRegistration = match.map(hasBundledCoordinate) ?? !place.id.hasPrefix("saved:")
        return .init(id: place.id, coordinate: usesRegistration ? registration.mapCoordinate(coordinate) : coordinate,
                     modelContact: modelContact(for: place.id, at: coordinate))
    }

    static func modelContact(for id: String?, at coordinate: CLLocationCoordinate2D) -> SIMD3<Double>? {
        guard let id, let contact = modelContacts[id], let place = contextByID[id] else { return nil }
        let point = CityDistrictCamera.world(coordinate)
        guard hypot(point.x - place.x, point.z - place.z) <= 1 else { return nil }
        return contact
    }

    @discardableResult
    static func confirm(_ candidate: SaveMapCandidate, in viewModel: MapViewModel,
                        retaining camera: MapCamera?) async throws -> Place {
        // The shared import flow focuses raw source coordinates. This local
        // renderer has a registered native camera, heading and pitch already;
        // confirmation must not replace it with an unrelated flat region.
        defer { if let camera { viewModel.cameraPosition = .camera(camera) } }
        let place = try await viewModel.saveMapCandidateAsPlace(candidate)
        viewModel.selectPlace(place, enrichPhoto: false)
        return place
    }

    static func select(_ place: CityScenePlace, in viewModel: MapViewModel) {
        if let saved = savedMatch(for: place, in: viewModel.places) {
            viewModel.selectPlace(saved, enrichPhoto: false)
        } else {
            viewModel.clearSelectedMapObject()
            viewModel.selectedMapCandidate = candidate(for: place)
        }
    }

    static func candidate(for place: CityContextPlace) -> SaveMapCandidate {
        SaveMapCandidate(id: "city-mvp:\(place.id)", title: place.title,
            subtitle: place.originalName + " · Taipei · street address not supplied",
            latitude: place.latitude, longitude: place.longitude,
            category: PlaceCategory.inferred(from: place.category.rawValue + " " + place.originalName),
            sourceURL: place.sourceURL.absoluteString, sourcePlatform: .other,
            evidence: ["Public map context · not saved until you confirm.",
                       "OpenStreetMap \(place.id) · source export \(CityContextPlace.sourceDate).",
                       place.positionKind == .sourceNode
                           ? "Source node position; entrance and current operation unverified."
                           : "Approximate footprint mean; entrance and current operation unverified.",
                       "English names are original source values, when available."]
                .map { "Evidence: " + $0 })
    }

    static func select(_ place: CityContextPlace, in viewModel: MapViewModel) {
        if let saved = viewModel.places.first(where: { $0.sourceUrl == place.sourceURL.absoluteString }) {
            viewModel.selectPlace(saved, enrichPhoto: false)
        } else {
            viewModel.clearSelectedMapObject()
            viewModel.selectedMapCandidate = candidate(for: place)
        }
    }

    static func symbol(for category: String) -> String {
        if let category = PlaceCategory(rawValue: category) { return category.mapMarkerSymbol }
        switch category {
        case "公園": return "tree.fill"
        case "購物": return "bag.fill"
        case "咖啡": return "cup.and.saucer.fill"
        case "住宿": return "bed.double.fill"
        default: return "mappin"
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
            CityScenePlace(id: contextID(for: $0) ?? "saved:\($0.id.uuidString)", title: $0.name, category: $0.category.rawValue,
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
                .map { "Evidence: " + $0 }
        )
    }
}

struct CityMVPSelectedPin {
    let anchor: CityDistrictCamera.Pin
    let contextID: String?
    let title: String
    let isSaved: Bool
    let isVisited: Bool
    let isInDistrict: Bool
    let symbol: String

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
            isVisited = place.status == .visited
            isInDistrict = CityMVPPlaceBridge.inScene(place)
            symbol = place.category.mapMarkerSymbol
        } else if let candidate = viewModel.selectedMapCandidate, candidate.hasTrustworthyCoordinate {
            contextID = candidate.id.hasPrefix("city-mvp:") ? String(candidate.id.dropFirst(9)) : nil
            let coordinate = contextID != nil
                ? registration?.mapCoordinate(candidate.coordinate) ?? candidate.coordinate : candidate.coordinate
            anchor = .init(id: candidate.id, coordinate: coordinate,
                           modelContact: CityMVPPlaceBridge.modelContact(for: contextID, at: candidate.coordinate))
            title = candidate.title
            isSaved = false
            isVisited = false
            let sourcePoint = CityDistrictCamera.world(candidate.coordinate)
            isInDistrict = abs(sourcePoint.x) < 650 && abs(sourcePoint.z) < 650
            symbol = candidate.category?.mapMarkerSymbol ?? "mappin"
        } else {
            return nil
        }
    }

    func usesGeographicOverlay(style: CityDistrictMapStyle, hasRegistration: Bool,
                               geographicPinsEnabled: Bool) -> Bool {
        style == .city && hasRegistration && isInDistrict && geographicPinsEnabled
    }

    func artwork(contactOpacity: Double = 0,
                 browsePhotoDiameter: CGFloat = CityPinArtwork.photoDiameter) -> some View {
        VStack(spacing: 0) {
            CityPinArtwork(id: contextID, title: title, symbol: symbol,
                           saved: isSaved, selected: true, visited: isVisited,
                           contactOpacity: contactOpacity, browsePhotoDiameter: browsePhotoDiameter)
                .accessibilityHidden(true)
            CityPinArtwork.Title(text: title, selected: true)
                .frame(height: CityPinArtwork.selectedTitleClearance)
                .accessibilityHidden(true)
        }
        .frame(width: 140, height: CityPinArtwork.nativeSelectedHeight)
        .background(CityNativePinPriority())
        .id(anchor.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(CityPinArtwork.stateDescription(saved: isSaved, visited: isVisited))
        .accessibilityIdentifier("cityMVP.selectedGroundPin")
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
    var nativeLabelsQuiet = false
    var labelChangeCamera: MapCamera?
    var labelPolicyRevision = 0
    let appleMap: () -> AppleMap
    @AppStorage(CityMVPStyle.nightPreference) private var night = false
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cityMVPMapIsVisible) private var mapIsVisible
    @Environment(\.cityMVPOpenFriends) private var onFriends
    @Environment(\.cityMVPOpenGuide) private var onGuide
    @Environment(\.cityMVPOpenSaved) private var onSaved
    @State private var city = City.taipei
    @State private var sceneRequested = false
    @State private var scenePreparationFailed = false
    @State private var sceneGeneration = 0
    @State private var showsAgent = false
    @State private var showsPlaces = false
    @State private var pendingPlaceID: String?
    @State private var showsFriends = false
    @State private var query = ""
    @State private var expandedPanelHeight: CGFloat = 240
    @State private var compactPanelHeight = CityMVPPlacePanel.minimumCompactHeight
    @State private var verifyOverviewRequested = false
    @State private var verifyLaunchFinished = false
    @State private var verificationDistanceOverride: Double?
    @State private var verificationCenterEast = 0.0
    enum City: String, CaseIterable { case taipei = "Taipei 台北", shanghai = "Shanghai 上海" }

    private var places: [CityScenePlace] {
        CityMVPPlaceBridge.places(context: CityMVPPlaceBridge.context, saved: viewModel.filteredPlaces)
    }
    private var showsStreetDetail: Bool { frame?.showsStreetDetail == true }
    private var verifyAtOverview: Bool {
        guard verifyOverviewRequested, !verifyLaunchFinished, let frame else { return false }
        return frame.style == .city && abs(frame.distance - CityMVPCameras.taipei.distance) < 160
    }

    private static var verificationDistances: [Double] { [10_000, 9_500, 9_000, 8_500, 8_000, 7_500, 6_500, 5_200, 5_000, 4_692, 4_350, 4_150, 3_650, 2_900, 1_450] }
    private var verificationRenderEnabled: Bool {
        CityDistrictTrace.enabled && ProcessInfo.processInfo.arguments.contains("--verify-xinyi-far-render")
    }

    private var verificationRenderDistance: Double {
        if verificationRenderEnabled, let verificationDistanceOverride { return verificationDistanceOverride }
        let prefix = "--verify-xinyi-render-distance="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
              let distance = Double(argument.dropFirst(prefix.count)),
              Self.verificationDistances.contains(distance) else { return 4_692 }
        return distance
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
                                  registration: registration, pins: sceneReady ? renderPins : [],
                                  contextLabels: renderedContextLabels,
                                  cloudPatches: CitySceneView.usesCloudHandoff && rendererOwnsPins ? frame?.cloudPatches ?? [] : [],
                                  cloudOpacity: frame?.cloudOpacity ?? 0,
                                  onLoading: {
                                      sceneReady = false
                                      scenePreparationFailed = false
                                  },
                                  onReady: { ready in
                                      sceneReady = ready
                                      scenePreparationFailed = !ready
                                      CityDistrictTrace.write("scene-ready\t\(ready)")
                                  })
                        .id(sceneGeneration)
                        .mask { CityMVPAttributionMask() }
                        .onAppear {
                            sceneRequested = true
                            sceneReady = false
                            scenePreparationFailed = false
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if let frame, !frame.cloudPatches.isEmpty {
                    if CitySceneView.usesCloudHandoff && !rendererOwnsPins {
                        CityGeographicCloudFallback(patches: frame.cloudPatches, opacity: frame.cloudOpacity, night: night)
                            .mask { CityMVPAttributionMask() }
                    } else if !CitySceneView.usesOpaqueReveal {
                        CityDistrictCloudVeil(patches: frame.cloudPatches, night: night)
                            .opacity(frame.cloudOpacity)
                            .animation(sceneRevealAnimation, value: sceneReady)
                            .mask { CityMVPAttributionMask() }
                    }
                }
                if mapIsVisible { placePins.animation(sceneRevealAnimation, value: sceneReady) }
            }
            if mapIsVisible {
                mapChrome
                if city == .taipei, isNearTaipei, !sceneReady, !scenePreparationFailed,
                   sceneRequested || frame?.shouldPrewarm == true {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Preparing 3D streets…").font(.caption.weight(.medium))
                    }
                    .foregroundStyle(CityMVPStyle.ink)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .cityMVPGlass(in: Capsule())
                    .padding(.top, 118)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("cityMVP.preparingStreets")
                }
            }
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
            if verificationRenderEnabled {
                requestVerificationCamera(distance: verificationRenderDistance)
                return
            }
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
            if (CityDistrictTrace.enabled || CityMVPPreviewConfiguration.inspectsPreview) && mapIsVisible {
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
        .overlay(alignment: .topTrailing) {
            if CityMVPPreviewConfiguration.inspectsPreview, mapIsVisible, let frame {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Local preview inspection")
                    .accessibilityValue(previewInspection(frame))
                    .accessibilityIdentifier("cityMVP.previewInspection")
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if verificationRenderEnabled && mapIsVisible {
                verificationCameraMenu.padding(.leading, 16).padding(.top, 116)
            }
        }
        .overlay {
            if verificationRenderEnabled, let frame {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Map render fixture")
                    .accessibilityIdentifier("cityMVP.farRenderFixture")
                    .accessibilityValue(farRenderFixture(frame))
                    .allowsHitTesting(false)
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
                if mapIsVisible, let place = viewModel.selectedPlace {
                    CityMVPPlacePanel(name: place.name, detail: place.address, saved: place, candidate: nil,
                                      photoCredit: CityPinArtwork.photo(for: selectedContextID),
                                      onSave: { _ in }, onClose: viewModel.clearSelectedMapObject,
                                      compact: chromePlacement.compact,
                                      onExpandedHeight: { expandedPanelHeight = $0 },
                                      onCompactHeight: { compactPanelHeight = $0 })
                        .id(place.id)
                } else if mapIsVisible, let candidate = viewModel.selectedMapCandidate {
                    CityMVPPlacePanel(name: candidate.title, detail: candidate.subtitle, saved: nil, candidate: candidate,
                                      photoCredit: CityPinArtwork.photo(for: selectedContextID),
                                      onSave: { candidate in
                        try await CityMVPPlaceBridge.confirm(candidate, in: viewModel,
                            retaining: frame?.mapCamera ?? viewModel.cameraPosition.camera)
                    }, onClose: viewModel.clearSelectedMapObject,
                                      compact: chromePlacement.compact,
                                      onExpandedHeight: { expandedPanelHeight = $0 },
                                      onCompactHeight: { compactPanelHeight = $0 })
                        .id(candidate.id)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, chromePlacement.panelBottomInset)
        }
        .preference(key: CityMVPDockInsetKey.self,
                    value: mapIsVisible ? chromePlacement.dockBottomInset : CityMVPBottomBar.bottomClearance)
        .sheet(isPresented: $showsAgent) {
            CityMVPAgentSheet(places: viewModel.places, onOpen: openAgentPlace)
                .tint(CityMVPStyle.blue)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showsFriends) {
            CityMVPFriendExchangeSheet(places: viewModel.places) { place in
                try viewModel.confirmCityMVPFriendPlace(place)
            }
        }
        .sheet(isPresented: $showsPlaces, onDismiss: completePlaceSelection) {
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
                Button { if let onFriends { onFriends() } else { showsFriends = true } } label: {
                    Image(systemName: "person.2.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .cityMVPGlass(in: Circle())
                .accessibilityLabel("朋友推薦 Friends")
                .accessibilityIdentifier("cityMVP.friends")
                if city == .taipei {
                    Button {
                        SaveHaptics.tap()
                        Task { await viewModel.focusOnUserLocation() }
                    } label: {
                        Group {
                            if viewModel.isLocatingUser { ProgressView() }
                            else { Image(systemName: "location") }
                        }.frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .cityMVPGlass(in: Circle())
                    .disabled(viewModel.isLocatingUser)
                    .accessibilityLabel(language.localized(english: "Center map on current location", traditionalChinese: "將地圖移至目前位置"))
                    .accessibilityIdentifier("map.currentLocation")
                }
                Spacer(minLength: 4)
                HStack(spacing: 0) {
                    if city == .taipei { modeButton }
                    lightingButton
                }
                .buttonStyle(.plain)
                .cityMVPGlass(in: Capsule())
            }

        }
        .foregroundStyle(CityMVPStyle.ink)
        .padding(.horizontal, 16).padding(.top, 62)
    }

    private var cityMenu: some View {
        Menu {
            Button("世界 World", systemImage: "globe") { openAppleMap(at: SavvyMapRegion.world.camera ?? CityMVPCameras.world) }
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
                    Button("Places 地點", systemImage: "list.bullet") { if let onSaved { onSaved() } else { showsPlaces = true } }
                }
                Button("SAV-E Agent", systemImage: "sparkles") { if let onGuide { onGuide() } else { showsAgent = true } }
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

    private var verificationCameraMenu: some View {
        Menu {
            ForEach(Self.verificationDistances, id: \.self) { distance in
                Button("\(Int(distance)) m") { requestVerificationCamera(distance: distance) }
                    .accessibilityIdentifier("cityMVP.renderProbe.distance.\(Int(distance))")
            }
            Button("2 km east · 5,000 m") { requestVerificationCamera(distance: 5_000, east: 2_000) }
                .accessibilityIdentifier("cityMVP.renderProbe.east2000")
            Button("1 km east · 5,000 m") { requestVerificationCamera(distance: 5_000, east: 1_000) }
                .accessibilityIdentifier("cityMVP.renderProbe.east1000")
        } label: {
            Label("Render \(Int(verificationRenderDistance)) m", systemImage: "camera")
                .font(.caption.weight(.semibold)).padding(.horizontal, 12)
                .frame(height: 44).contentShape(Capsule())
        }
        .background(.regularMaterial, in: Capsule())
        .disabled(registration == nil || !verifyLaunchFinished)
        .accessibilityIdentifier("cityMVP.renderProbe.camera")
    }

    private var verificationTarget: CLLocationCoordinate2D {
        let center = registeredTaipei.centerCoordinate
        return .init(latitude: center.latitude, longitude: center.longitude + verificationCenterEast / 100850)
    }

    private func requestVerificationCamera(distance: Double, east: Double = 0) {
        guard verificationRenderEnabled, registration != nil,
              Self.verificationDistances.contains(distance), [0.0, 1_000, 2_000].contains(east) else { return }
        verificationDistanceOverride = distance
        verificationCenterEast = east
        navigate(MapCamera(centerCoordinate: verificationTarget, distance: distance,
                           heading: 20, pitch: 35), nil)
    }

    private func previewInspection(_ frame: CityDistrictCamera) -> String {
        let camera = frame.mapCamera
        let point = selectedPin.flatMap { frame.selectedPlacement(for: $0.anchor)?.point }
        var value: [String: Any] = [
            "route": CityMVPPreviewConfiguration.selectedRoute.rawValue,
            "trace": CityDistrictTrace.enabled,
            "nativeGround": CitySceneView.usesNativeGroundOwner,
            "opaqueReveal": CitySceneView.usesOpaqueReveal,
            "materialTone": CitySceneView.usesMaterialTone,
            "cloudHandoff": CitySceneView.usesCloudHandoff,
            "groundOwnership": CitySceneGeometry.usesGroundOwnership,
            "contextRing": CityContextBuildings.enabled,
            "contextHideRequested": CitySceneView.hidesContextForInspection,
            "contextSurfaceDetail": CityContextBuildings.usesSurfaceDetail,
            "contextLabels": CityContextPlace.enabled,
            "contextLabelCount": renderedContextLabels.count,
            "nativeLabelsQuiet": nativeLabelsQuiet,
            "sceneReady": sceneReady, "projectionAvailable": frame.projection != nil,
            "sceneOpacity": frame.opacity,
            "geographicPinOverlay": frame.usesGeographicPinOverlay,
            "selectedContactOpacity": selectedPin.flatMap { frame.selectedPlacement(for: $0.anchor)?.contactOpacity } ?? -1,
            "fitError": frame.projection?.error ?? -1,
            "latitude": camera.centerCoordinate.latitude, "longitude": camera.centerCoordinate.longitude,
            "distance": camera.distance, "heading": camera.heading, "pitch": camera.pitch,
            "selectionInput": CityPinSelectionObservation.events,
            "selectedID": selectedPin?.contextID ?? "",
            "selectedNativeIdentity": selectedPin?.anchor.id ?? "",
            "selectedPinX": point?.x ?? -1, "selectedPinY": point?.y ?? -1,
            "night": night, "savedCount": viewModel.places.count,
            "pins": renderPins.map { pin in
                ["id": pin.id, "saved": pin.saved, "selected": pin.selected, "visited": pin.visited,
                 "photo": CityPinArtwork.photo(for: pin.contextID) != nil, "symbol": pin.symbol,
                 "x": pin.placement.point.x, "y": pin.placement.point.y] as [String: Any]
            }]
        if let observation = frame.registrationInspection {
            var alignment: [String: Any] = [
                "sourceLatitude": CityScenePlace.originLatitude,
                "sourceLongitude": CityScenePlace.originLongitude,
                "latitudeOffset": observation.latitudeOffset,
                "longitudeOffset": observation.longitudeOffset,
                "provenance": observation.provenance
            ]
            if let source = observation.sourcePoint {
                alignment["sourceX"] = source.x; alignment["sourceY"] = source.y
            }
            if let registered = observation.registeredPoint {
                alignment["registeredX"] = registered.x; alignment["registeredY"] = registered.y
            }
            value["registrationObservation"] = alignment
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "{}" }
        return result
    }

    private func farRenderFixture(_ frame: CityDistrictCamera) -> String {
        let camera = frame.mapCamera
        let target = verificationTarget
        let matchesRequest = registration != nil && frame.hasRegistration
            && abs(frame.distance - verificationRenderDistance) < 2
            && abs(camera.heading - 20) < 0.1 && abs(camera.pitch - 35) < 0.1
            && abs(camera.centerCoordinate.latitude - target.latitude) < 0.000001
            && abs(camera.centerCoordinate.longitude - target.longitude) < 0.000001
        let selectedPoint = selectedPin.flatMap { frame.selectedPlacement(for: $0.anchor)?.point }
        var value: [String: Any] = [
            // At/above prewarm's5200m boundary the native map intentionally
            // owns the frame and a scene projection may be absent.
            "ready": sceneReady && (verificationRenderDistance >= frame.projectionCutoff || frame.projection != nil) && matchesRequest
                && (!frame.cloudHandoff || selectedPin == nil || selectedPoint != nil),
            "requestedDistance": Int(verificationRenderDistance),
            "materialTone": CitySceneView.usesMaterialTone,
            "cloudHandoff": frame.cloudHandoff,
            "contextRing": CityContextBuildings.enabled,
            "contextLabelsEnabled": CityContextPlace.enabled,
            "contextLabelCount": renderedContextLabels.count,
            "selectedSource": viewModel.selectedMapCandidate?.sourceURL ?? viewModel.selectedPlace?.sourceUrl ?? "",
            "savedCount": viewModel.places.count,
            "contextLabels": renderedContextLabels.map { label in
                ["id": label.id, "title": label.place.title, "x": label.bounds.midX,
                 "y": label.bounds.midY, "width": label.bounds.width, "height": label.bounds.height] as [String: Any]
            },
            "quietNativeLabels": CityDistrictMapStyle.quietNativeLabels,
            "nativeLabelsQuiet": nativeLabelsQuiet,
            "labelPolicyRevision": labelPolicyRevision,
            "requestedCenterEast": verificationCenterEast,
            "requestedLatitude": target.latitude,
            "requestedLongitude": target.longitude,
            "cloudOpacity": frame.cloudOpacity,
            "cloudPatchCount": frame.cloudPatches.count,
            "projectionAvailable": frame.projection != nil,
            "groundOwnership": CitySceneGeometry.usesGroundOwnership,
            "opaqueReveal": CitySceneView.usesOpaqueReveal,
            "registrationProvenance": registration?.provenance.rawValue ?? "unavailable",
            "registrationAnchorLatitude": registration?.mapCoordinate(CityDistrictCamera.coordinate(x: 0, z: 0)).latitude ?? -1,
            "registrationAnchorLongitude": registration?.mapCoordinate(CityDistrictCamera.coordinate(x: 0, z: 0)).longitude ?? -1,
            "night": night,
            "selectionInput": CityPinSelectionObservation.events,
            "selectedID": selectedPin?.contextID ?? "",
            "latitude": camera.centerCoordinate.latitude,
            "longitude": camera.centerCoordinate.longitude,
            "distance": camera.distance, "heading": camera.heading, "pitch": camera.pitch,
            "width": frame.viewport.width, "height": frame.viewport.height,
            "pinX": frame.landmarkPoint?.x ?? -1, "pinY": frame.landmarkPoint?.y ?? -1,
            "selectedPinX": selectedPoint?.x ?? -1, "selectedPinY": selectedPoint?.y ?? -1,
            "fitError": frame.projection?.error ?? -1
        ]
        if let labelChangeCamera {
            value["labelChangeLatitude"] = labelChangeCamera.centerCoordinate.latitude
            value["labelChangeLongitude"] = labelChangeCamera.centerCoordinate.longitude
            value["labelChangeDistance"] = labelChangeCamera.distance
            value["labelChangeHeading"] = labelChangeCamera.heading
            value["labelChangePitch"] = labelChangeCamera.pitch
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-cloud-consumer") {
            value["patches"] = frame.cloudPatches.map { patch in
                ["x": patch.center.x, "y": patch.center.y, "eastX": patch.east.dx,
                 "eastY": patch.east.dy, "southX": patch.south.dx, "southY": patch.south.dy]
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "{}" }
        return result
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
        var visited = false
    }

    private func contextPins(in frame: CityDistrictCamera) -> [OverlayPin] {
        guard registration != nil, frame.style == .city else { return [] }
        // Bind saved status once for this render sample, with the same exact
        // source/UUID identity as the pin bridge. No name or proximity joins.
        let visitedByID = viewModel.filteredPlaces.reduce(into: [String: Bool]()) { result, place in
            guard let id = CityMVPPlaceBridge.contextID(for: place), result[id] == nil else { return }
            result[id] = place.status == .visited
        }
        return places.compactMap { place in
            guard place.id != selectedContextID,
                  place.isSaved || CityMVPPlaceBridge.showsContextPin(place.id, in: frame),
                  let placement = contextPlacement(for: place, in: frame) else { return nil }
            let reveal = pinReveal(for: place.id, saved: place.isSaved, in: frame)
            return OverlayPin(id: place.id, contextID: place.id, title: place.title,
                              symbol: place.id == CityMVPPlaceBridge.cityHallID ? "building.columns" : CityMVPPlaceBridge.symbol(for: place.category),
                              saved: place.isSaved, selected: false, placement: placement, reveal: reveal,
                              visited: place.isSaved && visitedByID[place.id] == true)
        }
    }

    private func pinReveal(for contextID: String?, saved: Bool, in frame: CityDistrictCamera) -> Double {
        guard !saved, let contextID else { return 1 }
        return CityDistrictCamera.contextPinReveal(
            distance: frame.distance, sceneOpacity: frame.opacity,
            primary: CityMVPPlaceBridge.isPrimaryContextPin(contextID)
        )
    }

    private var renderPins: [CityScenePin] {
        guard mapIsVisible, let frame, frame.usesGeographicPinOverlay else { return [] }
        let context = contextPins(in: frame)
        let photoDiameter = CityPinArtwork.zoomPhotoDiameter(distance: frame.distance)
        let selection: (pin: CityMVPSelectedPin, placement: CityDistrictCamera.PinPlacement)? = selectedPin.flatMap { pin in
            guard pin.usesGeographicOverlay(style: frame.style, hasRegistration: registration != nil,
                                            geographicPinsEnabled: frame.usesGeographicPinOverlay) else { return nil }
            return frame.selectedPlacement(for: pin.anchor).map { (pin: pin, placement: $0) }
        }
        let titleAbove = selectedTitleAbove
        let reserved: [CGRect] = selection.map { selection in
            let point = selection.placement.point
            return [
                CityPinLabelLayout.badge(at: point, diameter: CityPinArtwork.selectedPhotoDiameter,
                         selected: true),
                CityPinLabelLayout.title(selection.pin.title, at: point, selected: true, above: titleAbove),
            ]
        } ?? []
        let entries = context.map { pin in
            let point = pin.placement.point
            let diameter = CityPinArtwork.headDiameter(hasPhoto: CityPinArtwork.photo(for: pin.id) != nil,
                                                       selected: false, browseDiameter: photoDiameter)
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
                symbol: selection.pin.symbol,
                saved: selection.pin.isSaved, selected: true,
                placement: selection.placement, reveal: 1, visited: selection.pin.isVisited)]
        } ?? [])
        return pins.map { pin in
            let sourceReveal = pinReveal(for: pin.contextID, saved: pin.saved, in: frame)
            let sourceScale = CityPinArtwork.visibleScale(reveal: sourceReveal, reduceMotion: reduceMotion)
            return CityScenePin(id: pin.id, contextID: pin.contextID, title: pin.title, symbol: pin.symbol,
                                saved: pin.saved, selected: pin.selected, placement: pin.placement,
                                reveal: pin.reveal, photoDiameter: photoDiameter * (pin.selected ? sourceScale : 1),
                                titleOpacity: titles[pin.id] ?? 1, titleAbove: titleAbove, visited: pin.visited)
        }
    }

    private var renderedContextLabels: [CityContextLabel] {
        guard CityContextPlace.enabled, nativeLabelsQuiet, mapIsVisible, sceneReady,
              let frame, let registration else { return [] }
        let pins = renderPins
        var reserved = pins.flatMap { pin in
            [CityPinLabelLayout.badge(at: pin.placement.point,
                 diameter: pin.selected ? 68 : max(44, pin.photoDiameter + 4), selected: pin.selected),
             CityPinLabelLayout.title(pin.title, at: pin.placement.point, selected: pin.selected,
                                      above: pin.selected && pin.titleAbove)]
        }
        let viewport = frame.viewport
        let chrome = chromePlacement
        reserved += [CGRect(x: 0, y: 0, width: viewport.width, height: 134),
                     CGRect(x: 0, y: viewport.height-chrome.dockBottomInset-80, width: viewport.width, height: 80),
                     CGRect(x: 0, y: viewport.height-38, width: viewport.width, height: 38)]
        if selectedPin != nil {
            let height = chrome.compact ? compactPanelHeight : expandedPanelHeight
            reserved.append(CGRect(x: 0, y: viewport.height-chrome.panelBottomInset-height,
                                   width: viewport.width, height: height))
        }
        var excluding = Set(pins.compactMap(\.contextID))
        // Saved annotations keep their existing owner. Never draw two controls
        // for an exact saved identity or merge equal-name branches.
        excluding.formUnion(viewModel.places.compactMap { $0.sourceUrl.flatMap { CityContextPlace.bySource[$0]?.id } })
        return CityContextLabels.projected(frame: frame, registration: registration,
                                           excluding: excluding, reserved: reserved)
    }

    private var rendererOwnsPins: Bool {
        sceneReady && frame?.projection != nil
    }

    private var placePins: some View {
        GeometryReader { _ in
            ForEach(renderedContextLabels) { label in
                CityPinControl(title: label.place.title, value: "Public map context · not saved",
                    identifier: "cityMVP.contextLabel.\(label.id)", selected: false, enabled: true,
                    action: { CityMVPPlaceBridge.select(label.place, in: viewModel) })
                    .frame(width: label.bounds.width, height: label.bounds.height)
                    .position(x: label.bounds.midX, y: label.bounds.midY)
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
            }
            ForEach(renderPins) { pin in
                Group {
                    if !rendererOwnsPins {
                        pin.artwork
                            .position(x: pin.placement.point.x, y: pin.placement.point.y - CityPinArtwork.height / 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    // One semantic44pt+ host; physical touches always reach the
                    // native map, whose shared tap observer selects the pin.
                    let diameter = pin.selected ? 64 : max(44, pin.photoDiameter + 4)
                    CityPinControl(title: pin.title, value: CityPinArtwork.stateDescription(saved: pin.saved, visited: pin.visited),
                                   identifier: pin.selected ? "cityMVP.selectedGroundPin" : "cityMVP.groundPin.\(pin.id)",
                                   selected: pin.selected, enabled: pin.reveal >= 0.45,
                                   action: { if !pin.selected { select(pin.id) } })
                        .frame(width: diameter, height: diameter)
                        .position(x: pin.placement.point.x, y: pin.placement.point.y - diameter / 2 - 3)
                        .allowsHitTesting(false)
                }
                .opacity(pin.reveal)
                .allowsHitTesting(pin.reveal >= 0.45)
                .accessibilityHidden(pin.reveal < 0.45)
                .zIndex(pin.selected ? 1 : 0)
                .transaction { $0.animation = nil }
                if pin.selected, !rendererOwnsPins {
                    // The head artwork omits selected captions because the
                    // scene normally draws them. Keep the same caption bounds
                    // when the native-map fallback owns the photo instead.
                    let bounds = CityPinLabelLayout.title(pin.title, at: pin.placement.point,
                                                         selected: true, above: pin.titleAbove)
                    CityPinArtwork.Title(text: pin.title, selected: true)
                        .frame(width: bounds.width, height: bounds.height)
                        .position(x: bounds.midX, y: bounds.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(2)
                        .transaction { $0.animation = nil }
                }
                if pin.selected, CityDistrictTrace.enabled {
                    let bounds = CityPinLabelLayout.title(pin.title, at: pin.placement.point,
                                                         selected: true, above: pin.titleAbove)
                    CityPinCaptionAccessibility(title: pin.title)
                        .frame(width: bounds.width, height: bounds.height)
                        .position(x: bounds.midX, y: bounds.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .clipped()
    }

    private var selectedTitleAbove: Bool {
        guard let frame, let selectedPin,
              let placement = frame.selectedPlacement(for: selectedPin.anchor) else { return false }
        // Use the resting shelf boundary rather than its resolved position.
        // A moving shelf must not flip the title and cause a layout loop.
        let below = CityPinLabelLayout.title(selectedPin.title, at: placement.point, selected: true)
        return CityMVPChromeLayout.prefersTitleAbove(captionBelow: below, viewport: frame.viewport,
                                                    compactHeight: compactPanelHeight)
    }

    private var chromePlacement: CityMVPChromeLayout.Placement {
        let viewport = frame?.viewport ?? .zero
        let selectedBounds: CGRect? = {
            guard mapIsVisible, let frame, let selectedPin,
                  let placement = frame.selectedPlacement(for: selectedPin.anchor) else { return nil }
            let point = placement.point
            let badge = CityPinLabelLayout.badge(at: point, diameter: 64, selected: true)
            let title = CityPinLabelLayout.title(selectedPin.title, at: point, selected: true, above: selectedTitleAbove)
            let bounds = badge.union(title)
            return bounds.intersects(CGRect(origin: .zero, size: viewport)) ? bounds : nil
        }()
        return CityMVPChromeLayout.resolve(viewport: viewport, selectedBounds: selectedBounds,
                                          expandedHeight: expandedPanelHeight, compactHeight: compactPanelHeight)
    }

    private var selectedContextID: String? {
        selectedPin?.contextID
    }

    private func contextPlacement(for place: CityScenePlace, in frame: CityDistrictCamera) -> CityDistrictCamera.PinPlacement? {
        guard let registration else { return nil }
        let pin = CityMVPPlaceBridge.contextPin(for: place, registration: registration, saved: viewModel.places)
        return frame.contextPlacement(for: pin)
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
        Button {
            CityDistrictTrace.write("places-row\tstart")
            // Commit selection only after this presentation actually dismisses;
            // its owner is not mutated while UIKit is still closing the sheet.
            pendingPlaceID = place.id
            showsPlaces = false
            CityDistrictTrace.write("places-row\tend\t\(showsPlaces)\tpending")
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.title).foregroundStyle(CityMVPStyle.ink)
                Text(place.isSaved ? "Map Stamp · 已收藏" : "Unsaved · check source before saving")
                    .font(.caption).foregroundStyle(CityMVPStyle.muted)
            }.frame(minHeight: 44)
        }.accessibilityIdentifier("cityMVP.place.\(place.id)")
    }
    private func completePlaceSelection() {
        guard let id = pendingPlaceID else { return }
        pendingPlaceID = nil
        select(id)
        CityDistrictTrace.write("places-selection\tcommitted\t\(viewModel.selectedMapCandidate != nil || viewModel.selectedPlace != nil)")
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
        // The native map has no extra bottom inset in City Lab. Preserve its
        // original credit controls in the 32pt footer below the floating dock,
        // rather than exposing a second ground strip above the dock and card.
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 12)
            Color.clear.frame(height: 32)
        }
    }
}
#endif
