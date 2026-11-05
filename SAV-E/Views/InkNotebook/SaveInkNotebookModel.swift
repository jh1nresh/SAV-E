import Combine
import CoreLocation
import Foundation
import UIKit

/// Provisional HoP numbers. Founder has not confirmed the thresholds.
enum SaveInkProvisional {
    static let radiusMeters = 150.0
    static let maxAccuracyMeters = 100.0
    static let timeoutSeconds = 10.0
    static let samePlaceWindow: TimeInterval = 6 * 60 * 60
    static let upgradeWindow: TimeInterval = 24 * 60 * 60
    static let dailyVerifiedCap = 20
    static let maxSpeedKmh = 300.0
    static let maxFixAge: TimeInterval = 60
    static let defaultVisibility = SaveInkVisibility.public
    /// Friend-card quotations are still example copy.
    static let commentMark = "待定"
}

enum SaveInkVerification: String, Codable, Equatable {
    case verified
    case unverified
}

enum SaveInkVisibility: String, Codable, Equatable {
    case `public` = "public"
    case `private` = "private"
}

enum SaveInkSentiment: String, Codable, Equatable, CaseIterable {
    case again
    case worthQueue
    case ordinary

    var title: String { title(language: .traditionalChinese) }

    func title(language: AppLanguage) -> String {
        switch self {
        case .again: language.localized(english: "Would return", traditionalChinese: "會再來")
        case .worthQueue: language.localized(english: "Worth the wait", traditionalChinese: "值得排")
        case .ordinary: language.localized(english: "Okay", traditionalChinese: "普通")
        }
    }
}

enum SaveInkAnomaly: String, Codable, Equatable {
    case simulatedLocation
    case implausibleSpeed
    case dailyCap
}

enum SaveInkAuthorization: Equatable {
    case authorized
    case denied
    case restricted
}

/// One fresh fix. Discarded after the distance decision. Never stored.
struct SaveInkFix: Equatable {
    var authorization: SaveInkAuthorization
    var precise: Bool
    var timedOut: Bool
    var distanceMeters: Double?
    var horizontalAccuracyMeters: Double?
    var ageSeconds: TimeInterval?
    var isSimulated: Bool

    static func inRange(meters: Double = 18, accuracy: Double = 12) -> SaveInkFix {
        SaveInkFix(
            authorization: .authorized,
            precise: true,
            timedOut: false,
            distanceMeters: meters,
            horizontalAccuracyMeters: accuracy,
            ageSeconds: 1,
            isSimulated: false
        )
    }
}

enum SaveInkCheckInSituation: Equatable {
    case verified
    case locationFailed
    case placeChanged
    case permissionDenied
    case approximateOnly
    case tooFar(meters: Int)
    case downgradedUnverified
    case duplicate

    var id: String {
        switch self {
        case .verified: "verified"
        case .locationFailed: "failed"
        case .placeChanged: "place-changed"
        case .permissionDenied: "permission"
        case .approximateOnly: "approximate"
        case .tooFar(let meters): "far-\(meters)"
        case .downgradedUnverified: "downgraded"
        case .duplicate: "duplicate"
        }
    }
}

struct SaveInkCheckInDecision: Equatable {
    var situation: SaveInkCheckInSituation
    var recordsVisit: Bool
    var verification: SaveInkVerification
    var anomaly: SaveInkAnomaly?
}

/// A visit and its comment share one visibility. Coordinates are not a field.
struct SaveInkVisitRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var placeID: String
    var visitedAt: Date
    var verification: SaveInkVerification
    var visibility: SaveInkVisibility
    var comment: String
    var sentiment: SaveInkSentiment?
    var anomaly: SaveInkAnomaly?
}

enum SaveInkAccountPurgeError: Error {
    case unreadablePlaces
}

enum SaveInkPlaceBadge: Equatable {
    case visited
    case saved
    case unverified
}

struct SaveInkSavedPlaceRecord: Codable, Equatable {
    var id: String
    var name: String
    var stampName: String
    var street: String
    var blurb: String
    var sourceLabel: String
    var detailNote: String
    /// Nil on records saved before accounts were recorded, and while signed out.
    var ownerSubject: String? = nil
}

struct SaveInkPlace: Identifiable, Equatable {
    var id: String
    var name: String
    var stampName: String
    var street: String
    var distanceMeters: Double?
    var blurb: String
    var sourceLabel: String
    var badge: SaveInkPlaceBadge
    var detailNote: String
    var friendUsualCount: Int
    var walkMinutes: Int?
    var addressLine: String?
    var videoTitle: String?
    var videoSource: String?
    /// Shop position used only to measure a one-shot fix. Not written onto a visit.
    var shopLatitude: Double?
    var shopLongitude: Double?
    /// Former stamp ids folded into this row by `Place.consolidated`.
    var aliasIDs: [String] = []
    /// Transient display provenance. User-authored notes must not be translated
    /// even when their text happens to equal a generated fallback label.
    var blurbIsUserContent = false
    var detailNoteIsUserContent = false

    var meta: String {
        let streetText = street
        guard let distanceMeters else { return streetText }
        return "\(streetText)・\(SaveInkClock.distance(distanceMeters))"
    }
}

struct SaveInkFriendVisitInput: Equatable {
    var authorID: String
    var authorName: String
    var placeID: String
    var placeName: String
    var street: String
    var comment: String
    var visitedAt: Date
    var verification: SaveInkVerification
    var visibility: SaveInkVisibility
}

enum SaveInkFriendSegment: String, Equatable {
    case verified
    case unverified
}

struct SaveInkFriendCard: Identifiable, Equatable {
    var id: String
    var authorName: String
    var placeName: String
    var street: String
    var comment: String
    var verifiedCount: Int
    var latestAt: Date
    var segment: SaveInkFriendSegment

    func subtitle(now: Date, language: AppLanguage = .traditionalChinese) -> String {
        let when = SaveInkClock.ago(latestAt, now: now, language: language)
        switch segment {
        case .verified:
            return language.localized(english: "\(verifiedCount) visits · \(when)", traditionalChinese: "去過 \(verifiedCount) 次・\(when)")
        case .unverified:
            return when
        }
    }
}

enum SaveInkRoute: Hashable {
    case passport
    case place(String)
    case friends
    case review(String)
    case arrival(String)
    case welcome
}

enum SaveInkSheet: Equatable, Identifiable {
    case save
    case checkIn(SaveInkCheckInSituation, placeID: String)

    var id: String {
        switch self {
        case .save:
            return "save"
        case .checkIn(let situation, let placeID):
            return "checkin-\(placeID)-\(situation.id)"
        }
    }
}

enum SaveInkPreviewScreen: String, CaseIterable {
    case main = "01-main"
    case savePlace = "02-save-place"
    case passport = "03-passport"
    case stampConfirm = "04-stamp-confirm"
    case shopDetail = "05-shop-detail"
    case welcome = "06-welcome"
    case checkInSuccess = "07-checkin-success"
    case checkInFailed = "08-checkin-failed"
    case checkInNoPermission = "09-checkin-no-permission"
    case checkInApproximate = "10-checkin-approximate"
    case checkInTooFar = "11-checkin-too-far"
    case friends = "12-friends"
    case reviewVisibility = "13-review-visibility"
    case friendsEmpty = "14-friends-empty"
}

enum SaveInkClock {
    static var taipei: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .gmt
        return calendar
    }

    static let previewNow: Date = date(2026, 11, 1, 12)

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        return taipei.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    static func stampDate(_ date: Date) -> String {
        let parts = taipei.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func shortDate(_ date: Date) -> String {
        let parts = taipei.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }

    static func ago(_ date: Date, now: Date, language: AppLanguage = .traditionalChinese) -> String {
        let days = taipei.dateComponents(
            [.day],
            from: taipei.startOfDay(for: date),
            to: taipei.startOfDay(for: now)
        ).day ?? 0
        if days <= 0 { return language.localized(english: "Today", traditionalChinese: "今天") }
        if days < 7 { return language.localized(english: days == 1 ? "1 day ago" : "\(days) days ago", traditionalChinese: "\(days) 天前") }
        if days < 14 { return language.localized(english: "1 week ago", traditionalChinese: "1 週前") }
        return language.localized(english: "\(days / 7) weeks ago", traditionalChinese: "\(days / 7) 週前")
    }

    static func distance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }
}

enum SaveInkSeed {
    static func of(_ text: String) -> Int {
        var hash = 5381
        for byte in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return hash
    }
}

enum SaveInkCheckIn {
    static func decide(
        fix: SaveInkFix,
        verifiedToday: Int,
        impliedSpeedKmh: Double?
    ) -> SaveInkCheckInDecision {
        if fix.authorization == .denied || fix.authorization == .restricted {
            return unverified(.permissionDenied, anomaly: nil)
        }
        if fix.authorization == .authorized && !fix.precise {
            return unverified(.approximateOnly, anomaly: nil)
        }
        if !usable(fix) {
            return unverified(.locationFailed, anomaly: nil)
        }
        let meters = fix.distanceMeters ?? 0
        if meters > SaveInkProvisional.radiusMeters {
            return SaveInkCheckInDecision(
                situation: .tooFar(meters: Int(meters.rounded())),
                recordsVisit: false,
                verification: .unverified,
                anomaly: nil
            )
        }
        if fix.isSimulated {
            return unverified(.downgradedUnverified, anomaly: .simulatedLocation)
        }
        if let impliedSpeedKmh, impliedSpeedKmh > SaveInkProvisional.maxSpeedKmh {
            return unverified(.downgradedUnverified, anomaly: .implausibleSpeed)
        }
        if verifiedToday >= SaveInkProvisional.dailyVerifiedCap {
            return unverified(.downgradedUnverified, anomaly: .dailyCap)
        }
        return SaveInkCheckInDecision(
            situation: .verified,
            recordsVisit: true,
            verification: .verified,
            anomaly: nil
        )
    }

    private static func usable(_ fix: SaveInkFix) -> Bool {
        guard fix.authorization == .authorized, !fix.timedOut else { return false }
        guard let distance = fix.distanceMeters, distance >= 0 else { return false }
        guard let accuracy = fix.horizontalAccuracyMeters, accuracy >= 0 else { return false }
        guard accuracy <= SaveInkProvisional.maxAccuracyMeters else { return false }
        guard let age = fix.ageSeconds, age >= 0 else { return false }
        return age <= SaveInkProvisional.maxFixAge
    }

    private static func unverified(
        _ situation: SaveInkCheckInSituation,
        anomaly: SaveInkAnomaly?
    ) -> SaveInkCheckInDecision {
        SaveInkCheckInDecision(
            situation: situation,
            recordsVisit: true,
            verification: .unverified,
            anomaly: anomaly
        )
    }

    static func impliedSpeedKmh(
        from previous: (date: Date, latitude: Double, longitude: Double)?,
        to latitude: Double?,
        longitude: Double?,
        now: Date
    ) -> Double? {
        guard
            let previous,
            let latitude,
            let longitude
        else { return nil }
        let elapsed = now.timeIntervalSince(previous.date)
        guard elapsed > 0 else { return nil }
        let meters = haversine(
            latitude1: previous.latitude,
            longitude1: previous.longitude,
            latitude2: latitude,
            longitude2: longitude
        )
        return meters / elapsed * 3.6
    }

    static func haversine(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let radius = 6_371_000.0
        let phi1 = latitude1 * .pi / 180
        let phi2 = latitude2 * .pi / 180
        let dPhi = (latitude2 - latitude1) * .pi / 180
        let dLambda = (longitude2 - longitude1) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * radius * atan2(sqrt(a), sqrt(1 - a))
    }
}

enum SaveInkApplyKind: Equatable {
    case inserted(UUID)
    case upgraded(UUID)
    case suppressed
    case ignored
}

enum SaveInkVisitBook {
    static func apply(
        decision: SaveInkCheckInDecision,
        placeID: String,
        now: Date,
        visits: inout [SaveInkVisitRecord],
        recordTooFar: Bool = false
    ) -> SaveInkApplyKind {
        let verification: SaveInkVerification
        if recordTooFar {
            verification = .unverified
        } else if decision.recordsVisit {
            verification = decision.verification
        } else {
            return .ignored
        }

        if verification == .verified && decision.anomaly == nil {
            if let index = visits.lastIndex(where: { visit in
                visit.placeID == placeID
                    && visit.verification == .unverified
                    && now.timeIntervalSince(visit.visitedAt) >= 0
                    && now.timeIntervalSince(visit.visitedAt) <= SaveInkProvisional.upgradeWindow
            }) {
                visits[index].verification = .verified
                visits[index].visitedAt = now
                visits[index].anomaly = nil
                return .upgraded(visits[index].id)
            }
        }

        let recent = visits.contains { visit in
            visit.placeID == placeID
                && now.timeIntervalSince(visit.visitedAt) >= 0
                && now.timeIntervalSince(visit.visitedAt) <= SaveInkProvisional.samePlaceWindow
        }
        if recent {
            return .suppressed
        }

        let record = SaveInkVisitRecord(
            id: UUID(),
            placeID: placeID,
            visitedAt: now,
            verification: verification,
            visibility: SaveInkProvisional.defaultVisibility,
            comment: "",
            sentiment: nil,
            anomaly: recordTooFar ? nil : decision.anomaly
        )
        visits.append(record)
        return .inserted(record.id)
    }
}

enum SaveInkFriends {
    static func cards(from inputs: [SaveInkFriendVisitInput]) -> [SaveInkFriendCard] {
        let visible = inputs.filter { $0.visibility == .public }
        let groups = Dictionary(grouping: visible) { "\($0.authorID)|\($0.placeID)" }
        let cards = groups.map { key, visits -> SaveInkFriendCard in
            let verified = visits.filter { $0.verification == .verified }
            let segment: SaveInkFriendSegment = verified.isEmpty ? .unverified : .verified
            let pool = segment == .verified ? verified : visits
            let latest = pool.max { $0.visitedAt < $1.visitedAt } ?? visits[0]
            let commentSource = pool.filter { !$0.comment.isEmpty }.max { $0.visitedAt < $1.visitedAt }
            let sample = visits[0]
            return SaveInkFriendCard(
                id: key,
                authorName: sample.authorName,
                placeName: sample.placeName,
                street: sample.street,
                comment: commentSource?.comment ?? "",
                verifiedCount: verified.count,
                latestAt: latest.visitedAt,
                segment: segment
            )
        }
        return cards.sorted { lhs, rhs in
            if lhs.segment != rhs.segment {
                return lhs.segment == .verified
            }
            if lhs.segment == .verified && lhs.verifiedCount != rhs.verifiedCount {
                return lhs.verifiedCount > rhs.verifiedCount
            }
            if lhs.latestAt != rhs.latestAt {
                return lhs.latestAt > rhs.latestAt
            }
            return lhs.authorName < rhs.authorName
        }
    }
}

/// A link is not a place unless the text names a known shop or is a map link.
enum SaveInkPlaceLink {
    static let notAPlaceMessage = "這則跟地點無關，所以沒有存成地點，不會出現在地圖上，也不能蓋章。"

    static func rejects(_ text: String, knownPlaces: [SaveInkPlace]) -> Bool {
        let names = knownPlaces.flatMap { [$0.name, $0.street] }
        return SavePlaceLinkGate.rejects(urlString: text, evidence: text, knownPlaceNames: names)
    }

    static func hasPlaceEvidence(_ text: String, knownPlaces: [SaveInkPlace]) -> Bool {
        if linkedPlace(in: text, knownPlaces: knownPlaces) != nil { return true }
        guard let url = firstURL(in: text) else { return false }
        return isMapLink(url)
    }

    static func linkedPlace(in text: String, knownPlaces: [SaveInkPlace]) -> SaveInkPlace? {
        knownPlaces.first { place in
            text.contains(place.name) || (!place.street.isEmpty && text.contains(place.street))
        }
    }

    static func savedName(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = firstURL(in: trimmed) else { return trimmed }
        let caption = trimmed
            .replacingOccurrences(of: url.absoluteString, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return caption.isEmpty ? trimmed : caption
    }

    private static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
    }

    private static func isMapLink(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("maps.") || host.contains("openstreetmap.org") || url.path.contains("/maps")
    }

    /// A venue name carried by a map link, such as `?q=` or `/maps/place/`.
    /// A coordinate-only link has no name.
    static func mapPlaceName(in text: String) -> String? {
        guard let url = firstURL(in: text), isMapLink(url) else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for key in ["q", "query", "name", "address"] {
            guard let value = items.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  !value.contains("://"),
                  value.rangeOfCharacter(from: CharacterSet.letters) != nil
            else { continue }
            return value
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(where: { $0 == "place" || $0 == "search" }),
              index + 1 < parts.count else { return nil }
        let raw = parts[index + 1].split(separator: "@").first.map(String.init) ?? parts[index + 1]
        let decoded = raw.removingPercentEncoding ?? raw
        let cleaned = decoded.replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.rangeOfCharacter(from: CharacterSet.letters) != nil else { return nil }
        return cleaned
    }

    static func isUnresolvedMapLink(_ text: String) -> Bool {
        guard let url = firstURL(in: text), isMapLink(url) else { return false }
        return mapPlaceName(in: text) == nil
    }
}

/// Visit JSON written before visibility existed. A missing field stays public.
private struct SaveInkLegacyVisit: Decodable {
    var id: UUID
    var placeID: String
    var visitedAt: Date
    var verification: SaveInkVerification
    var visibility: SaveInkVisibility?
    var comment: String
    var sentiment: SaveInkSentiment?
    var anomaly: SaveInkAnomaly?

    var record: SaveInkVisitRecord {
        SaveInkVisitRecord(
            id: id,
            placeID: placeID,
            visitedAt: visitedAt,
            verification: verification,
            visibility: visibility ?? SaveInkProvisional.defaultVisibility,
            comment: comment,
            sentiment: sentiment,
            anomaly: anomaly
        )
    }
}

protocol SaveInkLocating: AnyObject {
    func requestFix(for place: SaveInkPlace) async -> SaveInkFix
}

final class SaveInkScriptedLocator: SaveInkLocating {
    var fix: SaveInkFix
    var calls = 0

    init(fix: SaveInkFix = .inRange()) {
        self.fix = fix
    }

    func requestFix(for place: SaveInkPlace) async -> SaveInkFix {
        calls += 1
        return fix
    }
}

@MainActor
final class SaveInkNotebookStore: ObservableObject {
    @Published private(set) var visits: [SaveInkVisitRecord]
    @Published private(set) var places: [SaveInkPlace]
    @Published var path: [SaveInkRoute] = []
    @Published var sheet: SaveInkSheet?
    @Published var draftComment = ""
    @Published var draftSentiment: SaveInkSentiment?
    @Published var draftVisibility: SaveInkVisibility = SaveInkProvisional.defaultVisibility
    @Published var saveLink = "" {
        didSet { if saveLink != oldValue { recognizedPlaceID = nil } }
    }
    @Published var saveQuery = "" {
        didSet { if saveQuery != oldValue { recognizedPlaceID = nil } }
    }
    @Published var saveNotice: String?
    @Published var recognizedPlaceID: String?
    @Published var activePlaceID: String?
    @Published private(set) var usesLivePlaces: Bool
    @Published private(set) var userCoordinate: CLLocationCoordinate2D?

    let city = "大安區"
    let includesSampleCatalog: Bool
    let friendInputs: [SaveInkFriendVisitInput]
    private let defaults: UserDefaults
    private let placesDefaults: UserDefaults
    private let storageKey = "save.ink.visits.v1"
    private let placesKey = SavePlaceLinkGate.placesKey
    private let now: () -> Date
    private let makeLocator: () -> any SaveInkLocating
    private let liveLoader: SaveInkLivePlaceLoader
    private let liveOwner: () -> String?
    private let canSaveAnotherLivePlace: @MainActor (Int) -> Bool
    private let liveSavedPlaceTierIsAuthoritative: @MainActor () -> Bool
    private let parkCappedLiveSave: (@MainActor (String) -> Bool)?
    private var refreshTask: Task<Void, Never>?
    private var refreshQueued = false
    private var locator: (any SaveInkLocating)?
    private var pendingSituation: SaveInkCheckInSituation?
    /// Account that opened the check-in sheet. 「還是記下」refuses a later account.
    private var checkInOwner: String?
    /// Account whose places are on screen. A save refuses a different account.
    private var catalogOwner: String?
    private var liveGeneration = 0
    /// True after a load that knew the full saved-place count. New live saves
    /// wait for that, so a partial local list cannot admit a 51st stamp.
    private var liveCatalogAuthoritative = false

    var currentDate: Date { now() }

    /// `seedFixture` is the screenshot and UI-test catalog: five sample shops,
    /// friend cards, and first-launch check-ins. Normal launch leaves it false.
    /// `includeSampleCatalog` keeps those shops in memory without writing check-ins.
    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        seedFixture: Bool = false,
        includeSampleCatalog: Bool = false,
        friendInputs: [SaveInkFriendVisitInput]? = nil,
        makeLocator: @escaping () -> any SaveInkLocating = { SaveInkOneShotLocator() },
        usesLivePlaces: Bool = false,
        liveLoader: SaveInkLivePlaceLoader? = nil,
        liveOwner: @escaping () -> String? = {
            let auth = PrivyAuthService.shared
            return SaveInkNotebookStore.resolvedLiveOwner(
                authUnknown: auth.authState == .unknown,
                currentUserId: auth.currentUserId,
                cachedOwner: SavePlaceLimitHandoff.cachedActiveOwner()
            )
        },
        canSaveAnotherLivePlace: @escaping @MainActor (Int) -> Bool = SaveInkNotebookStore.allowsAnotherLivePlace,
        liveSavedPlaceTierIsAuthoritative: @escaping @MainActor () -> Bool = {
            SaveEntitlementStore.shared.hasAuthoritativeSavedPlaceTier
        },
        parkCappedLiveSave: (@MainActor (String) -> Bool)? = nil
    ) {
        self.defaults = defaults
        let placesDefaults = Self.placesDefaults(for: defaults)
        self.placesDefaults = placesDefaults
        self.now = now
        self.makeLocator = makeLocator
        self.usesLivePlaces = usesLivePlaces
        self.includesSampleCatalog = !usesLivePlaces && (seedFixture || includeSampleCatalog)
        let loader = liveLoader ?? (usesLivePlaces ? SaveInkLivePlaceLoader.production() : .inactive)
        self.liveLoader = loader
        self.liveOwner = liveOwner
        self.canSaveAnotherLivePlace = canSaveAnotherLivePlace
        self.liveSavedPlaceTierIsAuthoritative = liveSavedPlaceTierIsAuthoritative
        self.parkCappedLiveSave = parkCappedLiveSave
        if usesLivePlaces { catalogOwner = liveOwner() }
        let saved = Self.loadSavedPlaces(
            defaults: placesDefaults, key: placesKey,
            owner: usesLivePlaces ? liveOwner() : nil, scoped: usesLivePlaces
        )
        let loadedVisits: [SaveInkVisitRecord]
        if usesLivePlaces {
            loadedVisits = Self.load(defaults: defaults, key: Self.visitsKey(owner: liveOwner())) ?? []
        } else if seedFixture {
            if let stored = Self.load(defaults: defaults, key: storageKey) {
                loadedVisits = stored
            } else {
                loadedVisits = SaveInkFixture.visits()
                Self.save(loadedVisits, defaults: defaults, key: storageKey)
            }
        } else {
            loadedVisits = Self.visitsWithoutPersistedSamples(defaults: defaults, key: storageKey)
        }
        self.visits = loadedVisits
        if usesLivePlaces {
            self.places = loader.localPlaces(saved)
        } else if includesSampleCatalog {
            self.places = SaveInkFixture.places + saved
        } else {
            self.places = saved + Self.placesForRetainedSampleVisits(loadedVisits, alreadyLoaded: saved)
        }
        if let friendInputs {
            self.friendInputs = friendInputs
        } else if seedFixture && !usesLivePlaces {
            self.friendInputs = SaveInkFixture.friendInputs(now: SaveInkClock.previewNow)
        } else {
            self.friendInputs = []
        }
        if usesLivePlaces { reflectVisitBadges() }
    }

    func homePlaces() -> [SaveInkPlace] {
        if usesLivePlaces { return places }
        let saved = places.filter { $0.id.hasPrefix("saved-") }
        guard includesSampleCatalog else { return saved }
        let featured = [SaveInkFixture.dingtai, SaveInkFixture.qingtian, SaveInkFixture.chifeng]
        let main = featured.compactMap { id in places.first { $0.id == id } }
        return main + saved
    }

    /// Home's location-check target. Unlocated saves use the explicit unverified entry.
    func arrivalPlaceID() -> String? {
        if usesLivePlaces { return liveArrivalPlaceID() }
        return homePlaces().first { $0.shopLatitude != nil && $0.shopLongitude != nil }?.id
    }

    /// Sample shops stay off Home. A visit the user kept still needs a name and stamp.
    private static func placesForRetainedSampleVisits(
        _ visits: [SaveInkVisitRecord],
        alreadyLoaded: [SaveInkPlace]
    ) -> [SaveInkPlace] {
        let referenced = Set(visits.map(\.placeID))
        let known = Set(alreadyLoaded.map(\.id))
        return SaveInkFixture.places
            .filter { referenced.contains($0.id) && !known.contains($0.id) }
            .map { place in
                SaveInkPlace(
                    id: place.id, name: place.name, stampName: place.stampName, street: place.street,
                    distanceMeters: nil, blurb: "你保留的到訪紀錄", sourceLabel: "來自 你的到訪紀錄",
                    badge: .visited, detailNote: "你保留的到訪紀錄。", friendUsualCount: 0,
                    walkMinutes: nil, addressLine: nil, videoTitle: nil, videoSource: nil,
                    shopLatitude: nil, shopLongitude: nil
                )
            }
    }

    func openFriends() {
        path.append(.friends)
    }

    func openPassport() {
        path.append(.passport)
    }

    func openPlace(_ id: String) {
        let resolved = place(id)?.id ?? id
        activePlaceID = resolved
        path.append(.place(resolved))
    }

    func openWelcome() {
        path.append(.welcome)
    }

    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func friendCards() -> [SaveInkFriendCard] {
        SaveInkFriends.cards(from: friendInputs)
    }

    func place(_ id: String) -> SaveInkPlace? {
        if let exact = places.first(where: { $0.id == id }) { return exact }
        return places.first { $0.aliasIDs.contains(id) }
    }

    /// The Home「我到了」target. Live mode uses it only when a place has a
    /// measured distance, so a denied location cannot check in the first name.
    func liveArrivalPlaceID() -> String? {
        guard usesLivePlaces, let nearest = places.first, nearest.distanceMeters != nil else { return nil }
        return nearest.id
    }

    func verifiedCount(for placeID: String) -> Int {
        visits.filter { $0.placeID == placeID && $0.verification == .verified }.count
    }

    func visitCount(for placeID: String) -> Int {
        visits.filter { $0.placeID == placeID }.count
    }

    func homeSummary(count: Int, language: AppLanguage = .traditionalChinese) -> String {
        guard count > 0 else { return language.localized(english: "No saved places yet", traditionalChinese: "還沒有地點") }
        let english = count == 1 ? "1 place for you" : "\(count) places for you"
        return language.localized(
            english: english,
            traditionalChinese: includesSampleCatalog ? "今天在\(city)，挑了 \(count) 個給你" : "挑了 \(count) 個給你"
        )
    }

    func detailNote(for place: SaveInkPlace) -> String {
        if !includesSampleCatalog, !place.detailNoteIsUserContent,
           place.shopLatitude == nil || place.shopLongitude == nil,
           place.detailNote == "剛存下來，到了再按「我到了」。" {
            return "剛存下來。可以記錄到訪（未驗證）。"
        }
        return place.detailNote
    }

    func homeBadge(for place: SaveInkPlace) -> SaveInkPlaceBadge {
        guard !includesSampleCatalog else { return place.badge }
        if verifiedCount(for: place.id) > 0 { return .visited }
        if latestVisit(for: place.id) != nil { return .unverified }
        return usesLivePlaces ? place.badge : .saved
    }

    func totalVisits() -> Int {
        visits.count
    }

    func stampedPlaceIDs() -> [String] {
        var seen: [String] = []
        for visit in visits.sorted(by: { $0.visitedAt > $1.visitedAt }) where !seen.contains(visit.placeID) {
            seen.append(visit.placeID)
        }
        return seen
    }

    func latestVisit(for placeID: String) -> SaveInkVisitRecord? {
        visits.filter { $0.placeID == placeID }.max { $0.visitedAt < $1.visitedAt }
    }

    func checkIn(placeID: String) async {
        let ownerAtStart = usesLivePlaces ? liveOwner() : nil
        if usesLivePlaces, ownerAtStart != catalogOwner {
            sheet = nil
            return
        }
        guard let place = place(placeID) else { return }
        activePlaceID = placeID
        let fix = await locatorOrMake().requestFix(for: place)
        if usesLivePlaces, liveOwner() != ownerAtStart || catalogOwner != ownerAtStart { return }
        guard let currentPlace = self.place(placeID) else { return }
        let placeID = currentPlace.id
        activePlaceID = placeID
        checkInOwner = ownerAtStart
        guard currentPlace.shopLatitude == place.shopLatitude,
              currentPlace.shopLongitude == place.shopLongitude else {
            pendingSituation = .placeChanged
            sheet = .checkIn(.placeChanged, placeID: placeID)
            return
        }
        let previous = previousShop(before: placeID)
        let speed = SaveInkCheckIn.impliedSpeedKmh(
            from: previous,
            to: currentPlace.shopLatitude,
            longitude: currentPlace.shopLongitude,
            now: now()
        )
        let decision = SaveInkCheckIn.decide(
            fix: fix,
            verifiedToday: verifiedTodayCount(),
            impliedSpeedKmh: speed
        )
        let outcome = SaveInkVisitBook.apply(
            decision: decision,
            placeID: placeID,
            now: now(),
            visits: &visits
        )
        switch outcome {
        case .ignored:
            if case .tooFar(_) = decision.situation {
                pendingSituation = decision.situation
                sheet = .checkIn(decision.situation, placeID: placeID)
            }
        case .suppressed:
            pendingSituation = .duplicate
            sheet = .checkIn(.duplicate, placeID: placeID)
        case .inserted(_), .upgraded(_):
            persist(owner: ownerAtStart)
            markVisited(placeID)
            pendingSituation = decision.situation
            prepareDraft(placeID: placeID)
            sheet = .checkIn(decision.situation, placeID: placeID)
        }
    }

    /// The user explicitly records a visit without claiming location proof.
    func recordUnverifiedVisit(placeID: String) {
        let owner = usesLivePlaces ? liveOwner() : nil
        if usesLivePlaces, owner != catalogOwner {
            sheet = nil
            return
        }
        guard let place = place(placeID),
              place.shopLatitude == nil || place.shopLongitude == nil else { return }
        let placeID = place.id
        activePlaceID = placeID
        checkInOwner = owner
        let outcome = SaveInkVisitBook.apply(
            decision: SaveInkCheckInDecision(
                situation: .downgradedUnverified, recordsVisit: true,
                verification: .unverified, anomaly: nil
            ),
            placeID: placeID, now: now(), visits: &visits
        )
        persist(owner: owner)
        if case .inserted = outcome { markVisited(placeID) }
        prepareDraft(placeID: placeID)
        let situation: SaveInkCheckInSituation = outcome == .suppressed ? .duplicate : .downgradedUnverified
        pendingSituation = situation
        sheet = .checkIn(situation, placeID: placeID)
    }

    func saveAnyway() {
        guard case .checkIn(.tooFar(_), let placeID)? = sheet else { return }
        if usesLivePlaces, liveOwner() != checkInOwner || catalogOwner != checkInOwner {
            sheet = nil
            pendingSituation = nil
            return
        }
        let decision = SaveInkCheckInDecision(
            situation: .tooFar(meters: 0),
            recordsVisit: false,
            verification: .unverified,
            anomaly: nil
        )
        _ = SaveInkVisitBook.apply(
            decision: decision,
            placeID: placeID,
            now: now(),
            visits: &visits,
            recordTooFar: true
        )
        persist(owner: usesLivePlaces ? checkInOwner : nil)
        markVisited(placeID)
        prepareDraft(placeID: placeID)
        pendingSituation = .downgradedUnverified
        sheet = .checkIn(.downgradedUnverified, placeID: placeID)
    }

    func cancelSheet() {
        sheet = nil
        pendingSituation = nil
    }

    func retryCheckIn() async {
        guard case .checkIn(_, let placeID)? = sheet else { return }
        sheet = nil
        await checkIn(placeID: placeID)
    }

    func beginReview() {
        guard case .checkIn(_, let placeID)? = sheet ?? nilSheet(placeID: activePlaceID) else { return }
        sheet = nil
        prepareDraft(placeID: placeID)
        path.append(.review(placeID))
    }

    func beginArrival() {
        guard case .checkIn(_, let placeID)? = sheet else { return }
        sheet = nil
        prepareDraft(placeID: placeID)
        path.append(.arrival(placeID))
    }

    func commitDraft() {
        if pendingSituation == .placeChanged {
            cancelSheet()
            return
        }
        if usesLivePlaces, liveOwner() != checkInOwner || catalogOwner != checkInOwner {
            sheet = nil
            path.removeAll()
            return
        }
        let placeID = activePlaceID ?? ""
        if let index = visits.lastIndex(where: { $0.placeID == placeID }) {
            visits[index].comment = draftComment.trimmingCharacters(in: .whitespacesAndNewlines)
            visits[index].visibility = draftVisibility
            visits[index].sentiment = draftSentiment
            persist(owner: usesLivePlaces ? checkInOwner : nil)
        }
        sheet = nil
        path.removeAll()
    }

    func pasteExampleLink() {
        if usesLivePlaces {
            paste(liveText: UIPasteboard.general.string)
            return
        }
        guard includesSampleCatalog, place(SaveInkFixture.qingtian) != nil else { return }
        saveLink = "https://短影音連結/v/8f2k…"
        recognizedPlaceID = SaveInkFixture.qingtian
    }

    /// Live 「貼上」 reads the clipboard. It does not insert the fixture link
    /// or point at the fixture place. An empty clipboard leaves the field alone.
    func paste(liveText: String?) {
        guard usesLivePlaces else {
            pasteExampleLink()
            return
        }
        let pasted = liveText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pasted.isEmpty else { return }
        saveLink = pasted
        recognizedPlaceID = nil
        recognizeQuery()
    }

    func recognizeQuery() {
        let query = [saveLink, saveQuery]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        if let match = places.first(where: { query.contains($0.name) || (!query.contains("://") && $0.name.contains(query)) || query.contains($0.street) }) {
            recognizedPlaceID = match.id
        }
    }

    func commitSave() {
        if usesLivePlaces, liveOwner() != catalogOwner {
            sheet = nil
            return
        }
        if let id = recognizedPlaceID, place(id) == nil {
            recognizedPlaceID = nil
        }
        recognizeQuery()
        if !usesLivePlaces && !includesSampleCatalog, let id = recognizedPlaceID,
           !id.hasPrefix("saved-"), var retained = place(id) {
            let savedID = "saved-\(id)"
            places.removeAll { $0.id == id }
            if place(savedID) == nil {
                retained.id = savedID
                places.append(retained)
            }
            for index in visits.indices where visits[index].placeID == id {
                visits[index].placeID = savedID
            }
            if activePlaceID == id { activePlaceID = savedID }
            path = path.map { route in
                switch route {
                case .place(id): .place(savedID)
                case .review(id): .review(savedID)
                case .arrival(id): .arrival(savedID)
                default: route
                }
            }
            persist()
            recognizedPlaceID = savedID
        }
        let combined = [saveLink, saveQuery].joined(separator: " ")
        if recognizedPlaceID == nil, SaveInkPlaceLink.rejects(combined, knownPlaces: places) {
            saveNotice = SaveInkPlaceLink.notAPlaceMessage
            return
        }
        saveNotice = nil
        var appendedIndex: Int?
        var proposedName: String?
        if recognizedPlaceID == nil {
            if !saveQuery.isEmpty {
                proposedName = SaveInkPlaceLink.savedName(from: saveQuery)
            } else if let mapName = SaveInkPlaceLink.mapPlaceName(in: combined) {
                proposedName = mapName
            } else if SaveInkPlaceLink.isUnresolvedMapLink(combined) {
                saveNotice = "這則地圖連結還沒有店名。在下面寫下店名再存。"
                return
            }
        }
        if let name = proposedName {
            if usesLivePlaces, refreshTask != nil || !liveCatalogAuthoritative {
                saveNotice = "還在核對已存的地點，請稍後再存。"
                return
            }
            if usesLivePlaces, !liveSavedPlaceTierIsAuthoritative() {
                saveNotice = "還在核對可以存幾個地點，請稍後再存。"
                return
            }
            if usesLivePlaces, !canSaveAnotherLivePlace(places.count) {
                let parked = parkCappedLiveSave?(name) ?? parkLiveNameOffTheMap(name)
                saveNotice = parked
                    ? "已存 50 個地點，所以暫放，還沒放上地圖。"
                    : "已存 50 個地點，這次沒有存下來。請稍後再試。"
                return
            }
            let place = SaveInkPlace(
                id: "saved-\(SaveInkSeed.of(name))",
                name: name,
                stampName: name,
                street: name,
                distanceMeters: nil,
                blurb: "剛存的",
                sourceLabel: "來自 你貼上的店名",
                badge: .saved,
                detailNote: "剛存下來，到了再按「我到了」。",
                friendUsualCount: 0,
                walkMinutes: nil,
                addressLine: nil,
                videoTitle: nil,
                videoSource: nil,
                shopLatitude: nil,
                shopLongitude: nil
            )
            places.append(place)
            recognizedPlaceID = place.id
            appendedIndex = places.count - 1
        }
        if let id = recognizedPlaceID, let index = places.firstIndex(where: { $0.id == id }) {
            if places[index].badge != .visited {
                places[index].badge = .saved
            }
        }
        guard persistPlaces() else {
            if let appendedIndex, places.indices.contains(appendedIndex) {
                let removed = places.remove(at: appendedIndex)
                if recognizedPlaceID == removed.id {
                    recognizedPlaceID = nil
                }
            }
            saveNotice = "這次沒有存下來。請稍後再試。"
            return
        }
        sheet = nil
        if usesLivePlaces {
            Task { await refreshLivePlaces() }
        }
    }

    /// While sign-in is still restoring, the cached account is the owner.
    /// `currentUserId` is nil until that finishes, so the two must not diverge.
    static func resolvedLiveOwner(authUnknown: Bool, currentUserId: String?, cachedOwner: String?) -> String? {
        if authUnknown { return cachedOwner }
        return currentUserId
    }

    /// Same cap as the share queue. The caller waits until the tier is known.
    /// This check fails open only after that, so a resolved Pro account is not parked.
    private static func allowsAnotherLivePlace(count: Int) -> Bool {
        guard SaveEntitlementStore.shared.hasAuthoritativeSavedPlaceTier else { return true }
        return SavePlaceLimitGate.decide(
            tier: SaveEntitlementStore.shared.tier,
            savedPlaceCount: count
        ) != .overFreeLimit
    }

    /// The 51st free save stays off the map. It is parked as a review item.
    private func parkLiveNameOffTheMap(_ name: String) -> Bool {
        let pending = PendingSharedPlace(
            ownerSubject: liveOwner(),
            name: name,
            address: name,
            category: "food",
            latitude: 0,
            longitude: 0,
            dishes: [],
            savedAt: now()
        )
        let candidate = PlaceReviewCandidate.unplacedInboxItem(
            from: Place.from(pending),
            ownerSubject: liveOwner()
        )
        do {
            _ = try SaveLocalVaultService.shared.saveReviewCandidate(candidate, preservingParkedContext: true)
            return true
        } catch {
            return false
        }
    }

    /// Reloads vault stamps, the share queue, and ink saves. Fixture launches
    /// no-op so screenshot baselines and ink UI tests keep their seeded rows.
    /// Overlapping callers wait for the in-flight load, then run one more pass.
    func refreshLivePlaces() async {
        guard usesLivePlaces else { return }
        if refreshTask != nil {
            refreshQueued = true
            await refreshTask?.value
            return
        }
        let task = Task { @MainActor in
            await self.performLiveRefresh()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
        if refreshQueued {
            refreshQueued = false
            await refreshLivePlaces()
        }
    }

    private func performLiveRefresh() async {
        liveGeneration += 1
        let generation = liveGeneration
        let owner = liveOwner()
        let ink = Self.loadSavedPlaces(
            defaults: placesDefaults,
            key: placesKey,
            owner: owner,
            scoped: true
        )
        let loaded = await liveLoader.load(ink)
        guard generation == liveGeneration else { return }
        guard liveOwner() == owner else { return }
        catalogOwner = owner
        places = loaded.places
        userCoordinate = loaded.userCoordinate
        liveCatalogAuthoritative = loaded.countIsAuthoritative
        retargetOpenPlaces()
        let visitKey = Self.visitsKey(owner: owner)
        if let stored = Self.load(defaults: defaults, key: visitKey) {
            visits = stored
        } else {
            visits = []
        }
        rekeyVisits(using: loaded.places)
        reflectVisitBadges()
    }

    func openSave() {
        sheet = .save
    }

    func openSettings() {
        SaveInkSettingsOpener.open()
    }

    private func nilSheet(placeID: String?) -> SaveInkSheet? {
        guard let placeID else { return nil }
        return .checkIn(.verified, placeID: placeID)
    }

    private func locatorOrMake() -> any SaveInkLocating {
        if let locator { return locator }
        let created = makeLocator()
        locator = created
        return created
    }

    private func prepareDraft(placeID: String) {
        activePlaceID = placeID
        let visit = latestVisit(for: placeID)
        draftComment = visit?.comment ?? ""
        draftVisibility = visit?.visibility ?? SaveInkProvisional.defaultVisibility
        draftSentiment = visit?.sentiment
    }

    private func verifiedTodayCount() -> Int {
        let today = now()
        return visits.filter {
            $0.verification == .verified && SaveInkClock.taipei.isDate($0.visitedAt, inSameDayAs: today)
        }.count
    }

    private func previousShop(before placeID: String) -> (date: Date, latitude: Double, longitude: Double)? {
        guard
            let previous = visits.filter({ $0.placeID != placeID }).max(by: { $0.visitedAt < $1.visitedAt }),
            let place = place(previous.placeID),
            let latitude = place.shopLatitude,
            let longitude = place.shopLongitude
        else { return nil }
        return (previous.visitedAt, latitude, longitude)
    }

    private func markVisited(_ placeID: String) {
        guard let index = places.firstIndex(where: { $0.id == placeID }) else { return }
        places[index].badge = .visited
    }

    private func reflectVisitBadges() {
        let visited = Set(visits.map(\.placeID))
        guard !visited.isEmpty else { return }
        places = places.map { place in
            guard place.badge != .visited else { return place }
            let ids = Set([place.id] + place.aliasIDs)
            guard !visited.isDisjoint(with: ids) else { return place }
            var copy = place
            copy.badge = .visited
            return copy
        }
    }

    private func retargetOpenPlaces() {
        path = path.map(retarget)
        if let activePlaceID, let resolved = place(activePlaceID)?.id, resolved != activePlaceID {
            self.activePlaceID = resolved
        }
        if case .checkIn(let situation, let placeID) = sheet, let resolved = place(placeID)?.id, resolved != placeID {
            sheet = .checkIn(situation, placeID: resolved)
        }
    }

    private func retarget(_ route: SaveInkRoute) -> SaveInkRoute {
        switch route {
        case .place(let id):
            return .place(place(id)?.id ?? id)
        case .review(let id):
            return .review(place(id)?.id ?? id)
        case .arrival(let id):
            return .arrival(place(id)?.id ?? id)
        case .passport, .friends, .welcome:
            return route
        }
    }

    private func rekeyVisits(using places: [SaveInkPlace]) {
        var aliasToPrimary: [String: String] = [:]
        for place in places {
            for alias in place.aliasIDs where alias != place.id {
                aliasToPrimary[alias] = place.id
            }
        }
        guard !aliasToPrimary.isEmpty else { return }
        var changed = false
        for index in visits.indices {
            guard let primary = aliasToPrimary[visits[index].placeID] else { continue }
            visits[index].placeID = primary
            changed = true
        }
        if changed { persist(owner: liveOwner()) }
    }

    private func persist(owner explicitOwner: String? = nil) {
        let key = usesLivePlaces ? Self.visitsKey(owner: explicitOwner ?? liveOwner()) : storageKey
        Self.save(visits, defaults: defaults, key: key)
    }

    private static func visitsKey(owner: String?) -> String {
        // Signed-out live launches must not read fixture visits stored on the
        // base key. Those rows are not migrated: the account is unknown.
        guard let owner, !owner.isEmpty else { return "save.ink.visits.live.signed-out" }
        return "save.ink.visits.v1.\(owner)"
    }

    /// False when this account's rows could not be written. A file that exists
    /// but cannot be decoded is left untouched, so one bad value cannot erase
    /// every account's ink saves.
    private func persistPlaces() -> Bool {
        if usesLivePlaces, liveOwner() != catalogOwner { return false }
        let owner = usesLivePlaces ? liveOwner() : nil
        let mine = places.filter { $0.id.hasPrefix("saved-") }.map {
            SaveInkSavedPlaceRecord(
                id: $0.id,
                name: $0.name,
                stampName: $0.stampName,
                street: $0.street,
                blurb: $0.blurb,
                sourceLabel: $0.sourceLabel,
                detailNote: $0.detailNote,
                ownerSubject: owner
            )
        }
        let records: [SaveInkSavedPlaceRecord]
        if usesLivePlaces, let data = placesDefaults.data(forKey: placesKey) {
            guard let existing = try? JSONDecoder().decode([SaveInkSavedPlaceRecord].self, from: data) else {
                return false
            }
            records = existing.filter { $0.ownerSubject != owner } + mine
        } else {
            records = mine
        }
        guard let data = try? JSONEncoder().encode(records) else { return false }
        placesDefaults.set(data, forKey: placesKey)
        return true
    }

    /// Production places live in the App Group. A private test suite stays isolated.
    /// Places saved by the previous app container are copied across once.
    private static func placesDefaults(for defaults: UserDefaults) -> UserDefaults {
        guard defaults === UserDefaults.standard else { return defaults }
        let shared = SavePlaceLinkGate.sharedPlacesDefaults()
        let key = SavePlaceLinkGate.placesKey
        if shared.data(forKey: key) == nil, let legacy = defaults.data(forKey: key) {
            shared.set(legacy, forKey: key)
        }
        return shared
    }

    /// Removes this account's ink visits and name saves. Other accounts' rows stay.
    static func purgeAccount(_ owner: String, defaults: UserDefaults = .standard) throws {
        guard !owner.isEmpty else { return }
        defaults.removeObject(forKey: "save.ink.visits.v1.\(owner)")
        let store = placesDefaults(for: defaults)
        let key = SavePlaceLinkGate.placesKey
        guard let data = store.data(forKey: key) else { return }
        guard let records = try? JSONDecoder().decode([SaveInkSavedPlaceRecord].self, from: data) else {
            throw SaveInkAccountPurgeError.unreadablePlaces
        }
        let kept = records.filter { $0.ownerSubject != owner }
        guard kept.count != records.count else { return }
        if kept.isEmpty {
            store.removeObject(forKey: key)
            return
        }
        guard let encoded = try? JSONEncoder().encode(kept) else {
            throw SaveInkAccountPurgeError.unreadablePlaces
        }
        store.set(encoded, forKey: key)
    }

    /// Signed-in live launches see only that account's rows. Ownerless rows
    /// stay hidden while an account is signed in, matching the vault.
    static func visibleSavedRecords(
        _ records: [SaveInkSavedPlaceRecord],
        owner: String?,
        scoped: Bool
    ) -> [SaveInkSavedPlaceRecord] {
        guard scoped else { return records }
        return records.filter { $0.ownerSubject == owner }
    }

    private static func loadSavedPlaces(
        defaults: UserDefaults,
        key: String,
        owner: String?,
        scoped: Bool
    ) -> [SaveInkPlace] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([SaveInkSavedPlaceRecord].self, from: data)
        else { return [] }
        return visibleSavedRecords(records, owner: owner, scoped: scoped).map {
            SaveInkPlace(
                id: $0.id,
                name: $0.name,
                stampName: $0.stampName,
                street: $0.street,
                distanceMeters: nil,
                blurb: $0.blurb,
                sourceLabel: $0.sourceLabel,
                badge: .saved,
                detailNote: $0.detailNote,
                friendUsualCount: 0,
                walkMinutes: nil,
                addressLine: nil,
                videoTitle: nil,
                videoSource: nil,
                shopLatitude: nil,
                shopLongitude: nil
            )
        }
    }

    static let sampleCheckInMigrationKey = "save.ink.sampleCheckIns.removed.v1"

    /// One pass. Drops untouched seeded check-ins and rewrites storage only
    /// when one of those rows was removed. A visit the user commented on,
    /// hid, rated, or recorded on another date stays as stored.
    private static func visitsWithoutPersistedSamples(
        defaults: UserDefaults,
        key: String
    ) -> [SaveInkVisitRecord] {
        let stored = load(defaults: defaults, key: key)
        if defaults.bool(forKey: sampleCheckInMigrationKey) {
            return stored ?? []
        }
        if defaults.data(forKey: key) != nil, stored == nil {
            return []
        }
        let current = stored ?? []
        let kept = current.filter { !SaveInkFixture.isUntouchedSeedVisit($0) }
        if stored != nil, kept.count != current.count {
            save(kept, defaults: defaults, key: key)
        }
        defaults.set(true, forKey: sampleCheckInMigrationKey)
        return kept
    }

    private static func load(defaults: UserDefaults, key: String) -> [SaveInkVisitRecord]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let legacy = try? Self.decoder.decode([SaveInkLegacyVisit].self, from: data) else { return nil }
        return legacy.map(\.record)
    }

    private static func save(_ visits: [SaveInkVisitRecord], defaults: UserDefaults, key: String) {
        guard let data = try? encoder.encode(visits) else { return }
        defaults.set(data, forKey: key)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum SaveInkSettingsOpener {
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

enum SaveInkFixture {
    static let dingtai = "dingtai"
    static let qingtian = "qingtian"
    static let chifeng = "chifeng"
    static let huashan = "huashan"
    static let dadaocheng = "dadaocheng"
    static let samplePlaceIDs: Set<String> = [dingtai, qingtian, chifeng, huashan, dadaocheng]

    static let places: [SaveInkPlace] = [
        SaveInkPlace(
            id: dingtai,
            name: "鼎泰小館",
            stampName: "鼎泰小館",
            street: "永康街",
            distanceMeters: 350,
            blurb: "你去過 3 次，朋友 2 人也常去",
            sourceLabel: "來自 小紅書影片",
            badge: .visited,
            detailNote: "你去過 3 次，朋友 2 人也常去，平日下午人比較少。",
            friendUsualCount: 2,
            walkMinutes: 5,
            addressLine: "台北市大安區永康街",
            videoTitle: "永康街必吃小籠包",
            videoSource: "來自 小紅書影片・10/20 存的",
            shopLatitude: 25.0327,
            shopLongitude: 121.5294
        ),
        SaveInkPlace(
            id: qingtian,
            name: "青田七六咖啡",
            stampName: "青田七六",
            street: "青田街",
            distanceMeters: 1_200,
            blurb: "上週存的，今天剛好順路",
            sourceLabel: "來自 抖音影片",
            badge: .saved,
            detailNote: "上週存的，今天剛好順路。",
            friendUsualCount: 1,
            walkMinutes: 16,
            addressLine: "台北市大安區青田街 7 巷 6 號",
            videoTitle: "大安老宅咖啡",
            videoSource: "來自 抖音影片「大安老宅咖啡」",
            shopLatitude: 25.0268,
            shopLongitude: 121.5308
        ),
        SaveInkPlace(
            id: chifeng,
            name: "赤峰街雜貨鋪",
            stampName: "赤峰街",
            street: "赤峰街",
            distanceMeters: 2_400,
            blurb: "朋友 4 人打過卡，週末有市集",
            sourceLabel: "來自 朋友推薦",
            badge: .visited,
            detailNote: "朋友 4 人打過卡，週末有市集。",
            friendUsualCount: 4,
            walkMinutes: 32,
            addressLine: "台北市中山區赤峰街",
            videoTitle: nil,
            videoSource: nil,
            shopLatitude: 25.0552,
            shopLongitude: 121.5202
        ),
        SaveInkPlace(
            id: huashan,
            name: "華山文創草地",
            stampName: "華山",
            street: "華山",
            distanceMeters: 1_800,
            blurb: "傍晚光線很漂亮",
            sourceLabel: "來自 朋友推薦",
            badge: .visited,
            detailNote: "傍晚光線很漂亮，帶野餐墊去。",
            friendUsualCount: 1,
            walkMinutes: 24,
            addressLine: "台北市中正區八德路一段 1 號",
            videoTitle: nil,
            videoSource: nil,
            shopLatitude: 25.0441,
            shopLongitude: 121.5295
        ),
        SaveInkPlace(
            id: dadaocheng,
            name: "大稻埕碼頭",
            stampName: "大稻埕",
            street: "大稻埕",
            distanceMeters: 3_200,
            blurb: "未驗證造訪",
            sourceLabel: "來自 你的造訪",
            badge: .visited,
            detailNote: "這次記成未驗證。",
            friendUsualCount: 0,
            walkMinutes: 40,
            addressLine: "台北市大同區大稻埕",
            videoTitle: nil,
            videoSource: nil,
            shopLatitude: 25.0554,
            shopLongitude: 121.5102
        ),
    ]

    private static let seedVisits: [(String, Int, Int, Int, SaveInkVerification)] = [
        (dingtai, 2026, 8, 2, .verified),
        (dingtai, 2026, 9, 18, .verified),
        (dingtai, 2026, 10, 28, .verified),
        (chifeng, 2026, 7, 3, .verified),
        (chifeng, 2026, 10, 12, .verified),
        (huashan, 2026, 9, 30, .verified),
        (dadaocheng, 2026, 9, 14, .unverified),
    ]

    static func visits() -> [SaveInkVisitRecord] {
        seedVisits.map { placeID, year, month, day, verification in
            SaveInkVisitRecord(
                id: UUID(),
                placeID: placeID,
                visitedAt: SaveInkClock.date(year, month, day),
                verification: verification,
                visibility: .public,
                comment: "",
                sentiment: nil,
                anomaly: nil
            )
        }
    }

    /// A row written by `visits()` that the user has not edited.
    static func isUntouchedSeedVisit(_ record: SaveInkVisitRecord) -> Bool {
        guard record.visibility == .public,
              record.sentiment == nil,
              record.anomaly == nil,
              record.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        return seedVisits.contains { placeID, year, month, day, verification in
            record.placeID == placeID
                && record.verification == verification
                && abs(record.visitedAt.timeIntervalSince(SaveInkClock.date(year, month, day))) < 1
        }
    }

    static func friendInputs(now: Date) -> [SaveInkFriendVisitInput] {
        func input(
            _ author: String,
            _ name: String,
            _ place: String,
            _ placeName: String,
            _ street: String,
            _ comment: String,
            daysAgo: Int,
            count: Int,
            verification: SaveInkVerification
        ) -> [SaveInkFriendVisitInput] {
            (0..<count).map { index in
                SaveInkFriendVisitInput(
                    authorID: author,
                    authorName: name,
                    placeID: place,
                    placeName: placeName,
                    street: street,
                    comment: index == 0 ? comment : "",
                    visitedAt: now.addingTimeInterval(TimeInterval(-(daysAgo + index) * 86_400)),
                    verification: verification,
                    visibility: .public
                )
            }
        }
        return input("azhe", "阿哲", dingtai, "鼎泰小館", "永康街", "小籠包還是最穩，平日兩點去不用排。", daysAgo: 2, count: 5, verification: .verified)
            + input("kaiwen", "凱文", huashan, "華山文創草地", "華山", "傍晚光線很漂亮，帶野餐墊去。", daysAgo: 7, count: 3, verification: .verified)
            + input("momo", "茉茉", qingtian, "青田七六咖啡", "青田街", "宅宅很安靜，適合看書，甜點普通。", daysAgo: 5, count: 2, verification: .verified)
            + input("xiaoan", "小安", chifeng, "赤峰街雜貨鋪", "赤峰街", "週末市集好逛，買了一個手工杯。", daysAgo: 3, count: 1, verification: .unverified)
    }

    static var homePlaces: [SaveInkPlace] {
        places.filter { [dingtai, qingtian, chifeng].contains($0.id) }
    }
}

/// Only known Savvy-generated fallback copy; original names, comments and sources stay intact.
enum SaveInkSystemCopy {
    static func text(_ value: String, language: AppLanguage, isUserContent: Bool = false) -> String {
        guard language == .english, !isUserContent else { return value }
        return english[value] ?? value
    }

    private static let english: [String: String] = [
        "還沒有地點": "No saved places yet",
        "這則跟地點無關，所以沒有存成地點，不會出現在地圖上，也不能蓋章。": "This content is not about a place. It was not saved, will not appear on the map, and cannot receive a stamp.",
        "這則地圖連結還沒有店名。在下面寫下店名再存。": "This map link has no place name. Enter the name below before saving.",
        "還在核對已存的地點，請稍後再存。": "Checking saved places. Try saving again shortly.",
        "還在核對可以存幾個地點，請稍後再存。": "Checking your place limit. Try saving again shortly.",
        "已存 50 個地點，所以暫放，還沒放上地圖。": "You have saved 50 places. This clue is waiting and has not been added to the map.",
        "已存 50 個地點，這次沒有存下來。請稍後再試。": "You have saved 50 places. This place was not saved. Try again later.",
        "這次沒有存下來。請稍後再試。": "The place was not saved. Try again later.",
        "你保留的到訪紀錄": "Your recorded visit",
        "來自 你的到訪紀錄": "From your visit history",
        "你保留的到訪紀錄。": "Your recorded visit.",
        "剛存的": "Recently saved",
        "來自 你貼上的店名": "From the place name you entered",
        "剛存下來，到了再按「我到了」。": "Saved. Tap “I’m here” when you arrive.",
        "剛存下來。可以記錄到訪（未驗證）。": "Saved. You can record an unverified visit.",
        "你去過": "Visited",
        "存了，還沒去": "Saved, not visited",
        "來自 分享": "From a shared place",
        "來自 已存的地點": "From your saved places"
    ]
}
