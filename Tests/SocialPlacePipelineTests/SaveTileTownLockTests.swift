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
        XCTAssertTrue(bar.contains("hidesTitle"))
        XCTAssertTrue(bar.contains("AtlasPalette.strokeWidth"))
        XCTAssertTrue(bar.contains("iconView"))
        XCTAssertEqual(AtlasTabBarMetrics.raisedControlStrokeWidth, 0)
        XCTAssertEqual(AtlasPalette.strokeWidth, 2)
        let root = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(root.contains("hidesTitle: { $0.isCaptureControl }"))
        XCTAssertTrue(root.contains("SavePixelChromeIcon("))
        XCTAssertTrue(root.contains("pointSize: 24"))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("coral on the active destination only"))
        XCTAssertTrue(design.contains("full-pixel tile-town"))
        XCTAssertTrue(design.contains("superseded for the map base"))
        XCTAssertTrue(design.contains("no visible \"Save\" label"))
    }

    func testCaptureTabKeepsAccessibilityNameWithoutVisibleSaveLabel() throws {
        XCTAssertEqual(SaveRootTab.capture.atlasTitle, "Save")
        XCTAssertEqual(SaveRootTab.capture.title(language: .english), "Save")
        XCTAssertEqual(SaveRootTab.capture.title(language: .traditionalChinese), "收藏")
        let bar = try source(at: "Prototypes/AtlasPostcard/Sources/Components.swift")
        XCTAssertTrue(bar.contains(".accessibilityLabel(displayTitle?(item) ?? item[keyPath: title])"))
        XCTAssertTrue(bar.contains("if !hidesTitle(item)"))
        XCTAssertTrue(bar.contains("accessibilityPrefix"))
        XCTAssertTrue(bar.contains("item[keyPath: title].lowercased()"))
        let root = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(root.contains("accessibilityPrefix: \"root.tab\""))
        XCTAssertTrue(root.contains("hidesTitle: { $0.isCaptureControl }"))
    }

    func testTownPinsRemainTappableOnHomeAndMap() throws {
        let town = try source(at: "SAV-E/Views/TileTown/SaveTileTownMap.swift")
        XCTAssertTrue(town.contains("map.tilePin.\\(pin.id.uuidString)"))
        XCTAssertTrue(town.contains("showsPins"))
        XCTAssertTrue(town.contains("scaledToFillRect"))
        XCTAssertTrue(town.contains("@MainActor"))
        XCTAssertTrue(town.contains("imageCache"))
        XCTAssertTrue(town.contains("像素小鎮地圖"))
        XCTAssertTrue(town.contains("地圖章，\\(pin.name)"))
        XCTAssertTrue(town.contains("isSelected ? 32 : 28"))
        XCTAssertGreaterThanOrEqual(SaveTileTownRaster.houses.count, 32)
        XCTAssertTrue(town.contains("coastX"))
        XCTAssertTrue(town.contains("color(for: .grass).cgColor"))
        let home = try source(at: "SAV-E/Views/TileTown/SaveTileTownHomeView.swift")
        XCTAssertTrue(home.contains("home.tileTown"))
        XCTAssertTrue(home.contains("SaveTileTownCanvas"))
        XCTAssertTrue(home.contains("homeHeroHeight"))
        XCTAssertTrue(home.contains("onSelect: { id in presentation.onOpenPlace(id.uuidString) }"))
        XCTAssertFalse(home.contains(".frame(height: 168)"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("func testTileTownPinsAreTappableOnHomeAndMap"))
        XCTAssertTrue(rail.contains("identifier BEGINSWITH 'map.tilePin.'"))
        let peek = SaveTileTownRaster.scaledToFillRect(
            viewSize: CGSize(width: 360, height: SaveTileTownProductLock.homeHeroHeight)
        )
        XCTAssertEqual(peek.width, 360, accuracy: 0.01)
        XCTAssertEqual(peek.minY, 0, accuracy: 0.01)
        XCTAssertGreaterThan(peek.height, SaveTileTownProductLock.homeHeroHeight)
        let exact = SaveTileTownRaster.scaledToFillRect(
            viewSize: CGSize(
                width: CGFloat(SaveTileTownRaster.baseWidth),
                height: CGFloat(SaveTileTownRaster.baseHeight)
            )
        )
        XCTAssertEqual(
            exact,
            CGRect(
                x: 0,
                y: 0,
                width: CGFloat(SaveTileTownRaster.baseWidth),
                height: CGFloat(SaveTileTownRaster.baseHeight)
            )
        )
    }

    func testPixelDisplayFontIsOFLWithCJKFallbackAndSFBody() throws {
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        XCTAssertTrue(theme.contains("enum SavePixelType"))
        XCTAssertTrue(theme.contains("PixelifySans-SemiBold"))
        XCTAssertTrue(theme.contains("Fusion-Pixel-12px-Prop-zh-Hant-Regular"))
        XCTAssertTrue(theme.contains("kCTFontCascadeListAttribute"))
        XCTAssertTrue(theme.contains("UIFontMetrics"))
        XCTAssertTrue(theme.contains("fontDescriptor.withDesign(.rounded)"))
        XCTAssertFalse(theme.contains("Zpix"))
        XCTAssertFalse(theme.contains("zpix"))
        let stamp = try source(at: "SAV-E/Views/TileTown/SaveKraftStamp.swift")
        XCTAssertTrue(stamp.contains("struct SavePixelDisplayText"))
        XCTAssertTrue(stamp.contains("Text(text)"))
        XCTAssertTrue(stamp.contains("SavePixelType.display"))
        XCTAssertTrue(stamp.contains("SaveAtlasType.strong(size.title)"))
        XCTAssertFalse(stamp.contains("private static let glyphs"))
        let readme = try source(at: "SAV-E/Resources/PixelFont/README.md")
        XCTAssertTrue(readme.contains("SIL Open Font License"))
        XCTAssertTrue(readme.contains("Zpix"))
        XCTAssertTrue(readme.contains("not bundled"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent("SAV-E/Resources/PixelFont/zpix.ttf").path
        ))
        let info = try source(at: "SAV-E/Info.plist")
        XCTAssertTrue(info.contains("PixelFont/PixelifySans-Regular.ttf"))
        XCTAssertTrue(info.contains("PixelFont/fusion-pixel-12px-proportional-zh_hant.otf"))
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
        let peek = memberBody("peek", in: home)
        XCTAssertTrue(peek.contains("homeHeroHeight"))
        XCTAssertTrue(peek.contains("ZStack(alignment: .bottom)"))
        XCTAssertFalse(peek.contains(".frame(height: 168)"))
        XCTAssertTrue(peek.contains(".allowsHitTesting(false)"))
        XCTAssertFalse(home.contains(".overlay(alignment: .topTrailing)"))
        XCTAssertFalse(home.contains(".opacity(0.02)"))
        XCTAssertTrue(home.contains(".accessibilityHidden(true)"))
        let moreSheet = memberBody("moreActionsSheet", in: home)
        let resting = memberBody("restingHome", in: home)
        let empty = memberBody("emptyHome", in: home)
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
        XCTAssertTrue(map.contains("allowsPan: true"))
        XCTAssertTrue(map.contains(".frame(minHeight: 44)"))
        let town = try source(at: "SAV-E/Views/TileTown/SaveTileTownMap.swift")
        XCTAssertTrue(town.contains("interpolationQuality = .none"))
        XCTAssertTrue(town.contains("interpolation(.none)"))
        XCTAssertTrue(town.contains("nonisolated enum SaveTileTownRaster"))
        XCTAssertTrue(town.contains("paintIsometricTown"))
        XCTAssertTrue(town.contains("normalizedHouseAnchors"))
        XCTAssertTrue(town.contains("scaledToFillRect"))
        XCTAssertTrue(town.contains("alignment: .top"))
        XCTAssertTrue(town.contains("map.tilePin.\\(pin.id.uuidString)"))
        XCTAssertEqual(SaveTileTownRaster.houses.count, SaveTileTownLayout.lots.count)
        XCTAssertTrue(town.contains("var allowsPan = false"))
        XCTAssertTrue(town.contains("map.tileTown.pan"))
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
        XCTAssertFalse(root.contains("RootAtlasMapScreen()"))
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
        XCTAssertTrue(passport.contains("onOpenPlace(place)"))
        XCTAssertTrue(passport.contains("rootTabScrollClearance"))
        XCTAssertTrue(passport.contains("???"))
    }

    func testFriendsIsPeopleFirstWithLastAt() throws {
        let friends = try source(at: "SAV-E/Views/Origin/SaveFriendsView.swift")
        XCTAssertTrue(friends.contains("SavePostageSealAvatar"))
        XCTAssertTrue(friends.contains("Last at"))
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

    func testTownLotsStayOnVisibleLand() {
        let anchors = SaveTileTownRaster.normalizedHouseAnchors()
        XCTAssertEqual(anchors.count, 32)
        for point in anchors {
            XCTAssertGreaterThan(point.x, 0.20)
            XCTAssertLessThan(point.x, 0.65)
            XCTAssertGreaterThan(point.y, 0.04)
            XCTAssertLessThan(point.y, 0.82)
        }
        let mapFill = SaveTileTownRaster.scaledToFillRect(viewSize: CGSize(width: 360, height: 640))
        for lot in anchors {
            let point = CGPoint(
                x: mapFill.minX + lot.x * mapFill.width,
                y: mapFill.minY + lot.y * mapFill.height
            )
            XCTAssertGreaterThanOrEqual(point.x, 20, "Map pin x \(point.x) left the frame")
            XCTAssertLessThanOrEqual(point.x, 340, "Map pin x \(point.x) left the frame")
            XCTAssertGreaterThanOrEqual(point.y, 20, "Map pin y \(point.y) left the frame")
            XCTAssertLessThanOrEqual(point.y, 620, "Map pin y \(point.y) left the frame")
        }
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
        let overflow = (0..<40).map { index in
            UUID(uuidString: String(format: "10000000-0000-4000-8000-%012d", index))!
        }
        let spread = SaveTileTownLayout.assignments(for: overflow)
        XCTAssertEqual(Set(spread.values).count, overflow.count)
        XCTAssertGreaterThan(SaveTileTownLayout.lots.count, 16)
    }

    func testThemeOwnsTileTownMaterials() throws {
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        XCTAssertTrue(theme.contains("enum SaveTileTownPalette"))
        XCTAssertTrue(theme.contains("6BB34A"))
        XCTAssertTrue(theme.contains("3DB5DC"))
        XCTAssertTrue(theme.contains("E8D5A3"))
        XCTAssertTrue(theme.contains("F3E6C8"))
        let town = try source(at: "SAV-E/Views/TileTown/SaveTileTownMap.swift")
        XCTAssertTrue(town.contains("0x6BB34A"))
        XCTAssertTrue(town.contains("paintIsometricTown"))
        XCTAssertTrue(theme.contains("FFF9EB"))
        XCTAssertTrue(theme.contains("2F2E23"))
        XCTAssertTrue(theme.contains("EADDC6"))
        XCTAssertTrue(theme.contains("C9AF8B"))
        XCTAssertFalse(theme.contains("FFF8EE"))
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
