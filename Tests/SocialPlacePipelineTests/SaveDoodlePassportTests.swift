import XCTest
@testable import SAVE

@MainActor
final class SaveDoodlePassportTests: XCTestCase {
    func testVisitRanksFollowOneThreeFive() {
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 0), .none)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 1), .single)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 2), .single)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 3), .double)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 4), .double)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 5), .gold)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 9), .gold)
    }

    func testCitySlotsPadToTwelveAndColorVisited() {
        let suite = "save.doodle.passport.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SavePassportVisitStore(defaults: defaults)
        let now = Date()
        let duck = place("Duck", "Beijing, China", .food, status: .visited, createdAt: now)
        let cafe = place("Grey Cafe", "Beijing, China", .cafe, createdAt: now.addingTimeInterval(-1))
        let park = place("Tiantan", "Beijing, China", .attraction, createdAt: now.addingTimeInterval(-2))
        let tokyo = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food,
            createdAt: now.addingTimeInterval(-3)
        )
        let slots = SaveDoodlePassportCatalog.slots(
            from: [duck, cafe, park, tokyo],
            selection: .city("beijing"),
            locationDenied: true,
            visitStore: store
        )
        XCTAssertEqual(slots.count, 12)
        XCTAssertEqual(slots.compactMap(\.place?.name), ["Duck", "Grey Cafe", "Tiantan"])
        XCTAssertTrue(slots[0].isVisited)
        XCTAssertFalse(slots[1].isVisited)
        XCTAssertEqual(SaveDoodlePassportCatalog.visitedCount(in: [duck, cafe, park]), 1)
        XCTAssertEqual(SaveDoodlePassportCatalog.stickerKind(for: duck), .duck)
        XCTAssertEqual(SaveDoodlePassportCatalog.stickerKind(for: cafe), .coffee)
        XCTAssertEqual(SaveDoodleStickerKind.duck.officialSticker, .duck)
        XCTAssertEqual(SaveDoodleStickerKind.noodles.officialSticker, .noodle)
        for kind in SaveDoodleStickerKind.allCases {
            XCTAssertNotEqual(kind.officialSticker, .elephant)
        }
        XCTAssertNotEqual(
            SaveDoodleOfficialSticker.named(for: .attraction, placeName: "Elephant Park"),
            .elephant
        )
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCount(availableGridWidth: 311), 3)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCount(availableGridWidth: 326), 3)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCount(availableGridWidth: 338), 4)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCount(availableGridWidth: 366), 4)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCount(availableGridWidth: 0), 1)
    }

    func testDoodleFaceSlotsMatchThePassportMockGrid() {
        let slots = SaveDoodlePassportCatalog.doodleFaceSlots()
        XCTAssertEqual(slots.count, 12)
        XCTAssertEqual(slots.filter(\.isVisited).count, 4)
        XCTAssertEqual(
            slots.compactMap { slot -> SaveDoodleStickerKind? in
                if case let .place(_, kind, _) = slot.content { return kind }
                return nil
            },
            [
                .duck, .noodles, .temple, .lantern,
                .coffee, .hill, .bridge, .baozi,
                .tea, .bookstore, .bicycle, .ferris,
            ]
        )
        XCTAssertFalse(SaveDoodlePassportCatalog.usesDoodleFace)
        let unvisited = slots.compactMap { slot -> SaveDoodleStickerKind? in
            guard case let .place(_, kind, rank) = slot.content, rank == .none else { return nil }
            return kind
        }
        XCTAssertEqual(
            unvisited,
            [.coffee, .hill, .bridge, .baozi, .tea, .bookstore, .bicycle, .ferris]
        )
        XCTAssertEqual(Set(unvisited).count, unvisited.count)
        XCTAssertEqual(unvisited.filter(\.usesOfficialAsset), [.coffee])
        XCTAssertEqual(slots.compactMap(\.stampNumber), [1, 2, 3, 3])
    }

    func testEmptyCityScopeDoesNotExpandWorldwide() {
        let suite = "save.doodle.passport.empty-city.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let tokyo = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food
        )
        let slots = SaveDoodlePassportCatalog.slots(
            from: [tokyo],
            selection: .city("beijing"),
            locationDenied: true,
            visitStore: SavePassportVisitStore(defaults: defaults)
        )
        XCTAssertTrue(slots.isEmpty)
    }

    func testEmptyExplicitCityKeepsItsLabelAndPickerSelection() {
        let tokyo = place("Ichiran", "Tokyo, Japan", .food)
        for locationDenied in [false, true] {
            for places in [[], [tokyo]] {
                let selection = SaveDoodlePassportCatalog.resolvedSelection(
                    .city("beijing"), places: places, locationDenied: locationDenied
                )
                XCTAssertEqual(selection, .city("beijing"))
                XCTAssertTrue(SaveDoodlePassportCatalog.cityPlaces(
                    from: places, selection: selection, locationDenied: locationDenied
                ).isEmpty)
                let selected = SaveDoodlePassportCatalog.pickerCityGroups(
                    from: places, selection: selection
                ).filter { $0.id == "beijing" }
                XCTAssertEqual(selected.count, 1)
                XCTAssertEqual(selected.first?.count, 0)
                XCTAssertEqual(selected.first?.englishName, "Beijing")
                XCTAssertEqual(selected.first?.chineseName, "北京")
            }
        }
    }

    func testPassportCityPickerKeepsExistingCountsAndNearYouFallback() {
        let beijing = place("Duck", "Beijing, China", .food)
        let groups = SaveDoodlePassportCatalog.pickerCityGroups(
            from: [beijing], selection: .city("beijing")
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.count, 1)
        XCTAssertEqual(SaveDoodlePassportCatalog.resolvedSelection(
            .nearYou, places: [beijing], locationDenied: false
        ), .nearYou)
        XCTAssertEqual(SaveDoodlePassportCatalog.resolvedSelection(
            .nearYou, places: [beijing], locationDenied: true
        ), .city("beijing"))
    }

    func testHomeCollectedProgressUsesActualCityCount() {
        let places = [
            place("Duck", "Beijing, China", .food, status: .visited),
            place("Cafe", "Beijing, China", .cafe)
        ]
        let progress = SaveDoodlePassportCatalog.progress(in: places, collectionMode: .homeCollected)
        XCTAssertEqual(progress.visited, 1)
        XCTAssertEqual(progress.total, 2)
        let empty = SaveDoodlePassportCatalog.progress(in: [], collectionMode: .homeCollected)
        XCTAssertEqual(empty.visited, 0)
        XCTAssertEqual(empty.total, 0)
        let root = SaveDoodlePassportCatalog.progress(in: places, collectionMode: .collection)
        XCTAssertEqual(root.visited, 1)
        XCTAssertEqual(root.total, 12)
    }

    func testRecordingAVisitClimbsTheStampRank() {
        let suite = "save.doodle.passport.visit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        var day = Date(timeIntervalSince1970: 1_760_000_000)
        let store = SavePassportVisitStore(defaults: defaults, now: { day })
        let mapHistory = SaveDoodleVisitStore(defaults: defaults, now: { day })
        let id = UUID()
        XCTAssertEqual(store.rank(for: id, visited: false), .none)
        XCTAssertEqual(store.recordVisit(for: id), 1)
        XCTAssertEqual(store.recordVisit(for: id), 1, "The second surface cannot double-count the same day")
        XCTAssertEqual(store.rank(for: id, visited: true), .single)
        for _ in 2...3 {
            day = day.addingTimeInterval(86_400)
            XCTAssertTrue(mapHistory.recordVisit(for: id))
        }
        XCTAssertEqual(store.rank(for: id, visited: true), .double)
        for _ in 4...5 {
            day = day.addingTimeInterval(86_400)
            XCTAssertTrue(mapHistory.recordVisit(for: id))
        }
        XCTAssertEqual(store.rank(for: id, visited: true), .gold)
        XCTAssertTrue(mapHistory.undoToday(for: id))
        XCTAssertEqual(store.rank(for: id, visited: true), .double)
        XCTAssertEqual(SavePassportVisitStore(defaults: defaults).count(for: id), 4)
    }

    func testRootIsDoodleGridAndFlagsOffTileTownMissions() throws {
        let passport = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        let page = try source(at: "SAV-E/Views/Profile/SaveDoodlePassportView.swift")
        XCTAssertTrue(passport.contains("NavigationStack {"))
        XCTAssertTrue(
            passport.contains("if isRootTab {\n                passportRoot"),
            "Root-tab Passport must reuse ContentView's stack; a nested stack breaks Home → Saves"
        )
        XCTAssertTrue(passport.contains("NavigationStack {\n                    passportRoot"))
        XCTAssertTrue(passport.contains("SaveDoodlePassportPage("))
        XCTAssertTrue(passport.contains("SaveDoodlePassportFlags.showTodayMissions"))
        XCTAssertTrue(passport.contains("SaveDoodlePassportFlags.showFieldStreak"))
        XCTAssertTrue(passport.contains("SaveDoodlePassportFlags.showStampLedger"))
        XCTAssertFalse(SaveDoodlePassportFlags.showTodayMissions)
        XCTAssertFalse(SaveDoodlePassportFlags.showFieldStreak)
        XCTAssertFalse(SaveDoodlePassportFlags.showStampLedger)
        XCTAssertFalse(passport.contains("PassportTileTownCollection"))
        XCTAssertFalse(passport.contains("SaveKraftStamp("))
        XCTAssertTrue(page.contains("profile.stampGrid"))
        XCTAssertTrue(page.contains("SaveDoodlePassportCatalog.screenMargin"))
        XCTAssertTrue(page.contains("SaveDisplayTitle("))
        XCTAssertTrue(page.contains("locksPointSize: true"))
        XCTAssertTrue(page.contains("traditionalChinese: \"護照\""))
        XCTAssertFalse(page.contains("profile.settings"))
        XCTAssertTrue(page.contains("onOpenCollected"))
        XCTAssertTrue(passport.contains("opensCollected"))
        XCTAssertTrue(passport.contains("if opensCollected"))
        XCTAssertFalse(passport.contains("navigationDestination(isPresented: $opensCollected)"))
        XCTAssertTrue(
            passport.contains("""
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("passport.root")
            """),
            "passport.root without contain flattens stampProgress and profile.root"
        )
        XCTAssertTrue(passport.contains("profile.collected.root"))
        XCTAssertTrue(passport.contains("SharedPostsGrid"))
        XCTAssertTrue(page.contains("SaveHaptics.stamp()"))
        let stickers = try source(at: "SAV-E/Views/Profile/SaveDoodlePassportStickers.swift")
        XCTAssertTrue(stickers.contains("SaveDoodleOfficialSticker"))
        XCTAssertTrue(stickers.contains("SaveDoodlePassportCatalog.visitedStickerSize"))
        XCTAssertTrue(stickers.contains("officialSticker"))
        XCTAssertFalse(stickers.contains("dieCut"))
        XCTAssertFalse(stickers.contains("249 / 255"))
        XCTAssertFalse(stickers.contains("SaveDoodlePassportStickerArt"))
        XCTAssertTrue(stickers.contains(".fill(SaveDoodlePassportChrome.stampBase)"))
        let catalog = try source(at: "SAV-E/Views/Profile/SaveDoodlePassportCatalog.swift")
        XCTAssertTrue(catalog.contains("SaveDoodleHomeProgressCatalog.cityPlaces"))
        XCTAssertTrue(catalog.contains("SaveDoodleHomeProgressCatalog.visitedCount"))
        XCTAssertFalse(catalog.contains("enum SaveDoodleHomeProgressCatalog"))
        XCTAssertTrue(page.contains("columnCount("))
        XCTAssertTrue(page.contains("physicalScreenWidth:"))
        XCTAssertTrue(page.contains("MemoMascotMark"))
        XCTAssertFalse(page.contains("SaveDoodleElephant"))
        XCTAssertTrue(page.contains("passport.empty"))
        XCTAssertTrue(page.contains("showsEmptyPassport"))
        XCTAssertTrue(page.contains("legendSwatchSize"))
        XCTAssertFalse(page.contains(".frame(width: 8, height: 8)"))
        XCTAssertTrue(page.contains("SaveDoodleHandwriting"))
        XCTAssertTrue(page.contains("SaveDoodleSolidCaret"))
        XCTAssertTrue(page.contains("SaveDoodlePassportCatalog.titlePointSize"))
        XCTAssertTrue(page.contains("single ring 1 · double ring 3 · gold 5"))
        XCTAssertFalse(page.contains("Text(\"▾\")"))
        XCTAssertFalse(page.contains("Capsule()"))
        XCTAssertTrue(page.contains("guard stampingID == nil else { return }"))
        XCTAssertTrue(page.contains("if stampingID != nil { return true }"))
        XCTAssertTrue(page.contains("profile.stamp.visitError"))
        XCTAssertTrue(page.contains("Couldn’t update this place. Please try again."))
        XCTAssertTrue(catalog.contains("stableHash(place.id.uuidString)"))
        XCTAssertTrue(catalog.contains("if city.isEmpty { return [] }"))
        XCTAssertFalse(catalog.contains("let city = scoped.isEmpty ? places : scoped"))
        XCTAssertFalse(catalog.contains("Hasher()"))
        XCTAssertFalse(catalog.contains("place.name, \"\\(index)\""))
        XCTAssertTrue(catalog.contains("cardHeight: CGFloat = 80"))
        XCTAssertTrue(catalog.contains("stampNumber"))
        XCTAssertTrue(stickers.contains("Circle()"))
        XCTAssertFalse(stickers.contains("RoundedRectangle"))
        XCTAssertFalse(page.contains("--uitest-passport-width="))
        XCTAssertTrue(page.contains(".accessibilityValue(\"\\(columns)\")"))
        XCTAssertTrue(page.contains("SaveDoodlePassportCatalog.panelTop"))
        XCTAssertTrue(page.contains(".fill(SaveDoodlePassportChrome.panelFill)"))
        XCTAssertTrue(stickers.contains("SaveDoodlePassportNumberStamp"))
        XCTAssertTrue(stickers.contains("SaveDisplayType.fixed(14)"))
        XCTAssertTrue(stickers.contains("usesOfficialAsset"))
        XCTAssertTrue(stickers.contains("SaveDoodlePassportUniqueGlyph"))
        XCTAssertTrue(stickers.contains("stampOffset"))
        XCTAssertTrue(stickers.contains("enum SaveDoodlePassportUnvisitedArt"))
        XCTAssertTrue(stickers.contains("resolvedImageName(for:"))
        XCTAssertFalse(stickers.contains("struct SaveDoodlePassportStamp"))
    }

    func testUnvisitedColorArtLookupUsesDraftPlateNamesAt75() throws {
        let expected: [(SaveDoodleStickerKind, String)] = [
            (.coffee, "DoodlePlateCoffeeColor"),
            (.hill, "DoodlePlateMountainColor"),
            (.bridge, "DoodlePlateBridgeColor"),
            (.baozi, "DoodlePlateBaoziColor"),
            (.tea, "DoodlePlateTeaColor"),
            (.bookstore, "DoodlePlateBookColor"),
            (.bicycle, "DoodlePlateBicycleColor"),
            (.ferris, "DoodlePlateFerrisColor"),
        ]
        XCTAssertEqual(SaveDoodlePassportUnvisitedArt.assetNames.count, 8)
        XCTAssertEqual(
            Set(SaveDoodlePassportUnvisitedArt.assetNames.keys),
            Set(expected.map(\.0))
        )
        XCTAssertEqual(SaveDoodlePassportUnvisitedArt.plateSize, 75)
        XCTAssertEqual(SaveDoodlePassportUnvisitedArt.plateSize, SaveDoodlePassportCatalog.unvisitedDiscSize)
        for (kind, name) in expected {
            XCTAssertEqual(SaveDoodlePassportUnvisitedArt.assetName(for: kind), name)
            let imageset = repositoryRoot.appendingPathComponent(
                "SAV-E/Resources/Assets.xcassets/\(name).imageset"
            )
            let contents = imageset.appendingPathComponent("Contents.json")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: contents.path),
                "Missing DRAFT v0 imageset \(name)"
            )
            let json = try String(contentsOf: contents, encoding: .utf8)
            XCTAssertTrue(json.contains("\"template-rendering-intent\" : \"original\"") || json.contains("\"template-rendering-intent\": \"original\""))
            XCTAssertTrue(json.contains("\"scale\": \"1x\"") || json.contains("\"scale\" : \"1x\""))
            XCTAssertTrue(json.contains("\"scale\": \"2x\"") || json.contains("\"scale\" : \"2x\""))
            XCTAssertTrue(json.contains("\"scale\": \"3x\"") || json.contains("\"scale\" : \"3x\""))
        }
        XCTAssertNil(SaveDoodlePassportUnvisitedArt.assetName(for: .duck))
        XCTAssertNil(SaveDoodlePassportUnvisitedArt.resolvedImageName(for: .duck))
        let stickers = try source(at: "SAV-E/Views/Profile/SaveDoodlePassportStickers.swift")
        XCTAssertTrue(stickers.contains("DRAFT v0"))
        XCTAssertTrue(stickers.contains("SaveDoodlePassportUniqueGlyph"))
        XCTAssertTrue(stickers.contains("resolvedImageName(for: kind)"))
        XCTAssertTrue(stickers.contains("else if kind.usesOfficialAsset"))
    }

    func testUnhintedStickerKindIsStableForTheSamePlace() {
        let id = UUID(uuidString: "20000000-0000-0000-0000-000000000099")!
        let first = Place(
            id: id,
            name: "Nameless Spot",
            address: "Beijing, China",
            latitude: 39.88,
            longitude: 116.40,
            category: .attraction,
            status: .wantToGo,
            sourcePlatform: .other,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        var second = first
        second.address = "Jingshan Front St, Beijing, China"
        second.name = "Different Spot"
        XCTAssertNil(SaveDoodlePassportCatalog.kindHinted(by: first.name))
        XCTAssertNil(SaveDoodlePassportCatalog.kindHinted(by: second.name))
        XCTAssertEqual(
            SaveDoodlePassportCatalog.stickerKind(for: first),
            SaveDoodlePassportCatalog.stickerKind(for: second)
        )
        XCTAssertEqual(
            SaveDoodlePassportCatalog.rotationDegrees(for: first.id.uuidString),
            SaveDoodlePassportCatalog.rotationDegrees(for: second.id.uuidString)
        )
    }

    func testPassportParityTargetIsTheDoodleMockAtExactly90() throws {
        let script = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        XCTAssertTrue(script.contains("five-tab-passport*)"))
        XCTAssertTrue(script.contains("screen=\"passport\""))
        XCTAssertTrue(script.contains("parity_screens=(home saves plan map friends capture paywall passport)"))
        let target = repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/passport.png"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        let png = try Data(contentsOf: target)
        XCTAssertEqual([UInt8](png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(pngDimension(png, at: 16), 402)
        XCTAssertEqual(pngDimension(png, at: 20), 874)
        XCTAssertEqual(png[25], 2, "Passport target must stay RGB 8-bit, not a generated screenshot.")
        let darkTarget = repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/passport-dark.png"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: darkTarget.path))
        let darkPNG = try Data(contentsOf: darkTarget)
        XCTAssertEqual([UInt8](darkPNG.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(pngDimension(darkPNG, at: 16), 402)
        XCTAssertEqual(pngDimension(darkPNG, at: 20), 874)
        XCTAssertEqual(darkPNG[25], 2, "Passport dark target must stay RGB 8-bit, not a generated screenshot.")
        XCTAssertTrue(script.contains("THRESHOLD=\"0.90\""))
        XCTAssertFalse(script.contains("status=\"REVIEW\""))
        XCTAssertFalse(script.contains("The 0.90 score is not a CI gate."))
        XCTAssertFalse(script.contains("0.90 is report-only"))
        XCTAssertTrue(script.contains("gate_failed=1"))
        XCTAssertTrue(script.contains("Home, Map, Saves, Plan, and Passport all fail the job below 0.90."))
        XCTAssertFalse(script.contains("passport-mask"))
        XCTAssertFalse(script.contains("[[ \"$screen\" == \"passport\""))
        let readme = try source(at: "Prototypes/AtlasPostcard/README.md")
        XCTAssertTrue(readme.contains("passport-light.png"))
        XCTAssertTrue(readme.contains("passport-dark.png"))
        XCTAssertTrue(readme.contains("eade369"))
        XCTAssertTrue(readme.contains("stickers and cities"))
        XCTAssertTrue(readme.contains("0.90"))
        XCTAssertTrue(readme.contains("402×874") || readme.contains("402 x 874") || readme.contains("402 × 874"))
        XCTAssertFalse(readme.contains("23cca55"))
        XCTAssertFalse(readme.contains("2026-10-19-doodle-v1-passport.png"))
        XCTAssertFalse(readme.contains("padded with paper"))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("passport-light.png"))
        XCTAssertTrue(design.contains("passport-dark.png"))
        XCTAssertTrue(design.contains("Passport (Doodle v1)"))
        XCTAssertTrue(design.contains("Do not wrap a shrunken icon in a filled circle"))
        XCTAssertTrue(design.contains("empty Passport state"))
        XCTAssertTrue(design.contains("floor((availableGridWidth + 16) / 80)"))
        XCTAssertFalse(design.contains("23cca55"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("attach(app, name: \"five-tab-passport\")"))
        XCTAssertTrue(rail.contains("Connections back from Collected returns to Collected"))
        XCTAssertTrue(rail.contains("ProductionTargets/passport.png"))
        XCTAssertTrue(rail.contains("at exactly 0.90"))
        XCTAssertTrue(rail.contains("--uitest-doodle-passport-face"))
        XCTAssertTrue(rail.contains("doodle-passport-light"))
        XCTAssertTrue(rail.contains("doodle-passport-dark"))
        XCTAssertTrue(rail.contains("passport-375"))
        XCTAssertTrue(rail.contains("passport-390"))
        XCTAssertTrue(rail.contains("passport-430"))
        XCTAssertTrue(rail.contains("func testPassportWidth375"))
        XCTAssertTrue(rail.contains("func testPassportWidth390"))
        XCTAssertTrue(rail.contains("func testPassportWidth430"))
        XCTAssertFalse(rail.contains("--uitest-passport-width="))
        XCTAssertFalse(rail.contains("uiTestPassportWidth"))
        let workflow = try source(at: ".github/workflows/ios.yml")
        XCTAssertTrue(workflow.contains("five-tab-passport"))
        XCTAssertTrue(workflow.contains("doodle-passport-light"))
        XCTAssertTrue(workflow.contains("doodle-passport-dark"))
        XCTAssertTrue(workflow.contains("testPassportWidth375"))
        XCTAssertTrue(workflow.contains("testPassportWidth390"))
        XCTAssertTrue(workflow.contains("testPassportWidth430"))
        XCTAssertTrue(workflow.contains("iPhone-SE-3rd-generation"))
        XCTAssertTrue(workflow.contains("iPhone-14"))
        XCTAssertTrue(workflow.contains("iPhone-16-Pro-Max"))
        XCTAssertTrue(workflow.contains("passport-375"))
        XCTAssertTrue(workflow.contains("passport-390"))
        XCTAssertTrue(workflow.contains("passport-430"))
        XCTAssertFalse(workflow.contains("--uitest-passport-width="))
        let selector = try source(at: "scripts/select-ios-tests.py")
        XCTAssertFalse(selector.contains("testPassportWidth375"))
        XCTAssertFalse(selector.contains("testPassportWidth390"))
        XCTAssertFalse(selector.contains("testPassportWidth430"))
    }

    func testPassportColumnsAtDesignDeviceWidths() {
        let inset = SaveDoodlePassportCatalog.screenMargin * 2
            + SaveDoodlePassportCatalog.panelPadding * 2
        XCTAssertEqual(inset, 64)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCount(availableGridWidth: 375 - inset), 3)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCount(availableGridWidth: 390 - inset), 3)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCount(availableGridWidth: 402 - inset), 4)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCount(availableGridWidth: 430 - inset), 4)
        XCTAssertEqual(
            SaveDoodlePassportCatalog.columnCount(measuredGridWidth: 338, physicalScreenWidth: 375),
            3
        )
        XCTAssertEqual(
            SaveDoodlePassportCatalog.columnCount(measuredGridWidth: 338, physicalScreenWidth: 390),
            3
        )
        XCTAssertEqual(
            SaveDoodlePassportCatalog.columnCount(measuredGridWidth: 338, physicalScreenWidth: 402),
            4
        )
        XCTAssertEqual(
            SaveDoodlePassportCatalog.columnCount(measuredGridWidth: 338, physicalScreenWidth: 430),
            4
        )
    }

    func testPassportPanelGeometryMatchesMeasuredTarget() {
        XCTAssertEqual(SaveDoodlePassportCatalog.screenMargin, 16)
        XCTAssertEqual(SaveDoodlePassportCatalog.panelLeading, 16)
        XCTAssertEqual(SaveDoodlePassportCatalog.panelWidth, 370)
        XCTAssertEqual(SaveDoodlePassportCatalog.panelHeight, 496)
        XCTAssertEqual(SaveDoodlePassportCatalog.panelTop, 158)
        XCTAssertEqual(SaveDoodlePassportCatalog.panelWidth + SaveDoodlePassportCatalog.panelLeading, 386)
        XCTAssertEqual(SaveDoodlePassportCatalog.panelTop + SaveDoodlePassportCatalog.panelHeight, 654)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCenters, [70.5, 158, 245.5, 331])
        XCTAssertEqual(SaveDoodlePassportCatalog.rowCenters, [212, 336.5, 461])
        XCTAssertEqual(SaveDoodlePassportCatalog.columnStride, 87.5)
        XCTAssertEqual(SaveDoodlePassportCatalog.rowStride, 124.5)
        XCTAssertEqual(SaveDoodlePassportCatalog.unvisitedDiscSize, 75)
        XCTAssertEqual(SaveDoodlePassportCatalog.visitedStickerSize.width, 80)
        XCTAssertEqual(SaveDoodlePassportCatalog.visitedStickerSize.height, 76)
        XCTAssertEqual(SaveDoodlePassportCatalog.stampDiameter, 28)
        XCTAssertEqual(SaveDoodlePassportCatalog.stampOffset.width, 22)
        XCTAssertEqual(SaveDoodlePassportCatalog.stampOffset.height, 26.5)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCenterX(0, columns: 4), 70.5)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCenterX(1, columns: 4), 158)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCenterX(2, columns: 4), 245.5)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCenterX(3, columns: 4), 331)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCenterX(0, columns: 3), 70.5)
        XCTAssertEqual(SaveDoodlePassportCatalog.columnCenterX(2, columns: 3), 245.5)
        XCTAssertEqual(SaveDoodlePassportCatalog.rowCenterY(0), 212)
        XCTAssertEqual(SaveDoodlePassportCatalog.rowCenterY(1), 336.5)
        XCTAssertEqual(SaveDoodlePassportCatalog.rowCenterY(2), 461)
        let first = SaveDoodlePassportCatalog.panelPoint(column: 0, row: 0, columns: 4)
        XCTAssertEqual(first.x, 54.5)
        XCTAssertEqual(first.y, 54)
        XCTAssertEqual(SaveDoodlePassportCatalog.panelFillLightHex, "E9DCC3")
        XCTAssertEqual(SaveDoodlePassportCatalog.panelStrokeLightHex, "C9BBA2")
        XCTAssertEqual(SaveDoodlePassportCatalog.discFillLightHex, "F6F0E6")
        XCTAssertEqual(SaveDoodlePassportCatalog.stampBaseLightHex, "FAF7F1")
        XCTAssertEqual(SaveDoodlePassportCatalog.stampRingRedHex, "B3534A")
        XCTAssertEqual(SaveDoodlePassportCatalog.stampRingGoldHex, "C19349")
        XCTAssertEqual(SaveDoodlePassportCatalog.titleLeading, 24)
        XCTAssertEqual(SaveDoodlePassportCatalog.titleBaseline, 106)
        XCTAssertEqual(SaveDoodlePassportCatalog.titlePointSize, 64)
        XCTAssertEqual(SaveDoodlePassportCatalog.subtitleLeading, 28)
        XCTAssertEqual(SaveDoodlePassportCatalog.subtitleBaseline, 138)
    }

    private func place(
        _ name: String,
        _ address: String,
        _ category: PlaceCategory,
        status: PlaceStatus = .wantToGo,
        createdAt: Date = Date()
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: 39.88,
            longitude: 116.40,
            category: category,
            status: status,
            sourcePlatform: .other,
            createdAt: createdAt
        )
    }

    private func pngDimension(_ data: Data, at offset: Int) -> UInt32 {
        let bytes = [UInt8](data.subdata(in: offset..<(offset + 4)))
        return UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
