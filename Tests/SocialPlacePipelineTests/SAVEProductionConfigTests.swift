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
        XCTAssertTrue(paywall.contains("paywall.savedNote"))
        XCTAssertTrue(paywall.contains("paywall.benefit.unlimited"))
        XCTAssertTrue(paywall.contains("paywall.loading"))
        XCTAssertTrue(paywall.contains("paywall.unavailable"))
        XCTAssertTrue(paywall.contains("paywall.retry"))
        XCTAssertFalse(paywall.contains("paywall.keepGoing"))
        XCTAssertFalse(paywall.contains("paywall.retryProducts"))
        XCTAssertTrue(paywall.contains("--uitest-show-paywall-retry"))
        XCTAssertTrue(paywall.contains("func retryOffers(message: String)"))
        XCTAssertFalse(paywall.contains("paywall.productsRetry"))
        XCTAssertFalse(paywall.contains("paywall.proBenefit"))
        XCTAssertFalse(paywall.contains("paywall.freePlaceLimit"))
        XCTAssertFalse(paywall.contains("paywall.loadingProducts"))
        XCTAssertTrue(
            paywall.contains("if trigger == .savedPlaceLimit"),
            "Q1: the saved-50 line belongs only on the 51st-save trigger"
        )
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
        XCTAssertTrue(map.contains("startedBy userId: String?"))
        XCTAssertTrue(map.contains("generation: Int"))
        XCTAssertTrue(map.contains("try ensureConfirmationSession(userId, generation)"))
        XCTAssertTrue(map.contains("parkIfServerSavedPlaceLimit("))
        XCTAssertTrue(map.contains("startedBy: userId,"))
        XCTAssertTrue(map.contains("syncSavedPlaceLimitCache()"))
        XCTAssertTrue(
            map.contains("place: merged,") && map.contains("generation: importGeneration"),
            "C6: pending Share Extension imports park on a server cap"
        )
        XCTAssertTrue(share.contains("SaveShareExtensionPlaceDestination.resolve"))
        XCTAssertTrue(
            map.contains("savedPlaceCount: savedPlaceCountForLimit"),
            "A1: the local cap counts confirmed Map Stamps, preferring the last server count"
        )
        XCTAssertTrue(
            map.contains("authoritativeSavedPlaceCount"),
            "A5 inverse: a stale vault row must not keep the local cap at 50"
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

    func testFreeCapE4ScreenshotFixturesStayOnDebugLaunchArgs() throws {
        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(content.contains("--uitest-show-saved-place-limit-paywall"))
        XCTAssertTrue(content.contains("--uitest-show-unplaced-candidate"))
        XCTAssertTrue(content.contains("--uitest-show-ai-quota-notice"))
        XCTAssertTrue(content.contains("Unplaced Harbor Cafe"))
        XCTAssertTrue(
            content.contains("e4000000-0000-4000-8000-000000000051"),
            "E4 Unplaced row id is saves.unplaced.row.<this placeId>"
        )
        XCTAssertTrue(content.contains("parkPlaceInUnplacedInbox(place, requestPaywall: false)"))
        XCTAssertTrue(
            content.contains("consumePendingSavedPlaceLimitPaywall()"),
            "E4 Unplaced must clear a leftover paywall handoff so Home Saves stays tappable"
        )
        XCTAssertTrue(content.contains("ShareAnalysisError.usageLimit.errorDescription"))
        XCTAssertTrue(content.contains("showAIQuotaNotice = true"))

        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("func testFreeCapE4Screenshots()"))
        XCTAssertTrue(
            rail.contains("home.saves"),
            "E4 taps the live Home header Saves control (SaveTileTownHomeView)"
        )
        XCTAssertTrue(
            rail.contains("home.more.saves"),
            "More → Manage remains a fallback after the in-flow sheet opens"
        )
        XCTAssertTrue(
            rail.contains("firstHittable"),
            "Do not coordinate-tap a covered header; wait for a hittable Saves control"
        )
        XCTAssertFalse(
            rail.contains("app.buttons[\"Manage saved places\"]"),
            "that label is shared with header home.saves and throws on tap"
        )
        for name in [
            "e4-51st-save-paywall",
            "e4-paywall-retry",
            "e4-unplaced-candidate",
            "e4-settings-paywall",
            "e4-ai-quota-notice",
        ] {
            XCTAssertTrue(rail.contains("attach(app, name: \"\(name)\")"), name)
        }
        XCTAssertTrue(rail.contains("You've saved 50 places. Keep going."))
        XCTAssertTrue(rail.contains("paywall.savedNote"))
        XCTAssertFalse(rail.contains("paywall.keepGoing"))
        XCTAssertTrue(rail.contains("func testSavedPlaceLimitPaywallRetryIsActionable()"))
        XCTAssertTrue(rail.contains("--uitest-show-paywall-retry"))
        XCTAssertTrue(rail.contains("paywall.retry"))
        XCTAssertTrue(rail.contains("attach(app, name: \"paywall-retry\")"))
        XCTAssertTrue(
            try source(at: "scripts/select-ios-tests.py").contains("testSavedPlaceLimitPaywallRetryIsActionable"),
            "B6 retry assertion must stay on the required ios/FULL selector list"
        )
        XCTAssertTrue(rail.contains("Review Candidate"))
        XCTAssertTrue(
            rail.contains("Settings Pro row requires a confirmed Map Stamp on Home first."),
            "E4 Settings waits for home.featuredName before opening the gated Pro row"
        )
        let saves = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(saves.contains("saves.unplaced"))
        XCTAssertTrue(saves.contains("saves.unplaced.row.\\(candidate.id.uuidString)"))
        let candidate = try source(at: "SAV-E/Services/PendingPlaceImportService.swift")
        XCTAssertTrue(candidate.contains("unplacedInboxMarker"))
        XCTAssertTrue(candidate.contains("isUnplacedInbox"))
        XCTAssertTrue(candidate.contains("missingInfo: [unplacedInboxMarker]"))

        XCTAssertTrue(rail.contains("saves.unplaced"))
        XCTAssertTrue(rail.contains("saves.unplaced.row.E4000000-0000-4000-8000-000000000051"))
        XCTAssertTrue(
            rail.contains("Q1: Settings uses the Passport trigger, not the saved-50 line."),
            "Settings still must prove the saved-50 line is absent"
        )
        XCTAssertTrue(rail.contains("The analysis usage limit has been reached. Keep the source and try again later."))
        XCTAssertTrue(rail.contains("exhausted AI quota must not open the paywall."))

        let workflow = try source(at: ".github/workflows/ci.yml")
        XCTAssertTrue(workflow.contains("save-free-cap-e4-${{ github.sha }}"))
        XCTAssertTrue(workflow.contains("SAVEUITests/SAVEScreenshotRailTests/testFreeCapE4Screenshots"))
        XCTAssertTrue(workflow.contains("e4-paywall-retry"))
        XCTAssertFalse(
            try source(at: "scripts/select-ios-tests.py").contains("testFreeCapE4Screenshots"),
            "E4 stays off FULL so the required ios job does not grow four launches"
        )
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
    func testExplicitLocalReviewDecisionsSurviveVaultAndMapReloadWithFullContext() async throws {
        let auth = PrivyAuthService.shared
        let oldAuth = auth.authState
        defer { auth.authState = oldAuth }
        for owner in [nil, "local-decision-owner"] as [String?] {
            auth.authState = owner.map { .authenticated(userId: $0) } ?? .unauthenticated
            for status in ["source_only", "needs_more_evidence"] {
                for parked in [false, true] {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let url = directory.appendingPathComponent("vault.json")
                    let vault = SaveLocalVaultService(overrideVaultURL: url)
                    let candidate = localReviewDecisionFixture(owner: owner, parked: parked)
                    var record = try vault.saveReviewCandidate(candidate, preservingParkedContext: true)
                    record.sourceURL = "https://example.com/private-original"
                    record.sourceText = "Original private caption and input"
                    try vault.deleteAllRecords()
                    try vault.append(record)
                    let events = SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("events.json"))
                    let map = MapViewModel(supabaseService: SupabaseService(apiBaseURL: nil), saveLocalVaultService: vault,
                        correctionEventStore: events, usesRemotePersistence: owner != nil)
                    map.reviewCandidates = [candidate]
                    map.selectedReviewCandidate = candidate
                    if status == "source_only" { try await map.saveReviewCandidateAsSourceOnly(candidate) }
                    else { try await map.investigateReviewCandidateMore(candidate) }
                    XCTAssertEqual(map.reviewCandidates.first?.status, status)
                    XCTAssertEqual(map.selectedReviewCandidate?.status, status)
                    XCTAssertTrue(map.places.isEmpty)
                    let reloaded = SaveLocalVaultService(overrideVaultURL: url)
                    let persisted = try XCTUnwrap(reloaded.reviewCandidates(belongingTo: owner).first)
                    XCTAssertEqual(persisted.id, candidate.id)
                    XCTAssertEqual(persisted.ownerSubject, owner)
                    XCTAssertEqual(persisted.status, status)
                    XCTAssertEqual(persisted.name, candidate.name)
                    XCTAssertEqual(persisted.address, candidate.address)
                    XCTAssertEqual(persisted.city, candidate.city)
                    XCTAssertEqual(persisted.confidence, candidate.confidence)
                    XCTAssertEqual(persisted.createdAt, candidate.createdAt)
                    XCTAssertEqual(persisted.placeHighlights, candidate.placeHighlights)
                    XCTAssertEqual(persisted.recommendedItems, candidate.recommendedItems)
                    XCTAssertEqual(persisted.vibeTags, candidate.vibeTags)
                    XCTAssertEqual(persisted.accessNotes, candidate.accessNotes)
                    XCTAssertEqual(persisted.sourceHandle, candidate.sourceHandle)
                    XCTAssertEqual(persisted.correctionScopeKey, candidate.correctionScopeKey)
                    XCTAssertEqual(persisted.missingInfo, candidate.missingInfo)
                    XCTAssertNil(persisted.captureId)
                    XCTAssertNil(persisted.workflowRunId)
                    XCTAssertTrue(candidate.evidence.allSatisfy { persisted.evidence.contains($0) })
                    XCTAssertEqual(try reloaded.recentRecords().first?.sourceText, record.sourceText)
                    XCTAssertEqual(try reloaded.recentRecords().first?.sourceURL, record.sourceURL)
                    XCTAssertTrue(try reloaded.confirmedPlaces().isEmpty)
                    XCTAssertTrue(try reloaded.reviewCandidates(belongingTo: "different-account").isEmpty)
                    if owner != nil { XCTAssertTrue(try reloaded.reviewCandidates(belongingTo: nil).isEmpty) }
                    let fresh = MapViewModel(supabaseService: SupabaseService(apiBaseURL: nil), saveLocalVaultService: reloaded,
                        correctionEventStore: events, usesRemotePersistence: owner != nil)
                    try await fresh.refreshReviewCandidates()
                    XCTAssertEqual(fresh.reviewCandidates.first?.status, status, "Refresh must not resurrect the old parked review status")
                    XCTAssertEqual(fresh.reviewCandidates.first?.isUnplacedInbox, parked)
                }
            }
        }
    }

    @MainActor
    func testLocalReviewDecisionWriteFailureKeepsInputAndPendingEventUntilRetry() async throws {
        let auth = PrivyAuthService.shared
        let oldAuth = auth.authState
        defer { auth.authState = oldAuth }
        auth.authState = .authenticated(userId: "decision-owner")
        for status in ["source_only", "needs_more_evidence"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("vault.json")
            let vault = SaveLocalVaultService(overrideVaultURL: url)
            let candidate = localReviewDecisionFixture(owner: "decision-owner", parked: true)
            try vault.saveReviewCandidate(candidate, preservingParkedContext: true)
            let before = try Data(contentsOf: url)
            let events = SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("events.json"))
            let map = MapViewModel(supabaseService: SupabaseService(apiBaseURL: nil), saveLocalVaultService: vault,
                correctionEventStore: events, usesRemotePersistence: true)
            map.reviewCandidates = [candidate]
            map.selectedReviewCandidate = candidate
            vault.saveReviewCandidateError = SaveLocalVaultError.storageUnavailable
            do {
                if status == "source_only" { try await map.saveReviewCandidateAsSourceOnly(candidate) }
                else { try await map.investigateReviewCandidateMore(candidate) }
                XCTFail("Failed durable write cannot report a successful decision")
            } catch SaveLocalVaultError.storageUnavailable {}
            XCTAssertEqual(map.reviewCandidates, [candidate])
            XCTAssertEqual(map.selectedReviewCandidate, candidate)
            XCTAssertEqual(try Data(contentsOf: url), before)
            let pending = try events.recentEvents()
            XCTAssertEqual(pending.count, 1)
            XCTAssertEqual(pending.first?.learningCommitted, false)
            vault.saveReviewCandidateError = nil
            if status == "source_only" { try await map.saveReviewCandidateAsSourceOnly(candidate) }
            else { try await map.investigateReviewCandidateMore(candidate) }
            XCTAssertEqual(map.reviewCandidates.first?.status, status)
            XCTAssertEqual(try SaveLocalVaultService(overrideVaultURL: url).reviewCandidates(belongingTo: "decision-owner").first?.status, status)
            XCTAssertTrue(map.places.isEmpty)
        }
    }

    @MainActor
    func testLocalReviewDecisionRejectsForeignOwnerBeforeWritingReceiptOrVault() async throws {
        let auth = PrivyAuthService.shared
        let oldAuth = auth.authState
        defer { auth.authState = oldAuth }
        auth.authState = .authenticated(userId: "account-b")
        for owner in [nil, "account-a"] as [String?] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("vault.json")
            let vault = SaveLocalVaultService(overrideVaultURL: url)
            let candidate = localReviewDecisionFixture(owner: owner, parked: true)
            try vault.saveReviewCandidate(candidate, preservingParkedContext: true)
            let before = try Data(contentsOf: url)
            let events = SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("events.json"))
            let map = MapViewModel(supabaseService: SupabaseService(apiBaseURL: nil), saveLocalVaultService: vault,
                correctionEventStore: events, usesRemotePersistence: true)
            map.reviewCandidates = [candidate]
            do { try await map.saveReviewCandidateAsSourceOnly(candidate); XCTFail("No ownerless or A-to-B reassignment") }
            catch ReviewCandidateError.sessionChangedAfterCommit {}
            XCTAssertEqual(map.reviewCandidates, [candidate])
            XCTAssertEqual(try Data(contentsOf: url), before)
            XCTAssertTrue(try events.recentEvents().isEmpty)
        }
    }

    @MainActor
    func testRemoteWorkflowReviewDecisionsStillUseServerAndDoNotUseLocalDecisionWriter() async throws {
        let auth = PrivyAuthService.shared
        let oldAuth = auth.authState
        defer { auth.authState = oldAuth; AnalysisRequestURLProtocol.reset() }
        auth.authState = .authenticated(userId: "remote-decision-owner")
        for status in ["source_only", "needs_more_evidence"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
            vault.saveReviewCandidateError = SaveLocalVaultError.storageUnavailable
            var candidate = localReviewDecisionFixture(owner: "remote-decision-owner", parked: true)
            let run = UUID()
            candidate.workflowRunId = run
            let workflow = "{\"id\":\"\(run)\",\"workflow_id\":\"fixture\",\"listing_id\":\"fixture\",\"source_type\":\"social_url\",\"status\":\"pending\",\"evidence_tier\":\"weak\",\"result_evidence_refs\":[],\"result_candidate_refs\":[],\"credit_reserved\":1,\"credit_settlement\":\"pending\"}"
            let receipt = "{\"id\":\"\(UUID())\",\"run_id\":\"\(run)\",\"workflow_id\":\"fixture\",\"verdict\":\"\(status)\",\"settlement\":\"pending\",\"evaluator_summary\":\"fixture\",\"evidence_refs\":[],\"candidate_refs\":[],\"receipt_hash\":\"fixture\",\"anchor_status\":\"none\"}"
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { request in
                if request.httpMethod == "GET", request.url?.path == "/v0/lists" { return (200, "[]") }
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v0/workflows/place-recovery/runs/\(run.uuidString)/decision")
                let body = try AnalysisRequestURLProtocol.body(request)
                XCTAssertEqual(body["action"] as? String, status == "source_only" ? "source_only" : "investigate_more")
                return (200, "{\"run\":\(workflow),\"receipt\":\(receipt)}")
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
            let service = SupabaseService(apiBaseURL: "https://local-decision.test", session: URLSession(configuration: configuration), accessTokenProvider: { "fixture-token" })
            let events = SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("events.json"))
            let map = MapViewModel(supabaseService: service, saveLocalVaultService: vault, correctionEventStore: events)
            map.reviewCandidates = [candidate]
            if status == "source_only" { try await map.saveReviewCandidateAsSourceOnly(candidate) }
            else { try await map.investigateReviewCandidateMore(candidate) }
            XCTAssertEqual(map.reviewCandidates.first?.status, status)
            XCTAssertEqual(AnalysisRequestURLProtocol.requests.filter { $0.httpMethod == "POST" }.count, 1)
            XCTAssertEqual(try events.recentEvents().first?.learningCommitted, true)
        }
    }

    @MainActor
    private func localReviewDecisionFixture(owner: String?, parked: Bool) -> PlaceReviewCandidate {
        var candidate = contextualReviewCandidate(owner: owner ?? "unused", workflow: false)
        candidate.captureId = nil
        candidate.ownerSubject = owner
        candidate.correctionScopeKey = "instagram:local-review-fixture"
        candidate.missingInfo = ["Analysis pending", "Original unknown field"]
        if parked { candidate.missingInfo.append(PlaceReviewCandidate.unplacedInboxMarker) }
        return candidate
    }

    @MainActor
    private func contextualReviewCandidate(owner: String, workflow: Bool) -> PlaceReviewCandidate {
        PlaceReviewCandidate(id: UUID(), captureId: UUID(), workflowRunId: workflow ? UUID() : nil,
            name: "Original Review Cafe", address: "1 Context Road", city: "Taipei",
            latitude: 25.15, longitude: 121.56,
            evidence: ["Source URL: https://example.com/context", "Original caption and user clue"],
            confidence: 0.83, missingInfo: ["User confirmation"], status: "review",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            placeHighlights: ["Original highlight"], recommendedItems: [RecommendedItem(name: "Tea", price: "$50")],
            vibeTags: ["quiet"], accessNotes: ["upstairs"], sourceHandle: "@context",
            googlePlaceId: "context-place", category: .cafe, ownerSubject: owner)
    }

    @MainActor
    func testExistingReviewCapPersistsUnplacedContextAcrossReloadAndRefresh() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        defer { auth.authState = originalAuth; SavePlaceLimitHandoff.testDefaults = originalDefaults; AnalysisRequestURLProtocol.reset() }
        for route in ["local", "legacy", "workflow"] {
            let owner = "context-owner-\(route)"
            auth.authState = .authenticated(userId: owner)
            SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.context.\(UUID())")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vaultURL = directory.appendingPathComponent("vault.json")
            let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
            let candidate = contextualReviewCandidate(owner: owner, workflow: route == "workflow")
            try vault.saveReviewCandidate(candidate)
            let capPath = route == "workflow"
                ? "/v0/workflows/place-recovery/runs/\(candidate.workflowRunId!.uuidString)/decision" : "/places"
            var refusalCount = 0
            var remoteStatus = "review"
            var superseded = false
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { request in
                if request.httpMethod == "POST", request.url?.path == capPath {
                    refusalCount += 1
                    return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
                }
                if request.url?.path == "/memory/candidates" {
                    // Fresh venue data must win; missing local workflow/source context and marker must survive.
                    var row: [String: Any] = ["id": candidate.id.uuidString, "name": "Updated Remote Cafe",
                        "address": "2 New Road", "city": "New City", "latitude": 26.2, "longitude": 122.3,
                        "confidence": 0.97, "evidence": [["text": "Fresh server venue evidence", "google_place_id": "new-context-place", "google_types": ["cafe"]]],
                        "missing_info": [], "status": remoteStatus, "created_at": "2023-11-14T22:13:20Z"]
                    if superseded { row["superseded_by_candidate_id"] = UUID().uuidString }
                    return (200, String(data: try JSONSerialization.data(withJSONObject: [row]), encoding: .utf8)!)
                }
                return (200, request.httpMethod == "GET" ? "[]" : "{}")
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
            let service = SupabaseService(apiBaseURL: "https://context.test", session: URLSession(configuration: configuration), accessTokenProvider: { "fixture-token" })
            let map = MapViewModel(supabaseService: service, saveLocalVaultService: vault,
                correctionEventStore: SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("events.json")),
                entitlementTierProvider: { .free }, entitlementResolvedProvider: { true }, usesRemotePersistence: route != "local")
            map.places = makeCappedPlaces(50)
            map.reviewCandidates = [candidate]
            map.selectedReviewCandidate = candidate
            do { _ = try await map.saveReviewCandidateAsPlace(candidate); XCTFail("Cap must keep this item unconfirmed") }
            catch is SavePlaceLimitError {}
            var expected = candidate
            expected.missingInfo.append(PlaceReviewCandidate.unplacedInboxMarker)
            XCTAssertEqual(map.reviewCandidates, [expected])
            XCTAssertEqual(map.selectedReviewCandidate, expected)
            XCTAssertTrue(map.reviewCandidates[0].isUnplacedInbox, "SaveRootViews uses this property for its Unplaced section")
            XCTAssertEqual(map.places.count, 50)
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
            XCTAssertEqual(refusalCount, route == "local" ? 0 : 1)
            let reloaded = SaveLocalVaultService(overrideVaultURL: vaultURL)
            XCTAssertEqual(try reloaded.reviewCandidates(belongingTo: owner), [expected], "Disk reload must preserve all original context")
            XCTAssertTrue(try reloaded.confirmedPlaces(belongingTo: owner).isEmpty)

            // A new VM proves the refresh overlay comes from durable state, not the old array.
            let refreshedMap = MapViewModel(supabaseService: service, saveLocalVaultService: reloaded)
            try await refreshedMap.refreshReviewCandidates()
            let refreshed = try XCTUnwrap(refreshedMap.reviewCandidates.first)
            XCTAssertTrue(refreshed.isUnplacedInbox)
            XCTAssertEqual(refreshed.id, candidate.id)
            XCTAssertEqual(refreshed.ownerSubject, owner)
            XCTAssertEqual(refreshed.captureId, candidate.captureId)
            XCTAssertEqual(refreshed.workflowRunId, candidate.workflowRunId)
            XCTAssertEqual(refreshed.name, "Updated Remote Cafe")
            XCTAssertEqual(refreshed.latitude, 26.2)
            XCTAssertEqual(refreshed.city, "New City")
            XCTAssertEqual(refreshed.confidence, 0.97)
            XCTAssertEqual(refreshed.googlePlaceId, "new-context-place")
            XCTAssertTrue(candidate.evidence.allSatisfy { refreshed.evidence.contains($0) })
            XCTAssertTrue(refreshed.evidence.contains("Fresh server venue evidence"))
            remoteStatus = "saved"
            try await refreshedMap.refreshReviewCandidates()
            XCTAssertTrue(refreshedMap.reviewCandidates.isEmpty, "A local park cannot resurrect a terminal remote candidate")
            remoteStatus = "review"
            superseded = true
            try await refreshedMap.refreshReviewCandidates()
            XCTAssertTrue(refreshedMap.reviewCandidates.isEmpty, "A local park cannot resurrect a superseded candidate")
        }
    }

    @MainActor
    func testExistingReviewFailedParkingKeepsOriginalAndAllowsRetry() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        defer { auth.authState = originalAuth; SavePlaceLimitHandoff.testDefaults = originalDefaults; AnalysisRequestURLProtocol.reset() }
        for route in ["local", "legacy", "workflow"] {
            let owner = "failed-context-owner"
            auth.authState = .authenticated(userId: owner)
            SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.failed-context.\(UUID())")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
            let candidate = contextualReviewCandidate(owner: owner, workflow: route == "workflow")
            try vault.saveReviewCandidate(candidate)
            let before = try Data(contentsOf: directory.appendingPathComponent("vault.json"))
            vault.saveReviewCandidateError = SaveLocalVaultError.storageUnavailable
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { request in
                if request.httpMethod == "POST" { return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#) }
                return (200, "[]")
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
            let service = SupabaseService(apiBaseURL: "https://failed-context.test", session: URLSession(configuration: configuration), accessTokenProvider: { "fixture-token" })
            let map = MapViewModel(supabaseService: service, saveLocalVaultService: vault,
                correctionEventStore: SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("events.json")),
                entitlementTierProvider: { .free }, entitlementResolvedProvider: { true }, usesRemotePersistence: route != "local")
            map.places = makeCappedPlaces(50)
            map.reviewCandidates = [candidate]
            map.selectedReviewCandidate = candidate
            do { _ = try await map.saveReviewCandidateAsPlace(candidate); XCTFail("Storage failure cannot report a parked result") }
            catch SaveLocalVaultError.storageUnavailable {}
            XCTAssertEqual(map.reviewCandidates, [candidate])
            XCTAssertEqual(map.selectedReviewCandidate, candidate)
            XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
            XCTAssertFalse(SavePlaceLimitHandoff.consumePaywallPending())
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("vault.json")), before)
            XCTAssertEqual(map.places.count, 50)
            vault.saveReviewCandidateError = nil
            do { _ = try await map.saveReviewCandidateAsPlace(candidate); XCTFail("Still over the cap") }
            catch is SavePlaceLimitError {}
            XCTAssertTrue(map.reviewCandidates.first?.isUnplacedInbox == true)
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
            XCTAssertEqual(try vault.reviewCandidates(belongingTo: owner).first?.captureId, candidate.captureId)
        }
    }

    @MainActor
    func testExistingReviewCapResponseAfterAccountSwitchDoesNotParkForNewOwner() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        defer { auth.authState = originalAuth; SavePlaceLimitHandoff.testDefaults = originalDefaults; AnalysisRequestURLProtocol.reset() }
        for workflow in [false, true] {
            let owner = "context-session-A"
            auth.authState = .authenticated(userId: owner)
            SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.context-session.\(UUID())")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
            let candidate = contextualReviewCandidate(owner: owner, workflow: workflow)
            try vault.saveReviewCandidate(candidate)
            let before = try Data(contentsOf: directory.appendingPathComponent("vault.json"))
            let arrived = expectation(description: "candidate cap response in flight")
            let release = DispatchSemaphore(value: 0)
            var hold = true
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { request in
                if request.httpMethod == "POST", request.url?.path == "/places" || request.url?.path.hasSuffix("/decision") == true {
                    if hold { arrived.fulfill(); _ = release.wait(timeout: .now() + 10) }
                    return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
                }
                return (200, "[]")
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
            let service = SupabaseService(apiBaseURL: "https://context-session.test", session: URLSession(configuration: configuration), accessTokenProvider: { "fixture-token" })
            let map = MapViewModel(supabaseService: service, saveLocalVaultService: vault,
                correctionEventStore: SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("events.json")),
                entitlementTierProvider: { .free }, entitlementResolvedProvider: { true }, usesRemotePersistence: true)
            map.reviewCandidates = [candidate]
            let task = Task { try await map.saveReviewCandidateAsPlace(candidate) }
            await fulfillment(of: [arrived], timeout: 5)
            auth.authState = .authenticated(userId: "context-session-B")
            release.signal()
            do { _ = try await task.value; XCTFail("The old session must stop") }
            catch is CancellationError {}
            XCTAssertEqual(map.reviewCandidates, [candidate])
            XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
            XCTAssertTrue(map.places.isEmpty)
            XCTAssertTrue(try vault.reviewCandidates(belongingTo: "context-session-B").isEmpty)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("vault.json")), before)
            auth.authState = .authenticated(userId: owner)
            hold = false
            do { _ = try await map.saveReviewCandidateAsPlace(candidate); XCTFail("Still capped for A") }
            catch is SavePlaceLimitError {}
            XCTAssertTrue(map.reviewCandidates.first?.isUnplacedInbox == true)
            XCTAssertEqual(try vault.reviewCandidates(belongingTo: owner).first?.workflowRunId, candidate.workflowRunId)
        }
    }

    @MainActor
    func testParkedCandidateSnapshotIsBackwardCompatibleAndCannotCrossRecordIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let owner = "snapshot-owner"
        var parked = contextualReviewCandidate(owner: owner, workflow: true)
        parked.missingInfo.append(PlaceReviewCandidate.unplacedInboxMarker)
        var record = SaveMemoryRecord(id: parked.id, state: .reviewCandidate, title: "Generic Record", ownerSubject: owner)
        let encoded = try JSONEncoder().encode(record)
        var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyJSON.removeValue(forKey: "parkedReviewCandidate")
        let legacy = try JSONDecoder().decode(SaveMemoryRecord.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        XCTAssertNil(legacy.parkedReviewCandidate)
        try vault.append(legacy)
        XCTAssertEqual(try vault.reviewCandidates(belongingTo: owner).first?.name, "Generic Record")
        XCTAssertNil(try vault.reviewCandidates(belongingTo: owner).first?.captureId)
        try vault.deleteAllRecords()
        parked.correctionLearningPlaceID = UUID()
        parked.correctionLearningUserID = owner
        parked.sourceFailureReason = SourceSearchFailureReason(kind: .providerFailure, reason: nil, stage: "source")
        try vault.saveReviewCandidate(parked, preservingParkedContext: true)
        let persisted = try XCTUnwrap(vault.reviewCandidates(belongingTo: owner).first)
        XCTAssertNil(persisted.correctionLearningPlaceID)
        XCTAssertNil(persisted.correctionLearningUserID)
        XCTAssertNil(persisted.sourceFailureReason)
        XCTAssertEqual(persisted.captureId, parked.captureId)
        var refreshed = contextualReviewCandidate(owner: owner, workflow: false)
        refreshed.id = parked.id
        refreshed.name = "Vault Updated Venue"
        refreshed.latitude = 27.5
        refreshed.evidence = ["New merged evidence"]
        try vault.saveReviewCandidate(refreshed)
        let merged = try XCTUnwrap(vault.reviewCandidates(belongingTo: owner).first)
        XCTAssertTrue(merged.isUnplacedInbox)
        XCTAssertEqual(merged.captureId, parked.captureId)
        XCTAssertEqual(merged.workflowRunId, parked.workflowRunId)
        XCTAssertEqual(merged.name, refreshed.name)
        XCTAssertEqual(merged.latitude, refreshed.latitude)
        XCTAssertTrue(merged.evidence.contains("New merged evidence"))
        XCTAssertTrue(parked.evidence.allSatisfy { merged.evidence.contains($0) })
        try vault.deleteAllRecords()
        for mismatch in ["owner", "id", "confirmed"] {
            record.state = mismatch == "confirmed" ? .confirmedPlace : .reviewCandidate
            record.parkedReviewCandidate = parked
            if mismatch == "owner" { record.parkedReviewCandidate?.ownerSubject = "different-owner" }
            if mismatch == "id" { record.parkedReviewCandidate?.id = UUID() }
            try vault.append(record)
            let projected = try vault.reviewCandidates(belongingTo: owner)
            if mismatch == "confirmed" { XCTAssertTrue(projected.isEmpty) }
            else {
                XCTAssertEqual(projected.count, 1)
                XCTAssertNil(projected.first?.captureId)
                XCTAssertNil(projected.first?.workflowRunId)
                XCTAssertFalse(projected.first?.isUnplacedInbox == true)
            }
            try vault.deleteAllRecords()
        }
    }

    @MainActor
    func testProAndDuplicateConfirmationRemoveParkedCandidateSnapshot() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        defer { auth.authState = originalAuth }
        let owner = "snapshot-confirm-owner"
        auth.authState = .authenticated(userId: owner)
        for duplicate in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vaultURL = directory.appendingPathComponent("vault.json")
            let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
            var candidate = contextualReviewCandidate(owner: owner, workflow: true)
            candidate.missingInfo.append(PlaceReviewCandidate.unplacedInboxMarker)
            try vault.saveReviewCandidate(candidate, preservingParkedContext: true)
            let map = MapViewModel(saveLocalVaultService: vault,
                entitlementTierProvider: { duplicate ? .free : .pro }, entitlementResolvedProvider: { true }, usesRemotePersistence: false)
            map.reviewCandidates = [candidate]
            if duplicate {
                let existing = Place.from(candidate)
                try vault.saveConfirmedPlace(existing, ownerSubject: owner)
                map.places = [existing] + makeCappedPlaces(49)
            } else { map.places = makeCappedPlaces(50) }
            _ = try await map.saveReviewCandidateAsPlace(candidate)
            XCTAssertEqual(map.places.count, duplicate ? 50 : 51)
            XCTAssertTrue(map.reviewCandidates.isEmpty)
            let reloaded = SaveLocalVaultService(overrideVaultURL: vaultURL)
            XCTAssertTrue(try reloaded.reviewCandidates(belongingTo: owner).isEmpty)
            XCTAssertTrue(try reloaded.recentRecords(belongingTo: owner).allSatisfy { $0.parkedReviewCandidate == nil })
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
            XCTAssertNotEqual(
                map.reviewCandidates.first?.id,
                social.id,
                "author places.id must not become the recipient Map Stamp id"
            )
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
        // The receipt path calls loadPlaces() when hasLoadedPlaces is false.
        // In-memory assignment alone is wiped by GET /places [] + an empty
        // vault; parking does not clear Map Stamps. Persist the 49 first.
        let seeded = makeCappedPlaces(49)
        for place in seeded {
            _ = try vault.saveConfirmedPlace(place, ownerSubject: "receipt-owner")
        }
        map.places = seeded
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
            XCTAssertFalse(map.places.contains(where: { $0.name == "Server Cap Cafe" }))
            XCTAssertEqual(map.reviewCandidates.first?.name, "Server Cap Cafe")
            XCTAssertEqual(map.reviewCandidates.first?.status, "review")
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        }
    }

    @MainActor
    func testShortCodeReceiptExpiredAtCapDoesNotPark() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "receipt-owner")
        defer { PrivyAuthService.shared.authState = previousAuth }

        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "POST", request.url?.path == "/places" {
                return (410, #"{"error":"Shared place link expired"}"#)
            }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-short-expired.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-short-expired-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)
        let seeded = makeCappedPlaces(50)
        for place in seeded {
            _ = try vault.saveConfirmedPlace(place, ownerSubject: "receipt-owner")
        }
        map.places = seeded
        let receipt = makeShortCodeReceipt(name: "Expired Cafe", code: "AbC123_x")

        do {
            _ = try await map.saveSharedPlaceReceipt(receipt)
            XCTFail("an expired short-code receipt must not become a Map Stamp")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTFail("an expired short-code receipt must not park as an over-limit save")
        } catch {
            let posted = try XCTUnwrap(AnalysisRequestURLProtocol.requests.first {
                $0.httpMethod == "POST" && $0.url?.path == "/places"
            })
            let body = try AnalysisRequestURLProtocol.body(posted)
            XCTAssertEqual(body["friend_share_code"] as? String, "AbC123_x")
            XCTAssertEqual(map.places.count, 50)
            XCTAssertFalse(map.places.contains(where: { $0.name == "Expired Cafe" }))
            XCTAssertTrue(map.reviewCandidates.isEmpty)
            XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        }
    }

    @MainActor
    func testShortCodeReceiptServerCapParksInsteadOfConfirmingLocally() async throws {
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
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-short-cap.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-short-cap-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)
        let seeded = makeCappedPlaces(49)
        for place in seeded {
            _ = try vault.saveConfirmedPlace(place, ownerSubject: "receipt-owner")
        }
        map.places = seeded
        let receipt = makeShortCodeReceipt(name: "Short Cap Cafe", code: "AbC123_x")

        do {
            _ = try await map.saveSharedPlaceReceipt(receipt)
            XCTFail("a server over-limit short-code receipt must not become a local Map Stamp")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            let posted = try XCTUnwrap(AnalysisRequestURLProtocol.requests.first {
                $0.httpMethod == "POST" && $0.url?.path == "/places"
            })
            let body = try AnalysisRequestURLProtocol.body(posted)
            XCTAssertEqual(body["friend_share_code"] as? String, "AbC123_x")
            XCTAssertEqual(map.places.count, 49)
            XCTAssertFalse(map.places.contains(where: { $0.name == "Short Cap Cafe" }))
            XCTAssertEqual(map.reviewCandidates.first?.name, "Short Cap Cafe")
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
    func testAcknowledgingPaywallKeepsTheParkedCandidate() throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        let place = makeSocialPlace(name: "Stay In Review")
        _ = try map.parkPlaceInUnplacedInbox(place)
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

    /// P2 4348075539: a duplicate pending share must not consume the 50th slot.
    @MainActor
    func testLocalPendingImportDuplicateDoesNotConsumeAFreeSlot() throws {
        let previousAuth = PrivyAuthService.shared.authState
        let owner = "did:privy:dup-cap"
        PrivyAuthService.shared.authState = .authenticated(userId: owner)
        defer { PrivyAuthService.shared.authState = previousAuth }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-dup-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.dup-cap.\(UUID().uuidString)")
        let saved = makeCappedPlaces(49)
        let duplicateOfFirst = saved[0]
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            PendingSharedPlace(
                ownerSubject: owner,
                googlePlaceId: duplicateOfFirst.googlePlaceId,
                name: duplicateOfFirst.name,
                address: duplicateOfFirst.address,
                category: "food",
                latitude: duplicateOfFirst.latitude,
                longitude: duplicateOfFirst.longitude,
                dishes: [],
                savedAt: Date()
            ),
            PendingSharedPlace(
                ownerSubject: owner,
                googlePlaceId: "cap-place-new-50",
                name: "Fiftieth Unique Cafe",
                address: "50 New Street",
                category: "food",
                latitude: 25.5,
                longitude: 121.9,
                dishes: [],
                savedAt: Date()
            )
        ])
        let map = MapViewModel(
            pendingImportService: queue,
            saveLocalVaultService: SaveLocalVaultService(
                overrideVaultURL: directory.appendingPathComponent("vault.json")
            ),
            entitlementTierProvider: { .free },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: false
        )
        map.places = saved

        map.importPendingPlacesForLocalUse()

        XCTAssertEqual(map.places.count, 50)
        XCTAssertTrue(map.places.contains { $0.name == "Fiftieth Unique Cafe" })
        XCTAssertTrue(
            map.reviewCandidates.isEmpty,
            "a matching duplicate must not park the legitimate 50th place"
        )
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
    }

    @MainActor
    func testPendingOfflineParkingFailureRetriesSameModelWithoutConsumingRemoteSlot() async throws {
        let auth = PrivyAuthService.shared
        let original = auth.authState
        let owner = "pending-offline-owner"
        auth.authState = .authenticated(userId: owner)
        defer { auth.authState = original; AnalysisRequestURLProtocol.reset() }
        let rows = makeCappedPlaces(49).enumerated().map { index, place in
            cappedPlaceRowJSON(id: place.id, index: index, name: place.name, googlePlaceID: place.googlePlaceId)
        }.joined(separator: ",")
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/places" { return (200, "[\(rows)]") }
            if request.httpMethod == "POST" { throw URLError(.notConnectedToInternet) }
            return (200, "[]")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.pending-offline-retry.\(UUID())")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let service = SupabaseService(apiBaseURL: "https://pending.test", session: URLSession(configuration: configuration),
            accessTokenProvider: { "fixture-token" })
        let map = MapViewModel(supabaseService: service, pendingImportService: queue, saveLocalVaultService: vault,
            entitlementTierProvider: { .free }, entitlementResolvedProvider: { true }, usesRemotePersistence: true)
        await map.loadPlaces()
        let pending = (50...51).map { number in
            PendingSharedPlace(ownerSubject: owner, googlePlaceId: "pending-\(number)", name: "Pending \(number)",
                address: "\(number) Offline Road", category: "cafe", latitude: 25.8 + Double(number) * 0.001,
                longitude: 121.9, dishes: [], sourceURL: "https://example.com/venue/\(number)",
                sourceText: "Saved capture \(number)", savedAt: Date())
        }
        queue.restorePendingPlaces(pending)
        vault.saveReviewCandidateError = SaveLocalVaultError.storageUnavailable
        map.importPendingPlacesForLocalUse()
        XCTAssertEqual(Place.consolidated(map.places).count, 50)
        XCTAssertTrue(map.places.contains { $0.name == "Pending 50" })
        XCTAssertFalse(map.places.contains { $0.name == "Pending 51" })
        XCTAssertTrue(map.reviewCandidates.isEmpty)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        let retained = queue.consumePendingPlaces(ownerSubject: owner)
        XCTAssertEqual(Set(retained.map(\.deduplicationKey)), Set(pending.map(\.deduplicationKey)))
        XCTAssertEqual(retained.first { $0.name == "Pending 51" }?.sourceText, "Saved capture 51")
        queue.restorePendingPlaces(retained)
        map.syncSavedPlaceLimitCache()
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .allowed, "Local confirmation cannot consume authoritative server slot49")

        vault.saveReviewCandidateError = nil
        map.importPendingPlacesForLocalUse()
        XCTAssertEqual(Place.consolidated(map.places).count, 50)
        let parked = try XCTUnwrap(map.reviewCandidates.first)
        XCTAssertEqual(map.reviewCandidates.count, 1)
        XCTAssertEqual(parked.name, "Pending 51")
        XCTAssertEqual(parked.ownerSubject, owner)
        XCTAssertEqual(parked.googlePlaceId, "pending-51")
        XCTAssertTrue(parked.evidence.joined(separator: " ").contains("https://example.com/venue/51"))
        XCTAssertEqual(try vault.reviewCandidates().map(\.id), [parked.id])
        let stillQueued = queue.consumePendingPlaces(ownerSubject: owner)
        XCTAssertEqual(stillQueued.map(\.name), ["Pending 50"], "Only durably parked51 is removed; local50 still awaits remote sync")
        queue.restorePendingPlaces(stillQueued)
        map.importPendingPlacesForLocalUse()
        XCTAssertEqual(map.reviewCandidates.map(\.id), [parked.id])
        XCTAssertEqual(Place.consolidated(map.places).count, 50)
        map.syncSavedPlaceLimitCache()
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .allowed)
    }

    /// P1 4351218392: a throwing cap park must restore every unfinished input,
    /// including an earlier generic failure, but never replay completed inputs.
    @MainActor
    func testPendingRemoteParkingFailureRestoresUnfinishedBatchInOrder() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        let owner = "pending-parking-owner"
        auth.authState = .authenticated(userId: owner)
        defer {
            auth.authState = originalAuth
            SavePlaceLimitHandoff.testDefaults = originalDefaults
            AnalysisRequestURLProtocol.reset()
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.pending-restore.\(UUID())")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let names = ["Remote Success", "Generic Failure", "Durable Park", "Failed Park", "Untouched Tail"]
        let pending = names.enumerated().map { index, name in
            PendingSharedPlace(ownerSubject: owner, googlePlaceId: "restore-\(index)", name: name,
                address: "\(index) Restore Road", category: "food", latitude: 25 + Double(index) * 0.01,
                longitude: 121, dishes: ["Dish \(index)"], priceRange: "$$",
                sourceURL: "https://example.com/restore/\(index)", sourceText: "Original clue \(index)",
                savedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)))
        }
        queue.restorePendingPlaces(pending)
        var retry = false
        var submittedNames: [String] = []
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "POST", request.url?.path == "/places" {
                let name = try XCTUnwrap(AnalysisRequestURLProtocol.body(request)["name"] as? String)
                submittedNames.append(name)
                if !retry && name == "Generic Failure" { return (500, #"{"error":"temporary_failure"}"#) }
                if name == "Durable Park" || (!retry && name == "Failed Park") {
                    if name == "Failed Park" { vault.saveReviewCandidateError = SaveLocalVaultError.storageUnavailable }
                    return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
                }
                return (201, "{}")
            }
            return (200, "[]")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let service = SupabaseService(apiBaseURL: "https://pending-restore.test",
            session: URLSession(configuration: configuration), accessTokenProvider: { "owner-token" })
        let map = MapViewModel(supabaseService: service, pendingImportService: queue, saveLocalVaultService: vault,
            entitlementTierProvider: { .free }, entitlementResolvedProvider: { true }, usesRemotePersistence: true)

        await map.loadPlaces()

        XCTAssertEqual(submittedNames, Array(names.prefix(4)), "The parking throw must leave the tail unprocessed")
        XCTAssertEqual(try vault.confirmedPlaces(belongingTo: owner).map(\.name), ["Remote Success"])
        XCTAssertEqual(try vault.reviewCandidates(belongingTo: owner).map(\.name), ["Durable Park"])
        let retained = queue.consumePendingPlaces(ownerSubject: owner)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(retained), try encoder.encode([pending[1], pending[3], pending[4]]),
            "Restore the original full payloads in input order, excluding only completed save/park")
        queue.restorePendingPlaces(retained)

        vault.saveReviewCandidateError = nil
        retry = true
        await map.handleSceneDidBecomeActive()
        XCTAssertEqual(submittedNames, Array(names.prefix(4)) + [names[1], names[3], names[4]])
        XCTAssertTrue(queue.consumePendingPlaces(ownerSubject: owner).isEmpty)
        XCTAssertEqual(Set(try vault.confirmedPlaces(belongingTo: owner).map(\.name)),
            Set([names[0], names[1], names[3], names[4]]))
        XCTAssertEqual(try vault.reviewCandidates(belongingTo: owner).map(\.name), [names[2]])
        await map.handleSceneDidBecomeActive()
        XCTAssertEqual(submittedNames.count, 7, "A further activation must not duplicate any completed input")
    }

    @MainActor
    func testPendingRemoteImportAccountSwitchRetainsOriginalOwnerForRetry() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        let owner = "pending-session-owner"
        let otherOwner = "pending-session-other"
        auth.authState = .authenticated(userId: owner)
        defer {
            auth.authState = originalAuth
            SavePlaceLimitHandoff.testDefaults = originalDefaults
            AnalysisRequestURLProtocol.reset()
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.pending-session-restore.\(UUID())")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let pending = (0..<3).map { index in
            PendingSharedPlace(ownerSubject: owner, googlePlaceId: "session-\(index)", name: "Session \(index)",
                address: "\(index) Session Road", category: "food", latitude: 26 + Double(index) * 0.01,
                longitude: 122, dishes: [], sourceText: "Original session clue \(index)",
                savedAt: Date(timeIntervalSince1970: 1_700_000_100 + Double(index)))
        }
        queue.restorePendingPlaces(pending)
        var scopedTokenLookups = 0
        var didSwitch = false
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "POST", request.url?.path == "/places" { return (201, "{}") }
            return (200, "[]")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let service = SupabaseService(apiBaseURL: "https://pending-session.test",
            session: URLSession(configuration: configuration), accessTokenProvider: {
                if let scope = SAVEPendingImportSessionScope.current, scope.owner == owner {
                    await MainActor.run {
                        scopedTokenLookups += 1
                        // Scoped GET, first POST, then suspend the second POST's token lookup.
                        if scopedTokenLookups == 3 {
                            didSwitch = true
                            auth.authState = .authenticated(userId: otherOwner)
                        }
                    }
                }
                return "fixture-token"
            })
        let map = MapViewModel(supabaseService: service, pendingImportService: queue, saveLocalVaultService: vault,
            entitlementTierProvider: { .free }, entitlementResolvedProvider: { true }, usesRemotePersistence: true)

        await map.loadPlaces()
        XCTAssertTrue(didSwitch, "The account switch must occur inside the real import token lookup")
        let writesBeforeRetry = AnalysisRequestURLProtocol.requests.filter { $0.httpMethod == "POST" && $0.url?.path == "/places" }
        XCTAssertEqual(writesBeforeRetry.count, 1)
        XCTAssertTrue(queue.consumePendingPlaces(ownerSubject: otherOwner).isEmpty)
        let retained = queue.consumePendingPlaces(ownerSubject: owner)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(retained), try encoder.encode(Array(pending.dropFirst())))
        queue.restorePendingPlaces(retained)
        await map.handleSceneDidBecomeActive()
        XCTAssertEqual(AnalysisRequestURLProtocol.requests.filter { $0.httpMethod == "POST" && $0.url?.path == "/places" }.count, 1,
            "B's activation must not submit A's retained records")
        XCTAssertTrue(try vault.confirmedPlaces(belongingTo: otherOwner).isEmpty)
        XCTAssertTrue(try vault.reviewCandidates(belongingTo: otherOwner).isEmpty)

        auth.authState = .authenticated(userId: owner)
        await map.handleSceneDidBecomeActive()
        let writes = AnalysisRequestURLProtocol.requests.filter { $0.httpMethod == "POST" && $0.url?.path == "/places" }
        XCTAssertEqual(try writes.map { try AnalysisRequestURLProtocol.body($0)["name"] as? String }, pending.map { Optional($0.name) })
        XCTAssertTrue(try writes.allSatisfy { try AnalysisRequestURLProtocol.body($0)["user_id"] as? String == owner })
        XCTAssertEqual(Set(try vault.confirmedPlaces(belongingTo: owner).map(\.name)), Set(pending.map(\.name)))
        XCTAssertTrue(queue.consumePendingPlaces(ownerSubject: owner).isEmpty)
    }

    /// P2 4348222437: unknown/loading membership must not block a local import.
    @MainActor
    func testLocalPendingImportAllowsWhileEntitlementUnresolved() throws {
        let previousAuth = PrivyAuthService.shared.authState
        let owner = "did:privy:unresolved-tier"
        PrivyAuthService.shared.authState = .authenticated(userId: owner)
        defer { PrivyAuthService.shared.authState = previousAuth }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-unresolved-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.unresolved-tier.\(UUID().uuidString)")
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            PendingSharedPlace(
                ownerSubject: owner,
                googlePlaceId: "cap-place-unresolved",
                name: "Offline Import Cafe",
                address: "1 Loading Street",
                category: "food",
                latitude: 25.6,
                longitude: 121.8,
                dishes: [],
                savedAt: Date()
            )
        ])
        let map = MapViewModel(
            pendingImportService: queue,
            saveLocalVaultService: SaveLocalVaultService(
                overrideVaultURL: directory.appendingPathComponent("vault.json")
            ),
            entitlementTierProvider: { .free },
            entitlementResolvedProvider: { false },
            usesRemotePersistence: false
        )
        map.places = makeCappedPlaces(50)

        map.importPendingPlacesForLocalUse()

        XCTAssertEqual(map.places.count, 51)
        XCTAssertTrue(map.places.contains { $0.name == "Offline Import Cafe" })
        XCTAssertTrue(map.reviewCandidates.isEmpty)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
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
        _ = try map.parkPlaceInUnplacedInbox(makeSocialPlace(name: "Local Park Cafe"))
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
    func testFullCachedCountStillSendsSaveAndParksServerRefusal() async throws {
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
            if request.httpMethod == "POST", request.url?.path == "/places" {
                return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
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
            XCTFail("the server refusal must park the new venue")
        } catch SavePlaceLimitError.parkedInUnplacedInbox {
            XCTAssertEqual(map.places.count, 50)
            XCTAssertEqual(map.reviewCandidates.first?.name, "After Refresh Cafe")
        }
        let writes = AnalysisRequestURLProtocol.requests.filter { $0.httpMethod == "POST" && $0.url?.path == "/places" }
        XCTAssertEqual(writes.count, 1, "A full cached count must still let the server decide")
    }

    @MainActor
    func testStaleLocalVaultDoesNotBlockSaveAfterServerReportsAFreeSlot() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "stale-vault-owner")
        defer { PrivyAuthService.shared.authState = previousAuth }

        let remotePlaces = makeCappedPlaces(49)
        let stalePlace = makeCappedPlaces(1, indexOffset: 49)[0]
        let rows = remotePlaces.enumerated().map { index, place in
            cappedPlaceRowJSON(
                id: place.id,
                index: index,
                name: place.name,
                googlePlaceID: place.googlePlaceId
            )
        }.joined(separator: ",")
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/places" {
                return (200, "[\(rows)]")
            }
            if request.httpMethod == "POST", request.url?.path == "/places" {
                return (201, "{}")
            }
            if request.url?.path.contains("/memory/candidates") == true { return (200, "[]") }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(
            suiteName: "save.place-limit-stale-vault.\(UUID().uuidString)"
        )
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-stale-vault-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        for place in remotePlaces + [stalePlace] {
            _ = try vault.saveConfirmedPlace(place, ownerSubject: "stale-vault-owner")
        }
        let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)

        await map.loadPlaces()
        await map.loadPlaces(force: true)
        XCTAssertEqual(map.places.count, 50, "merge can keep the deleted-elsewhere vault row")
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .allowed)

        let saved = try await map.saveMapCandidateAsPlace(
            SaveMapCandidate(
                id: "cap-stale-vault-50",
                title: "Freed Remote Slot Cafe",
                subtitle: "Taipei",
                latitude: 25.44,
                longitude: 121.84,
                category: .cafe
            )
        )
        XCTAssertEqual(saved.name, "Freed Remote Slot Cafe")
        XCTAssertEqual(map.places.count, 51)
        XCTAssertTrue(map.reviewCandidates.isEmpty)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
    }

    func testAccountSwitchClearsOnlyThePreviousOwnersCapHandoff() throws {
        let suite = "save.owner-cap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SavePlaceLimitHandoff.syncActiveOwner("owner-a", defaults: defaults)
        SavePlaceLimitHandoff.syncCache(tier: .free, savedPlaceCount: 50, defaults: defaults)
        SavePlaceLimitHandoff.markPaywallPending(defaults: defaults, notify: false)
        SavePlaceLimitHandoff.syncActiveOwner("owner-a", defaults: defaults)
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(defaults: defaults), .overFreeLimit)
        XCTAssertTrue(SavePlaceLimitHandoff.consumePaywallPending(defaults: defaults))
        SavePlaceLimitHandoff.markPaywallPending(defaults: defaults, notify: false)
        SavePlaceLimitHandoff.syncActiveOwner("owner-b", defaults: defaults)
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(defaults: defaults), .allowed)
        XCTAssertFalse(SavePlaceLimitHandoff.consumePaywallPending(defaults: defaults))
        SavePlaceLimitHandoff.syncCache(tier: .free, savedPlaceCount: 50, defaults: defaults)
        SavePlaceLimitHandoff.markPaywallPending(defaults: defaults, notify: false)
        SavePlaceLimitHandoff.syncActiveOwner(nil, defaults: defaults)
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(defaults: defaults), .allowed)
        XCTAssertFalse(SavePlaceLimitHandoff.consumePaywallPending(defaults: defaults))
    }

    @MainActor
    func testOfflineMapSaveDoesNotConsumeTheLastRemoteSlot() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        auth.authState = .authenticated(userId: "offline-cap-owner")
        defer { auth.authState = previousAuth }
        let rows = makeCappedPlaces(49).enumerated().map { index, place in
            cappedPlaceRowJSON(id: place.id, index: index, name: place.name, googlePlaceID: place.googlePlaceId)
        }.joined(separator: ",")
        var writes = 0
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/places" { return (200, "[\(rows)]") }
            if request.httpMethod == "POST", request.url?.path == "/places" {
                writes += 1
                if writes == 1 { throw URLError(.notConnectedToInternet) }
                return (201, "{}")
            }
            return (200, "[]")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.offline-cap.\(UUID().uuidString)")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let map = makeRemoteCappedMap(vaultURL: directory.appendingPathComponent("vault.json"))
        await map.loadPlaces()
        _ = try await map.saveMapCandidateAsPlace(SaveMapCandidate(
            id: "offline-cafe", title: "Offline Cafe", subtitle: "Taipei", latitude: 25.8, longitude: 121.9, category: .cafe
        ))
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .allowed)
        _ = try await map.saveMapCandidateAsPlace(SaveMapCandidate(
            id: "online-cafe", title: "Online Cafe", subtitle: "Taipei", latitude: 25.9, longitude: 121.9, category: .cafe
        ))
        XCTAssertEqual(writes, 2, "The failed insert cannot locally refuse the next remote save")
        XCTAssertTrue(map.reviewCandidates.isEmpty)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        map.syncSavedPlaceLimitCache()
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .overFreeLimit, "The successful insert consumes the last remote slot")
    }

    @MainActor
    func testOfflineFallbackCapsTheSecondUniqueSaveButNotADuplicateOrUnresolvedTier() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        defer { auth.authState = previousAuth }
        for resolved in [true, false] {
            auth.authState = .authenticated(userId: "offline-projected-owner")
            let rows = makeCappedPlaces(49).enumerated().map { index, place in
                cappedPlaceRowJSON(id: place.id, index: index, name: place.name, googlePlaceID: place.googlePlaceId)
            }.joined(separator: ",")
            var posts = 0
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { request in
                if request.httpMethod == "GET", request.url?.path == "/places" { return (200, "[\(rows)]") }
                if request.httpMethod == "POST", request.url?.path == "/places" { posts += 1; throw URLError(.notConnectedToInternet) }
                if request.httpMethod == "PATCH", request.url?.path.hasPrefix("/places/") == true { throw URLError(.notConnectedToInternet) }
                return (200, "[]")
            }
            SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.offline-projection.\(UUID().uuidString)")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
            let map = makeRemoteCappedMap(vaultURL: directory.appendingPathComponent("vault.json"), vault: vault, resolved: resolved)
            await map.loadPlaces()
            let first = SaveMapCandidate(id: "offline-50", title: "Offline 50", subtitle: "Taipei", latitude: 25.8, longitude: 121.9, category: .cafe)
            let firstSaved = try await map.saveMapCandidateAsPlace(first)
            XCTAssertEqual(Place.consolidated(map.places).count, 50)
            do {
                _ = try await map.saveMapCandidateAsPlace(first)
                XCTFail("The duplicate's source update is offline")
            } catch is SavePlaceLimitError {
                XCTFail("An offline duplicate cannot consume a new slot or be parked by the cap")
            } catch {}
            XCTAssertEqual(posts, 1, "Duplicate must use the existing row rather than insert another")
            XCTAssertTrue(map.reviewCandidates.isEmpty)
            let next = SaveMapCandidate(id: "offline-51", title: "Offline 51", subtitle: "Taipei", latitude: 25.9, longitude: 121.9, category: .cafe)
            var secondSavedID: UUID?
            do {
                let nextSaved = try await map.saveMapCandidateAsPlace(next)
                secondSavedID = nextSaved.id
                XCTAssertFalse(resolved, "Resolved free tier must park the second new offline venue")
            } catch is SavePlaceLimitError {
                XCTAssertTrue(resolved)
            }
            XCTAssertEqual(posts, 2, "Remote save still gets the first opportunity to decide")
            XCTAssertEqual(Place.consolidated(map.places).count, resolved ? 50 : 51)
            let offlineRows = try vault.confirmedPlaces(belongingTo: "offline-projected-owner")
            let expectedOfflineIDs = Set([firstSaved.id] + (secondSavedID.map { [$0] } ?? []))
            XCTAssertEqual(offlineRows.count, resolved ? 1 : 2, "GET rows populate the map; only successful offline fallbacks are mirrored")
            XCTAssertEqual(Set(offlineRows.map(\.id)), expectedOfflineIDs)
            XCTAssertEqual(secondSavedID == nil, resolved)
            XCTAssertEqual(map.reviewCandidates.map(\.name), resolved ? ["Offline 51"] : [])
            XCTAssertEqual(map.shouldPresentSavedPlaceLimitPaywall, resolved)
            let receipt = SharedPlaceReceipt.embedded(makeShortCodeReceipt(name: "Offline Receipt", code: "unused").payload)
            do {
                _ = try await map.saveSharedPlaceReceipt(receipt)
                XCTAssertFalse(resolved, "Embedded-receipt offline fallback shares the same local boundary")
            } catch is SavePlaceLimitError { XCTAssertTrue(resolved) }
            XCTAssertEqual(posts, 3)
            XCTAssertEqual(Place.consolidated(map.places).count, resolved ? 50 : 52)
            let finalOfflineRows = try vault.confirmedPlaces(belongingTo: "offline-projected-owner")
            let receiptID = receipt.privatePlace(ownerSubject: "offline-projected-owner").id
            XCTAssertEqual(finalOfflineRows.count, resolved ? 1 : 3)
            XCTAssertEqual(Set(finalOfflineRows.map(\.id)), resolved ? expectedOfflineIDs : expectedOfflineIDs.union([receiptID]))
            if resolved {
                XCTAssertEqual(Set(map.reviewCandidates.map(\.name)), Set(["Offline 51", "Offline Receipt"]))
                map.syncSavedPlaceLimitCache()
                XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .allowed, "Offline fallbacks never consume server quota")
            }
        }
    }

    @MainActor
    func testSocialAndListOfflineFallbackHonorProjectedUniqueCapAndRemoteCount() async throws {
        let auth = PrivyAuthService.shared
        let original = auth.authState
        defer { auth.authState = original; AnalysisRequestURLProtocol.reset() }
        for route in ["social", "list"] {
            for (tier, resolved) in [(SaveProTier.free, true), (.free, false), (.pro, true)] {
                auth.authState = .authenticated(userId: "fallback-owner")
                let rows = makeCappedPlaces(49).enumerated().map { index, place in
                    cappedPlaceRowJSON(id: place.id, index: index, name: place.name, googlePlaceID: place.googlePlaceId)
                }.joined(separator: ",")
                var posts = 0
                AnalysisRequestURLProtocol.reset()
                AnalysisRequestURLProtocol.handler = { request in
                    if request.httpMethod == "GET", request.url?.path == "/places" { return (200, "[\(rows)]") }
                    if request.httpMethod == "POST", request.url?.path == "/places" {
                        posts += 1
                        throw URLError(.notConnectedToInternet)
                    }
                    if request.httpMethod == "PATCH" { return (200, "{}") }
                    return (200, "[]")
                }
                SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.offline-surfaces.\(UUID())")
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: directory) }
                let vaultURL = directory.appendingPathComponent("vault.json")
                let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
                let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault, tier: tier, resolved: resolved)
                await map.loadPlaces()
                let fixtures = makeCappedPlaces(2, indexOffset: 80)
                let first = try await saveFallbackFixture(fixtures[0], route: route, map: map)
                XCTAssertEqual(Place.consolidated(map.places).count, 50)
                let duplicate = try await saveFallbackFixture(fixtures[0], route: route, map: map)
                XCTAssertEqual(duplicate.id, first.id)
                XCTAssertEqual(posts, 1, "Duplicate updates the existing row instead of consuming a slot")
                XCTAssertTrue(map.reviewCandidates.isEmpty)
                let capped = tier == .free && resolved
                if route == "social" {
                    map.socialPlaces = [fixtures[1]]
                    map.selectedSocialPlace = fixtures[1]
                }
                do {
                    _ = try await saveFallbackFixture(fixtures[1], route: route, map: map)
                    XCTAssertFalse(capped, "Resolved Free must park the 51st unique offline venue")
                } catch is SavePlaceLimitError { XCTAssertTrue(capped) }
                XCTAssertEqual(posts, 2, "The server still gets first opportunity to decide both new saves")
                XCTAssertEqual(Place.consolidated(map.places).count, capped ? 50 : 51)
                XCTAssertEqual(try vault.confirmedPlaces(belongingTo: "fallback-owner").count, capped ? 1 : 2)
                XCTAssertEqual(map.reviewCandidates.map(\.name), capped ? [fixtures[1].name] : [])
                XCTAssertEqual(try vault.reviewCandidates().map(\.name), capped ? [fixtures[1].name] : [])
                XCTAssertEqual(map.shouldPresentSavedPlaceLimitPaywall, capped)
                if route == "social" {
                    XCTAssertTrue(map.socialPlaces.isEmpty)
                    XCTAssertNil(map.selectedSocialPlace)
                }
                map.syncSavedPlaceLimitCache()
                XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .allowed,
                    "Failed remote inserts must not increment the authoritative49 count")
            }
        }
    }

    @MainActor
    func testSocialAndListFallbackCannotLeakAcrossTokenAccountChange() async throws {
        let auth = PrivyAuthService.shared
        let original = auth.authState
        defer { auth.authState = original; AnalysisRequestURLProtocol.reset() }
        for route in ["social", "list"] {
            for signOut in [false, true] {
                auth.authState = .authenticated(userId: "fallback-owner-a")
                let generation = auth.sessionGeneration
                var scopes: [(generation: Int, owner: String)] = []
                AnalysisRequestURLProtocol.reset()
                AnalysisRequestURLProtocol.handler = { request in
                    if request.httpMethod == "GET" { return (200, "[]") }
                    throw URLError(.notConnectedToInternet)
                }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
                let service = SupabaseService(apiBaseURL: "https://fallback.test", session: URLSession(configuration: configuration),
                    accessTokenProvider: {
                        guard let scope = SAVEPendingImportSessionScope.current else { return "background-token" }
                        await MainActor.run {
                            scopes.append(scope)
                            auth.authState = signOut ? .unauthenticated : .authenticated(userId: "fallback-owner-b")
                        }
                        return "replacement-token"
                    })
                SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.fallback-account.\(UUID())")
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: directory) }
                let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
                let map = MapViewModel(supabaseService: service, saveLocalVaultService: vault,
                    entitlementTierProvider: { .free }, entitlementResolvedProvider: { true }, usesRemotePersistence: true)
                map.places = makeCappedPlaces(50)
                let initialIDs = map.places.map(\.id)
                do {
                    _ = try await saveFallbackFixture(makeCappedPlaces(1, indexOffset: 80)[0], route: route, map: map)
                    XCTFail("Account switch must cancel rather than confirm or park")
                } catch is CancellationError {} catch ReviewCandidateError.sessionChangedAfterCommit {}
                XCTAssertEqual(scopes.count, 1)
                XCTAssertEqual(scopes.first?.owner, "fallback-owner-a")
                XCTAssertEqual(scopes.first?.generation, generation)
                XCTAssertTrue(AnalysisRequestURLProtocol.requests.filter { $0.httpMethod == "POST" && $0.url?.path == "/places" }.isEmpty)
                XCTAssertEqual(map.places.map(\.id), initialIDs)
                XCTAssertTrue(map.reviewCandidates.isEmpty)
                XCTAssertTrue(try vault.confirmedPlaceRecords().isEmpty)
                XCTAssertTrue(try vault.reviewCandidates().isEmpty)
                XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
            }
        }
    }

    @MainActor
    func testSocialAndListFailedOfflineParkingRetainsRetryableSelection() async throws {
        let auth = PrivyAuthService.shared
        let original = auth.authState
        defer { auth.authState = original; AnalysisRequestURLProtocol.reset() }
        auth.authState = .authenticated(userId: "fallback-park-owner")
        for route in ["social", "list"] {
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { request in
                if request.httpMethod == "POST" { throw URLError(.notConnectedToInternet) }
                return (200, "[]")
            }
            SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.fallback-park.\(UUID())")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vaultURL = directory.appendingPathComponent("vault.json")
            let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
            vault.saveReviewCandidateError = SaveLocalVaultError.storageUnavailable
            let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)
            map.places = makeCappedPlaces(50)
            let fixture = makeCappedPlaces(1, indexOffset: 80)[0]
            map.socialPlaces = [fixture]
            map.selectedSocialPlace = fixture
            do {
                _ = try await saveFallbackFixture(fixture, route: route, map: map)
                XCTFail("Failed durable parking cannot report cap completion")
            } catch SaveLocalVaultError.storageUnavailable {}
            XCTAssertEqual(map.places.count, 50)
            XCTAssertTrue(map.reviewCandidates.isEmpty)
            XCTAssertTrue(try vault.reviewCandidates().isEmpty)
            XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
            XCTAssertEqual(map.selectedSocialPlace?.id, fixture.id)
            XCTAssertEqual(map.socialPlaces.map(\.id), [fixture.id])
            vault.saveReviewCandidateError = nil
            do {
                _ = try await saveFallbackFixture(fixture, route: route, map: map)
                XCTFail("Retry should park, not confirm")
            } catch is SavePlaceLimitError {}
            XCTAssertEqual(map.reviewCandidates.map(\.name), [fixture.name])
            XCTAssertEqual(try vault.reviewCandidates().map(\.name), [fixture.name])
            XCTAssertTrue(try vault.confirmedPlaceRecords().isEmpty)
            if route == "social" { XCTAssertNil(map.selectedSocialPlace); XCTAssertTrue(map.socialPlaces.isEmpty) }
        }
    }

    @MainActor
    func testSignedOutRemoteModeFallbacksStillApplyLocalFreeCap() async throws {
        let auth = PrivyAuthService.shared
        let original = auth.authState
        auth.authState = .unauthenticated
        defer { auth.authState = original; AnalysisRequestURLProtocol.reset() }
        for route in ["social", "list", "map", "receipt"] {
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { _ in (200, "[]") }
            SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.signed-out-fallback.\(UUID())")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vaultURL = directory.appendingPathComponent("vault.json")
            let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
            let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)
            // Complete signed-out loading before establishing the visible local snapshot.
            await map.loadPlaces()
            map.places = makeCappedPlaces(50)
            do {
                if route == "map" {
                    _ = try await map.saveMapCandidateAsPlace(SaveMapCandidate(id: "signed-out-new", title: "Signed Out New", subtitle: "Taipei", latitude: 25.9, longitude: 121.9, category: .cafe))
                } else if route == "receipt" {
                    _ = try await map.saveSharedPlaceReceipt(.embedded(makeShortCodeReceipt(name: "Signed Out Receipt", code: "unused").payload))
                } else {
                    _ = try await saveFallbackFixture(makeCappedPlaces(1, indexOffset: 80)[0], route: route, map: map)
                }
                XCTFail("No token path must not bypass the local free cap")
            } catch is SavePlaceLimitError {}
            XCTAssertEqual(Place.consolidated(map.places).count, 50)
            XCTAssertEqual(map.reviewCandidates.count, 1)
            XCTAssertEqual(try vault.reviewCandidates().count, 1)
            XCTAssertTrue(try vault.confirmedPlaceRecords().isEmpty)
            XCTAssertTrue(AnalysisRequestURLProtocol.requests.filter { $0.httpMethod == "POST" }.isEmpty)
        }
    }

    @MainActor
    private func saveFallbackFixture(_ place: Place, route: String, map: MapViewModel) async throws -> Place {
        if route == "social" { return try await map.saveSocialPlaceToMySave(place) }
        return try await map.saveListItemAsPlace(SaveListItem.from(place: place))
    }

    @MainActor
    func testActivationRefreshFreesADeletedRemoteSlotBeforeSaving() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        auth.authState = .authenticated(userId: "activation-cap-owner")
        defer { auth.authState = previousAuth }
        var remoteCount = 50
        let rows = makeCappedPlaces(50).enumerated().map { index, place in
            cappedPlaceRowJSON(id: place.id, index: index, name: place.name, googlePlaceID: place.googlePlaceId)
        }
        var writes = 0
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/places" {
                return (200, "[\(rows.prefix(remoteCount).joined(separator: ","))]")
            }
            if request.httpMethod == "POST", request.url?.path == "/places" { writes += 1; return (201, "{}") }
            return (200, "[]")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.activation-cap.\(UUID().uuidString)")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let map = makeRemoteCappedMap(vaultURL: directory.appendingPathComponent("vault.json"))
        await map.loadPlaces()
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .overFreeLimit)
        remoteCount = 49
        await map.handleSceneDidBecomeActive()
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .allowed)
        _ = try await map.saveMapCandidateAsPlace(SaveMapCandidate(
            id: "activation-cafe", title: "Activation Cafe", subtitle: "Taipei", latitude: 25.8, longitude: 121.9, category: .cafe
        ))
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(map.reviewCandidates.isEmpty)
    }

    @MainActor
    func testStaleFullCountDefersToServerForAllowedSaveAndGenuine51st() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        auth.authState = .authenticated(userId: "stale-server-owner")
        defer { auth.authState = previousAuth }
        let rows = makeCappedPlaces(50).enumerated().map { index, place in
            cappedPlaceRowJSON(id: place.id, index: index, name: place.name, googlePlaceID: place.googlePlaceId)
        }.joined(separator: ",")
        var writes = 0
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/places" { return (200, "[\(rows)]") }
            if request.httpMethod == "POST", request.url?.path == "/places" {
                writes += 1
                // Another device freed a slot after the GET. The next genuinely
                // new venue is refused by the server after that slot is filled.
                return writes == 1 ? (201, "{}") : (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
            }
            return (200, "[]")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.stale-server.\(UUID().uuidString)")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let map = makeRemoteCappedMap(vaultURL: directory.appendingPathComponent("vault.json"))
        await map.loadPlaces()
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .overFreeLimit)
        _ = try await map.saveMapCandidateAsPlace(SaveMapCandidate(
            id: "freed-slot", title: "Freed Slot", subtitle: "Taipei", latitude: 25.8, longitude: 121.9, category: .cafe))
        do {
            _ = try await map.saveMapCandidateAsPlace(SaveMapCandidate(
                id: "genuine-51st", title: "Next New Venue", subtitle: "Taipei", latitude: 25.9, longitude: 121.9, category: .cafe))
            XCTFail("The genuine 51st venue must remain in Review")
        } catch is SavePlaceLimitError {}
        XCTAssertEqual(writes, 2)
        XCTAssertEqual(map.reviewCandidates.map(\.name), ["Next New Venue"])
        XCTAssertFalse(map.places.contains { $0.name == "Next New Venue" })
        XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
    }

    @MainActor
    func testTakeoutCannotSendAfterAccountSwitchDuringTokenLookup() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        defer { auth.authState = previousAuth }
        for switchDuringToken in [false, true] {
            auth.authState = .authenticated(userId: "takeout-token-owner")
            let expectedGeneration = auth.sessionGeneration
            var observedImportScopes: [(generation: Int, owner: String)] = []
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { request in
                if request.httpMethod == "GET" { return (200, "[]") }
                return (201, "{}")
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
            let service = SupabaseService(
                apiBaseURL: "https://analysis.test", session: URLSession(configuration: configuration),
                accessTokenProvider: {
                    // Map initialization also fetches collaborative lists. Only
                    // the suspended Takeout request may trigger this account switch.
                    guard let importing = SAVEPendingImportSessionScope.current else { return "owner-token" }
                    await MainActor.run {
                        observedImportScopes.append(importing)
                        if switchDuringToken { auth.authState = .authenticated(userId: "other-owner") }
                    }
                    return switchDuringToken ? "other-token" : "owner-token"
                }
            )
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let map = MapViewModel(supabaseService: service,
                saveLocalVaultService: SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json")),
                entitlementTierProvider: { .free }, entitlementResolvedProvider: { true }, usesRemotePersistence: true)
            let draft = ImportedPlaceDraft(name: "Token Cafe", address: "1 Token Road", latitude: 25, longitude: 121,
                sourceFile: "Saved Places.json", sourceFormat: "json", reviewState: .readyToSave)
            do {
                let result = try await map.saveImportedPlaces([draft])
                XCTAssertFalse(switchDuringToken)
                XCTAssertEqual(result.saved, 1)
            } catch is CancellationError {
                XCTAssertTrue(switchDuringToken)
            }
            XCTAssertEqual(observedImportScopes.count, 1, "The token lookup must actually run inside the initiating import scope")
            XCTAssertEqual(observedImportScopes.first?.owner, "takeout-token-owner")
            XCTAssertEqual(observedImportScopes.first?.generation, expectedGeneration)
            let writes = AnalysisRequestURLProtocol.requests.filter { $0.httpMethod == "POST" && $0.url?.path == "/places" }
            XCTAssertEqual(writes.count, switchDuringToken ? 0 : 1)
            if !switchDuringToken {
                let request = try XCTUnwrap(writes.first)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owner-token")
                let body = try AnalysisRequestURLProtocol.body(request)
                XCTAssertEqual(body["user_id"] as? String, "takeout-token-owner")
                XCTAssertEqual(body["name"] as? String, "Token Cafe")
            }
            XCTAssertTrue(map.reviewCandidates.isEmpty, "A switched session must not park into the new owner's vault")
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
        _ = try map.parkPlaceInUnplacedInbox(makeSocialPlace(name: "Upgrade Later Cafe"))
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
        _ = try map.parkPlaceInUnplacedInbox(makeSocialPlace(name: "Waiting After Dismiss"))
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
    func testUpdatePlaceMapsStructuredCapAndLeavesOrdinaryFailures() async throws {
        AnalysisRequestURLProtocol.reset()
        defer { AnalysisRequestURLProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let service = SupabaseService(
            apiBaseURL: "https://analysis.test",
            session: URLSession(configuration: configuration),
            accessTokenProvider: { "test-token" }
        )
        let cap = #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#
        for status in [403, 409, 422] {
            AnalysisRequestURLProtocol.handler = { request in
                XCTAssertEqual(request.httpMethod, "PATCH")
                return (status, cap)
            }
            do {
                try await service.updatePlace(Place.mock)
                XCTFail("structured cap \(status) must map to SavePlaceLimitError")
            } catch is SavePlaceLimitError {}
        }
        AnalysisRequestURLProtocol.handler = { _ in (403, "rejected") }
        do {
            try await service.updatePlace(Place.mock)
            XCTFail("ordinary PATCH 403 must stay an auth failure")
        } catch SupabaseError.notAuthenticated {}
        AnalysisRequestURLProtocol.handler = { _ in (500, "down") }
        do {
            try await service.updatePlace(Place.mock)
            XCTFail("PATCH 500 must not look like a cap")
        } catch {
            XCTAssertFalse(error is SavePlaceLimitError)
        }
        AnalysisRequestURLProtocol.handler = { _ in (200, "{}") }
        try await service.updatePlace(Place.mock)
    }

    /// 2026-10-23 P2 ruling (B): when the server rejects a PATCH that would
    /// grow the canonical set, the attempted place is Unplaced and the
    /// saved-50 paywall is the one that appears.
    @MainActor
    func testRulingBPatchRejectParksUnplacedAndShowsSaved50Paywall() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        defer {
            auth.authState = originalAuth
            SavePlaceLimitHandoff.testDefaults = originalDefaults
            AnalysisRequestURLProtocol.reset()
        }
        let owner = "ruling-b-patch-owner"
        auth.authState = .authenticated(userId: owner)
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.ruling-b.\(UUID())")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vaultURL = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        var original = makeCappedPlaces(1)[0]
        original.googlePlaceId = "ruling-b-existing"
        var edited = original
        edited.name = "Ruling B New Venue"
        edited.googlePlaceId = "ruling-b-new-unique"
        var patchCount = 0
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "PATCH", request.url?.path.hasPrefix("/places/") == true {
                patchCount += 1
                return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
            }
            return (200, request.httpMethod == "GET" ? "[]" : "{}")
        }
        let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)
        map.places = [original] + makeCappedPlaces(49, indexOffset: 1)
        map.selectedPlace = original
        do {
            try await map.updatePlace(edited)
            XCTFail("PATCH growth refusal must not keep the attempted identity saved")
        } catch is SavePlaceLimitError {}
        XCTAssertEqual(patchCount, 1)
        XCTAssertEqual(map.places.count, 50)
        XCTAssertEqual(map.places.first(where: { $0.id == original.id })?.googlePlaceId, "ruling-b-existing")
        XCTAssertEqual(map.places.first(where: { $0.id == original.id })?.name, original.name)
        XCTAssertEqual(map.selectedPlace?.id, original.id)
        XCTAssertEqual(map.selectedPlace?.googlePlaceId, "ruling-b-existing")
        let parked = try XCTUnwrap(map.reviewCandidates.first)
        XCTAssertTrue(parked.isUnplacedInbox)
        XCTAssertEqual(parked.name, "Ruling B New Venue")
        XCTAssertEqual(parked.googlePlaceId, "ruling-b-new-unique")
        XCTAssertNotEqual(parked.id, original.id, "Unplaced must not collide with the confirmed stamp")
        XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        let persisted = try XCTUnwrap(vault.reviewCandidates(belongingTo: owner).first)
        XCTAssertEqual(persisted.id, parked.id)
        XCTAssertTrue(persisted.isUnplacedInbox)
        XCTAssertEqual(persisted.name, "Ruling B New Venue")
        XCTAssertTrue(try vault.confirmedPlaces(belongingTo: owner).isEmpty)

        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(content.contains(".onChange(of: mapVM.shouldPresentSavedPlaceLimitPaywall)"))
        XCTAssertTrue(content.contains("presentSavedPlaceLimitPaywall()"))
        XCTAssertTrue(content.contains("SaveProPaywallView(trigger: .savedPlaceLimit)"))
        let paywall = try source(at: "SAV-E/Views/Profile/SaveProPaywallView.swift")
        XCTAssertTrue(paywall.contains("if trigger == .savedPlaceLimit"))
        XCTAssertTrue(paywall.contains("You've saved 50 places. Keep going."))
        XCTAssertTrue(paywall.contains("Free: 50 places"))
        XCTAssertTrue(paywall.contains("paywall.savedNote"))

        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "PATCH", request.url?.path.hasPrefix("/places/") == true {
                return (403, "rejected")
            }
            return (200, request.httpMethod == "GET" ? "[]" : "{}")
        }
        map.acknowledgeSavedPlaceLimitPaywall()
        map.reviewCandidates = []
        var noteOnly = original
        noteOnly.note = "ordinary edit"
        do {
            try await map.updatePlace(noteOnly)
            XCTFail("ordinary PATCH 403 must not look like a cap")
        } catch {
            XCTAssertFalse(error is SavePlaceLimitError)
        }
        XCTAssertTrue(map.reviewCandidates.isEmpty)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        XCTAssertEqual(map.places.first(where: { $0.id == original.id })?.note, original.note)
    }

    /// P1 4365096518: a pending Share merge onto a cached stamp must not park
    /// under that stamp's ID when PATCH hits the cap.
    @MainActor
    func testPendingShareMergeCapParksNewUnplacedIDAndKeepsConfirmedStamp() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        defer {
            auth.authState = originalAuth
            SavePlaceLimitHandoff.testDefaults = originalDefaults
            AnalysisRequestURLProtocol.reset()
        }
        let owner = "pending-merge-cap-owner"
        auth.authState = .authenticated(userId: owner)
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.pending-merge-cap.\(UUID())")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vaultURL = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let stamps = makeCappedPlaces(50)
        let stamp = stamps[0]
        _ = try vault.saveConfirmedPlace(stamp, ownerSubject: owner)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            PendingSharedPlace(
                ownerSubject: owner,
                googlePlaceId: stamp.googlePlaceId,
                name: stamp.name,
                address: stamp.address,
                category: stamp.category.rawValue,
                latitude: stamp.latitude,
                longitude: stamp.longitude,
                dishes: ["New share dish"],
                sourceURL: "https://example.com/share/pending-merge-cap",
                sourceText: "Fresh share capture for the cached stamp",
                savedAt: Date()
            )
        ])
        var patchCount = 0
        let rows = stamps.enumerated().map { index, place in
            cappedPlaceRowJSON(
                id: place.id,
                index: index,
                name: place.name,
                googlePlaceID: place.googlePlaceId
            )
        }.joined(separator: ",")
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/places" {
                return (200, "[\(rows)]")
            }
            if request.httpMethod == "PATCH", request.url?.path.hasPrefix("/places/") == true {
                patchCount += 1
                return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
            }
            return (200, request.httpMethod == "GET" ? "[]" : "{}")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let service = SupabaseService(
            apiBaseURL: "https://pending-merge-cap.test",
            session: URLSession(configuration: configuration),
            accessTokenProvider: { "test-token" }
        )
        let map = MapViewModel(
            supabaseService: service,
            pendingImportService: queue,
            saveLocalVaultService: vault,
            entitlementTierProvider: { .free },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: true
        )
        await map.loadPlaces()
        XCTAssertEqual(patchCount, 1)
        XCTAssertEqual(map.places.count, 50)
        XCTAssertEqual(map.places.first(where: { $0.id == stamp.id })?.googlePlaceId, stamp.googlePlaceId)
        XCTAssertEqual(map.places.first(where: { $0.id == stamp.id })?.name, stamp.name)
        let parked = try XCTUnwrap(map.reviewCandidates.first)
        XCTAssertEqual(map.reviewCandidates.count, 1)
        XCTAssertTrue(parked.isUnplacedInbox)
        XCTAssertEqual(parked.name, stamp.name)
        XCTAssertNotEqual(parked.id, stamp.id)
        XCTAssertEqual(parked.correctionLearningPlaceID, stamp.id)
        XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        XCTAssertTrue(queue.consumePendingPlaces(ownerSubject: owner).isEmpty)

        try await map.refreshReviewCandidates()
        XCTAssertEqual(map.reviewCandidates.count, 1)
        XCTAssertEqual(map.reviewCandidates.first?.id, parked.id)
        XCTAssertTrue(map.reviewCandidates.first?.isUnplacedInbox == true)
        let persisted = try XCTUnwrap(vault.reviewCandidates(belongingTo: owner).first)
        XCTAssertEqual(persisted.id, parked.id)
        XCTAssertTrue(persisted.isUnplacedInbox)
        XCTAssertFalse(try vault.reviewCandidates(belongingTo: owner).contains { $0.id == stamp.id })
        let confirmed = try XCTUnwrap(vault.confirmedPlaces(belongingTo: owner).first { $0.id == stamp.id })
        XCTAssertEqual(confirmed.id, stamp.id)
        XCTAssertEqual(confirmed.googlePlaceId, stamp.googlePlaceId)
        XCTAssertEqual(confirmed.name, stamp.name)
    }

    @MainActor
    func testMatchedReviewMergeCapParksOriginalCandidate() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        defer {
            auth.authState = originalAuth
            SavePlaceLimitHandoff.testDefaults = originalDefaults
            AnalysisRequestURLProtocol.reset()
        }
        let cap = #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#
        for status in [403, 409, 422] {
            let owner = "merge-cap-owner-\(status)"
            auth.authState = .authenticated(userId: owner)
            SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.merge-cap.\(UUID())")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
            let candidate = contextualReviewCandidate(owner: owner, workflow: true)
            try vault.saveReviewCandidate(candidate)
            var existing = makeCappedPlaces(1)[0]
            existing.googlePlaceId = candidate.googlePlaceId
            var patchCount = 0
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { request in
                if request.httpMethod == "PATCH", request.url?.path.hasPrefix("/places/") == true {
                    patchCount += 1
                    return (status, cap)
                }
                return (200, request.httpMethod == "GET" ? "[]" : "{}")
            }
            let map = makeRemoteCappedMap(
                vaultURL: directory.appendingPathComponent("vault.json"),
                vault: vault
            )
            map.places = [existing] + makeCappedPlaces(49, indexOffset: 1)
            map.reviewCandidates = [candidate]
            map.selectedReviewCandidate = candidate
            do {
                _ = try await map.saveReviewCandidateAsPlace(candidate)
                XCTFail("matched PATCH cap \(status) must keep the original Review item")
            } catch is SavePlaceLimitError {}
            XCTAssertEqual(patchCount, 1)
            XCTAssertEqual(map.places.count, 50)
            XCTAssertEqual(map.reviewCandidates.first?.id, candidate.id)
            XCTAssertEqual(map.reviewCandidates.first?.ownerSubject, owner)
            XCTAssertEqual(map.reviewCandidates.first?.captureId, candidate.captureId)
            XCTAssertEqual(map.reviewCandidates.first?.workflowRunId, candidate.workflowRunId)
            XCTAssertTrue(map.reviewCandidates.first?.isUnplacedInbox == true)
            XCTAssertEqual(map.selectedReviewCandidate?.id, candidate.id)
            XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
            let persisted = try XCTUnwrap(vault.reviewCandidates(belongingTo: owner).first)
            XCTAssertEqual(persisted.id, candidate.id)
            XCTAssertEqual(persisted.ownerSubject, owner)
            XCTAssertEqual(persisted.captureId, candidate.captureId)
            XCTAssertEqual(persisted.workflowRunId, candidate.workflowRunId)
            XCTAssertTrue(persisted.isUnplacedInbox)
            XCTAssertTrue(try vault.confirmedPlaces(belongingTo: owner).isEmpty)
        }
    }

    @MainActor
    func testMatchedReviewMergeFailedParkingStaysRetryable() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        defer {
            auth.authState = originalAuth
            SavePlaceLimitHandoff.testDefaults = originalDefaults
            AnalysisRequestURLProtocol.reset()
        }
        let owner = "merge-cap-retry-owner"
        auth.authState = .authenticated(userId: owner)
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.merge-cap-retry.\(UUID())")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vaultURL = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let candidate = contextualReviewCandidate(owner: owner, workflow: false)
        try vault.saveReviewCandidate(candidate)
        let before = try Data(contentsOf: vaultURL)
        vault.saveReviewCandidateError = SaveLocalVaultError.storageUnavailable
        var existing = makeCappedPlaces(1)[0]
        existing.googlePlaceId = candidate.googlePlaceId
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "PATCH", request.url?.path.hasPrefix("/places/") == true {
                return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
            }
            return (200, request.httpMethod == "GET" ? "[]" : "{}")
        }
        let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)
        map.places = [existing]
        map.reviewCandidates = [candidate]
        map.selectedReviewCandidate = candidate
        do {
            _ = try await map.saveReviewCandidateAsPlace(candidate)
            XCTFail("storage failure cannot report a parked merge result")
        } catch SaveLocalVaultError.storageUnavailable {}
        XCTAssertEqual(map.reviewCandidates, [candidate])
        XCTAssertEqual(map.selectedReviewCandidate, candidate)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        XCTAssertFalse(SavePlaceLimitHandoff.consumePaywallPending())
        XCTAssertEqual(try Data(contentsOf: vaultURL), before)
        vault.saveReviewCandidateError = nil
        do {
            _ = try await map.saveReviewCandidateAsPlace(candidate)
            XCTFail("retry must still see the PATCH cap")
        } catch is SavePlaceLimitError {}
        XCTAssertTrue(map.reviewCandidates.first?.isUnplacedInbox == true)
        XCTAssertEqual(map.reviewCandidates.first?.id, candidate.id)
        XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        XCTAssertEqual(try vault.reviewCandidates(belongingTo: owner).first?.captureId, candidate.captureId)
    }

    @MainActor
    func testMatchedReviewMergeCapAfterAccountSwitchDoesNotParkForNewOwner() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        defer {
            auth.authState = originalAuth
            SavePlaceLimitHandoff.testDefaults = originalDefaults
            AnalysisRequestURLProtocol.reset()
        }
        let owner = "merge-cap-session-A"
        auth.authState = .authenticated(userId: owner)
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.merge-cap-session.\(UUID())")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let candidate = contextualReviewCandidate(owner: owner, workflow: true)
        try vault.saveReviewCandidate(candidate)
        let before = try Data(contentsOf: directory.appendingPathComponent("vault.json"))
        var existing = makeCappedPlaces(1)[0]
        existing.googlePlaceId = candidate.googlePlaceId
        let arrived = expectation(description: "matched PATCH cap response in flight")
        let release = DispatchSemaphore(value: 0)
        var hold = true
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "PATCH", request.url?.path.hasPrefix("/places/") == true {
                if hold { arrived.fulfill(); _ = release.wait(timeout: .now() + 10) }
                return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
            }
            return (200, request.httpMethod == "GET" ? "[]" : "{}")
        }
        let map = makeRemoteCappedMap(
            vaultURL: directory.appendingPathComponent("vault.json"),
            vault: vault
        )
        map.places = [existing]
        map.reviewCandidates = [candidate]
        let task = Task { try await map.saveReviewCandidateAsPlace(candidate) }
        await fulfillment(of: [arrived], timeout: 5)
        auth.authState = .authenticated(userId: "merge-cap-session-B")
        release.signal()
        do {
            _ = try await task.value
            XCTFail("the old session must stop before parking")
        } catch is CancellationError {}
        XCTAssertEqual(map.reviewCandidates, [candidate])
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        XCTAssertTrue(try vault.reviewCandidates(belongingTo: "merge-cap-session-B").isEmpty)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("vault.json")), before)
        auth.authState = .authenticated(userId: owner)
        hold = false
        do {
            _ = try await map.saveReviewCandidateAsPlace(candidate)
            XCTFail("still capped for A")
        } catch is SavePlaceLimitError {}
        XCTAssertTrue(map.reviewCandidates.first?.isUnplacedInbox == true)
        XCTAssertEqual(try vault.reviewCandidates(belongingTo: owner).first?.workflowRunId, candidate.workflowRunId)
    }

    @MainActor
    func testMatchedReviewMergeOrdinaryFailureDoesNotPark() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        defer { auth.authState = originalAuth; AnalysisRequestURLProtocol.reset() }
        let owner = "merge-ordinary-403-owner"
        auth.authState = .authenticated(userId: owner)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let candidate = contextualReviewCandidate(owner: owner, workflow: false)
        try vault.saveReviewCandidate(candidate)
        var existing = makeCappedPlaces(1)[0]
        existing.googlePlaceId = candidate.googlePlaceId
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "PATCH", request.url?.path.hasPrefix("/places/") == true {
                return (403, "rejected")
            }
            return (200, request.httpMethod == "GET" ? "[]" : "{}")
        }
        let map = makeRemoteCappedMap(
            vaultURL: directory.appendingPathComponent("vault.json"),
            vault: vault
        )
        map.places = [existing]
        map.reviewCandidates = [candidate]
        do {
            _ = try await map.saveReviewCandidateAsPlace(candidate)
            XCTFail("ordinary PATCH 403 must surface, not park")
        } catch {
            XCTAssertFalse(error is SavePlaceLimitError)
        }
        XCTAssertEqual(map.reviewCandidates, [candidate])
        XCTAssertFalse(map.reviewCandidates.first?.isUnplacedInbox == true)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        XCTAssertEqual(try vault.reviewCandidates(belongingTo: owner).first?.id, candidate.id)
    }

    @MainActor
    func testMatchedMapSocialAndListMergeCapParksIncomingPlace() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        defer {
            auth.authState = originalAuth
            SavePlaceLimitHandoff.testDefaults = originalDefaults
            AnalysisRequestURLProtocol.reset()
        }
        let owner = "merge-adjacent-owner"
        auth.authState = .authenticated(userId: owner)
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.merge-adjacent.\(UUID())")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var existing = makeCappedPlaces(1)[0]
        existing.name = "Harbor Cafe"
        existing.address = "0 Server Road"
        existing.latitude = 25.0
        existing.longitude = 121.0
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "PATCH", request.url?.path.hasPrefix("/places/") == true {
                return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
            }
            return (200, request.httpMethod == "GET" ? "[]" : "{}")
        }
        let map = makeRemoteCappedMap(
            vaultURL: directory.appendingPathComponent("vault.json"),
            vault: vault
        )
        map.places = [existing]

        let mapCandidate = SaveMapCandidate(
            id: "merge-cap-map",
            title: existing.name,
            subtitle: existing.address,
            latitude: existing.latitude,
            longitude: existing.longitude,
            category: existing.category
        )
        map.mapCandidates = [mapCandidate]
        do {
            _ = try await map.saveMapCandidateAsPlace(mapCandidate)
            XCTFail("matched map-candidate PATCH cap must park")
        } catch is SavePlaceLimitError {}
        XCTAssertEqual(map.places.count, 1)
        XCTAssertTrue(map.mapCandidates.isEmpty)
        XCTAssertEqual(map.reviewCandidates.first?.name, existing.name)
        XCTAssertTrue(map.reviewCandidates.first?.isUnplacedInbox == true)
        XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
        map.acknowledgeSavedPlaceLimitPaywall()
        map.reviewCandidates = []

        let social = Place(
            id: UUID(),
            name: existing.name,
            address: existing.address,
            latitude: existing.latitude,
            longitude: existing.longitude,
            googlePlaceId: existing.googlePlaceId,
            category: existing.category,
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
        map.socialPlaces = [social]
        do {
            _ = try await map.saveSocialPlaceToMySave(social)
            XCTFail("matched social PATCH cap must park")
        } catch is SavePlaceLimitError {}
        XCTAssertEqual(map.places.count, 1)
        XCTAssertTrue(map.socialPlaces.isEmpty)
        XCTAssertEqual(map.reviewCandidates.first?.name, existing.name)
        XCTAssertTrue(map.reviewCandidates.first?.isUnplacedInbox == true)
        map.acknowledgeSavedPlaceLimitPaywall()
        map.reviewCandidates = []

        let listItem = SaveListItem.from(place: existing)
        do {
            _ = try await map.saveListItemAsPlace(listItem)
            XCTFail("matched list PATCH cap must park")
        } catch is SavePlaceLimitError {}
        XCTAssertEqual(map.places.count, 1)
        XCTAssertEqual(map.reviewCandidates.first?.name, existing.name)
        XCTAssertTrue(map.reviewCandidates.first?.isUnplacedInbox == true)
    }

    func testMatchedStampMergeParksStructuredCapInSource() throws {
        let map = try source(at: "SAV-E/ViewModels/MapViewModel.swift")
        let supabase = try source(at: "SAV-E/Services/SupabaseService.swift")
        let updateStart = try XCTUnwrap(supabase.range(of: "func updatePlace(_ place: Place, previous: Place? = nil)"))
        let updateRemainder = supabase[updateStart.lowerBound...]
        let updateEnd = try XCTUnwrap(updateRemainder.range(of: "func deletePlace(_ placeId: UUID)"))
        let update = String(updateRemainder[..<updateEnd.lowerBound])
        XCTAssertTrue(update.contains("method: \"PATCH\""))
        XCTAssertTrue(
            update.contains("throw mappedSavedPlaceLimit(error)"),
            "P2 4353381364: PATCH growth refusals must use the same structured-cap mapper as POST"
        )

        XCTAssertTrue(map.contains("parkIfLimited: () throws -> Void"))
        XCTAssertTrue(
            map.contains("try await mergeSavedSources(place, into: match) {\n                try parkExistingReviewCandidate("),
            "confirming a matching Review candidate must park the original item on PATCH cap"
        )
        XCTAssertTrue(
            map.contains("try await mergeSavedSources(incoming, into: match) {\n                try parkExistingReviewCandidate("),
            "exact-search merge onto an existing stamp must park the original clue on PATCH cap"
        )
        let chooseStampStart = try XCTUnwrap(map.range(of: "func resolveExactSearchClue(toSavedPlace place: Place)"))
        let chooseStampEnd = try XCTUnwrap(map.range(of: "func completeExactSearchMergeOntoExistingStamp"))
        let chooseStamp = String(map[chooseStampStart.lowerBound..<chooseStampEnd.lowerBound])
        XCTAssertTrue(
            chooseStamp.contains("try await supabaseService.updatePlace(associated, previous: place)"),
            "choosing a saved stamp still PATCHes attached clue evidence"
        )
        XCTAssertTrue(
            chooseStamp.contains("if error is SavePlaceLimitError {\n                do {\n                    try parkExistingReviewCandidate("),
            "choosing a saved stamp must park the original clue when that PATCH hits the cap"
        )
        XCTAssertTrue(
            map.contains("try await mergeSavedSources(place, into: match) {\n                    if try parkIfServerSavedPlaceLimit("),
            "map-candidate merge must park the incoming place on PATCH cap"
        )
        XCTAssertTrue(
            map.contains("try await mergeSavedSources(socialPlace, into: match) {\n                if try parkIfServerSavedPlaceLimit("),
            "social merge must park the incoming place on PATCH cap"
        )
        XCTAssertTrue(
            map.contains("try await mergeSavedSources(place, into: match) {\n                _ = try parkIfServerSavedPlaceLimit("),
            "friend-share and list merges must park the incoming place on PATCH cap"
        )
        let offlineStart = try XCTUnwrap(map.range(of: "if !usesRemotePersistence {\n            let place = Place.from(candidate, refinedMatch: nil, nameOverride: nameOverride)"))
        let offline = String(map[offlineStart.lowerBound...].prefix(700))
        XCTAssertTrue(
            offline.contains("let existing = try await mergeSavedSources(place, into: match)"),
            "local-only Review merge never hits the PATCH guard"
        )
        XCTAssertFalse(
            offline.contains("parkIfLimited"),
            "do not wrap the offline merge in the PATCH-cap parking helper"
        )

        let userEditStart = try XCTUnwrap(map.range(of: "func updatePlace(_ place: Place) async throws"))
        let userEditEnd = try XCTUnwrap(map[userEditStart.lowerBound...].range(of: "func discoverRelatedSources("))
        let userEdit = String(map[userEditStart.lowerBound..<userEditEnd.lowerBound])
        XCTAssertTrue(
            userEdit.contains("if error is SavePlaceLimitError"),
            "2026-10-23 P2 ruling (B): user-edit PATCH growth refusals park Unplaced"
        )
        XCTAssertTrue(
            userEdit.contains("try parkPlaceAfterPatchCap(place, startedBy: owner, generation: generation)"),
            "ruling B parks the attempted identity before rethrowing the cap"
        )
        XCTAssertTrue(map.contains("private func parkPlaceAfterPatchCap("))
        XCTAssertTrue(
            userEdit.contains("try parkPlaceInUnplacedInbox(place)"),
            "ruling B reuses the shared Unplaced park so stamp IDs are remapped"
        )
        let inboxStart = try XCTUnwrap(map.range(of: "func parkPlaceInUnplacedInbox(_ place: Place, requestPaywall: Bool = true)"))
        let inboxEnd = try XCTUnwrap(map[inboxStart.lowerBound...].range(of: "private func parkIfServerSavedPlaceLimit("))
        let inbox = String(map[inboxStart.lowerBound..<inboxEnd.lowerBound])
        XCTAssertTrue(
            inbox.contains("candidate.id = UUID()"),
            "P1 4365096518: pending merges must not park under the confirmed stamp ID"
        )
        XCTAssertTrue(
            inbox.contains("candidate.correctionLearningPlaceID = confirmedID"),
            "keep a reference to the confirmed stamp after minting a new Unplaced ID"
        )
        XCTAssertTrue(map.contains("requestSavedPlaceLimitPaywall()"))
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
        var savedIDs: [UUID] = []
        store.saveSharedPost = { id in
            savedIDs.append(id)
            throw SavePlaceLimitError.parkedInUnplacedInbox
        }
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

        store.fetchSharedPostForParking = { _ in post }
        let outcome = try await store.save(post)
        XCTAssertEqual(savedIDs, [post.id], "the live post must be revalidated before parking")
        XCTAssertEqual(outcome, .parkedAtFreeLimit)
        XCTAssertEqual(parked?.name, "Harbor Town")
        XCTAssertNotEqual(
            parked?.id,
            post.id,
            "author places.id must not become the recipient Map Stamp id"
        )
        XCTAssertEqual(parked?.latitude, 25.033)
        XCTAssertEqual(parked?.longitude, 121.565)
        XCTAssertEqual(parked?.googlePlaceId, "ChIJcap-harbor")
        XCTAssertNil(parked?.note)
        XCTAssertNil(parked?.rating)
        XCTAssertNil(parked?.recommender)
        XCTAssertTrue(parked?.sourceEvidence.isEmpty ?? false)
    }

    @MainActor
    func testSharedPostsStoreSaveWithdrawnDoesNotPark() async throws {
        let store = SharedPostsStore()
        var savedIDs: [UUID] = []
        store.saveSharedPost = { id in
            savedIDs.append(id)
            throw SupabaseError.recordNotFound
        }
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

        do {
            _ = try await store.save(post)
            XCTFail("a withdrawn shared post must not become a Map Stamp")
        } catch SupabaseError.recordNotFound {
            XCTAssertEqual(savedIDs, [post.id])
            XCTAssertNil(parked, "withdrawn or inaccessible posts must not park in Unplaced")
        }
    }

    func testLocalReviewCandidatesAreScopedToTheActiveAccountInSource() throws {
        let map = try source(at: "SAV-E/ViewModels/MapViewModel.swift")
        XCTAssertTrue(map.contains("localVaultRecordBelongsToActiveAccount"))
        XCTAssertTrue(
            map.contains("ownerSubject: authService.currentUserId"),
            "parked Unplaced must stamp the signed-in account"
        )
        XCTAssertTrue(map.contains("SaveVaultOwnerScope.belongsToActiveAccount"))
        let policy = try source(at: "SAV-EShared/SAVEProAccessPolicy.swift")
        XCTAssertTrue(
            policy.contains("return ownerSubject == currentUserId"),
            "signed-in refresh must hide another account's vault rows"
        )
        let vault = try source(at: "SAV-E/Services/SaveLocalVaultService.swift")
        let intent = try source(at: "SAV-E/Intents/SavePlaceFromURLIntent.swift")
        let share = try source(at: "SAV-EShareExtension/ShareViewController.swift")
        XCTAssertTrue(vault.contains("existing.ownerSubject == incoming.ownerSubject"))
        XCTAssertTrue(vault.contains("ownerSubject: candidate.ownerSubject"))
        XCTAssertTrue(vault.contains("func saveSourceOnly(url: URL, note: String? = nil, ownerSubject: String? = nil)"))
        XCTAssertTrue(vault.contains("func saveConfirmedPlace(_ incoming: Place, ownerSubject: String? = nil)"))
        XCTAssertTrue(vault.contains("func confirmedPlaceRecords"))
        XCTAssertTrue(
            vault.contains("func deleteRecords(belongingTo ownerSubject: String)"),
            "P1 4347594680: account deletion needs an owner-scoped vault purge"
        )
        XCTAssertFalse(
            vault.contains("func claimOwnerlessRecords"),
            "auto-claiming ownerless rows assigns private notes to whoever signs in first"
        )
        XCTAssertFalse(map.contains("claimOwnerlessRecords"))
        XCTAssertTrue(
            map.contains("Remote fetch remains the upgrade path"),
            "ownerless pre-upgrade rows stay hidden while signed in"
        )
        XCTAssertTrue(intent.contains("let startedBy = PrivyAuthService.shared.currentUserId"))
        XCTAssertTrue(intent.contains("let generation = PrivyAuthService.shared.sessionGeneration"))
        XCTAssertTrue(intent.contains("try Self.ensureInitiatingSession(startedBy, generation)"))
        XCTAssertTrue(
            intent.contains("ownerSubject: startedBy"),
            "a late URL-intent write must keep the initiating owner"
        )
        XCTAssertFalse(
            intent.contains("ownerSubject: PrivyAuthService.shared.currentUserId"),
            "do not re-read the signed-in account after the analysis await"
        )
        XCTAssertTrue(share.contains("cachedActiveOwner: SavePlaceLimitHandoff.cachedActiveOwner()"))
        XCTAssertTrue(
            share.contains("ownerSubject: shareOwnerSubject"),
            "locally parsed over-cap shares must keep the captured active owner"
        )
        XCTAssertFalse(
            share.contains("ownerSubject: analysisCredential?.ownerSubject,"),
            "do not persist an ownerless share when only analysisCredential is missing"
        )
        XCTAssertTrue(
            share.contains("func bindShareSessionOwnerIfNeeded"),
            "capture the share owner before attachment and analysis awaits"
        )
        XCTAssertTrue(
            share.contains("try snapshot.validate("),
            "a late share write must not stamp the next signed-in account"
        )
        XCTAssertTrue(
            share.contains("try snapshot.ownerForNewItem(existingOwner: candidate.ownerSubject)"),
            "screenshot and Maps-list Review candidates must stamp the owner at persist"
        )
        XCTAssertTrue(share.contains("appendPendingItems(stamped"))
        for purpose in ["append source-only memory", "append pending queue"] {
            let accessor = "purpose: \"\(purpose)\") { coordinatedURL in\n            guard shareSessionStillMatches(requireAnalysisCredential: false)"
            XCTAssertTrue(share.contains(accessor),
                "Check the current account inside the file coordinator accessor, after any wait")
        }
        XCTAssertTrue(share.contains("guard shareSessionStillMatches(requireAnalysisCredential: !sourceFallback) else { return }"),
            "Keeping a source must still validate the account even when its analysis token is unusable")
        XCTAssertTrue(map.contains("belongingTo: authService.currentUserId"))
        XCTAssertTrue(map.contains("saveConfirmedPlace(place, ownerSubject: userId)"))
        XCTAssertTrue(
            map.contains("let startedBy = authService.currentUserId"),
            "P1 4346852374: capture the initiating owner before fetchPlaces/deletePlace await"
        )
        XCTAssertTrue(
            map.contains("removeConfirmedPlace(place, belongingTo: startedBy)"),
            "P1 4346852374: Delete uses the owner captured before the network await"
        )
        XCTAssertTrue(
            map.contains("saveConfirmedPlace(place, ownerSubject: startedBy)"),
            "P1 4346852374: failed delete must restore the initiating owner's row"
        )
        XCTAssertTrue(
            map.contains("remainingAuthoritativeCount = Place.consolidated("),
            "P2 4347594688: post-delete cap uses the owner-scoped remote remainder, not places.count"
        )
        XCTAssertFalse(
            map.contains("alignAuthoritativeSavedPlaceCountWithPlaces"),
            "P2 4347594688: assigning places.count after delete keeps a stale vault row at 50"
        )
        let memoryInspector = try source(at: "SAV-E/Views/Profile/SaveMemoryDebugView.swift")
        XCTAssertTrue(memoryInspector.contains("SaveMemoryInspector.records"))
        XCTAssertTrue(
            memoryInspector.contains("belongingTo: PrivyAuthService.shared.currentUserId"),
            "P1 4347594673: Memory inspector must not show another account's vault rows"
        )
        XCTAssertFalse(
            memoryInspector.contains("recentRecords(limit: 50)"),
            "unscoped recentRecords(limit: 50) is the inspector leak Codex named"
        )
        let profile = try source(at: "SAV-E/ViewModels/ProfileViewModel.swift")
        // Owner isolation and legacy cleanup are exercised through real vaults
        // by the ProfileAvatarStoreTests account-deletion scenarios.
        XCTAssertFalse(
            profile.contains("deleteAllRecords()"),
            "deleteAllRecords wipes every account on this device"
        )
        // Pending-import deduplication and the projected local cap are exercised by
        // testPendingOfflineParkingFailureRetriesSameModelWithoutConsumingRemoteSlot.
        // Keep this source check independent of temporary variable spelling.
        XCTAssertFalse(
            map.contains("if isNewKey { importedPlaces.append(place) }"),
            "P2 4348075539: a matching duplicate must not inflate importedPlaces"
        )
        XCTAssertTrue(
            map.contains("if entitlementResolvedProvider(),"),
            "P2 4348222437: unresolved membership must fail open on local pending import"
        )
        XCTAssertTrue(
            map.contains("authService.currentUserId == startedBy,\n               authService.sessionGeneration == generation {\n                places = previousPlaces"),
            "deletePlace catch must not restore A's list onto B after a mid-call switch"
        )
        XCTAssertTrue(
            map.contains("saveConfirmedPlace(place, ownerSubject: authService.currentUserId)"),
            "local-only confirm must stamp the active owner so a signed-in reload keeps the Map Stamp"
        )
        let privy = try source(at: "SAV-E/Services/PrivyAuthService.swift")
        XCTAssertTrue(
            privy.contains("saveConfirmedPlace(place, ownerSubject: ReviewDemo.userId)"),
            "reviewer-demo Map Stamps must stay visible to the demo owner"
        )
        XCTAssertTrue(map.contains("try persistParkedReviewCandidate(candidate)"))
        XCTAssertTrue(
            map.contains("SAVEPendingImportSessionScope.$current.withValue((importGeneration, userId))"),
            "Takeout must retain the initiating session across token-provider suspension"
        )
        XCTAssertTrue(map.contains("try ensureConfirmationSession(userId, importGeneration)"))
        XCTAssertTrue(map.contains("startedBy userId: String?"))
        XCTAssertTrue(
            map.contains("throw ReviewCandidateError.sessionChangedAfterCommit"),
            "a late vault mirror must not stamp the next signed-in account"
        )
        XCTAssertTrue(
            map.contains("try ensureConfirmationSession(userId, generation)"),
            "a late over-limit must not park into a new account"
        )
        XCTAssertTrue(map.contains("startedBy userId: String?"))
        let shortCodeStart = try XCTUnwrap(map.range(of: "A verified short-code receipt is server-owned"))
        let shortCodeRemainder = String(map[shortCodeStart.lowerBound...])
        let shortCodeEnd = try XCTUnwrap(shortCodeRemainder.range(of: "if let match = existingSavedPlace"))
        let shortCode = String(shortCodeRemainder[..<shortCodeEnd.lowerBound])
        XCTAssertFalse(
            shortCode.contains("isOverFreeSavedPlaceLimit"),
            "expired short-code receipts must reach the server before parking"
        )
        XCTAssertTrue(shortCode.contains("saveFriendSharedPlace"))
        XCTAssertTrue(shortCode.contains("parkIfServerSavedPlaceLimit"))
    }

    func testSharedPostOverLimitParkRechecksTheInitiatingAccount() throws {
        let store = try source(at: "SAV-E/ViewModels/SharedPostsStore.swift")
        let start = try XCTUnwrap(store.range(of: "func save(_ post: SharedPlacePost)"))
        let end = try XCTUnwrap(store.range(of: "func acknowledgeSavedPlaceLimitPaywall()"))
        let save = String(store[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(
            save.contains("isOverFreeLimit"),
            "a cached local cap must not park a withdrawn post before /v0/shared-posts/:id/save"
        )
        let catchStart = try XCTUnwrap(save.range(of: "} catch {"))
        let beforeCatch = String(save[..<catchStart.lowerBound])
        XCTAssertTrue(
            beforeCatch.contains("saveSharedPost"),
            "the live post must be revalidated before parking"
        )
        let catchBody = String(save[catchStart.lowerBound...])
        XCTAssertTrue(
            catchBody.contains("account == PrivyAuthService.shared.currentUserId"),
            "a late over-limit response must not park into a new account"
        )
        XCTAssertTrue(catchBody.contains("parkOverLimitPlace"))
        XCTAssertTrue(catchBody.contains("Task.isCancelled"))
        XCTAssertTrue(catchBody.contains("SavePlaceLimitError"))
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
        XCTAssertNotEqual(
            parked.id,
            post.id,
            "author places.id must not become the recipient Map Stamp id"
        )
        XCTAssertEqual(parked.latitude, 25.033)
        XCTAssertEqual(parked.longitude, 121.565)
        XCTAssertEqual(parked.googlePlaceId, "ChIJcap-harbor")
        XCTAssertNil(parked.note)
        XCTAssertNil(parked.rating)
        XCTAssertNil(parked.recommender)
        XCTAssertTrue(parked.sourceEvidence.isEmpty)
    }

    @MainActor
    func testSharedPostParkingUsesLiveVenueAndStableRecipientIdentity() async throws {
        let postJSON = """
        {"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","name":"Current cafe","address":"Current road",
         "latitude":31.23,"longitude":121.47,"coordinate_system":"GCJ-02","location_provider":"amap",
         "provider_place_id":"amap-cafe","provider_map_url":"https://uri.amap.com/marker?position=121.47,31.23",
         "category":"cafe","status":"visited","stars":5,"caption":"Revocable caption",
         "shared_at":"2026-10-01","author_id":"author","author_name":"Author","visible_to_followers":true}
        """
        let live = try JSONDecoder().decode(SharedPlacePost.self, from: Data(postJSON.utf8))
        let staleJSON = postJSON.replacingOccurrences(of: "Current cafe", with: "Stale cafe")
        let stale = try JSONDecoder().decode(SharedPlacePost.self, from: Data(staleJSON.utf8))
        let editedJSON = postJSON.replacingOccurrences(of: "amap-cafe", with: "amap-corrected")
            .replacingOccurrences(of: "31.23", with: "31.24")
            .replacingOccurrences(of: "121.47", with: "121.48")
        let edited = try JSONDecoder().decode(SharedPlacePost.self, from: Data(editedJSON.utf8))
        var currentLive = live
        let store = SharedPostsStore()
        store.saveSharedPost = { _ in throw SavePlaceLimitError.parkedInUnplacedInbox }
        store.fetchSharedPostForParking = { id in XCTAssertEqual(id, live.id); return currentLive }
        var parked: [Place] = []
        store.parkOverLimitPlace = { place in
            parked.append(place)
            return PlaceReviewCandidate.unplacedInboxItem(from: place)
        }
        _ = try await store.save(stale)
        currentLive = edited
        _ = try await store.save(stale)
        XCTAssertEqual(parked.count, 2)
        XCTAssertEqual(parked[0].id, parked[1].id)
        XCTAssertEqual(parked[0].name, "Current cafe")
        XCTAssertEqual(parked[0].resolvedCoordinateSystem, .gcj02)
        XCTAssertEqual(parked[0].providerPlaceId, "amap-cafe")
        XCTAssertFalse(parked[0].isMapKitMappable)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        _ = try vault.saveReviewCandidate(PlaceReviewCandidate.unplacedInboxItem(from: parked[0], ownerSubject: "a"))
        _ = try vault.saveReviewCandidate(PlaceReviewCandidate.unplacedInboxItem(from: parked[1], ownerSubject: "a"))
        let reloadedVault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        XCTAssertEqual(try reloadedVault.reviewCandidates().count, 1)
        let restored = try XCTUnwrap(reloadedVault.reviewCandidates().first)
        XCTAssertNil(restored.latitude, "GCJ-02 coordinates must never be promoted as WGS84")
        let confirmed = Place.from(restored)
        XCTAssertEqual(confirmed.resolvedCoordinateSystem, .gcj02)
        XCTAssertEqual(confirmed.providerPlaceId, "amap-corrected")
        XCTAssertEqual(confirmed.latitude, 31.24)
        XCTAssertEqual(confirmed.longitude, 121.48)
        XCTAssertTrue(confirmed.providerMapUrl?.contains("121.48,31.24") == true)
        XCTAssertFalse(restored.evidence.contains { $0.contains("amap-cafe") || $0.contains("31.23") })
        // A later WGS84 projection must also retire the prior active Amap fields.
        var wgsPlace = parked[1]
        wgsPlace.coordinateSystem = .wgs84
        wgsPlace.locationProvider = nil
        wgsPlace.providerPlaceId = nil
        wgsPlace.providerMapUrl = nil
        _ = try vault.saveReviewCandidate(PlaceReviewCandidate.unplacedInboxItem(from: wgsPlace, ownerSubject: "a"))
        let wgsCandidate = try XCTUnwrap(reloadedVault.reviewCandidates().first)
        XCTAssertNil(wgsCandidate.providerLocation)
        XCTAssertEqual(Place.from(wgsCandidate).resolvedCoordinateSystem, .wgs84)
        XCTAssertNil(parked[0].note)
        XCTAssertNil(parked[0].rating)
        XCTAssertNotEqual(live.asUnplacedPlace(ownerSubject: "a").id, live.asUnplacedPlace(ownerSubject: "b").id)
        store.fetchSharedPostForParking = { _ in throw SupabaseError.recordNotFound }
        do {
            _ = try await store.save(stale)
            XCTFail("Revoked access must not park the cached post")
        } catch SupabaseError.recordNotFound {}
        XCTAssertEqual(parked.count, 2)
    }

    @MainActor
    func testExactSearchCapDurablyParksOriginalClueAcrossLocalRemoteAndFallbackPaths() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        let previousDefaults = SavePlaceLimitHandoff.testDefaults
        defer { auth.authState = previousAuth; SavePlaceLimitHandoff.testDefaults = previousDefaults; AnalysisRequestURLProtocol.reset() }
        for route in ["local-precheck", "remote-cap", "local-fallback"] {
            for failWriteFirst in [false, true] {
                let owner: String? = route == "local-fallback" ? nil : "exact-owner"
                auth.authState = owner.map { .authenticated(userId: $0) } ?? .unauthenticated
                SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.exact-cap.\(UUID())")
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: directory) }
                let url = directory.appendingPathComponent("vault.json")
                let vault = SaveLocalVaultService(overrideVaultURL: url)
                var clue = contextualReviewCandidate(owner: owner ?? "unused", workflow: true)
                clue.ownerSubject = owner
                clue.latitude = nil
                clue.longitude = nil
                try vault.saveReviewCandidate(clue)
                let before = try Data(contentsOf: url)
                AnalysisRequestURLProtocol.reset()
                AnalysisRequestURLProtocol.handler = { request in
                    if request.httpMethod == "GET", request.url?.path == "/v0/lists" { return (200, "[]") }
                    XCTAssertEqual(request.httpMethod, "POST")
                    XCTAssertEqual(request.url?.path, "/places")
                    return (403, #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#)
                }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
                let service = SupabaseService(apiBaseURL: "https://exact-cap.test", session: URLSession(configuration: configuration), accessTokenProvider: { "fixture-token" })
                let map = MapViewModel(supabaseService: service, mapCandidateUserIDProvider: { owner },
                    saveLocalVaultService: vault,
                    correctionEventStore: SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("events.json")),
                    entitlementTierProvider: { .free }, entitlementResolvedProvider: { true }, usesRemotePersistence: route != "local-precheck")
                let candidate = SaveMapCandidate(id: "exact-cafe", title: "Refined Search Cafe", subtitle: "1 Refined Road",
                    latitude: 25, longitude: 121, category: .cafe)
                map.places = makeCappedPlaces(50)
                map.reviewCandidates = [clue]
                map.selectedReviewCandidate = clue
                map.mapCandidates = [candidate]
                map.selectedMapCandidate = candidate
                map.beginExactSearchResolution(for: clue)
                if failWriteFirst {
                    vault.saveReviewCandidateError = SaveLocalVaultError.storageUnavailable
                    do { _ = try await map.saveMapCandidateAsPlace(candidate); XCTFail("No parked success without durable storage") }
                    catch SaveLocalVaultError.storageUnavailable {}
                    XCTAssertEqual(map.reviewCandidates, [clue])
                    XCTAssertEqual(map.selectedReviewCandidate, clue)
                    XCTAssertEqual(map.mapCandidates.map(\.id), [candidate.id])
                    XCTAssertEqual(map.selectedMapCandidate?.id, candidate.id)
                    XCTAssertTrue(map.mapCandidate(candidate, resolvesReviewCandidateID: clue.id))
                    XCTAssertEqual(try Data(contentsOf: url), before)
                    XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
                    XCTAssertFalse(SavePlaceLimitHandoff.consumePaywallPending())
                    vault.saveReviewCandidateError = nil
                }
                do { _ = try await map.saveMapCandidateAsPlace(candidate); XCTFail("The cap must park the original clue") }
                catch is SavePlaceLimitError {}
                XCTAssertEqual(map.reviewCandidates.map(\.id), [clue.id])
                XCTAssertTrue(map.reviewCandidates.first?.isUnplacedInbox == true)
                XCTAssertEqual(map.reviewCandidates.first?.name, clue.name, "Do not replace the clue with the refined place")
                XCTAssertTrue(map.mapCandidate(candidate, resolvesReviewCandidateID: clue.id))
                XCTAssertEqual(map.places.count, 50)
                XCTAssertTrue(map.shouldPresentSavedPlaceLimitPaywall)
                let persisted = try XCTUnwrap(SaveLocalVaultService(overrideVaultURL: url).reviewCandidates(belongingTo: owner).first)
                XCTAssertTrue(persisted.isUnplacedInbox)
                XCTAssertEqual(persisted.id, clue.id)
                XCTAssertEqual(persisted.ownerSubject, owner)
                XCTAssertEqual(persisted.captureId, clue.captureId)
                XCTAssertEqual(persisted.workflowRunId, clue.workflowRunId)
                XCTAssertEqual(persisted.city, clue.city)
                XCTAssertEqual(persisted.confidence, clue.confidence)
                XCTAssertEqual(persisted.createdAt, clue.createdAt)
                XCTAssertTrue(clue.evidence.allSatisfy { persisted.evidence.contains($0) })
                XCTAssertTrue(try vault.confirmedPlaces().isEmpty)
                XCTAssertEqual(AnalysisRequestURLProtocol.requests.filter { $0.httpMethod == "POST" }.count,
                    route == "remote-cap" ? (failWriteFirst ? 2 : 1) : 0)
            }
        }
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
        XCTAssertNotEqual(
            parked.id,
            post.id,
            "author places.id must not become the recipient Map Stamp id"
        )
        XCTAssertNil(parked.note)
        XCTAssertNil(parked.rating)
        XCTAssertNil(parked.recommender)
        XCTAssertFalse(evidence.contains("Secret counter seat"))
        XCTAssertFalse(evidence.contains("Alex"))
        XCTAssertEqual(parked.status, .wantToGo)
    }

    @MainActor
    func testParkingFromASheetDoesNotPresentUnderTheSheet() throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(50)
        let place = makeSocialPlace(name: "Sheet Cafe")
        _ = try map.parkPlaceInUnplacedInbox(place, requestPaywall: false)
        XCTAssertEqual(map.reviewCandidates.first?.name, "Sheet Cafe")
        XCTAssertEqual(map.reviewCandidates.first?.status, "review")
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        XCTAssertFalse(
            SavePlaceLimitHandoff.consumePaywallPending(),
            "a quiet park must not leave a handoff that covers Home on the next activation"
        )
    }

    @MainActor
    func testParkDoesNotReportSuccessWhenVaultWriteFails() throws {
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-vault-fail.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-vault-fail-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        vault.saveReviewCandidateError = SaveLocalVaultError.storageUnavailable
        let map = MapViewModel(
            saveLocalVaultService: vault,
            entitlementTierProvider: { .free },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: false
        )
        map.places = makeCappedPlaces(50)
        let place = makeSocialPlace(name: "Lost If Parked")
        XCTAssertThrowsError(try map.parkPlaceInUnplacedInbox(place))
        XCTAssertTrue(map.reviewCandidates.isEmpty)
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
        XCTAssertTrue(try vault.reviewCandidates().isEmpty)
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
        _ = try map.parkPlaceInUnplacedInbox(place)
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
        XCTAssertEqual(
            SaveVaultOwnerScope.belongsToActiveAccount("did:privy:a", currentUserId: "did:privy:a"),
            MapViewModel.localVaultRecordBelongsToActiveAccount("did:privy:a", currentUserId: "did:privy:a")
        )
        XCTAssertEqual(
            SaveVaultOwnerScope.belongsToActiveAccount(nil, currentUserId: "did:privy:b"),
            MapViewModel.localVaultRecordBelongsToActiveAccount(nil, currentUserId: "did:privy:b")
        )
    }

    /// D3 / P1 4343590029: shortcuts must use the owner-scoped vault read.
    func testAskSaveMemoryIntentReadsOnlyTheActiveOwnerRecentRecords() throws {
        let intent = try source(at: "SAV-E/Intents/AskSaveMemoryIntent.swift")
        XCTAssertTrue(intent.contains("SaveLocalVaultService.shared.recentRecords"))
        XCTAssertTrue(
            intent.contains("belongingTo: PrivyAuthService.shared.currentUserId"),
            "Ask Savvy Memory must not speak another account's recent titles"
        )
        XCTAssertFalse(
            intent.contains("recentRecords(\n            limit: 5\n        )"),
            "unscoped recentRecords(limit:) is the leak Codex named"
        )
        let vault = try source(at: "SAV-E/Services/SaveLocalVaultService.swift")
        XCTAssertTrue(vault.contains("func recentRecords(\n        limit: Int = 25,\n        belongingTo currentUserId: String?"))
        XCTAssertTrue(vault.contains("scopedToActiveAccount: true"))
        XCTAssertTrue(
            vault.contains("Array(scoped.prefix(limit))"),
            "limit applies after the owner filter"
        )
    }

    /// D3 / P1 4344606407: iMessage cannot link SAV-EShared; keep the same owner rule.
    func testIMessageVaultReadFiltersByCachedOwnerBeforeLimit() throws {
        let reader = try source(at: "SAV-EiMessage/MessagesVaultReader.swift")
        XCTAssertTrue(reader.contains("let ownerSubject: String?"))
        XCTAssertTrue(reader.contains("cachedOwnerKey = \"save.cachedActiveOwnerSubject\""))
        XCTAssertTrue(reader.contains("belongsToActiveAccount($0.ownerSubject, currentUserId: currentOwner)"))
        XCTAssertTrue(reader.contains("return ownerSubject == currentUserId"))
        XCTAssertTrue(reader.contains("return ownerSubject == nil"))
        let filterRange = try XCTUnwrap(reader.range(of: "belongsToActiveAccount($0.ownerSubject, currentUserId: currentOwner)"))
        let limitRange = try XCTUnwrap(reader.range(of: ".prefix(limit)"))
        XCTAssertLessThan(
            filterRange.lowerBound,
            limitRange.lowerBound,
            "owner filter must run before prefix so B is not truncated by A's newer stamps"
        )
        let policy = try source(at: "SAV-EShared/SAVEProAccessPolicy.swift")
        XCTAssertTrue(policy.contains("cachedOwnerKey = \"save.cachedActiveOwnerSubject\""))
        XCTAssertTrue(policy.contains("func syncActiveOwner"))
        let auth = try source(at: "SAV-E/Services/PrivyAuthService.swift")
        XCTAssertTrue(auth.contains("SavePlaceLimitHandoff.syncActiveOwner(userId)"))
        XCTAssertTrue(auth.contains("SavePlaceLimitHandoff.syncActiveOwner(nil)"))
    }

    @MainActor
    func testShareExtensionUnplacedCandidateKeepsInboxMarker() throws {
        let share = try source(at: "SAV-EShareExtension/ShareViewController.swift")
        XCTAssertTrue(
            share.contains("missingInfo: [SAVEProAccessPolicy.unplacedInboxMarker]"),
            "P2 4344606412: parked Share Extension saves must stay Unplaced, not ordinary Review"
        )
        XCTAssertEqual(SAVEProAccessPolicy.unplacedInboxMarker, "Unplaced inbox")
        let inboxMarker = PlaceReviewCandidate.unplacedInboxMarker
        XCTAssertEqual(inboxMarker, SAVEProAccessPolicy.unplacedInboxMarker)
        XCTAssertTrue(
            share.contains("saveReviewCandidates([candidate], markSavedPlaceLimitPaywall: true)"),
            "P2 4348222446: over-cap share parks first, then may mark the paywall"
        )
        XCTAssertTrue(
            share.contains("guard appendPendingItems(stamped, to: fileURL, as: PendingReviewCandidate.self) else { return }\n        if markSavedPlaceLimitPaywall {\n            SavePlaceLimitHandoff.markPaywallPending()"),
            "P2 4348222446: paywall handoff only after the Unplaced append succeeds"
        )
        XCTAssertFalse(
            share.contains("SavePlaceLimitHandoff.markPaywallPending()\n            saveReviewCandidates([candidate])"),
            "do not persist a paywall for a failed Share Extension save"
        )
    }

    func testEntitlementRefreshResyncsAppGroupCacheInSource() throws {
        let store = try source(at: "SAV-E/Services/SaveEntitlementStore.swift")
        let map = try source(at: "SAV-E/ViewModels/MapViewModel.swift")
        let listing = try source(at: "specs/app-store-listing.md")
        XCTAssertTrue(listing.contains("Monthly AI-assist allowance is higher on Pro (Free 20, Pro 500)."))
        XCTAssertFalse(listing.contains("Monthly AI-assist allowance is the same on Free and Pro"))
        let supabase = try source(at: "SAV-E/Services/SupabaseService.swift")
        XCTAssertTrue(
            supabase.contains("func saveFriendRestaurant(placeID: UUID) async throws -> Place"),
            "P2 4346012936: friend-rating save must remap the server cap"
        )
        XCTAssertTrue(supabase.contains("/v0/friend-ratings/\\(placeID)/save"))
        let friendSaveRange = try XCTUnwrap(supabase.range(of: "func saveFriendRestaurant(placeID: UUID) async throws -> Place"))
        let mappedAfterFriendSave = supabase[friendSaveRange.lowerBound...].range(of: "throw mappedSavedPlaceLimit(error)")
        XCTAssertNotNil(mappedAfterFriendSave, "saveFriendRestaurant must remap over_free_limit like shared-post save")
        XCTAssertTrue(store.contains("NotificationCenter.default.post(name: .saveEntitlementDidRefresh, object: nil)"))
        XCTAssertTrue(map.contains("publisher(for: .saveEntitlementDidRefresh)"))
        XCTAssertTrue(map.contains("self?.syncSavedPlaceLimitCache()"))
    }

    func testHandoffCachesActiveOwnerForExtensionReads() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "save.owner-handoff.\(UUID().uuidString)"))
        SavePlaceLimitHandoff.syncActiveOwner("did:privy:a", defaults: defaults)
        XCTAssertEqual(SavePlaceLimitHandoff.cachedActiveOwner(defaults: defaults), "did:privy:a")
        SavePlaceLimitHandoff.syncActiveOwner("", defaults: defaults)
        XCTAssertNil(SavePlaceLimitHandoff.cachedActiveOwner(defaults: defaults))
        SavePlaceLimitHandoff.syncActiveOwner(nil, defaults: defaults)
        XCTAssertNil(SavePlaceLimitHandoff.cachedActiveOwner(defaults: defaults))
    }

    @MainActor
    func testEntitlementRefreshNotificationResyncsAppGroupCache() throws {
        let map = makeCappedMap(tier: .free)
        map.places = makeCappedPlaces(12)
        SavePlaceLimitHandoff.syncCache(tier: .free, savedPlaceCount: 50)
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .overFreeLimit)

        NotificationCenter.default.post(name: .saveEntitlementDidRefresh, object: nil)
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, SavePlaceLimitHandoff.cachedDecision() != .allowed {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(
            SavePlaceLimitHandoff.cachedDecision(),
            .allowed,
            "P2 4343238313: purchase/restore refresh must rewrite the Share Extension cache"
        )
    }

    @MainActor
    func testSourceOnlyFallbackStampsTheSignedInOwner() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-only-owner-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let record = try vault.saveSourceOnly(
            url: URL(string: "https://example.com/clue")!,
            note: "Keep this source",
            ownerSubject: "did:privy:owner-a"
        )
        XCTAssertEqual(record.ownerSubject, "did:privy:owner-a")
        XCTAssertEqual(try vault.reviewCandidates().first?.ownerSubject, "did:privy:owner-a")
        XCTAssertTrue(
            MapViewModel.localVaultRecordBelongsToActiveAccount(
                try XCTUnwrap(vault.reviewCandidates().first).ownerSubject,
                currentUserId: "did:privy:owner-a"
            )
        )
        XCTAssertFalse(
            MapViewModel.localVaultRecordBelongsToActiveAccount(
                try XCTUnwrap(vault.reviewCandidates().first).ownerSubject,
                currentUserId: "did:privy:owner-b"
            )
        )
    }

    @MainActor
    func testURLIntentAbortsWhenTheSessionChanges() throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "did:privy:owner-a")
        defer { PrivyAuthService.shared.authState = previousAuth }

        let generation = PrivyAuthService.shared.sessionGeneration
        XCTAssertNoThrow(
            try SavePlaceFromURLIntent.ensureInitiatingSession("did:privy:owner-a", generation)
        )

        PrivyAuthService.shared.authState = .authenticated(userId: "did:privy:owner-b")
        XCTAssertThrowsError(
            try SavePlaceFromURLIntent.ensureInitiatingSession("did:privy:owner-a", generation)
        ) { error in
            guard case ReviewCandidateError.sessionChangedAfterCommit = error else {
                return XCTFail("a late URL-intent write must not stamp the next account")
            }
        }
    }

    /// D3 / P1 4346852374: capture A before await; do not delete B's matching row.
    @MainActor
    func testDeletePlaceKeepsOtherOwnerAfterAccountSwitchMidCall() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "did:privy:a")
        defer {
            PrivyAuthService.shared.authState = previousAuth
            AnalysisRequestURLProtocol.reset()
        }

        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.url?.path == "/places" {
                let group = DispatchGroup()
                group.enter()
                Task { @MainActor in
                    PrivyAuthService.shared.authState = .authenticated(userId: "did:privy:b")
                    group.leave()
                }
                group.wait()
                return (200, "[]")
            }
            return (200, "{}")
        }

        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.delete-switch.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-switch-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let placeA = makeSocialPlace(name: "Harbor Cafe")
        let placeB = makeSocialPlace(name: "Harbor Cafe")
        _ = try vault.saveConfirmedPlace(placeA, ownerSubject: "did:privy:a")
        _ = try vault.saveConfirmedPlace(placeB, ownerSubject: "did:privy:b")

        let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)
        map.places = [placeA]
        map.selectedPlace = placeA

        do {
            try await map.deletePlace(placeA)
            XCTFail("a mid-delete account switch must abort the vault mutation")
        } catch ReviewCandidateError.sessionChangedAfterCommit {
            // Expected: A's remote work must not delete B's local row.
        }
        XCTAssertTrue(
            map.places.isEmpty,
            "deletePlace catch must not restore A's list onto B's screen"
        )
        XCTAssertNil(map.selectedPlace, "A's selected stamp must not reappear after the switch")

        XCTAssertEqual(
            try vault.confirmedPlaces(belongingTo: "did:privy:b").map(\.id),
            [placeB.id],
            "account B's matching venue must survive A's interrupted delete"
        )
        XCTAssertEqual(
            try vault.confirmedPlaces(belongingTo: "did:privy:a").first?.id,
            placeA.id,
            "failed delete restores A's row for the initiating owner"
        )
        XCTAssertEqual(try vault.confirmedPlaceRecords().first { $0.id == placeA.id }?.ownerSubject, "did:privy:a")
    }

    /// D3 / P1 4346852374: offline delete rollback must keep the owner stamp.
    @MainActor
    func testFailedDeleteRestoresConfirmedPlaceWithInitiatingOwner() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "did:privy:a")
        defer {
            PrivyAuthService.shared.authState = previousAuth
            AnalysisRequestURLProtocol.reset()
        }

        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.url?.path == "/places" { return (500, #"{"error":"offline"}"#) }
            return (200, "{}")
        }

        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.delete-restore.\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-restore-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let place = makeSocialPlace(name: "Rollback Cafe")
        _ = try vault.saveConfirmedPlace(place, ownerSubject: "did:privy:a")

        let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)
        map.places = [place]

        do {
            try await map.deletePlace(place)
            XCTFail("an offline remote delete must fail closed")
        } catch {
            XCTAssertFalse(error is ReviewCandidateError)
        }

        let restored = try vault.confirmedPlaces(belongingTo: "did:privy:a")
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, place.id)
        XCTAssertEqual(
            try vault.confirmedPlaceRecords().first { $0.id == place.id }?.ownerSubject,
            "did:privy:a",
            "rollback must not persist an ownerless row that signed-in reload would hide"
        )
    }

    /// D3 / P2 4347594688: 50 server + 1 stale local; deleting a server stamp
    /// must drop the authoritative count to 49, not assign places.count (50).
    @MainActor
    func testDeletePlaceCountComesFromOwnerScopedRemoteRemainder() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "did:privy:count-owner")
        defer {
            PrivyAuthService.shared.authState = previousAuth
            AnalysisRequestURLProtocol.reset()
        }

        let remotePlaces = makeCappedPlaces(50)
        let stalePlace = makeCappedPlaces(1, indexOffset: 50)[0]
        let rows = remotePlaces.enumerated().map { index, place in
            cappedPlaceRowJSON(
                id: place.id,
                index: index,
                name: place.name,
                googlePlaceID: place.googlePlaceId
            )
        }.joined(separator: ",")
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/places" {
                return (200, "[\(rows)]")
            }
            if request.httpMethod == "DELETE", request.url?.path.hasPrefix("/places/") == true {
                return (200, "{}")
            }
            if request.httpMethod == "POST", request.url?.path == "/places" {
                return (201, "{}")
            }
            if request.url?.path.contains("/memory/candidates") == true { return (200, "[]") }
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(
            suiteName: "save.delete-count.\(UUID().uuidString)"
        )
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-count-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        for place in remotePlaces + [stalePlace] {
            _ = try vault.saveConfirmedPlace(place, ownerSubject: "did:privy:count-owner")
        }
        let map = makeRemoteCappedMap(vaultURL: vaultURL, vault: vault)

        await map.loadPlaces(force: true)
        XCTAssertEqual(map.places.count, 51, "merge keeps the extra stale vault row")
        XCTAssertEqual(SavePlaceLimitHandoff.cachedDecision(), .overFreeLimit)

        let removed = try XCTUnwrap(remotePlaces.first)
        try await map.deletePlace(removed)
        XCTAssertEqual(map.places.count, 50, "display still includes the stale vault-only row")
        XCTAssertEqual(
            SavePlaceLimitHandoff.cachedDecision(),
            .allowed,
            "authoritative count must be 49 from the owner-scoped remote remainder"
        )

        let saved = try await map.saveMapCandidateAsPlace(
            SaveMapCandidate(
                id: "cap-after-stale-delete",
                title: "Freed After Delete Cafe",
                subtitle: "Taipei",
                latitude: 25.45,
                longitude: 121.85,
                category: .cafe
            )
        )
        XCTAssertEqual(saved.name, "Freed After Delete Cafe")
        XCTAssertFalse(map.shouldPresentSavedPlaceLimitPaywall)
    }

    @MainActor
    func testAnotherAccountVaultDoesNotInflateTheFreeCap() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "did:privy:owner-b")
        defer { PrivyAuthService.shared.authState = previousAuth }

        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200, "[]") }
            return (200, "{}")
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "save.place-limit-scope-\(UUID().uuidString)")
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("place-limit-scope-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        for place in makeCappedPlaces(50) {
            _ = try vault.saveConfirmedPlace(place, ownerSubject: "did:privy:owner-a")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let map = MapViewModel(
            supabaseService: SupabaseService(
                apiBaseURL: "https://analysis.test",
                session: URLSession(configuration: configuration),
                accessTokenProvider: { "test-token" }
            ),
            saveLocalVaultService: vault,
            entitlementTierProvider: { .free },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: true
        )
        await map.loadPlaces(force: true)
        XCTAssertTrue(map.places.isEmpty, "account B must not inherit A's cached Map Stamps")
        XCTAssertEqual(try vault.confirmedPlaceRecords().count, 50)
    }

    @MainActor
    func testOwnerlessPreUpgradeRecordsStayHiddenWhileSignedIn() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "did:privy:owner-a")
        defer { PrivyAuthService.shared.authState = previousAuth }

        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ownerless-hidden-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let stamp = makeCappedPlaces(1)[0]
        _ = try vault.saveConfirmedPlace(stamp)
        let unsigned = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Pre-upgrade Clue",
            address: "1 Legacy Road",
            city: nil,
            latitude: 25.0,
            longitude: 121.0,
            evidence: ["Source URL: https://example.com/pre-upgrade"],
            confidence: 0.9,
            missingInfo: [],
            status: "review",
            createdAt: Date()
        )
        _ = try vault.saveReviewCandidate(unsigned)
        XCTAssertNil(try vault.confirmedPlaceRecords().first?.ownerSubject)
        XCTAssertNil(try vault.reviewCandidates().first?.ownerSubject)

        let map = MapViewModel(
            saveLocalVaultService: vault,
            entitlementTierProvider: { .free },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: false
        )
        await map.loadPlaces(force: true)

        XCTAssertFalse(
            map.places.contains { $0.id == stamp.id },
            "first signed-in account must not inherit ownerless pre-upgrade Map Stamps"
        )
        XCTAssertFalse(
            map.reviewCandidates.contains { $0.id == unsigned.id },
            "first signed-in account must not inherit ownerless pre-upgrade clues"
        )
        XCTAssertNil(
            try vault.confirmedPlaceRecords().first?.ownerSubject,
            "a nil owner is not evidence that the current account created the row"
        )
        XCTAssertNil(try vault.reviewCandidates().first?.ownerSubject)
    }

    @MainActor
    func testLocalOnlyConfirmStampsOwnerSoSignedInReloadKeepsTheMapStamp() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "did:privy:demo-owner")
        defer { PrivyAuthService.shared.authState = previousAuth }

        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-only-confirm-owner-\(UUID().uuidString).json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        let map = MapViewModel(
            saveLocalVaultService: vault,
            entitlementTierProvider: { .pro },
            entitlementResolvedProvider: { true },
            usesRemotePersistence: false
        )
        let candidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Quarter Sheets Pizza Club",
            address: "1 Fixture Road",
            city: nil,
            latitude: 34.0779,
            longitude: -118.2543,
            evidence: ["Source URL: https://www.google.com/maps/place/Quarter+Sheets"],
            confidence: 0.9,
            missingInfo: [],
            status: "review",
            createdAt: Date()
        )
        map.reviewCandidates = [candidate]

        let saved = try await map.saveReviewCandidateAsPlace(candidate)
        XCTAssertEqual(saved.name, "Quarter Sheets Pizza Club")
        XCTAssertEqual(
            try vault.confirmedPlaceRecords().first?.ownerSubject,
            "did:privy:demo-owner"
        )

        map.places = []
        await map.loadPlaces(force: true)
        XCTAssertTrue(
            map.places.contains { $0.id == saved.id },
            "a signed-in offline confirm must remain visible after a vault reload"
        )
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
        let parked = try map.parkPlaceInUnplacedInbox(place)
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

    func testShareExtensionDestinationDefersCachedCapUntilCanonicalDedup() {
        XCTAssertEqual(
            SaveShareExtensionPlaceDestination.resolve(cached: .overFreeLimit),
            .pendingMapStamp
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
            .pendingMapStamp
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

    private func makeShortCodeReceipt(name: String, code: String) -> SharedPlaceReceipt {
        SharedPlaceReceipt(
            code: code,
            payload: SharedPlaceData(
                id: "",
                name: name,
                address: "7 Cap Road",
                lat: 25.20,
                lng: 121.61,
                category: "Cafe",
                rating: nil,
                reviewCount: nil,
                priceRange: nil,
                hours: nil,
                sourceLabel: "Savvy",
                sourceURL: nil,
                photoURLs: [],
                note: nil
            ),
            sourcePlaceID: nil,
            expiresAt: nil,
            sender: nil
        )
    }

    @MainActor
    func testLegacyReviewFailureRollsBackOnlyNewRowAndPinsRollbackSession() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        defer {
            auth.authState = originalAuth
            SavePlaceLimitHandoff.testDefaults = originalDefaults
            AnalysisRequestURLProtocol.reset()
        }
        for switchMode in ["unchanged", "other-account", "signed-out"] {
            let owner = "legacy-rollback-owner"
            auth.authState = .authenticated(userId: owner)
            let generation = auth.sessionGeneration
            SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "rollback-row.\(UUID())")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
            let candidate = contextualReviewCandidate(owner: owner, workflow: false)
            let existing = Place.from(candidate)
            var remoteIDs: Set<UUID> = [existing.id]
            var createdID: UUID?
            var correctionRequests = 0
            var rollbackTokenRequests = 0
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { request in
                if request.httpMethod == "POST", request.url?.path == "/places" {
                    let body = try AnalysisRequestURLProtocol.body(request)
                    let id = try XCTUnwrap((body["id"] as? String).flatMap(UUID.init(uuidString:)))
                    XCTAssertEqual(body["google_place_id"] as? String, existing.googlePlaceId)
                    createdID = id
                    remoteIDs.insert(id)
                    return (201, "{}")
                }
                if request.httpMethod == "PATCH", request.url?.path == "/memory/candidates/\(candidate.id)" {
                    correctionRequests += 1
                    return (500, #"{"error":"fixture_correction_failed"}"#)
                }
                if request.httpMethod == "DELETE", let url = request.url {
                    let id = try XCTUnwrap(UUID(uuidString: url.lastPathComponent))
                    if URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "scope" && $0.value == "group" }) == true {
                        remoteIDs.removeAll() // This reproduces the destructive old endpoint.
                    } else {
                        remoteIDs.remove(id)
                    }
                    return (204, "")
                }
                // A stale/unloaded client does not yet know the saved alias.
                return (200, request.httpMethod == "GET" ? "[]" : "{}")
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
            let service = SupabaseService(apiBaseURL: "https://row-rollback.test",
                session: URLSession(configuration: configuration), accessTokenProvider: {
                    if let scope = SAVEPendingImportSessionScope.current {
                        XCTAssertEqual(scope.owner, owner)
                        XCTAssertEqual(scope.generation, generation)
                        await MainActor.run {
                            rollbackTokenRequests += 1
                            if switchMode == "other-account" { auth.authState = .authenticated(userId: "other-owner") }
                            if switchMode == "signed-out" { auth.authState = .unauthenticated }
                        }
                    }
                    return "fixture-token"
                })
            let map = MapViewModel(supabaseService: service, saveLocalVaultService: vault,
                correctionEventStore: SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("events.json")),
                entitlementTierProvider: { .free }, entitlementResolvedProvider: { true }, usesRemotePersistence: true)
            map.places = []
            map.reviewCandidates = [candidate]
            do {
                _ = try await map.saveReviewCandidateAsPlace(candidate)
                XCTFail("Correction failure must remain a failure")
            } catch {}
            let inserted = try XCTUnwrap(createdID)
            XCTAssertNotEqual(inserted, existing.id)
            XCTAssertEqual(correctionRequests, 1)
            XCTAssertEqual(rollbackTokenRequests, 1)
            let deletes = AnalysisRequestURLProtocol.requests.filter { $0.httpMethod == "DELETE" }
            XCTAssertEqual(deletes.count, switchMode == "unchanged" ? 1 : 0)
            if switchMode == "unchanged" {
                XCTAssertNil(try XCTUnwrap(deletes.first?.url).query, "Legacy rollback must use exact-row default")
                XCTAssertEqual(remoteIDs, [existing.id])
                XCTAssertTrue(map.reviewCandidates.contains { $0.id == candidate.id })
            } else {
                XCTAssertEqual(remoteIDs, [existing.id, inserted], "A switched token must not send the rollback")
            }
            XCTAssertFalse(map.places.contains { $0.id == inserted })
            XCTAssertFalse(try vault.confirmedPlaces(belongingTo: owner).contains { $0.id == inserted })
        }
    }

    @MainActor
    func testNormalDeleteUsesExplicitCanonicalGroupScope() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let originalDefaults = SavePlaceLimitHandoff.testDefaults
        let owner = "normal-delete-owner"
        auth.authState = .authenticated(userId: owner)
        defer {
            auth.authState = originalAuth
            SavePlaceLimitHandoff.testDefaults = originalDefaults
            AnalysisRequestURLProtocol.reset()
        }
        SavePlaceLimitHandoff.testDefaults = UserDefaults(suiteName: "delete-group.\(UUID())")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let candidate = contextualReviewCandidate(owner: owner, workflow: false)
        let original = Place.from(candidate)
        let alias = Place.from(candidate)
        let displayed = try XCTUnwrap(Place.consolidated([original, alias]).first)
        var remoteIDs: Set<UUID> = [original.id, alias.id]
        let rows = [original, alias].enumerated().map { index, place in
            cappedPlaceRowJSON(id: place.id, index: index, name: place.name, googlePlaceID: place.googlePlaceId)
        }.joined(separator: ",")
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/places" { return (200, remoteIDs.isEmpty ? "[]" : "[\(rows)]") }
            if request.httpMethod == "DELETE", let url = request.url {
                XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                    [URLQueryItem(name: "scope", value: "group")])
                remoteIDs.removeAll()
                return (204, "")
            }
            return (200, "[]")
        }
        let map = makeRemoteCappedMap(vaultURL: directory.appendingPathComponent("vault.json"), vault: vault)
        map.places = [displayed]
        try await map.deletePlace(displayed)
        XCTAssertTrue(remoteIDs.isEmpty)
        XCTAssertTrue(map.places.isEmpty)
        XCTAssertFalse(AnalysisRequestURLProtocol.requests.filter { $0.httpMethod == "DELETE" }.isEmpty)
    }

    @MainActor
    func testAccountDeletionCannotSendAfterTokenSuspensionChangesAccount() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        defer { auth.authState = originalAuth; AnalysisRequestURLProtocol.reset() }
        for explicitSession in [false, true] {
            let owner = "account-delete-a"
            auth.authState = .authenticated(userId: owner)
            let generation = auth.sessionGeneration
            let arrived = expectation(description: "Account-delete token suspended")
            let release = DispatchSemaphore(value: 0)
            AnalysisRequestURLProtocol.reset()
            AnalysisRequestURLProtocol.handler = { _ in (204, "") }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
            let service = SupabaseService(apiBaseURL: "https://delete-account.test",
                session: URLSession(configuration: configuration), accessTokenProvider: {
                    await Task.detached {
                        arrived.fulfill()
                        XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                        return "account-b-token"
                    }.value
                })
            let deletion = Task {
                if explicitSession { try await service.deleteAccount(startedBy: owner, generation: generation) }
                else { try await service.deleteAccount() }
            }
            await fulfillment(of: [arrived], timeout: 2)
            auth.authState = .authenticated(userId: "account-delete-b")
            release.signal()
            do {
                try await deletion.value
                XCTFail("A new account token must never delete the initiating or new account")
            } catch is CancellationError {}
            XCTAssertTrue(AnalysisRequestURLProtocol.requests.isEmpty)
            XCTAssertEqual(auth.currentUserId, "account-delete-b")
        }
    }

    @MainActor
    func testAccountDeletionResponseAfterAccountSwitchCleansOnlyInitiatingOwner() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        let owner = "account-delete-a"
        let other = "account-delete-b"
        auth.authState = .authenticated(userId: owner)
        let generation = auth.sessionGeneration
        defer { auth.authState = originalAuth; AnalysisRequestURLProtocol.reset() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let originalLegacy = SaveMemoryRecord(state: .sourceOnly, title: "Original legacy")
        let a = SaveMemoryRecord(state: .sourceOnly, title: "A", ownerSubject: owner)
        let b = SaveMemoryRecord(state: .sourceOnly, title: "B", ownerSubject: other)
        try vault.append(originalLegacy)
        try vault.append(a)
        try vault.append(b)
        let avatars = ProfileAvatarStore(baseDirectory: directory.appendingPathComponent("avatars"))
        try avatars.save(Data([1]), for: owner)
        try avatars.save(Data([2]), for: other)
        let arrived = expectation(description: "A account deletion sent; response suspended")
        let release = DispatchSemaphore(value: 0)
        AnalysisRequestURLProtocol.reset()
        AnalysisRequestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v0/account")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-a-token")
            arrived.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            return (204, "")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisRequestURLProtocol.self]
        let service = SupabaseService(apiBaseURL: "https://delete-account.test",
            session: URLSession(configuration: configuration), accessTokenProvider: { "account-a-token" })
        let profile = ProfileViewModel(supabaseService: service, accountDeletionService: service,
            avatarStore: avatars, saveLocalVaultService: vault,
            pendingPlaceImportService: PendingPlaceImportService(overrideContainerURL: directory),
            reviewerDemoProvider: { false })
        let deletion = Task {
            await SAVEPendingImportSessionScope.$current.withValue((generation, owner)) {
                await profile.deleteAccount()
            }
        }
        await fulfillment(of: [arrived], timeout: 2)
        auth.authState = .authenticated(userId: other)
        let laterLegacy = SaveMemoryRecord(state: .sourceOnly, title: "Later legacy")
        try vault.append(laterLegacy)
        release.signal()
        let deleted = await deletion.value
        XCTAssertTrue(deleted, "A's successful response must reach its local cleanup after switching to B")
        XCTAssertEqual(Set(try vault.recentRecords().map(\.id)), [b.id, laterLegacy.id])
        XCTAssertNil(avatars.load(for: owner))
        XCTAssertEqual(avatars.load(for: other), Data([2]))
        XCTAssertEqual(auth.currentUserId, other, "A cleanup must not sign out B")
        XCTAssertNil(profile.errorMessage)
        XCTAssertEqual(AnalysisRequestURLProtocol.requests.count, 1)
    }

    @MainActor
    private func makeRemoteCappedMap(
        vaultURL: URL,
        vault: SaveLocalVaultService? = nil,
        tier: SaveProTier = .free,
        resolved: Bool = true
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
            entitlementResolvedProvider: { resolved },
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

        for token in ["FDF8F3", "FFFDF7", "0E4A33", "2E2117", SaveAtlasPalette.coralLightHex, "B5E3F5", "D6E8C4", "F0CFA1"] {
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
        let previousAuth = PrivyAuthService.shared.authState
        PrivyAuthService.shared.authState = .authenticated(userId: "owner")
        defer { PrivyAuthService.shared.authState = previousAuth }

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

/// Exercises the same account binding used by local parsing, both pending
/// queues, and source-only vault writes in the Share Extension.
@MainActor
final class ShareOwnerSnapshotTests: XCTestCase {
    private let ownerA = "did:privy:share-a"
    private let ownerB = "did:privy:share-b"

    private func credential(owner: String, expired: Bool = false) -> ShareAnalysisCredential {
        ShareAnalysisCredential(token: "synthetic-analysis-only-token", ownerSubject: owner,
            expiresAt: Date().addingTimeInterval(expired ? -3600 : 3600),
            apiBaseURL: "https://share.example.test")
    }

    func testMissingAnalysisCredentialKeepsAuthenticatedOwner() throws {
        let snapshot = ShareOwnerSnapshot(cachedActiveOwner: ownerA)
        try snapshot.validate(cachedActiveOwner: ownerA, credential: nil)
        XCTAssertEqual(try snapshot.ownerForNewItem(existingOwner: nil), ownerA)
    }

    func testExpiredAnalysisCredentialDoesNotPreventLocalSourceSave() throws {
        let expired = credential(owner: ownerA, expired: true)
        XCTAssertFalse(expired.isUsable())
        let snapshot = ShareOwnerSnapshot(cachedActiveOwner: ownerA)
        try snapshot.validate(cachedActiveOwner: ownerA, credential: expired)
        XCTAssertEqual(try snapshot.ownerForNewItem(existingOwner: nil), ownerA)
    }

    func testProvisioningAndRefreshingSameOwnerCredentialKeepsBinding() throws {
        let snapshot = ShareOwnerSnapshot(cachedActiveOwner: ownerA)
        for current in [nil, credential(owner: ownerA, expired: true), credential(owner: ownerA), nil] {
            try snapshot.validate(cachedActiveOwner: ownerA, credential: current)
            XCTAssertEqual(try snapshot.ownerForNewItem(existingOwner: nil), ownerA)
        }
    }

    func testAnalysisValidatesTheCapturedCredentialAfterAnEarlierSessionCheck() throws {
        let snapshot = ShareOwnerSnapshot(cachedActiveOwner: ownerA)
        try snapshot.validate(cachedActiveOwner: ownerA, credential: credential(owner: ownerA))
        // The keychain changes after the first session check. The actual
        // credential selected for the request must not carry A's input to B.
        let capturedForRequest = credential(owner: ownerB)
        for cachedOwner in [ownerA, ownerB] {
            XCTAssertThrowsError(try snapshot.validatedAnalysisCredential(
                cachedActiveOwner: cachedOwner, credential: capturedForRequest)) { error in
                guard case ShareAnalysisError.sessionChanged = error else {
                    return XCTFail("Expected sessionChanged, got \(error)")
                }
            }
        }
    }

    func testAnalysisReturnsExactUsableSameOwnerCredential() throws {
        let snapshot = ShareOwnerSnapshot(cachedActiveOwner: ownerA)
        let capturedForRequest = credential(owner: ownerA)
        XCTAssertEqual(try snapshot.validatedAnalysisCredential(
            cachedActiveOwner: ownerA, credential: capturedForRequest), capturedForRequest)
        XCTAssertThrowsError(try snapshot.validatedAnalysisCredential(
            cachedActiveOwner: ownerA, credential: nil))
        XCTAssertThrowsError(try snapshot.validatedAnalysisCredential(
            cachedActiveOwner: ownerA, credential: credential(owner: ownerA, expired: true)))
    }

    func testSignedOutSnapshotCannotBindToLaterSignIn() throws {
        let snapshot = ShareOwnerSnapshot(cachedActiveOwner: nil)
        try snapshot.validate(cachedActiveOwner: nil, credential: nil)
        XCTAssertNil(try snapshot.ownerForNewItem(existingOwner: nil))
        XCTAssertThrowsError(try snapshot.validate(cachedActiveOwner: ownerB, credential: nil))
        XCTAssertThrowsError(try snapshot.validate(cachedActiveOwner: nil, credential: credential(owner: ownerB)))
        XCTAssertNil(snapshot.ownerSubject)
    }

    func testAccountSwitchAndSignOutRejectEvenWithStaleAnalysisCredential() throws {
        let snapshot = ShareOwnerSnapshot(cachedActiveOwner: ownerA)
        for currentOwner in [nil, ownerB] {
            XCTAssertThrowsError(try snapshot.validate(cachedActiveOwner: currentOwner, credential: nil))
            XCTAssertThrowsError(try snapshot.validate(cachedActiveOwner: currentOwner,
                credential: credential(owner: ownerA)))
        }
        XCTAssertThrowsError(try snapshot.validate(cachedActiveOwner: ownerA,
            credential: credential(owner: ownerB)))
        XCTAssertEqual(snapshot.ownerSubject, ownerA)
    }

    func testCandidateWithDifferentOwnerCannotBeRestamped() throws {
        let snapshot = ShareOwnerSnapshot(cachedActiveOwner: ownerA)
        XCTAssertEqual(try snapshot.ownerForNewItem(existingOwner: ownerA), ownerA)
        XCTAssertThrowsError(try snapshot.ownerForNewItem(existingOwner: ownerB))
        XCTAssertThrowsError(try ShareOwnerSnapshot(cachedActiveOwner: nil).ownerForNewItem(existingOwner: ownerA))
    }

    func testNewSourceVaultRowKeepsOwnerWithoutClaimingLegacyRow() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy: [String: String] = ["id": UUID().uuidString, "state": "source_only", "sourceText": "Legacy private clue"]
        try JSONEncoder().encode([legacy]).write(to: url)
        let snapshot = ShareOwnerSnapshot(cachedActiveOwner: ownerA)
        try snapshot.validate(cachedActiveOwner: ownerA, credential: nil)
        let row = ["id": UUID().uuidString, "state": "source_only", "sourceText": "New private clue",
                   "ownerSubject": try XCTUnwrap(snapshot.ownerForNewItem(existingOwner: nil))]
        try SaveMemoryVaultAppender.appending(row, to: Data(contentsOf: url)).write(to: url, options: .atomic)
        let reloaded = try JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: url))
        XCTAssertEqual(reloaded.first?["ownerSubject"], ownerA)
        XCTAssertEqual(reloaded.last, legacy)
        XCTAssertNil(reloaded.last?["ownerSubject"])
    }

    func testAccountSwitchWhileWaitingForFileCoordinationDoesNotAppend() throws {
        let suite = "ShareOwnerSnapshotTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data(#"[{"sourceText":"Existing private clue"}]"#.utf8)
        try original.write(to: url)
        SavePlaceLimitHandoff.syncActiveOwner(ownerA, defaults: defaults)
        let snapshot = ShareOwnerSnapshot(cachedActiveOwner: SavePlaceLimitHandoff.cachedActiveOwner(defaults: defaults))
        try snapshot.validate(cachedActiveOwner: SavePlaceLimitHandoff.cachedActiveOwner(defaults: defaults), credential: nil)
        // A parse/save check passed, but another app process switches the owner
        // before the coordinated accessor is granted access to the file.
        SavePlaceLimitHandoff.syncActiveOwner(ownerB, defaults: defaults)
        var rejected = false
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try snapshot.validate(cachedActiveOwner: SavePlaceLimitHandoff.cachedActiveOwner(defaults: defaults), credential: nil)
                let newData = try SaveMemoryVaultAppender.appending(["sourceText": "Must not append"], to: Data(contentsOf: coordinatedURL))
                try newData.write(to: coordinatedURL, options: .atomic)
                XCTFail("Account switch must reject the write")
            } catch ShareAnalysisError.sessionChanged {
                rejected = true
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertNil(coordinationError)
        XCTAssertTrue(rejected)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
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
