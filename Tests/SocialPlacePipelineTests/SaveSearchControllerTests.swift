import XCTest
@testable import Wanderly

final class SaveSearchControllerTests: XCTestCase {
    func testSearchSeparatesSavedPlacesAndRecommendationShell() {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "recommend new food in LA",
            places: [
                place(name: "Quarter Sheets Pizza Club", address: "1305 Portia St, Los Angeles, CA", category: .food)
            ],
            localRecords: []
        )

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Quarter Sheets Pizza Club"])
        XCTAssertEqual(response.newRecommendations.results.count, 1)
        XCTAssertEqual(response.newRecommendations.results.first?.objectType, .newRecommendation)
        XCTAssertEqual(response.newRecommendations.results.first?.userState, .unsaved)
        XCTAssertTrue(response.newRecommendations.results.first?.isRecommendationShell == true)
    }

    func testVisitedPlaceBecomesTriedMemorySearchResult() {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "visited cafe",
            places: [
                place(name: "Tried Coffee", address: "1 Main St, Taipei, Taiwan", category: .cafe, status: .visited),
                place(name: "Want Coffee", address: "2 Main St, Taipei, Taiwan", category: .cafe, status: .wantToGo)
            ],
            localRecords: []
        )

        XCTAssertEqual(response.fromYourSave.results.count, 1)
        XCTAssertEqual(response.fromYourSave.results.first?.title, "Tried Coffee")
        XCTAssertEqual(response.fromYourSave.results.first?.objectType, .triedMemory)
        XCTAssertEqual(response.fromYourSave.results.first?.userState, .visited)
    }

    func testUnsavedMapCandidatesStayCollectibleButNotSaved() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "nearby sushi",
            places: [],
            localRecords: [],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Sushi Gen",
                    subtitle: "Little Tokyo · Japanese",
                    latitude: 34.0478,
                    longitude: -118.2386,
                    category: .food,
                    rating: 4.6,
                    reviewCount: 4100,
                    sourceURL: "https://maps.google.com/?q=Sushi+Gen",
                    sourcePlatform: .googleMaps,
                    evidence: ["Visible on map", "Google rating 4.6"]
                )
            ]
        )

        let result = try XCTUnwrap(response.newRecommendations.results.first)
        XCTAssertEqual(result.objectType, .mapVisibleUnsavedPlace)
        XCTAssertEqual(result.userState, .unsaved)
        XCTAssertEqual(result.title, "Sushi Gen")
        XCTAssertEqual(result.rating, 4.6)
        XCTAssertEqual(result.reviewCount, 4100)
        XCTAssertEqual(result.primaryAction, .savePlace)
        XCTAssertFalse(result.isRecommendationShell)
        XCTAssertTrue(result.evidence.contains("Visible on map"))
    }

    func testUnsavedMapCandidateMakesSaveDraftWithMapEvidence() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "nearby sushi",
            places: [],
            localRecords: [],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Sushi Gen",
                    subtitle: "Little Tokyo · Japanese",
                    latitude: 34.0478,
                    longitude: -118.2386,
                    category: .food,
                    rating: 4.6,
                    reviewCount: 4100,
                    sourceURL: "https://maps.google.com/?q=Sushi+Gen",
                    sourcePlatform: .googleMaps,
                    evidence: ["Visible on map", "Google rating 4.6"]
                )
            ]
        )

        let result = try XCTUnwrap(response.newRecommendations.results.first)
        let draft = try XCTUnwrap(controller.makeSaveDraft(from: result))

        XCTAssertEqual(draft.title, "Sushi Gen")
        XCTAssertEqual(draft.address, "Little Tokyo · Japanese")
        XCTAssertEqual(draft.latitude, 34.0478)
        XCTAssertEqual(draft.longitude, -118.2386)
        XCTAssertEqual(draft.category, .food)
        XCTAssertEqual(draft.sourceURL, "https://maps.google.com/?q=Sushi+Gen")
        XCTAssertEqual(draft.sourcePlatform, .googleMaps)
        XCTAssertEqual(draft.externalRating, 4.6)
        XCTAssertEqual(draft.externalReviewCount, 4100)
        XCTAssertTrue(draft.evidence.contains("Visible on map"))
    }

    func testSourceOnlyClueCannotMakeSaveDraft() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "instagram",
            places: [],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://www.instagram.com/reel/example/",
                    title: "Instagram Reel",
                    evidence: ["Source URL: https://www.instagram.com/reel/example/"]
                )
            ]
        )

        let result = try XCTUnwrap(response.fromYourSave.results.first)
        XCTAssertNil(controller.makeSaveDraft(from: result))
    }

    func testSaveDraftBecomesPlaceWithoutPrivateRating() async throws {
        let controller = SaveSearchController()
        let draft = SavePlaceDraft(
            title: "Sushi Gen",
            address: "Little Tokyo · Japanese",
            latitude: 34.0478,
            longitude: -118.2386,
            category: .food,
            sourceURL: "https://maps.google.com/?q=Sushi+Gen",
            sourcePlatform: .googleMaps,
            evidence: ["Visible on map"],
            externalRating: 4.6,
            externalReviewCount: 4100
        )

        let place = try await controller.saveMapCandidate(draft)

        XCTAssertEqual(place.name, "Sushi Gen")
        XCTAssertEqual(place.address, "Little Tokyo · Japanese")
        XCTAssertEqual(place.status, .wantToGo)
        XCTAssertNil(place.rating)
        XCTAssertEqual(place.googleRating, 4.6)
        XCTAssertEqual(place.sourceUrl, "https://maps.google.com/?q=Sushi+Gen")
        XCTAssertEqual(place.sourcePlatform, .googleMaps)
        XCTAssertTrue(place.note?.contains("Visible on map") == true)
        XCTAssertTrue(place.note?.contains("External reviews: 4100") == true)
    }

    func testSavedMapCandidateSearchesFromYourSaveAfterSave() async throws {
        let controller = SaveSearchController()
        let draft = SavePlaceDraft(
            title: "Sushi Gen",
            address: "Little Tokyo · Japanese",
            latitude: 34.0478,
            longitude: -118.2386,
            category: .food,
            sourceURL: "https://maps.google.com/?q=Sushi+Gen",
            sourcePlatform: .googleMaps,
            evidence: ["Visible on map"],
            externalRating: 4.6,
            externalReviewCount: 4100
        )
        let place = try await controller.saveMapCandidate(draft)

        let response = controller.search(query: "sushi", places: [place], localRecords: [], mapCandidates: [])
        let result = try XCTUnwrap(response.fromYourSave.results.first)

        XCTAssertEqual(response.newRecommendations.results.count, 0)
        XCTAssertEqual(result.title, "Sushi Gen")
        XCTAssertEqual(result.objectType, .savedPlace)
        XCTAssertEqual(result.userState, .wantToGo)
        XCTAssertEqual(result.primaryAction, .openSource)
        XCTAssertEqual(result.rating, 4.6)
    }

    func testSourceOnlyAndReviewRecordsStayReviewScoped() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "instagram review taipei",
            places: [],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://www.instagram.com/reel/example/",
                    title: "Instagram Reel",
                    evidence: ["Source URL: https://www.instagram.com/reel/example/"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Instagram source"],
                        attempts: ["Checked public metadata"],
                        missingFields: ["place name", "verified address", "coordinates"],
                        nextBestClue: "Share a screenshot with the venue tag"
                    )
                ),
                SaveMemoryRecord(
                    state: .reviewCandidate,
                    sourceURL: "https://www.instagram.com/reel/taipei/",
                    title: "Possible place found",
                    placeName: "東京家庭義大利麵 士林店",
                    address: "Taipei · near Shilin Station",
                    evidence: ["Place name detected from caption"]
                )
            ]
        )

        XCTAssertEqual(response.fromYourSave.results.count, 1)
        let result = try XCTUnwrap(response.fromYourSave.results.first)
        XCTAssertEqual(result.title, "東京家庭義大利麵 士林店")
        XCTAssertEqual(result.objectType, .pendingCandidate)
        XCTAssertEqual(result.objectType.displayName, "Review Candidate")
        XCTAssertEqual(result.statusLabel, "Review Candidate")
        XCTAssertEqual(result.userState, .waitingReview)
        XCTAssertNil(result.confidence)
        XCTAssertFalse(result.isRecommendationShell)
    }

    func testReviewDraftDefaultsToPrivateAndReceiptReadyWithoutChainWrite() {
        let draft = SavePrivateReviewDraft(
            placeId: UUID(),
            rating: 4.5,
            tags: ["date-night"],
            note: "Would go back.",
            proofRefs: [
                SaveReceiptProofRef(
                    kind: .receiptCommitment,
                    label: "Receipt commitment placeholder",
                    url: nil,
                    commitmentHash: "sha256-placeholder"
                )
            ]
        )

        XCTAssertEqual(draft.visibility, .privateOnly)
        XCTAssertEqual(draft.proofRefs.first?.kind, .receiptCommitment)
        XCTAssertEqual(draft.proofRefs.first?.commitmentHash, "sha256-placeholder")
    }

    func testAgentActionDrawerAdaptsToPlaceMemoryState() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "",
            places: [
                place(
                    name: "Kato",
                    address: "777 S Alameda St, Los Angeles, CA",
                    category: .food,
                    sourceUrl: "https://www.instagram.com/reel/kato/"
                )
            ],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://www.instagram.com/reel/source-only/",
                    title: "Pasta reel clue",
                    evidence: ["Caption says best pasta in LA"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Instagram source"],
                        attempts: ["Parsed caption"],
                        missingFields: ["exact place", "coordinates"],
                        nextBestClue: "Find tagged venue profile"
                    )
                ),
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "javascript:alert(1)",
                    title: "Malformed source clue",
                    evidence: ["Invalid source URL should not render as a link"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Source text"],
                        attempts: ["Parsed source"],
                        missingFields: ["valid source URL"],
                        nextBestClue: "Share the original link"
                    )
                )
            ],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Sushi Gen",
                    subtitle: "Little Tokyo · Japanese",
                    latitude: 34.0478,
                    longitude: -118.2386,
                    category: .food,
                    rating: 4.6,
                    reviewCount: 4100,
                    sourceURL: "https://maps.google.com/?q=Sushi+Gen",
                    sourcePlatform: .googleMaps,
                    evidence: ["Visible on map", "Google rating 4.6"]
                )
            ]
        )

        let sourceOnly = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Pasta reel clue" })
        XCTAssertEqual(sourceOnly.objectType.displayName, "Clue")
        XCTAssertEqual(sourceOnly.agentDrawer.primaryAction.kind, .runRecovery)
        XCTAssertEqual(sourceOnly.agentDrawer.heading, "Clue found")
        XCTAssertTrue(sourceOnly.agentDrawer.secondaryActions.map(\.kind).contains(.openSource))
        XCTAssertTrue(sourceOnly.agentDrawer.evidenceSummary.contains("Missing: exact place, coordinates"))

        let malformedSource = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Malformed source clue" })
        XCTAssertFalse(malformedSource.agentDrawer.secondaryActions.map(\.kind).contains(.openSource))

        let savedPlace = try XCTUnwrap(response.fromYourSave.results.first { $0.objectType == .savedPlace })
        XCTAssertEqual(savedPlace.objectType.displayName, "Map Stamp")
        XCTAssertEqual(savedPlace.agentDrawer.heading, "Plan around this Map Stamp")
        XCTAssertEqual(savedPlace.agentDrawer.primaryAction.kind, .planAround)
        XCTAssertTrue(savedPlace.agentDrawer.secondaryActions.map(\.kind).contains(.openSource))
        XCTAssertTrue(savedPlace.agentDrawer.secondaryActions.map(\.kind).contains(.addToTrip))

        let unsavedMapPlace = try XCTUnwrap(response.newRecommendations.results.first { $0.objectType == .mapVisibleUnsavedPlace })
        XCTAssertEqual(unsavedMapPlace.objectType.displayName, "Unsaved Candidate")
        XCTAssertEqual(unsavedMapPlace.agentDrawer.primaryAction.kind, .savePlace)
        XCTAssertEqual(unsavedMapPlace.agentDrawer.heading, "Save unsaved candidate")
        XCTAssertTrue(unsavedMapPlace.agentDrawer.secondaryActions.map(\.kind).contains(.planAround))
        XCTAssertTrue(unsavedMapPlace.agentDrawer.secondaryActions.map(\.kind).contains(.openSource))
    }

    func testSourceOnlyEvidenceDrawerIncludesMissingFieldsAndRecoveryQuery() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "pasta",
            places: [],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://www.instagram.com/reel/pasta/",
                    title: "Best pasta reel",
                    evidence: ["Caption says best pasta in LA"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Source URL: https://www.instagram.com/reel/pasta/"],
                        attempts: ["Checked public metadata/caption text"],
                        missingFields: ["exact venue", "address", "coordinates"],
                        nextBestClue: "Run source recovery search",
                        suggestedSearchQueries: ["best pasta LA instagram reel"]
                    )
                )
            ]
        )

        let result = try XCTUnwrap(response.fromYourSave.results.first)
        let drawer = result.evidenceDrawer

        XCTAssertEqual(result.objectType, .sourceOnlyClue)
        XCTAssertEqual(drawer.sourcePlatform, .instagram)
        XCTAssertEqual(drawer.missingFields, ["exact venue", "address", "coordinates"])
        XCTAssertEqual(drawer.recoveryQueries, ["best pasta LA instagram reel"])
        XCTAssertTrue(drawer.candidateExplanation?.contains("without creating a Map Stamp") == true)
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .caption && $0.value.contains("best pasta in LA") })
    }

    func testUnsavedMapCandidateEvidenceDrawerShowsMapEvidenceWithoutMemoryClaim() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "nearby sushi",
            places: [],
            localRecords: [],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Sushi Gen",
                    subtitle: "Little Tokyo · Japanese",
                    latitude: 34.0478,
                    longitude: -118.2386,
                    category: .food,
                    rating: 4.6,
                    reviewCount: 4100,
                    sourceURL: "https://maps.google.com/?q=Sushi+Gen",
                    sourcePlatform: .googleMaps,
                    evidence: ["Visible on map"]
                )
            ]
        )

        let result = try XCTUnwrap(response.newRecommendations.results.first)
        let drawer = result.evidenceDrawer

        XCTAssertEqual(result.objectType, .mapVisibleUnsavedPlace)
        XCTAssertEqual(result.userState, .unsaved)
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .rating && $0.value == "4.6" })
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .reviewCount && $0.value == "4100" })
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .coordinates && $0.value == "present" })
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .receipt && $0.value == "Unsaved; not a Map Stamp" })
        XCTAssertEqual(drawer.candidateExplanation, "This is an unsaved candidate, not a Map Stamp yet.")
    }

    func testSavedPlaceEvidenceDrawerIncludesSourcePlatformAndAddress() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "kato",
            places: [
                place(
                    name: "Kato",
                    address: "777 S Alameda St, Los Angeles, CA",
                    category: .food,
                    sourceUrl: "https://www.instagram.com/reel/kato/"
                )
            ],
            localRecords: []
        )

        let result = try XCTUnwrap(response.fromYourSave.results.first)
        let drawer = result.evidenceDrawer

        XCTAssertEqual(result.objectType, .savedPlace)
        XCTAssertEqual(drawer.sourcePlatform, .instagram)
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.label == "Platform" && $0.value == "Instagram" })
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .address && $0.value == "777 S Alameda St, Los Angeles, CA" })
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .receipt && $0.value == "Saved Map Stamp" })
    }

    func testEvidenceDrawerDoesNotTrustLookalikeSourceHost() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "lookalike",
            places: [],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://notinstagram.com/reel/source/",
                    title: "Lookalike source",
                    evidence: ["Caption says cafe"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Source URL: https://notinstagram.com/reel/source/"],
                        attempts: ["Checked public metadata"],
                        missingFields: ["verified source platform"],
                        nextBestClue: "Share the original social link"
                    )
                )
            ]
        )

        let result = try XCTUnwrap(response.fromYourSave.results.first)
        XCTAssertEqual(result.sourcePlatform, .other)
        XCTAssertNotEqual(result.evidenceDrawer.sourcePlatform, .instagram)
        XCTAssertFalse(result.evidenceDrawer.evidenceAtoms.contains { $0.label == "Platform" && $0.value == "Instagram" })
    }

    private func place(
        name: String,
        address: String,
        category: PlaceCategory,
        status: PlaceStatus = .wantToGo,
        sourceUrl: String? = nil
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: 34.0522,
            longitude: -118.2437,
            googlePlaceId: nil,
            category: category,
            status: status,
            rating: nil,
            note: nil,
            sourceUrl: sourceUrl,
            sourcePlatform: .instagram,
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
