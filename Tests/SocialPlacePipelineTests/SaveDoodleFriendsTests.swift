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
        XCTAssertEqual(rows[0].postCount, 2)
        let now = ISO8601DateFormatter().date(from: "2026-10-20T10:00:00Z")!
        XCTAssertEqual(
            SaveFriendLastAt.lastAtText(rows[0].lastPost, language: .english, now: now),
            "saved Grey Cafe · Oct 18"
        )
        XCTAssertEqual(
            SaveFriendLastAt.lastAtText(rows[0].lastPost, postCount: 2, language: .english, now: now),
            "2 places in Town · Oct 18"
        )
        XCTAssertEqual(
            SaveFriendLastAt.lastAtText(rows[1].lastPost, language: .english, now: now),
            "visited Temple of Heaven Park · Oct 13"
        )
        XCTAssertEqual(
            SaveFriendLastAt.relativeAge(from: "2026-10-20T08:00:00Z", now: now),
            "2h"
        )
        XCTAssertEqual(
            SaveFriendLastAt.relativeAge(from: "2026-10-19T10:00:00Z", now: now),
            "yesterday"
        )
        XCTAssertEqual(SaveDoodleFriendAvatar.initial(from: "Mia 林"), "M")
        XCTAssertEqual(SaveDoodleFriendAvatar.initial(from: "Leo"), "L")
        XCTAssertEqual(SaveDoodleFriendAvatar.initial(from: "阿哲"), "哲")
        XCTAssertEqual(SaveDoodleFriendAvatar.initial(from: "小雨"), "雨")
    }

    func testProductionFriendsIsDoodleNotTileTown() throws {
        let friends = try source(at: "SAV-E/Views/Origin/SaveFriendsView.swift")
        XCTAssertTrue(friends.contains("SaveDisplayTitle"))
        XCTAssertTrue(friends.contains("pointSize: 34"))
        XCTAssertTrue(friends.contains("traditionalChinese: \"朋友\""))
        XCTAssertTrue(friends.contains("SaveDoodleFriendAvatar"))
        XCTAssertTrue(friends.contains("SaveDoodleDashedDivider"))
        XCTAssertTrue(friends.contains("SaveDottedBackground()"))
        XCTAssertTrue(friends.contains("SaveLayout.screenMargin"))
        XCTAssertTrue(friends.contains("friends.connections"))
        XCTAssertTrue(friends.contains("＋ Invite"))
        XCTAssertTrue(friends.contains("最近動態 Recent"))
        XCTAssertTrue(friends.contains("SaveAtlasPalette.kraftLight"))
        XCTAssertTrue(friends.contains("SaveAtlasPalette.coral"))
        XCTAssertTrue(friends.contains("SaveAtlasPalette.forest"))
        XCTAssertFalse(friends.contains("SaveDoodleFriendSticker"))
        XCTAssertTrue(friends.contains("friends.findFriends"))
        XCTAssertFalse(friends.contains("foregroundStyle(Color.white)"))
        let store = try source(at: "SAV-E/ViewModels/SharedPostsStore.swift")
        XCTAssertTrue(store.contains("friendsTownPosts"))
        XCTAssertTrue(store.contains("紅橋市場"))
        XCTAssertTrue(store.contains("天壇公園"))
        XCTAssertTrue(store.contains("錦芳小吃"))
        XCTAssertTrue(store.contains("Mia 林"))
        XCTAssertTrue(store.contains("阿哲"))
        XCTAssertTrue(store.contains("小雨"))
        XCTAssertTrue(store.contains("Harbor Town"))
        XCTAssertTrue(friends.contains("SaveFriendLastAt.lastAtText"))
        XCTAssertFalse(friends.contains("SavePostageSealAvatar"))
        XCTAssertFalse(friends.contains("friends.mapStrip"))
        XCTAssertFalse(friends.contains("SaveTileTownCanvas"))
        XCTAssertFalse(friends.contains("Shared map"))
        XCTAssertTrue(friends.contains("HoP keeps the map strip off this tab"))
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
        XCTAssertTrue(rail.contains("friends.author.mia"))
        XCTAssertTrue(rail.contains("--uitest-friends-town"))
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
        XCTAssertFalse(script.contains("FRIENDS_IGNORE_RECT"))
        XCTAssertFalse(script.contains("0,565,402,48"))
        let parity = try source(at: "Prototypes/AtlasPostcard/Scripts/VisualParity.swift")
        XCTAssertTrue(parity.contains("ignoreRects"))
        XCTAssertTrue(parity.contains("[--ignore-rect x,y,w,h]"))
        let friendsPNG = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/friends.png"
        ))
        XCTAssertEqual([UInt8](friendsPNG.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(pngDimension(friendsPNG, at: 16), 402)
        XCTAssertEqual(pngDimension(friendsPNG, at: 20), 874)
        let friendsDarkPNG = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/friends-dark.png"
        ))
        XCTAssertEqual(pngDimension(friendsDarkPNG, at: 16), 402)
        XCTAssertEqual(pngDimension(friendsDarkPNG, at: 20), 874)
        let readme = try source(at: "Prototypes/AtlasPostcard/README.md")
        XCTAssertTrue(readme.contains("friends-light.png"))
        XCTAssertTrue(readme.contains("2026-10-20"))
        XCTAssertFalse(readme.contains("2026-10-19-doodle-v1-friends.png"))
        XCTAssertFalse(readme.contains("Shared map strip"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("attach(app, name: \"five-tab-friends\")"))
        XCTAssertTrue(rail.contains("ProductionTargets/friends.png"))
        XCTAssertTrue(rail.contains("at exactly 0.90"))
    }

    private func pngDimension(_ data: Data, at offset: Int) -> UInt32 {
        let bytes = [UInt8](data.subdata(in: offset..<(offset + 4)))
        return UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
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
