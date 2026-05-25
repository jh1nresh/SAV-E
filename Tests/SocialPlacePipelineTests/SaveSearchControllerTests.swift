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

    private func place(
        name: String,
        address: String,
        category: PlaceCategory,
        status: PlaceStatus = .wantToGo
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
            sourceUrl: nil,
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
