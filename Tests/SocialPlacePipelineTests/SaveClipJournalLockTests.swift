import XCTest

final class SaveClipJournalLockTests: XCTestCase {
    func testAppClipUsesV31PlacePageAndSaveFlow() throws {
        let clip = try source(at: "SAV-EClip/ClipContentView.swift")
        let theme = try source(at: "SAV-EClip/ClipDoodleTheme.swift")
        let save = try source(at: "SAV-EClip/ClipSaveService.swift")
        let clipPayload = try source(at: "SAV-EClip/SharedTripData.swift")
        let appPayload = try source(at: "SAV-E/Models/SharedTripData.swift")
        let pending = try source(at: "SAV-EClip/PendingShareStore.swift")
        let appPending = try source(at: "SAV-E/Models/PendingShareStore.swift")
        let app = try source(at: "SAV-E/App/SaveApp.swift")
        let content = try source(at: "SAV-E/App/ContentView.swift")
        let strings = try source(at: "SAV-EClip/Localizable.xcstrings")
        let entitlements = try source(at: "SAV-EClip/SAV-EClip.entitlements")

        XCTAssertTrue(theme.contains("enum ClipJournalPalette"))
        XCTAssertTrue(theme.contains("enum ClipDisplayType"))
        XCTAssertTrue(theme.contains("Iansui-SavvySubset.ttf (3.48 MB)"))
        XCTAssertTrue(theme.contains("Iansui-ClipTitles.ttf"))
        XCTAssertTrue(theme.contains("static var wordmark"))
        XCTAssertTrue(theme.contains("ClipJournalPalette.forest"))
        XCTAssertTrue(theme.contains("dotGridStep: CGFloat = 14"))
        XCTAssertTrue(theme.contains("heroHeight: CGFloat = 470"))
        XCTAssertTrue(theme.contains("buttonHeight: CGFloat = 54"))
        XCTAssertTrue(theme.contains("struct ClipTornPaperEdge"))
        XCTAssertTrue(theme.contains("static func forHero"))
        XCTAssertFalse(theme.contains("SavvyLogo"))
        XCTAssertFalse(theme.contains("case elephant"))
        XCTAssertFalse(theme.contains("case temple"))
        XCTAssertFalse(theme.contains("case duck"))
        XCTAssertTrue(clip.contains("ClipJournalPalette"))
        XCTAssertTrue(clip.contains("scrollTargetBehavior(.paging)"))
        XCTAssertTrue(clip.contains("SKOverlay.AppClipConfiguration(position: .bottom)"))
        XCTAssertTrue(clip.contains("PendingShareStore.write"))
        XCTAssertTrue(clip.contains("SharedPlaceData.from(url: url)"))
        XCTAssertTrue(clip.contains("SharedListPayload.isListLink(url)"))
        XCTAssertTrue(clip.contains("clip.error.retry"))
        XCTAssertTrue(clip.contains("presentsAppClipOverlay = true"))
        XCTAssertTrue(clip.contains("surface = .saved"))
        XCTAssertFalse(clip.contains("mapStyle(.standard)"))
        XCTAssertFalse(clip.contains("ClipDoodlePin"))
        XCTAssertFalse(clip.contains("pendingFriendShareURL"))
        XCTAssertFalse(clip.contains("nothingAdded"))
        XCTAssertFalse(clip.contains("Nothing is added until you open the app"))
        XCTAssertFalse(clip.contains(".elephant"))
        XCTAssertFalse(clip.contains("coming soon") || clip.contains("Coming Soon"))
        XCTAssertFalse(clip.contains("ClipAtlasPalette"))
        XCTAssertFalse(clip.contains("mappin.circle.fill"))
        XCTAssertFalse(clip.contains("free 50") || clip.contains("Free 50"))
        XCTAssertFalse(clip.contains("Save All") || clip.contains("Save this list"))
        XCTAssertTrue(clip.contains("saveWholeList"))
        XCTAssertTrue(clip.contains("clip.list.saveAll"))
        XCTAssertTrue(clip.contains("clip.listPartial.body"))
        XCTAssertTrue(clip.contains("signInScreen"))
        XCTAssertTrue(clip.contains("clip.signin.saveOne"))
        XCTAssertTrue(clip.contains("clip.signin.saveCount"))
        XCTAssertGreaterThanOrEqual(
            clip.components(separatedBy: "accessibilityElement(children: .contain)").count - 1,
            2
        )
        XCTAssertTrue(clip.contains("ClipListSwipeHint"))
        XCTAssertTrue(clip.contains("listSaved"))
        XCTAssertTrue(theme.contains("ClipListSaveCountTable"))
        XCTAssertTrue(theme.contains("clip.listSaved.row.new"))
        XCTAssertTrue(theme.contains("case seal"))
        XCTAssertTrue(theme.contains("nonisolated private func jitteredPath"))
        XCTAssertTrue(theme.contains("nonisolated struct ClipJitterRoundedRect"))
        XCTAssertFalse(clip.contains("ClipGooglePhoto"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent("SAV-EClip/ClipGooglePhotoView.swift").path))
        XCTAssertTrue(save.contains("POST"))
        XCTAssertTrue(save.contains("/places"))
        XCTAssertTrue(save.contains("over_free_limit"))
        XCTAssertTrue(save.contains("already_saved"))
        XCTAssertTrue(save.contains("saveList"))
        XCTAssertTrue(save.contains("postPlaces"))
        let planner = try source(at: "SAV-EClip/ClipListSavePlanner.swift")
        XCTAssertTrue(planner.contains("newly_saved"))
        XCTAssertTrue(planner.contains("already_saved"))
        XCTAssertTrue(planner.contains("over_cap"))
        XCTAssertTrue(planner.contains("uniqueItems"))
        XCTAssertTrue(planner.contains("clipListSwipeHintDismissed"))
        XCTAssertTrue(planner.contains("group.com.wanderly.app"))
        XCTAssertFalse(planner.contains("PendingShareStore"))
        XCTAssertTrue(planner.contains("enum ClipSignInKind"))
        XCTAssertTrue(planner.contains("enum ClipListSaveFailure: Error"))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("Save all N"))
        XCTAssertTrue(design.contains("19b"))
        XCTAssertTrue(design.contains("SL6"))
        XCTAssertTrue(design.contains("LS4"))
        XCTAssertTrue(design.contains("clipListSwipeHintDismissed"))
        XCTAssertTrue(design.contains("Save this place"))
        XCTAssertTrue(design.contains("group.com.wanderly.app"))
        XCTAssertTrue(design.contains("not `group.com.wanderly.app.shared`"))
        let backend = try source(at: "backend/src/clipListSave.ts")
        XCTAssertTrue(backend.contains("planClipListSave"))
        XCTAssertTrue(backend.contains("overCap"))
        XCTAssertTrue(save.contains("ASAuthorizationAppleIDProvider"))
        XCTAssertTrue(save.contains("enum ClipSaveError: Error"))
        XCTAssertTrue(save.contains("ClipFullApp.isInstalled"))
        XCTAssertTrue(entitlements.contains("com.apple.developer.applesignin"))
        XCTAssertFalse(clipPayload.contains("var photoAttribution"))
        XCTAssertFalse(appPayload.contains("var photoAttribution"))
        XCTAssertTrue(appPayload.contains("isGooglePlacesPhotoURL"))
        XCTAssertTrue(appPayload.contains("isGoogleDomainURL"))
        XCTAssertTrue(clipPayload.contains("isGoogleDomainURL"))
        let list = try source(at: "SAV-E/Models/SaveCollaborativeList.swift")
        XCTAssertTrue(list.contains("sanitizingPublicPayload"))
        XCTAssertTrue(pending.contains("static let key = \"pendingShare\""))
        XCTAssertTrue(appPending.contains("static let key = \"pendingShare\""))
        XCTAssertTrue(app.contains("restorePendingShare"))
        XCTAssertTrue(app.contains("ClipAppleAccountStore.clear"))
        XCTAssertTrue(content.contains("performPendingShareAutoSave"))
        let carry = try source(at: "SAV-E/Services/ClipSignInCarryOver.swift")
        let appleStore = try source(at: "SAV-E/Models/ClipAppleAccountStore.swift")
        let auth = try source(at: "SAV-E/Services/PrivyAuthService.swift")
        XCTAssertTrue(appleStore.contains("static let key = \"clipAppleUserID\""))
        XCTAssertTrue(appleStore.contains("Never a JWT"))
        XCTAssertTrue(carry.contains("getCredentialState(forUserID:"))
        XCTAssertTrue(carry.contains("withCheckedContinuation"))
        XCTAssertTrue(carry.contains("requestedScopes = []"))
        XCTAssertTrue(carry.contains("case skipSignIn"))
        XCTAssertTrue(auth.contains("restoreClipSignInIfNeeded"))
        XCTAssertTrue(auth.contains("ClipAppleAccountStore.read"))
        XCTAssertTrue(auth.contains("ClipAppleAccountStore.clear"))
        XCTAssertFalse(appleStore.contains("identityToken"))
        XCTAssertFalse(appleStore.contains("Bearer"))
        XCTAssertTrue(save.contains("ClipAppleAccountStore.write(credential.user)"))
        XCTAssertTrue(save.contains("static let key = \"clipAppleUserID\""))
        XCTAssertFalse(entitlements.contains("keychain-access-groups"))
        XCTAssertTrue(strings.contains("clip.save"))
        XCTAssertTrue(strings.contains("clip.saveAll"))
        XCTAssertTrue(strings.contains("Save all %d places"))
        XCTAssertTrue(strings.contains("整份清單都存"))
        XCTAssertTrue(strings.contains("clip.listSaved.row.new"))
        XCTAssertTrue(strings.contains("clip.listPartial.body"))
        XCTAssertTrue(strings.contains("#293 Q1"))
        XCTAssertTrue(strings.contains("clip.signin.saveOne"))
        XCTAssertTrue(strings.contains("Save this place"))
        XCTAssertTrue(strings.contains("存這一家"))
        XCTAssertTrue(strings.contains("Save %d places"))
        XCTAssertTrue(strings.contains("往上滑看下一家"))
        XCTAssertTrue(strings.contains("clip.saved.title"))
        XCTAssertTrue(strings.contains("clip.cap50.body"))
        XCTAssertFalse(strings.contains("clip.footnote.howSave"))
        XCTAssertFalse(strings.contains("clip.footnote.nothingAdded"))
        XCTAssertFalse(strings.contains("Nothing is added until you open the app"))
    }

    func testClipDoesNotShipMainCatalogOrFullIansuiSubset() throws {
        let project = try? String(
            contentsOf: repositoryRoot.appendingPathComponent("SAV-E.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertNotNil(project)
        XCTAssertFalse((project ?? "").contains("DisplayFont in SAVEClip Resources"))
        XCTAssertTrue((project ?? "").contains("Caveat-SemiBold.ttf in SAVEClip Resources"))
        XCTAssertTrue((project ?? "").contains("\"Caveat-SemiBold.ttf\""))
        XCTAssertTrue((project ?? "").contains("Iansui-ClipTitles.ttf"))
        XCTAssertTrue((project ?? "").contains("ClipSaveService.swift"))
        XCTAssertTrue((project ?? "").contains("ClipListSavePlanner.swift"))
        XCTAssertTrue((project ?? "").contains("ClipListSaveTests.swift in Sources"))
        XCTAssertTrue((project ?? "").contains("PendingShareStoreTests.swift in Sources"))
        let pendingTests = try source(at: "Tests/SocialPlacePipelineTests/PendingShareStoreTests.swift")
        XCTAssertTrue(pendingTests.contains("@testable import SAVE"))
        XCTAssertTrue(pendingTests.contains("@MainActor"))
        XCTAssertFalse((project ?? "").contains("C1A000000000000000000046 /* PendingShareStoreTests.swift"))
        XCTAssertFalse((project ?? "").contains("C1A000000000000000000047 /* PendingShareStoreTests.swift"))
        let objectIDs = (project ?? "").split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("\t\t"), line.contains(" = {isa = ") else { return nil }
            let id = String(line.dropFirst(2).prefix { !$0.isWhitespace })
            return id.allSatisfy(\.isHexDigit) && (24...32).contains(id.count) ? id : nil
        }
        XCTAssertEqual(
            Set(objectIDs).count,
            objectIDs.count,
            "SAVEClip compiled XCTest after PendingShareStoreTests reused ClipSaveService object IDs"
        )
        XCTAssertFalse((project ?? "").contains("Iansui-SavvySubset.ttf in SAVEClip Resources"))
        let iansui = repositoryRoot.appendingPathComponent("SAV-E/Resources/DisplayFont/Iansui-SavvySubset.ttf")
        XCTAssertGreaterThan((try? iansui.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0, 3_000_000)
        let clipTitles = repositoryRoot.appendingPathComponent("SAV-E/Resources/DisplayFont/Iansui-ClipTitles.ttf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: clipTitles.path))
        XCTAssertLessThan((try? clipTitles.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0, 80_000)
        let caveat = repositoryRoot.appendingPathComponent("SAV-E/Resources/DisplayFont/Caveat-SemiBold.ttf")
        XCTAssertLessThan((try? caveat.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0, 400_000)
    }

    func testClipTargetDeploymentTargetIsSeventeen() throws {
        let project = try source(at: "SAV-E.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("IPHONEOS_DEPLOYMENT_TARGET = 17.0;"))
        XCTAssertFalse(project.contains("com.apple.developer.nfc"))
        XCTAssertFalse(project.contains("NFCReaderUsageDescription"))
        let entitlements = try source(at: "SAV-EClip/SAV-EClip.entitlements")
        XCTAssertTrue(entitlements.contains("appclips:sav-e-app.vercel.app"))
        XCTAssertTrue(entitlements.contains("group.com.wanderly.app"))
        XCTAssertFalse(entitlements.contains("group.com.wanderly.app.shared"))
        let pendingStore = try source(at: "SAV-EClip/PendingShareStore.swift")
        let appPendingStore = try source(at: "SAV-E/Models/PendingShareStore.swift")
        XCTAssertFalse(pendingStore.contains("group.com.wanderly.app.shared"))
        XCTAssertFalse(appPendingStore.contains("group.com.wanderly.app.shared"))
        XCTAssertTrue(pendingStore.contains("group.com.wanderly.app"))
        XCTAssertTrue(entitlements.contains("com.apple.developer.parent-application-identifiers"))
        XCTAssertTrue(entitlements.contains("com.apple.developer.applesignin"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.wanderly.app.Clip;"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_LSApplicationQueriesSchemes"))
    }

    func testClipSaveOutcomeParserMatches293AndFriendShare() {
        func parse(_ status: Int, json: String) -> String {
            let data = Data(json.utf8)
            if status == 403,
               let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (body["code"] as? String) == "over_free_limit" || (body["error"] as? String) == "saved_place_limit" {
                return "cap"
            }
            if (200...299).contains(status) {
                if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (body["outcome"] as? String) == "already_saved" {
                    return "duplicate"
                }
                return "saved"
            }
            if status == 409 { return "duplicate" }
            return "failed"
        }
        XCTAssertEqual(parse(201, json: #"{"outcome":"saved"}"#), "saved")
        XCTAssertEqual(parse(201, json: #"{"outcome":"already_saved"}"#), "duplicate")
        XCTAssertEqual(parse(403, json: #"{"error":"saved_place_limit","code":"over_free_limit","limit":50}"#), "cap")
        XCTAssertEqual(parse(409, json: #"{"error":"Place id conflict"}"#), "duplicate")
        XCTAssertEqual(parse(500, json: #"{"error":"no"}"#), "failed")
    }

    func testClipCoralStaysF26B4AInDark() throws {
        let coral = try source(at: "SAV-EClip/Assets.xcassets/ClipCoral.colorset/Contents.json")
        XCTAssertTrue(coral.contains("\"red\": \"0.949\""))
        XCTAssertTrue(coral.contains("\"green\": \"0.420\""))
        XCTAssertTrue(coral.contains("\"blue\": \"0.290\""))
        XCTAssertTrue(coral.contains("\"value\": \"dark\""))
        XCTAssertEqual(coral.components(separatedBy: "0.949").count - 1, 2)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
