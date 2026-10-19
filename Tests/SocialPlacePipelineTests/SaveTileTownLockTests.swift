import XCTest
import UIKit
import SwiftUI
import CoreText
import Metal
@testable import SAVE

@MainActor
final class SaveTileTownLockTests: XCTestCase {
    func testBundledPixelFontHasLatinAndTraditionalChineseGlyphs() throws {
        _ = SaveAtlasType.body(16)
        let font = try XCTUnwrap(UIFont(name: SaveAtlasType.pixelFontName, size: 16))
        XCTAssertEqual(font.fontName, SaveAtlasType.pixelFontName)
        let characters = Array("Savvy地圖護照朋友".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font as CTFont, characters, &glyphs, characters.count))
        XCTAssertFalse(glyphs.contains(0))
    }

    func testPixelShaderIsBundledAndStampPerforationsStayInsideBounds() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        XCTAssertTrue(library.functionNames.contains("savePixelate"))
        for size in [CGSize(width: 164, height: 64), CGSize(width: 72, height: 96), CGSize(width: 2, height: 2)] {
            let bounds = CGRect(origin: .zero, size: size)
            let path = SavePostcardScallopedRectangle(depth: 3, pitch: 9).path(in: bounds)
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(path.boundingRect))
            path.forEach { element in
                switch element {
                case .quadCurve, .curve: XCTFail("Pixel perforations must have straight edges")
                default: break
                }
            }
        }
    }

    func testNormalMapDirectionRetainsRootLensAndPassportContract() {
        XCTAssertFalse(SaveTileTownProductLock.productMapBaseIsTileTown)
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
        XCTAssertTrue(design.contains("MapKit"))
    }

    func testHomeChromeOmitsMapLensesAndKeepsSearch() throws {
        let home = try source(at: "SAV-E/Views/TileTown/SaveTileTownHomeView.swift")
        XCTAssertFalse(home.contains("SaveTileTownCanvas"))
        XCTAssertTrue(home.contains("Map("))
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

    func testMapOwnsNearbySavedFriendsChipsWithNativeGeography() throws {
        let map = try source(at: "SAV-E/Views/TileTown/SaveTileTownRootMap.swift")
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertFalse(map.contains("SaveTileTownCanvas"))
        XCTAssertTrue(map.contains("MapView("))
        XCTAssertTrue(map.contains("AtlasMetrics.statusBarHeight"))
        XCTAssertFalse(map.contains(".padding(.top, 8)"))
        XCTAssertTrue(map.contains("SaveTileTownPeekCard"))
        XCTAssertTrue(map.contains("map.peek.card"))
        XCTAssertTrue(map.contains("accessibilityElement(children: .contain)"))
        XCTAssertTrue(map.contains("tracksVisibleRegion: true"))
        XCTAssertFalse(map.contains("SaveTileTownLayout"))
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
        let nativeMap = try source(at: "SAV-E/Views/Map/MapView.swift")
        XCTAssertTrue(nativeMap.contains("map.liveSurface"))
        XCTAssertFalse(map.contains("accessibilityIdentifier(\"map.liveSurface\")"))
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
        XCTAssertTrue(passport.contains("accessibilityElement(children: .contain)"))
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
        XCTAssertFalse(friends.contains("SaveTileTownCanvas"))
        XCTAssertTrue(friends.contains("sharedPlacesSummary"))
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

    func testHomeMapPreviewRejectsInvalidAndProviderOnlyCoordinates() throws {
        let valid = try XCTUnwrap(ReviewDemoSeed.places().first)
        let invalidCoordinates: [(Double, Double)] = [
            (0, 0), (.nan, 121), (25, .infinity), (91, 121), (25, -181)
        ]
        for (latitude, longitude) in invalidCoordinates {
            var invalid = valid
            invalid.latitude = latitude
            invalid.longitude = longitude
            XCTAssertTrue(SaveHomeMapPreview.places(from: [mapPresentation(invalid)]).isEmpty)
        }
        var providerOnly = valid
        providerOnly.coordinateSystem = .gcj02
        XCTAssertTrue(SaveHomeMapPreview.places(from: [mapPresentation(providerOnly)]).isEmpty)
        let preview = SaveHomeMapPreview.places(from: [mapPresentation(providerOnly), mapPresentation(valid)])
        XCTAssertEqual(preview.map(\.id), [valid.id])
        XCTAssertEqual(preview.first?.latitude, valid.latitude)
        XCTAssertEqual(preview.first?.longitude, valid.longitude)
    }

    func testHomeMapDoesNotInventPinsFromPresentationOnlyCoordinates() {
        let clue = AtlasPlacePresentation(
            id: UUID().uuidString, name: "Unconfirmed clue", area: "",
            region: nil, photoURL: nil, latitude: 25.033, longitude: 121.565,
            relativeDay: "", note: ""
        )
        XCTAssertTrue(SaveHomeMapPreview.places(from: [clue]).isEmpty)
        XCTAssertTrue(SaveHomeMapPreview.places(from: []).isEmpty)
    }

    private func mapPresentation(_ place: Place) -> AtlasPlacePresentation {
        AtlasPlacePresentation(
            id: place.id.uuidString, name: place.name, area: place.address,
            region: nil, photoURL: nil, latitude: place.latitude, longitude: place.longitude,
            relativeDay: "", note: "", searchPlace: place
        )
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

    func testCategoryArtworkUsesExistingPlaceCategoryAndSeparateFaces() throws {
        let fixtures: [(String, String, SaveKraftStampScene)] = [
            ("Bar Benfiddich", "bar", .bar), ("The Siam Hotel", "stay", .hotel),
            ("Guerrilla Tacos", "food", .restaurant), ("Fujin Tree 353 Cafe", "cafe", .cafe),
            ("Daan Forest Park", "attraction", .pine), ("Ramen Shop", "food", .noodle),
            ("Bookshop", "shopping", .shop), ("Unknown place", "", .house)
        ]
        for (name, category, expected) in fixtures {
            XCTAssertEqual(SaveKraftStampScene.from(name: name, category: category), expected)
        }
        // A name mentioning a landscape cannot override a known business category.
        XCTAssertEqual(SaveKraftStampScene.from(name: "Pine View", category: "stay"), .hotel)
        XCTAssertEqual(SaveKraftStampScene.from(name: "Ichiran Shibuya", category: "food", detail: "Tonkotsu ramen"), .noodle)
        let art = try XCTUnwrap(UIImage(named: "SavvyCategoryStampArtwork")?.cgImage)
        XCTAssertEqual(art.width * 2, art.height * 3)
        let scenes: [SaveKraftStampScene] = [.bar, .hotel, .restaurant, .noodle, .shop, .house]
        let faces = scenes.map(SaveKraftStampPixelArt.image(for:))
        XCTAssertEqual(Set(faces.compactMap { $0.pngData() }).count, 6)
        for face in faces {
            XCTAssertEqual(face.cgImage?.width, art.width / 3)
            XCTAssertEqual(face.cgImage?.height, art.height / 2)
        }
    }

    func testFriendPortraitsAreStableAndBundled() throws {
        let atlas = try XCTUnwrap(UIImage(named: "SavvyFriendPortraits")?.cgImage)
        let identities = (0..<100).map { "author-\($0)" }
        XCTAssertEqual(Set(identities.map(SavePostageSealAvatar.portraitIndex(for:))).count, 6)
        let faces = identities.map(SavePostageSealAvatar.portraitImage(for:))
        XCTAssertEqual(Set(faces.compactMap { $0.pngData() }).count, 6)
        for face in faces {
            XCTAssertEqual(face.cgImage?.width, atlas.width / 3)
            XCTAssertEqual(face.cgImage?.height, atlas.height / 2)
        }
        XCTAssertEqual(SavePostageSealAvatar.portraitIndex(for: "alex"), 1)
        XCTAssertEqual(Set(["alex", "jordan", "taylor"].map(SavePostageSealAvatar.portraitIndex(for:))).count, 3)
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
