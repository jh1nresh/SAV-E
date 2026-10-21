import XCTest
import CoreLocation
@testable import SAVE

final class SAVEProductionConfigTests: XCTestCase {
    /// Regrades the PR #131 no-paywall guard. A paywall now exists, but the
    /// launch-surface promises it replaced must still hold: no automatic
    /// launch paywall, core memory loop free, enforcement off until Slice 3.
    func testPaywallExistsButNeverPresentsAutomaticallyAtLaunch() throws {
        let policy = try source(at: "SAV-EShared/SAVEProAccessPolicy.swift")
        let paywall = try source(at: "SAV-E/Views/Profile/SaveProPaywallView.swift")
        let backend = try source(at: "backend/src/server.ts")

        XCTAssertFalse(SAVEProAccessPolicy.showsAutomaticLaunchPaywall)
        XCTAssertFalse(SAVEProAccessPolicy.firstMapStampRequiresPurchase)
        XCTAssertTrue(SAVEProAccessPolicy.coreMemoryLoopIsFree)
        XCTAssertEqual(SAVEProAccessPolicy.freeSavedPlaceLimit, 50)
        // Slice 1 must not be able to refuse anyone.
        XCTAssertFalse(SAVEProAccessPolicy.enforcementEnabled)
        XCTAssertFalse(SAVEProAccessPolicy.purchasingIsAvailable)

        // App Store review requirements must live on the paywall itself.
        for required in ["paywall.restore", "paywall.terms", "paywall.privacy", "paywall.close"] {
            XCTAssertTrue(paywall.contains(required), "Paywall must expose \(required)")
        }
        XCTAssertTrue(policy.contains("enforcementEnabled"))
        XCTAssertTrue(policy.contains("freeSavedPlaceLimit = 50"))
        XCTAssertTrue(paywall.contains("Save every place you love"))
        XCTAssertTrue(paywall.contains("想去的地方，全部存下"))
        XCTAssertFalse(paywall.contains("收藏每一個你愛的地方"))
        XCTAssertTrue(paywall.contains("SaveDisplayTitle(text: headline, pointSize: 34)"))
        XCTAssertFalse(paywall.contains("SaveAtlasType.display(28)"))
        XCTAssertTrue(paywall.contains("Free: 50 places"))
        XCTAssertTrue(paywall.contains("免費：50 個地點"))
        XCTAssertEqual(
            paywall.components(separatedBy: "english: \"Free: 50 places\"").count - 1,
            1,
            "Free: 50 places must appear once, as the free-tier line"
        )
        XCTAssertTrue(paywall.contains("Unlimited saved places"))
        XCTAssertTrue(paywall.contains("無限收藏地點"))
        XCTAssertFalse(paywall.contains("收藏地點不設限"))
        XCTAssertTrue(paywall.contains("You've saved 50 places. Keep going."))
        XCTAssertTrue(paywall.contains("已存 50 個地點，繼續存下去"))
        XCTAssertTrue(paywall.contains("paywall.keepGoing"))
        XCTAssertTrue(
            paywall.contains("if trigger == .savedPlaceLimit"),
            "Q1: the saved-50 line belongs only on the 51st-save trigger"
        )
        XCTAssertTrue(paywall.contains("paywall.retryProducts"))
        XCTAssertTrue(paywall.contains("Try again"))
        XCTAssertTrue(paywall.contains("再試一次"))
        XCTAssertFalse(paywall.contains("Always free"))
        XCTAssertFalse(paywall.contains("永遠免費"))
        XCTAssertFalse(paywall.contains("stay free and unlimited"))
        XCTAssertFalse(paywall.contains("Unlimited saved places and Map Stamps"))
        XCTAssertFalse(paywall.contains("永遠免費且無上限"))
        XCTAssertFalse(paywall.contains("AI quota"))
        XCTAssertFalse(paywall.contains("AI assists"))
        XCTAssertFalse(paywall.contains("boundaryGroup"))
        XCTAssertFalse(policy.contains("saved-place memory loop is free forever"))

        let profile = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        XCTAssertTrue(profile.contains("english: \"Savvy Pro\""))
        XCTAssertTrue(profile.contains("english: \"Free: 50 places\""))
        XCTAssertTrue(profile.contains("traditionalChinese: \"免費：50 個地點\""))
        XCTAssertTrue(profile.contains("SaveProPaywallView(trigger: .passport)"))
        XCTAssertTrue(profile.contains("profile.pro"))
        XCTAssertTrue(profile.contains("if !passportPlaces.isEmpty"))
        XCTAssertFalse(
            profile.contains("SaveProPaywallView(trigger: .savedPlaceLimit)"),
            "Q1: Settings/Passport uses neutral copy, not the saved-50 line"
        )

        let share = try source(at: "SAV-EShareExtension/ShareViewController.swift")
        let content = try source(at: "SAV-E/App/ContentView.swift")
        let social = try source(at: "SAV-E/Views/Origin/SharedPostViews.swift")
        XCTAssertTrue(share.contains("SaveShareExtensionPlaceDestination.resolve"))
        XCTAssertTrue(share.contains("unplacedReviewCandidate"))
        XCTAssertTrue(content.contains("SaveProPaywallView(trigger: .savedPlaceLimit)"))
        XCTAssertTrue(content.contains("consumePendingSavedPlaceLimitPaywall"))
        XCTAssertTrue(content.contains("parkPlaceInUnplacedInbox($0, requestPaywall: false)"))
        XCTAssertTrue(social.contains("case .parkedAtFreeLimit"))
        XCTAssertTrue(social.contains("error = nil"))
        XCTAssertTrue(social.contains("showSavedPlaceLimitPaywall = true"))
        XCTAssertTrue(social.contains("SaveProPaywallView(trigger: .savedPlaceLimit)"))

        // Backend metering stays intact and untouched by this slice.
        XCTAssertTrue(backend.contains("recordAIUsageEvent"))
        XCTAssertTrue(backend.contains("buildGeminiUsageEvent"))
        XCTAssertTrue(backend.contains("assertNewSavedPlaceAllowed"))
        XCTAssertTrue(backend.contains("SavedPlaceLimitError"))

        let map = try source(at: "SAV-E/ViewModels/MapViewModel.swift")
        XCTAssertTrue(map.contains("parkIfServerSavedPlaceLimit(error, place: place)"))
        XCTAssertTrue(map.contains("syncSavedPlaceLimitCache()"))
        XCTAssertTrue(
            map.contains("if parkIfServerSavedPlaceLimit(error, place: merged)"),
            "C6: pending Share Extension imports park on a server cap"
        )
        XCTAssertTrue(share.contains("SaveShareExtensionPlaceDestination.resolve"))
        XCTAssertTrue(
            map.contains("savedPlaceCount: places.count"),
            "A1: the local cap counts confirmed Map Stamps only"
        )
        XCTAssertTrue(map.contains("let remotePlaces = try await supabaseService.fetchPlaces(for: userId)"))
        XCTAssertTrue(map.contains("places = mergeRemotePlaces(remotePlaces, withLocalPlaces: localConfirmedPlaces())"))

        let clip = try source(at: "SAV-EClip/ClipContentView.swift")
        let imessage = try source(at: "SAV-EiMessage/MessagesViewController.swift")
        XCTAssertFalse(clip.contains("savePlace("))
        XCTAssertFalse(imessage.contains("savePlace("))
        XCTAssertFalse(clip.contains("assertNewSavedPlaceAllowed"))
        XCTAssertFalse(imessage.contains("assertNewSavedPlaceAllowed"))
    }

    /// The gate is the only thing allowed to refuse an AI assist, so its truth
    /// table is pinned here.
    func testAIAssistGateFailsOpenAndRespectsEnforcementSwitch() {
        // Pro is unmetered regardless of usage.
        XCTAssertEqual(
            SaveAIAssistGate.decide(tier: .pro, usedUnits: 999, limitUnits: 20, warningThresholdUnits: 15),
            .allowed
        )

        // Metering unavailable: fail open rather than guess.
        XCTAssertEqual(
            SaveAIAssistGate.decide(tier: .free, usedUnits: nil, limitUnits: 20, warningThresholdUnits: 15),
            .allowed
        )

        XCTAssertEqual(
            SaveAIAssistGate.decide(tier: .free, usedUnits: 3, limitUnits: 20, warningThresholdUnits: 15),
            .allowed
        )

        XCTAssertEqual(
            SaveAIAssistGate.decide(tier: .free, usedUnits: 16, limitUnits: 20, warningThresholdUnits: 15),
            .allowedWarningNearLimit(remaining: 4)
        )

        // Exhausted while enforcement is off: served anyway, but recorded.
        XCTAssertEqual(
            SaveAIAssistGate.decide(
                tier: .free, usedUnits: 20, limitUnits: 20, warningThresholdUnits: 15,
                enforcementEnabled: false
            ),
            .allowedEnforcementDisabled
        )

        // Only with enforcement explicitly on may a refusal happen.
        XCTAssertEqual(
            SaveAIAssistGate.decide(
                tier: .free, usedUnits: 20, limitUnits: 20, warningThresholdUnits: 15,
                enforcementEnabled: true
            ),
            .refusedAllowanceExhausted
        )
    }

    func testFreeSavedPlaceCapAllowsFiftyAndParksTheFiftyFirst() {
        XCTAssertEqual(SAVEProAccessPolicy.freeSavedPlaceLimit, 50)
        XCTAssertEqual(
            SavePlaceLimitGate.decide(tier: .free, savedPlaceCount: 49),
            .allowed
        )
        XCTAssertEqual(
            SavePlaceLimitGate.decide(tier: .free, savedPlaceCount: 50),
            .overFreeLimit
        )
        XCTAssertEqual(
            SavePlaceLimitGate.decide(tier: .pro, savedPlaceCount: 9_999),
            .allowed
        )
        XCTAssertEqual(
            SavePlaceLimitGate.remainingNewSaves(tier: .free, savedPlaceCount: 60),
            0,
            "legacy accounts over 50 keep existing places; only new saves are gated"
        )
        XCTAssertNil(SavePlaceLimitGate.remainingNewSaves(tier: .pro, savedPlaceCount: 60))
    }

    func testSavedPlaceLimitHandoffMarksAndConsumesPaywall() {
        let defaults = UserDefaults(suiteName: "save.place-limit-tests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "") }

        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(defaults: defaults), .allowed)
        SavePlaceLimitHandoff.syncCache(tier: .free, savedPlaceCount: 50, defaults: defaults)
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(defaults: defaults), .overFreeLimit)
        SavePlaceLimitHandoff.syncCache(tier: .pro, savedPlaceCount: 50, defaults: defaults)
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(defaults: defaults), .allowed)

        XCTAssertFalse(SavePlaceLimitHandoff.consumePaywallPending(defaults: defaults))
        SavePlaceLimitHandoff.markPaywallPending(defaults: defaults)
        XCTAssertTrue(SavePlaceLimitHandoff.consumePaywallPending(defaults: defaults))
        XCTAssertFalse(SavePlaceLimitHandoff.consumePaywallPending(defaults: defaults))
    }

    @MainActor
    func testFreeSaveAtLimitParksInUnplacedInboxAndOpensPaywall() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        let candidate = SaveMapCandidate(
            id: "cap-51",
            title: "Fifty First Cafe",
            subtitle: "Taipei",
            latitude: 25.11,
            longitude: 121.52,
            category: .cafe
        )
        map.mapCandidates = [candidate]

        do {
            _ = try await map.saveMapCandidateAsPlace(candidate)
            XCTFail("the 51st free save must not become a Map Stamp")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 50)
            XCTAssertTrue(map.places.allSatisfy { $0.name.hasPrefix("Cap Place") })
            XCTAssertEqual(map.reviewCandidates.count, 1)
            XCTAssertEqual(map.reviewCandidates.first?.name, "Fifty First Cafe")
            XCTAssertEqual(map.reviewCandidates.first?.status, "review")
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        }
    }

    @MainActor
    func testFreeSaveBelowLimitStillBecomesMapStamp() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(49)
        let candidate = SaveMapCandidate(
            id: "cap-50",
            title: "Fiftieth Cafe",
            subtitle: "Taipei",
            latitude: 25.12,
            longitude: 121.53,
            category: .cafe
        )

        let saved = try await map.saveMapCandidateAsPlace(candidate)
        XCTAssertEqual(saved.name, "Fiftieth Cafe")
        XCTAssertEqual(map.places.count, 50)
        XCTAssertTrue(map.reviewCandidates.isEmpty)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
    }

    @MainActor
    func testProSaveIsUnlimitedBeyondFifty() async throws {
        let map = makeCappedMap(tier: .pro)
        map.places = makeCappedPlaces(50)
        let candidate = SaveMapCandidate(
            id: "cap-pro",
            title: "Pro Cafe",
            subtitle: "Taipei",
            latitude: 25.13,
            longitude: 121.54,
            category: .cafe
        )

        let saved = try await map.saveMapCandidateAsPlace(candidate)
        XCTAssertEqual(saved.name, "Pro Cafe")
        XCTAssertEqual(map.places.count, 51)
        XCTAssertTrue(map.reviewCandidates.isEmpty)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
    }

    @MainActor
    func testLegacyOverFiftyKeepsExistingPlacesAndParksNewSaves() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(60)
        let candidate = SaveMapCandidate(
            id: "cap-legacy",
            title: "Legacy Extra Cafe",
            subtitle: "Taipei",
            latitude: 25.14,
            longitude: 121.55,
            category: .cafe
        )

        do {
            _ = try await map.saveMapCandidateAsPlace(candidate)
            XCTFail("new saves over a legacy 60 must not become Map Stamps")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 60)
            XCTAssertEqual(map.reviewCandidates.first?.name, "Legacy Extra Cafe")
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        }
    }

    @MainActor
    func testConfirmingReviewCandidateAtCapStaysInInbox() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        let candidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Review Cafe",
            address: "1 Cap Road",
            city: nil,
            latitude: 25.15,
            longitude: 121.56,
            evidence: ["Source URL: https://example.com/review-cafe"],
            confidence: 0.9,
            missingInfo: [],
            status: "review",
            createdAt: Date()
        )
        map.reviewCandidates = [candidate]

        do {
            _ = try await map.saveReviewCandidateAsPlace(candidate)
            XCTFail("confirming a clue at the free cap must stay in Review")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 50)
            XCTAssertTrue(map.reviewCandidates.contains { $0.id == candidate.id })
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        }
    }

    @MainActor
    func testUnresolvedEntitlementDoesNotParkThe51stLocally() async throws {
        let map = makeCappedMap(tier: .free, resolved: false)
        map.places = makeCappedPlaces(50)
        let item = SaveListItem(
            id: UUID(),
            source: .mapCandidate,
            sourceID: "list-unresolved-51",
            title: "Unresolved Cafe",
            subtitle: "4 Cap Road",
            latitude: 25.18,
            longitude: 121.59,
            category: .cafe,
            rating: nil,
            reviewCount: nil,
            sourceURL: nil,
            photoURLs: [],
            note: nil,
            addedByDisplayName: "You",
            addedAt: Date()
        )

        let saved = try await map.saveListItemAsPlace(item)
        XCTAssertEqual(saved.name, "Unresolved Cafe")
        XCTAssertEqual(map.places.count, 51)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        XCTAssertFalse(map.reviewCandidates.contains { $0.name == "Unresolved Cafe" })
    }

    @MainActor
    func testSavingSocialPlaceAtCapParksInUnplacedInbox() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        let social = makeSocialPlace(name: "Social Cafe")
        map.socialPlaces = [social]

        do {
            _ = try await map.saveSocialPlaceToMySave(social)
            XCTFail("a social save at the free cap must not become a Map Stamp")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 50)
            XCTAssertEqual(map.reviewCandidates.first?.name, "Social Cafe")
            XCTAssertEqual(map.reviewCandidates.first?.status, "review")
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
            XCTAssertFalse(map.socialPlaces.contains { $0.id == social.id })
        }
    }

    @MainActor
    func testSavingListItemAtCapParksInUnplacedInbox() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        let item = SaveListItem(
            id: UUID(),
            source: .mapCandidate,
            sourceID: "list-cap-51",
            title: "List Cafe",
            subtitle: "3 Cap Road",
            latitude: 25.17,
            longitude: 121.58,
            category: .cafe,
            rating: nil,
            reviewCount: nil,
            sourceURL: nil,
            photoURLs: [],
            note: nil,
            addedByDisplayName: "You",
            addedAt: Date()
        )

        do {
            _ = try await map.saveListItemAsPlace(item)
            XCTFail("a list save at the free cap must not become a Map Stamp")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 50)
            XCTAssertEqual(map.reviewCandidates.first?.name, "List Cafe")
            XCTAssertEqual(map.reviewCandidates.first?.status, "review")
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        }
    }

    @MainActor
    func testSavingReceiptAtCapParksInUnplacedInbox() async throws {
        let map = makeCappedMap(tier: .free)
        await map.loadPlaces()
        map.places = makeCappedPlaces(50)
        let receipt = SharedPlaceReceipt.embedded(
            SharedPlaceData(
                id: "",
                name: "Receipt Cafe",
                address: "2 Cap Road",
                lat: 25.16,
                lng: 121.57,
                category: "Cafe",
                rating: nil,
                reviewCount: nil,
                priceRange: nil,
                hours: nil,
                sourceLabel: "Savvy",
                sourceURL: nil,
                photoURLs: [],
                note: nil
            )
        )

        do {
            _ = try await map.saveSharedPlaceReceipt(receipt)
            XCTFail("a receipt save at the free cap must not become a Map Stamp")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 50)
            XCTAssertEqual(map.reviewCandidates.first?.name, "Receipt Cafe")
            XCTAssertEqual(map.reviewCandidates.first?.status, "review")
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        }
    }

    @MainActor
    func testEmbeddedReceiptServerCapParksInsteadOfConfirmingLocally() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "receipt-owner")
        defer { PrivyAuthService.shared.authState = previousAuth }

        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "POST", request.url?.path == "/places" {
                return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
            }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-receipt.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-receipt-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let service = SupabaseService(
            apiBaseURL: "https://analysis.test",
            session: URLSession(configuration: configuration),
            accessTokenProvider: { "test-token" }
        )
        let map = MapViewModel(
            supabaseService: service,
            saveLocalVaultService: vault,
            entitlementTierProvider: { .free },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: true
        )
        map.places = makeCappedPlaces(49)
        let receipt = SharedPlaceReceipt.embedded(
            SharedPlaceData(
                id: "",
                name: "Server Cap Cafe",
                address: "5 Cap Road",
                lat: 25.19,
                lng: 121.60,
                category: "Cafe",
                rating: nil,
                reviewCount: nil,
                priceRange: nil,
                hours: nil,
                sourceLabel: "Savvy",
                sourceURL: nil,
                photoURLs: [],
                note: nil
            )
        )

        do {
            _ = try await map.saveSharedPlaceReceipt(receipt)
            XCTFail("a server over-limit receipt must not become a local Map Stamp")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 49)
            XCTAssertEqual(map.reviewCandidates.first?.name, "Server Cap Cafe")
            XCTAssertEqual(map.reviewCandidates.first?.status, "review")
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        }
    }

    @MainActor
    func testTakeoutImportAtCapParksInUnplacedInbox() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        let drafts = [
            ImportedPlaceDraft(
                name: "Takeout Cafe",
                address: "4 Cap Road",
                latitude: 25.18,
                longitude: 121.59,
                sourceFile: "Saved Places.json",
                sourceFormat: "json",
                reviewState: .readyToSave
            )
        ]

        let summary = try await map.saveImportedPlaces(drafts)
        XCTAssertEqual(summary.saved, 0)
        XCTAssertEqual(summary.reviewDrafts, 1)
        XCTAssertEqual(summary.skippedDuplicates, 0)
        XCTAssertEqual(map.places.count, 50)
        XCTAssertEqual(map.reviewCandidates.first?.name, "Takeout Cafe")
        XCTAssertEqual(map.reviewCandidates.first?.status, "review")
        XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
    }

    @MainActor
    func testDeletingAPlaceFreesASlotAndRefreshesExtensionCache() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        map.syncSavedPlaceLimitCache()
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .overFreeLimit)

        let removed = try XCTUnwrap(map.places.first)
        try await map.deletePlace(removed)
        XCTAssertEqual(map.places.count, 49)
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .allowed)

        let candidate = SaveMapCandidate(
            id: "cap-after-delete",
            title: "Freed Slot Cafe",
            subtitle: "Taipei",
            latitude: 25.22,
            longitude: 121.63,
            category: .cafe
        )
        let saved = try await map.saveMapCandidateAsPlace(candidate)
        XCTAssertEqual(saved.name, "Freed Slot Cafe")
        XCTAssertEqual(map.places.count, 50)
        XCTAssertTrue(map.reviewCandidates.isEmpty)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
    }

    @MainActor
    func testAcknowledgingPaywallKeepsTheParkedCandidate() {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        let place = makeSocialPlace(name: "Stay In Review")
        _ = map.parkPlaceInUnplacedInbox(place)
        XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        map.acknowledgeSavedPlaceLimitPaywall()
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        XCTAssertEqual(map.reviewCandidates.first?.name, "Stay In Review")
        XCTAssertEqual(map.places.count, 50)
    }

    @MainActor
    func testProCanConfirmAParkedCandidateWithOneTap() async throws {
        let map = makeCappedMap(tier: .pro)
        map.places = makeCappedPlaces(50)
        let candidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Upgrade Cafe",
            address: "7 Cap Road",
            city: nil,
            latitude: 25.25,
            longitude: 121.66,
            evidence: ["Source URL: https://example.com/upgrade-cafe"],
            confidence: 0.9,
            missingInfo: [],
            status: "review",
            createdAt: Date()
        )
        map.reviewCandidates = [candidate]

        let saved = try await map.saveReviewCandidateAsPlace(candidate)
        XCTAssertEqual(saved.name, "Upgrade Cafe")
        XCTAssertEqual(map.places.count, 51)
        XCTAssertFalse(map.reviewCandidates.contains { $0.id == candidate.id })
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
    }

    @MainActor
    func testDeletingAPlaceLetsAParkedCandidateSave() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        let candidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Waiting Cafe",
            address: "8 Cap Road",
            city: nil,
            latitude: 25.26,
            longitude: 121.67,
            evidence: ["Source URL: https://example.com/waiting-cafe"],
            confidence: 0.9,
            missingInfo: [],
            status: "review",
            createdAt: Date()
        )
        map.reviewCandidates = [candidate]

        do {
            _ = try await map.saveReviewCandidateAsPlace(candidate)
            XCTFail("the parked candidate must wait until a slot is free")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.reviewCandidates.first?.id, candidate.id)
        }

        try await map.deletePlace(map.places[0])
        let saved = try await map.saveReviewCandidateAsPlace(candidate)
        XCTAssertEqual(saved.name, "Waiting Cafe")
        XCTAssertEqual(map.places.count, 50)
        XCTAssertFalse(map.reviewCandidates.contains { $0.id == candidate.id })
    }

    @MainActor
    func testLocalOnlyParkedCandidateConfirmsWithoutRemoteCandidateRow() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "local-park-owner")
        defer { PrivyAuthService.shared.authState = previousAuth }

        var patchedCandidate = false
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "PATCH", request.url?.path.contains("/memory/candidates/") == true {
                patchedCandidate = true
                return (404, #"{"error":"not_found"}"#)
            }
            if request.httpMethod == "POST", request.url?.path == "/places" {
                return (201, "{}")
            }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-local-park.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-local-park-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let service = SupabaseService(
            apiBaseURL: "https://analysis.test",
            session: URLSession(configuration: configuration),
            accessTokenProvider: { "test-token" }
        )
        let map = MapViewModel(
            supabaseService: service,
            saveLocalVaultService: vault,
            entitlementTierProvider: { .free },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: true
        )
        map.places = makeCappedPlaces(49)
        _ = map.parkPlaceInUnplacedInbox(makeSocialPlace(name: "Local Park Cafe"))
        let parked = try XCTUnwrap(map.reviewCandidates.first)

        let saved = try await map.saveReviewCandidateAsPlace(parked)
        XCTAssertEqual(saved.name, "Local Park Cafe")
        XCTAssertEqual(map.places.count, 50)
        XCTAssertFalse(patchedCandidate, "local-only Unplaced must not PATCH /memory/candidates")
        XCTAssertFalse(map.reviewCandidates.contains { $0.id == parked.id })
    }

    @MainActor
    func testAccountSavedPlacesOnlyCountTowardTheCap() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(25, status: .visited) + makeCappedPlaces(24, status: .wantToGo, indexOffset: 25)
        map.socialPlaces = [makeSocialPlace(name: "Friend Share Cafe")]
        map.collaborativeLists = [
            SaveCollaborativeList(
                title: "Taipei weekend",
                items: makeCappedPlaces(12, indexOffset: 200).map { SaveListItem.from(place: $0) }
            )
        ]
        map.reviewCandidates = [
            PlaceReviewCandidate(
                id: UUID(),
                captureId: nil,
                name: "Unplaced Cafe",
                address: "Inbox Road",
                city: "Taipei",
                latitude: 25.4,
                longitude: 121.8,
                evidence: [],
                confidence: 0.9,
                missingInfo: [],
                status: "review",
                createdAt: Date()
            )
        ]

        let fiftieth = try await map.saveMapCandidateAsPlace(
            SaveMapCandidate(
                id: "cap-a1-50",
                title: "Fiftieth Own Cafe",
                subtitle: "Taipei",
                latitude: 25.41,
                longitude: 121.81,
                category: .cafe
            )
        )
        XCTAssertEqual(fiftieth.name, "Fiftieth Own Cafe")
        XCTAssertEqual(map.places.count, 50)
        XCTAssertEqual(map.places.filter { $0.status == .visited }.count, 25)
        XCTAssertEqual(map.places.filter { $0.status == .wantToGo }.count, 25)
        XCTAssertEqual(map.socialPlaces.count, 1)
        XCTAssertEqual(map.collaborativeLists.first?.items.count, 12)
        XCTAssertEqual(map.reviewCandidates.count, 1)

        do {
            _ = try await map.saveMapCandidateAsPlace(
                SaveMapCandidate(
                    id: "cap-a1-51",
                    title: "Fifty First Own Cafe",
                    subtitle: "Taipei",
                    latitude: 25.42,
                    longitude: 121.82,
                    category: .cafe
                )
            )
            XCTFail("lists, friend shares, and Unplaced must not consume a free slot")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 50)
            XCTAssertTrue(map.reviewCandidates.contains { $0.name == "Fifty First Own Cafe" })
        }
    }

    @MainActor
    func testServerSavedPlaceCountWinsAfterRefresh() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "server-count-owner")
        defer { PrivyAuthService.shared.authState = previousAuth }

        let remoteIDs = (0..<50).map { _ in UUID() }
        let rows = remoteIDs.enumerated().map { index, id in
            cappedPlaceRowJSON(id: id, index: index)
        }.joined(separator: ",")
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/places" {
                return (200, "[\(rows)]")
            }
            if request.url?.path.contains("/memory/candidates") == true { return (200, "[]") }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-a5.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-a5-\(UUID().uuidString).json")
        let map = makeRemoteCappedMap(vaultURL: vaultURL)
        map.places = makeCappedPlaces(49)

        await map.loadPlaces()
        XCTAssertEqual(map.places.count, 50, "A5: the server place list replaces the stale local count")
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .overFreeLimit)

        do {
            _ = try await map.saveMapCandidateAsPlace(
                SaveMapCandidate(
                    id: "cap-a5-51",
                    title: "After Refresh Cafe",
                    subtitle: "Taipei",
                    latitude: 25.43,
                    longitude: 121.83,
                    category: .cafe
                )
            )
            XCTFail("a refresh that reports 50 must park the next save")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 50)
            XCTAssertEqual(map.reviewCandidates.first?.name, "After Refresh Cafe")
        }
    }

    @MainActor
    func testAfterProAParkedCandidateSavesWithOneTap() async throws {
        var tier: SaveProTier = .free
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-b4.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-b4-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let map = MapViewModel(
            saveLocalVaultService: vault,
            entitlementTierProvider: { tier },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: false
        )
        map.places = makeCappedPlaces(50)
        _ = map.parkPlaceInUnplacedInbox(makeSocialPlace(name: "Upgrade Later Cafe"))
        map.acknowledgeSavedPlaceLimitPaywall()
        let parked = try XCTUnwrap(map.reviewCandidates.first)
        XCTAssertEqual(parked.name, "Upgrade Later Cafe")
        XCTAssertEqual(map.places.count, 50)

        tier = .pro
        let saved = try await map.saveReviewCandidateAsPlace(parked)
        XCTAssertEqual(saved.name, "Upgrade Later Cafe")
        XCTAssertEqual(map.places.count, 51)
        XCTAssertFalse(map.reviewCandidates.contains { $0.id == parked.id })
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
    }

    @MainActor
    func testDismissedPaywallKeepsUnplacedUntilASlotFrees() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        _ = map.parkPlaceInUnplacedInbox(makeSocialPlace(name: "Waiting After Dismiss"))
        map.acknowledgeSavedPlaceLimitPaywall()
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        let parked = try XCTUnwrap(map.reviewCandidates.first)
        XCTAssertEqual(parked.name, "Waiting After Dismiss")

        try await map.deletePlace(map.places[0])
        let saved = try await map.saveReviewCandidateAsPlace(parked)
        XCTAssertEqual(saved.name, "Waiting After Dismiss")
        XCTAssertEqual(map.places.count, 50)
        XCTAssertFalse(map.reviewCandidates.contains { $0.id == parked.id })
    }

    @MainActor
    func testExpiredProKeepsExistingPlacesViewableAndDeletable() async throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(60)
        let kept = try XCTUnwrap(map.places.last)
        XCTAssertEqual(map.places.count, 60)

        try await map.deletePlace(map.places[0])
        XCTAssertEqual(map.places.count, 59)
        XCTAssertTrue(map.places.contains { $0.id == kept.id })
        XCTAssertEqual(map.places.first { $0.id == kept.id }?.name, kept.name)

        do {
            _ = try await map.saveMapCandidateAsPlace(
                SaveMapCandidate(
                    id: "cap-c5-61",
                    title: "Expired Pro Extra Cafe",
                    subtitle: "Taipei",
                    latitude: 25.44,
                    longitude: 121.84,
                    category: .cafe
                )
            )
            XCTFail("expiry must not delete old stamps or allow a 61st insert")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 59)
            XCTAssertTrue(map.places.contains { $0.id == kept.id })
            XCTAssertEqual(map.reviewCandidates.first?.name, "Expired Pro Extra Cafe")
        }
    }

    @MainActor
    func testMergeExistingRemovesLocalUnplacedFromTheVault() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "merge-vault-owner")
        defer { PrivyAuthService.shared.authState = previousAuth }

        let existingID = UUID()
        let googlePlaceID = "ChIJmerge-existing-cafe"
        let existingRow = cappedPlaceRowJSON(id: existingID, index: 0, name: "Harbor Cafe", googlePlaceID: googlePlaceID)
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "PATCH", request.url?.path.contains("/memory/candidates/") == true {
                return (404, #"{"error":"not_found"}"#)
            }
            if request.httpMethod == "PATCH", request.url?.path.hasPrefix("/places/") == true {
                return (200, "{}")
            }
            if request.httpMethod == "GET", request.url?.path == "/places" {
                return (200, "[\(existingRow)]")
            }
            if request.url?.path.contains("/memory/candidates") == true { return (200, "[]") }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-merge-vault.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-merge-vault-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)
        let existing = Place(
            id: existingID,
            name: "Harbor Cafe",
            address: "0 Server Road",
            latitude: 25.0,
            longitude: 121.0,
            googlePlaceId: googlePlaceID,
            category: .food,
            status: .wantToGo,
            rating: nil,
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
            createdAt: Date()
        )
        map.places = [existing]
        let parked = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Harbor Cafe",
            address: "0 Server Road",
            city: nil,
            latitude: 25.0,
            longitude: 121.0,
            evidence: ["Source URL: https://example.com/harbor-cafe"],
            confidence: 0.9,
            missingInfo: [],
            status: "review",
            createdAt: Date(),
            googlePlaceId: googlePlaceID
        )
        _ = try vault.saveReviewCandidate(parked)
        map.reviewCandidates = [parked]
        XCTAssertEqual(try vault.reviewCandidates().first?.id, parked.id)

        let saved = try await map.saveReviewCandidateAsPlace(parked)
        XCTAssertEqual(saved.id, existingID)
        XCTAssertEqual(map.places.count, 1)
        XCTAssertFalse(map.reviewCandidates.contains { $0.id == parked.id })
        XCTAssertFalse(try vault.reviewCandidates().contains { $0.id == parked.id })

        try await map.refreshReviewCandidates()
        XCTAssertFalse(map.reviewCandidates.contains { $0.id == parked.id })
    }

    @MainActor
    func testFiftyFirstSaveParksWhenPurchasingIsUnavailable() async throws {
        XCTAssertFalse(SAVEProAccessPolicy.purchasingIsAvailable)
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        let candidate = SaveMapCandidate(
            id: "cap-b6",
            title: "Retry Cafe",
            subtitle: "Taipei",
            latitude: 25.23,
            longitude: 121.64,
            category: .cafe
        )

        do {
            _ = try await map.saveMapCandidateAsPlace(candidate)
            XCTFail("a StoreKit miss must not lock the 51st into a dropped save")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 50)
            XCTAssertEqual(map.reviewCandidates.first?.name, "Retry Cafe")
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        }
    }

    @MainActor
    func testTakeoutServerCapParksInsteadOfDropping() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "takeout-owner")
        defer { PrivyAuthService.shared.authState = previousAuth }

        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "POST", request.url?.path == "/places" {
                return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
            }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-takeout.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-takeout-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let service = SupabaseService(
            apiBaseURL: "https://analysis.test",
            session: URLSession(configuration: configuration),
            accessTokenProvider: { "test-token" }
        )
        let map = MapViewModel(
            supabaseService: service,
            saveLocalVaultService: vault,
            entitlementTierProvider: { .free },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: true
        )
        map.places = makeCappedPlaces(49)
        let drafts = [
            ImportedPlaceDraft(
                name: "Server Takeout Cafe",
                address: "6 Cap Road",
                latitude: 25.24,
                longitude: 121.65,
                sourceFile: "Saved Places.json",
                sourceFormat: "json",
                reviewState: .readyToSave
            )
        ]

        let summary = try await map.saveImportedPlaces(drafts)
        XCTAssertEqual(summary.saved, 0)
        XCTAssertEqual(summary.reviewDrafts, 1)
        XCTAssertEqual(map.places.count, 49)
        XCTAssertEqual(map.reviewCandidates.first?.name, "Server Takeout Cafe")
        XCTAssertEqual(map.reviewCandidates.first?.status, "review")
        XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
    }

    @MainActor
    func testSharedPostsStoreSaveAtCapParksAndReturnsDistinctOutcome() async throws {
        let store = SharedPostsStore()
        store.isOverFreeLimit = { true }
        var parked: Place?
        store.parkOverLimitPlace = { place in
            parked = place
            return PlaceReviewCandidate.unplacedInboxItem(from: place)
        }
        let post = SharedPlacePost(
            id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            name: "Harbor Town",
            address: "Water",
            latitude: 25.033,
            longitude: 121.565,
            google_place_id: "ChIJcap-harbor",
            category: "attraction",
            status: .wantToGo,
            stars: nil,
            caption: nil,
            shared_at: "2026-10-12T10:00:00Z",
            author_id: "alex",
            author_name: "Alex Last",
            author_handle: "alex",
            author_avatar_url: nil,
            visible_to_followers: true
        )

        let outcome = try await store.save(post)
        XCTAssertEqual(outcome, .parkedAtFreeLimit)
        XCTAssertEqual(parked?.name, "Harbor Town")
        XCTAssertEqual(parked?.id, post.id)
        XCTAssertEqual(parked?.latitude, 25.033)
        XCTAssertEqual(parked?.longitude, 121.565)
        XCTAssertEqual(parked?.googlePlaceId, "ChIJcap-harbor")
        XCTAssertNil(parked?.note)
        XCTAssertNil(parked?.rating)
        XCTAssertNil(parked?.recommender)
        XCTAssertTrue(parked?.sourceEvidence.isEmpty ?? false)
    }

    func testLocalReviewCandidatesAreScopedToTheActiveAccountInSource() throws {
        let map = try source(at: "SAV-E/ViewModels/MapViewModel.swift")
        XCTAssertTrue(map.contains("localVaultRecordBelongsToActiveAccount"))
        XCTAssertTrue(
            map.contains("ownerSubject: authService.currentUserId"),
            "parked Unplaced must stamp the signed-in account"
        )
        XCTAssertTrue(
            map.contains("return ownerSubject == currentUserId"),
            "signed-in refresh must hide another account's vault rows"
        )
        let vault = try source(at: "SAV-E/Services/SaveLocalVaultService.swift")
        XCTAssertTrue(vault.contains("existing.ownerSubject == incoming.ownerSubject"))
        XCTAssertTrue(vault.contains("ownerSubject: candidate.ownerSubject"))
        XCTAssertTrue(
            map.contains("try ensureConfirmationSession(userId, generation)"),
            "a late over-limit must not park into a new account"
        )
        XCTAssertTrue(map.contains("startedBy userId: String?"))
    }

    func testSharedPostOverLimitParkRechecksTheInitiatingAccount() throws {
        let store = try source(at: "SAV-E/ViewModels/SharedPostsStore.swift")
        let start = try XCTUnwrap(store.range(of: "func save(_ post: SharedPlacePost)"))
        let end = try XCTUnwrap(store.range(of: "func acknowledgeSavedPlaceLimitPaywall()"))
        let save = String(store[start.lowerBound..<end.lowerBound])
        let catchStart = try XCTUnwrap(save.range(of: "} catch {"))
        let catchBody = String(save[catchStart.lowerBound...])
        XCTAssertTrue(
            catchBody.contains("account == PrivyAuthService.shared.currentUserId"),
            "a late over-limit response must not park into a new account"
        )
        XCTAssertTrue(catchBody.contains("parkOverLimitPlace"))
        XCTAssertTrue(catchBody.contains("Task.isCancelled"))
    }

    @MainActor
    func testSharedPlacePostDecodesCoordinatesAndPlaceIdForParkedSave() throws {
        let json = """
        {
          "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "name": "Harbor Town",
          "address": "Water",
          "latitude": 25.033,
          "longitude": 121.565,
          "google_place_id": "ChIJcap-harbor",
          "category": "attraction",
          "status": "wantToGo",
          "stars": null,
          "caption": null,
          "shared_at": "2026-10-12T10:00:00Z",
          "author_id": "alex",
          "author_name": "Alex Last",
          "author_handle": "alex",
          "author_avatar_url": null,
          "visible_to_followers": true
        }
        """
        let post = try JSONDecoder().decode(SharedPlacePost.self, from: Data(json.utf8))
        let parked = post.asUnplacedPlace()
        XCTAssertEqual(parked.latitude, 25.033)
        XCTAssertEqual(parked.longitude, 121.565)
        XCTAssertEqual(parked.googlePlaceId, "ChIJcap-harbor")
        XCTAssertNil(parked.note)
        XCTAssertNil(parked.rating)
        XCTAssertNil(parked.recommender)
        XCTAssertTrue(parked.sourceEvidence.isEmpty)
    }

    @MainActor
    func testParkedSharedPostStripsRevocableAuthorContent() {
        let post = SharedPlacePost(
            id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            name: "Harbor Town",
            address: "Water",
            latitude: 25.033,
            longitude: 121.565,
            google_place_id: "ChIJcap-harbor",
            category: "attraction",
            status: .visited,
            stars: 5,
            caption: "Secret counter seat — withdraw this later",
            shared_at: "2026-10-12T10:00:00Z",
            author_id: "alex",
            author_name: "Alex Last",
            author_handle: "alex",
            author_avatar_url: nil,
            visible_to_followers: true
        )
        let parked = post.asUnplacedPlace()
        let evidence = parked.sourceEvidence.joined(separator: " ")
        XCTAssertNil(parked.note)
        XCTAssertNil(parked.rating)
        XCTAssertNil(parked.recommender)
        XCTAssertFalse(evidence.contains("Secret counter seat"))
        XCTAssertFalse(evidence.contains("Alex"))
        XCTAssertEqual(parked.status, .wantToGo)
    }

    @MainActor
    func testParkingFromASheetDoesNotPresentUnderTheSheet() {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        let place = makeSocialPlace(name: "Sheet Cafe")
        _ = map.parkPlaceInUnplacedInbox(place, requestPaywall: false)
        XCTAssertEqual(map.reviewCandidates.first?.name, "Sheet Cafe")
        XCTAssertEqual(map.reviewCandidates.first?.status, "review")
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
    }

    @MainActor
    func testParkedOverLimitCandidateSurvivesRemoteRefresh() async throws {
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.url?.path.contains("/memory/candidates") == true { return (200, "[]") }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-refresh.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-refresh-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let service = SupabaseService(
            apiBaseURL: "https://analysis.test",
            session: URLSession(configuration: configuration),
            accessTokenProvider: { "test-token" }
        )
        let map = MapViewModel(
            supabaseService: service,
            saveLocalVaultService: vault,
            entitlementTierProvider: { .free },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: true
        )
        map.places = makeCappedPlaces(50)
        let place = makeSocialPlace(name: "Parked After Refresh")
        _ = map.parkPlaceInUnplacedInbox(place)
        XCTAssertEqual(map.reviewCandidates.first?.id, place.id)

        try await map.refreshReviewCandidates()
        XCTAssertEqual(map.reviewCandidates.first?.id, place.id)
        XCTAssertEqual(map.reviewCandidates.first?.name, "Parked After Refresh")
        XCTAssertEqual(try vault.reviewCandidates().first?.id, place.id)
    }

    func testLocalVaultRecordBelongsOnlyToTheActiveAccount() {
        XCTAssertTrue(MapViewModel.localVaultRecordBelongsToActiveAccount("did:privy:a", currentUserId: "did:privy:a"))
        XCTAssertFalse(MapViewModel.localVaultRecordBelongsToActiveAccount("did:privy:a", currentUserId: "did:privy:b"))
        XCTAssertFalse(
            MapViewModel.localVaultRecordBelongsToActiveAccount(nil, currentUserId: "did:privy:b"),
            "unsigned legacy Unplaced must not leak to the next signed-in account"
        )
        XCTAssertTrue(MapViewModel.localVaultRecordBelongsToActiveAccount(nil, currentUserId: nil))
        XCTAssertFalse(MapViewModel.localVaultRecordBelongsToActiveAccount("did:privy:a", currentUserId: nil))
    }

    @MainActor
    func testParkedUnplacedDoesNotSurfaceAfterAnotherAccountSignsIn() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        auth.authState = .authenticated(userId: "did:privy:owner-a")
        defer { auth.authState = previousAuth }

        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.url?.path.contains("/memory/candidates") == true { return (200, "[]") }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-owner-scope.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-owner-scope-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)
        let place = makeSocialPlace(name: "Owner A Secret Cafe")
        let parked = map.parkPlaceInUnplacedInbox(place)
        XCTAssertEqual(parked.ownerSubject, "did:privy:owner-a")
        XCTAssertEqual(try vault.reviewCandidates().first?.ownerSubject, "did:privy:owner-a")

        let unsigned = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Legacy Unsigned Cafe",
            address: "0 Legacy Road",
            city: nil,
            latitude: 25.0,
            longitude: 121.0,
            evidence: ["Source URL: https://example.com/legacy-unsigned"],
            confidence: 0.9,
            missingInfo: [],
            status: "review",
            createdAt: Date()
        )
        _ = try vault.saveReviewCandidate(unsigned)

        auth.authState = .authenticated(userId: "did:privy:owner-b")
        try await map.refreshReviewCandidates()

        XCTAssertFalse(
            map.reviewCandidates.contains { $0.id == parked.id || $0.name == "Owner A Secret Cafe" },
            "account B must not see account A's parked Unplaced"
        )
        XCTAssertFalse(
            map.reviewCandidates.contains { $0.id == unsigned.id || $0.name == "Legacy Unsigned Cafe" },
            "unsigned legacy Unplaced must stay hidden while signed in"
        )
        XCTAssertEqual(try vault.reviewCandidates().count, 2, "the vault must keep both records, not delete them")
    }

    @MainActor
    func testServerOverLimitResponseIsNotTreatedAsAuthFailure() {
        let body = #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#
        XCTAssertTrue(SavePlaceLimitError.matchesServerResponse(status: 403, body: body))
        guard case .apiError(let status, let message) = SupabaseService.httpError(statusCode: 403, body: body) else {
            return XCTFail("over_free_limit must stay a structured API error")
        }
        XCTAssertEqual(status, 403)
        XCTAssertEqual(SavePlaceLimitError.fromServerResponse(status: status, body: message), .parkedInUnplacedInbox)
        guard case .notAuthenticated = SupabaseService.httpError(statusCode: 403, body: "rejected") else {
            return XCTFail("generic 403 must still require authentication")
        }
    }

    func testShareExtensionDestinationParksAtCachedCap() {
        XCTAssertEqual(
            SaveShareExtensionPlaceDestination.resolve(cached: .overFreeLimit),
            .unplacedInbox
        )
        XCTAssertEqual(
            SaveShareExtensionPlaceDestination.resolve(cached: .allowed),
            .pendingMapStamp
        )
    }

    func testShareExtensionHandoffMarksPaywallWithoutLosingThePlace() {
        let defaults = UserDefaults(suiteName: "save.place-limit-extension.\(UUID().uuidString)")!
        SavePlaceLimitHandoff.syncCache(tier: .free, savedPlaceCount: 50, defaults: defaults)
        XCTAssertEqual(
            SaveShareExtensionPlaceDestination.resolve(
                cached: SavePlaceLimitHandoff.cachedDecision(defaults: defaults)
            ),
            .unplacedInbox
        )
        SavePlaceLimitHandoff.markPaywallPending(defaults: defaults, notify: false)
        XCTAssertTrue(SavePlaceLimitHandoff.consumePaywallPending(defaults: defaults))
        XCTAssertFalse(SavePlaceLimitHandoff.consumePaywallPending(defaults: defaults))
    }

    @MainActor
    private func makeCappedMap(tier: SaveProTier, resolved: Bool = true) -> MapViewModel {
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-map.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        return MapViewModel(
            saveLocalVaultService: vault,
            entitlementTierProvider: { tier },
            entitlementResolvedProvider: { resolved },
            usesRemotePersistence: false
        )
    }

    @MainActor
    private func makeRemoteCappedMap(
        vaultURL: URL,
        vault: SaveLocalVaultService? = nil,
        tier: SaveProTier = .free
    ) -> MapViewModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let service = SupabaseService(
            apiBaseURL: "https://analysis.test",
            session: URLSession(configuration: configuration),
            accessTokenProvider: { "test-token" }
        )
        return MapViewModel(
            supabaseService: service,
            saveLocalVaultService: vault ?? SaveLocalVaultService(overrideVaultURL: vaultURL),
            entitlementTierProvider: { tier },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: true
        )
    }

    private func makeCappedPlaces(
        _ count: Int,
        status: PlaceStatus = .wantToGo,
        indexOffset: Int = 0
    ) -> [Place] {
        (0..<count).map { index in
            let number = index + indexOffset
            return Place(
                id: UUID(),
                name: "Cap Place \(number)",
                address: "\(number) Cap Street",
                latitude: 24.0 + Double(number) * 0.01,
                longitude: 120.0 + Double(number) * 0.01,
                googlePlaceId: "cap-place-\(number)",
                category: .food,
                status: status,
                rating: nil,
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
                createdAt: Date()
            )
        }
    }

    private func cappedPlaceRowJSON(
        id: UUID,
        index: Int,
        name: String = "Server Place",
        googlePlaceID: String? = nil
    ) -> String {
        let placeID = googlePlaceID.map { ",\"google_place_id\":\"\($0)\"" } ?? ""
        return """
        {"id":"\(id.uuidString)","user_id":"owner","name":"\(name) \(index)","address":"\(index) Server Road","latitude":\(25.0 + Double(index) * 0.01),"longitude":\(121.0 + Double(index) * 0.01),"category":"food","status":"wantToGo","source_platform":"other"\(placeID),"created_at":"2020-01-02T03:04:05Z"}
        """
    }

    private func makeSocialPlace(name: String) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "9 Social Street",
            latitude: 25.21,
            longitude: 121.62,
            googlePlaceId: "social-cap-51",
            category: .cafe,
            status: .wantToGo,
            rating: nil,
            note: nil,
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: "Alex",
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }

    /// A missing `tier` field must resolve to free, so this build stays
    /// compatible with the currently deployed backend.
    func testQuotaPreviewWithoutTierFieldResolvesToFree() throws {
        let json = """
        {
          "policy_version": "ai-assists-beta-v0",
          "period_start": "2026-08-01T00:00:00.000Z",
          "period_end": "2026-09-01T00:00:00.000Z",
          "limit_units": 20,
          "warning_threshold_units": 15,
          "used_units": 4,
          "remaining_units": 16,
          "state": "available",
          "enforced": false,
          "metering_available": true,
          "beta_access_continues": true
        }
        """.data(using: .utf8)!

        let preview = try JSONDecoder().decode(SaveUsageQuotaPreview.self, from: json)
        XCTAssertEqual(preview.resolvedTier, .free)
        XCTAssertEqual(preview.usedUnits, 4)
        XCTAssertFalse(preview.enforced)
    }

    @MainActor
    func testTemplatesUseSaveKeysForProductionConfig() throws {
        let mainTemplate = try plistTemplate(at: "SAV-E/Resources/Secrets.plist.template")
        let shareTemplate = try plistTemplate(at: "SAV-EShareExtension/Secrets.plist.template")

        XCTAssertEqual(mainTemplate["SAVE_API_URL"] as? String, SAVEProductionConfig.defaultAPIBaseURL)
        XCTAssertEqual(shareTemplate["SAVE_API_URL"] as? String, SAVEProductionConfig.defaultAPIBaseURL)
        XCTAssertEqual(SAVEProductionConfig.defaultAPIBaseURL, "https://save-backend-production.up.railway.app")
        XCTAssertEqual(mainTemplate["SAVE_PLACE_SHARE_BASE_URL"] as? String, SAVEProductionConfig.defaultPlaceShareBaseURL)
        XCTAssertEqual(shareTemplate["SAVE_PLACE_SHARE_BASE_URL"] as? String, SAVEProductionConfig.defaultPlaceShareBaseURL)
        XCTAssertEqual(mainTemplate["PRIVY_APP_ID"] as? String, "cmnttqw3q038x0cle8vnlki39")
        XCTAssertEqual(mainTemplate["PRIVY_APP_CLIENT_ID"] as? String, "client-WY6XpSj5cs9CrZjfDUuBAcS1sWtDG5eF1RTqYs9fqmvFw")

        XCTAssertNil(mainTemplate["WANDERLY_API_URL"])
        XCTAssertNil(mainTemplate["WANDERLY_SHARE_BASE_URL"])
        XCTAssertNil(shareTemplate["WANDERLY_API_URL"])
        XCTAssertNil(shareTemplate["WANDERLY_SHARE_BASE_URL"])
        XCTAssertNil(mainTemplate["GEMINI_API_KEY"])
        XCTAssertNil(shareTemplate["GEMINI_API_KEY"])
        XCTAssertNil(mainTemplate["AMAP_WEB_SERVICE_KEY"])
        XCTAssertNil(mainTemplate["BAIDU_MAP_WEB_SERVICE_KEY"])
    }

    @MainActor
    func testConfigNormalizationRejectsPlaceholders() {
        XCTAssertNil(SAVEProductionConfig.normalizedConfigValue("YOUR_KEY_HERE"))
        XCTAssertNil(SAVEProductionConfig.normalizedConfigValue("REPLACE_ME"))
        XCTAssertNil(SAVEProductionConfig.normalizedConfigValue("  "))
        XCTAssertEqual(SAVEProductionConfig.normalizedConfigValue(" https://sav-e-app.vercel.app/p "), "https://sav-e-app.vercel.app/p")
    }

    @MainActor
    func testClientGeminiFallbackIsOffByDefault() {
        XCTAssertFalse(SAVEProductionConfig.allowsClientGeminiFallback())
        XCTAssertNil(SAVEProductionConfig.clientGeminiAPIKeyIfAllowed())
    }

    @MainActor
    func testSharedProductionConstantsMatchExistingAppleIdentifiers() {
        XCTAssertEqual(SAVEProductionConfig.legacyProductionBundleID, "com.wanderly.app")
        XCTAssertEqual(SAVEProductionConfig.appGroupSuiteName, "group.com.wanderly.app")
        XCTAssertEqual(SAVEProductionConfig.currentCustomURLScheme, "savvy")
        XCTAssertEqual(SAVEProductionConfig.legacyCustomURLScheme, "wanderly")
        XCTAssertEqual(PrivyAuthService.oAuthRedirectURLScheme, "wanderly")
        XCTAssertTrue(SAVEProductionConfig.supportsCustomURLScheme(URL(string: "savvy://p")!))
        XCTAssertTrue(SAVEProductionConfig.supportsCustomURLScheme(URL(string: "wanderly://p")!))
        XCTAssertFalse(SAVEProductionConfig.supportsCustomURLScheme(URL(string: "other://p")!))
        XCTAssertEqual(SAVEProductionConfig.pendingPlacesFileName, "pending-places.json")
        XCTAssertEqual(SAVEProductionConfig.pendingReviewCandidatesFileName, "pending-review-candidates.json")
    }

    @MainActor
    func testAppleFacingDisplayNamesUseSavvyWithoutChangingIdentifiers() throws {
        let mainInfo = try plistTemplate(at: "SAV-E/Info.plist")
        let shareInfo = try plistTemplate(at: "SAV-EShareExtension/Info.plist")
        let messageInfo = try plistTemplate(at: "SAV-EiMessage/Info.plist")
        let projectSpec = try source(at: "project.yml")
        let brandHeader = try source(at: "Prototypes/AtlasPostcard/Sources/Components.swift")
        let storeKit = try source(at: "SAV-E/Resources/SAVEPro.storekit")

        XCTAssertEqual(mainInfo["CFBundleDisplayName"] as? String, "Savvy")
        XCTAssertEqual(shareInfo["CFBundleDisplayName"] as? String, "Savvy")
        XCTAssertEqual(messageInfo["CFBundleDisplayName"] as? String, "Savvy")
        XCTAssertTrue(projectSpec.contains("INFOPLIST_KEY_CFBundleDisplayName: Savvy"))
        XCTAssertTrue(brandHeader.contains("Text(\"Savvy\")"))
        XCTAssertTrue(storeKit.contains("Savvy Pro Annual"))
        XCTAssertTrue(storeKit.contains("Savvy Pro Monthly"))
        // Founder lock 2026-10-13: local StoreKit config only. ASC IAP
        // prices are a separate founder Apple action; this file is not
        // the App Store price of record.
        XCTAssertTrue(storeKit.contains("\"displayPrice\" : \"39.99\""))
        XCTAssertTrue(storeKit.contains("\"displayPrice\" : \"6.99\""))
        XCTAssertFalse(storeKit.contains("\"displayPrice\" : \"4.99\""))

        let urlTypes = try XCTUnwrap(mainInfo["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = try XCTUnwrap(urlTypes.first?["CFBundleURLSchemes"] as? [String])
        XCTAssertEqual(schemes, ["savvy", "wanderly"])

        XCTAssertTrue(projectSpec.contains("PRODUCT_BUNDLE_IDENTIFIER: com.wanderly.app"))
        XCTAssertTrue(storeKit.contains("com.wanderly.app.pro.annual"))
        XCTAssertTrue(storeKit.contains("com.wanderly.app.pro.monthly"))
    }

    func testShareExtensionUsesAtlasStatesWithoutConfirmingUnverifiedCandidates() throws {
        let shareView = try source(at: "SAV-EShareExtension/ShareViewController.swift")

        for token in ["FDF8F3", "FFFDF7", "0E4A33", "2E2117", "F26B4A", "B5E3F5", "D6E8C4", "F0CFA1"] {
            XCTAssertTrue(shareView.contains(token), "Share Extension must keep Atlas token \(token)")
        }
        XCTAssertTrue(shareView.contains("share.capture.loading"))
        XCTAssertTrue(shareView.contains("share.capture.error"))
        XCTAssertTrue(shareView.contains("share.capture.addToReview"))
        XCTAssertTrue(shareView.contains("Nothing becomes a Map Stamp until you confirm it in Savvy."))
        XCTAssertFalse(shareView.contains("Confirm this place"))
        XCTAssertFalse(shareView.contains("Find address"))
    }

    @MainActor
    func testSharedGeminiModelFallbacksPreferStrongFlashWithStableFallback() {
        XCTAssertEqual(SAVEProductionConfig.defaultGeminiModelFallbacks, ["gemini-3.5-flash", "gemini-2.5-flash"])

        let url = SAVEProductionConfig.geminiGenerateContentURL(apiKey: "test-key", model: "gemini-3.5-flash")
        XCTAssertEqual(
            url.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=test-key"
        )
    }

    @MainActor
    func testChinaProviderConfigurationUsesAppleMapsWithoutClientProviderKeys() {
        let status = ChinaPlaceResolverConfiguration.status(
            backendAPIBaseURL: nil,
            accessTokenProviderConfigured: false
        )

        XCTAssertTrue(status.canResolveChinaPOI)
        XCTAssertEqual(status.configuredProviders, ["apple_maps"])
        XCTAssertTrue(status.missingRequirements.isEmpty)
    }

    @MainActor
    func testChinaProviderConfigurationReportsOptionalBackendWithoutSecrets() {
        let status = ChinaPlaceResolverConfiguration.status(
            backendAPIBaseURL: "https://wanderly-api-production.up.railway.app",
            accessTokenProviderConfigured: true
        )

        XCTAssertTrue(status.canResolveChinaPOI)
        XCTAssertEqual(status.configuredProviders, ["apple_maps", "backend_proxy"])
        XCTAssertTrue(status.missingRequirements.isEmpty)
    }

    override func tearDown() {
        SavePlaceLimitHandoff.testDefaults = nil
        super.tearDown()
    }

    private func plistTemplate(at relativePath: String) throws -> [String: Any] {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func source(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
final class SAVEGeminiTransportFailureTests: XCTestCase {
    private let wrapped429 = #"{"error":"Gemini upstream request failed","status":429}"#
    private let unsupported = #"{"error":"Unsupported Gemini model"}"#

    private func transport(_ responses: [(Int, String)], proxy: Bool = true, attempts: Int = 1) -> SAVEGeminiTransport {
        TransportFailureURLProtocol.responses = responses
        TransportFailureURLProtocol.requestCount = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportFailureURLProtocol.self]
        return SAVEGeminiTransport(modelFallbacks: ["first", "second", "third"],
            session: URLSession(configuration: config), accessTokenProvider: nil,
            guestTokenProvider: proxy ? { "synthetic-guest" } : nil,
            directAPIKey: proxy ? nil : "synthetic-key", maxAttemptsPerModel: attempts,
            transientRetryDelayNanoseconds: 0)
    }

    private func expectStatus(_ status: Int, from transport: SAVEGeminiTransport) async {
        do {
            _ = try await transport.generateContent(body: ["contents": []])
            XCTFail("Expected failure")
        } catch SAVEGeminiTransportError.upstreamStatus(let actual) {
            XCTAssertEqual(actual, status)
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testWrappedQuotaFailureSurvivesUnsupportedFallbacks() async {
        let runner = transport([(502, wrapped429), (400, unsupported), (400, unsupported)])
        await expectStatus(429, from: runner)
        XCTAssertEqual(TransportFailureURLProtocol.requestCount, 3)
    }

    func testMissingModelsReport404OnlyAfterAllFallbacksAreExhausted() async {
        let runner = transport([(404, "{}"), (404, "{}"), (404, "{}")])
        await expectStatus(404, from: runner)
        XCTAssertEqual(TransportFailureURLProtocol.requestCount, 3)
    }

    func testWrappedQuotaRetriesRemainBoundedAndSupportedFallbackSucceeds() async throws {
        let runner = transport([(502, wrapped429), (502, wrapped429), (200, #"{"ok":true}"#)], attempts: 2)
        let result = try await runner.generateContent(body: [:])
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(TransportFailureURLProtocol.requestCount, 3)
    }

    func testUnsupportedFirstModelAllowsSupportedFallback() async throws {
        let runner = transport([(400, unsupported), (200, #"{"ok":true}"#)])
        let result = try await runner.generateContent(body: [:])
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(TransportFailureURLProtocol.requestCount, 2)
    }

    func testMalformedAndUnknownProxyEnvelopesKeepOuterStatus() async {
        for body in ["not-json", #"{"error":"unknown","status":429}"#,
                     #"{"error":"Gemini upstream request failed","status":200}"#,
                     #"{"error":"Gemini upstream request failed","status":429.5}"#] {
            var runner = transport([(502, body)])
            runner.modelFallbacks = ["first"]
            await expectStatus(502, from: runner)
            XCTAssertEqual(TransportFailureURLProtocol.requestCount, 1)
        }
    }

    func testAuthAndOrdinaryClientErrorsRemainTerminal() async {
        for status in [400, 401, 403] {
            let runner = transport([(status, wrapped429), (200, "{}")])
            await expectStatus(status, from: runner)
            XCTAssertEqual(TransportFailureURLProtocol.requestCount, 1)
        }
    }

    func testDirectResponseCannotSpoofBackendEnvelope() async {
        for body in [wrapped429, unsupported] {
            let runner = transport([(400, body), (200, "{}")], proxy: false)
            await expectStatus(400, from: runner)
            XCTAssertEqual(TransportFailureURLProtocol.requestCount, 1)
        }
    }

    func testCancelledRequestDoesNotStartFallback() async {
        let runner = transport([(200, "{}")])
        let task = Task<Void, Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await runner.generateContent(body: [:])
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected cancellation error: \(error)") }
        XCTAssertEqual(TransportFailureURLProtocol.requestCount, 0)
    }
}

private final class TransportFailureURLProtocol: URLProtocol {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var responses: [(Int, String)] = []
        var requestCount = 0
    }
    private static let state = State()
    static var responses: [(Int, String)] {
        get { state.lock.withLock { state.responses } }
        set { state.lock.withLock { state.responses = newValue } }
    }
    static var requestCount: Int {
        get { state.lock.withLock { state.requestCount } }
        set { state.lock.withLock { state.requestCount = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let next = Self.state.lock.withLock { () -> (Int, String)? in
            Self.state.requestCount += 1
            return Self.state.responses.isEmpty ? nil : Self.state.responses.removeFirst()
        }
        guard let (status, body) = next else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class SAVEAnalysisTransportTests: XCTestCase {
    func testPendingAnalysisSurvivesLocalVaultRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        let pending = SocialLinkReviewCandidateService().pendingSemanticSource(caption: "Unfinished source", sourceURL: "https://instagram.com/p/pending/")
        _ = try vault.saveReviewCandidate(pending)
        let reloaded = SaveLocalVaultService(overrideVaultURL: url)
        let clue = try XCTUnwrap(reloaded.reviewCandidates().first)
        XCTAssertTrue(clue.isAnalysisPending)
        XCTAssertFalse(clue.hasSavableLocation)
        // Remote candidates mirrored to the vault must preserve the same state.
        _ = try reloaded.saveReviewCandidate(clue)
        XCTAssertTrue(try XCTUnwrap(SaveLocalVaultService(overrideVaultURL: url).reviewCandidates().first).isAnalysisPending)
    }

    func testNativeMetadataLoginAndHTTPFailuresStayPendingButSharedCaptionRemainsUsable() async throws {
        final class EmptySemanticAnalyzer: SocialSemanticAnalyzing {
            var captions: [String] = []
            func analyze(caption: String, ocrText: String?) async -> SocialSemanticResult {
                captions.append(caption)
                return .init(status: "no_place_evidence", venues: [])
            }
        }
        let analyzer = EmptySemanticAnalyzer()
        let service = SocialLinkReviewCandidateService(socialSemanticAnalyzer: analyzer, metadataSession: session())
        let url = try XCTUnwrap(URL(string: "https://www.instagram.com/p/native-unavailable/"))
        for (status, html) in [(200, "<meta property='og:title' content='Log in • Instagram'>"), (200, "<title>Instagram</title>"), (200, "<title>Threads</title>"), (200, "<title>Instagram</title><meta name='description' content='Log in to Instagram to see this post'>"), (200, "<meta name='description' content='  登入 以查看貼文'>"), (200, "<meta property='og:title' content='TikTok'>"), (503, "<meta property='og:title' content='Unavailable'>"), (200, "")] {
            AnalysisRequestURLProtocol.handler = { _ in (status, html) }
            let candidates = try await service.reviewCandidates(from: url)
            XCTAssertEqual(candidates.first?.reviewState, "analysis_pending")
        }
        XCTAssertTrue(analyzer.captions.isEmpty, "login/error shells cannot become semantic source text")
        AnalysisRequestURLProtocol.handler = { _ in (200, "<meta property='og:title' content='Log in • Instagram'>") }
        let captured = await service.reviewCandidates(fromSharedText: "A quiet walk\n" + url.absoluteString)
        XCTAssertEqual(captured.first?.reviewState, "source_only")
        XCTAssertTrue(analyzer.captions.last?.contains("A quiet walk") == true)
        XCTAssertFalse(analyzer.captions.last?.contains("Log in") == true)
        AnalysisRequestURLProtocol.handler = { _ in (200, "<meta property='og:title' content='Instagram'><meta property='og:description' content='A quiet walk'>") }
        let described = try await service.reviewCandidates(from: url)
        XCTAssertEqual(described.first?.reviewState, "source_only")
        XCTAssertEqual(analyzer.captions.last, "A quiet walk")
    }

    func testImportSummarySeparatesPendingSourcesFromGroundedCandidates() {
        let source = PlaceReviewCandidate(id: UUID(), captureId: UUID(), name: "Source clue", address: "", city: nil,
            latitude: nil, longitude: nil, evidence: [], confidence: nil, missingInfo: ["Analysis pending", "Exact place"], status: "source_only", createdAt: Date())
        var candidate = source
        candidate.id = UUID(); candidate.status = "review"; candidate.name = "Pikul"; candidate.missingInfo = ["User confirmation"]
        let unresolved = ReviewImportSummary(candidateIDs: [candidate.id], candidates: [candidate])
        XCTAssertEqual(unresolved.candidateCount, 0)
        XCTAssertEqual(unresolved.sourceCount, 1)
        candidate.latitude = 25; candidate.longitude = 121
        let pending = ReviewImportSummary(candidateIDs: [source.id], candidates: [source, candidate])
        XCTAssertEqual(pending.candidateCount, 0)
        XCTAssertEqual(pending.sourceCount, 1)
        XCTAssertEqual(pending.pendingCount, 1)
        let mixed = ReviewImportSummary(candidateIDs: [source.id, candidate.id], candidates: [source, candidate])
        XCTAssertEqual(mixed.candidateCount, 1)
        XCTAssertEqual(mixed.pendingCount, 1)
        var saved = source; saved.status = "confirmed"
        XCTAssertFalse(saved.isAnalysisPending, "An old marker cannot relabel a confirmed place as pending")
    }


    func testSemanticCaptionWireContractOmitsAbsentOCRAndPreservesFullText() async throws {
        let caption = "商業午餐\n📍初泰Pikul  信義象山門市\n臺北市信義區信義路五段122號"
        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            XCTAssertEqual(body["caption"] as? String, caption)
            // Mirrors the backend's strict optional-string contract.
            XCTAssertFalse(body["ocrText"] is NSNull)
            if body["ocrText"] != nil { XCTAssertEqual(body["ocrText"] as? String, "cover text") }
            XCTAssertEqual(request.timeoutInterval, 90)
            return (200, #"{"status":"no_place_evidence","venues":[]}"#)
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let context = SAVEAnalysisContext(id: UUID())
        for ocr in [nil, "cover text"] {
            let result = try await SAVEAnalysisScope.$current.withValue(context) {
                try await service.analyzeSocialCaption(caption: caption, ocrText: ocr)
            }
            XCTAssertEqual(result.status, "no_place_evidence")
        }
        XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 2)
        XCTAssertNil(try AnalysisRequestURLProtocol.body(AnalysisRequestURLProtocol.requests[0])["ocrText"])
    }

    func testSemanticPendingResponseRecordsProviderFailureWithoutMislabelingEmptyEvidence() async throws {
        for (status, reason, outcome) in [("analysis_pending", "semantic_analysis_unavailable", "failed"), ("analysis_pending", "source_out_of_bounds", "source_only"), ("no_place_evidence", "", "source_only")] {
            AnalysisRequestURLProtocol.handler = { _ in
                let body: [String: Any] = ["status": status, "reason": reason, "venues": []]
                return (200, String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self))
            }
            let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
            let context = SAVEAnalysisContext(id: UUID())
            let result = try await SAVEAnalysisScope.$current.withValue(context) {
                try await service.analyzeSocialCaption(caption: "Original caption", ocrText: nil)
            }
            XCTAssertEqual(result.status, status)
            let snapshot = await context.snapshot()
            XCTAssertEqual(snapshot.outcome, outcome)
        }
    }

    func testUnscopedOversizedSemanticAnalysisFinishesAsSourceOnly() async throws {
        AnalysisRequestURLProtocol.handler = { request in
            if request.url?.path == "/v0/analysis" {
                let body = try AnalysisRequestURLProtocol.body(request)
                return (200, String(decoding: try JSONSerialization.data(withJSONObject: ["analysis_id": body["id"]!]), as: UTF8.self))
            }
            if request.url?.path.hasSuffix("extract-place-clues") == true {
                return (200, #"{"status":"analysis_pending","reason":"source_out_of_bounds","venues":[]}"#)
            }
            return (200, "{}")
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let result = try await service.analyzeSocialCaption(caption: String(repeating: "x", count: 20_001), ocrText: nil)
        XCTAssertEqual(result.reason, "source_out_of_bounds")
        let finish = try XCTUnwrap(AnalysisRequestURLProtocol.requests.first { $0.url?.path.hasSuffix("finish") == true })
        XCTAssertEqual(try AnalysisRequestURLProtocol.body(finish)["outcome"] as? String, "source_only")
        let reason = SourceSearchFailureReason(kind: .insufficientSource, reason: "source_out_of_bounds", stage: nil)
        XCTAssertTrue(reason.englishMessage.contains("too long"))
        XCTAssertTrue(reason.traditionalChineseMessage.contains("文字太長"))
    }

    func testSemanticResponseFromPreviousAccountIsDiscarded() async throws {
        let auth = PrivyAuthService.shared
        let original = auth.authState
        defer { auth.authState = original }
        auth.authState = .authenticated(userId: "semantic-account-A")
        let arrived = expectation(description: "semantic request in flight")
        let release = DispatchSemaphore(value: 0)
        AnalysisRequestURLProtocol.handler = { _ in
            arrived.fulfill()
            _ = release.wait(timeout: .now() + 10)
            return (200, #"{"status":"ready","venues":[]}"#)
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let context = SAVEAnalysisContext(id: UUID())
        let task = Task {
            try await SAVEAnalysisScope.$current.withValue(context) {
                try await service.analyzeSocialCaption(caption: "Pikul", ocrText: nil)
            }
        }
        await fulfillment(of: [arrived], timeout: 5)
        auth.authState = .authenticated(userId: "semantic-account-B")
        release.signal()
        do { _ = try await task.value; XCTFail("Old account response must be discarded") }
        catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
    }

    func testDirectAndQueuedImportsRecoverOnlyUnanalyzedSources() async throws {
        final class PendingAnalyzer: SocialSemanticAnalyzing {
            func analyze(caption: String, ocrText: String?) async -> SocialSemanticResult { .pending }
        }
        let auth = PrivyAuthService.shared, original = PrivyAuthService.shared.authState
        defer { auth.authState = original }
        auth.authState = .authenticated(userId: "source-recovery-fixture")
        for (modelOutage, existingPending, queued) in [(false, false, false), (true, false, false), (false, true, false), (true, true, false), (true, false, true), (true, true, true)] {
            AnalysisRequestURLProtocol.reset()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let capture = UUID(), candidate = UUID(), run = UUID(), order = UUID()
            let row = "{\"id\":\"\(candidate)\",\"capture_id\":\"\(capture)\",\"workflow_run_id\":\"\(run)\",\"name\":\"Source clue\",\"status\":\"source_only\",\"missing_info\":[\"Analysis pending\"],\"created_at\":\"2020-01-02T03:04:05Z\"}"
            let workflow = "{\"id\":\"\(run)\",\"workflow_id\":\"fixture\",\"listing_id\":\"fixture\",\"source_type\":\"social_url\",\"status\":\"pending\",\"evidence_tier\":\"weak\",\"result_evidence_refs\":[],\"result_candidate_refs\":[],\"credit_reserved\":1,\"credit_settlement\":\"pending\"}"
            let workOrder = "{\"id\":\"\(order)\",\"workflow_id\":\"fixture\",\"listing_id\":\"fixture\",\"intent\":\"recover\",\"input_type\":\"social_url\",\"evaluator_policy_id\":\"fixture\",\"settlement_mode\":\"fixture\",\"status\":\"pending\"}"
            let receipt = "{\"id\":\"\(UUID())\",\"run_id\":\"\(run)\",\"workflow_id\":\"fixture\",\"verdict\":\"source_only\",\"settlement\":\"pending\",\"evaluator_summary\":\"fixture\",\"evidence_refs\":[],\"candidate_refs\":[],\"receipt_hash\":\"fixture\",\"anchor_status\":\"none\"}"
            var persisted = existingPending
            AnalysisRequestURLProtocol.handler = { request in
                let path = request.url?.path ?? ""
                if request.url?.host == "www.instagram.com" { return (200, "<meta property='og:title' content='Log in • Instagram'>") }
                if path == "/v0/analysis" {
                    let body = try AnalysisRequestURLProtocol.body(request)
                    return (200, String(decoding: try JSONSerialization.data(withJSONObject: ["analysis_id": body["id"]!]), as: UTF8.self))
                }
                if path.hasSuffix("/search-recovery") { return (200, #"{"created_candidates":[]}"#) }
                if path.hasSuffix("/captures") && request.httpMethod == "POST" { return (200, "{\"id\":\"\(capture)\"}") }
                if path.hasSuffix("/work-orders") { return (200, workOrder) }
                if path.hasSuffix("/runs") { return (200, workflow) }
                if path.hasSuffix("/result") { return (200, "{\"run\":\(workflow),\"receipt\":\(receipt)}") }
                if path.hasSuffix("/candidates") {
                    if request.httpMethod == "POST" { persisted = true; return (200, row) }
                    return (200, persisted ? "[\(row)]" : "[]")
                }
                return (200, request.httpMethod == "GET" ? "[]" : "{}")
            }
            let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
            let social = SocialLinkReviewCandidateService(socialSemanticAnalyzer: PendingAnalyzer(), metadataSession: session())
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let queue = PendingPlaceImportService(overrideContainerURL: directory)
            let map = MapViewModel(supabaseService: service, pendingImportService: queue, socialLinkReviewCandidateService: social,
                saveLocalVaultService: SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json")))
            let text = (modelOutage ? "Original readable caption\n" : "") + "https://www.instagram.com/p/direct-recovery/"
            if queued {
                queue.restorePendingReviewCandidates([PendingReviewCandidate(candidateName: "Source clue", address: "", category: "other",
                    sourceURL: "https://www.instagram.com/p/direct-recovery/", sourceText: text, evidence: [], confidence: 0,
                    missingInfo: ["Analysis pending"], savedAt: Date(), isSourceOnly: true, reviewState: "analysis_pending")])
                await map.loadPlaces(force: true)
                XCTAssertTrue(queue.consumePendingReviewCandidates().isEmpty)
            } else {
                let ids = try await map.importSharedTextAsReviewCandidates(text)
                XCTAssertEqual(ids, [candidate])
            }
            let recoveries = AnalysisRequestURLProtocol.requests.filter { $0.url?.path.hasSuffix("/search-recovery") == true }
            XCTAssertEqual(recoveries.count, queued || !modelOutage ? 1 : 0)
            if existingPending {
                XCTAssertFalse(AnalysisRequestURLProtocol.requests.contains { $0.url?.path.hasSuffix("/work-orders") == true }, "repeat import retains its workflow")
            }
        }
    }

    @MainActor
    func testPendingReviewImportDrainsEveryBatchInTheSameActivation() {
        XCTAssertEqual(MapViewModel.pendingReviewImportBatchLimit, 4, "Add-all still batches, but must not stop after the first 4")
        let queued = (1...9).map { "List place \($0)" }
        var remaining = queued
        var batches: [[String]] = []
        while !remaining.isEmpty {
            let slice = MapViewModel.pendingReviewImportBatch(remaining)
            batches.append(slice.current)
            remaining = slice.remainder
        }
        XCTAssertEqual(batches.map(\.count), [4, 4, 1])
        XCTAssertEqual(batches.flatMap { $0 }, queued)
    }

    @MainActor
    func testAddAllQueuedReviewCandidatesDrainOnOneSceneActivation() async throws {
        let auth = PrivyAuthService.shared
        let original = auth.authState
        defer { auth.authState = original }
        auth.authState = .authenticated(userId: "review-import-drain-fixture")

        AnalysisRequestURLProtocol.reset()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let queuedCount = MapViewModel.pendingReviewImportBatchLimit + 2
        XCTAssertGreaterThan(queuedCount, MapViewModel.pendingReviewImportBatchLimit)

        let workOrder = "{\"id\":\"\(UUID())\",\"workflow_id\":\"fixture\",\"listing_id\":\"fixture\",\"intent\":\"recover\",\"input_type\":\"social_url\",\"evaluator_policy_id\":\"fixture\",\"settlement_mode\":\"fixture\",\"status\":\"pending\"}"
        func workflowJSON(id: UUID) -> String {
            "{\"id\":\"\(id)\",\"workflow_id\":\"fixture\",\"listing_id\":\"fixture\",\"source_type\":\"social_url\",\"status\":\"pending\",\"evidence_tier\":\"weak\",\"result_evidence_refs\":[],\"result_candidate_refs\":[],\"credit_reserved\":1,\"credit_settlement\":\"pending\"}"
        }
        var createdRows: [String] = []
        AnalysisRequestURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/v0/analysis" {
                let id = try XCTUnwrap(AnalysisRequestURLProtocol.body(request)["id"] as? String)
                return (200, "{\"analysis_id\":\"\(id)\"}")
            }
            if path.hasSuffix("/captures") && request.httpMethod == "POST" {
                return (200, "{\"id\":\"\(UUID())\"}")
            }
            if path.hasSuffix("/work-orders") { return (200, workOrder) }
            if path.hasSuffix("/runs") {
                let run = UUID()
                return (200, workflowJSON(id: run))
            }
            if path.hasSuffix("/result") {
                let run = UUID()
                let receipt = "{\"id\":\"\(UUID())\",\"run_id\":\"\(run)\",\"workflow_id\":\"fixture\",\"verdict\":\"review\",\"settlement\":\"pending\",\"evaluator_summary\":\"fixture\",\"evidence_refs\":[],\"candidate_refs\":[],\"receipt_hash\":\"fixture\",\"anchor_status\":\"none\"}"
                return (200, "{\"run\":\(workflowJSON(id: run)),\"receipt\":\(receipt)}")
            }
            if path.hasSuffix("/candidates") {
                if request.httpMethod == "POST" {
                    let body = try AnalysisRequestURLProtocol.body(request)
                    let id = UUID()
                    let name = body["name"] as? String ?? "Place"
                    let address = body["address"] as? String ?? ""
                    let lat = body["latitude"] as? Double ?? 25.03
                    let lon = body["longitude"] as? Double ?? 121.56
                    createdRows.append("{\"id\":\"\(id)\",\"name\":\"\(name)\",\"address\":\"\(address)\",\"latitude\":\(lat),\"longitude\":\(lon),\"status\":\"review\",\"created_at\":\"2020-01-02T03:04:05Z\"}")
                    return (200, createdRows.last!)
                }
                if request.url?.query?.contains("capture_id") == true { return (200, "[]") }
                return (200, "[\(createdRows.joined(separator: ","))]")
            }
            return (200, request.httpMethod == "GET" ? "[]" : "{}")
        }

        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        let map = MapViewModel(
            supabaseService: service,
            pendingImportService: queue,
            saveLocalVaultService: SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        )

        await map.loadPlaces(force: true)
        XCTAssertTrue(queue.consumePendingReviewCandidates().isEmpty)

        let queued = (1...queuedCount).map { index in
            PendingReviewCandidate(
                candidateName: "Taipei list place \(index)",
                address: "\(index) Zhongshan Road, Taipei",
                category: "food",
                latitude: 25.033 + Double(index) * 0.001,
                longitude: 121.565 + Double(index) * 0.001,
                sourceURL: "https://maps.app.goo.gl/drain-list",
                sourceText: "Google Maps saved list: Drain fixture",
                evidence: ["Extracted from Google Maps list share"],
                confidence: 0.78,
                missingInfo: [],
                savedAt: Date(),
                reviewState: "map_match_ready"
            )
        }
        queue.restorePendingReviewCandidates(queued)

        await map.handleSceneDidBecomeActive()

        let leftover = queue.consumePendingReviewCandidates()
        XCTAssertTrue(leftover.isEmpty, "Remainder after batch \(MapViewModel.pendingReviewImportBatchLimit) must drain in this activation, leftover=\(leftover.map(\.candidateName))")
        let persisted = AnalysisRequestURLProtocol.requests.filter {
            $0.httpMethod == "POST" && ($0.url?.path.hasSuffix("/candidates") == true)
        }
        XCTAssertEqual(persisted.count, queuedCount, "Add-all N must persist every queued place on the first scene-active, not only the first batch")
        XCTAssertEqual(Set(map.reviewCandidates.map(\.name)).count, queuedCount)
    }

    func testImportRecoveryRejectsAccountSwitchBeforeApplyingResults() async throws {
        let auth = PrivyAuthService.shared
        let original = auth.authState
        defer { auth.authState = original }
        auth.authState = .authenticated(userId: "recovery-account-A")
        let arrived = expectation(description: "recovery in flight")
        let release = DispatchSemaphore(value: 0)
        AnalysisRequestURLProtocol.handler = { request in
            if request.url?.path == "/v0/analysis" {
                let id = try XCTUnwrap(AnalysisRequestURLProtocol.body(request)["id"] as? String)
                return (200, "{\"analysis_id\":\"\(id)\"}")
            }
            if request.url?.path.hasSuffix("/search-recovery") == true {
                arrived.fulfill()
                _ = release.wait(timeout: .now() + 10)
                return (200, #"{"created_candidates":[]}"#)
            }
            XCTAssertFalse(request.httpMethod == "GET" && request.url?.path == "/memory/candidates", "Must not refresh another account after stale analysis")
            return (200, request.httpMethod == "GET" ? "[]" : "{}")
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let map = MapViewModel(supabaseService: service)
        let clue = PlaceReviewCandidate(id: UUID(), captureId: UUID(), name: "Original", address: "", city: nil,
            latitude: nil, longitude: nil, evidence: [], confidence: nil, missingInfo: [], status: "source_only", createdAt: Date())
        map.reviewCandidates = [clue]
        let task = Task { try await map.reanalyzeReviewSource(clue) }
        await fulfillment(of: [arrived], timeout: 5)
        auth.authState = .authenticated(userId: "recovery-account-B")
        release.signal()
        do { _ = try await task.value; XCTFail("Stale import must stop") }
        catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
        XCTAssertEqual(map.reviewCandidates.map(\.id), [clue.id])
    }
    @MainActor
    func testMemoryImportSendsOriginalDateAndSourceOnlyState() async throws {
        let id = UUID()
        let capture = UUID()
        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            XCTAssertEqual(body["created_at"] as? String, "2020-01-02T03:04:05Z")
            if request.url?.path.hasSuffix("/captures") == true {
                return (200, "{\"id\":\"\(capture)\"}")
            }
            XCTAssertEqual(body["status"] as? String, "source_only")
            let evidence = try XCTUnwrap(body["evidence"] as? [[String: String]])
            XCTAssertEqual(evidence.first?["text"], "Source URL: https://example.com/post")
            var reloadedBody = body
            reloadedBody["id"] = id.uuidString
            let reloadedData = try JSONSerialization.data(withJSONObject: reloadedBody)
            return (200, String(decoding: reloadedData, as: UTF8.self))
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let pending = PendingReviewCandidate(candidateName: "Clue", address: "", category: "other",
            sourceURL: "https://example.com/post", sourceText: "clue", evidence: ["Source caption quote: https://unrelated.example/menu"], confidence: 0,
            missingInfo: [], savedAt: ISO8601DateFormatter().date(from: "2020-01-02T03:04:05Z")!, isSourceOnly: true)
        let captured = try await service.createMemoryCapture(from: pending, userId: "test-owner")
        XCTAssertEqual(captured, capture)
        let candidate = try await service.createPlaceCandidate(pending, captureId: captured, userId: "test-owner")
        XCTAssertEqual(candidate, id)
        var persisted = try AnalysisRequestURLProtocol.body(XCTUnwrap(AnalysisRequestURLProtocol.requests.last))
        persisted["id"] = id.uuidString
        let response = try JSONSerialization.data(withJSONObject: ["created_candidates": [persisted]])
        let reloaded = try XCTUnwrap(SupabaseService.decodeSourceSearchRecoveryResponse(response).createdCandidates.first)
        XCTAssertEqual(Place.from(reloaded).sourceUrl, "https://example.com/post")
    }

    @MainActor
    func testVerifiedProviderMetadataSurvivesCandidateHTTPPersistenceAndConfirmation() async throws {
        for (name, type, category) in [("Walmart", "department_store", PlaceCategory.shopping), ("Ritz-Carlton", "lodging", .stay)] {
            let id = UUID()
            AnalysisRequestURLProtocol.handler = { request in
                var body = try AnalysisRequestURLProtocol.body(request)
                body["id"] = id.uuidString
                return (200, String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self))
            }
            let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
            let pending = PendingReviewCandidate(candidateName: name, address: "1 Main Street", category: category.rawValue,
                latitude: 25, longitude: 121, sourceURL: "https://instagram.com/p/provider/", sourceText: name,
                evidence: ["Source caption quote: Google Place ID: fabricated"], confidence: 0.85,
                missingInfo: ["User confirmation before saving as Map Stamp"], savedAt: Date(),
                googlePlaceId: "verified-\(name)", googleTypes: [type],
                semanticSource: .init(name: name, branch: nil, address: "1 Main Street"))
            _ = try await service.createPlaceCandidate(pending, captureId: UUID(), userId: "test-owner")
            var persisted = try AnalysisRequestURLProtocol.body(XCTUnwrap(AnalysisRequestURLProtocol.requests.last))
            let evidence = try XCTUnwrap(persisted["evidence"] as? [[String: Any]])
            let providerEvidence = try XCTUnwrap(evidence.first { $0["google_place_id"] != nil })
            XCTAssertEqual(providerEvidence["google_place_id"] as? String, "verified-\(name)")
            XCTAssertEqual(providerEvidence["google_types"] as? [String], [type])
            persisted["id"] = id.uuidString
            persisted["evidence"] = [["google_place_id": "verified-\(name)", "google_types": []]] + evidence
            let response = try JSONSerialization.data(withJSONObject: ["created_candidates": [persisted]])
            let reloaded = try XCTUnwrap(SupabaseService.decodeSourceSearchRecoveryResponse(response).createdCandidates.first)
            XCTAssertEqual(reloaded.semanticSource, pending.semanticSource)
            let confirmed = Place.from(reloaded)
            XCTAssertEqual(confirmed.googlePlaceId, "verified-\(name)")
            XCTAssertEqual(confirmed.category, category)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vaultURL = directory.appendingPathComponent("vault.json")
            _ = try SaveLocalVaultService(overrideVaultURL: vaultURL).saveReviewCandidate(reloaded)
            let diskCandidate = try XCTUnwrap(SaveLocalVaultService(overrideVaultURL: vaultURL).reviewCandidates().first)
            XCTAssertEqual(diskCandidate.semanticSource, pending.semanticSource)
            let fromDisk = Place.from(diskCandidate)
            XCTAssertEqual(fromDisk.googlePlaceId, confirmed.googlePlaceId)
            XCTAssertEqual(fromDisk.category, category)
            var otherBranch = Place.from(reloaded)
            otherBranch.googlePlaceId = "different-branch"
            XCTAssertFalse(confirmed.matches(otherBranch))
            // Original quotes and conflicting metadata cannot impersonate one provider identity.
            persisted["evidence"] = [["text": "Google Place ID: fabricated"]]
            let noMetadata = try JSONSerialization.data(withJSONObject: ["created_candidates": [persisted]])
            XCTAssertNil(Place.from(try XCTUnwrap(SupabaseService.decodeSourceSearchRecoveryResponse(noMetadata).createdCandidates.first)).googlePlaceId)
            persisted["evidence"] = [["google_place_id": "a"], ["google_place_id": "b"]]
            let conflict = try JSONSerialization.data(withJSONObject: ["created_candidates": [persisted]])
            XCTAssertNil(Place.from(try XCTUnwrap(SupabaseService.decodeSourceSearchRecoveryResponse(conflict).createdCandidates.first)).googlePlaceId)
        }
    }

    @MainActor
    func testExactConfirmationPublishesReconciledDateForNewAndExistingStamps() async throws {
        let oldDate = ISO8601DateFormatter().date(from: "2020-01-02T03:04:05Z")!
        for isExisting in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
            let clue = PlaceReviewCandidate(id: UUID(), captureId: UUID(), name: "Cafe", address: "1 Road", city: nil,
                latitude: nil, longitude: nil, evidence: [], confidence: nil, missingInfo: [], status: "review",
                createdAt: oldDate.addingTimeInterval(1000))
            let candidate = SaveMapCandidate(id: "exact-cafe", title: "Cafe", subtitle: "1 Road", latitude: 25, longitude: 121, category: .cafe)
            var existing = Place.from(clue)
            existing.latitude = 25
            existing.longitude = 121
            existing.note = "Latest user note"
            var savedID = existing.id
            var saveCount = 0
            var decisionFails = !isExisting
            AnalysisRequestURLProtocol.handler = { request in
                if decisionFails, request.httpMethod == "PATCH", request.url?.path.contains("/candidates/") == true {
                    return (503, "{\"error\":\"decision offline\"}")
                }
                if request.httpMethod == "GET", request.url?.path.hasSuffix("/places") == true {
                    return (200, "[{\"id\":\"\(savedID)\",\"user_id\":\"owner\",\"name\":\"Cafe\",\"address\":\"1 Road\",\"latitude\":25,\"longitude\":121,\"category\":\"cafe\",\"status\":\"wantToGo\",\"source_platform\":\"other\",\"note\":\"stale note\",\"created_at\":\"2020-01-02T03:04:05.000Z\"}]")
                }
                return (200, request.httpMethod == "GET" ? "[]" : "{}")
            }
            let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
            let map = MapViewModel(supabaseService: service,
                mapCandidatePlaceSaver: { place, _ in savedID = place.id; saveCount += 1 }, mapCandidateUserIDProvider: { "owner" },
                saveLocalVaultService: vault, correctionEventStore: SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("corrections.json")))
            if isExisting { map.places = [existing] }
            map.reviewCandidates = [clue]
            map.mapCandidates = [candidate]
            map.beginExactSearchResolution(for: clue)
            if !isExisting {
                do {
                    _ = try await map.saveMapCandidateAsPlace(candidate)
                    XCTFail("The failed decision must keep the clue pending")
                } catch {}
                XCTAssertTrue(map.reviewCandidates.contains { $0.id == clue.id })
                XCTAssertEqual(map.places.first?.id, savedID)
                decisionFails = false
            }
            let saved = try await map.saveMapCandidateAsPlace(candidate)
            XCTAssertEqual(saveCount, isExisting ? 0 : 1, "Retry must reuse the already inserted stamp")
            XCTAssertEqual(saved.createdAt, oldDate)
            XCTAssertEqual(map.places.first?.createdAt, oldDate)
            XCTAssertEqual(try vault.confirmedPlaces().first?.createdAt, oldDate)
            XCTAssertFalse(map.reviewCandidates.contains { $0.id == clue.id })
            if isExisting { XCTAssertTrue(saved.note?.contains("Latest user note") == true) }

            AnalysisRequestURLProtocol.handler = { _ in (503, "{\"error\":\"offline\"}") }
            let fallback = await map.refreshedConfirmedPlace(saved)
            XCTAssertEqual(fallback, saved, "A readback failure must not retry a committed save")
        }
    }

    @MainActor
    func testMemoryFetchPreservesServerDatesWithAndWithoutFractionalSeconds() async throws {
        let id = UUID()
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let base = ISO8601DateFormatter().date(from: "2020-01-02T03:04:05Z")!
        for (timestamp, fraction) in [("2020-01-02T03:04:05Z", 0.0), ("2020-01-02T03:04:05.123Z", 0.123), ("2020-01-02T03:04:05.123456+00:00", 0.123456)] {
            AnalysisRequestURLProtocol.handler = { request in
                if request.url?.path.hasSuffix("/candidates") == true {
                    return (200, "[{\"id\":\"\(id)\",\"name\":\"Clue\",\"status\":\"review\",\"created_at\":\"\(timestamp)\"}]")
                }
                return (200, "[{\"id\":\"\(id)\",\"user_id\":\"owner\",\"name\":\"Cafe\",\"address\":\"1 Road\",\"latitude\":25,\"longitude\":121,\"category\":\"food\",\"status\":\"wantToGo\",\"source_platform\":\"other\",\"created_at\":\"\(timestamp)\"}]")
            }
            let candidates = try await service.fetchReviewCandidates()
            let places = try await service.fetchPlaces(for: "owner")
            XCTAssertEqual(try XCTUnwrap(candidates.first).createdAt.timeIntervalSince(base), fraction, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(places.first).createdAt.timeIntervalSince(base), fraction, accuracy: 0.001)
        }
    }

    @MainActor
    func testFetchPlacesKeepsServerMappedOwnerRowsWhenPrivySubjectDiffersFromProfileId() async throws {
        let id = UUID()
        let privySubject = "did:privy:linked-subject"
        let resolvedProfileId = "11111111-2222-4333-8444-555555555555"
        AnalysisRequestURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/places")
            return (200, "[{\"id\":\"\(id)\",\"user_id\":\"\(resolvedProfileId)\",\"name\":\"Cedar Noodles 松山店\",\"address\":\"1 Road\",\"latitude\":25,\"longitude\":121,\"category\":\"food\",\"status\":\"wantToGo\",\"source_platform\":\"other\",\"created_at\":\"2020-01-02T03:04:05Z\"}]")
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let places = try await service.fetchPlaces(for: privySubject)
        XCTAssertEqual(places.map(\.id), [id], "Linked-account /places rows stay owned even when the Privy subject is not the profile id")
        XCTAssertEqual(places.first?.name, "Cedar Noodles 松山店")
    }

    @MainActor
    func testRetryUsesExistingCaptureAndHidesOnlySupersededClueAfterReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var stampID = UUID()
        var readbackFails = false
        let capture = UUID(), oldID = UUID(), newID = UUID(), secondID = UUID(), run = UUID(), firstRun = UUID(), secondRun = UUID()
        let oldJSON = "{\"id\":\"\(oldID)\",\"capture_id\":\"\(capture)\",\"workflow_run_id\":\"\(run)\",\"name\":\"Clue\",\"status\":\"source_only\",\"created_at\":\"2020-01-02T03:04:05Z\",\"superseded_by_candidate_id\":\"\(newID)\",\"superseded_by_candidate_ids\":[\"\(newID)\",\"\(secondID)\"]}"
        let newJSON = "{\"id\":\"\(newID)\",\"capture_id\":\"\(capture)\",\"workflow_run_id\":\"\(firstRun)\",\"name\":\"Cafe\",\"status\":\"review\",\"created_at\":\"2020-01-02T03:04:06Z\"}"
        let secondJSON = "{\"id\":\"\(secondID)\",\"capture_id\":\"\(capture)\",\"workflow_run_id\":\"\(secondRun)\",\"name\":\"Museum\",\"status\":\"review\",\"created_at\":\"2020-01-02T03:04:05Z\"}"
        AnalysisRequestURLProtocol.handler = { request in
            if request.url?.path == "/v0/analysis" {
                let id = try XCTUnwrap(AnalysisRequestURLProtocol.body(request)["id"] as? String)
                return (200, "{\"analysis_id\":\"\(id)\"}")
            }
            if request.url?.path.hasSuffix("/search-recovery") == true {
                XCTAssertTrue(request.url!.path.contains(capture.uuidString))
                let body = try AnalysisRequestURLProtocol.body(request)
                XCTAssertEqual(body["workflow_run_id"] as? String, run.uuidString)
                XCTAssertEqual(body["explicit_retry"] as? Bool, true)
                return (200, "{\"created_candidates\":[\(newJSON),\(secondJSON)]}")
            }
            if request.url?.path.hasSuffix("/candidates") == true { return (200, "[\(oldJSON),\(newJSON),\(secondJSON)]") }
            if request.url?.path.hasSuffix("/places") == true {
                if readbackFails { return (503, "{}") }
                return (200, "[{\"id\":\"\(stampID)\",\"user_id\":\"owner\",\"name\":\"Cafe\",\"address\":\"1 Road\",\"latitude\":25,\"longitude\":121,\"category\":\"cafe\",\"status\":\"wantToGo\",\"source_platform\":\"other\",\"note\":\"stale server note\",\"created_at\":\"2020-01-02T03:04:05Z\"}]")
            }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        let map = MapViewModel(supabaseService: service, saveLocalVaultService: vault)
        let old = PlaceReviewCandidate(id: oldID, captureId: capture, workflowRunId: run, name: "Clue", address: "",
            city: nil, latitude: nil, longitude: nil, evidence: [], confidence: nil, missingInfo: [],
            status: "source_only", createdAt: Date(timeIntervalSince1970: 1))
        let ids = try await map.reanalyzeReviewSource(old)
        XCTAssertEqual(ids, [newID, secondID])
        XCTAssertEqual(map.reviewCandidates.map(\.id), [newID, secondID])
        XCTAssertEqual(map.reviewCandidates.map(\.workflowRunId), [firstRun, secondRun])
        let pending = PendingReviewCandidate(candidateName: "Clue", address: "", category: "other",
            sourceURL: nil, sourceText: "source", evidence: [], confidence: 0, missingInfo: [], savedAt: Date(), isSourceOnly: true)
        var stampClue = old
        stampClue.latitude = 25
        stampClue.longitude = 121
        var stamp = Place.from(stampClue)
        stampID = stamp.id
        stamp.createdAt = Date()
        stamp.note = "Latest local note"
        map.places = [stamp]
        let reusedIDs = try await map.reuseImportedCandidate(pending, captureId: capture, userId: "owner")
        XCTAssertEqual(reusedIDs, [newID, secondID], "A repeated source returns every successor, not an arbitrary first venue")
        XCTAssertEqual(map.places.first?.createdAt, ISO8601DateFormatter().date(from: "2020-01-02T03:04:05Z"))
        XCTAssertEqual(map.places.first?.note, "Latest local note")
        XCTAssertEqual(try vault.confirmedPlaces().first?.createdAt, map.places.first?.createdAt)
        readbackFails = true
        let repeatedAfterReadbackFailure = try await map.reuseImportedCandidate(pending, captureId: capture, userId: "owner")
        XCTAssertEqual(repeatedAfterReadbackFailure, reusedIDs, "Date readback failure must not retry a committed import")
        XCTAssertTrue(AnalysisRequestURLProtocol.requests.allSatisfy {
            $0.httpMethod != "POST" || !$0.url!.path.hasSuffix("/captures")
        })
        try await map.refreshReviewCandidates()
        XCTAssertEqual(map.reviewCandidates.map(\.id), [newID, secondID])
    }

    func testPlaceMergeSendsEarliestKnownDateAndOmitsUnknownFallback() async throws {
        let early = ISO8601DateFormatter().date(from: "2020-01-02T03:04:05Z")!
        let clue = PlaceReviewCandidate(id: UUID(), captureId: nil, name: "Cafe", address: "1 Road",
            city: nil, latitude: 25, longitude: 121, evidence: [], confidence: nil, missingInfo: [], status: "review", createdAt: early)
        var existing = Place.from(clue)
        existing.createdAt = early.addingTimeInterval(1000)
        var incoming = Place.from(clue)
        incoming.note = "Earlier source evidence"
        let merged = existing.mergingSources(from: incoming)
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        var expectsDate = true
        AnalysisRequestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            let body = try AnalysisRequestURLProtocol.body(request)
            if expectsDate {
                XCTAssertEqual(body["created_at"] as? String, "2020-01-02T03:04:05Z")
                XCTAssertFalse((body["note"] as? String)?.contains("Earlier source evidence") == true)
                XCTAssertTrue(merged.savedAdditionalSourceEvidence.contains("Earlier source evidence"))
            } else { XCTAssertNil(body["created_at"]) }
            return (200, "{}")
        }
        try await service.updatePlace(merged)
        expectsDate = false
        var unknown = merged
        unknown.createdAt = .distantPast
        try await service.updatePlace(unknown)
    }

    func testUpdatePlaceSendsRecommenderAndSourceURLWhenPresent() async throws {
        var place = Place.mock
        place.sourceHandle = "la.harbor.eats"
        place.recommender = "la.harbor.eats"
        place.sourceUrl = "https://www.instagram.com/p/harborovenpizza/"
        place.sourcePlatform = .instagram
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        AnalysisRequestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            let body = try AnalysisRequestURLProtocol.body(request)
            XCTAssertEqual(body["recommender"] as? String, "la.harbor.eats")
            XCTAssertEqual(body["source_url"] as? String, "https://www.instagram.com/p/harborovenpizza/")
            XCTAssertEqual(body["source_platform"] as? String, "instagram")
            return (200, "{}")
        }
        try await service.updatePlace(place)
    }

    func testUpdatePlaceOmitsUnchangedOrInvalidRecommenderAndPersistsPlatform() async throws {
        var place = Place.mock
        place.sourceHandle = "la.harbor.eats"
        place.recommender = "la.harbor.eats"
        place.sourceUrl = "https://www.instagram.com/p/harborovenpizza/"
        place.sourcePlatform = .instagram
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })

        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            XCTAssertNil(body["recommender"])
            XCTAssertNil(body["extracted_dishes"])
            XCTAssertNil(body["source_platform"], "Unchanged source_platform must not be PATCHed")
            return (200, "{}")
        }
        try await service.updatePlace(place, previous: place)

        var coordinateHandle = place
        coordinateHandle.recommender = "33.7405"
        coordinateHandle.sourceHandle = "33.7405"
        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            XCTAssertTrue(body["recommender"] is NSNull, "Clearing a displayable handle must send JSON null even if the raw value is coordinate-shaped")
            XCTAssertNil(body["source_platform"], "Unchanged source_platform must not be PATCHed")
            return (200, "{}")
        }
        try await service.updatePlace(coordinateHandle, previous: place)

        var renamed = place
        renamed.recommender = "taipei.cafe.hop"
        renamed.sourceHandle = "taipei.cafe.hop"
        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            XCTAssertEqual(body["recommender"] as? String, "taipei.cafe.hop")
            XCTAssertNil(body["source_platform"], "Unchanged source_platform must not be PATCHed")
            return (200, "{}")
        }
        try await service.updatePlace(renamed, previous: place)

        var hoursOnly = Place.mock
        hoursOnly.openingHours = "Tue 9:00 AM - 5:00 PM"
        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            XCTAssertNil(body["recommender"], "A normal hours edit must not rewrite or clear attribution")
            XCTAssertEqual(body["opening_hours"] as? String, "Tue 9:00 AM - 5:00 PM")
            return (200, "{}")
        }
        try await service.updatePlace(hoursOnly, previous: Place.mock)
    }

    func testUpdatePlaceOmitsNilEnrichmentUnlessExplicitlyCleared() async throws {
        var local = Place.mock
        local.rating = nil
        local.googlePlaceId = nil
        local.googleRating = nil
        local.googlePriceLevel = nil
        local.priceRange = nil
        local.openingHours = nil
        local.sourceImageUrl = nil
        local.businessPhotoUrls = nil
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })

        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            XCTAssertNil(body["rating"], "Missing local enrichment must not PATCH JSON null")
            XCTAssertNil(body["google_place_id"])
            XCTAssertNil(body["google_rating"])
            XCTAssertNil(body["google_price_level"])
            XCTAssertNil(body["price_range"])
            XCTAssertNil(body["opening_hours"])
            XCTAssertNil(body["source_image_url"])
            XCTAssertNil(body["business_photo_urls"])
            return (200, "{}")
        }
        try await service.updatePlace(local)
        try await service.updatePlace(local, previous: local)

        var cleared = Place.mock
        cleared.googleRating = nil
        cleared.openingHours = nil
        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            XCTAssertTrue(body["google_rating"] is NSNull, "Clearing a known rating must send JSON null")
            XCTAssertTrue(body["opening_hours"] is NSNull)
            XCTAssertNil(body["google_place_id"], "Unchanged enrichment must stay omitted")
            return (200, "{}")
        }
        try await service.updatePlace(cleared, previous: Place.mock)
    }

    func testUpdatePlaceRollbackClearsMergedServerFieldsWithoutWritingEnvelope() async throws {
        var original = Place.mock
        original.note = "Must try the bun"
        original.sourceUrl = nil
        original.sourcePlatform = .other
        original.recommender = nil
        original.sourceHandle = nil
        original.recommendedItems = [RecommendedItem(name: "Cortado", price: "$6")]
        original.extractedDishes = ["Cortado"]

        var merged = original
        merged.sourceUrl = "https://www.instagram.com/p/harborovenpizza/"
        merged.sourcePlatform = .instagram
        merged.recommender = "la.harbor.eats"
        merged.sourceHandle = "la.harbor.eats"
        merged.additionalSourceEvidence = ["Original source note"]
        merged.placeHighlights = ["Window seats", "Single-origin pour-over"]
        merged.recommendedItems = [
            RecommendedItem(name: "Cortado", price: nil),
            RecommendedItem(name: "Egg tart", price: nil),
        ]
        merged.extractedDishes = ["Cortado", "Egg tart"]

        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        var mergedBody: [String: Any] = [:]
        AnalysisRequestURLProtocol.handler = { request in
            mergedBody = try AnalysisRequestURLProtocol.body(request)
            return (200, "{}")
        }
        try await service.updatePlace(merged, previous: original)
        XCTAssertEqual(mergedBody["note"] as? String, "Must try the bun")
        XCTAssertFalse((mergedBody["note"] as? String ?? "").hasPrefix("SavvyMemory/"))
        XCTAssertEqual(mergedBody["source_url"] as? String, "https://www.instagram.com/p/harborovenpizza/")
        XCTAssertEqual(mergedBody["source_platform"] as? String, "instagram")
        XCTAssertEqual(mergedBody["recommender"] as? String, "la.harbor.eats")
        XCTAssertEqual(mergedBody["extracted_dishes"] as? [String], ["Cortado", "Egg tart"])
        let mergedMeta = try decodeMemoryMeta(mergedBody["memory_meta"])
        XCTAssertEqual(mergedMeta.evidence, ["Original source note"])
        XCTAssertEqual(mergedMeta.highlights, ["Window seats", "Single-origin pour-over"])

        var rolledBackBody: [String: Any] = [:]
        AnalysisRequestURLProtocol.handler = { request in
            rolledBackBody = try AnalysisRequestURLProtocol.body(request)
            return (200, "{}")
        }
        try await service.updatePlace(original, previous: merged)
        XCTAssertEqual(rolledBackBody["note"] as? String, "Must try the bun")
        XCTAssertFalse((rolledBackBody["note"] as? String ?? "").hasPrefix("SavvyMemory/"))
        XCTAssertTrue(rolledBackBody["source_url"] is NSNull)
        XCTAssertEqual(rolledBackBody["source_platform"] as? String, "other")
        XCTAssertTrue(rolledBackBody["recommender"] is NSNull)
        XCTAssertEqual(rolledBackBody["extracted_dishes"] as? [String], ["Cortado"])

        var legacyOriginal = original
        legacyOriginal.recommender = "33.7405"
        legacyOriginal.sourceHandle = "33.7405"
        var legacyRollbackBody: [String: Any] = [:]
        AnalysisRequestURLProtocol.handler = { request in
            legacyRollbackBody = try AnalysisRequestURLProtocol.body(request)
            return (200, "{}")
        }
        try await service.updatePlace(legacyOriginal, previous: merged)
        XCTAssertTrue(
            legacyRollbackBody["recommender"] is NSNull,
            "Rollback must clear a clue handle even when the original raw recommender is coordinate-shaped"
        )
        XCTAssertFalse((rolledBackBody["note"] as? String ?? "").contains("Original source note"))
        let rolledBackMeta = try decodeMemoryMeta(rolledBackBody["memory_meta"])
        XCTAssertEqual(rolledBackMeta.recommended, [RecommendedItem(name: "Cortado", price: "$6")])
        XCTAssertNil(rolledBackMeta.evidence)
        XCTAssertNil(rolledBackMeta.highlights)

        var emptyOriginal = original
        emptyOriginal.recommendedItems = []
        emptyOriginal.extractedDishes = []
        var emptiedDishesBody: [String: Any] = [:]
        AnalysisRequestURLProtocol.handler = { request in
            emptiedDishesBody = try AnalysisRequestURLProtocol.body(request)
            return (200, "{}")
        }
        try await service.updatePlace(emptyOriginal, previous: merged)
        XCTAssertEqual(emptiedDishesBody["extracted_dishes"] as? [String], [])
    }

    func testUpdatePlaceClearsNoteWithJSONNull() async throws {
        var previous = Place.mock
        previous.note = "Must try the bun"
        var cleared = previous
        cleared.note = nil
        var patched: [String: Any] = [:]
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        AnalysisRequestURLProtocol.handler = { request in
            patched = try AnalysisRequestURLProtocol.body(request)
            return (200, "{}")
        }
        try await service.updatePlace(cleared, previous: previous)
        XCTAssertTrue(patched["note"] is NSNull, "A cleared user note must PATCH JSON null, not omit the key")

        AnalysisRequestURLProtocol.handler = { request in
            let payload: [String: Any] = [
                "id": cleared.id.uuidString,
                "user_id": "owner",
                "name": cleared.name,
                "address": cleared.address,
                "latitude": cleared.latitude,
                "longitude": cleared.longitude,
                "category": cleared.category.rawValue,
                "status": cleared.status.rawValue,
                "source_platform": cleared.sourcePlatform.rawValue,
                "note": NSNull(),
                "created_at": "2020-01-02T03:04:05Z",
            ]
            let data = try JSONSerialization.data(withJSONObject: [payload])
            return (200, String(data: data, encoding: .utf8) ?? "[]")
        }
        let places = try await service.fetchPlaces(for: "owner")
        let reloaded = try XCTUnwrap(places.first)
        XCTAssertNil(reloaded.userFacingNote)
        XCTAssertNil(reloaded.note)
    }

    func testUpdatePlacePersistsMergedStructuredFieldsAcrossRemoteReload() async throws {
        var previous = Place.mock
        previous.note = "Must try the bun"
        previous.placeHighlights = ["Window seats"]
        previous.recommendedItems = [RecommendedItem(name: "Cortado", price: "$6")]
        previous.vibeTags = ["quiet"]
        previous.accessNotes = ["Walk-up"]
        previous.extractedDishes = ["Cortado"]

        var merged = previous
        merged.additionalSourceEvidence = [
            "Original source note",
            "Source URL: https://www.xiaohongshu.com/explore/extra-clue",
        ]
        merged.placeHighlights = ["Window seats", "Single-origin pour-over"]
        merged.recommendedItems = [
            RecommendedItem(name: "Cortado", price: "$6"),
            RecommendedItem(name: "Egg tart", price: "NT$45"),
        ]
        merged.vibeTags = ["quiet", "sunny"]
        merged.accessNotes = ["Walk-up", "No reservations"]

        var patched: [String: Any] = [:]
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
        AnalysisRequestURLProtocol.handler = { request in
            patched = try AnalysisRequestURLProtocol.body(request)
            return (200, "{}")
        }
        try await service.updatePlace(merged, previous: previous)
        XCTAssertEqual(patched["extracted_dishes"] as? [String], ["Cortado", "Egg tart"])
        let note = try XCTUnwrap(patched["note"] as? String)
        XCTAssertEqual(note, "Must try the bun")
        XCTAssertFalse(note.hasPrefix("SavvyMemory/"))
        XCTAssertFalse(note.contains("Original source note"))
        XCTAssertFalse(note.contains("https://www.xiaohongshu.com/explore/extra-clue"))
        XCTAssertFalse(note.contains("Window seats"))
        XCTAssertFalse(note.contains("Single-origin pour-over"))
        XCTAssertFalse(note.contains("sunny"))
        XCTAssertFalse(note.contains("No reservations"))
        XCTAssertNil(patched["place_highlights"])
        XCTAssertNil(patched["vibe_tags"])
        XCTAssertNil(patched["access_notes"])
        XCTAssertNil(patched["recommended_items"])
        XCTAssertNil(patched["additional_source_evidence"])
        let meta = try decodeMemoryMeta(patched["memory_meta"])
        XCTAssertEqual(meta.v, 1)
        XCTAssertEqual(meta.evidence, [
            "Original source note",
            "Source URL: https://www.xiaohongshu.com/explore/extra-clue",
        ])
        XCTAssertEqual(meta.highlights, ["Window seats", "Single-origin pour-over"])
        XCTAssertEqual(meta.vibe, ["quiet", "sunny"])
        XCTAssertEqual(meta.access, ["Walk-up", "No reservations"])
        XCTAssertEqual(meta.recommended, [
            RecommendedItem(name: "Cortado", price: "$6"),
            RecommendedItem(name: "Egg tart", price: "NT$45"),
        ])

        var enriched = merged
        enriched.businessPhotoUrls = ["https://photos.example/1.jpg"]
        var enrichmentBody: [String: Any] = [:]
        AnalysisRequestURLProtocol.handler = { request in
            enrichmentBody = try AnalysisRequestURLProtocol.body(request)
            return (200, "{}")
        }
        try await service.updatePlace(enriched, previous: merged)
        XCTAssertNil(enrichmentBody["extracted_dishes"], "Photo enrichment must not rewrite dishes")
        XCTAssertNil(enrichmentBody["note"], "Photo enrichment must not rewrite the user note")
        XCTAssertNil(enrichmentBody["memory_meta"], "Photo enrichment must not rewrite stamp memory")
        XCTAssertEqual(enrichmentBody["business_photo_urls"] as? [String], ["https://photos.example/1.jpg"])

        var emptied = merged
        emptied.placeHighlights = []
        emptied.recommendedItems = []
        emptied.vibeTags = []
        emptied.accessNotes = []
        emptied.extractedDishes = []
        emptied.additionalSourceEvidence = []
        var emptiedBody: [String: Any] = [:]
        AnalysisRequestURLProtocol.handler = { request in
            emptiedBody = try AnalysisRequestURLProtocol.body(request)
            return (200, "{}")
        }
        try await service.updatePlace(emptied, previous: merged)
        XCTAssertEqual(emptiedBody["extracted_dishes"] as? [String], [])
        XCTAssertEqual(emptiedBody["note"] as? String, "Must try the bun")
        XCTAssertFalse((emptiedBody["note"] as? String ?? "").hasPrefix("SavvyMemory/"))
        let emptiedMeta = try decodeMemoryMeta(emptiedBody["memory_meta"])
        XCTAssertEqual(emptiedMeta, PlaceMemoryMeta.cleared, "Empty structured memory must send a tombstone object, not omit the column")

        AnalysisRequestURLProtocol.handler = { request in
            let payload: [String: Any] = [
                "id": merged.id.uuidString,
                "user_id": "owner",
                "name": merged.name,
                "address": merged.address,
                "latitude": merged.latitude,
                "longitude": merged.longitude,
                "category": merged.category.rawValue,
                "status": merged.status.rawValue,
                "source_platform": merged.sourcePlatform.rawValue,
                "note": patched["note"] as? String ?? "",
                "extracted_dishes": patched["extracted_dishes"] as? [String] ?? [],
                "memory_meta": patched["memory_meta"] as Any,
                "created_at": "2020-01-02T03:04:05Z",
            ]
            let data = try JSONSerialization.data(withJSONObject: [payload])
            return (200, String(data: data, encoding: .utf8) ?? "[]")
        }
        let reloadedPlaces = try await service.fetchPlaces(for: "owner")
        let reloaded = try XCTUnwrap(reloadedPlaces.first)
        XCTAssertEqual(reloaded.note, "Must try the bun")
        XCTAssertEqual(ShareRoutePayloadSanitizer.publicNote(reloaded.note), "Must try the bun")
        XCTAssertEqual(reloaded.placeHighlights, ["Window seats", "Single-origin pour-over"])
        XCTAssertEqual(reloaded.recommendedItems, [
            RecommendedItem(name: "Cortado", price: "$6"),
            RecommendedItem(name: "Egg tart", price: "NT$45"),
        ])
        XCTAssertEqual(reloaded.vibeTags, ["quiet", "sunny"])
        XCTAssertEqual(reloaded.accessNotes, ["Walk-up", "No reservations"])
        XCTAssertTrue(reloaded.sourceEvidence.contains("Must try the bun"))
        XCTAssertTrue(reloaded.sourceEvidence.contains("Original source note"))
        XCTAssertTrue(reloaded.sourceEvidence.contains("Source URL: https://www.xiaohongshu.com/explore/extra-clue"))
        XCTAssertFalse((reloaded.note ?? "").contains("Highlight:"))
        XCTAssertFalse((reloaded.note ?? "").contains("Vibe:"))
        XCTAssertFalse((reloaded.note ?? "").contains("Evidence:"))
        XCTAssertFalse((reloaded.note ?? "").hasPrefix("SavvyMemory/"))
    }

    func testDecodedWireNotePreservesUntaggedUserNotes() throws {
        for raw in [
            "Highlight: the bun was amazing",
            "Vibe: casual counter seats",
            "Evidence: keep this as my memory",
            "Creator handle: @me.and.the.bun",
        ] {
            let decoded = Place.decodedWireNote(raw)
            XCTAssertEqual(decoded.note, raw)
            XCTAssertTrue(decoded.additional.isEmpty)
            XCTAssertTrue(decoded.highlights.placeHighlights.isEmpty)
            XCTAssertTrue(decoded.highlights.vibeTags.isEmpty)
            XCTAssertTrue(decoded.highlights.accessNotes.isEmpty)
            XCTAssertTrue(decoded.highlights.recommendedItems.isEmpty)
        }

        var place = Place.mock
        place.note = "Highlight: the bun was amazing"
        place.additionalSourceEvidence = ["Original source note"]
        place.placeHighlights = ["Window seats"]
        let wire = try XCTUnwrap(place.wireNoteForPersistence())
        XCTAssertEqual(wire, "Highlight: the bun was amazing")
        XCTAssertFalse(wire.hasPrefix("SavvyMemory/"))
        let decoded = Place.decodedWireNote(wire)
        XCTAssertEqual(decoded.note, "Highlight: the bun was amazing")
        XCTAssertTrue(decoded.additional.isEmpty)
        XCTAssertTrue(decoded.highlights.placeHighlights.isEmpty)
        XCTAssertEqual(ShareRoutePayloadSanitizer.publicNote(wire), "Highlight: the bun was amazing")

        let leftoverEnvelope = """
        SavvyMemory/1
        {"v":1,"note":"Must try the bun","evidence":["Original source note"]}
        """
        let fromEnvelope = Place.decodedWireNote(leftoverEnvelope)
        XCTAssertEqual(fromEnvelope.note, "Must try the bun")
        XCTAssertEqual(fromEnvelope.additional, ["Original source note"])
        XCTAssertNil(ShareRoutePayloadSanitizer.publicNote(leftoverEnvelope))

        let multiline = Place.decodedWireNote("""
        Must try the bun
        Evidence: keep this as my memory
        Highlight: the seating was great
        Vibe: loud in a good way
        Access: walk up
        """)
        XCTAssertEqual(
            multiline.note,
            """
            Must try the bun
            Evidence: keep this as my memory
            Highlight: the seating was great
            Vibe: loud in a good way
            Access: walk up
            """
        )
        XCTAssertTrue(multiline.additional.isEmpty)
        XCTAssertTrue(multiline.highlights.placeHighlights.isEmpty)
        XCTAssertTrue(multiline.highlights.vibeTags.isEmpty)
        XCTAssertTrue(multiline.highlights.accessNotes.isEmpty)
    }

    func testEmptyRetryDistinguishesExistingSuccessorsFromUnresolvedSource() async throws {
        for status in ["saved", "confirmed", "rejected", "review", "missing", "unresolved"] {
            let capture = UUID(), source = UUID(), successor = UUID()
            let marker = status == "unresolved" ? "" : ",\"superseded_by_candidate_ids\":[\"\(successor)\"]"
            let sourceJSON = "{\"id\":\"\(source)\",\"capture_id\":\"\(capture)\",\"name\":\"Saved source\",\"status\":\"source_only\",\"created_at\":\"2020-01-01T00:00:00Z\"\(marker)}"
            let successorJSON = ["unresolved", "missing"].contains(status) ? "" : ",{\"id\":\"\(successor)\",\"capture_id\":\"\(capture)\",\"name\":\"Cafe\",\"status\":\"\(status)\",\"created_at\":\"2020-01-01T00:00:00Z\"}"
            AnalysisRequestURLProtocol.handler = { request in
                if request.url?.path == "/v0/analysis" {
                    let id = try XCTUnwrap(AnalysisRequestURLProtocol.body(request)["id"] as? String)
                    return (200, "{\"analysis_id\":\"\(id)\"}")
                }
                if request.url?.path.hasSuffix("/search-recovery") == true { return (200, "{\"created_candidates\":[]}") }
                if request.url?.path.hasSuffix("/candidates") == true { return (200, "[\(sourceJSON)\(successorJSON)]") }
                if request.httpMethod == "GET" { return (200, "[]") }
                return (200, "{}")
            }
            let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "test-token" })
            let map = MapViewModel(supabaseService: service, usesRemotePersistence: true)
            let clue = PlaceReviewCandidate(id: source, captureId: capture, name: "Saved source", address: "",
                city: nil, latitude: nil, longitude: nil, evidence: [], confidence: nil, missingInfo: [], status: "source_only", createdAt: Date())
            do {
                let ids = try await map.reanalyzeReviewSource(clue)
                XCTAssertFalse(["saved", "confirmed", "rejected"].contains(status), "Terminal successors must acknowledge already reviewed")
                XCTAssertEqual(ids, status == "review" ? [successor] : [])
                if status == "unresolved" { XCTAssertTrue(map.reviewCandidates.contains { $0.id == source }) }
            } catch ReviewCandidateError.sourceAlreadyReviewed {
                XCTAssertTrue(["saved", "confirmed", "rejected"].contains(status))
            }
        }
    }

    override func tearDown() {
        AnalysisRequestURLProtocol.reset()
        super.tearDown()
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AnalysisRequestURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func decodeMemoryMeta(_ value: Any?) throws -> PlaceMemoryMeta {
        let object = try XCTUnwrap(value)
        XCTAssertFalse(object is NSNull)
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(PlaceMemoryMeta.self, from: data)
    }

    private func gemini(session: URLSession) -> SAVEGeminiTransport {
        SAVEGeminiTransport(modelFallbacks: ["first", "second"], session: session,
            accessTokenProvider: { "synthetic-token" }, directAPIKey: "must-not-be-used",
            apiBaseURL: "https://analysis.test", maxAttemptsPerModel: 2,
            transientRetryDelayNanoseconds: 0)
    }

    func testConcurrentGeminiSessionsCorrelateEveryFallbackWithoutLeakingScope() async throws {
        AnalysisRequestURLProtocol.handler = { request in
            let body = try AnalysisRequestURLProtocol.body(request)
            if body["model"] as? String == "first" {
                return (400, #"{"error":"Unsupported Gemini model"}"#)
            }
            return (200, #"{"ok":true}"#)
        }
        let runner = gemini(session: session())
        let first = SAVEAnalysisContext(id: UUID())
        let second = SAVEAnalysisContext(id: UUID())
        let a = Task { @MainActor in
            try await SAVEAnalysisScope.$current.withValue(first) { _ = try await runner.generateContent(body: [:]) }
        }
        let b = Task { @MainActor in
            try await SAVEAnalysisScope.$current.withValue(second) { _ = try await runner.generateContent(body: [:]) }
        }
        let results = await (a.result, b.result)
        try results.0.get()
        try results.1.get()
        XCTAssertNil(SAVEAnalysisScope.current)
        let requests = AnalysisRequestURLProtocol.requests
        XCTAssertEqual(requests.count, 4)
        for context in [first, second] {
            XCTAssertEqual(requests.filter { $0.value(forHTTPHeaderField: "x-save-analysis-id") == context.id.uuidString }.count, 2)
        }
        XCTAssertTrue(requests.allSatisfy { $0.url?.host == "analysis.test" })
    }

    func testAnalysisDenialDoesNotRetryModelOrUseDirectProvider() async {
        for code in ["analysis_limit_exceeded", "analysis_controls_unavailable", "analysis_closed", "analysis_not_found"] {
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { _ in (429, "{\"code\":\"\(code)\"}") }
            let context = SAVEAnalysisContext(id: UUID())
            do {
                _ = try await SAVEAnalysisScope.$current.withValue(context) {
                    try await gemini(session: session()).generateContent(body: [:])
                }
                XCTFail("Expected a terminal analysis denial")
            } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 1)
            XCTAssertEqual(AnalysisRequestURLProtocol.requests.first?.url?.host, "analysis.test")
        }
    }

    func testMissingAnalysisProxyNeverUsesConfiguredDirectGeminiKey() async {
        var runner = gemini(session: session())
        runner.apiBaseURL = nil
        do {
            _ = try await SAVEAnalysisScope.$current.withValue(SAVEAnalysisContext(id: UUID())) {
                try await runner.generateContent(body: [:])
            }
            XCTFail("Expected unavailable analysis")
        } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(AnalysisRequestURLProtocol.requests.isEmpty)
    }

    func testGoogleUsesServerWithoutClientKeyAndKeepsOrdinarySearchRoute() async throws {
        let result = #"{"status":"OK","results":[{"place_id":"fixture","name":"Fixture","geometry":{"location":{"lat":25.03,"lng":121.56}}}]}"#
        AnalysisRequestURLProtocol.handler = { _ in (200, result) }
        let places = GooglePlacesService(apiKey: "REPLACE_ME", session: session(), apiBaseURL: "https://analysis.test",
            accessTokenProvider: { "synthetic-token" })
        let context = SAVEAnalysisContext(id: UUID())
        let matches = try await SAVEAnalysisScope.$current.withValue(context) {
            try await places.searchPlace(query: "Fixture", near: nil)
        }
        XCTAssertEqual(matches.first?.id, "fixture")
        let request = try XCTUnwrap(AnalysisRequestURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/v0/analysis/\(context.id.uuidString)/places")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-save-analysis-id"), context.id.uuidString)
        XCTAssertNil(request.url?.query)
        let ordinary = GooglePlacesService(apiKey: "synthetic-key", session: session(), apiBaseURL: "https://analysis.test",
            accessTokenProvider: { XCTFail("Ordinary search must keep its route"); return "unused" })
        _ = try await ordinary.searchPlace(query: "Fixture", near: nil)
        let unscoped = try XCTUnwrap(AnalysisRequestURLProtocol.requests.last)
        XCTAssertEqual(unscoped.url?.host, "maps.googleapis.com")
        XCTAssertNil(unscoped.value(forHTTPHeaderField: "x-save-analysis-id"))
    }

    func testGoogleDenialNeverFallsBackToClientKeyOrMakesLaterAnalysisCall() async {
        AnalysisRequestURLProtocol.handler = { _ in (429, #"{"code":"analysis_limit_exceeded"}"#) }
        let places = GooglePlacesService(apiKey: "must-not-be-used", session: session(), apiBaseURL: "https://analysis.test",
            accessTokenProvider: { "synthetic-token" })
        let context = SAVEAnalysisContext(id: UUID())
        for _ in 0..<2 {
            do {
                _ = try await SAVEAnalysisScope.$current.withValue(context) {
                    try await places.searchPlace(query: "Fixture", near: nil)
                }
                XCTFail("Expected denial")
            } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 1)
        XCTAssertEqual(AnalysisRequestURLProtocol.requests.first?.url?.host, "analysis.test")
    }

    func testActualSessionStartAndCancelledFinishSendRedactedCorrelatedEvents() async throws {
        let id = UUID()
        let captureID = UUID()
        AnalysisRequestURLProtocol.handler = { request in
            if request.url?.path == "/v0/analysis" {
                let body = try AnalysisRequestURLProtocol.body(request)
                return (200, "{\"analysis_id\":\"\(body["id"] as! String)\"}")
            }
            return (200, "{}")
        }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "synthetic-token" })
        let started = try await service.startAnalysis(id: id)
        XCTAssertEqual(started, id)
        let context = SAVEAnalysisContext(id: id)
        await context.addCapture(captureID)
        await SAVEAnalysisScope.$current.withValue(context) {
            _ = try? await SAVEAnalysisScope.measure(.publicSearch) {
                throw NSError(domain: "private caption or token must not enter telemetry", code: 1)
            }
            await SAVEAnalysisScope.measure(.localOCR) { () }
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await service.finishAnalysis(context, outcome: "cancelled")
        }
        await task.value
        let requests = AnalysisRequestURLProtocol.requests
        XCTAssertEqual(requests.count, 3)
        let eventsRequest = try XCTUnwrap(requests.first { $0.url?.path.hasSuffix("/client-events") == true })
        XCTAssertTrue(eventsRequest.url!.path.contains(id.uuidString))
        let events = try XCTUnwrap(try AnalysisRequestURLProtocol.body(eventsRequest)["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?["outcome"] as? String, "failure")
        for event in events { XCTAssertEqual(Set(event.keys), ["event_id", "operation", "outcome", "duration_ms"]) }
        let finish = try AnalysisRequestURLProtocol.body(try XCTUnwrap(requests.last))
        XCTAssertEqual(finish["outcome"] as? String, "cancelled")
        XCTAssertEqual(finish["capture_ids"] as? [String], [captureID.uuidString])
    }

    func testChinaControlDenialStopsGoogleAndLaterResolverAttempts() async {
        for code in ["analysis_limit_exceeded", "analysis_controls_unavailable", "analysis_closed", "analysis_not_found"] {
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { _ in (429, "{\"code\":\"\(code)\"}") }
            let google = AnalysisGoogleSpy()
            let apple = AnalysisAppleSpy()
            let china = BackendPlaceResolverService(apiBaseURL: "https://analysis.test", session: session(),
                accessTokenProvider: { "synthetic-token" })
            let resolver = PlaceResolverService(googlePlacesService: google,
                appleMapsPlaceSearchService: apple, backendPlaceResolverService: china)
            await SAVEAnalysisScope.$current.withValue(SAVEAnalysisContext(id: UUID())) {
                for _ in 0..<2 {
                    do {
                        _ = try await resolver.searchPlace(query: "台北咖啡", near: nil)
                        XCTFail("Expected terminal analysis denial")
                    } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
                }
            }
            XCTAssertEqual(google.searchCount, 0)
            XCTAssertEqual(apple.searchCount, 1)
            XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 1)
            XCTAssertEqual(AnalysisRequestURLProtocol.requests.first?.url?.path, "/place-resolve")
        }
    }

    func testRecoveryControlDenialStopsLaterRecoveryGoogleAndGeminiRequests() async {
        AnalysisRequestURLProtocol.handler = { _ in (503, #"{"code":"analysis_controls_unavailable"}"#) }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "synthetic-token" })
        let google = GooglePlacesService(apiKey: "must-not-be-used", session: session(), apiBaseURL: "https://analysis.test",
            accessTokenProvider: { "synthetic-token" })
        let runner = gemini(session: session())
        await SAVEAnalysisScope.$current.withValue(SAVEAnalysisContext(id: UUID())) {
            for _ in 0..<2 {
                do {
                    _ = try await service.recoverSourceOnlyReviewCandidates(captureId: UUID())
                    XCTFail("Expected recovery denial")
                } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
            }
            do {
                _ = try await google.searchPlace(query: "Fixture", near: nil)
                XCTFail("Expected Google to stop before sending")
            } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
            do {
                _ = try await runner.generateContent(body: [:])
                XCTFail("Expected Gemini to stop before sending")
            } catch SAVEAnalysisError.denied {} catch { XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 1)
        XCTAssertTrue(AnalysisRequestURLProtocol.requests.first?.url?.path.hasSuffix("/search-recovery") == true)
    }

    func testEmptyClientEventsStillSendsReceiptBeforeFinish() async throws {
        AnalysisRequestURLProtocol.handler = { _ in (200, "{}") }
        let service = SupabaseService(apiBaseURL: "https://analysis.test", session: session(), accessTokenProvider: { "synthetic-token" })
        await service.finishAnalysis(SAVEAnalysisContext(id: UUID()), outcome: "source_only")
        let requests = AnalysisRequestURLProtocol.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.first?.url?.path.hasSuffix("/client-events") == true)
        let body = try AnalysisRequestURLProtocol.body(try XCTUnwrap(requests.first))
        XCTAssertEqual((body["events"] as? [Any])?.count, 0)
        XCTAssertEqual(body["events_truncated"] as? Bool, false)
        XCTAssertTrue(requests.last?.url?.path.hasSuffix("/finish") == true)
    }

    func testClientEventBufferReportsOverflowAndKeepsCountsPerSession() async {
        let context = SAVEAnalysisContext(id: UUID())
        for _ in 0..<65 {
            await context.record(.metadata, outcome: .success, started: ProcessInfo.processInfo.systemUptime)
        }
        let snapshot = await context.snapshot()
        XCTAssertEqual(snapshot.events.count, 64)
        XCTAssertTrue(snapshot.eventsTruncated)
        let independent = await SAVEAnalysisContext(id: UUID()).snapshot()
        XCTAssertTrue(independent.events.isEmpty)
        XCTAssertFalse(independent.eventsTruncated)
    }

    func testFailureReceiptUsesActionableCopyWithoutProviderDiagnostics() throws {
        for reason in ["login_required", "expired", "caption_missing", "unresolved_source", "no_place_evidence"] {
            let data = Data("{\"created_candidates\":[],\"receipt\":{\"failureReason\":{\"kind\":\"insufficient_source\",\"reason\":\"\(reason)\"}}}".utf8)
            let recovered = try SupabaseService.decodeSourceSearchRecoveryResponse(data)
            let failure = try XCTUnwrap(recovered.failureReason)
            XCTAssertEqual(failure.kind, .insufficientSource)
            XCTAssertTrue(failure.englishMessage.contains("caption"))
            XCTAssertTrue(failure.englishMessage.contains("screenshot"))
        }
        let data = Data(#"{"created_candidates":[],"receipt":{"failureReason":{"kind":"provider_failure","stage":"public_search"}}}"#.utf8)
        let failure = try XCTUnwrap(try SupabaseService.decodeSourceSearchRecoveryResponse(data).failureReason)
        XCTAssertTrue(failure.englishMessage.contains("try again"))
        XCTAssertFalse(failure.englishMessage.contains("public_search"))
        XCTAssertNil(try SupabaseService.decodeSourceSearchRecoveryResponse(Data(#"{"created_candidates":[]}"#.utf8)).failureReason)
    }
}

@MainActor
private final class AnalysisGoogleSpy: GooglePlacesServiceProtocol {
    var searchCount = 0
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        searchCount += 1
        return []
    }
    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails { throw GooglePlacesError.noResults }
    func photoURL(reference: String, maxWidth: Int) -> URL? { nil }
}

@MainActor
private final class AnalysisAppleSpy: AppleMapsPlaceSearchServiceProtocol {
    var searchCount = 0
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
        searchCount += 1
        return []
    }
}

private final class AnalysisRequestURLProtocol: URLProtocol {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var requests: [URLRequest] = []
        var handler: ((URLRequest) throws -> (Int, String))?
    }
    private static let state = State()
    static var requests: [URLRequest] { state.lock.withLock { state.requests } }
    static var handler: ((URLRequest) throws -> (Int, String))? {
        get { state.lock.withLock { state.handler } }
        set { state.lock.withLock { state.handler = newValue } }
    }
    static func reset() { state.lock.withLock { state.requests = []; state.handler = nil } }
    static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            // Materialize URLSession's stream once so assertions can inspect it after completion.
            var recorded = request
            if recorded.httpBody == nil, request.httpBodyStream != nil {
                recorded.httpBody = try JSONSerialization.data(withJSONObject: Self.body(request))
            }
            let handler = Self.state.lock.withLock { Self.state.requests.append(recorded); return Self.state.handler }
            guard let handler else { throw URLError(.badServerResponse) }
            let (status, body) = try handler(recorded)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class ShareInlineAnalysisTests: XCTestCase {
    private func credential(owner: String = "did:privy:owner") -> ShareAnalysisCredential {
        ShareAnalysisCredential(token: "analysis-only-test-token", ownerSubject: owner,
            expiresAt: Date().addingTimeInterval(3600), apiBaseURL: "https://api.example.test")
    }

    private func client(status: Int = 200, body: String) -> ShareAnalysisClient {
        TransportFailureURLProtocol.responses = [(status, body)]
        TransportFailureURLProtocol.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportFailureURLProtocol.self]
        return ShareAnalysisClient(session: URLSession(configuration: configuration))
    }

    func testReportedInstagramCaptionCanReturnVerifiedPlaceWithoutMainAppHandoff() async throws {
        let body = #"{"owner_subject":"did:privy:owner","semanticStatus":"ready","candidates":[{"name":"smith+hsu 中山旗艦店","address":"台北市中山區中山北路二段50巷31號","latitude":25.057,"longitude":121.52,"placeId":"fixture-place-id","types":["cafe"],"evidence":["Source name and address","Google Places match"],"confidence":0.95,"missingInfo":[]}]}"#
        let result = try await client(body: body).analyze(sourceURL: "https://www.instagram.com/p/DdfnwpUDgBj/",
            caption: "地點：smith+hsu 中山旗艦店\n台北市中山區中山北路二段50巷31號", credential: credential())
        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertTrue(candidate.isVerified)
        XCTAssertEqual(candidate.category, "cafe")
        XCTAssertEqual(candidate.name, "smith+hsu 中山旗艦店")
        XCTAssertEqual(TransportFailureURLProtocol.requestCount, 1)
    }

    func testCaptionOnlyCandidateNeverBecomesConfirmedPlaceWithoutProviderIdentity() throws {
        var candidate = ShareAnalysisCandidate(name: "smith+hsu", address: "台北市中山區中山北路二段50巷31號",
            latitude: 25.057, longitude: 121.52, evidence: [], confidence: 1, missingInfo: [])
        XCTAssertFalse(candidate.isVerified)
        candidate.placeId = "fixture-id"
        candidate.latitude = .nan
        XCTAssertFalse(candidate.isVerified)
        candidate.latitude = 91
        XCTAssertFalse(candidate.isVerified)
        candidate.latitude = 25
        candidate.address = ""
        XCTAssertFalse(candidate.isVerified)
    }

    func testExpiredCredentialNeverMakesNetworkRequest() async {
        var expired = credential()
        expired.expiresAt = .distantPast
        let client = client(body: "{}")
        do {
            _ = try await client.analyze(sourceURL: "https://www.instagram.com/p/DdfnwpUDgBj/", caption: "", credential: expired)
            XCTFail("Expired session must not analyze")
        } catch {}
        XCTAssertEqual(TransportFailureURLProtocol.requestCount, 0)
    }

    func testOtherOwnerResponseIsRejected() async {
        do {
            _ = try await client(body: #"{"owner_subject":"did:privy:other","candidates":[]}"#)
                .analyze(sourceURL: "https://www.instagram.com/p/DdfnwpUDgBj/", caption: "", credential: credential())
            XCTFail("Account mismatch must not be accepted")
        } catch ShareAnalysisError.sessionChanged {} catch { XCTFail("Unexpected error \(error)") }
    }

    func testRevokedCredentialSurfacesSignInInsteadOfMissingAddress() async {
        do {
            _ = try await client(status: 401, body: "{}").analyze(
                sourceURL: "https://www.instagram.com/p/DdfnwpUDgBj/", caption: "", credential: credential())
            XCTFail("Revoked session must fail")
        } catch ShareAnalysisError.sessionUnavailable {} catch { XCTFail("Unexpected error \(error)") }
    }

    func testIssueRejectsAccountMismatchAndParsesFractionalExpiry() async throws {
        let issued = try await client(body: #"{"token":"scoped-token","owner_subject":"did:privy:owner","expires_at":"2099-01-01T00:00:00.000Z"}"#)
            .issue(bearer: "test-bearer", ownerSubject: "did:privy:owner", installationID: UUID().uuidString, apiBaseURL: "https://api.example.test")
        XCTAssertTrue(issued.isUsable())
        do {
            _ = try await client(body: #"{"token":"scoped-token","owner_subject":"did:privy:other","expires_at":"2099-01-01T00:00:00Z"}"#)
                .issue(bearer: "test-bearer", ownerSubject: "did:privy:owner", installationID: UUID().uuidString, apiBaseURL: "https://api.example.test")
            XCTFail("Other owner's token must not be stored")
        } catch ShareAnalysisError.sessionChanged {} catch { XCTFail("Unexpected error \(error)") }
    }

    func testConfirmedShareStaysQueuedUntilItsOwnerReturns() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = PendingPlaceImportService(overrideContainerURL: directory)
        let place = PendingSharedPlace(ownerSubject: "did:privy:owner", googlePlaceId: "verified-provider-id",
            name: "smith+hsu", address: "台北市中山區中山北路二段50巷31號", category: "cafe",
            latitude: 25.057, longitude: 121.52, dishes: [], savedAt: Date())
        service.restorePendingPlaces([place])
        XCTAssertTrue(service.consumePendingPlaces().isEmpty, "Signed-out local import cannot display owned places")
        XCTAssertTrue(service.consumePendingPlaces(ownerSubject: "did:privy:other").isEmpty)
        let returned = service.consumePendingPlaces(ownerSubject: "did:privy:owner")
        XCTAssertEqual(returned.count, 1)
        XCTAssertEqual(Place.from(try XCTUnwrap(returned.first)).googlePlaceId, "verified-provider-id")
        XCTAssertTrue(service.consumePendingPlaces(ownerSubject: "did:privy:owner").isEmpty)
    }

    func testRetryReusesAnalysisIdentifierAfterLostResponse() async throws {
        AnalysisRequestURLProtocol.reset()
        let id = UUID()
        var first = true
        AnalysisRequestURLProtocol.handler = { request in
            XCTAssertEqual(try AnalysisRequestURLProtocol.body(request)["analysis_id"] as? String, id.uuidString)
            if first { first = false; throw URLError(.networkConnectionLost) }
            return (200, #"{"owner_subject":"did:privy:owner","candidates":[]}"#)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let client = ShareAnalysisClient(session: URLSession(configuration: configuration))
        do {
            _ = try await client.analyze(sourceURL: "https://www.instagram.com/p/DdfnwpUDgBj/", caption: "",
                credential: credential(), analysisID: id)
            XCTFail("Transport fixture should fail once")
        } catch {}
        _ = try await client.analyze(sourceURL: "https://www.instagram.com/p/DdfnwpUDgBj/", caption: "",
            credential: credential(), analysisID: id)
        XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 2)
    }

    func testPendingImportCannotSendWithAnotherAccountsToken() async throws {
        let auth = PrivyAuthService.shared
        let original = auth.authState
        defer { auth.authState = original }
        let owner = "did:privy:import-owner"
        let place = Place.from(PendingSharedPlace(ownerSubject: owner, googlePlaceId: "fixture-id",
            name: "smith+hsu", address: "Taipei", category: "cafe", latitude: 25, longitude: 121,
            dishes: [], savedAt: Date()))
        for shouldSwitch in [false, true] {
            auth.authState = .authenticated(userId: owner)
            let generation = auth.sessionGeneration
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { _ in (200, "{}") }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
            let service = SupabaseService(apiBaseURL: "https://analysis.test",
                session: URLSession(configuration: configuration), accessTokenProvider: {
                    await MainActor.run {
                        if shouldSwitch { auth.authState = .authenticated(userId: "did:privy:other") }
                    }
                    return shouldSwitch ? "other-token" : "owner-token"
                })
            do {
                try await SAVEPendingImportSessionScope.$current.withValue((generation, owner)) {
                    try await service.savePlace(place, userId: owner)
                    try await service.updatePlace(place)
                }
                XCTAssertFalse(shouldSwitch, "A switched account must cancel the import")
            } catch is CancellationError {
                XCTAssertTrue(shouldSwitch)
            }
            XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, shouldSwitch ? 0 : 2)
        }
    }

    func testReviewSourceIsAlsoBoundToOriginatingAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = PendingPlaceImportService(overrideContainerURL: directory)
        service.restorePendingReviewCandidates([PendingReviewCandidate(ownerSubject: "owner", candidateName: "Source clue",
            address: "", category: "other", sourceURL: "https://www.instagram.com/p/DdfnwpUDgBj/", sourceText: nil, evidence: [],
            confidence: 0, missingInfo: ["Analysis pending"], savedAt: Date(), isSourceOnly: true, reviewState: "analysis_pending")])
        XCTAssertTrue(service.consumePendingReviewCandidates(ownerSubject: "other").isEmpty)
        XCTAssertEqual(service.consumePendingReviewCandidates(ownerSubject: "owner").count, 1)
    }
}

@MainActor
final class ShareAnalysisFailureTests: XCTestCase {
    func testRecoveryActionsDoNotInviteUnproductiveRetries() {
        for error in [ShareAnalysisError.sourceUnavailable(reason: "login_required"), .noPlaceEvidence,
                      .usageLimit, .sessionUnavailable, .sessionChanged] {
            XCTAssertFalse(error.offersImmediateRetry)
        }
        for error in [ShareAnalysisError.timedOut, .networkUnavailable, .analysisInProgress,
                      .serviceUnavailable, .analysisFailed] {
            XCTAssertTrue(error.offersImmediateRetry)
        }
    }

    private func analyze(_ fixture: String) async throws -> ShareAnalysisResponse {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ShareFailureURLProtocol.self]
        let client = ShareAnalysisClient(session: URLSession(configuration: config))
        let credential = ShareAnalysisCredential(token: "fixture", ownerSubject: "fixture-owner",
            expiresAt: Date().addingTimeInterval(3600), apiBaseURL: "https://share.example.test/" + fixture)
        return try await client.analyze(sourceURL: "https://www.instagram.com/reel/reported/", caption: "",
            credential: credential, analysisID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)
    }

    func testUsageLimitIsActionableInsteadOfGenericServiceFailure() async throws {
        do {
            _ = try await analyze("limit")
            XCTFail("A usage limit must not succeed")
        } catch ShareAnalysisError.usageLimit {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testRetryDistinguishesRunningFromTerminalFailure() async throws {
        do {
            _ = try await analyze("running")
            XCTFail("Running claim must not start another analysis")
        } catch ShareAnalysisError.analysisInProgress {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            _ = try await analyze("failed")
            XCTFail("Terminal failure must allow a fresh claim")
        } catch ShareAnalysisError.analysisFailed {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testPendingSourceReceiptSurvivesDecodingWithoutCreatingPlace() async throws {
        for reason in ["login_required", "expired", "caption_missing", "unresolved_source", "source_out_of_bounds"] {
            let result = try await analyze(reason)
            XCTAssertEqual(result.semanticStatus, "analysis_pending")
            XCTAssertTrue(result.candidates.isEmpty)
            guard case .sourceUnavailable(let actual) = result.pendingError else {
                return XCTFail("Source failure was hidden")
            }
            XCTAssertEqual(actual, reason)
            XCTAssertFalse(result.pendingError.localizedDescription.contains("來源已"), "Unsaved source must not claim persistence")
        }
    }

    func testProviderAndLegacyPendingResponsesRemainServiceFailures() async throws {
        for fixture in ["provider", "legacy"] {
            let result = try await analyze(fixture)
            guard case .serviceUnavailable = result.pendingError else { return XCTFail("Provider must not be blamed on source content") }
        }
        do {
            _ = try await analyze("server-error")
            XCTFail("Unknown error must fail safely")
        } catch ShareAnalysisError.serviceUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testTransportErrorsKeepActionableMeaning() async throws {
        do {
            _ = try await analyze("timeout")
            XCTFail("Timeout must not succeed")
        } catch ShareAnalysisError.timedOut {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            _ = try await analyze("offline")
            XCTFail("Offline must not succeed")
        } catch ShareAnalysisError.networkUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

private final class ShareFailureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let fixture = request.url!.pathComponents[1]
        if fixture == "timeout" || fixture == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(fixture == "timeout" ? .timedOut : .notConnectedToInternet))
            return
        }
        let status: Int
        let body: String
        switch fixture {
        case "limit":
            status = 429; body = #"{"code":"analysis_limit_exceeded","error":"Daily analysis limit reached"}"#
        case "running":
            status = 409; body = #"{"code":"analysis_in_progress"}"#
        case "failed":
            status = 409; body = #"{"code":"analysis_failed"}"#
        case "server-error":
            status = 500; body = #"{"error":"internal details must not reach UI"}"#
        case "provider":
            status = 200; body = #"{"owner_subject":"fixture-owner","candidates":[],"semanticStatus":"analysis_pending","receipt":{"failureReason":{"kind":"provider_failure","stage":"public_search"}}}"#
        case "legacy":
            status = 200; body = #"{"owner_subject":"fixture-owner","candidates":[],"semanticStatus":"analysis_pending"}"#
        default:
            status = 200; body = """
            {"owner_subject":"fixture-owner","candidates":[],"semanticStatus":"analysis_pending","receipt":{"failureReason":{"kind":"insufficient_source","reason":"\(fixture)"}}}
            """
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
