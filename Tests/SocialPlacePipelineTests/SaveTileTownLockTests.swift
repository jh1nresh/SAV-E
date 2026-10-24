import XCTest
@testable import SAVE

@MainActor
final class SaveTileTownLockTests: XCTestCase {
    func testTileTownHasNoReachableProductPath() throws {
        let productFiles = [
            "SAV-E/App/ContentView.swift",
            "SAV-E/Views/Home/SaveRootViews.swift",
            "SAV-E/Views/Home/SaveDoodleHomeView.swift",
            "SAV-E/Views/Map/SaveDoodleMapView.swift",
            "SAV-E/Views/Capture/SaveCaptureFlowView.swift",
            "SAV-E/Views/Profile/SaveProPaywallView.swift",
            "SAV-E/Views/Origin/SaveFriendsView.swift",
            "SAV-E/Views/Onboarding/OnboardingView.swift",
        ]
        let forbidden = [
            "SaveTileTownCanvas(",
            "SaveTileTownRootMap(",
            "SaveTileTownHomeView(",
            "SavePixelChromeIcon(",
            "SaveKraftStamp(",
            "SaveKraftStampPixelArt(",
            "interpolationQuality = .none",
        ]
        for file in productFiles {
            let text = try source(at: file)
            for token in forbidden {
                XCTAssertFalse(text.contains(token), "\(file) must not reach \(token)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "SAV-E/Views/TileTown/SaveTileTownHomeView.swift"
            ).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "SAV-E/Views/TileTown/SaveTileTownRootMap.swift"
            ).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent("SAV-E/Resources/PixelFont").path
        ))
        let leftoverTown = try source(at: "SAV-E/Views/TileTown/SaveTileTownMap.swift")
        XCTAssertTrue(leftoverTown.contains("enum SaveTileTownProductLock"))
        XCTAssertFalse(leftoverTown.contains("struct SaveTileTownCanvas"))
        XCTAssertFalse(leftoverTown.contains("struct SaveTileTownPin"))
        XCTAssertFalse(leftoverTown.contains("map.tilePin.\\(pin.id.uuidString)"))
        XCTAssertFalse(leftoverTown.contains("showsPins"))
        XCTAssertFalse(leftoverTown.contains("enum SaveTileTownRaster"))
        XCTAssertFalse(leftoverTown.contains("enum SaveTileTownMapLens"))
        XCTAssertFalse(leftoverTown.contains("struct SaveTileTownPeekCard"))
        let friends = try source(at: "SAV-E/Views/Origin/SaveFriendsView.swift")
        XCTAssertFalse(friends.contains("friends.mapStrip"))
        XCTAssertTrue(friends.contains("friends.root"))
        XCTAssertTrue(friends.contains("friends.list"))
        XCTAssertTrue(friends.contains("friends.empty"))
        XCTAssertTrue(friends.contains("friends.findFriends"))
        XCTAssertTrue(friends.contains("friends.author."))
        XCTAssertFalse(friends.contains("SaveTileTownCanvas"))
        XCTAssertFalse(friends.contains("SaveTileTownPin"))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("Product navigation does not mount"))
        XCTAssertTrue(design.contains("TileTown Home, RootMap, or Canvas"))
    }

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
        XCTAssertEqual(AtlasPalette.strokeWidth, 1)
        let root = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(root.contains("hidesTitle: { $0.isCaptureControl }"))
        XCTAssertTrue(root.contains("SaveDoodleTabIcon("))
        XCTAssertFalse(root.contains("SavePixelChromeIcon("))
        XCTAssertTrue(root.contains("pointSize: 24"))
        let stamp = try source(at: "SAV-E/Views/TileTown/SaveKraftStamp.swift")
        XCTAssertTrue(stamp.contains("struct SaveDoodleTabIcon"))
        XCTAssertTrue(stamp.contains("lineWidth: 1.5"))
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
        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        XCTAssertTrue(town.contains("enum SaveTileTownProductLock"))
        XCTAssertFalse(town.contains("map.tilePin.\\(pin.id.uuidString)"))
        XCTAssertFalse(town.contains("map.tilePin."))
        XCTAssertFalse(town.contains("showsPins"))
        XCTAssertFalse(town.contains("struct SaveTileTownCanvas"))
        XCTAssertFalse(town.contains("struct SaveTileTownPin"))
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        XCTAssertFalse(home.contains("home.miniMap"))
        XCTAssertFalse(home.contains("Map("))
        XCTAssertFalse(home.contains("MKMapView"))
        XCTAssertFalse(home.contains("Map(initialPosition:"))
        XCTAssertFalse(home.contains("Annotation("))
        XCTAssertFalse(home.contains("onOpenMap"))
        XCTAssertFalse(home.contains("map.tilePin."))
        XCTAssertTrue(map.contains("map.tilePin.\\(item.place.id.uuidString)"))
        XCTAssertTrue(map.contains("map.tilePin."))
    }

    func testDisplayFontIsOFLWithCJKFallbackAndSFBody() throws {
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        XCTAssertTrue(theme.contains("enum SaveDisplayType"))
        XCTAssertTrue(theme.contains("static func fixed("))
        XCTAssertTrue(theme.contains("Caveat-SemiBold"))
        XCTAssertTrue(theme.contains("Iansui-Regular"))
        XCTAssertTrue(theme.contains("Iansui-SavvySubset"))
        XCTAssertTrue(theme.contains("PingFangTC-Regular"))
        XCTAssertTrue(theme.contains("kCTFontCascadeListAttribute"))
        XCTAssertTrue(theme.contains("UIFontMetrics"))
        XCTAssertTrue(theme.contains("fontDescriptor.withDesign(.rounded)"))
        XCTAssertFalse(theme.contains("Zpix"))
        XCTAssertFalse(theme.contains("zpix"))
        XCTAssertFalse(theme.contains("PixelifySans"))
        XCTAssertFalse(theme.contains("Fusion-Pixel"))
        XCTAssertFalse(theme.contains("enum SavePixelType"))
        let stamp = try source(at: "SAV-E/Views/TileTown/SaveKraftStamp.swift")
        XCTAssertTrue(stamp.contains("struct SaveDisplayTitle"))
        XCTAssertTrue(stamp.contains("Text(text)"))
        XCTAssertTrue(stamp.contains("SaveDisplayType.display"))
        XCTAssertTrue(stamp.contains("SaveAtlasType.strong(size.title)"))
        XCTAssertFalse(stamp.contains("struct SavePixelDisplayText"))
        XCTAssertFalse(stamp.contains("private static let glyphs"))
        let readme = try source(at: "SAV-E/Resources/DisplayFont/README.md")
        XCTAssertTrue(readme.contains("SIL Open Font License"))
        XCTAssertTrue(readme.contains("Caveat"))
        XCTAssertTrue(readme.contains("Iansui"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent("SAV-E/Resources/DisplayFont/LICENSES/caveat/OFL.txt").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent("SAV-E/Resources/DisplayFont/LICENSES/iansui/OFL.txt").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent("SAV-E/Resources/PixelFont").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent("SAV-E/Resources/PixelFont/zpix.ttf").path
        ))
        let info = try source(at: "SAV-E/Info.plist")
        XCTAssertTrue(info.contains("DisplayFont/Caveat-SemiBold.ttf"))
        XCTAssertTrue(info.contains("DisplayFont/Iansui-SavvySubset.ttf"))
        XCTAssertFalse(info.contains("PixelFont/"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "SAV-E/Resources/DisplayFont/edu-standard-4808.txt"
            ).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "SAV-E/Resources/DisplayFont/iansui-savvy-charset.txt"
            ).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "scripts/doodle-fonts/edu-standard-4808.txt"
            ).path
        ))
        let displayFont = repositoryRoot.appendingPathComponent("SAV-E/Resources/DisplayFont")
        let bundledTxt = try FileManager.default.contentsOfDirectory(atPath: displayFont.path)
            .filter { $0.hasSuffix(".txt") }
        XCTAssertEqual(bundledTxt, [], "DisplayFont must ship fonts and OFL licenses only")
    }

    func testHomeChromeOmitsMapLensesAndKeepsSearch() throws {
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        XCTAssertFalse(home.contains("SaveDoodleMiniMap"))
        XCTAssertFalse(home.contains("home.miniMap"))
        XCTAssertTrue(home.contains("home.review"))
        XCTAssertTrue(home.contains("accessibilityIdentifier(\"home.saves\")"))
        XCTAssertFalse(home.contains("home.openSaves"))
        XCTAssertTrue(home.contains("home.collected"))
        XCTAssertTrue(home.contains("home.empty.capture"))
        XCTAssertTrue(home.contains("home.savedPlaces"))
        XCTAssertTrue(home.contains("home.citySwitcher"))
        XCTAssertTrue(home.contains("lens.accessibilityIdentifier"))
        XCTAssertTrue(home.contains(".contentShape(Rectangle())"))
        let catalog = try source(at: "SAV-E/Services/SaveDoodleHomeCatalog.swift")
        XCTAssertTrue(catalog.contains("home.\\(rawValue)"))
        XCTAssertTrue(catalog.contains("case eat"))
        XCTAssertTrue(catalog.contains("case go"))
        XCTAssertTrue(home.contains("AtlasTabBarMetrics.height"))
        XCTAssertFalse(home.contains("rootTabScrollClearance"))
        XCTAssertTrue(home.contains("\"home.saves\""))
        XCTAssertFalse(home.contains("See all saves"))
        XCTAssertFalse(home.contains("accessibilityIdentifier(\"home.trips\")"))
        XCTAssertTrue(home.contains("SaveDisplayTitle"))
        XCTAssertTrue(home.contains("AtlasMetrics.statusBarHeight"))
        XCTAssertTrue(home.contains("allowsHitTesting(false)"))
        XCTAssertTrue(home.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(home.contains("home.search"))
        XCTAssertFalse(home.contains("SaveTileTownCanvas"))
        XCTAssertFalse(home.contains("map.lens.nearby"))
        XCTAssertFalse(home.contains("map.lens.saved"))
        XCTAssertFalse(home.contains("map.lens.friends"))
        XCTAssertFalse(home.contains("SaveTileTownMapLens"))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("SaveDoodleHomeView"))
        XCTAssertTrue(design.contains("Eat/Go"))
    }

    func testMapOwnsNearbySavedFriendsChipsOnTileTown() throws {
        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(map.contains(".mapStyle(.standard(emphasis: .automatic))"))
        XCTAssertTrue(map.contains("AtlasMetrics.statusBarHeight"))
        XCTAssertFalse(map.contains("emphasis: .muted"))
        XCTAssertFalse(map.contains(".saturation("))
        XCTAssertFalse(map.contains(".colorMultiply("))
        XCTAssertFalse(map.contains("SaveTileTownCanvas"))
        XCTAssertTrue(map.contains("map.placeSheet"))
        XCTAssertTrue(map.contains(".frame(minHeight: 44)") || map.contains("SaveLayout.minTap"))
        let town = try source(at: "SAV-E/Views/TileTown/SaveTileTownMap.swift")
        XCTAssertTrue(town.contains("mapChromeHeight"))
        XCTAssertTrue(town.contains("enum SaveTileTownProductLock"))
        XCTAssertFalse(town.contains("map.tilePin.\\(pin.id.uuidString)"))
        XCTAssertFalse(town.contains("map.tilePin."))
        XCTAssertFalse(town.contains("showsPins"))
        XCTAssertFalse(town.contains("interpolationQuality = .none"))
        XCTAssertFalse(town.contains("enum SaveTileTownRaster"))
        XCTAssertFalse(town.contains("struct SaveTileTownCanvas"))
        XCTAssertFalse(town.contains("addQuadCurve"))
        XCTAssertFalse(town.contains("struct Triangle"))
        XCTAssertTrue(map.contains("map.liveSurface"))
        XCTAssertTrue(map.contains("SaveDoodleSession"))
        XCTAssertTrue(map.contains("SaveDoodleHomeCatalog.listedPlaces("))
        XCTAssertTrue(map.contains("mapAccessibilityIdentifier"))
        XCTAssertTrue(map.contains("map.city"))
        XCTAssertTrue(map.contains("map.eatGo"))
        let panel = try source(at: "SAV-E/Views/Map/SaveMapDrawerPanel.swift")
        XCTAssertTrue(panel.contains("Spacer(minLength: 0)"))
        XCTAssertTrue(panel.contains("alignment: .bottom"))
        XCTAssertTrue(panel.contains("SaveTileTownProductLock.mapChromeHeight"))
        XCTAssertTrue(root.contains("SaveDoodleMapView("))
        XCTAssertFalse(root.contains("SaveTileTownRootMap("))
        XCTAssertFalse(root.contains("SaveAtlasInteractiveRootMap("))
        let friends = try source(at: "SAV-E/Views/Origin/SaveFriendsView.swift")
        XCTAssertFalse(friends.contains("SaveTileTownCanvas("))
        XCTAssertFalse(friends.contains("friends.mapStrip"))
        XCTAssertTrue(friends.contains("friends.root"))
        XCTAssertTrue(friends.contains("friends.list"))
    }

    func testStampLanguageIsOneSystem() throws {
        let stamp = try source(at: "SAV-E/Views/TileTown/SaveKraftStamp.swift")
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        let passport = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        XCTAssertTrue(stamp.contains("enum SaveKraftStampFace"))
        XCTAssertTrue(stamp.contains("case scene"))
        XCTAssertTrue(stamp.contains("SaveKraftStampPixelArt"))
        XCTAssertTrue(stamp.contains("SaveDisplayTitle"))
        XCTAssertTrue(stamp.contains("enum SavePixelChromeIconKind"))
        XCTAssertTrue(stamp.contains("struct SavePixelChromeIcon"))
        XCTAssertTrue(stamp.contains("case locked"))
        XCTAssertTrue(stamp.contains("SaveSoftPixelAccentsLock.visibleStampText"))
        XCTAssertTrue(home.contains("SaveDoodleCollectedMark"))
        XCTAssertTrue(passport.contains("SaveDoodlePassportPage("))
        XCTAssertFalse(passport.contains("PassportTileTownCollection"))
        XCTAssertFalse(passport.contains("SaveKraftStamp("))
        XCTAssertTrue(passport.contains("onOpenPlace: onOpenPlace"))
        let page = try source(at: "SAV-E/Views/Profile/SaveDoodlePassportView.swift")
        XCTAssertTrue(page.contains("profile.stampGrid"))
        XCTAssertTrue(page.contains("rootTabScrollClearance"))
    }

    func testFriendsIsPeopleFirstWithLastAt() throws {
        let friends = try source(at: "SAV-E/Views/Origin/SaveFriendsView.swift")
        XCTAssertTrue(friends.contains("SaveDoodleFriendAvatar"))
        XCTAssertTrue(friends.contains("last at"))
        XCTAssertTrue(friends.contains("SaveDoodleFriendSticker"))
        XCTAssertFalse(friends.contains("SavePostageSealAvatar"))
        XCTAssertFalse(friends.contains("friends.mapStrip"))
        XCTAssertFalse(friends.contains("SaveTileTownCanvas"))
        XCTAssertTrue(friends.contains("friends.empty"))
        XCTAssertTrue(friends.contains("friends.findFriends"))
        XCTAssertTrue(friends.contains("friends.author."))
        XCTAssertTrue(friends.contains("SharedAuthorPassport"))
        XCTAssertFalse(friends.contains(".disabled(store.isDemo)"))
        let store = try source(at: "SAV-E/ViewModels/SharedPostsStore.swift")
        XCTAssertTrue(store.contains("applyDemoFixture(items:"))
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

    func testThemeOwnsDoodleTokensAndTileTownMaterials() throws {
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        XCTAssertTrue(theme.contains("enum SaveTileTownPalette"))
        XCTAssertTrue(theme.contains("enum SaveDoodle"))
        XCTAssertTrue(theme.contains("enum SaveSpace"))
        XCTAssertTrue(theme.contains("enum SaveLayout"))
        XCTAssertTrue(theme.contains("8FBF6A"))
        XCTAssertTrue(theme.contains("7EC8E3"))
        XCTAssertTrue(theme.contains("F4E6C8"))
        XCTAssertTrue(theme.contains("FFF9EB"))
        XCTAssertTrue(theme.contains("1E1C19"))
        XCTAssertTrue(theme.contains("2F2E23"))
        XCTAssertTrue(theme.contains("EADDC6"))
        XCTAssertTrue(theme.contains("DCCFB9"))
        XCTAssertTrue(theme.contains("A39C8E"))
        XCTAssertTrue(theme.contains("D3E4C1"))
        XCTAssertTrue(theme.contains("D2E6EC"))
        XCTAssertTrue(theme.contains("C8372D"))
        XCTAssertTrue(theme.contains("B8902F"))
        XCTAssertTrue(theme.contains("static let cardRadius: CGFloat = 12"))
        XCTAssertTrue(theme.contains("static let strokeWidth: CGFloat = 1"))
        XCTAssertTrue(theme.contains("static let xl = SaveSpace.lg"))
        XCTAssertFalse(theme.contains("C9AF8B"))
        XCTAssertFalse(theme.contains("11161C"))
        XCTAssertFalse(theme.contains("FFF8EE"))
        XCTAssertEqual(SaveSpace.tight, 4)
        XCTAssertEqual(SaveSpace.xs, 8)
        XCTAssertEqual(SaveSpace.sm, 12)
        XCTAssertEqual(SaveSpace.md, 16)
        XCTAssertEqual(SaveSpace.lg, 24)
        XCTAssertEqual(SaveSpace.xl, 32)
        XCTAssertEqual(SaveSpace.xxl, 48)
        XCTAssertEqual(SaveTheme.Spacing.xl, 24)
        XCTAssertEqual(SaveLayout.screenMargin, 24)
        XCTAssertEqual(SaveAtlasPalette.cardRadius, 12)
        XCTAssertEqual(SaveAtlasPalette.strokeWidth, 1)
        XCTAssertTrue(theme.contains("PaperGrain"))
        XCTAssertTrue(theme.contains("PaperGrainDark"))
        XCTAssertTrue(theme.contains("resizingMode: .tile"))
        XCTAssertFalse(theme.contains("stride(from: CGFloat(8)"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "SAV-E/Resources/Assets.xcassets/PaperGrain.imageset/paper-grain@2x.png"
            ).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "SAV-E/Resources/Assets.xcassets/PaperGrainDark.imageset/paper-grain-dark@2x.png"
            ).path
        ))
    }

    func testWarmDarkModeIsUnlockedOnTheProductApp() throws {
        let info = try source(at: "SAV-E/Info.plist")
        XCTAssertFalse(info.contains("UIUserInterfaceStyle"))
        let project = try source(at: "project.yml")
        XCTAssertFalse(project.contains("UIUserInterfaceStyle: Light"))
        XCTAssertFalse(project.contains("INFOPLIST_KEY_UIUserInterfaceStyle"))
        let prototype = try source(at: "Prototypes/AtlasPostcard/Sources/AtlasPostcardApp.swift")
        XCTAssertFalse(prototype.contains("preferredColorScheme(.light)"))
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        XCTAssertTrue(theme.contains("dark: \"1E1C19\""))
        XCTAssertTrue(theme.contains("enum SaveDoodle"))
        XCTAssertTrue(theme.contains("PaperGrainDark"))
        XCTAssertTrue(theme.contains("colorScheme == .dark"))
        XCTAssertFalse(theme.contains("static let mutedMap"))
        XCTAssertFalse(theme.contains("static let mapOverlay"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("func testHomeAndPassportWarmDarkMode"))
        XCTAssertTrue(rail.contains("XCUIDevice.shared.appearance = appearance"))
        XCTAssertTrue(rail.contains("appearance: .dark"))
        XCTAssertTrue(rail.contains("-AppleInterfaceStyle"))
        XCTAssertTrue(rail.contains("--uitest-force-dark"))
        XCTAssertTrue(rail.contains("--uitest-force-light"))
        XCTAssertTrue(rail.contains("assertScreenshotBackground"))
        XCTAssertTrue(rail.contains("0x1E"))
        XCTAssertTrue(rail.contains("0xFF"))
        XCTAssertTrue(rail.contains("dark-home"))
        XCTAssertTrue(rail.contains("dark-passport"))
        let app = try source(at: "SAV-E/App/SaveApp.swift")
        XCTAssertTrue(app.contains("--uitest-force-dark"))
        XCTAssertTrue(app.contains("overrideUserInterfaceStyle"))
        XCTAssertTrue(app.contains("preferredColorScheme"))
        let viewportTheme = try source(at: "Prototypes/AtlasPostcard/Sources/Theme.swift")
        XCTAssertTrue(viewportTheme.contains("SaveAtlasPalette.canvas"))
        XCTAssertTrue(viewportTheme.contains("SaveDottedBackground()"))
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
