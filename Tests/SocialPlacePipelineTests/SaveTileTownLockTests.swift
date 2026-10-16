import XCTest
import UIKit
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
        XCTAssertTrue(home.contains("rootTabScrollClearance"))
        XCTAssertTrue(home.contains("home.search"))
        XCTAssertTrue(home.contains("home.featuredName"))
        XCTAssertTrue(home.contains("home.empty.capture"))
        XCTAssertTrue(home.contains("home.savedPlaces"))
        XCTAssertTrue(home.contains("home.trips"))
        XCTAssertTrue(home.contains("home.saves"))
        XCTAssertTrue(home.contains("headerIconButton("))
        XCTAssertTrue(home.contains("SavePixelChromeIcon"))
        XCTAssertTrue(home.contains("AtlasMetrics.statusBarHeight"))
        XCTAssertTrue(home.contains("allowsHitTesting(false)"))
        XCTAssertFalse(home.contains(".overlay(alignment: .topTrailing)"))
        XCTAssertFalse(home.contains(".opacity(0.02)"))
        XCTAssertTrue(home.contains(".accessibilityHidden(true)"))
        let moreSheet = memberBody("moreActionsSheet", in: home)
        let resting = memberBody("restingHome", in: home)
        let empty = memberBody("emptyHome", in: home)
        XCTAssertTrue(resting.contains("home.search.count"))
        XCTAssertTrue(moreSheet.contains("reviewQueuePreview"))
        XCTAssertFalse(resting.contains("reviewQueuePreview"))
        XCTAssertFalse(empty.contains("reviewQueuePreview"))
        XCTAssertTrue(home.contains("Waiting for review"))
        XCTAssertFalse(home.contains("map.lens.nearby"))
        XCTAssertFalse(home.contains("map.lens.saved"))
        XCTAssertFalse(home.contains("map.lens.friends"))
        XCTAssertFalse(home.contains("SaveTileTownMapLens"))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("SavePixelChromeIcon"))
        XCTAssertTrue(design.contains("lives under More"))
    }

    func testMapOwnsNearbySavedFriendsChipsOnTileTown() throws {
        let map = try source(at: "SAV-E/Views/TileTown/SaveTileTownRootMap.swift")
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(map.contains("SaveTileTownCanvas"))
        XCTAssertTrue(map.contains("AtlasMetrics.statusBarHeight"))
        XCTAssertFalse(map.contains(".padding(.top, 8)"))
        XCTAssertTrue(map.contains("SaveTileTownPeekCard"))
        XCTAssertTrue(map.contains("map.peek.card"))
        XCTAssertTrue(map.contains("accessibilityElement(children: .contain)"))
        XCTAssertTrue(map.contains("allowsPan: true"))
        XCTAssertTrue(map.contains(".frame(minHeight: 44)"))
        let town = try source(at: "SAV-E/Views/TileTown/SaveTileTownMap.swift")
        XCTAssertTrue(town.contains("interpolationQuality = .none"))
        XCTAssertTrue(town.contains("interpolation(.none)"))
        XCTAssertTrue(town.contains("enum SaveTileTownRaster"))
        XCTAssertTrue(town.contains("var allowsPan = false"))
        XCTAssertTrue(town.contains("map.tileTown.pan"))
        XCTAssertTrue(town.contains("map.peek.name"))
        XCTAssertTrue(town.contains("map.peek.subtitle"))
        XCTAssertTrue(town.contains("mapChromeHeight"))
        XCTAssertFalse(town.contains("addQuadCurve"))
        XCTAssertFalse(town.contains("struct Triangle"))
        XCTAssertTrue(map.contains("map.lens.nearby") || map.contains("map.lensRail"))
        XCTAssertTrue(map.contains("SaveTileTownMapLens"))
        XCTAssertTrue(map.contains("map.liveSurface"))
        let panel = try source(at: "SAV-E/Views/Map/SaveMapDrawerPanel.swift")
        XCTAssertTrue(panel.contains("Spacer(minLength: 0)"))
        XCTAssertTrue(panel.contains("alignment: .bottom"))
        XCTAssertTrue(panel.contains("SaveTileTownProductLock.mapChromeHeight"))
        XCTAssertTrue(root.contains("SaveTileTownRootMap("))
        XCTAssertFalse(root.contains("SaveAtlasInteractiveRootMap("))
    }

    func testStampLanguageIsOneSystem() throws {
        let stamp = try source(at: "SAV-E/Views/TileTown/SaveKraftStamp.swift")
        let home = try source(at: "SAV-E/Views/TileTown/SaveTileTownHomeView.swift")
        let passport = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        XCTAssertTrue(stamp.contains("enum SaveKraftStampFace"))
        XCTAssertTrue(stamp.contains("case scene"))
        XCTAssertTrue(stamp.contains("SaveKraftStampPixelArt"))
        XCTAssertTrue(stamp.contains("SavePixelDisplayText"))
        XCTAssertTrue(stamp.contains("enum SavePixelChromeIconKind"))
        XCTAssertTrue(stamp.contains("struct SavePixelChromeIcon"))
        XCTAssertTrue(stamp.contains("case locked"))
        XCTAssertTrue(stamp.contains("SaveSoftPixelAccentsLock.visibleStampText"))
        XCTAssertTrue(home.contains("SaveKraftStamp("))
        XCTAssertTrue(passport.contains("SaveKraftStamp("))
        XCTAssertTrue(passport.contains("face: .locked"))
        XCTAssertTrue(passport.contains("profile.stampGrid"))
        XCTAssertTrue(passport.contains("profile.stampProgress"))
        XCTAssertTrue(passport.contains("accessibilityIdentifier(\"profile.stampProgress\")"))
        XCTAssertTrue(passport.contains("onOpenPlace(place)"))
        XCTAssertTrue(passport.contains("rootTabScrollClearance"))
        XCTAssertTrue(passport.contains("???"))
    }

    func testFriendsIsPeopleFirstWithExplicitShareStatus() throws {
        let friends = try source(at: "SAV-E/Views/Origin/SaveFriendsView.swift")
        XCTAssertTrue(friends.contains("SavePostageSealAvatar"))
        XCTAssertTrue(friends.contains("Shared ·"))
        XCTAssertTrue(friends.contains("Wants to go ·"))
        XCTAssertFalse(friends.contains("Last at"))
        XCTAssertTrue(friends.contains("friends.mapStrip"))
        XCTAssertTrue(friends.contains("friends.empty"))
        XCTAssertTrue(friends.contains("friends.findFriends"))
        XCTAssertTrue(friends.contains("friends.author."))
        XCTAssertTrue(friends.contains("SharedAuthorPassport"))
        XCTAssertFalse(friends.contains(".disabled(store.isDemo)"))
        let store = try source(at: "SAV-E/ViewModels/SharedPostsStore.swift")
        XCTAssertTrue(store.contains("applyDemoFixture()"))
        XCTAssertTrue(store.contains("case .author(let id):"))
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

    func testApprovedArtworkIsBundledAndStampFacesStaySeparate() throws {
        let town = try XCTUnwrap(UIImage(named: "SavvyTownArtwork"))
        XCTAssertGreaterThan(town.size.width, 500)
        XCTAssertGreaterThan(town.size.height, 500)
        let atlas = try XCTUnwrap(UIImage(named: "SavvyStampArtwork")?.cgImage)
        XCTAssertEqual(atlas.width * 2, atlas.height * 3)
        let scenes: [SaveKraftStampScene] = [.harbor, .pine, .maple, .mountain, .lake, .cafe]
        let faces = scenes.map(SaveKraftStampPixelArt.image(for:))
        for face in faces {
            XCTAssertEqual(face.cgImage?.width, atlas.width / 3)
            XCTAssertEqual(face.cgImage?.height, atlas.height / 2)
        }
        XCTAssertEqual(Set(faces.compactMap { $0.pngData() }).count, 6)
    }

    private func memberBody(_ name: String, in source: String) -> String {
        guard let start = source.range(of: "private var \(name)") else { return "" }
        let after = source[start.upperBound...]
        let limit = after.range(of: "\n    private var ") ?? after.range(of: "\n    private func ")
        return String(source[start.lowerBound..<(limit?.lowerBound ?? after.endIndex)])
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
