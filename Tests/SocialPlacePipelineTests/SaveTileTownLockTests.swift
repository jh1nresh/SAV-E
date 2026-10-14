import XCTest
@testable import SAVE

@MainActor
final class SaveTileTownLockTests: XCTestCase {
    func testFounderLockSupersedesMapKitSoftPixelBase() {
        XCTAssertTrue(SaveTileTownProductLock.productMapBaseIsTileTown)
        XCTAssertFalse(SaveTileTownProductLock.homeShowsMapFilterChips)
        XCTAssertTrue(SaveTileTownProductLock.mapShowsNearbySavedFriendsChips)
        XCTAssertEqual(SaveTileTownProductLock.passportGoal(for: 4), 12)
        XCTAssertEqual(SaveTileTownProductLock.passportGoal(for: 12), 12)
        XCTAssertEqual(SaveTileTownProductLock.passportGoal(for: 13), 24)
    }

    func testTabBarBibleUsesQuietLineIconsAndCoralPlus() throws {
        XCTAssertEqual(
            SaveRootTab.allCases.map(\.atlasIcon),
            ["house", "map", "plus", "person.2", "book.closed"]
        )
        let bar = try source(at: "Prototypes/AtlasPostcard/Sources/Components.swift")
        XCTAssertTrue(bar.contains("AtlasPalette.coral"))
        XCTAssertFalse(bar.contains("AtlasPalette.mint.opacity(0.62)"))
        XCTAssertTrue(bar.contains("selection == item"))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("coral on the active destination only"))
        XCTAssertTrue(design.contains("full-pixel tile-town"))
        XCTAssertTrue(design.contains("superseded for the map base"))
    }

    func testHomeChromeOmitsMapLensesAndKeepsSearch() throws {
        let home = try source(at: "SAV-E/Views/TileTown/SaveTileTownHomeView.swift")
        XCTAssertTrue(home.contains("SaveTileTownCanvas"))
        XCTAssertTrue(home.contains("home.tileTown"))
        XCTAssertTrue(home.contains("home.cluesBar"))
        XCTAssertTrue(home.contains("Recent stamps") || home.contains("home.recentSaves"))
        XCTAssertTrue(home.contains("SaveKraftStamp"))
        XCTAssertTrue(home.contains("home.search"))
        XCTAssertTrue(home.contains("home.featuredName"))
        XCTAssertTrue(home.contains("home.empty.capture"))
        XCTAssertTrue(home.contains("home.savedPlaces"))
        XCTAssertTrue(home.contains("home.trips"))
        XCTAssertTrue(home.contains("home.saves"))
        XCTAssertFalse(home.contains("map.lens.nearby"))
        XCTAssertFalse(home.contains("map.lens.saved"))
        XCTAssertFalse(home.contains("map.lens.friends"))
        XCTAssertFalse(home.contains("SaveTileTownMapLens"))
    }

    func testMapOwnsNearbySavedFriendsChipsOnTileTown() throws {
        let map = try source(at: "SAV-E/Views/TileTown/SaveTileTownRootMap.swift")
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(map.contains("SaveTileTownCanvas"))
        XCTAssertTrue(map.contains("map.lens.nearby") || map.contains("map.lensRail"))
        XCTAssertTrue(map.contains("SaveTileTownMapLens"))
        XCTAssertTrue(map.contains("map.liveSurface"))
        XCTAssertTrue(root.contains("SaveTileTownRootMap("))
        XCTAssertFalse(root.contains("SaveAtlasInteractiveRootMap("))
    }

    func testStampLanguageIsOneSystem() throws {
        let stamp = try source(at: "SAV-E/Views/TileTown/SaveKraftStamp.swift")
        let home = try source(at: "SAV-E/Views/TileTown/SaveTileTownHomeView.swift")
        let passport = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        XCTAssertTrue(stamp.contains("enum SaveKraftStampFace"))
        XCTAssertTrue(stamp.contains("case locked"))
        XCTAssertTrue(stamp.contains("SaveSoftPixelAccentsLock.visibleStampText"))
        XCTAssertTrue(home.contains("SaveKraftStamp("))
        XCTAssertTrue(passport.contains("SaveKraftStamp("))
        XCTAssertTrue(passport.contains("face: .locked"))
        XCTAssertTrue(passport.contains("profile.stampGrid"))
        XCTAssertTrue(passport.contains("???"))
    }

    func testFriendsIsPeopleFirstWithLastAt() throws {
        let friends = try source(at: "SAV-E/Views/Origin/SaveFriendsView.swift")
        XCTAssertTrue(friends.contains("SavePostageSealAvatar"))
        XCTAssertTrue(friends.contains("Last at"))
        XCTAssertTrue(friends.contains("friends.mapStrip"))
        XCTAssertTrue(friends.contains("friends.empty"))
        XCTAssertTrue(friends.contains("friends.findFriends"))
        XCTAssertFalse(friends.contains("friends.invite"))
        let posts = try JSONDecoder().decode([SharedPlacePost].self, from: Data(
            """
            [
              {
                "id": "11111111-1111-4111-8111-111111111111",
                "name": "Harbor Town",
                "address": "Water",
                "category": "attraction",
                "status": "visited",
                "stars": null,
                "caption": null,
                "shared_at": "2026-10-12T10:00:00.000Z",
                "author_id": "alex",
                "author_name": "Alex",
                "author_handle": null,
                "author_avatar_url": null,
                "visible_to_followers": true
              },
              {
                "id": "22222222-2222-4222-8222-222222222222",
                "name": "Pine View",
                "address": "Forest",
                "category": "attraction",
                "status": "wantToGo",
                "stars": null,
                "caption": null,
                "shared_at": "2026-10-13T10:00:00.000Z",
                "author_id": "alex",
                "author_name": "Alex",
                "author_handle": null,
                "author_avatar_url": null,
                "visible_to_followers": true
              }
            ]
            """.utf8
        ))
        let rows = SaveFriendLastAt.rows(from: posts)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].lastPost.name, "Pine View")
    }

    func testTileTownLotsStayStableAndUnique() {
        let first = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let assigned = SaveTileTownLayout.assignments(for: [first, second])
        XCTAssertEqual(Set(assigned.values).count, 2)
        XCTAssertEqual(
            SaveTileTownLayout.assignments(for: [first, second])[first],
            assigned[first]
        )
    }

    func testThemeOwnsTileTownMaterials() throws {
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        XCTAssertTrue(theme.contains("enum SaveTileTownPalette"))
        XCTAssertTrue(theme.contains("8FBF6A"))
        XCTAssertTrue(theme.contains("7EC8E3"))
        XCTAssertTrue(theme.contains("F4E6C8"))
        XCTAssertFalse(theme.contains("FFF8EE"))
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
