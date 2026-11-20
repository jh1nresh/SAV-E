#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation
import XCTest
@testable import SAVE

@MainActor
final class LiveFriendMapPlacesTests: XCTestCase {
    private let firstID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let secondID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let thirdID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private let fourthID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

    func testDifferentAuthorsAtSameVenueKeepEveryPostAndStablePin() {
        let posts = [post(id: firstID, author: "Author A"), post(id: secondID, author: "Author B")]
        let values = LiveFriendMapPlace.projections(posts: posts)
        XCTAssertEqual(values.map(\.postID), [firstID, secondID])
        XCTAssertEqual(values.map(\.authorName), ["Author A", "Author B"])
        XCTAssertEqual(Set(values.map { $0.pin.id }).count, 2)
        XCTAssertEqual(values.map { $0.pin.id }, LiveFriendMapPlace.projections(posts: posts).map { $0.pin.id })
        XCTAssertEqual(values.map { $0.pin.place.name }, ["Fixture Cafe", "Fixture Cafe"])
    }

    func testVisitAndShareLabelsReflectSenderStatusWithoutRecommendationClaim() throws {
        let visited = try XCTUnwrap(LiveFriendMapPlace.projections(posts: [post(status: .visited)]).first)
        let shared = try XCTUnwrap(LiveFriendMapPlace.projections(posts: [post(status: .wantToGo)]).first)
        XCTAssertTrue(visited.hasVisited)
        XCTAssertFalse(shared.hasVisited)
        XCTAssertEqual(visited.statusTitle(.traditionalChinese), "Author・去過")
        XCTAssertEqual(shared.statusTitle(.traditionalChinese), "Author・分享")
        XCTAssertEqual(visited.statusTitle(.english), "Author・Visited")
        XCTAssertEqual(shared.statusTitle(.english), "Author・Shared")
        XCTAssertEqual(visited.statusName(.traditionalChinese), "去過")
        XCTAssertEqual(shared.statusName(.english), "Shared")
        XCTAssertEqual(visited.pin.origin, .shared)
        XCTAssertEqual(visited.pin.place.status, .wantToGo)
    }

    func testMissingAuthorUsesNeutralLocalizedFallbackWithoutRenamingRealAuthor() throws {
        let unknown = try XCTUnwrap(LiveFriendMapPlace.projections(posts: [post(author: " \n ")]).first)
        XCTAssertEqual(unknown.authorName, "朋友")
        XCTAssertEqual(unknown.statusTitle(.english), "Friend・Shared")
        XCTAssertEqual(unknown.statusTitle(.traditionalChinese), "朋友・分享")
        let named = try XCTUnwrap(LiveFriendMapPlace.projections(posts: [post(author: "朋友")]).first)
        XCTAssertEqual(named.statusTitle(.english), "朋友・Shared")
    }

    func testInvalidCoordinatesAndWithdrawnPostsAreOmitted() {
        var nan = post(); nan.latitude = .nan
        var missing = post(); missing.longitude = nil
        var zero = post(); zero.latitude = 0; zero.longitude = 0
        var gcj = post(); gcj.coordinate_system = .gcj02
        var outside = post(); outside.latitude = 91
        let values = LiveFriendMapPlace.projections(posts: [post(), nan, missing, zero, gcj, outside, post(visible: false)])
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.postID, firstID)
    }

    func testSenderMemoryAndAvatarNeverEnterRecipientPlaceOrSharePayload() throws {
        let source = post(status: .visited, avatar: "https://example.invalid/private-avatar.jpg")
        let value = try XCTUnwrap(LiveFriendMapPlace.projections(posts: [source]).first)
        XCTAssertNotNil(value.avatarURL)
        XCTAssertNil(value.pin.place.note)
        XCTAssertNil(value.pin.place.rating)
        XCTAssertNil(value.pin.place.googleRating)
        XCTAssertNil(value.pin.place.recommender)
        XCTAssertNil(value.pin.place.sourceImageUrl)
        XCTAssertTrue(value.pin.place.businessPhotoUrls?.isEmpty ?? true)
        let payload = value.pin.listPayload
        XCTAssertNil(payload.note)
        XCTAssertNil(payload.rating)
        XCTAssertNil(payload.sourceURL)
        XCTAssertTrue(payload.photoURLs.isEmpty)
        XCTAssertTrue(payload.addedByDisplayName.isEmpty)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(payload), as: UTF8.self).contains("private-"))
        XCTAssertEqual(source.caption, "private-caption")
        XCTAssertEqual(source.status, .visited)
    }

    func testAvatarURLPolicyAcceptsWebURLsAndRejectsUnsafeMetadata() throws {
        for url in ["https://example.invalid/avatar.jpg", "http://example.invalid/avatar.jpg"] {
            let value = try XCTUnwrap(LiveFriendMapPlace.projections(posts: [post(avatar: url)]).first)
            XCTAssertEqual(value.avatarURL?.absoluteString, url)
        }
        for url in ["relative/avatar.jpg", "file:///tmp/avatar.jpg", "https://", "https://user:password@example.invalid/avatar.jpg"] {
            let value = try XCTUnwrap(LiveFriendMapPlace.projections(posts: [post(avatar: url)]).first)
            XCTAssertNil(value.avatarURL)
        }
    }

    func testSameNormalizedVenueGroupsAllAuthorsWithoutLosingTheirStatuses() throws {
        let first = post(id: firstID, author: "Author A", status: .visited, name: "Fixture  Cafe")
        var nearby = post(id: secondID, author: "Author B", name: " fixture cafe\n")
        nearby.latitude = 25.030004
        nearby.longitude = 121.540004
        let values = LiveFriendMapPlace.projections(posts: [first, nearby])
        let groups = LiveFriendMapPlace.groupedByVenue(values)
        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.map(\.postID), [firstID, secondID])
        XCTAssertEqual(group.map(\.authorName), ["Author A", "Author B"])
        XCTAssertEqual(group.map { $0.statusName(.traditionalChinese) }, ["去過", "分享"])
        XCTAssertEqual(group.first?.pin.coordinate.latitude, first.latitude)
        XCTAssertEqual(group.last?.pin.coordinate.latitude, nearby.latitude)
    }

    func testOtherNamesAndDistantBranchesStaySeparateWithStableGroupAndPostOrder() {
        let first = post(id: firstID, name: "Fixture Cafe")
        let differentName = post(id: secondID, name: "Another Cafe")
        var distantBranch = post(id: thirdID, name: "Fixture Cafe")
        distantBranch.latitude = 25.04
        let repeatedVenue = post(id: fourthID, status: .visited, name: "FIXTURE CAFE")
        let values = LiveFriendMapPlace.projections(posts: [first, differentName, distantBranch, repeatedVenue])
        let expected = [[firstID, fourthID], [secondID], [thirdID]]
        XCTAssertEqual(LiveFriendMapPlace.groupedByVenue(values).map { $0.map(\.postID) }, expected)
        XCTAssertEqual(LiveFriendMapPlace.groupedByVenue(values).map { $0.map(\.postID) }, expected)
    }

    private func post(id: UUID? = nil, author: String = "Author", status: PlaceStatus = .wantToGo,
                      visible: Bool = true, avatar: String? = nil, name: String = "Fixture Cafe") -> SharedPlacePost {
        SharedPlacePost(id: id ?? firstID, name: name, address: "Fixture Street 1",
                        latitude: 25.03, longitude: 121.54, coordinate_system: .wgs84,
                        category: PlaceCategory.cafe.rawValue, status: status, stars: 4.5,
                        caption: "private-caption", shared_at: "2026-11-14T06:00:00Z",
                        author_id: (id ?? firstID).uuidString, author_name: author, author_handle: nil,
                        author_avatar_url: avatar, visible_to_followers: visible, photo_count: 3)
    }
}
#endif
