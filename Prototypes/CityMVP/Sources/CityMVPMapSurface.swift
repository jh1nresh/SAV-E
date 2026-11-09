#if SAVVY_CITY_MVP
import SwiftUI
import MapKit

/// Shared saved-place identity, separate from illustrative building geometry.
@MainActor
enum CityMVPPlaceBridge {
    private static let highlightedWays = [137077760, 234589397, 226945262]
    private static let landmarkID = "landmark-101"
    private static let landmarkSource = "https://www.openstreetmap.org/?mlat=25.033968&mlon=121.564468#map=18/25.033968/121.564468"

    static func showsContextPin(_ id: String, in frame: CityDistrictCamera) -> Bool {
        guard frame.distance < 3_800 else { return false }
        return id == landmarkID || (frame.opacity > 0.5 && highlightedWays.contains { id == "way/\($0)" })
    }

    static func hasBundledCoordinate(_ place: Place) -> Bool {
        guard inScene(place), let url = place.sourceUrl else { return false }
        return url == landmarkSource || url.hasPrefix("https://www.openstreetmap.org/way/")
    }

    static func projectsSavedPin(_ place: Place, in frame: CityDistrictCamera) -> Bool {
        guard inScene(place), let url = place.sourceUrl else { return false }
        if url == landmarkSource { return showsContextPin(landmarkID, in: frame) }
        return highlightedWays.contains { way in
            url == "https://www.openstreetmap.org/way/\(way)" && showsContextPin("way/\(way)", in: frame)
        }
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
            return CityScenePlace(id: place.id, title: match.name, category: match.category.rawValue,
                                  address: match.address, latitude: match.latitude, longitude: match.longitude, isSaved: true)
        }
        return mapped + visibleSaved.filter { !used.contains($0.id) }.map {
            CityScenePlace(id: "saved:\($0.id.uuidString)", title: $0.name, category: $0.category.rawValue,
                           address: $0.address, latitude: $0.latitude, longitude: $0.longitude, isSaved: true)
        }
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

struct CityMVPMapSurface<AppleMap: View>: View {
    @ObservedObject var viewModel: MapViewModel
    let frame: CityDistrictCamera?
    let proxy: MapProxy
    let registration: CityDistrictRegistration?
    let appleMap: () -> AppleMap
    @AppStorage(CityMVPStyle.nightPreference) private var night = false
    @Environment(\.appLanguageSettings) private var language
    @State private var city = City.taipei
    @State private var showsAgent = false
    @State private var showsPlaces = false
    @State private var showsFriends = false
    @State private var query = ""
    @State private var context = CityScenePlace.contextPlaces()
    enum City: String, CaseIterable { case taipei = "Taipei 台北", shanghai = "Shanghai 上海" }

    private var places: [CityScenePlace] { CityMVPPlaceBridge.places(context: context, saved: viewModel.filteredPlaces) }
    private var shows3D: Bool { (frame?.opacity ?? 0) > 0.5 }

    private var isNearTaipei: Bool {
        guard let camera = frame?.mapCamera else { return false }
        return camera.distance < 30_000 && abs(camera.centerCoordinate.latitude - 25.034) < 0.3
            && abs(camera.centerCoordinate.longitude - 121.564) < 0.3
    }
    var body: some View {
        ZStack(alignment: .top) {
            if city == .shanghai {
                shanghaiPlaceholder
            } else {
                appleMap()
                if let frame, frame.shouldPrewarm {
                    CitySceneView(projection: frame.projection, night: night,
                                  landmarkPoint: CityDistrictTrace.enabled ? landmarkPoint : nil,
                                  nativeDistance: frame.distance)
                        .opacity(frame.opacity)
                        .mask {
                            VStack(spacing: 0) {
                                Color.black
                                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 28)
                                Color.clear.frame(height: 118)
                            }
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                placePins
            }
            VStack(spacing: 7) {
                HStack(spacing: 9) {
                    Button { showsFriends = true } label: {
                        Image(systemName: "person.2.fill").frame(width: 44, height: 44)
                    }
                    .cityMVPGlass(in: Circle())
                    .accessibilityLabel("朋友推薦 Friends")
                    .accessibilityIdentifier("cityMVP.friends")
                    Menu {
                        Button("世界 World", systemImage: "globe") { openAppleMap(at: CityMVPCameras.world) }
                        Button("台北 Taipei", systemImage: "building.2") { openAppleMap(at: registeredTaipei) }
                        Button("市府路 × 信義路", systemImage: "tree") { openCorner(CityStreetDetail.cityHall) }
                            .disabled(registration == nil)
                        Button("松智路 × 信義路", systemImage: "tree") { openCorner(CityStreetDetail.songzhi) }
                            .disabled(registration == nil)
                        Button("上海 Shanghai", systemImage: "building.columns") {
                            viewModel.clearSelectedMapObject()
                            city = .shanghai
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(city == .shanghai ? "Shanghai" : "Explore").font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        }.padding(.horizontal, 15).frame(height: 44)
                    }
                    .cityMVPGlass(in: Capsule())
                    .accessibilityIdentifier("cityMVP.city")
                    Spacer(minLength: 0)
                    if city == .taipei {
                        Button {
                            zoomToDistrict(!shows3D)
                        } label: {
                            Text(shows3D ? "Map" : "3D").font(.system(size: 13, weight: .bold))
                                .frame(width: 44, height: 44)
                        }
                        .cityMVPGlass(in: Circle())
                        .accessibilityLabel(shows3D ? "Back to Apple Maps" : "Explore Taipei 101 in 3D")
                        .accessibilityIdentifier("cityMVP.mode")
                        .accessibilityValue(modeValue)
                        .disabled(registration == nil)
                    }
                    Button { night.toggle() } label: {
                        Image(systemName: night ? "moon.stars.fill" : "sun.max.fill")
                            .frame(width: 44, height: 44)
                    }
                    .cityMVPGlass(in: Circle())
                    .accessibilityLabel(language.localized(english: "Map lighting", traditionalChinese: "地圖光線"))
                    .accessibilityValue(night
                        ? language.localized(english: "Night", traditionalChinese: "夜晚")
                        : language.localized(english: "Day", traditionalChinese: "白天"))
                    .accessibilityIdentifier("cityMVP.lighting")
                    Button { showsAgent = true } label: {
                        Image(systemName: "sparkles").frame(width: 44, height: 44)
                    }
                    .cityMVPGlass(in: Circle())
                    .foregroundStyle(CityMVPStyle.blue)
                    .accessibilityLabel("SAV-E Agent")
                    .accessibilityIdentifier("cityMVP.agent")
                }
                if city == .taipei && !shows3D {
                    HStack(spacing: 8) {
                        mapShortcut("World", symbol: "globe", id: "world") { openAppleMap(at: CityMVPCameras.world) }
                        mapShortcut("Taipei", symbol: "building.2", id: "taipei") { openAppleMap(at: registeredTaipei) }
                            .accessibilityAddTraits(isNearTaipei ? .isSelected : [])
                        Spacer(minLength: 0)
                    }
                }
                if city == .taipei && shows3D {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Button { showsPlaces = true } label: {
                                Image(systemName: "list.bullet").frame(width: 44, height: 44)
                            }
                            .cityMVPGlass(in: Circle())
                            .accessibilityLabel("Places 地點")
                            .accessibilityIdentifier("cityMVP.places")
                        }
                    }.padding(.top, 18)
                }
            }
            .foregroundStyle(CityMVPStyle.ink)
            .padding(.horizontal, 16).padding(.top, 62)
        }
        .coordinateSpace(name: CityDistrictCamera.space)
        .overlay(alignment: .top) {
            if CityDistrictTrace.enabled {
                Color.clear
                    .frame(width: 220, height: 220)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Map pinch area")
                    .accessibilityIdentifier("cityMVP.pinchArea")
                    .allowsHitTesting(false)
                    .padding(.top, 160)
            }
        }
        .onChange(of: frame) { _, sample in
            guard CityDistrictTrace.enabled, let sample, sample.distance < 5_500 else { return }
            let point = landmarkPoint
            CityDistrictTrace.write("map\t\(sample.distance)\t\(sample.opacity)\t\(sample.projection?.error ?? -1)\t\(selectedContextID == "landmark-101")\t\(point?.x ?? -1)\t\(point?.y ?? -1)")
        }
        .background(CityMVPStyle.canvas)
        .overlay(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if let place = viewModel.selectedPlace {
                    CityMVPPlacePanel(name: place.name, detail: place.address, saved: place, candidate: nil,
                                      photoCredit: CityPinArtwork.photo(for: selectedContextID),
                                      onSave: { _ in }, onClose: viewModel.clearSelectedMapObject)
                        .id(place.id)
                } else if let candidate = viewModel.selectedMapCandidate {
                    CityMVPPlacePanel(name: candidate.title, detail: candidate.subtitle, saved: nil, candidate: candidate,
                                      photoCredit: CityPinArtwork.photo(for: selectedContextID),
                                      onSave: { candidate in
                        let place = try await viewModel.saveMapCandidateAsPlace(candidate)
                        viewModel.selectPlace(place, enrichPhoto: false)
                    }, onClose: viewModel.clearSelectedMapObject)
                        .id(candidate.id)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 122)
        }
        .overlay(alignment: .topLeading) {
            if city == .taipei, let frame, frame.opacity > 0 {
                Text(CityScenePlace.contextDataAvailable
                     ? "© OpenStreetMap contributors · ODbL"
                     : "Street data unavailable · 101 model only")
                    .font(.system(size: 9)).foregroundStyle(CityMVPStyle.ink)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(CityMVPStyle.panel.opacity(0.96), in: Capsule())
                    .padding(.leading, 16).padding(.top, 167)
                    .allowsHitTesting(false)
            }
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
    private var modeValue: String {
        let mode = shows3D ? "District" : "Map"
        guard CityDistrictTrace.enabled, let frame else { return mode }
        return "\(mode) \(Int(frame.distance))"
    }

    private var landmarkPoint: CGPoint? {
        guard let registration else { return nil }
        return proxy.convert(registration.mapCoordinate(CityDistrictCamera.coordinate(x: 0, z: 0)),
                             to: .named(CityDistrictCamera.space))
    }

    private var placePins: some View {
        GeometryReader { geometry in
            if let frame {
                if registration != nil, frame.distance < 3_800 {
                    ForEach(places.filter { place in
                        CityMVPPlaceBridge.showsContextPin(place.id, in: frame) && place.id != selectedContextID
                    }) { place in
                        if let point = projected(latitude: place.latitude, longitude: place.longitude, registered: true, in: geometry.size) {
                            Button { select(place.id) } label: {
                                CityPinArtwork(id: place.id, title: place.title, symbol: contextSymbol(place.category),
                                               saved: place.isSaved, selected: false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(place.title)
                            .accessibilityValue(place.isSaved ? "Map Stamp" : "Unsaved place")
                            .accessibilityIdentifier("cityMVP.groundPin.\(place.id)")
                            .position(x: point.x, y: point.y - CityPinArtwork.height / 2)
                        }
                    }
                }
                if let selection = selectedPin,
                   let point = projected(latitude: selection.latitude, longitude: selection.longitude, registered: selection.registered, in: geometry.size) {
                    CityPinArtwork(id: selectedContextID, title: selection.title, symbol: selection.symbol,
                                   saved: viewModel.selectedPlace != nil, selected: true)
                        .id(selection.identity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(selection.title)
                        .accessibilityValue(viewModel.selectedPlace != nil ? "Map Stamp" : "Unsaved place")
                        .accessibilityIdentifier("cityMVP.selectedGroundPin")
                        .position(x: point.x, y: point.y - CityPinArtwork.height / 2)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var selectedContextID: String? {
        if let saved = viewModel.selectedPlace {
            return context.first { CityMVPPlaceBridge.savedMatch(for: $0, in: [saved]) != nil }?.id
        }
        return viewModel.selectedMapCandidate?.id.hasPrefix("city-mvp:") == true
            ? viewModel.selectedMapCandidate.map { String($0.id.dropFirst(9)) } : nil
    }

    private var selectedPin: (identity: String, title: String, latitude: Double, longitude: Double, symbol: String, registered: Bool)? {
        if let place = viewModel.selectedPlace, place.isMapKitMappable {
            return (String(describing: place.id), place.name, place.latitude, place.longitude, "bookmark.fill",
                    CityMVPPlaceBridge.hasBundledCoordinate(place))
        }
        if let candidate = viewModel.selectedMapCandidate {
            return (candidate.id, candidate.title, candidate.latitude, candidate.longitude, "mappin",
                    candidate.id.hasPrefix("city-mvp:"))
        }
        return nil
    }

    private func projected(latitude: Double, longitude: Double, registered: Bool, in size: CGSize) -> CGPoint? {
        let source = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let native = registered ? registration?.mapCoordinate(source) ?? source : source
        guard let point = proxy.convert(native, to: .named(CityDistrictCamera.space)),
              point.x.isFinite, point.y.isFinite,
              CGRect(origin: .zero, size: size).contains(point) else { return nil }
        return point
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

    private func mapShortcut(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).frame(minHeight: 44)
                .cityMVPGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cityMVP.\(id)")
    }

    private var registeredTaipei: MapCamera {
        let camera = CityMVPCameras.taipei
        let coordinate = registration?.mapCoordinate(camera.centerCoordinate) ?? camera.centerCoordinate
        return MapCamera(centerCoordinate: coordinate, distance: camera.distance, heading: camera.heading, pitch: camera.pitch)
    }

    private func openAppleMap(at camera: MapCamera) {
        city = .taipei
        viewModel.clearSelectedMapObject()
        withAnimation(SaveTheme.Motion.standardSpring) {
            viewModel.cameraPosition = .camera(camera)
        }
    }

    private func openCorner(_ coordinate: CLLocationCoordinate2D) {
        guard let registration else { return }
        city = .taipei
        withAnimation(.easeInOut(duration: 0.55)) {
            viewModel.cameraPosition = .camera(MapCamera(centerCoordinate: registration.mapCoordinate(coordinate), distance: 550,
                                                         heading: 0, pitch: 49))
        }
    }

    private func zoomToDistrict(_ closer: Bool) {
        guard let registration else { return }
        let current = frame?.mapCamera ?? registeredTaipei
        let offset = CityDistrictCamera.world(registration.sceneCoordinate(current.centerCoordinate))
        let isLocal = max(abs(offset.x), abs(offset.z)) < 450
        let camera = (isLocal || !closer) ? current : registeredTaipei
        let next = MapCamera(centerCoordinate: camera.centerCoordinate,
                             distance: closer ? 1_450 : 2_900,
                             heading: camera.heading, pitch: camera.pitch)
        withAnimation(.easeInOut(duration: 0.55)) {
            viewModel.cameraPosition = .camera(next)
        }
    }

    private func openAgentPlace(_ place: Place) {
        city = .taipei
        if place.isMapKitMappable {
            let coordinate = CityMVPPlaceBridge.hasBundledCoordinate(place)
                ? registration?.mapCoordinate(place.coordinate) ?? place.coordinate
                : place.coordinate
            viewModel.cameraPosition = .camera(MapCamera(centerCoordinate: coordinate,
                                                         distance: 900, heading: 0, pitch: 30))
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
        if let saved = CityMVPPlaceBridge.savedMatch(for: place, in: viewModel.places) {
            viewModel.selectPlace(saved, enrichPhoto: false)
        } else {
            // Preserve Savvy's real unsaved-candidate drawer, without network enrichment
            // or location prompts based on illustrative OSM geometry.
            viewModel.clearSelectedMapObject()
            viewModel.selectedMapCandidate = CityMVPPlaceBridge.candidate(for: place)
        }
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
                openAppleMap(at: registeredTaipei)
                zoomToDistrict(true)
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
#endif
