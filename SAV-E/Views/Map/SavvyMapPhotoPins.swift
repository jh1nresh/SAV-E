import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Motion (spec §6; analysis.md §2)

enum SavvyMapMotion {
    static let badge = Animation.spring(response: 0.46, dampingFraction: 0.61)
    static let cardOpen = Animation.spring(response: 0.46, dampingFraction: 0.74)
    static let cardClose = Animation.spring(response: 0.51, dampingFraction: 0.86)
    static let flipBack = Animation.spring(response: 0.54, dampingFraction: 1.0)
    static let flipFront = Animation.spring(response: 0.57, dampingFraction: 0.76)
    static let camera = Animation.spring(response: 1.05, dampingFraction: 0.76)
    static let reduceMotion = Animation.easeInOut(duration: 0.25)

    static func usesQuarterSecondFade(_ reduceMotion: Bool) -> Bool { reduceMotion }

    static func badge(reduceMotion: Bool) -> Animation { usesQuarterSecondFade(reduceMotion) ? Self.reduceMotion : badge }
    static func cardOpen(reduceMotion: Bool) -> Animation { usesQuarterSecondFade(reduceMotion) ? Self.reduceMotion : cardOpen }
    static func cardClose(reduceMotion: Bool) -> Animation { usesQuarterSecondFade(reduceMotion) ? Self.reduceMotion : cardClose }
    static func flipBack(reduceMotion: Bool) -> Animation { usesQuarterSecondFade(reduceMotion) ? Self.reduceMotion : flipBack }
    static func flipFront(reduceMotion: Bool) -> Animation { usesQuarterSecondFade(reduceMotion) ? Self.reduceMotion : flipFront }
    static func camera(reduceMotion: Bool) -> Animation { usesQuarterSecondFade(reduceMotion) ? Self.reduceMotion : camera }
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
    static let badgeStickerHeight: CGFloat = 89
    static let badgePhoto: CGFloat = 59
    static let badgeLabelReserve: CGFloat = 14
    /// Paper-circle center. `-sticker/2 + this` is 0 so the English arc is concentric.
    static let badgeArcLabelOffsetY: CGFloat = badgeStickerWidth / 2
    /// Word-path lift from the paper center. Do not share the arc offset.
    static let badgeWordLabelOffsetY: CGFloat = -32
    /// Extra lift on the CJK word so the top edge clears the paper rim.
    static let badgeWordLabelExtraLift: CGFloat = 5.5
    /// Photo circle sits this far below the paper center.
    static let badgePhotoOffsetY: CGFloat = 8
    static let badgeArcFontSize: CGFloat = 13
    static let badgeTail: CGFloat = 17
    static let badgeScaleFromPin = smallPinOuter / badgeWidth
    /// Gate 5: paper badge base is a circle (capsule-equivalent when square).
    static let badgeBaseIsCircle = true
    static let cardCoralIcon: CGFloat = 64

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
/// photos (terms forbid Places content on a non-Google map). Do not use
/// `sourceImageUrl` or `businessPhotoUrls`. The business-photo enricher is
/// left untouched.
///
/// Own photo = the user's own shared-post photos
/// (`friend_restaurant_ratings` via `/v0/shared-posts/{id}/photos/{n}`,
/// existing permission checks). Thumbnail cache TTL is 1 hour; a withdrawn
/// share disappears on the next refresh (≤1h). This PR cannot bind those
/// photos to a saved `Place`: `SharedPlacePost` has no place id, Google id,
/// or coordinates, and name/address guessing is not a bind. Pins stay coral.
/// Friend photos stay a stub for a later PR. No backend/schema changes.
///
/// Photo chain: own → friend → coral.
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

enum SavvyMapOwnPhotoSource {
    static let endpointPath = "/v0/shared-posts/{id}/photos/{n}"
    static let thumbnailCacheTTL: TimeInterval = 60 * 60
    static let readsSourceImageURL = false
    static let readsBusinessPhotoURLs = false

    static let missingPlaceBindFields = [
        "SharedPlacePost.place_id",
        "SharedPlacePost.google_place_id",
        "SharedPlacePost.latitude/longitude",
    ]

    static func canBindToSavedPlace(_ post: SharedPlacePost) -> Bool {
        _ = post
        return false
    }

    static func isThumbnailFresh(storedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(storedAt) < thumbnailCacheTTL
    }
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

    /// `Place` has no user-photo field. Never read Google `businessPhotoUrls`
    /// or `sourceImageUrl`.
    static func userAlbumPhotoURLs(for place: Place) -> [URL] {
        _ = place
        return []
    }

    /// Own shared-post photos cannot be joined to `Place` without a place id
    /// on `SharedPlacePost`. Do not guess from name/address.
    static func firstOwnSharedPhoto(
        in posts: [SharedPlacePost],
        matching place: Place
    ) -> SavvyMapSharedPhotoRef? {
        _ = place
        guard let post = posts.first(where: { ($0.photo_count ?? 0) > 0 && SavvyMapOwnPhotoSource.canBindToSavedPlace($0) }) else {
            return nil
        }
        return SavvyMapSharedPhotoRef(origin: .own, postID: post.id, photoIndex: 0)
    }

    /// Friend-photo hook. Empty in this PR — needs a later backend PR.
    static func firstFriendSharedPhoto(
        in posts: [SharedPlacePost],
        matching place: Place
    ) -> SavvyMapSharedPhotoRef? {
        _ = (posts, place)
        return nil
    }
}

/// Memory-only own-share thumbnails. TTL is 1 hour; withdrawn shares drop
/// on the next refresh. This PR never fills the cache because own posts
/// cannot be bound to a `Place` without backend identity fields.
@MainActor
final class SavvyMapSharedPinPhotoStore: ObservableObject {
    static let shared = SavvyMapSharedPinPhotoStore()

    @Published private(set) var ownPosts: [SharedPlacePost] = []
    private var thumbnails: [String: (image: UIImage, storedAt: Date)] = [:]

    func refreshOwnPosts() async {
        let liveIDs = Set(ownPosts.map(\.id))
        thumbnails = thumbnails.filter { key, _ in
            liveIDs.contains(where: { key.hasPrefix($0.uuidString) })
        }
    }

    func image(for place: Place, now: Date = Date()) -> UIImage? {
        guard let ref = SavvyMapPhotoPolicy.resolvedPhoto(
            for: place,
            isConfirmedSaved: true,
            ownPosts: ownPosts
        ).shared else { return nil }
        let key = cacheKey(ref)
        guard let entry = thumbnails[key],
              SavvyMapOwnPhotoSource.isThumbnailFresh(storedAt: entry.storedAt, now: now) else {
            return nil
        }
        return entry.image
    }

    func loadIfNeeded(for place: Place) async {
        _ = place
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

/// P14: unsaved Apple POI taps stay on the native feature card / save flow.
/// Only a confirmed saved Map Stamp opens the Savvy paper card.
enum SavvyMapPOITap {
    enum Path: Equatable {
        case savvyPin
        case nativeAppleCard
    }

    static func path(isConfirmedSaved: Bool) -> Path {
        isConfirmedSaved ? .savvyPin : .nativeAppleCard
    }

    static func opensSavvyCard(_ place: Place?, confirmedPlaces: [Place]) -> Place? {
        guard let place,
              path(isConfirmedSaved: SavvyMapStampPolicy.qualifiesForSavvyPin(
                place,
                confirmedPlaces: confirmedPlaces
              )) == .savvyPin else {
            return nil
        }
        return place
    }
}

enum SavvyMapBadgeLettering {
    static func usesArc(
        text: String,
        language: AppLanguage,
        dynamicTypeSize: DynamicTypeSize
    ) -> Bool {
        dynamicTypeSize < .xxxLarge
            && language != .traditionalChinese
            && text.count > 4
    }
}

/// Radial gaps for the English arc (paper-concentric, 13pt backup).
enum SavvyMapArcGeometry {
    static let paperRadius = SavvyMapPinMetrics.badgeStickerWidth / 2
    static let photoRadius = SavvyMapPinMetrics.badgePhoto / 2
    static let letterHalfHeight = SavvyMapPinMetrics.badgeArcFontSize / 2

    struct Gaps: Equatable {
        var paperOuterFromLetterCenter: CGFloat
        var photoFromLetterCenter: CGFloat
        var paperOuterFromGlyph: CGFloat
        var photoFromGlyph: CGFloat
    }

    static func gaps(atAngleDegrees angle: Double) -> Gaps {
        let radius = SavvyMapArcText.radius
        let radians = angle * .pi / 180
        let letter = CGPoint(x: radius * sin(radians), y: -radius * cos(radians))
        let paperFromCenter = paperRadius - radius
        let photoCenter = CGPoint(x: 0, y: SavvyMapPinMetrics.badgePhotoOffsetY)
        let photoFromCenter = hypot(letter.x - photoCenter.x, letter.y - photoCenter.y) - photoRadius
        return Gaps(
            paperOuterFromLetterCenter: paperFromCenter,
            photoFromLetterCenter: photoFromCenter,
            paperOuterFromGlyph: paperFromCenter - letterHalfHeight,
            photoFromGlyph: photoFromCenter - letterHalfHeight
        )
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
    /// P4: pin tap pans north only. Do not square the span — that changes zoom
    /// on a portrait map. Keep the live camera distance/heading and pitch 0.
    static let usesEqualLatLonSpan = false
    static let cameraPitch: CGFloat = 0

    static func center(
        for pin: CLLocationCoordinate2D,
        latitudeDelta: CLLocationDegrees
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: pin.latitude + 0.225 * latitudeDelta,
            longitude: pin.longitude
        )
    }

    static func camera(
        pin: CLLocationCoordinate2D,
        latitudeDelta: CLLocationDegrees,
        current: MapCamera
    ) -> MapCamera {
        MapCamera(
            centerCoordinate: center(for: pin, latitudeDelta: latitudeDelta),
            distance: current.distance,
            heading: current.heading,
            pitch: cameraPitch
        )
    }
}

/// P4: card opens first; camera follows after `cameraDelay` unless Reduce Motion.
struct SavvyMapScheduler {
    var asyncAfter: (TimeInterval, @escaping () -> Void) -> Void

    static let main = SavvyMapScheduler { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

enum SavvyMapCameraFollow {
    static func scheduleOpenMove(
        reduceMotion: Bool,
        delay: TimeInterval = SavvyMapPinMetrics.cameraDelay,
        scheduler: SavvyMapScheduler = .main,
        move: @escaping () -> Void
    ) {
        if reduceMotion {
            move()
            return
        }
        scheduler.asyncAfter(delay, move)
    }
}

enum SavvyMapCardDrag {
    static let minimumDistance: CGFloat = 12

    static func shouldCollapse(translationHeight: CGFloat) -> Bool {
        translationHeight > SavvyMapPinMetrics.collapseDrag
    }
}

/// 「怎麼去」opens Apple Maps directions. Transport stays Apple's default.
/// No in-app navigation. No coordinates → place page (`q=`), not a route.
enum SavvyMapDirectionsLaunch {
    enum Kind: Equatable {
        case directions
        case placePage
        case none
    }

    struct Plan: Equatable {
        var kind: Kind
        var launchOptions: [String: String]
        var destinationName: String?
    }

    static func plan(for place: Place) -> Plan {
        if place.hasValidCoordinate, place.isMapKitMappable {
            return Plan(
                kind: .directions,
                launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
                ],
                destinationName: place.name
            )
        }
        if placePageURL(for: place) != nil {
            return Plan(kind: .placePage, launchOptions: [:], destinationName: place.name)
        }
        return Plan(kind: .none, launchOptions: [:], destinationName: nil)
    }

    static func placePageURL(for place: Place) -> URL? {
        if let url = place.appleMapsURL { return url }
        let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: name)]
        return components?.url
    }

    static func open(
        _ place: Place,
        openMapItem: (MKMapItem, [String: Any]) -> Void = { $0.openInMaps(launchOptions: $1) },
        openURL: (URL) -> Void = { UIApplication.shared.open($0) }
    ) {
        let planned = plan(for: place)
        switch planned.kind {
        case .directions:
            let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
            item.name = place.name
            let options = planned.launchOptions.reduce(into: [String: Any]()) { $0[$1.key] = $1.value }
            openMapItem(item, options)
        case .placePage:
            if let url = placePageURL(for: place) { openURL(url) }
        case .none:
            break
        }
    }
}

enum SavvyMapEatGo: String {
    case eat = "Eat"
    case go = "Go"

    func label(language: AppLanguage) -> String {
        switch self {
        case .eat:
            return language.localized(english: "Eat", traditionalChinese: "吃")
        case .go:
            return language.localized(english: "Go", traditionalChinese: "去")
        }
    }
}

enum SavvyMapCardCopy {
    static func directionsTitle(language: AppLanguage) -> String {
        language.localized(english: "Directions", traditionalChinese: "怎麼去")
    }

    static func pinAccessibilityLabel(
        name: String,
        category: String,
        visit: String,
        language: AppLanguage
    ) -> String {
        let joiner = language == .traditionalChinese ? "、" : ", "
        return "\(name)\(joiner)\(category)\(joiner)\(visit)"
    }

    static func visitDateText(_ date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .traditionalChinese ? "zh_Hant_TW" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
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

/// Prototype adapter; shared Doodle/Passport history is authoritative.
@MainActor
final class SavvyMapVisitStore: ObservableObject {
    static let shared = SavvyMapVisitStore()

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let history: SaveDoodleVisitStore
    private var pending: Set<UUID> = []

    init(defaults: UserDefaults = .standard, key: String = "savvy.map.visits.v1",
         calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        history = SaveDoodleVisitStore(defaults: defaults, calendar: calendar)
        // Preserve the old payload verbatim. Import each date only once per
        // calendar day; existing shared counters must never be decremented.
        let migrationKey = key + ".imported." + SaveDoodleVisitStore.datesKey
        guard !defaults.bool(forKey: migrationKey) else { return }
        let legacy = defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
        for (rawID, timestamps) in legacy {
            guard let id = UUID(uuidString: rawID) else { continue }
            let snapshot = history.snapshot(for: id)
            var dates = snapshot.dates
            for stamp in timestamps.sorted() {
                let date = Date(timeIntervalSince1970: stamp)
                if !dates.contains(where: { calendar.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: date) }) {
                    dates.append(stamp)
                }
            }
            history.restore(.init(id: id, dates: dates, count: max(snapshot.count, dates.count)))
        }
        defaults.set(true, forKey: migrationKey)
    }

    func visits(for placeID: UUID) -> [Date] {
        history.snapshot(for: placeID).dates.map(Date.init(timeIntervalSince1970:))
    }

    func visitCount(for placeID: UUID, fallbackVisited: Bool) -> Int {
        max(history.count(for: placeID), fallbackVisited ? 1 : 0)
    }

    func lastVisit(for placeID: UUID, fallback: Date?) -> Date? {
        history.latestVisit(for: placeID) ?? fallback
    }

    @discardableResult
    func recordVisit(placeID: UUID, at date: Date = Date()) -> Int {
        let datedHistory = SaveDoodleVisitStore(defaults: defaults, calendar: calendar, now: { date })
        objectWillChange.send()
        datedHistory.recordVisit(for: placeID)
        return history.count(for: placeID)
    }

    /// No history mutation precedes persistence, including when the awaited
    /// operation resumes after sign-out or a same-account session replacement.
    @discardableResult
    func recordPersistedVisit(
        placeID: UUID,
        isCurrent: () -> Bool,
        persist: () async throws -> Void
    ) async throws -> Bool {
        guard isCurrent(), pending.insert(placeID).inserted else { return false }
        defer { pending.remove(placeID) }
        try await persist()
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        recordVisit(placeID: placeID)
        return true
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

    @MainActor
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

/// DESIGN gate 5 / QA catalog. Names only — no shipping photos. DEBUG
/// Previews inject a fixture image for the photo rows; production stays coral.
enum SavvyMapPhotoPinPreviewState: String, CaseIterable, Identifiable {
    case photoRoundPin
    case photoVisitedRing
    case photoBadge
    case photoCardHero
    case coralRoundPin
    case coralVisitedRing
    case coralBadge
    case coralCardHero

    var id: String { rawValue }

    var usesFixturePhoto: Bool {
        switch self {
        case .photoRoundPin, .photoVisitedRing, .photoBadge, .photoCardHero:
            return true
        case .coralRoundPin, .coralVisitedRing, .coralBadge, .coralCardHero:
            return false
        }
    }

    var isVisited: Bool {
        self == .photoVisitedRing || self == .coralVisitedRing
    }

    var showsBadge: Bool {
        self == .photoBadge || self == .coralBadge
    }

    var showsCard: Bool {
        self == .photoCardHero || self == .coralCardHero
    }

    var qaTitle: String {
        switch self {
        case .photoRoundPin: return "P1 photo round pin"
        case .photoVisitedRing: return "P1 photo + visited ring"
        case .photoBadge: return "P2 photo badge (latΔ ≤ 0.02)"
        case .photoCardHero: return "P1/P3 card hero image"
        case .coralRoundPin: return "P1 coral round pin"
        case .coralVisitedRing: return "P1 coral + visited ring"
        case .coralBadge: return "P2 coral badge (latΔ ≤ 0.02)"
        case .coralCardHero: return "P3 card hero coral"
        }
    }
}

struct SavvyMapPhotoPinView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var sharedPhotos = SavvyMapSharedPinPhotoStore.shared
#if DEBUG
    @Environment(\.savvyMapPreviewPhoto) private var previewPhoto
#endif
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
            ZStack {
                Circle()
                    .fill(SaveAtlasPalette.paper)
                    .frame(
                        width: SavvyMapPinMetrics.badgeStickerWidth,
                        height: SavvyMapPinMetrics.badgeStickerWidth
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
                    .offset(y: SavvyMapPinMetrics.badgePhotoOffsetY)

                badgeLabel
                    .offset(y: -SavvyMapPinMetrics.badgeStickerWidth / 2 + SavvyMapPinMetrics.badgeArcLabelOffsetY)
            }
            .frame(
                width: SavvyMapPinMetrics.badgeStickerWidth,
                height: SavvyMapPinMetrics.badgeStickerWidth
            )
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
        // P1: 「景點」 stays a word. Arc lettering splits two CJK characters.
        let usesArc = SavvyMapBadgeLettering.usesArc(
            text: text,
            language: languageSettings.language,
            dynamicTypeSize: dynamicTypeSize
        )
        if usesArc {
            SavvyMapArcText(
                text: text,
                radius: SavvyMapArcText.radius,
                font: .system(size: SavvyMapPinMetrics.badgeArcFontSize, weight: .heavy, design: .rounded)
            )
            .foregroundStyle(SaveAtlasPalette.ink)
        } else {
            Text(text)
                .font(SaveAtlasType.strong(15))
                .foregroundStyle(SaveAtlasPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 8)
                .offset(y: SavvyMapPinMetrics.badgeWordLabelOffsetY)
                .offset(y: -SavvyMapPinMetrics.badgeWordLabelExtraLift)
        }
    }

    private func coralOrPhotoCircle(diameter: CGFloat, paperStroke: CGFloat) -> some View {
        let inner = max(8, diameter - paperStroke * 2)
        return ZStack {
            Circle()
                .fill(SaveAtlasPalette.coral)
                .frame(width: inner, height: inner)
            SavvyMapPinPhotoFill(
                image: pinImage,
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

    private var pinImage: UIImage? {
#if DEBUG
        if let previewPhoto { return previewPhoto }
#endif
        return sharedPhotos.image(for: place)
    }

    private var hasPhoto: Bool {
        pinImage != nil
    }

    private var pinLabel: String {
        let category = place.category.displayName(language: languageSettings.language)
        let visit = isVisited
            ? languageSettings.localized(english: "visited", traditionalChinese: "去過")
            : languageSettings.localized(english: "not visited", traditionalChinese: "沒去過")
        return SavvyMapCardCopy.pinAccessibilityLabel(
            name: place.name,
            category: category,
            visit: visit,
            language: languageSettings.language
        )
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
    var font: Font = .system(size: SavvyMapPinMetrics.badgeArcFontSize, weight: .heavy, design: .rounded)

    /// Letters sit on one arc concentric with the 89pt paper circle.
    static let radius: CGFloat = 34.5
    static let maxSpreadDegrees: Double = 112
    static let degreesPerCharacter: Double = 20 * 112 / 150

    static func spreadDegrees(characterCount: Int) -> Double {
        min(maxSpreadDegrees, Double(max(characterCount, 1)) * degreesPerCharacter)
    }

    var body: some View {
        let characters = Array(text)
        let count = max(characters.count, 1)
        let spread = Self.spreadDegrees(characterCount: count)
        ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                let t = count == 1 ? 0.5 : Double(index) / Double(count - 1)
                let angle = -spread / 2 + spread * t
                Text(String(character))
                    .font(font)
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
#if DEBUG
    @Environment(\.savvyMapPreviewPhoto) private var previewPhoto
#endif
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
            DragGesture(minimumDistance: SavvyMapCardDrag.minimumDistance)
                .onEnded { value in
                    if SavvyMapCardDrag.shouldCollapse(translationHeight: value.translation.height) {
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
                    .offset(y: SavvyMapPinMetrics.cardPhotoInset - 6)
            }

            Text(metaLine)
                .font(SaveAtlasType.body(15))
                .foregroundStyle(SaveAtlasPalette.muted)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("map.peek.subtitle")

            HStack(spacing: 12) {
                Button(action: onDirections) {
                    Text(SavvyMapCardCopy.directionsTitle(language: languageSettings.language))
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

    private var cardHeroImage: UIImage? {
#if DEBUG
        if let previewPhoto { return previewPhoto }
#endif
        return sharedPhotos.image(for: place)
    }

    private var photoWell: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: SavvyMapPinMetrics.cardPhotoCorner, style: .continuous)
                .fill(SaveAtlasPalette.coral)
            if let image = cardHeroImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: SavvyMapPinMetrics.cardPhotoHeight)
                    .clipped()
                    .clipShape(
                        RoundedRectangle(cornerRadius: SavvyMapPinMetrics.cardPhotoCorner, style: .continuous)
                    )
            } else {
                Image(systemName: place.category.iconName)
                    .font(.system(size: SavvyMapPinMetrics.cardCoralIcon, weight: .semibold))
                    .foregroundStyle(SaveTheme.Colors.cream)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.55)],
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
        .frame(maxWidth: .infinity)
        .frame(height: SavvyMapPinMetrics.cardPhotoHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: SavvyMapPinMetrics.cardPhotoCorner, style: .continuous))
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
                    Text(SavvyMapCardCopy.directionsTitle(language: languageSettings.language))
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
        let date = back.lastVisit.map { SavvyMapCardCopy.visitDateText($0, language: languageSettings.language) } ?? ""
        if languageSettings.language == .traditionalChinese {
            return date.isEmpty ? "去過 \(count) 次" : "去過 \(count) 次 · 最近 \(date)"
        }
        return date.isEmpty ? "Visited \(count) time\(count == 1 ? "" : "s")" : "Visited \(count) time\(count == 1 ? "" : "s") · last \(date)"
    }
}

#if DEBUG
/// Preview-only photo hook. Default is nil so DEBUG app runs stay coral
/// unless a Preview or test fixture injects an image. Not shipping data.
private struct SavvyMapPreviewPhotoKey: EnvironmentKey {
    static let defaultValue: UIImage? = nil
}

extension EnvironmentValues {
    var savvyMapPreviewPhoto: UIImage? {
        get { self[SavvyMapPreviewPhotoKey.self] }
        set { self[SavvyMapPreviewPhotoKey.self] = newValue }
    }
}

enum SavvyMapPhotoPinPreviewFixtures {
    static let placeID = UUID(uuidString: "00000000-0000-4000-8000-000000000021")!

    static func place(
        visited: Bool,
        category: PlaceCategory = .attraction,
        name: String = "Temple of Heaven"
    ) -> Place {
        Place(
            id: placeID,
            name: name,
            address: "Tiantan Rd",
            latitude: 39.8822,
            longitude: 116.4066,
            googlePlaceId: nil,
            category: category,
            status: visited ? .visited : .wantToGo,
            rating: nil,
            note: "DEBUG fixture — not shipping data",
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            businessPhotoUrls: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: "09:00–17:00",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// Procedural circular-hall photo. Labeled DEBUG so QA never treats it as live.
    static func photo() -> UIImage {
        let size = CGSize(width: 360, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let sky = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.55, green: 0.70, blue: 0.80, alpha: 1).cgColor,
                    UIColor(red: 0.46, green: 0.58, blue: 0.66, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0, 1]
            )!
            cg.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: 360), options: [])
            UIColor(red: 0.34, green: 0.49, blue: 0.31, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 220, width: 360, height: 140))
            UIColor(red: 0.66, green: 0.23, blue: 0.18, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 58, y: 78, width: 244, height: 88))
            UIColor(red: 0.77, green: 0.31, blue: 0.21, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 86, y: 108, width: 188, height: 70))
            UIColor(red: 0.84, green: 0.38, blue: 0.24, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 114, y: 132, width: 132, height: 52))
            UIColor(red: 0.93, green: 0.84, blue: 0.64, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 98, y: 118, width: 164, height: 36))
            UIColor(red: 0.36, green: 0.16, blue: 0.13, alpha: 1).setFill()
            cg.fill(CGRect(x: 168, y: 168, width: 24, height: 70))
            UIColor(red: 0.82, green: 0.73, blue: 0.52, alpha: 1).setFill()
            cg.move(to: CGPoint(x: 110, y: 236))
            cg.addLine(to: CGPoint(x: 250, y: 236))
            cg.addLine(to: CGPoint(x: 270, y: 282))
            cg.addLine(to: CGPoint(x: 90, y: 282))
            cg.closePath()
            cg.fillPath()
            UIColor(red: 0.07, green: 0.05, blue: 0.05, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 328, width: 360, height: 32))
            ("DEBUG FIXTURE" as NSString).draw(
                in: CGRect(x: 12, y: 334, width: 336, height: 22),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                ]
            )
        }
    }
}

struct SavvyMapPhotoPinPreviewCell: View {
    let state: SavvyMapPhotoPinPreviewState
    var language: AppLanguage = .english
    var isFlipped: Bool = false
    var category: PlaceCategory = .attraction
    var placeName: String? = nil
    var visitCount: Int = 0
    var lastVisit: Date? = nil
    var dynamicTypeSize: DynamicTypeSize = .large
    private let visits: SavvyMapVisitStore

    init(
        state: SavvyMapPhotoPinPreviewState,
        language: AppLanguage = .english,
        isFlipped: Bool = false,
        category: PlaceCategory = .attraction,
        placeName: String? = nil,
        visitCount: Int = 0,
        lastVisit: Date? = nil,
        dynamicTypeSize: DynamicTypeSize = .large
    ) {
        self.state = state
        self.language = language
        self.isFlipped = isFlipped
        self.category = category
        self.placeName = placeName
        self.visitCount = visitCount
        self.lastVisit = lastVisit
        self.dynamicTypeSize = dynamicTypeSize
        let suite = "savvy.map.preview.\(language.rawValue).\(state.rawValue).\(category.rawValue).flip\(isFlipped).v\(visitCount)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = SavvyMapVisitStore(defaults: defaults, key: "gate5")
        if visitCount > 0 {
            let last = lastVisit ?? Date(timeIntervalSince1970: 1_700_000_000)
            for index in 0..<visitCount {
                _ = store.recordVisit(
                    placeID: SavvyMapPhotoPinPreviewFixtures.placeID,
                    at: last.addingTimeInterval(TimeInterval(index - visitCount + 1) * 86_400)
                )
            }
        }
        self.visits = store
    }

    var body: some View {
        let place = SavvyMapPhotoPinPreviewFixtures.place(
            visited: state.isVisited || visitCount > 0,
            category: category,
            name: placeName ?? "Temple of Heaven"
        )
        let settings = AppLanguageSettings(
            userDefaults: UserDefaults(suiteName: "savvy.map.preview.\(language.rawValue)") ?? .standard
        )
        settings.language = language
        return Group {
            if state.showsCard {
                SavvyMapPlaceCard(
                    visits: visits,
                    place: place,
                    userLocation: CLLocation(latitude: 39.883, longitude: 116.407),
                    isOpen: true,
                    isFlipped: isFlipped,
                    reduceMotion: true,
                    screenWidth: 390,
                    onFlip: {},
                    onBeenHere: {},
                    onDirections: {},
                    onOpenDetail: {},
                    onEditNote: {},
                    onCollapse: {}
                )
            } else {
                SavvyMapPhotoPinView(
                    place: place,
                    showsBadge: state.showsBadge,
                    isVisited: state.isVisited,
                    isSelected: false,
                    reduceMotion: true,
                    onTap: {}
                )
            }
        }
        .environment(\.appLanguageSettings, settings)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(
            \.savvyMapPreviewPhoto,
            state.usesFixturePhoto ? SavvyMapPhotoPinPreviewFixtures.photo() : nil
        )
    }
}

/// Xcode Previews + QA board. Debug/test-only; production Map never seeds this.
struct SavvyMapPhotoPinPreviewCatalog: View {
    var colorScheme: ColorScheme = .light
    var language: AppLanguage = .english
    /// Snapshot export: no ScrollView / Lazy* so every cell actually paints.
    var snapshotLayout: Bool = false

    var body: some View {
        let settings = AppLanguageSettings(
            userDefaults: UserDefaults(suiteName: "savvy.map.catalog.\(language.rawValue)") ?? .standard
        )
        settings.language = language
        let content = catalogGrid
        return Group {
            if snapshotLayout {
                content
            } else {
                ScrollView { content }
            }
        }
        .background(SaveAtlasPalette.paper.ignoresSafeArea())
        .environment(\.appLanguageSettings, settings)
        .environment(\.colorScheme, colorScheme)
        .preferredColorScheme(colorScheme)
        .accessibilityIdentifier("map.pin.previewCatalog")
    }

    private var catalogGrid: some View {
        let states = SavvyMapPhotoPinPreviewState.allCases
        return VStack(alignment: .leading, spacing: 16) {
            Text("DEBUG / test fixtures — not shipping data")
                .font(SaveAtlasType.strong(13))
                .foregroundStyle(SaveAtlasPalette.muted)
            Text("DESIGN gate 5 · photo + coral pin states")
                .font(SaveAtlasType.strong(20))
                .foregroundStyle(SaveAtlasPalette.ink)
            Grid(alignment: .top, horizontalSpacing: 20, verticalSpacing: 20) {
                ForEach(0..<(states.count / 2), id: \.self) { row in
                    GridRow {
                        catalogCell(states[row * 2])
                        catalogCell(states[row * 2 + 1])
                    }
                }
            }
        }
        .padding(16)
    }

    private func catalogCell(_ state: SavvyMapPhotoPinPreviewState) -> some View {
        VStack(spacing: 10) {
            SavvyMapPhotoPinPreviewCell(state: state, language: language)
                .frame(minHeight: state.showsCard ? 430 : 140)
            Text(state.qaTitle)
                .font(SaveAtlasType.strong(12))
                .foregroundStyle(SaveAtlasPalette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            SaveAtlasPalette.kraftLight,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

/// P14: saved / unsaved / visited on one board. Unsaved is a native-style POI.
struct SavvyMapP14PreviewBoard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("P14 · saved / unsaved / visited")
                .font(SaveAtlasType.strong(18))
                .foregroundStyle(SaveAtlasPalette.ink)
            HStack(alignment: .bottom, spacing: 28) {
                labeledPin("Saved", visited: false)
                labeledPOI("Unsaved")
                labeledPin("Visited", visited: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(SaveAtlasPalette.paper)
        .accessibilityIdentifier("map.p14.board")
    }

    private func labeledPin(_ title: String, visited: Bool) -> some View {
        VStack(spacing: 10) {
            SavvyMapPhotoPinView(
                place: SavvyMapPhotoPinPreviewFixtures.place(visited: visited),
                showsBadge: false,
                isVisited: visited,
                isSelected: false,
                reduceMotion: true,
                onTap: {}
            )
            Text(title)
                .font(SaveAtlasType.strong(13))
                .foregroundStyle(SaveAtlasPalette.ink)
        }
    }

    private func labeledPOI(_ title: String) -> some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Color(red: 0.18, green: 0.44, blue: 0.93))
                .frame(width: 12, height: 12)
                .overlay {
                    Circle().stroke(Color.white, lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(width: 44, height: 44)
            Text(title)
                .font(SaveAtlasType.strong(13))
                .foregroundStyle(SaveAtlasPalette.ink)
        }
    }
}

enum SavvyMapPhotoPinSnapshotExport {
    /// Hosted snapshot of the SwiftUI view. `ImageRenderer` alone skips
    /// `Lazy*` grids and ignores `UIColor` dynamic light/dark traits.
    @MainActor
    static func image<V: View>(
        for view: V,
        size: CGSize,
        scale: CGFloat = 2,
        scheme: ColorScheme
    ) -> UIImage? {
        let themed = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(scheme)
        let host = UIHostingController(rootView: themed)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = host
        window.isHidden = false
        host.view.bounds = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .clear
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let hosted = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        if hosted.size.width > 1 {
            return hosted
        }
        let renderer = ImageRenderer(content: themed)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }

    @MainActor
    static func writeAll(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        let pinSize = CGSize(width: 390, height: 520)
        let catalogSize = CGSize(width: 780, height: 1860)
        for scheme in [ColorScheme.light, .dark] {
            let schemeName = scheme == .light ? "light" : "dark"
            for state in SavvyMapPhotoPinPreviewState.allCases {
                let view = previewPage(state, scheme: scheme, language: .english)
                let url = directory.appendingPathComponent("\(schemeName)-\(state.rawValue).png")
                try write(view, size: pinSize, scheme: scheme, to: url)
                written.append(url)
            }
            let catalog = SavvyMapPhotoPinPreviewCatalog(
                colorScheme: scheme,
                language: .english,
                snapshotLayout: true
            )
            let catalogURL = directory.appendingPathComponent("catalog-\(schemeName).png")
            try write(catalog, size: catalogSize, scheme: scheme, to: catalogURL)
            written.append(catalogURL)
        }
        for state in [SavvyMapPhotoPinPreviewState.photoBadge, .coralBadge, .photoCardHero, .coralCardHero] {
            let view = previewPage(state, scheme: .light, language: .traditionalChinese)
            let url = directory.appendingPathComponent("zh-Hant-\(state.rawValue).png")
            try write(view, size: pinSize, scheme: .light, to: url)
            written.append(url)
        }
        let p14 = directory.appendingPathComponent("p14-saved-unsaved-visited.png")
        try write(
            SavvyMapP14PreviewBoard()
                .environment(\.colorScheme, .light)
                .preferredColorScheme(.light),
            size: CGSize(width: 780, height: 360),
            scheme: .light,
            to: p14
        )
        written.append(p14)
        let cardBack = directory.appendingPathComponent("light-coralCardBack.png")
        try write(
            previewPage(.coralCardHero, scheme: .light, isFlipped: true),
            size: pinSize,
            scheme: .light,
            to: cardBack
        )
        written.append(cardBack)
        let zhCardBack = directory.appendingPathComponent("zh-Hant-coralCardBack.png")
        try write(
            previewPage(.coralCardHero, scheme: .light, language: .traditionalChinese, isFlipped: true),
            size: pinSize,
            scheme: .light,
            to: zhCardBack
        )
        written.append(zhCardBack)
        let zhVisitedBack = directory.appendingPathComponent("zh-Hant-coralCardVisitedBack.png")
        try write(
            previewPage(
                .coralCardHero,
                scheme: .light,
                language: .traditionalChinese,
                isFlipped: true,
                visitCount: 2,
                lastVisit: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            size: pinSize,
            scheme: .light,
            to: zhVisitedBack
        )
        written.append(zhVisitedBack)
        let darkCardBack = directory.appendingPathComponent("dark-coralCardBack.png")
        try write(
            previewPage(.coralCardHero, scheme: .dark, isFlipped: true),
            size: pinSize,
            scheme: .dark,
            to: darkCardBack
        )
        written.append(darkCardBack)
        let zhFoodFront = directory.appendingPathComponent("zh-Hant-foodCardHero.png")
        try write(
            previewPage(
                .coralCardHero,
                scheme: .light,
                language: .traditionalChinese,
                category: .food,
                placeName: "Din Tai Fung"
            ),
            size: pinSize,
            scheme: .light,
            to: zhFoodFront
        )
        written.append(zhFoodFront)
        let shoppingBadge = directory.appendingPathComponent("light-shoppingBadge.png")
        try write(
            previewPage(
                .photoBadge,
                scheme: .light,
                category: .shopping,
                placeName: "Isetan"
            ),
            size: pinSize,
            scheme: .light,
            to: shoppingBadge
        )
        written.append(shoppingBadge)
        let xxxLargeBadge = directory.appendingPathComponent("xxxLarge-photoBadge.png")
        try write(
            previewPage(
                .photoBadge,
                scheme: .light,
                dynamicTypeSize: .xxxLarge
            ),
            size: pinSize,
            scheme: .light,
            to: xxxLargeBadge
        )
        written.append(xxxLargeBadge)
        return written
    }

    @MainActor
    private static func write<V: View>(
        _ view: V,
        size: CGSize,
        scheme: ColorScheme,
        to url: URL
    ) throws {
        guard let image = image(for: view, size: size, scheme: scheme),
              let data = image.pngData() else {
            throw NSError(domain: "SavvyMapPhotoPinSnapshotExport", code: 1)
        }
        try data.write(to: url, options: .atomic)
    }
}

struct SavvyMapPhotoPinMotionFixtureRoot: View {
    private let photoPlace = SavvyMapPhotoPinPreviewFixtures.place(visited: false)
    private let coralPlace = SavvyMapPhotoPinPreviewFixtures.place(visited: true)
    @State private var position = MapCameraPosition.camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 39.8835, longitude: 116.4079),
            distance: 4_500,
            heading: 0,
            pitch: 0
        )
    )
    @State private var showsBadge = false
    @State private var session = SavvyMapCardSession()
    @State private var selected: Place?
    @ObservedObject private var visits = SavvyMapVisitStore(
        defaults: UserDefaults(suiteName: "savvy.map.motion.visits") ?? .standard,
        key: "motion"
    )

    var body: some View {
        GeometryReader { geo in
            Map(position: $position) {
                Annotation("", coordinate: photoPlace.coordinate, anchor: .bottom) {
                    SavvyMapPhotoPinView(
                        place: photoPlace,
                        showsBadge: showsBadge,
                        isVisited: false,
                        isSelected: selected?.id == photoPlace.id,
                        reduceMotion: false
                    ) {
                        selected = photoPlace
                        session.select(photoPlace.id)
                    }
                    .environment(\.savvyMapPreviewPhoto, SavvyMapPhotoPinPreviewFixtures.photo())
                }
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: 39.8848, longitude: 116.4092), anchor: .bottom) {
                    SavvyMapPhotoPinView(
                        place: coralPlace,
                        showsBadge: showsBadge,
                        isVisited: true,
                        isSelected: false,
                        reduceMotion: false
                    ) {}
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .all, showsTraffic: false))
            .overlay {
                if let selected, session.isOpen {
                    SavvyMapPlaceCard(
                        visits: visits,
                        place: selected,
                        userLocation: nil,
                        isOpen: session.isOpen,
                        isFlipped: session.isFlipped,
                        reduceMotion: false,
                        screenWidth: geo.size.width,
                        onFlip: { session.toggleFlip() },
                        onBeenHere: {},
                        onDirections: {},
                        onOpenDetail: {},
                        onEditNote: {},
                        onCollapse: { session.finishCollapseAfterFlip(); self.selected = nil }
                    )
                    .environment(\.savvyMapPreviewPhoto, SavvyMapPhotoPinPreviewFixtures.photo())
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("map.fixture.motion")
        .task { await playMotion() }
    }

    private func playMotion() async {
        // Hold small pins on the live Apple Map before zoom so the 60fps
        // recording (starts at launch) shows pin → badge, not a grown badge.
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        withAnimation(SavvyMapMotion.camera) {
            position = .camera(
                MapCamera(
                    centerCoordinate: photoPlace.coordinate,
                    distance: 1_200,
                    heading: 0,
                    pitch: 0
                )
            )
            showsBadge = true
        }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        withAnimation(SavvyMapMotion.cardOpen) {
            selected = photoPlace
            session.select(photoPlace.id)
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        withAnimation(SavvyMapMotion.flipBack) {
            session.toggleFlip()
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        withAnimation(SavvyMapMotion.flipFront) {
            session.isFlipped = false
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        withAnimation(SavvyMapMotion.cardClose) {
            session.finishCollapseAfterFlip()
            selected = nil
        }
    }
}

#Preview("Gate 5 catalog / light") {
    SavvyMapPhotoPinPreviewCatalog(colorScheme: .light)
}

#Preview("Gate 5 catalog / dark") {
    SavvyMapPhotoPinPreviewCatalog(colorScheme: .dark)
}

#Preview("P2 photo badge / zh") {
    previewPage(.photoBadge, scheme: .light, language: .traditionalChinese)
}

#Preview("P14 board") {
    SavvyMapP14PreviewBoard()
}

#Preview("P1 photo round pin / light") {
    previewPage(.photoRoundPin, scheme: .light)
}

#Preview("P1 photo visited ring / dark") {
    previewPage(.photoVisitedRing, scheme: .dark)
}

#Preview("P2 photo badge / light") {
    previewPage(.photoBadge, scheme: .light)
}

#Preview("P3 photo card hero / dark") {
    previewPage(.photoCardHero, scheme: .dark)
}

#Preview("P1 coral pin / light") {
    previewPage(.coralRoundPin, scheme: .light)
}

#Preview("P1 coral visited / dark") {
    previewPage(.coralVisitedRing, scheme: .dark)
}

#Preview("P2 coral badge / light") {
    previewPage(.coralBadge, scheme: .light)
}

#Preview("P3 coral card / dark") {
    previewPage(.coralCardHero, scheme: .dark)
}

func previewPage(
    _ state: SavvyMapPhotoPinPreviewState,
    scheme: ColorScheme,
    language: AppLanguage = .english,
    isFlipped: Bool = false,
    category: PlaceCategory = .attraction,
    placeName: String? = nil,
    visitCount: Int = 0,
    lastVisit: Date? = nil,
    dynamicTypeSize: DynamicTypeSize = .large
) -> some View {
    ZStack {
        SaveAtlasPalette.paper.ignoresSafeArea()
        VStack(spacing: 16) {
            Text(state.qaTitle)
                .font(SaveAtlasType.strong(15))
                .foregroundStyle(SaveAtlasPalette.ink)
            SavvyMapPhotoPinPreviewCell(
                state: state,
                language: language,
                isFlipped: isFlipped,
                category: category,
                placeName: placeName,
                visitCount: visitCount,
                lastVisit: lastVisit,
                dynamicTypeSize: dynamicTypeSize
            )
        }
        .padding(24)
    }
    .environment(\.colorScheme, scheme)
    .preferredColorScheme(scheme)
    .environment(\.dynamicTypeSize, dynamicTypeSize)
}

/// Interactive paper card for XCUITest flip / swipe-down. DEBUG only.
struct SavvyMapPhotoPinCardFlowFixtureRoot: View {
    @State private var session = SavvyMapCardSession()
    private let place = SavvyMapPhotoPinPreviewFixtures.place(visited: false)
    private let visits = SavvyMapVisitStore(
        defaults: UserDefaults(suiteName: "savvy.map.cardflow.visits") ?? .standard,
        key: "cardflow"
    )

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SaveAtlasPalette.paper.ignoresSafeArea()
                if session.isOpen {
                    SavvyMapPlaceCard(
                        visits: visits,
                        place: place,
                        userLocation: CLLocation(latitude: 39.883, longitude: 116.407),
                        isOpen: session.isOpen,
                        isFlipped: session.isFlipped,
                        reduceMotion: true,
                        screenWidth: geo.size.width,
                        onFlip: { session.toggleFlip() },
                        onBeenHere: {},
                        onDirections: {},
                        onOpenDetail: {},
                        onEditNote: {},
                        onCollapse: { session.finishCollapseAfterFlip() }
                    )
                }
            }
        }
        .onAppear { session.select(place.id) }
        .accessibilityIdentifier("map.fixture.card")
    }
}
#endif
