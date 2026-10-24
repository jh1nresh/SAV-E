import Foundation
import MapKit

// MARK: - App Review Demo Account
//
// This is an **App Store / Beta App Review demo account**. Apple's reviewers
// cannot receive a real email OTP, so the normal Privy sign-in flow locks them
// out. The constant credentials below let a reviewer enter a fully-populated,
// isolated demo session (backend guest token + locally-seeded places) without a
// real Privy account.
//
// Security: only the EXACT (email, code) pair below triggers the bypass — every
// other email/code goes through the normal Privy flow unchanged. The demo
// session has no access to real users' data: it is backed by an anonymous guest
// token plus local seed data only.
//
// This account can be rotated or removed after approval — change the constants
// here (and the App Store Connect "Sign-In Information" notes) or delete the
// bypass branch in `PrivyAuthService`.
enum ReviewDemo {
    /// Demo email the reviewer types into the email sign-in field.
    static let email = "appreview@wanderly.app"

    /// Demo verification code the reviewer types into the code field.
    static let code = "424242"

    /// Stable user id used for the demo `authState`. Not a real Privy id.
    static let userId = "review-demo"

    /// UserDefaults flag so the isolated demo vault is seeded only once.
    static let seededDefaultsKey = "reviewDemoSeeded"

    /// Keeps the ReviewDemo UI-test path deterministic and fully local. The
    /// launch flag is DEBUG-only so App Review and production sessions keep
    /// their existing behavior.
    static var isOfflineUITestMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitest-review-demo-offline")
#else
        false
#endif
    }

    /// A per-test suffix prevents UI tests from reading or overwriting the
    /// normal reviewer-demo vault. Only a conservative filename-safe subset is
    /// accepted so an environment value cannot escape the demo directory.
    static var uiTestStorageIdentifier: String? {
#if DEBUG
        guard isOfflineUITestMode,
              let value = ProcessInfo.processInfo.environment["SAVE_UI_TEST_STORAGE_ID"]
        else { return nil }
        let normalized = value.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(64))
#else
        nil
#endif
    }

    /// Case-insensitive, whitespace-trimmed match on the email so the reviewer
    /// isn't tripped up by autocapitalization or trailing spaces.
    static func isDemoEmail(_ value: String) -> Bool {
        normalized(value) == email
    }

    /// Exact pair check: BOTH the demo email and the demo code must match for
    /// the bypass to fire. Everything else falls through to Privy.
    static func isDemoCredentialPair(email: String, code: String) -> Bool {
        isDemoEmail(email) && normalized(code) == self.code
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Isolated Demo Storage

@MainActor
enum ReviewDemoStorage {
    private static let defaultsSuiteName = ReviewDemo.uiTestStorageIdentifier
        .map { "com.wanderly.app.review-demo.ui-test.\($0)" }
        ?? "com.wanderly.app.review-demo"

    static let directoryURL: URL = {
        let fileManager = FileManager.default
        let baseURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SAVEProductionConfig.appGroupSuiteName
        ) ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryName = ReviewDemo.uiTestStorageIdentifier
            .map { "review-demo-ui-test-\($0)" }
            ?? "review-demo-v1"
        return baseURL.appendingPathComponent(directoryName, isDirectory: true)
    }()

    static let defaults: UserDefaults = {
        UserDefaults(suiteName: defaultsSuiteName)!
    }()
    static let localVaultService = SaveLocalVaultService(
        overrideVaultURL: directoryURL.appendingPathComponent("save-memory-records.json")
    )
    static let pendingImportService = PendingPlaceImportService(
        overrideContainerURL: directoryURL
    )
    static let correctionEventStore = SavePlaceCorrectionEventStore(
        overrideURL: directoryURL.appendingPathComponent("save-place-correction-events.json")
    )
    static let collaborativeListStore = SaveCollaborativeListStore(defaults: defaults)
    static let referralHandoffStore = SaveReferralHandoffStore(defaults: defaults)

    static func resetUITestStorageIfRequested() {
#if DEBUG
        guard ReviewDemo.isOfflineUITestMode,
              ReviewDemo.uiTestStorageIdentifier != nil,
              ProcessInfo.processInfo.arguments.contains("--uitest-reset-review-demo-storage")
        else { return }
        try? FileManager.default.removeItem(at: directoryURL)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
#endif
    }

    static func makeMapViewModel() -> MapViewModel {
        var searchService: MapCandidateSearchServiceProtocol = MapCandidateSearchService()
#if DEBUG
        if ReviewDemo.isOfflineUITestMode,
           ProcessInfo.processInfo.arguments.contains("--uitest-review-map-results") {
            searchService = ReviewMapResultsFixture()
        }
#endif
        return MapViewModel(
            pendingImportService: pendingImportService,
            saveLocalVaultService: localVaultService,
            correctionEventStore: correctionEventStore,
            mapCandidateSearchService: searchService,
            collaborativeListStore: collaborativeListStore,
            referralHandoffStore: referralHandoffStore,
            usesRemotePersistence: !ReviewDemo.isOfflineUITestMode
        )
    }
}

#if DEBUG
/// A deterministic result for the Review -> change place -> search-panel rail.
/// Selected only by the explicit offline UI-test launch flag above.
private struct ReviewMapResultsFixture: MapCandidateSearchServiceProtocol {
    func searchCandidates(near coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan,
                          excluding savedPlaces: [Place], categories: Set<PlaceCategory>) async -> [SaveMapCandidate] { [] }

    func searchCandidates(matching query: String, near coordinate: CLLocationCoordinate2D?,
                          span: MKCoordinateSpan?, excluding savedPlaces: [Place]) async -> [SaveMapCandidate] {
        guard query.contains("Harbor Oven Pizza") else { return [] }
        return [SaveMapCandidate(id: "review-map-result-fixture", title: "Harbor Oven Pizza — corrected branch",
            subtitle: "1 Fixture Road, Los Angeles", latitude: 33.741, longitude: -118.281,
            category: .food, evidence: ["Synthetic map-search result"])]
    }
}
#endif

// MARK: - Guest Token Holder

/// Thread-safe holder for the demo guest token so the (synchronous, actor-free)
/// `guestTokenProvider` closure on `SAVEGeminiTransport` can read it without
/// hopping to the main actor. The token is written once on demo entry.
final class ReviewDemoGuestTokenHolder: @unchecked Sendable {
    static let shared = ReviewDemoGuestTokenHolder()

    private let lock = NSLock()
    private var token: String?

    var current: String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    func set(_ value: String?) {
        lock.lock(); defer { lock.unlock() }
        token = value
    }
}

// MARK: - Demo Seed Data

enum ReviewDemoSeed {
    /// ~6 realistic places across regions so the map + passport are populated
    /// immediately when the reviewer enters demo mode. Coordinates, category, a
    /// short note, and a source platform are all set so map pins + place detail
    /// render fully.
    static func places(now: Date = Date()) -> [Place] {
#if DEBUG
        // Isolated visual acceptance data; the production parity fixture is unchanged.
        if ReviewDemo.isOfflineUITestMode, ReviewDemo.uiTestStorageIdentifier != nil {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--uitest-home-design-empty") { return [] }
            if arguments.contains("--uitest-home-design-other-city") {
                return [Place(id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
                              name: "Sydney Harbour Cafe", address: "Sydney, Australia",
                              latitude: -33.859, longitude: 151.213, category: .cafe,
                              status: .wantToGo, sourcePlatform: .other, createdAt: now)]
            }
            if arguments.contains("--uitest-home-design-fixture") {
                return Array(doodleParityPlaces(now: now).prefix(3))
            }
            if arguments.contains("--uitest-home-taipei-granted") {
                return taipeiGrantedPlaces(now: now)
            }
        }
        if ReviewDemo.isOfflineUITestMode,
           ReviewDemo.uiTestStorageIdentifier != nil,
           ProcessInfo.processInfo.arguments.contains("--uitest-doodle-parity-fixture") {
            return doodleParityPlaces(now: now)
        }
        if ReviewDemo.isOfflineUITestMode,
           ReviewDemo.uiTestStorageIdentifier != nil,
           ProcessInfo.processInfo.arguments.contains("--uitest-home-memory-fixture") {
            return [
                ("Taipei Window Cafe", "台北市大安區", PlaceCategory.cafe),
                ("Tainan Garden Cafe", "台南市中西區", PlaceCategory.cafe),
                ("New Taipei Corner Cafe", "新北市板橋區", PlaceCategory.cafe),
                ("Taipei Lunch", "台北市信義區", PlaceCategory.food),
                ("Taipei Riverside Park", "台北市中山區", PlaceCategory.attraction),
            ].enumerated().map { index, value in
                Place(id: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index + 1))!,
                      name: value.0, address: value.1, latitude: 25.04, longitude: 121.54,
                      category: value.2, status: index == 0 ? .visited : .wantToGo,
                      sourcePlatform: .other, createdAt: now.addingTimeInterval(Double(-index)))
            }
        }
#endif
        return [
            Place(
                id: UUID(),
                name: "Ichiran Shibuya",
                address: "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
                latitude: 35.6615,
                longitude: 139.6996,
                category: .food,
                status: .visited,
                rating: 4.6,
                note: "Tonkotsu ramen, order extra firm noodles. Solo booth seating.",
                sourcePlatform: .instagram,
                createdAt: now.addingTimeInterval(-6 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["Classic tonkotsu", "Private solo booths"],
                vibeTags: ["cozy", "late-night"],
                sourceHandle: "tokyo.eats"
            ),
            Place(
                id: UUID(),
                name: "Fujin Tree 353 Cafe",
                address: "No. 353, Section 1, Fuxing S Rd, Da'an District, Taipei",
                latitude: 25.0411,
                longitude: 121.5436,
                category: .cafe,
                status: .wantToGo,
                rating: 4.5,
                note: "Pour-over + cheesecake. Plant-filled corner spot, great for working.",
                sourcePlatform: .xiaohongshu,
                createdAt: now.addingTimeInterval(-5 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["Single-origin pour-over", "Window seats"],
                vibeTags: ["quiet", "work-friendly"],
                sourceHandle: "taipei.cafe.hop"
            ),
            Place(
                id: UUID(),
                name: "Guerrilla Tacos",
                address: "2000 E 7th St, Los Angeles, CA 90021",
                latitude: 34.0335,
                longitude: -118.2310,
                category: .food,
                status: .wantToGo,
                rating: 4.4,
                note: "Sweet potato taco is the move. Get there before the lunch rush.",
                sourcePlatform: .instagram,
                createdAt: now.addingTimeInterval(-4 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["Sweet potato taco", "Chef-driven menu"],
                vibeTags: ["casual", "lunch"],
                sourceHandle: "la.taco.guide"
            ),
            Place(
                id: UUID(),
                name: "The Siam Hotel",
                address: "3/2 Thanon Khao, Vachiraphayaban, Dusit, Bangkok 10300",
                latitude: 13.7842,
                longitude: 100.5072,
                category: .stay,
                status: .wantToGo,
                rating: 4.8,
                note: "Riverside art-deco hotel. Pool villas, ferry to the old town.",
                sourcePlatform: .other,
                createdAt: now.addingTimeInterval(-3 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["Riverside villas", "Art-deco design"],
                vibeTags: ["luxury", "riverside"],
                sourceHandle: "bangkok.stays"
            ),
            Place(
                id: UUID(),
                name: "Bar Benfiddich",
                address: "9F, 1-13-7 Nishishinjuku, Shinjuku City, Tokyo",
                latitude: 35.6938,
                longitude: 139.6970,
                category: .bar,
                status: .wantToGo,
                rating: 4.7,
                note: "Herb-forward cocktails, the bartender grinds botanicals tableside.",
                sourcePlatform: .threads,
                createdAt: now.addingTimeInterval(-2 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["House botanicals", "Reservation recommended"],
                vibeTags: ["intimate", "date-night"],
                sourceHandle: "tokyo.nightcap"
            ),
            Place(
                id: UUID(),
                name: "Daan Forest Park",
                address: "Section 2, Xinyi Rd, Da'an District, Taipei",
                latitude: 25.0297,
                longitude: 121.5354,
                category: .attraction,
                status: .visited,
                rating: 4.6,
                note: "City's green lung. Morning walk loop and an open-air amphitheatre.",
                sourcePlatform: .googleMaps,
                createdAt: now.addingTimeInterval(-1 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["Walking loop", "Open-air amphitheatre"],
                vibeTags: ["outdoors", "relaxed"],
                sourceHandle: "taipei.outdoors"
            ),
        ]
    }

    /// App Review fixture for the unresolved Postcard. Never Quarter Sheets.
    static let harborOvenPizzaName = "Harbor Oven Pizza"

    static func reviewCandidates(now: Date = Date()) -> [PendingReviewCandidate] {
#if DEBUG
        if ReviewDemo.isOfflineUITestMode, ReviewDemo.uiTestStorageIdentifier != nil,
           ProcessInfo.processInfo.arguments.contains("--uitest-home-design-fixture") {
            return ["Temple Courtyard Tea", "Beijing Dumpling Kitchen"].enumerated().map { index, name in
                PendingReviewCandidate(candidateName: name, address: "Tiantan, Beijing, China",
                    category: "food", latitude: 39.89, longitude: 116.40,
                    sourceURL: nil, sourceText: name, evidence: ["Unconfirmed saved clue"],
                    confidence: 0.8, missingInfo: ["User confirmation required"],
                    savedAt: now.addingTimeInterval(Double(-index)))
            }
        }
#endif
        return [
            PendingReviewCandidate(
                candidateName: harborOvenPizzaName,
                address: "Berth 73, San Pedro, Los Angeles, CA 90731",
                category: "food",
                latitude: 33.7405,
                longitude: -118.2807,
                sourceURL: "https://www.instagram.com/p/harborovenpizza/",
                sourceText: "Harbor Oven Pizza — waterfront pie after the harbor walk.",
                evidence: [
                    "Source URL: https://www.instagram.com/p/harborovenpizza/",
                    "Caption: Harbor Oven Pizza. Save this for a slow harbor dinner.",
                    "Creator handle: @la.harbor.eats",
                    "Source handle: @la.harbor.eats"
                ],
                confidence: 0.84,
                missingInfo: ["User confirmation required"],
                savedAt: now.addingTimeInterval(-3 * 3600),
                sourceHandle: "la.harbor.eats"
            )
        ]
    }

    static func missingReviewCandidates(
        from existingCandidates: [PlaceReviewCandidate],
        now: Date = Date()
    ) -> [PendingReviewCandidate] {
        reviewCandidates(now: now).filter { seed in
            !existingCandidates.contains { existing in
                existing.name.localizedCaseInsensitiveCompare(seed.candidateName) == .orderedSame
            }
        }
    }

    /// Repairs partial or stale demo vaults without duplicating existing seeds.
    static func missingPlaces(from existingPlaces: [Place], now: Date = Date()) -> [Place] {
        places(now: now).filter { seed in
            !existingPlaces.contains { existing in
                existing.id == seed.id || existing.matches(seed)
            }
        }
    }

    static func shouldSeedVault(
        existingPlaces: [Place],
        wasSeeded: Bool,
        repairForUITests: Bool
    ) -> Bool {
#if DEBUG
        if ReviewDemo.isOfflineUITestMode,
           ReviewDemo.uiTestStorageIdentifier != nil,
           ProcessInfo.processInfo.arguments.contains("--uitest-empty-home") {
            return false
        }
#endif
        return repairForUITests || (!wasSeeded && existingPlaces.isEmpty)
    }

    /// Taipei B-2 evidence: location-granted, 6 own saves in 台北 (mix of
    /// saved + visited) so Home rows show distances. Isolated from the
    /// Tiantan parity fixture and the multi-city memory fixture.
    static func taipeiGrantedPlaces(now: Date = Date()) -> [Place] {
        let seeds: [(Int, String, String, PlaceCategory, PlaceStatus, Double, Double)] = [
            (0, "Taipei Window Cafe", "台北市大安區", .cafe, .visited, 25.0370, 121.5600),
            (1, "Taipei Lunch", "台北市信義區", .food, .wantToGo, 25.0336, 121.5654),
            (2, "Raohe Night Market", "台北市松山區", .food, .wantToGo, 25.0380, 121.5720),
            (3, "Yongkang Beef Noodles", "台北市大安區", .food, .visited, 25.0325, 121.5550),
            (4, "Fujin Tree 353 Cafe", "台北市松山區", .cafe, .wantToGo, 25.0360, 121.5500),
            (5, "Taipei Riverside Park", "台北市中山區", .attraction, .visited, 25.0400, 121.5600),
        ]
        return seeds.map { index, name, address, category, status, latitude, longitude in
            Place(
                id: UUID(uuidString: String(format: "50000000-0000-0000-0000-%012d", index + 1))!,
                name: name,
                address: address,
                latitude: latitude,
                longitude: longitude,
                category: category,
                status: status,
                sourcePlatform: .other,
                createdAt: now.addingTimeInterval(Double(-index))
            )
        }
    }

    /// Temple of Heaven (天壇) Eat rows plus the Map sheet park. Distances
    /// match the Codex packet / spec §8 Tiantan face: 450m / 800m / 1.1km.
    /// Twelve Tiantan saves, four visited (2 Eat + 2 Go). Only the three
    /// nearby Eat rows are mappable on Home; extra city saves stay outside
    /// the 3 km Near you radius so the packet pins stay aligned.
    /// Coordinates must be real: `SaveMemoryRecord.confirmedPlace` drops
    /// `0,0`, which made UI Collected read 3/4 instead of 4/12.
    /// The 0.90 score is not evidence.
    static func doodleParityPlaces(now: Date = Date()) -> [Place] {
        let seeds: [(Int, String, PlaceCategory, PlaceStatus, Double, Double)] = [
            (0, "Siji Minfu Roast Duck", .food, .visited, 39.886242, 116.4066),
            (1, "Fangzhuangchang Noodles", .food, .visited, 39.889387, 116.4066),
            (2, "Grey Cafe", .cafe, .wantToGo, 39.892082, 116.4066),
            (3, "Temple of Heaven Park", .attraction, .visited, 39.884895, 116.4066),
            (4, "Lantern Alley", .attraction, .visited, 39.9410, 116.4030),
            (5, "Jingshan", .attraction, .wantToGo, 39.9265, 116.3898),
            (6, "Houhai Bridge", .attraction, .wantToGo, 39.9408, 116.3835),
            (7, "Page One", .shopping, .wantToGo, 39.9540, 116.4670),
            (8, "Houhai Bicycle", .attraction, .wantToGo, 39.9422, 116.3860),
            (9, "Chaoyang Park Wheel", .attraction, .wantToGo, 39.9435, 116.4780),
            (10, "Summer Palace", .attraction, .wantToGo, 39.9997, 116.2755),
            (11, "Beihai Park", .attraction, .wantToGo, 39.9280, 116.3890),
        ]
        return seeds.map { index, name, category, status, latitude, longitude in
            Place(
                id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", index + 1))!,
                name: name,
                address: "Tiantan",
                latitude: latitude,
                longitude: longitude,
                category: category,
                status: status,
                sourcePlatform: .other,
                createdAt: now.addingTimeInterval(Double(-index))
            )
        }
    }

    /// Harbor Oven is the Review demo face. Isolated offline UI tests that
    /// capture a map link must start with an empty Review queue so Confirm
    /// persists that captured place instead of the seed.
    static func shouldSeedReviewFace(
        repairForUITests: Bool,
        isolatedOfflineUITest: Bool
    ) -> Bool {
        repairForUITests || !isolatedOfflineUITest
    }
}
