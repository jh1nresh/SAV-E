import CoreLocation
import MapKit
import SwiftUI

// MARK: - Motion (spec §6; analysis.md §2)

enum SavvyMapMotion {
    static let badge = Animation.spring(response: 0.46, dampingFraction: 0.61)
    static let cardOpen = Animation.spring(response: 0.46, dampingFraction: 0.74)
    static let cardClose = Animation.spring(response: 0.51, dampingFraction: 0.86)
    static let flipBack = Animation.spring(response: 0.54, dampingFraction: 1.0)
    static let flipFront = Animation.spring(response: 0.57, dampingFraction: 0.76)
    static let camera = Animation.spring(response: 1.05, dampingFraction: 0.76)
    static let reduceMotion = Animation.easeInOut(duration: 0.25)

    static func badge(reduceMotion: Bool) -> Animation { reduceMotion ? Self.reduceMotion : badge }
    static func cardOpen(reduceMotion: Bool) -> Animation { reduceMotion ? Self.reduceMotion : cardOpen }
    static func cardClose(reduceMotion: Bool) -> Animation { reduceMotion ? Self.reduceMotion : cardClose }
    static func flipBack(reduceMotion: Bool) -> Animation { reduceMotion ? Self.reduceMotion : flipBack }
    static func flipFront(reduceMotion: Bool) -> Animation { reduceMotion ? Self.reduceMotion : flipFront }
    static func camera(reduceMotion: Bool) -> Animation { reduceMotion ? Self.reduceMotion : camera }
}

// MARK: - Metrics (spec §2–§5)

enum SavvyMapPinMetrics {
    static let smallPinOuter: CGFloat = 40
    static let smallPinPaperStroke: CGFloat = 4
    static let smallPinVisitedOuter: CGFloat = 45
    static let smallPinNoPhotoOuter: CGFloat = 20
    static let smallPinNoPhotoPaperStroke: CGFloat = 3
    static let visitedRing: CGFloat = 2.5
    static let hitTarget: CGFloat = 44

    static let badgeWidth: CGFloat = 89
    static let badgeHeight: CGFloat = 104
    static let badgeStickerWidth: CGFloat = 89
    static let badgeStickerHeight: CGFloat = 81
    static let badgePhoto: CGFloat = 59
    static let badgeLabelReserve: CGFloat = 14
    static let badgeTail: CGFloat = 17
    static let badgeScaleFromPin = smallPinOuter / badgeWidth

    static let cardWidthFraction: CGFloat = 0.845
    static let cardWidth: CGFloat = 332
    static let cardHeight: CGFloat = 400
    static let cardTail: CGFloat = 12
    static let cardCorner: CGFloat = 26
    static let cardPhotoHeight: CGFloat = 236
    static let cardPhotoInset: CGFloat = 10
    static let cardPhotoCorner: CGFloat = 18
    static let cardButtonHeight: CGFloat = 48
    static let cardScaleFromBadge = badgeWidth / cardWidth
    static let cardCenterOffsetY = (cardHeight + cardTail) / 2

    static let pinShadowOpacity: Double = 0.45
    static let pinShadowRadius: CGFloat = 4
    static let pinShadowY: CGFloat = 1
    static let badgeShadowRadius: CGFloat = 3
    static let cardShadowOpacity: Double = 0.35
    static let cardShadowRadius: CGFloat = 30
    static let cardShadowY: CGFloat = 10

    static let collapseDrag: CGFloat = 60
    static let cameraDelay: TimeInterval = 0.05
    static let pinScreenYFraction: CGFloat = 0.725
}

// MARK: - Q1b / P16 photo policy

/// HoP 圖釘照片定案: saved pins default to coral. A pin becomes a photo only
/// when someone has shared a photo of that place in Savvy. No Google Places
/// photos (terms forbid Places content on a non-Google map). Social/OG scrape
/// URLs are never pin art. The existing business-photo enricher is left
/// untouched.
///
/// This PR: own shared-post photos (`/v0/shared-posts/mine` +
/// `/v0/shared-posts/{id}/photos/{n}`), then a friend-photo hook, then coral.
/// Friend-shared photos are stubbed — `SharedPlacePost` has no place id,
/// coordinates, or Google id; there is no per-place friend-photo API; the
/// pending `shared-post-photos.sql` migration may be unapplied. The feed
/// already respects follow/share visibility, but cannot bind a photo to a
/// Map Stamp without those identity fields.
///
/// P14: unsaved places never resolve a pin photo.
/// P15: load failure stays coral — never a broken-image glyph.
enum SavvyMapPhotoOrigin: Equatable {
    case own
    case friend
    case none
}

struct SavvyMapSharedPhotoRef: Equatable {
    var origin: SavvyMapPhotoOrigin
    var postID: UUID
    var photoIndex: Int
}

struct SavvyMapResolvedPhoto: Equatable {
    var origin: SavvyMapPhotoOrigin
    var url: URL?
    var shared: SavvyMapSharedPhotoRef?

    static let coral = SavvyMapResolvedPhoto(origin: .none, url: nil, shared: nil)
}

enum SavvyMapPhotoLoadState: Equatable {
    case missing
    case loading
    case loaded
    case failed
}

enum SavvyMapPhotoDisplay: Equatable {
    case photo
    case coral

    static func surface(for state: SavvyMapPhotoLoadState) -> SavvyMapPhotoDisplay {
        state == .loaded ? .photo : .coral
    }

    static var hidesBrokenImageOnFailure: Bool { true }
}

enum SavvyMapPhotoPolicy {
    static func resolvedPhoto(
        for place: Place,
        isConfirmedSaved: Bool,
        ownPosts: [SharedPlacePost] = [],
        friendPosts: [SharedPlacePost] = []
    ) -> SavvyMapResolvedPhoto {
        guard isConfirmedSaved else { return .coral }
        if let own = firstOwnSharedPhoto(in: ownPosts, matching: place) {
            return SavvyMapResolvedPhoto(origin: .own, url: nil, shared: own)
        }
        if let friend = firstFriendSharedPhoto(in: friendPosts, matching: place) {
            return SavvyMapResolvedPhoto(origin: .friend, url: nil, shared: friend)
        }
        return .coral
    }

    static func licensedPhotoURL(for place: Place, isConfirmedSaved: Bool = true) -> URL? {
        resolvedPhoto(for: place, isConfirmedSaved: isConfirmedSaved).url
    }

    /// `Place` has no user-photo field. Own pin art comes from shared posts.
    static func userAlbumPhotoURLs(for place: Place) -> [URL] {
        _ = place
        return []
    }

    static func firstOwnSharedPhoto(
        in posts: [SharedPlacePost],
        matching place: Place
    ) -> SavvyMapSharedPhotoRef? {
        posts.first { post in
            (post.photo_count ?? 0) > 0 && matches(post, place: place)
        }.map {
            SavvyMapSharedPhotoRef(origin: .own, postID: $0.id, photoIndex: 0)
        }
    }

    /// Reserved hook. Always empty in this PR — see file header for why.
    static func firstFriendSharedPhoto(
        in posts: [SharedPlacePost],
        matching place: Place
    ) -> SavvyMapSharedPhotoRef? {
        _ = (posts, place)
        return nil
    }

    static func matches(_ post: SharedPlacePost, place: Place) -> Bool {
        place.matches(
            Place(
                id: post.id,
                name: post.name,
                address: post.address,
                latitude: 0,
                longitude: 0,
                googlePlaceId: nil,
                category: PlaceCategory(rawValue: post.category) ?? place.category,
                status: post.status,
                rating: post.stars,
                note: nil,
                sourceUrl: nil,
                sourcePlatform: .other,
                sourceImageUrl: nil,
                extractedDishes: nil,
                priceRange: nil,
                recommender: nil,
                googleRating: nil,
                googlePriceLevel: nil,
                openingHours: nil,
                createdAt: Date(timeIntervalSince1970: 0)
            )
        )
    }
}

/// Memory-only thumbnails for own shared-post pin photos. Never writes
/// follower/own share bytes into the public/disk image cache.
@MainActor
final class SavvyMapSharedPinPhotoStore: ObservableObject {
    static let shared = SavvyMapSharedPinPhotoStore()

    @Published private(set) var ownPosts: [SharedPlacePost] = []
    @Published private(set) var images: [String: UIImage] = [:]
    private var failedKeys: Set<String> = []
    private var inFlight: Set<String> = []

    func refreshOwnPosts(using service: SupabaseService = .shared) async {
        guard !PrivyAuthService.shared.isReviewerDemo,
              PrivyAuthService.shared.currentUserId != nil else {
            ownPosts = []
            return
        }
        do {
            ownPosts = try await service.fetchSharedPosts(mine: true, filter: .all, cursor: nil).items
        } catch {
            return
        }
    }

    func image(for place: Place) -> UIImage? {
        guard let ref = SavvyMapPhotoPolicy.resolvedPhoto(
            for: place,
            isConfirmedSaved: true,
            ownPosts: ownPosts
        ).shared else { return nil }
        return images[cacheKey(ref)]
    }

    func loadIfNeeded(for place: Place, using service: SupabaseService = .shared) async {
        let resolved = SavvyMapPhotoPolicy.resolvedPhoto(
            for: place,
            isConfirmedSaved: true,
            ownPosts: ownPosts
        )
        guard resolved.origin == .own, let ref = resolved.shared else { return }
        let key = cacheKey(ref)
        guard images[key] == nil, !failedKeys.contains(key), inFlight.insert(key).inserted else { return }
        defer { inFlight.remove(key) }
        do {
            let data = try await service.fetchSharedPostPhoto(id: ref.postID, index: ref.photoIndex)
            guard let decoded = UIImage(data: data) else {
                failedKeys.insert(key)
                return
            }
            images[key] = decoded
        } catch {
            failedKeys.insert(key)
        }
    }

    private func cacheKey(_ ref: SavvyMapSharedPhotoRef) -> String {
        "\(ref.postID.uuidString)-\(ref.photoIndex)"
    }
}

/// P14: saved vs unsaved must be distinguishable at a glance.
/// Only user-confirmed saved Map Stamps get Savvy pins. Unsaved Apple POIs,
/// review candidates, and friend-social places stay as native MapKit markers
/// even when a photo URL exists. Tapping an unsaved POI uses `selectMapFeature`
/// → the existing unsaved-candidate save flow. After the user confirms, the
/// stamp is in `MapViewModel.places` and appears immediately as a Savvy pin.
enum SavvyMapPinKind: Equatable {
    case savvyPin
    case nativeApplePOI
}

enum SavvyMapStampPolicy {
    static func pinKind(isConfirmedSaved: Bool, hasPhotoURL: Bool) -> SavvyMapPinKind {
        _ = hasPhotoURL
        return isConfirmedSaved ? .savvyPin : .nativeApplePOI
    }

    static func qualifiesForSavvyPin(_ place: Place, confirmedPlaces: [Place]) -> Bool {
        place.isMapKitMappable && confirmedPlaces.contains { $0.savedIDs.contains(place.id) }
    }

    static func friendLensPins(confirmedPlaces: [Place], socialPlaces: [Place]) -> [Place] {
        confirmedPlaces.filter { saved in
            guard saved.isMapKitMappable else { return false }
            if saved.socialSignal != nil { return true }
            return socialPlaces.contains { saved.matches($0) }
        }
    }

    static func includingSelectedSavedPin(
        _ pins: [Place],
        selected: Place?,
        confirmedPlaces: [Place]
    ) -> [Place] {
        guard let selected,
              qualifiesForSavvyPin(selected, confirmedPlaces: confirmedPlaces),
              !pins.contains(where: { $0.id == selected.id }) else {
            return pins
        }
        return pins + [selected]
    }
}

// MARK: - Zoom hysteresis + stagger (spec §3)

enum SavvyMapZoomHysteresis {
    static let badgeAtOrBelow: CLLocationDegrees = 0.02
    static let pinAbove: CLLocationDegrees = 0.025
    static let staggerPerHundredPoints: TimeInterval = 0.04
    static let staggerCap: TimeInterval = 0.12

    static func showsBadge(latitudeDelta: CLLocationDegrees, currentlyBadge: Bool) -> Bool {
        if currentlyBadge {
            return latitudeDelta <= pinAbove
        }
        return latitudeDelta <= badgeAtOrBelow
    }

    static func staggerDelay(distanceFromCenter: CGFloat) -> TimeInterval {
        min(staggerCap, max(0, Double(distanceFromCenter / 100) * staggerPerHundredPoints))
    }
}

enum SavvyMapCameraFocus {
    static func center(
        for pin: CLLocationCoordinate2D,
        latitudeDelta: CLLocationDegrees
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: pin.latitude + 0.225 * latitudeDelta,
            longitude: pin.longitude
        )
    }
}

enum SavvyMapEatGo: String {
    case eat = "Eat"
    case go = "Go"

    func label(language: AppLanguage) -> String {
        switch self {
        case .eat:
            return language.localized(english: "Eat", traditionalChinese: "Eat")
        case .go:
            return language.localized(english: "Go", traditionalChinese: "Go")
        }
    }
}

extension PlaceCategory {
    var savvyEatGo: SavvyMapEatGo {
        switch self {
        case .food, .cafe, .bar:
            return .eat
        case .attraction, .stay, .shopping:
            return .go
        }
    }
}

// MARK: - Visit log (P7)

final class SavvyMapVisitStore: ObservableObject, @unchecked Sendable {
    static let shared = SavvyMapVisitStore()

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, key: String = "savvy.map.visits.v1") {
        self.defaults = defaults
        self.key = key
    }

    func visits(for placeID: UUID) -> [Date] {
        lock.lock()
        defer { lock.unlock() }
        return stored()[placeID.uuidString, default: []].map { Date(timeIntervalSince1970: $0) }
    }

    func visitCount(for placeID: UUID, fallbackVisited: Bool) -> Int {
        let count = visits(for: placeID).count
        if count > 0 { return count }
        return fallbackVisited ? 1 : 0
    }

    func lastVisit(for placeID: UUID, fallback: Date?) -> Date? {
        visits(for: placeID).max() ?? fallback
    }

    @discardableResult
    func recordVisit(placeID: UUID, at date: Date = Date()) -> Int {
        lock.lock()
        var values = stored()
        var stamps = values[placeID.uuidString, default: []]
        stamps.append(date.timeIntervalSince1970)
        values[placeID.uuidString] = stamps
        defaults.set(values, forKey: key)
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
        return stamps.count
    }

    private func stored() -> [String: [TimeInterval]] {
        defaults.dictionary(forKey: key) as? [String: [TimeInterval]] ?? [:]
    }
}

// MARK: - Card session (P3–P6)

enum SavvyMapCollapsePlan: Equatable {
    case idle
    case close
    case flipThenClose
}

struct SavvyMapCardSession: Equatable {
    var placeID: UUID?
    var isOpen = false
    var isFlipped = false
    var dragTranslation: CGFloat = 0

    mutating func select(_ id: UUID) {
        placeID = id
        isOpen = true
        isFlipped = false
        dragTranslation = 0
    }

    mutating func toggleFlip() {
        guard isOpen else { return }
        isFlipped.toggle()
    }

    mutating func requestCollapse() -> SavvyMapCollapsePlan {
        guard isOpen else { return .idle }
        if isFlipped { return .flipThenClose }
        return .close
    }

    mutating func finishCollapseAfterFlip() {
        closeNow()
    }

    mutating func applyDrag(_ translation: CGFloat) {
        dragTranslation = max(0, translation)
    }

    mutating func endDrag() -> SavvyMapCollapsePlan {
        let shouldCollapse = dragTranslation > SavvyMapPinMetrics.collapseDrag
        dragTranslation = 0
        return shouldCollapse ? requestCollapse() : .idle
    }

    private mutating func closeNow() {
        isOpen = false
        isFlipped = false
        placeID = nil
        dragTranslation = 0
    }
}

struct SavvyMapCardBackModel: Equatable {
    var note: String?
    var albumURLs: [URL]
    var visitCount: Int
    var lastVisit: Date?
    var address: String
    var openingHours: String?

    var showsNotePrompt: Bool {
        (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var showsAlbum: Bool { !albumURLs.isEmpty }
    var albumOverflow: Int { max(0, albumURLs.count - 3) }
    var visibleAlbumURLs: [URL] { Array(albumURLs.prefix(3)) }

    var showsHours: Bool {
        !(openingHours ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasVisited: Bool { visitCount > 0 }

    static func make(
        place: Place,
        visits: SavvyMapVisitStore
    ) -> SavvyMapCardBackModel {
        let fallbackDate = place.status == .visited ? place.createdAt : nil
        return SavvyMapCardBackModel(
            note: place.userFacingNote,
            albumURLs: SavvyMapPhotoPolicy.userAlbumPhotoURLs(for: place),
            visitCount: visits.visitCount(
                for: place.id,
                fallbackVisited: place.status == .visited
            ),
            lastVisit: visits.lastVisit(
                for: place.id,
                fallback: fallbackDate
            ),
            address: place.address,
            openingHours: place.openingHours
        )
    }
}

// MARK: - Pin

struct SavvyMapPhotoPinView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var sharedPhotos = SavvyMapSharedPinPhotoStore.shared
    let place: Place
    var showsBadge: Bool
    var isVisited: Bool
    var isSelected: Bool
    var reduceMotion: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            SaveHaptics.select()
            onTap()
        } label: {
            pinBody
                .opacity(isSelected ? 0 : 1)
                .frame(
                    width: SavvyMapPinMetrics.badgeWidth,
                    height: SavvyMapPinMetrics.badgeHeight,
                    alignment: .bottom
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(pinLabel)
        .accessibilityIdentifier("map.pin.saved.\(place.id.uuidString)")
        .zIndex(-place.latitude)
        .task(id: place.id) {
            await sharedPhotos.loadIfNeeded(for: place)
        }
    }

    @ViewBuilder
    private var pinBody: some View {
        ZStack(alignment: .bottom) {
            smallPin
                .opacity(showsBadge ? 0 : 1)
                .transaction { $0.animation = nil }

            badge
                .scaleEffect(
                    reduceMotion ? 1 : (showsBadge ? 1 : SavvyMapPinMetrics.badgeScaleFromPin),
                    anchor: .bottom
                )
                .opacity(showsBadge ? 1 : 0)
        }
        .frame(
            width: SavvyMapPinMetrics.badgeWidth,
            height: SavvyMapPinMetrics.badgeHeight,
            alignment: .bottom
        )
    }

    private var smallPin: some View {
        let outer = isVisited
            ? (hasPhoto ? SavvyMapPinMetrics.smallPinVisitedOuter : SavvyMapPinMetrics.smallPinNoPhotoOuter + SavvyMapPinMetrics.visitedRing * 2)
            : (hasPhoto ? SavvyMapPinMetrics.smallPinOuter : SavvyMapPinMetrics.smallPinNoPhotoOuter)
        return ZStack {
            if isVisited {
                Circle()
                    .stroke(SaveAtlasPalette.coral, lineWidth: SavvyMapPinMetrics.visitedRing)
                    .frame(width: outer, height: outer)
            }
            coralOrPhotoCircle(
                diameter: hasPhoto ? SavvyMapPinMetrics.smallPinOuter : SavvyMapPinMetrics.smallPinNoPhotoOuter,
                paperStroke: hasPhoto
                    ? SavvyMapPinMetrics.smallPinPaperStroke
                    : SavvyMapPinMetrics.smallPinNoPhotoPaperStroke
            )
        }
        .shadow(
            color: Color.black.opacity(SavvyMapPinMetrics.pinShadowOpacity),
            radius: SavvyMapPinMetrics.pinShadowRadius,
            y: SavvyMapPinMetrics.pinShadowY
        )
    }

    private var badge: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(SaveAtlasPalette.paper)
                    .frame(
                        width: SavvyMapPinMetrics.badgeStickerWidth,
                        height: SavvyMapPinMetrics.badgeStickerHeight
                    )
                    .shadow(
                        color: Color.black.opacity(SavvyMapPinMetrics.pinShadowOpacity),
                        radius: SavvyMapPinMetrics.badgeShadowRadius,
                        y: SavvyMapPinMetrics.pinShadowY
                    )

                coralOrPhotoCircle(diameter: SavvyMapPinMetrics.badgePhoto, paperStroke: 0)
                    .overlay {
                        if isVisited {
                            Circle()
                                .stroke(SaveAtlasPalette.coral, lineWidth: SavvyMapPinMetrics.visitedRing)
                                .frame(
                                    width: SavvyMapPinMetrics.badgePhoto + SavvyMapPinMetrics.visitedRing * 2,
                                    height: SavvyMapPinMetrics.badgePhoto + SavvyMapPinMetrics.visitedRing * 2
                                )
                        }
                    }
                    .padding(.top, 18)

                badgeLabel
                    .offset(y: -2)
            }
            SavvyMapCalloutTail(size: 9)
                .fill(SaveAtlasPalette.paper)
                .frame(width: 17, height: 9)
                .offset(y: -1)
        }
        .frame(width: SavvyMapPinMetrics.badgeWidth, height: SavvyMapPinMetrics.badgeHeight, alignment: .bottom)
    }

    @ViewBuilder
    private var badgeLabel: some View {
        let text = place.category.displayName(language: languageSettings.language)
        if dynamicTypeSize >= .xxxLarge {
            Text(text)
                .font(SaveAtlasType.strong(15))
                .foregroundStyle(SaveAtlasPalette.ink)
                .lineLimit(1)
                .padding(.horizontal, 8)
        } else {
            SavvyMapArcText(
                text: text,
                radius: 38,
                font: .system(size: 15, weight: .heavy, design: .rounded)
            )
            .foregroundStyle(SaveAtlasPalette.ink)
            .frame(width: 86, height: 28)
        }
    }

    private func coralOrPhotoCircle(diameter: CGFloat, paperStroke: CGFloat) -> some View {
        let inner = max(8, diameter - paperStroke * 2)
        return ZStack {
            Circle()
                .fill(SaveAtlasPalette.coral)
                .frame(width: inner, height: inner)
            SavvyMapPinPhotoFill(
                image: sharedPhotos.image(for: place),
                url: resolvedPhoto.url,
                diameter: inner
            )
            if paperStroke > 0 {
                Circle()
                    .stroke(SaveAtlasPalette.paper, lineWidth: paperStroke)
                    .frame(width: diameter, height: diameter)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var resolvedPhoto: SavvyMapResolvedPhoto {
        SavvyMapPhotoPolicy.resolvedPhoto(
            for: place,
            isConfirmedSaved: true,
            ownPosts: sharedPhotos.ownPosts
        )
    }

    private var hasPhoto: Bool {
        sharedPhotos.image(for: place) != nil
    }

    private var pinLabel: String {
        let category = place.category.displayName(language: languageSettings.language)
        let visit = isVisited
            ? languageSettings.localized(english: "visited", traditionalChinese: "去過")
            : languageSettings.localized(english: "not visited", traditionalChinese: "沒去過")
        return "\(place.name), \(category), \(visit)"
    }
}

/// P15: photo fill sits on coral. Loading and failure keep the coral —
/// never a broken-image glyph.
struct SavvyMapPinPhotoFill: View {
    var image: UIImage?
    var url: URL?
    let diameter: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.clear
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .allowsHitTesting(false)
    }
}

struct SavvyMapCalloutTail: Shape {
    var size: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - size, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + size, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct SavvyMapArcText: View {
    let text: String
    var radius: CGFloat
    var font: Font = .system(size: 15, weight: .heavy, design: .rounded)

    var body: some View {
        let characters = Array(text)
        let count = max(characters.count, 1)
        let spread = min(110, Double(count) * 16)
        ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                let t = count == 1 ? 0.5 : Double(index) / Double(count - 1)
                let angle = -spread / 2 + spread * t
                Text(String(character))
                    .font(font)
                    .rotationEffect(.degrees(angle))
                    .offset(y: -radius)
                    .rotationEffect(.degrees(angle))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Callout card

struct SavvyMapPlaceCard: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var visits: SavvyMapVisitStore
    @ObservedObject private var sharedPhotos = SavvyMapSharedPinPhotoStore.shared
    let place: Place
    let userLocation: CLLocation?
    var isOpen: Bool
    var isFlipped: Bool
    var reduceMotion: Bool
    var screenWidth: CGFloat
    let onFlip: () -> Void
    let onBeenHere: () -> Void
    let onDirections: () -> Void
    let onOpenDetail: () -> Void
    let onEditNote: () -> Void
    let onCollapse: () -> Void

    @AccessibilityFocusState private var nameFocused: Bool

    private var width: CGFloat {
        min(SavvyMapPinMetrics.cardWidth, screenWidth * SavvyMapPinMetrics.cardWidthFraction)
    }

    var body: some View {
        let back = SavvyMapCardBackModel.make(place: place, visits: visits)
        VStack(spacing: 0) {
            ZStack {
                if reduceMotion {
                    if isFlipped {
                        backFace(back)
                    } else {
                        frontFace
                    }
                } else {
                    frontFace
                        .opacity(isFlipped ? 0 : 1)
                        .rotation3DEffect(
                            .degrees(isFlipped ? 180 : 0),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.5
                        )
                    backFace(back)
                        .opacity(isFlipped ? 1 : 0)
                        .rotation3DEffect(
                            .degrees(isFlipped ? 0 : -180),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.5
                        )
                }
            }
            .frame(width: width, height: SavvyMapPinMetrics.cardHeight)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: SavvyMapPinMetrics.cardCorner, style: .continuous))
            .shadow(
                color: Color.black.opacity(SavvyMapPinMetrics.cardShadowOpacity),
                radius: SavvyMapPinMetrics.cardShadowRadius,
                y: SavvyMapPinMetrics.cardShadowY
            )

            SavvyMapCalloutTail(size: 10)
                .fill(SaveAtlasPalette.paper)
                .frame(width: 22, height: SavvyMapPinMetrics.cardTail)
                .offset(y: -1)
        }
        .scaleEffect(
            reduceMotion ? 1 : (isOpen ? 1 : SavvyMapPinMetrics.cardScaleFromBadge),
            anchor: .bottom
        )
        .opacity(reduceMotion ? (isOpen ? 1 : 0) : 1)
        .frame(width: width, height: SavvyMapPinMetrics.cardHeight + SavvyMapPinMetrics.cardTail)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.card")
        .accessibilityAction(.escape, onCollapse)
        .accessibilityAction(
            named: languageSettings.localized(english: "See details", traditionalChinese: "看細節"),
            onFlip
        )
        .onAppear { nameFocused = true }
        .onChange(of: place.id) { _, _ in nameFocused = true }
        .task(id: place.id) {
            await sharedPhotos.loadIfNeeded(for: place)
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height > SavvyMapPinMetrics.collapseDrag {
                        onCollapse()
                    }
                }
        )
    }

    private var frontFace: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .top) {
                photoWell
                categorySticker
                    .offset(y: -14)
            }

            Text(metaLine)
                .font(SaveAtlasType.body(15))
                .foregroundStyle(SaveAtlasPalette.muted)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("map.peek.subtitle")

            HStack(spacing: 12) {
                Button(action: onDirections) {
                    Text("Directions")
                        .font(SaveAtlasType.strong(16))
                        .foregroundStyle(SaveAtlasPalette.paper)
                        .frame(maxWidth: .infinity, minHeight: SavvyMapPinMetrics.cardButtonHeight)
                        .background(SaveAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.card.directions")

                Button(action: onBeenHere) {
                    Text(languageSettings.localized(english: "I've been here", traditionalChinese: "我來過了"))
                        .font(SaveAtlasType.strong(16))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .frame(maxWidth: .infinity, minHeight: SavvyMapPinMetrics.cardButtonHeight)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(SaveAtlasPalette.ink, lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.card.beenHere")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFlip)
    }

    private var photoWell: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: SavvyMapPinMetrics.cardPhotoCorner, style: .continuous)
                .fill(SaveAtlasPalette.ink.opacity(0.08))
            Circle()
                .fill(SaveAtlasPalette.coral)
                .frame(width: 72, height: 72)
            if let image = sharedPhotos.image(for: place) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(
                        RoundedRectangle(cornerRadius: SavvyMapPinMetrics.cardPhotoCorner, style: .continuous)
                    )
            }
            LinearGradient(
                colors: [.clear, SaveAtlasPalette.ink.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: SavvyMapPinMetrics.cardPhotoCorner, style: .continuous))

            Button(action: onOpenDetail) {
                Text(place.name)
                    .font(SaveAtlasType.strong(22))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("map.peek.name")
                    .accessibilityFocused($nameFocused)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("map.peek.card")
            .padding(16)
        }
        .frame(height: SavvyMapPinMetrics.cardPhotoHeight)
        .padding(SavvyMapPinMetrics.cardPhotoInset)
        .accessibilityElement(children: .contain)
    }

    private var categorySticker: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(SaveAtlasPalette.coral)
                .frame(width: 14, height: 14)
            Text(place.category.displayName(language: languageSettings.language))
                .font(SaveAtlasType.strong(14))
                .foregroundStyle(SaveAtlasPalette.ink)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
        .background(SaveAtlasPalette.paper, in: Capsule())
        .overlay {
            Capsule().stroke(SaveAtlasPalette.line.opacity(0.7), lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func backFace(_ back: SavvyMapCardBackModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onEditNote) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(languageSettings.localized(english: "My notes", traditionalChinese: "我的筆記"))
                            .font(SaveDisplayType.display(30))
                            .foregroundStyle(SaveAtlasPalette.forest)
                        Text(
                            back.showsNotePrompt
                                ? languageSettings.localized(english: "Write something…", traditionalChinese: "寫點什麼…")
                                : (back.note ?? "")
                        )
                        .font(SaveAtlasType.body(15))
                        .foregroundStyle(back.showsNotePrompt ? SaveAtlasPalette.muted : SaveAtlasPalette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.card.note")

                if back.showsAlbum {
                    albumRow(back)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(languageSettings.localized(english: "Visits", traditionalChinese: "去過紀錄"))
                        .font(SaveAtlasType.strong(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                    Text(visitLine(back))
                        .font(SaveAtlasType.body(15))
                        .foregroundStyle(SaveAtlasPalette.ink)
                }
                .accessibilityIdentifier("map.card.visits")

                if !back.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(back.address)
                        .font(SaveAtlasType.body(15))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .accessibilityIdentifier("map.card.address")
                }

                if back.showsHours, let hours = back.openingHours {
                    Text(hours)
                        .font(SaveAtlasType.body(15))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .accessibilityIdentifier("map.card.hours")
                }

                Button(action: onDirections) {
                    Text("Directions")
                        .font(SaveAtlasType.strong(16))
                        .foregroundStyle(SaveAtlasPalette.paper)
                        .frame(maxWidth: .infinity, minHeight: SavvyMapPinMetrics.cardButtonHeight)
                        .background(SaveAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.card.back.directions")
            }
            .padding(20)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFlip)
    }

    private func albumRow(_ back: SavvyMapCardBackModel) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(back.visibleAlbumURLs.enumerated()), id: \.offset) { _, _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SaveAtlasPalette.kraft)
                    .frame(width: 72, height: 72)
            }
            if back.albumOverflow > 0 {
                Text("+\(back.albumOverflow)")
                    .font(SaveAtlasType.strong(16))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .frame(width: 72, height: 72)
                    .background(SaveAtlasPalette.kraft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .accessibilityIdentifier("map.card.album")
    }

    private var cardBackground: some View {
        SaveAtlasPalette.paper
            .overlay {
                Image("PaperGrain")
                    .resizable(resizingMode: .tile)
                    .opacity(0.18)
                    .allowsHitTesting(false)
            }
    }

    private var metaLine: String {
        let category = place.category.displayName(language: languageSettings.language)
        let eatGo = place.category.savvyEatGo.label(language: languageSettings.language)
        if let distance = formattedDistance {
            return "\(category) · \(eatGo) · \(distance)"
        }
        return "\(category) · \(eatGo)"
    }

    private var formattedDistance: String? {
        guard let userLocation else { return nil }
        let meters = userLocation.distance(
            from: CLLocation(latitude: place.latitude, longitude: place.longitude)
        )
        if meters < 1000 {
            return "\(Int(meters.rounded()))m"
        }
        return String(format: "%.1fkm", meters / 1000)
    }

    private func visitLine(_ back: SavvyMapCardBackModel) -> String {
        guard back.hasVisited else {
            return languageSettings.localized(english: "Not visited yet", traditionalChinese: "還沒來過")
        }
        let count = back.visitCount
        let date = back.lastVisit?.formatted(date: .abbreviated, time: .omitted) ?? ""
        if languageSettings.language == .traditionalChinese {
            return date.isEmpty ? "去過 \(count) 次" : "去過 \(count) 次 · 最近 \(date)"
        }
        return date.isEmpty ? "Visited \(count) time\(count == 1 ? "" : "s")" : "Visited \(count) time\(count == 1 ? "" : "s") · last \(date)"
    }
}
