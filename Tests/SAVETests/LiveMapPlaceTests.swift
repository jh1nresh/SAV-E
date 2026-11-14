#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation
import XCTest
import MapKit
@testable import SAVE

@MainActor
final class LiveMapPlaceTests: XCTestCase {
    private let venueID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let listID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let otherListID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    func testSavedWGS84KeepsOriginalMemoryAndStableIdentity() throws {
        let original = savedFixture()
        let first = try XCTUnwrap(LiveMapPlace.saved(original))
        let repeated = try XCTUnwrap(LiveMapPlace.saved(original))
        XCTAssertEqual(first.id, repeated.id)
        XCTAssertEqual(first.listPayload.id, repeated.listPayload.id)
        XCTAssertEqual(first.place, original)
        XCTAssertEqual(first.origin, .saved)
        XCTAssertEqual(first.sourceLabel, "已收藏")
        XCTAssertEqual(first.coordinate.latitude, original.latitude)
        XCTAssertEqual(first.coordinate.longitude, original.longitude)
        XCTAssertEqual(first.listPayload.source, .savedPlace)
        XCTAssertEqual(first.listPayload.sourceID, original.id.uuidString)
    }

    func testSavedRejectsInvalidCoordinatesAndNonWGS84() {
        for (latitude, longitude) in invalidCoordinates {
            var place = savedFixture()
            place.latitude = latitude
            place.longitude = longitude
            XCTAssertNil(LiveMapPlace.saved(place), "Rejected coordinate: \(latitude),\(longitude)")
        }
        for system in [PlaceCoordinateSystem.gcj02, .bd09] {
            var place = savedFixture()
            place.coordinateSystem = system
            XCTAssertNil(LiveMapPlace.saved(place))
        }
    }

    func testSearchReconstructedMapItemsHaveStableVenueIdentity() throws {
        let first = try XCTUnwrap(LiveMapPlace.search(searchFixture()))
        let repeated = try XCTUnwrap(LiveMapPlace.search(searchFixture()))
        XCTAssertEqual(first.id, repeated.id)
        XCTAssertEqual(first.place.id, repeated.place.id)
        XCTAssertEqual(first.listPayload, repeated.listPayload)
        XCTAssertEqual(first.origin, .search)
        XCTAssertEqual(first.sourceLabel, "搜尋結果候選")
        XCTAssertEqual(first.place.name, "Fixture Cafe")
        XCTAssertEqual(first.place.locationProvider, .appleMaps)
        XCTAssertEqual(first.place.resolvedCoordinateSystem, .wgs84)
        XCTAssertEqual(first.listPayload.source, .mapCandidate)
    }

    func testSearchSameNameAtDifferentCoordinatesDoesNotCollide() throws {
        let first = try XCTUnwrap(LiveMapPlace.search(searchFixture()))
        let second = try XCTUnwrap(LiveMapPlace.search(searchFixture(latitude: 25.045)))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.place.id, second.place.id)
        XCTAssertNotEqual(first.listPayload.id, second.listPayload.id)
    }

    func testSearchRejectsZeroCoordinate() {
        XCTAssertNil(LiveMapPlace.search(searchFixture(latitude: 0, longitude: 0)))
    }

    func testTeamCandidateDiscardsSenderMemoryAndPreservesInput() throws {
        let item = teamFixture()
        let original = item
        XCTAssertFalse(item.photoURLs.isEmpty, "The privacy fixture must actually contain photos")
        XCTAssertNotNil(item.note)
        XCTAssertNotNil(item.rating)
        let projected = try XCTUnwrap(LiveMapPlace.shared(item, listID: listID))
        XCTAssertEqual(item, original)
        XCTAssertEqual(projected.origin, .shared)
        XCTAssertEqual(projected.sourceLabel, "隊伍候選")
        XCTAssertEqual(projected.listPayload.source, .mapCandidate)
        XCTAssertEqual(projected.place.status, .wantToGo)
        assertNoSenderMemory(projected.place)
        try assertPrivatePayloadIsEmpty(projected.listPayload)
    }

    func testFriendVisitedPostIsSharedCandidateWithoutVisitOrRecommendationMemory() throws {
        let post = postFixture()
        let original = post
        let first = try XCTUnwrap(LiveMapPlace.sharedPost(post))
        let repeated = try XCTUnwrap(LiveMapPlace.sharedPost(post))
        XCTAssertEqual(post, original)
        XCTAssertEqual(post.status, .visited)
        XCTAssertEqual(first.id, repeated.id)
        XCTAssertEqual(first.place.id, repeated.place.id)
        XCTAssertEqual(first.origin, .shared)
        XCTAssertEqual(first.sourceLabel, "朋友已分享")
        XCTAssertEqual(first.place.status, .wantToGo)
        XCTAssertEqual(first.listPayload.source, .mapCandidate)
        XCTAssertEqual(first.place.providerPlaceId, post.provider_place_id)
        assertNoSenderMemory(first.place)
        try assertPrivatePayloadIsEmpty(first.listPayload)
    }

    func testSharedSourcesRejectInvalidAndNonWGS84Coordinates() {
        for (latitude, longitude) in invalidCoordinates {
            var item = teamFixture()
            item.latitude = latitude
            item.longitude = longitude
            XCTAssertNil(LiveMapPlace.shared(item, listID: listID))
            var post = postFixture()
            post.latitude = latitude
            post.longitude = longitude
            XCTAssertNil(LiveMapPlace.sharedPost(post))
        }
        for system in [PlaceCoordinateSystem.gcj02, .bd09] {
            var item = teamFixture()
            item.coordinateSystem = system
            XCTAssertNil(LiveMapPlace.shared(item, listID: listID))
            var post = postFixture()
            post.coordinate_system = system
            XCTAssertNil(LiveMapPlace.sharedPost(post))
        }
        var missing = postFixture()
        missing.latitude = nil
        XCTAssertNil(LiveMapPlace.sharedPost(missing))
        missing = postFixture()
        missing.longitude = nil
        XCTAssertNil(LiveMapPlace.sharedPost(missing))
    }

    func testSavedSharePayloadAllowlistKeepsVenueAndTypedCoordinateIdentityOnly() throws {
        let source = savedFixture()
        let payload = try XCTUnwrap(LiveMapPlace.saved(source)).listPayload
        XCTAssertEqual(payload.title, source.name)
        XCTAssertEqual(payload.subtitle, source.address)
        XCTAssertEqual(payload.latitude, source.latitude)
        XCTAssertEqual(payload.longitude, source.longitude)
        XCTAssertEqual(payload.category, source.category)
        XCTAssertEqual(payload.coordinateSystem, .wgs84)
        XCTAssertEqual(payload.locationProvider, .googlePlaces)
        XCTAssertEqual(payload.googlePlaceId, source.googlePlaceId)
        try assertPrivatePayloadIsEmpty(payload)
        // Sanitizing a share must not erase the account's private saved memory.
        XCTAssertEqual(source.note, "PRIVATE_NOTE_SENTINEL")
        XCTAssertEqual(source.status, .visited)
        XCTAssertEqual(source.rating, 2.5)
    }

    func testListAndOriginNamespacesPreventIdentityCollisions() throws {
        let item = teamFixture()
        let first = try XCTUnwrap(LiveMapPlace.shared(item, listID: listID))
        let repeated = try XCTUnwrap(LiveMapPlace.shared(item, listID: listID))
        let anotherList = try XCTUnwrap(LiveMapPlace.shared(item, listID: otherListID))
        let saved = try XCTUnwrap(LiveMapPlace.saved(savedFixture()))
        let post = try XCTUnwrap(LiveMapPlace.sharedPost(postFixture()))
        XCTAssertEqual(first.id, repeated.id)
        XCTAssertEqual(first.listPayload.id, repeated.listPayload.id)
        XCTAssertEqual(Set([first.id, anotherList.id, saved.id, post.id]).count, 4)
        XCTAssertEqual(Set([first.place.id, anotherList.place.id, saved.place.id, post.place.id]).count, 4)
        XCTAssertEqual(Set([first.listPayload.id, anotherList.listPayload.id,
                            saved.listPayload.id, post.listPayload.id]).count, 4)
    }

    func testUnknownTeamCategoryStaysUnknownInSharedPayload() throws {
        var item = teamFixture()
        item.category = nil
        let projected = try XCTUnwrap(LiveMapPlace.shared(item, listID: listID))
        XCTAssertNil(projected.listPayload.category)
        XCTAssertEqual(projected.origin, .shared)
    }

    private var invalidCoordinates: [(Double, Double)] {
        [(.nan, 121.54), (25.03, .nan), (.infinity, 121.54),
         (0, 0), (90.01, 121.54), (25.03, 180.01)]
    }

    private func savedFixture() -> Place {
        Place(id: venueID, name: "Fixture Cafe", address: "Fixture Street 1",
              latitude: 25.03, longitude: 121.54, googlePlaceId: "ChIJ_fixture_public_id",
              category: .cafe, status: .visited, rating: 2.5, note: "PRIVATE_NOTE_SENTINEL",
              sourceUrl: "https://example.invalid/PRIVATE_URL_SENTINEL", sourcePlatform: .instagram,
              coordinateSystem: .wgs84, locationProvider: .googlePlaces,
              providerPlaceId: "fixture-provider-id", providerMapUrl: "https://example.invalid/private-map",
              sourceImageUrl: "https://example.invalid/PRIVATE_PHOTO_SENTINEL",
              businessPhotoUrls: ["https://example.invalid/PRIVATE_PHOTO_SENTINEL"],
              extractedDishes: ["PRIVATE_DISH_SENTINEL"], priceRange: "PRIVATE_PRICE_SENTINEL",
              recommender: "PRIVATE_AUTHOR_SENTINEL", googleRating: 4.8,
              googlePriceLevel: 3, openingHours: "PRIVATE_HOURS_SENTINEL", createdAt: timestamp,
              visibility: .privateMemory)
    }

    private func teamFixture() -> SaveListItem {
        var item = SaveListItem.from(place: savedFixture(), addedByDisplayName: "PRIVATE_AUTHOR_SENTINEL",
                                     addedAt: timestamp)
        item.id = venueID
        item.reviewCount = 123
        // Bypass URL normalization in `from(place:)`: exercise nonempty raw sender fields.
        item.photoURLs = ["https://example.invalid/PRIVATE_PHOTO_SENTINEL"]
        item.extraPlaceIds = ["PRIVATE_ALIAS_SENTINEL"]
        return item
    }

    private func postFixture() -> SharedPlacePost {
        SharedPlacePost(id: venueID, name: "Fixture Cafe", address: "Fixture Street 1",
                        latitude: 25.03, longitude: 121.54, google_place_id: "ChIJ_fixture_public_id",
                        coordinate_system: .wgs84, location_provider: .googlePlaces,
                        provider_place_id: "fixture-provider-id",
                        provider_map_url: "https://example.invalid/PRIVATE_URL_SENTINEL",
                        category: PlaceCategory.cafe.rawValue, status: .visited, stars: 4.5,
                        caption: "PRIVATE_NOTE_SENTINEL", shared_at: "2026-11-14T06:00:00Z",
                        author_id: "fixture-author", author_name: "PRIVATE_AUTHOR_SENTINEL",
                        author_handle: "PRIVATE_HANDLE_SENTINEL",
                        author_avatar_url: "https://example.invalid/PRIVATE_PHOTO_SENTINEL",
                        visible_to_followers: true, photo_count: 3, photo_version: "fixture-version")
    }

    private func searchFixture(latitude: Double = 25.03, longitude: Double = 121.54) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: latitude, longitude: longitude)))
        item.name = "Fixture Cafe"
        item.pointOfInterestCategory = .cafe
        return item
    }

    private func assertNoSenderMemory(_ place: Place, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(place.note, file: file, line: line)
        XCTAssertNil(place.rating, file: file, line: line)
        XCTAssertNil(place.googleRating, file: file, line: line)
        XCTAssertNil(place.recommender, file: file, line: line)
        XCTAssertNil(place.sourceUrl, file: file, line: line)
        XCTAssertNil(place.sourceImageUrl, file: file, line: line)
        XCTAssertTrue(place.businessPhotoUrls?.isEmpty ?? true, file: file, line: line)
    }

    private func assertPrivatePayloadIsEmpty(
        _ payload: SaveListItem, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertNil(payload.note, file: file, line: line)
        XCTAssertNil(payload.rating, file: file, line: line)
        XCTAssertNil(payload.reviewCount, file: file, line: line)
        XCTAssertNil(payload.sourceURL, file: file, line: line)
        XCTAssertTrue(payload.photoURLs.isEmpty, file: file, line: line)
        XCTAssertTrue(payload.addedByDisplayName.isEmpty, file: file, line: line)
        XCTAssertNil(payload.extraPlaceIds, file: file, line: line)
        XCTAssertNil(payload.providerMapUrl, file: file, line: line)
        let encoded = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        XCTAssertFalse(encoded.contains("PRIVATE_"), file: file, line: line)
    }
}
#endif
