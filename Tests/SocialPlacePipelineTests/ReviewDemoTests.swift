import XCTest
@testable import SAVE

final class ReviewDemoTests: XCTestCase {
    @MainActor
    func testExactCredentialPairTriggersBypass() {
        XCTAssertTrue(ReviewDemo.isDemoCredentialPair(email: ReviewDemo.email, code: ReviewDemo.code))
    }

    @MainActor
    func testEmailMatchIsCaseAndWhitespaceTolerant() {
        XCTAssertTrue(ReviewDemo.isDemoEmail("  AppReview@Wanderly.app  "))
        XCTAssertTrue(ReviewDemo.isDemoCredentialPair(email: "APPREVIEW@WANDERLY.APP", code: " 424242 "))
    }

    @MainActor
    func testWrongCodeDoesNotTrigger() {
        XCTAssertFalse(ReviewDemo.isDemoCredentialPair(email: ReviewDemo.email, code: "000000"))
        XCTAssertFalse(ReviewDemo.isDemoCredentialPair(email: ReviewDemo.email, code: ""))
    }

    @MainActor
    func testWrongEmailDoesNotTrigger() {
        XCTAssertFalse(ReviewDemo.isDemoEmail("user@example.com"))
        XCTAssertFalse(ReviewDemo.isDemoCredentialPair(email: "user@example.com", code: ReviewDemo.code))
        // A real user who happens to type the demo code with their own email
        // must still go through Privy.
        XCTAssertFalse(ReviewDemo.isDemoCredentialPair(email: "someone@gmail.com", code: "424242"))
    }

    @MainActor
    func testSeedProducesPopulatedPlacesWithCoordinates() {
        let places = ReviewDemoSeed.places()
        XCTAssertGreaterThanOrEqual(places.count, 6)
        for place in places {
            XCTAssertFalse(place.name.isEmpty)
            XCTAssertFalse(place.address.isEmpty)
            XCTAssertTrue(place.latitude != 0 || place.longitude != 0)
        }
        // Mixed regions so the map is visibly populated.
        XCTAssertTrue(places.contains { $0.category == .food })
        XCTAssertTrue(places.contains { $0.category == .cafe })
        XCTAssertTrue(places.contains { $0.category == .stay })
    }

    @MainActor
    func testReviewFixtureIsHarborOvenPizzaNeverQuarterSheets() {
        let candidates = ReviewDemoSeed.reviewCandidates()
        XCTAssertEqual(candidates.map(\.candidateName), [ReviewDemoSeed.harborOvenPizzaName])
        XCTAssertFalse(candidates.contains { $0.candidateName.localizedCaseInsensitiveContains("Quarter Sheets") })
        XCTAssertEqual(candidates.first?.address.isEmpty, false)
        XCTAssertNotNil(candidates.first?.latitude)
        XCTAssertNotNil(candidates.first?.longitude)
    }

    @MainActor
    func testMissingSeedPlacesRepairsPartialVaultWithoutDuplicatingExistingSeeds() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let seeds = ReviewDemoSeed.places(now: now)
        let existingSeed = seeds[1]

        let missing = ReviewDemoSeed.missingPlaces(from: [existingSeed], now: now)

        XCTAssertEqual(missing.count, seeds.count - 1)
        XCTAssertFalse(missing.contains { $0.matches(existingSeed) })
        XCTAssertTrue(ReviewDemoSeed.missingPlaces(from: seeds, now: now).isEmpty)
    }

    @MainActor
    func testProductionSeedPolicyDoesNotWriteIntoAnExistingPersonalVault() {
        let personalPlace = Place(
            id: UUID(),
            name: "Personal Cafe",
            address: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            googlePlaceId: nil,
            category: .cafe,
            status: .wantToGo,
            rating: nil,
            note: nil,
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            businessPhotoUrls: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )

        XCTAssertFalse(ReviewDemoSeed.shouldSeedVault(
            existingPlaces: [personalPlace],
            wasSeeded: false,
            repairForUITests: false
        ))
        XCTAssertTrue(ReviewDemoSeed.shouldSeedVault(
            existingPlaces: [personalPlace],
            wasSeeded: true,
            repairForUITests: true
        ))
    }

    @MainActor
    func testIsolatedOfflineUITestDoesNotSeedReviewFaceWithoutRepairFlag() {
        XCTAssertFalse(
            ReviewDemoSeed.shouldSeedReviewFace(
                repairForUITests: false,
                isolatedOfflineUITest: true
            )
        )
        XCTAssertTrue(
            ReviewDemoSeed.shouldSeedReviewFace(
                repairForUITests: true,
                isolatedOfflineUITest: true
            )
        )
        XCTAssertTrue(
            ReviewDemoSeed.shouldSeedReviewFace(
                repairForUITests: false,
                isolatedOfflineUITest: false
            )
        )
    }

    @MainActor
    func testReviewerDemoSeedsStayVisibleToTheDemoOwner() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-demo-owner-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let seeds = ReviewDemoSeed.places()
        for place in seeds {
            _ = try vault.saveConfirmedPlace(place, ownerSubject: ReviewDemo.userId)
        }
        _ = try vault.saveConfirmedPlace(
            Place(
                id: UUID(),
                name: "Ownerless Seed Cafe",
                address: "Irvine, CA",
                latitude: 33.68,
                longitude: -117.82,
                googlePlaceId: nil,
                category: .cafe,
                status: .wantToGo,
                rating: nil,
                note: nil,
                sourceUrl: nil,
                sourcePlatform: .other,
                sourceImageUrl: nil,
                businessPhotoUrls: nil,
                extractedDishes: nil,
                priceRange: nil,
                recommender: nil,
                googleRating: nil,
                googlePriceLevel: nil,
                openingHours: nil,
                createdAt: Date()
            )
        )

        let demoPlaces = try vault.confirmedPlaces(limit: 500, belongingTo: ReviewDemo.userId)
        XCTAssertEqual(Set(demoPlaces.map(\.name)), Set(seeds.map(\.name)))
        XCTAssertFalse(demoPlaces.contains { $0.name == "Ownerless Seed Cafe" })
        XCTAssertTrue(
            try vault.confirmedPlaces(limit: 500).contains { $0.name == "Ownerless Seed Cafe" }
        )
    }

    /// P2 4365174273: an install seeded before owner stamps must still show
    /// the App Review Map Stamps and Harbor Oven Review clue.
    @MainActor
    func testOwnerlessLegacyDemoFixturesRemainVisibleAfterUpgrade() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: ReviewDemo.userId)
        defer { PrivyAuthService.shared.authState = previousAuth }

        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-demo-upgrade-\(UUID().uuidString).json")
        let suite = "review-demo-upgrade-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: vaultURL)
        }
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let seeds = ReviewDemoSeed.places()
        for place in seeds {
            _ = try vault.saveConfirmedPlace(place)
        }
        _ = try vault.saveReviewCandidate(ReviewDemoSeed.reviewCandidates()[0])
        _ = try vault.saveConfirmedPlace(
            Place(
                id: UUID(),
                name: "Ownerless Seed Cafe",
                address: "Irvine, CA",
                latitude: 33.68,
                longitude: -117.82,
                googlePlaceId: nil,
                category: .cafe,
                status: .wantToGo,
                rating: nil,
                note: nil,
                sourceUrl: nil,
                sourcePlatform: .other,
                sourceImageUrl: nil,
                businessPhotoUrls: nil,
                extractedDishes: nil,
                priceRange: nil,
                recommender: nil,
                googleRating: nil,
                googlePriceLevel: nil,
                openingHours: nil,
                createdAt: Date()
            )
        )
        defaults.set(true, forKey: ReviewDemo.seededDefaultsKey)

        XCTAssertTrue(
            try vault.confirmedPlaces(limit: 500, belongingTo: ReviewDemo.userId).isEmpty,
            "legacy ownerless fixtures are invisible to the demo owner before upgrade"
        )
        XCTAssertTrue(
            try vault.reviewCandidates(limit: 500, belongingTo: ReviewDemo.userId).isEmpty
        )

        ReviewDemoSeed.seedIsolatedVaultIfNeeded(
            vault: vault,
            defaults: defaults,
            repairForUITests: false,
            isolatedOfflineUITest: false
        )

        let map = MapViewModel(
            saveLocalVaultService: vault,
            usesRemotePersistence: false
        )
        await map.loadPlaces(force: true)

        XCTAssertEqual(Set(map.places.map(\.name)), Set(seeds.map(\.name)))
        XCTAssertEqual(Set(map.places.map(\.id)), Set(seeds.map(\.id)))
        XCTAssertFalse(map.places.contains { $0.name == "Ownerless Seed Cafe" })
        XCTAssertEqual(map.reviewCandidates.map(\.name), [ReviewDemoSeed.harborOvenPizzaName])
        XCTAssertEqual(
            Set(try vault.confirmedPlaces(limit: 500, belongingTo: ReviewDemo.userId).map(\.id)),
            Set(seeds.map(\.id))
        )
        XCTAssertEqual(
            try vault.reviewCandidates(limit: 500, belongingTo: ReviewDemo.userId).map(\.name),
            [ReviewDemoSeed.harborOvenPizzaName]
        )
    }

    @MainActor
    func testGuestTokenHolderRoundTrips() {
        let holder = ReviewDemoGuestTokenHolder()
        XCTAssertNil(holder.current)
        holder.set("guest-abc")
        XCTAssertEqual(holder.current, "guest-abc")
        holder.set(nil)
        XCTAssertNil(holder.current)
    }
}
