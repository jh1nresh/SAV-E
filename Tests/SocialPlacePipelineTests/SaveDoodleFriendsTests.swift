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
        XCTAssertEqual(SaveDoodleFriendAvatar.initial(from: "Leo"), "L")
        XCTAssertEqual(SaveDoodleFriendSticker.symbolName(for: .cafe), "cup.and.saucer")
        XCTAssertEqual(SaveDoodleFriendSticker.kind(name: "Grey Cafe", category: "cafe"), .coffee)
        XCTAssertEqual(SaveDoodleFriendSticker.kind(name: "Fangzhuanchang Noodles", category: "food"), .noodle)
        XCTAssertEqual(SaveDoodleFriendSticker.kind(name: "Temple of Heaven Park", category: "attraction"), .lantern)
        XCTAssertTrue(SaveDoodleFriendSticker.usesHillMark(name: "Jingshan Hill"))
        XCTAssertFalse(SaveDoodleFriendSticker.usesHillMark(name: "Temple of Heaven Park"))
        XCTAssertFalse(SaveDoodleFriendSticker.showsColor(for: .wantToGo))
        XCTAssertTrue(SaveDoodleFriendSticker.showsColor(for: .visited))
    }

    func testProductionFriendsIsDoodleNotTileTown() throws {
        let friends = try source(at: "SAV-E/Views/Origin/SaveFriendsView.swift")
        XCTAssertTrue(friends.contains("SaveDisplayTitle"))
        XCTAssertTrue(friends.contains("pointSize: 34"))
        XCTAssertTrue(friends.contains("locksPointSize: true"))
        XCTAssertTrue(friends.contains("traditionalChinese: \"朋友\""))
        XCTAssertTrue(friends.contains("SaveDoodleFriendAvatar"))
        XCTAssertTrue(friends.contains("SaveDoodleFriendSticker"))
        XCTAssertTrue(friends.contains("SaveDoodleDashedDivider"))
        XCTAssertTrue(friends.contains("SaveDottedBackground()"))
        XCTAssertTrue(friends.contains("SaveLayout.screenMargin"))
        XCTAssertTrue(friends.contains("friends.connections"))
        XCTAssertTrue(friends.contains("Invite"))
        XCTAssertTrue(friends.contains("accessibilityLabel(language.localized(english: \"Invite\""))
        XCTAssertTrue(friends.contains("frame(minHeight: 28)"))
        XCTAssertFalse(friends.contains("frame(height: SaveLayout.chipHeight)"))
        XCTAssertFalse(friends.contains("Manage following"))
        XCTAssertTrue(friends.contains("Open \\(row.lastPost.name)"))
        XCTAssertTrue(friends.contains("P2 4341083578, 4343545980"))
        XCTAssertFalse(friends.contains(".lineLimit(1)"))
        XCTAssertTrue(friends.contains("Text(row.authorName)"))
        XCTAssertFalse(friends.contains("""
                        Text(row.authorName)
                            .font(SaveAtlasType.strong(17))
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .lineLimit(1)
"""))
        XCTAssertFalse(friends.contains("withAnimation"))
        XCTAssertFalse(friends.contains(".animation("))
        XCTAssertTrue(friends.contains("SaveAtlasPalette.ink"))
        XCTAssertTrue(friends.contains("SaveAtlasPalette.forest"))
        XCTAssertTrue(friends.contains("lineWidth: 2.5"))
        XCTAssertTrue(friends.contains("pointSize: 32"))
        XCTAssertTrue(friends.contains("SaveAtlasType.strong(24)"))
        XCTAssertTrue(friends.contains("SaveAtlasType.display(17)"))
        XCTAssertTrue(friends.contains("frame(minHeight: 57"))
        XCTAssertTrue(friends.contains("SaveDoodleFriendHill"))
        XCTAssertTrue(friends.contains("usesHillMark"))
        XCTAssertTrue(friends.contains("showsColor(for:"))
        XCTAssertTrue(friends.contains(".accessibilityValue(\"1\")"))
        XCTAssertFalse(friends.contains("pointSize: 48"))
        XCTAssertFalse(friends.contains("SaveLayout.stickerArt"))
        XCTAssertFalse(friends.contains("--uitest-friends-width="))
        XCTAssertFalse(friends.contains("uiTestFriendsWidth"))
        XCTAssertTrue(friends.contains("showsColor(for: row.lastPost.status)"))
        XCTAssertTrue(friends.contains("filled: visited"))
        XCTAssertTrue(friends.contains("friends.retry"))
        XCTAssertTrue(friends.contains("SocialLoadError(centered: true"))
        XCTAssertTrue(friends.contains("SaveFriendsDotGrid"))
        XCTAssertFalse(friends.contains("visited: false"))
        XCTAssertTrue(friends.contains("SaveDoodleSticker("))
        XCTAssertFalse(friends.contains("SaveDoodleFriendStickerArt"))
        XCTAssertFalse(friends.contains("SaveDoodle.stampGold"))
        XCTAssertFalse(friends.contains("SaveDoodle.stampRed"))
        XCTAssertFalse(friends.contains("SaveDoodle.washGreen"))
        XCTAssertTrue(friends.contains("friends.findFriends"))
        XCTAssertTrue(friends.contains("friends.loading"))
        XCTAssertFalse(friends.contains("foregroundStyle(Color.white)"))
        let store = try source(at: "SAV-E/ViewModels/SharedPostsStore.swift")
        XCTAssertTrue(store.contains("friendsTownPosts"))
        XCTAssertTrue(store.contains("--uitest-friends-loading"))
        XCTAssertTrue(store.contains("--uitest-friends-error"))
        XCTAssertTrue(store.contains("case .feed, .author:"))
        XCTAssertTrue(store.contains("P2 4336028740"))
        XCTAssertTrue(store.contains("P2 4344156753"))
        XCTAssertTrue(store.contains("Grey Cafe"))
        XCTAssertTrue(store.contains("Fangzhuanchang Noodles"))
        XCTAssertTrue(store.contains("Temple of Heaven Park"))
        XCTAssertTrue(store.contains("Jingshan Hill"))
        XCTAssertTrue(store.contains("PlaceStatus.wantToGo, \"mia\""))
        XCTAssertTrue(store.contains(".wantToGo, \"leo\""))
        XCTAssertTrue(store.contains(".visited, \"kai\""))
        XCTAssertTrue(store.contains(".visited, \"ana\""))
        let artwork = try source(at: "SAV-E/Views/Origin/SharedPostViews.swift")
        XCTAssertTrue(artwork.contains("SaveDoodleFriendSticker"))
        XCTAssertTrue(artwork.contains("showsColor(for: post.status)"))
        XCTAssertFalse(artwork.contains("Image(systemName: post.icon)"))
        XCTAssertTrue(artwork.contains("traditionalChinese: \"重試\""))
        XCTAssertTrue(store.contains("\"Mia\""))
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
        XCTAssertTrue(design.contains("Codex packet spec §7.4"))
        XCTAssertTrue(design.contains("32pt"))
        XCTAssertTrue(design.contains("34pt"))
        XCTAssertTrue(design.contains("zh-Hant also Iansui"))
        XCTAssertTrue(design.contains("coffee / noodle / lantern / hill"))
        XCTAssertTrue(design.contains("outlined if the friend only saved"))
        XCTAssertTrue(design.contains("ProductionTargets/friends.png"))
        XCTAssertFalse(design.contains("There is no 0.90 pixel gate"))
        XCTAssertFalse(design.contains("is not adopted"))
        XCTAssertFalse(design.contains("即將推出"))
        XCTAssertFalse(friends.contains("即將推出"))
        let evidence = try source(at: "docs/evidence/pr296/README.md")
        XCTAssertTrue(evidence.contains("coffee / noodle / lantern / hill"))
        XCTAssertTrue(evidence.contains("outlined if saved, colored if visited"))
        XCTAssertTrue(evidence.contains("real 375 / 390 / 430"))
        XCTAssertFalse(evidence.contains("Official `.temple` (v2 lantern not adopted)"))
        XCTAssertFalse(evidence.contains("--uitest-friends-width"))
        XCTAssertTrue(design.contains("no animation (F-B11)"))
        XCTAssertFalse(design.contains("Parity target is DESIGN v2 `friends-light.png`"))
        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(content.contains("requestsSocialConnections = true; selectedRootTab = .profile"))
        XCTAssertTrue(content.contains("PassportConnectionsView (Friends section)"))
    }

    func testFriendsParityTargetIsTheDoodleMockAtExactly90() throws {
        let script = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        XCTAssertTrue(script.contains("five-tab-friends*)"))
        XCTAssertTrue(script.contains("screen=\"friends\""))
        XCTAssertTrue(script.contains("destination_screens=(home saves plan map)"))
        XCTAssertTrue(script.contains("parity_screens=(home saves plan map friends capture paywall passport)"))
        XCTAssertFalse(
            script
                .split(separator: "\n")
                .contains { $0.trimmingCharacters(in: .whitespaces) == "parity_screens=(home saves plan map)" }
        )
        XCTAssertTrue(script.contains("Home deferral on #290 does not apply to Friends"))
        XCTAssertTrue(script.contains("captured_from_prototype=1"))
        XCTAssertTrue(
            script.contains("testCaptureFourLockedScreens"),
            "destination mode still runs the four-screen prototype XCTest"
        )
        XCTAssertFalse(script.contains("FRIENDS_IGNORE_RECT"))
        XCTAssertFalse(script.contains("0,565,402,48"))
        let parity = try source(at: "Prototypes/AtlasPostcard/Scripts/VisualParity.swift")
        XCTAssertTrue(parity.contains("[--mask mask.png]"))
        XCTAssertFalse(parity.contains("[--ignore-rect x,y,w,h]"))
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
        XCTAssertTrue(readme.contains("testCaptureFourLockedScreens"))
        XCTAssertTrue(readme.contains("not Friends evidence"))
        XCTAssertTrue(readme.contains("Codex packet spec §7.4"))
        XCTAssertTrue(readme.contains("0.90 against"))
        XCTAssertTrue(readme.contains("Home deferral on #290 does not apply"))
        XCTAssertFalse(readme.contains("Shared map strip"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("attach(app, name: \"five-tab-friends\")"))
        XCTAssertTrue(rail.contains("friends-empty-\\(language)"))
        XCTAssertTrue(rail.contains("friends-dynamic-type-xxxl"))
        XCTAssertTrue(rail.contains("friends-loading"))
        XCTAssertTrue(rail.contains("friends-error"))
        XCTAssertTrue(rail.contains("friends.retry"))
        XCTAssertFalse(rail.contains("friends-coming-soon"))
        XCTAssertFalse(rail.contains("five-tab-friends-coming-soon"))
        XCTAssertTrue(rail.contains("func testFriendsWidth375"))
        XCTAssertTrue(rail.contains("func testFriendsWidth390"))
        XCTAssertTrue(rail.contains("func testFriendsWidth430"))
        XCTAssertTrue(rail.contains("friends-375"))
        XCTAssertTrue(rail.contains("friends-390"))
        XCTAssertTrue(rail.contains("friends-430"))
        XCTAssertFalse(rail.contains("--uitest-friends-width="))
        XCTAssertTrue(rail.contains("ProductionTargets/friends.png"))
        XCTAssertTrue(rail.contains("packet §7.4"))
        XCTAssertTrue(rail.contains("Home deferral on #290 does not"))
        let evidence = try source(at: "docs/evidence/pr296/README.md")
        XCTAssertTrue(evidence.contains("real 0.90 gate"))
        XCTAssertTrue(evidence.contains("real 375 / 390 / 430"))
        XCTAssertFalse(evidence.contains("--uitest-friends-width"))
        let workflow = try source(at: ".github/workflows/ios.yml")
        XCTAssertTrue(workflow.contains("light-home"))
        XCTAssertTrue(workflow.contains("testFriendsWidth375"))
        XCTAssertTrue(workflow.contains("testFriendsWidth390"))
        XCTAssertTrue(workflow.contains("testFriendsWidth430"))
        XCTAssertTrue(workflow.contains("iPhone-SE-3rd-generation"))
        XCTAssertTrue(workflow.contains("iPhone-14"))
        XCTAssertTrue(workflow.contains("iPhone-16-Pro-Max"))
        XCTAssertTrue(workflow.contains("friends-375"))
        XCTAssertFalse(workflow.contains("--uitest-friends-width="))
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
