import XCTest
@testable import SAVE

@MainActor
final class SaveDoodleFriendsTests: XCTestCase {
    func testLastAtKeepsNewestPostPerAuthor() throws {
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
                "name": "Grey Cafe",
                "address": "Town",
                "category": "cafe",
                "status": "wantToGo",
                "stars": null,
                "caption": null,
                "shared_at": "2026-10-18T10:00:00.000Z",
                "author_id": "alex",
                "author_name": "Alex",
                "author_handle": null,
                "author_avatar_url": null,
                "visible_to_followers": true
              },
              {
                "id": "33333333-3333-4333-8333-333333333333",
                "name": "Temple of Heaven Park",
                "address": "Beijing",
                "category": "attraction",
                "status": "visited",
                "stars": null,
                "caption": null,
                "shared_at": "2026-10-13T10:00:00.000Z",
                "author_id": "kai",
                "author_name": "Kai",
                "author_handle": null,
                "author_avatar_url": null,
                "visible_to_followers": true
              }
            ]
            """.utf8
        ))
        let rows = SaveFriendLastAt.rows(from: posts)
        XCTAssertEqual(rows.map(\.authorID), ["alex", "kai"])
        XCTAssertEqual(rows[0].lastPost.name, "Grey Cafe")
        let now = ISO8601DateFormatter().date(from: "2026-10-20T10:00:00Z")!
        XCTAssertEqual(
            SaveFriendLastAt.lastAtText(rows[0].lastPost, language: .english, now: now),
            "last at Grey Cafe · 2d"
        )
        XCTAssertEqual(
            SaveFriendLastAt.lastAtText(rows[1].lastPost, language: .traditionalChinese, now: now),
            "最近在 Temple of Heaven Park · 1週"
        )
        XCTAssertEqual(SaveDoodleFriendAvatar.initial(from: "Mia"), "M")
        XCTAssertEqual(SaveDoodleFriendSticker.symbolName(for: .cafe), "cup.and.saucer")
    }

    func testProductionFriendsIsDoodleNotTileTown() throws {
        let friends = try source(at: "SAV-E/Views/Origin/SaveFriendsView.swift")
        XCTAssertTrue(friends.contains("SaveDisplayTitle"))
        XCTAssertTrue(friends.contains("pointSize: 34"))
        XCTAssertTrue(friends.contains("traditionalChinese: \"朋友\""))
        XCTAssertTrue(friends.contains("SaveDoodleFriendAvatar"))
        XCTAssertTrue(friends.contains("SaveDoodleFriendSticker"))
        XCTAssertTrue(friends.contains("SaveDoodleDashedDivider"))
        XCTAssertTrue(friends.contains("SaveDottedBackground()"))
        XCTAssertTrue(friends.contains("SaveLayout.screenMargin"))
        XCTAssertTrue(friends.contains("friends.connections"))
        XCTAssertTrue(friends.contains("Invite"))
        XCTAssertTrue(friends.contains("SaveFriendLastAt.lastAtText"))
        XCTAssertFalse(friends.contains("SavePostageSealAvatar"))
        XCTAssertFalse(friends.contains("friends.mapStrip"))
        XCTAssertFalse(friends.contains("SaveTileTownCanvas"))
        XCTAssertFalse(friends.contains("Shared map"))
        XCTAssertFalse(friends.contains("SaveTileTownPin"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "SAV-E/Views/TileTown/SavePostageSealAvatar.swift"
            ).path
        ))
        let stamp = try source(at: "SAV-E/Views/TileTown/SaveKraftStamp.swift")
        XCTAssertFalse(stamp.contains("struct SavePostageSealAvatar"))
        XCTAssertFalse(stamp.contains("enum SaveFriendLastAt"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("five-tab-friends"))
        XCTAssertTrue(rail.contains("dark-friends"))
        XCTAssertFalse(rail.contains("atlas-friends-town"))
        XCTAssertFalse(rail.contains("friends.mapStrip\"].waitForExistence"))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("SaveFriendsView"))
        XCTAssertTrue(design.contains("shared map stays hidden"))
    }

    func testFriendsParityTargetIsTheDoodleMockAtExactly90() throws {
        let script = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        XCTAssertTrue(script.contains("five-tab-friends*)"))
        XCTAssertTrue(script.contains("screen=\"friends\""))
        XCTAssertTrue(script.contains("for screen in home saves plan map friends; do"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "Prototypes/AtlasPostcard/Reference/ProductionTargets/friends.png"
            ).path
        ))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("attach(app, name: \"five-tab-friends\")"))
        XCTAssertTrue(rail.contains("ProductionTargets/friends.png"))
        XCTAssertTrue(rail.contains("at exactly 0.90"))
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
