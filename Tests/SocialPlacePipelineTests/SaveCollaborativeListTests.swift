import CoreLocation
import XCTest
@testable import SAVE

final class SaveCollaborativeListTests: XCTestCase {
    @MainActor
    func testSharedListLinkRoundTripsViewerRole() throws {
        var list = SaveCollaborativeList(title: "Tokyo cafes", note: "For Saturday")
        list.add(.from(place: place(name: "Onibus Coffee", category: .cafe)))

        let url = try XCTUnwrap(list.shareURL(role: .viewer))
        let payload = try XCTUnwrap(SaveSharedListPayload.from(url: url))

        XCTAssertEqual(payload.role, .viewer)
        XCTAssertEqual(payload.list.viewerRole, .viewer)
        XCTAssertEqual(payload.list.title, "Tokyo cafes")
        XCTAssertEqual(payload.list.items.first?.title, "Onibus Coffee")
    }

    @MainActor
    func testListAcceptsSavedPlaceAndUnsavedMapCandidateSnapshots() {
        var list = SaveCollaborativeList(title: "OC weekend")
        let saved = place(name: "Maru Coffee", category: .cafe)
        let candidate = SaveMapCandidate(
            title: "Bright Coffee Bar",
            subtitle: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            category: .cafe,
            rating: 4.6,
            reviewCount: 120,
            sourceURL: "https://maps.apple.com/?q=Bright%20Coffee",
            photoURL: "https://example.com/bright.jpg",
            businessPhotoURLs: ["https://example.com/bright-2.jpg"],
            evidence: ["Apple Maps result"]
        )

        list.add(.from(place: saved))
        list.add(.from(candidate: candidate))

        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items.map(\.source), [.savedPlace, .mapCandidate])
        XCTAssertEqual(list.items.last?.photoURLs, ["https://example.com/bright.jpg", "https://example.com/bright-2.jpg"])
    }

    @MainActor
    func testViewerJoinedListCannotAddItems() {
        var list = SaveCollaborativeList(title: "Viewer list", viewerRole: .viewer)
        list.add(.from(place: place(name: "Viewer Coffee", category: .cafe)))

        XCTAssertTrue(list.items.isEmpty)
        XCTAssertFalse(list.canEdit)
    }

    @MainActor
    func testEditorJoinedListCanAddItems() {
        var list = SaveCollaborativeList(title: "Editor list", viewerRole: .editor)
        list.add(.from(place: place(name: "Editor Coffee", category: .cafe)))

        XCTAssertEqual(list.items.count, 1)
        XCTAssertTrue(list.canEdit)
    }

    @MainActor
    func testFriendCanSaveListItemIntoOwnSave() {
        let candidate = SaveMapCandidate(
            title: "List Ramen",
            subtitle: "Los Angeles, CA",
            latitude: 34.0522,
            longitude: -118.2437,
            category: .food,
            rating: 4.7,
            sourceURL: "https://maps.apple.com/?q=List%20Ramen",
            evidence: ["Apple Maps result"]
        )
        let item = SaveListItem.from(candidate: candidate, addedByDisplayName: "Ezven")
        let saved = item.asPlace()

        XCTAssertEqual(saved.name, "List Ramen")
        XCTAssertEqual(saved.category, .food)
        XCTAssertEqual(saved.googleRating, 4.7)
        XCTAssertEqual(saved.recommender, "Ezven")
        XCTAssertEqual(saved.sourceUrl, "https://maps.apple.com/?q=List%20Ramen")
    }

    @MainActor
    func testListItineraryKeepsUnsavedItemsSeparateFromPlaceIds() {
        var list = SaveCollaborativeList(title: "Mixed plan")
        let saved = place(name: "Saved Cafe", category: .cafe)
        let unsaved = SaveMapCandidate(
            title: "Unsaved Sushi",
            subtitle: "Costa Mesa, CA",
            latitude: 33.6638,
            longitude: -117.9047,
            category: .food
        )

        list.add(.from(place: saved))
        list.add(.from(candidate: unsaved))
        let response = list.itineraryResponse()

        XCTAssertEqual(response.componentType, .tripItinerary)
        XCTAssertEqual(response.placeIds, [saved.id.uuidString])
        XCTAssertEqual(response.itineraryDays.first?.stops.count, 2)
        XCTAssertTrue(response.itineraryDays.first?.stops.last?.note?.contains("Map result") == true)
    }

    @MainActor
    private func place(name: String, category: PlaceCategory) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            googlePlaceId: nil,
            category: category,
            status: .wantToGo,
            rating: nil,
            note: "House pick",
            sourceUrl: "https://example.com/\(name)",
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
    }
}
