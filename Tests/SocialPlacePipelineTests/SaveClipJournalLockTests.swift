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
        XCTAssertTrue(theme.contains("drawCoffeeCup"))
        XCTAssertTrue(theme.contains("drawNoodleBowl"))
        XCTAssertTrue(theme.contains("drawPostageStamp"))
        XCTAssertTrue(theme.contains("drawPaperAirplane"))
        XCTAssertTrue(theme.contains("ClipScallopedStamp"))
        XCTAssertTrue(theme.contains("ClipDashedInkLine"))
        XCTAssertTrue(theme.contains("dash: [3.5, 4.5]"))
        XCTAssertTrue(theme.contains("Iansui-Regular"))
        XCTAssertTrue(theme.contains("Iansui-ClipTitles.ttf"))
        XCTAssertTrue(theme.contains(".cascadeList"))
        XCTAssertTrue(theme.contains("minimumScaleFactor(0.85)"))
        XCTAssertTrue(theme.contains("titleInkOverflow: CGFloat = 18"))
        XCTAssertTrue(theme.contains("clip.friendNote"))
        XCTAssertTrue(theme.contains("enum ClipStickerInk"))
        XCTAssertTrue(theme.contains("static let plate"))
        XCTAssertTrue(theme.contains("#EADDC6"))
        XCTAssertTrue(theme.contains("#2F2E23"))
        XCTAssertTrue(theme.contains("Never a black fill or black stroke"))
        XCTAssertTrue(theme.contains("plateStroke: CGFloat = 1.6"))
        XCTAssertTrue(theme.contains("bowlStroke: CGFloat = 1.6"))
        XCTAssertTrue(theme.contains("cupStroke: CGFloat = 1.6"))
        XCTAssertTrue(theme.contains("handleStroke: CGFloat = 2.4"))
        XCTAssertTrue(theme.contains("chopstickStroke: CGFloat = 2.0"))
        XCTAssertTrue(theme.contains("ClipStickerInk.plate"))
        XCTAssertTrue(theme.contains("ClipStickerInk.outline"))
        XCTAssertTrue(theme.contains("ClipStickerInk.plateStroke"))
        XCTAssertTrue(theme.contains("ClipStickerInk.bowlStroke"))
        XCTAssertTrue(theme.contains("ClipStickerInk.cupStroke"))
        XCTAssertTrue(theme.contains("ClipStickerInk.handleStroke"))
        XCTAssertTrue(theme.contains("ClipStickerInk.chopstickStroke"))
        XCTAssertTrue(theme.contains("accessibilityIdentifier(\"clip.sharer\")"))
        XCTAssertGreaterThanOrEqual(
            theme.components(separatedBy: "accessibilityElement(children: .ignore)").count - 1,
            2,
            "wordmark plate and sharer chip must be XCUI elements, not hidden children"
        )
        XCTAssertFalse(theme.contains("Color.black"))
        XCTAssertFalse(theme.contains("#000000"))
        XCTAssertFalse(theme.contains("colorScheme == .dark ? Color.black"))
        XCTAssertGreaterThan(
            ClipContrastEvidence.ratio(
                foreground: ClipContrastEvidence.stickerInk,
                background: ClipContrastEvidence.cream
            ),
            4.5,
            "ClipStickerInk on cream must stay WCAG AA in dark mode"
        )
        XCTAssertFalse(theme.contains("SavvyLogo"))
        XCTAssertFalse(theme.contains("case elephant"))
        XCTAssertFalse(theme.contains("case temple"))
        XCTAssertFalse(theme.contains("case duck"))
        XCTAssertFalse(theme.contains("ring.insetBy(dx: 3, dy: 3)"))
        XCTAssertFalse(theme.contains("mark.addLine(to: CGPoint(x: size.width * 0.68, y: size.height * 0.38))"))
        XCTAssertFalse(theme.contains("Path(roundedRect: CGRect(x: size.width * 0.24, y: size.height * 0.2, width: size.width * 0.42, height: size.height * 0.46)"))
        XCTAssertFalse(theme.contains(".stroke(ClipJournalPalette.line, lineWidth: 1)"))
        XCTAssertTrue(clip.contains("ClipJournalPalette"))
        XCTAssertTrue(clip.contains("scrollTargetBehavior(.paging)"))
        XCTAssertTrue(clip.contains("SKOverlay.AppClipConfiguration(position: .bottom)"))
        XCTAssertTrue(save.contains("PendingShareStore.write"))
        XCTAssertFalse(clip.contains("PendingShareStore.write"))
        XCTAssertTrue(clip.contains("SharedPlaceData.from(url: url)"))
        XCTAssertTrue(clip.contains("SharedListPayload.isListLink(url)"))
        XCTAssertTrue(clip.contains("clip.error.retry"))
        XCTAssertTrue(clip.contains("presentsAppClipOverlay = true"))
        XCTAssertTrue(clip.contains("clip.pending.body"))
        XCTAssertTrue(clip.contains("surface = .pending"))
        XCTAssertFalse(save.contains("URLSession"))
        XCTAssertFalse(save.contains("Authorization"))
        XCTAssertFalse(save.contains("ClipAppleAuth"))
        XCTAssertTrue(content.contains("app.handoff.confirmList"))
        XCTAssertTrue(content.contains("requiringAuthenticatedSession: true"))
        XCTAssertTrue(content.contains("runConfirmed"))
        XCTAssertFalse(clip.contains("surface = .saved"))
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
        XCTAssertTrue(clip.contains("pendingSaveDraft"))
        XCTAssertTrue(clip.contains("saveTask?.cancel()"))
        XCTAssertTrue(clip.contains("activeSaveRequestID"))
        XCTAssertTrue(clip.contains("enqueueSave"))
        XCTAssertTrue(clip.contains("coordinateSystem: draft.coordinateSystem"))
        XCTAssertTrue(save.contains("confirmedPlaces: [snapshot]"))
        XCTAssertTrue(clipPayload.contains("var coordinateSystem: String? = nil"))
        XCTAssertTrue(appPayload.contains("var coordinateSystem: String? = nil"))
        XCTAssertTrue(clip.contains("ClipListSavePlanner.onePlaceItem"))
        XCTAssertTrue(clip.contains("ClipListSavePlanner.visiblePage"))
        XCTAssertTrue(clip.contains("clip.list.saveAll"))
        XCTAssertFalse(clip.contains("clip.listPartial.body"))
        XCTAssertFalse(clip.contains("signInScreen"))
        XCTAssertFalse(clip.contains("clip.signin.saveOne"))
        XCTAssertFalse(clip.contains("clip.signin.saveCount"))
        XCTAssertGreaterThanOrEqual(
            clip.components(separatedBy: "accessibilityElement(children: .contain)").count - 1,
            2
        )
        XCTAssertTrue(clip.contains("ClipListSwipeHint"))
        XCTAssertFalse(clip.contains("listSaved"))
        XCTAssertTrue(theme.contains("ClipListSaveCountTable"))
        XCTAssertTrue(theme.contains("clip.listSaved.row.new"))
        XCTAssertTrue(theme.contains("case .seal:"))
        XCTAssertTrue(theme.contains("nonisolated private func jitteredPath"))
        XCTAssertTrue(theme.contains("nonisolated struct ClipJitterRoundedRect"))
        XCTAssertTrue(theme.contains("ClipJitterRoundedRect(radius: 14, seed: 21)"))
        XCTAssertFalse(theme.contains("ClipJitterRoundedRect(seed:"))
        XCTAssertFalse(clip.contains("ClipGooglePhoto"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent("SAV-EClip/ClipGooglePhotoView.swift").path))
        XCTAssertFalse(save.contains("POST"))
        XCTAssertFalse(save.contains("/places"))
        XCTAssertFalse(save.contains("over_free_limit"))
        XCTAssertFalse(save.contains("already_saved"))
        XCTAssertTrue(save.contains("saveList"))
        XCTAssertFalse(save.contains("postPlaces"))
        XCTAssertFalse(save.contains("ClipListSavePlanner.onePlacePayload"))
        XCTAssertFalse(save.contains("ClipListSavePlanner.onePlaceResult"))
        XCTAssertFalse(save.contains("if let code = draft.friendShareCode { body[\"friend_share_code\"] = code }"))
        XCTAssertTrue(save.contains("universalLinksOnly"))
        XCTAssertTrue(save.contains("@MainActor @escaping (URL, @escaping (Bool) -> Void) -> Void"))
        XCTAssertTrue(save.contains("openInstalledApp"))
        XCTAssertFalse(save.contains("options: [:]"))
        let planner = try source(at: "SAV-EClip/ClipListSavePlanner.swift")
        XCTAssertTrue(planner.contains("newly_saved"))
        XCTAssertTrue(planner.contains("already_saved"))
        XCTAssertTrue(planner.contains("over_cap"))
        XCTAssertTrue(planner.contains("uniqueItems"))
        XCTAssertTrue(planner.contains("mergingIdentities"))
        XCTAssertTrue(planner.contains("matched.dropFirst()"))
        XCTAssertTrue(planner.contains("extraPlaceIds"))
        XCTAssertTrue(planner.contains("google_place_id"))
        XCTAssertTrue(planner.contains("extra_place_ids"))
        XCTAssertTrue(planner.contains("body[\"coordinate_system\"]"))
        XCTAssertTrue(planner.contains("body[\"location_provider\"]"))
        XCTAssertTrue(planner.contains("body[\"provider_map_url\"]"))
        XCTAssertTrue(planner.contains("isNearbyDuplicate"))
        XCTAssertTrue(planner.contains("([item.placeId ?? \"\"] + extras).first(where: isGooglePlaceID)"))
        XCTAssertTrue(planner.contains("static func isGooglePlaceID"))
        XCTAssertTrue(planner.contains("hasPrefix(\"eic\")"))
        XCTAssertTrue(planner.contains("hasPrefix(\"iho\")"))
        XCTAssertTrue(planner.contains("keys.append(\"p:\\(placeId)\")"))
        XCTAssertTrue(planner.contains("keys.append(\"g:\\(placeId)\")"))
        XCTAssertTrue(planner.contains("clipListSwipeHintDismissed"))
        XCTAssertTrue(planner.contains("group.com.wanderly.app"))
        XCTAssertFalse(planner.contains("PendingShareStore"))
        XCTAssertTrue(planner.contains("enum ClipSignInKind"))
        XCTAssertTrue(planner.contains("enum ClipListSaveFailure: Error"))
        XCTAssertTrue(planner.contains("recipientOwnedPlaceID"))
        XCTAssertTrue(planner.contains("static func onePlaceItem"))
        XCTAssertTrue(planner.contains("static func onePlacePayload"))
        XCTAssertTrue(planner.contains("static func onePlaceResult"))
        XCTAssertTrue(planner.contains("return requestBody(items: [item])"))
        XCTAssertTrue(planner.contains("if counts.newlySaved > 0 { return .saved }"))
        XCTAssertTrue(planner.contains("if counts.overCap > 0 { return .capReached }"))
        XCTAssertTrue(planner.contains("if counts.alreadySaved > 0 { return .duplicate }"))
        XCTAssertTrue(planner.contains("static func visiblePage"))
        XCTAssertFalse(planner.contains("return placeId.lowercased()"))
        XCTAssertFalse(planner.contains("body[\"note\"]"))
        XCTAssertFalse(planner.contains("body[\"rating\"]"))
        XCTAssertFalse(app.contains("consumedLaunchShareActivity"))
        XCTAssertFalse(app.contains("PendingShareStore.load() == nil"))
        XCTAssertTrue(app.contains("ClipPlaceHandoff.shouldConfirmPlace"))
        XCTAssertTrue(appPending.contains("matchesIncomingPlace(url:"))
        XCTAssertTrue(appPending.contains("shouldConfirmPlace"))
        XCTAssertTrue(appPending.contains("fromClipSnapshot"))
        XCTAssertTrue(appPending.contains("planStamps"))
        XCTAssertTrue(appPending.contains("case capReached"))
        XCTAssertTrue(appPending.contains("parseCounts"))
        XCTAssertTrue(appPending.contains("parseRemote"))
        XCTAssertTrue(appPending.contains("placesFromRemoteRows"))
        XCTAssertTrue(appPending.contains("already: [SavedRow]"))
        XCTAssertTrue(appPending.contains("body[\"already\"]"))
        XCTAssertFalse(appPending.contains("stampsFromRemoteCounts"))
        XCTAssertTrue(appPending.contains("journalByteLimit"))
        XCTAssertTrue(pending.contains("journalByteLimit"))
        XCTAssertTrue(pending.contains("data.count <= journalByteLimit"))
        XCTAssertTrue(app.contains("Preview-only AppStorage URL is not a Clip save intent."))
        XCTAssertTrue(appPending.contains("matchesIncomingList"))
        XCTAssertTrue(appPending.contains("static func shouldConfirmList"))
        XCTAssertTrue(app.contains("pendingClipListSave"))
        XCTAssertTrue(app.contains("ClipListHandoff.stampList"))
        XCTAssertTrue(app.contains("presentListJoinFailure"))
        XCTAssertTrue(app.contains("presentOpenedList(nil, incomingURL:"))
        XCTAssertTrue(appPending.contains("confirmedPlaces"))
        XCTAssertFalse(app.contains("pendingClipListSave = list"))
        XCTAssertTrue(appPending.contains("joined: SaveCollaborativeList?"))
        XCTAssertTrue(clip.contains("pendingListDrafts"))
        XCTAssertTrue(planner.contains("itemsToSave"))
        XCTAssertTrue(save.contains("confirmedPlaces: places"))
        XCTAssertFalse(save.contains("confirmedPlaceIds:"))
        XCTAssertTrue(pending.contains("200 * 8 * 1024"))
        XCTAssertTrue(appPending.contains("200 * 8 * 1024"))
        XCTAssertTrue(save.contains("extraPlaceIds: $0.extraPlaceIds.isEmpty ? nil : $0.extraPlaceIds"))
        XCTAssertTrue(appPending.contains("var extraPlaceIds: [String]? = nil"))
        XCTAssertTrue(appPending.contains("extraPlaceIds: extraPlaceIds"))
        XCTAssertTrue(appPending.contains("body[\"google_place_id\"] = google"))
        XCTAssertTrue(appPending.contains("body[\"extra_place_ids\"] = extras"))
        XCTAssertTrue(appPending.contains("body[\"coordinate_system\"]"))
        XCTAssertTrue(appPending.contains("body[\"location_provider\"]"))
        XCTAssertTrue(appPending.contains("body[\"provider_map_url\"]"))
        XCTAssertTrue(appPending.contains("([item.sourceID] + extras).first(where: isGooglePlaceID)"))
        XCTAssertTrue(appPending.contains("static func isGooglePlaceID"))
        XCTAssertTrue(appPending.contains("hasPrefix(\"eic\")"))
        XCTAssertTrue(appPending.contains("hasPrefix(\"iho\")"))
        XCTAssertTrue(appPending.contains("static func cachedAlreadySavedPlace"))
        XCTAssertTrue(appPending.contains("static func applyingJournalCoordinates"))
        XCTAssertTrue(appPending.contains("static func isNearbyDuplicate"))
        XCTAssertTrue(appPending.contains("static func uniqueItems(_ items: [SaveListItem])"))
        XCTAssertTrue(app.contains("requiresListConfirmation"))
        let generationReset = app[
            app.range(of: "private func handleAccountGenerationChange")!.lowerBound
            ..< (app.range(of: "private func storeUnclaimedOnboardingClue")?.lowerBound ?? app.endIndex)
        ]
        XCTAssertTrue(generationReset.contains("incomingPlaceReceipt = nil"))
        XCTAssertTrue(generationReset.contains("requiresShareConfirmation = false"))
        XCTAssertTrue(generationReset.contains("pendingFriendShareURL = \"\""))
        XCTAssertTrue(generationReset.contains("ClipPlaceHandoff.shouldResetHandoffOnAccountChange"))
        XCTAssertTrue(generationReset.contains("ClipPlaceHandoff.resetPlaceHandoffOnAccountChange()"))
        XCTAssertTrue(app.contains("lastAccountUserId = authService.currentUserId"))
        XCTAssertTrue(appPending.contains("shouldKeepPlaceHandoff(ownerGeneration:"))
        XCTAssertTrue(appPending.contains("static func shouldResetHandoffOnAccountChange"))
        XCTAssertTrue(appPending.contains("static func resetPlaceHandoffOnAccountChange"))
        XCTAssertTrue(appPending.contains("PendingShareStore.clear()"))
        XCTAssertTrue(content.contains("mapVM.sessionGeneration"))
        XCTAssertTrue(content.contains("guard mapVM.sessionGeneration == generation"))
        XCTAssertFalse(app.contains("if PendingShareStore.load()?.kind == .list {\n                PendingShareStore.clear()"))
        XCTAssertFalse(clip.contains("PendingSharePayload(\n                    kind: .place"))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("Save all N"))
        XCTAssertTrue(design.contains("19b"))
        XCTAssertTrue(design.contains("SL6"))
        XCTAssertTrue(design.contains("LS4"))
        XCTAssertTrue(design.contains("clipListSwipeHintDismissed"))
        XCTAssertTrue(design.contains("Confirm save"))
        XCTAssertTrue(design.contains("group.com.wanderly.app"))
        XCTAssertTrue(design.contains("not `group.com.wanderly.app.shared`"))
        XCTAssertTrue(design.contains("ClipStickerInk"))
        XCTAssertTrue(design.contains("#EADDC6` in light and dark"))
        XCTAssertTrue(design.contains("never a black oval"))
        XCTAssertFalse(design.contains("solid black oval, not kraft"))
        XCTAssertTrue(design.contains("cascade to Caveat"))
        XCTAssertTrue(design.contains("11-iansui-proof.md"))
        let backend = try source(at: "backend/src/clipListSave.ts")
        XCTAssertTrue(backend.contains("planClipListSave"))
        XCTAssertTrue(backend.contains("clipListSaveResponse"))
        XCTAssertTrue(backend.contains("saved: inserted.map"))
        XCTAssertTrue(backend.contains("already: plan.alreadyExisting.map"))
        // Cross-provider identity and transitive deduplication are exercised by
        // clipListSave.test.ts; local variable names are not a behavior contract.
        XCTAssertTrue(backend.contains("existingPlaces"))
        XCTAssertTrue(backend.contains("clipListPlacesAreNearbyDuplicate"))
        XCTAssertTrue(backend.contains("CLIP_LIST_NEARBY_DUPLICATE_METERS"))
        XCTAssertTrue(backend.contains("overCap"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("clipListSaveResponse(plan, inserted)"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("existingPlaces: existing.rows"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("readJson(request, clipListPlacesBodyMaxBytes)"))
        XCTAssertTrue(try source(at: "backend/src/listContracts.ts").contains("clipListPlacesEnvelopeMaxBytes"))
        XCTAssertTrue(try source(at: "backend/src/listContracts.ts").contains("listMaxItems * listItemPayloadMaxBytes + clipListPlacesEnvelopeMaxBytes"))
        XCTAssertTrue(try source(at: "backend/src/clipListSave.ts").contains("/^Eic/i"))
        XCTAssertTrue(try source(at: "backend/src/clipListSave.ts").contains("/^Iho/i"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("items.length > listMaxItems"))
        XCTAssertFalse(try source(at: "backend/src/server.ts").contains("items.length > 100"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("verifiedAppleIdentity"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("findUserForApple"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("ensureUserForApple"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("lookupAppleLinkedPrivySubject"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("verifiedAppleLinkedPrivySubject"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("verifiedPrivyAccessSubject"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("clip-apple-session"))
        XCTAssertTrue(try source(at: "backend/src/server.ts").contains("Privy bearer token required"))
        XCTAssertFalse(try source(at: "backend/src/server.ts").contains("profileIdForPrivySubject(appleSubject)"))
        let server = try source(at: "backend/src/server.ts")
        let sessionBlock = server[
            server.range(of: "resource === \"clip-apple-session\"")!.lowerBound
            ..< server.range(of: "resource === \"account-status\"")!.lowerBound
        ]
        XCTAssertTrue(sessionBlock.contains("lookupAppleLinkedPrivySubject"))
        XCTAssertFalse(sessionBlock.contains("ensureUserForApple"))
        let privyUsers = try source(at: "backend/src/privyUsers.ts")
        XCTAssertTrue(privyUsers.contains("/v1/users/apple/subject"))
        XCTAssertFalse(privyUsers.contains("searchParams.set(\"limit\", \"100\")"))
        XCTAssertFalse(privyUsers.contains("email: email.trim()"))
        let appleIdentity = try source(at: "backend/src/appleIdentityToken.ts")
        XCTAssertTrue(appleIdentity.contains("https://appleid.apple.com"))
        XCTAssertTrue(appleIdentity.contains("com.wanderly.app.Clip"))
        XCTAssertFalse(save.contains("ASAuthorizationAppleIDProvider"))
        XCTAssertFalse(save.contains("enum ClipSaveError: Error"))
        XCTAssertTrue(save.contains("ClipFullApp.isInstalled"))
        XCTAssertTrue(entitlements.contains("com.apple.developer.applesignin"))
        XCTAssertFalse(clipPayload.contains("var photoAttribution"))
        XCTAssertFalse(appPayload.contains("var photoAttribution"))
        XCTAssertTrue(appPayload.contains("isGooglePlacesPhotoURL"))
        XCTAssertTrue(appPayload.contains("isGoogleDomainURL"))
        XCTAssertTrue(clipPayload.contains("isGoogleDomainURL"))
        let list = try source(at: "SAV-E/Models/SaveCollaborativeList.swift")
        XCTAssertTrue(list.contains("sanitizingPublicPayload"))
        XCTAssertTrue(list.contains("func asPlace(id: UUID"))
        XCTAssertTrue(list.contains("ClipListHandoff.isGooglePlaceID"))
        XCTAssertTrue(list.contains("coordinateSystem: place.coordinateSystem"))
        XCTAssertTrue(list.contains("locationProvider: place.locationProvider"))
        XCTAssertTrue(list.contains("providerMapUrl: place.providerMapUrl"))
        XCTAssertTrue(pending.contains("static let key = \"pendingShare\""))
        XCTAssertTrue(appPending.contains("matchesIncomingList"))
        XCTAssertTrue(appPending.contains("enum ClipListHandoff"))
        XCTAssertTrue(appPending.contains("static let key = \"pendingShare\""))
        XCTAssertTrue(app.contains("restorePendingShare"))
        XCTAssertTrue(app.contains("ClipAppleAccountStore.clear"))
        XCTAssertFalse(content.contains("performPendingShareAutoSave"))
        XCTAssertTrue(content.contains("friendShareNoteTitle"))
        XCTAssertTrue(content.contains("FriendShareNoteCopy.title"))
        XCTAssertTrue(content.contains("friendShareReceipt.note"))
        XCTAssertTrue(content.contains("performPendingListStampImport"))
        XCTAssertTrue(content.contains("saveClipListHandoff"))
        XCTAssertFalse(content.contains("saveListItemAsPlace"))
        let mapVM = try source(at: "SAV-E/ViewModels/MapViewModel.swift")
        XCTAssertTrue(mapVM.contains("func saveClipListHandoff"))
        XCTAssertTrue(mapVM.contains("placesFromRemoteRows"))
        XCTAssertTrue(mapVM.contains("includeSenderMemory: false"))
        XCTAssertFalse(mapVM.contains("stampsFromRemoteCounts"))
        XCTAssertEqual(
            save.components(separatedBy: "guard written else { return .failed }").count - 1,
            2
        )
        XCTAssertEqual(
            save.components(separatedBy: "continuation.resume(returning: opened ? .handedOff : .pending(count))").count - 1,
            1
        )
        XCTAssertTrue(save.contains("func persist("))
        XCTAssertTrue(save.contains("func persistList"))
        XCTAssertTrue(planner.contains("handoffAfterPersist"))
        XCTAssertTrue(planner.contains("compactHandoffURL"))
        XCTAssertTrue(save.contains("compactHandoffURL"))
        XCTAssertTrue(appPending.contains("acceptedListURL"))
        XCTAssertTrue(app.contains("acceptedListURL"))
        XCTAssertFalse(clip.contains("note: draft.note"))
        XCTAssertFalse(clip.contains("rating: draft.rating"))
        let handoff = clip[
            clip.range(of: "private func handoffURL")!.lowerBound
            ..< clip.range(of: "private func openLeftover")!.lowerBound
        ]
        XCTAssertTrue(handoff.contains("strippingSenderMemory()"))
        XCTAssertFalse(
            handoff.split(whereSeparator: \.isNewline).contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && trimmed.hasPrefix("return lastIncomingURL")
            }
        )
        XCTAssertTrue(appPayload.contains("func strippingSenderMemory()"))
        XCTAssertTrue(appPayload.contains("enum FriendShareNoteCopy"))
        XCTAssertTrue(clipPayload.contains("func strippingSenderMemory()"))
        XCTAssertTrue(save.contains("func persistList"))
        XCTAssertTrue(save.contains(") -> Bool"))
        let placeModel = try source(at: "SAV-E/Models/Place.swift")
        XCTAssertTrue(placeModel.contains("fromClipSnapshot"))
        let supabase = try source(at: "SAV-E/Services/SupabaseService.swift")
        XCTAssertTrue(supabase.contains("func saveClipListPlaces"))
        guard let protoStart = supabase.range(of: "protocol SupabaseServiceProtocol"),
              let implStart = supabase.range(of: "final class SupabaseService:") else {
            return XCTFail("SupabaseServiceProtocol bounds")
        }
        let proto = String(supabase[protoStart.lowerBound..<implStart.lowerBound])
        XCTAssertTrue(proto.contains("func saveClipListPlaces"))
        XCTAssertFalse(mapVM.contains("supabaseService.isConfigured"))
        XCTAssertTrue(mapVM.contains("catch SupabaseError.notConfigured"))
        XCTAssertTrue(mapVM.contains("stampedHandoffItems"))
        XCTAssertTrue(mapVM.contains("importedPlace(_ place: Place, matches item: SaveListItem)"))
        XCTAssertTrue(mapVM.contains("contains(where:"))
        XCTAssertFalse(mapVM.contains("imported.contains {"))
        XCTAssertTrue(mapVM.contains("rows: remote.saved"))
        XCTAssertFalse(mapVM.contains("remote.saved + remote.already"))
        let listHandoff = mapVM[
            mapVM.range(of: "private func saveClipListHandoff")!.lowerBound
            ..< mapVM.range(of: "private func parkHandoffOverflowIfNeeded")!.lowerBound
        ]
        // Stale already-saved stamps must refresh from /places. The broad
        // loadPlaces(force: true) loader also imports clues and must not run
        // in this scope (a1ce8874).
        XCTAssertTrue(listHandoff.contains("needsPlaceRefresh"))
        XCTAssertTrue(listHandoff.contains("supabaseService.fetchPlaces(for: owner)"))
        XCTAssertTrue(listHandoff.contains("mergeRemotePlaces(remotePlaces, withLocalPlaces: localConfirmedPlaces())"))
        XCTAssertFalse(listHandoff.contains("loadPlaces(force: true)"))
        XCTAssertTrue(mapVM.contains("needsPlaceRefresh"))
        XCTAssertTrue(mapVM.contains("rekeyed(to: place.id)"))
        let receiptSave = mapVM[
            mapVM.range(of: "func saveSharedPlaceReceipt")!.lowerBound
            ..< (mapVM.range(of: "func acceptFriendRestaurantSave")?.lowerBound ?? mapVM.endIndex)
        ]
        XCTAssertTrue(receiptSave.contains("recipientOwnedPlace(ownerSubject:"))
        XCTAssertTrue(receiptSave.contains("applyingJournalCoordinates"))
        XCTAssertFalse(receiptSave.contains("receipt.privatePlace()"))
        XCTAssertTrue(receiptSave.contains("parkPlaceInUnplacedInbox"))
        XCTAssertTrue(receiptSave.contains("SavePlaceLimitError.parkedInUnplacedInbox"))
        XCTAssertTrue(receiptSave.contains("supabaseService.savePlace"))
        XCTAssertTrue(receiptSave.contains("parkIfServerSavedPlaceLimit"))
        XCTAssertFalse(receiptSave.contains("placesFromRemoteRows(confirmed: [item], rows: already)"))
        XCTAssertFalse(content.contains("catch ClipListHandoffError.capReached"))
        XCTAssertFalse(content.contains("Free Savvy is full (50 places)."))
        XCTAssertFalse(content.contains("免費版 Savvy 已滿 50 個地點。"))
        XCTAssertFalse(content.contains("已滿 50 個"))
        XCTAssertTrue(content.contains("catch is SavePlaceLimitError"))
        XCTAssertTrue(content.contains("if error is SavePlaceLimitError { return }"))
        XCTAssertTrue(mapVM.contains("parkHandoffOverflowIfNeeded"))
        XCTAssertTrue(mapVM.contains("parkNovelHandoffItems"))
        XCTAssertTrue(appPending.contains("static func onePlaceImport"))
        XCTAssertTrue(appPending.contains("static func needsPlaceRefresh"))
        let listModel = try source(at: "SAV-E/Models/SaveCollaborativeList.swift")
        XCTAssertTrue(listModel.contains("matchesMapFeature(title: title, coordinate: coordinate)"))
        XCTAssertFalse(listModel.contains("place.name.localizedCaseInsensitiveCompare(title)"))
        // PendingShareStoreTests.testPlanStampsRecordsSkippedIdentities verifies
        // the retained alias chain against the actual planner, independent of
        // whether the implementation uses a seen set or merges identity groups.
        let carry = try source(at: "SAV-E/Services/ClipSignInCarryOver.swift")
        let appleStore = try source(at: "SAV-E/Models/ClipAppleAccountStore.swift")
        let auth = try source(at: "SAV-E/Services/PrivyAuthService.swift")
        XCTAssertTrue(appleStore.contains("static let key = \"clipAppleUserID\""))
        XCTAssertTrue(appleStore.contains("never a JWT"))
        XCTAssertFalse(carry.contains("getCredentialState(forUserID:"))
        XCTAssertFalse(carry.contains("withCheckedContinuation"))
        XCTAssertFalse(carry.contains("requestedScopes = []"))
        XCTAssertFalse(carry.contains("case skipSignIn"))
        XCTAssertFalse(auth.contains("restoreClipSignInIfNeeded"))
        XCTAssertFalse(auth.contains("ClipAppleAccountStore.read"))
        XCTAssertTrue(auth.contains("ClipAppleAccountStore.clear"))
        XCTAssertFalse(auth.contains("clipAppleSessionActive"))
        XCTAssertFalse(auth.contains("ClipAppleSessionExchange.exchange"))
        XCTAssertFalse(auth.contains("try await signInWithApple()"))
        XCTAssertFalse(appleStore.contains("identityToken"))
        XCTAssertFalse(appleStore.contains("Bearer"))
        XCTAssertFalse(save.contains("ClipAppleAccountStore.write(credential.user)"))
        XCTAssertFalse(save.contains("static let key = \"clipAppleUserID\""))
        XCTAssertFalse(entitlements.contains("keychain-access-groups"))
        XCTAssertTrue(strings.contains("clip.save"))
        XCTAssertTrue(strings.contains("clip.saveAll"))
        XCTAssertTrue(strings.contains("Continue with %d places"))
        XCTAssertTrue(strings.contains("帶 %d 家到 Savvy"))
        XCTAssertTrue(strings.contains("clip.listSaved.row.new"))
        XCTAssertTrue(strings.contains("clip.listPartial.body"))
        XCTAssertFalse(strings.contains("#293 Q1"), "Internal planning notes must not appear in shipped copy")
        XCTAssertTrue(strings.contains("50 unique places"))
        XCTAssertTrue(strings.contains("50 個不重複地點"))
        XCTAssertTrue(strings.contains("clip.signin.saveOne"))
        XCTAssertTrue(strings.contains("Save this place"))
        XCTAssertTrue(strings.contains("存這一家"))
        XCTAssertTrue(strings.contains("Save %d places"))
        XCTAssertTrue(strings.contains("往上滑看下一家"))
        XCTAssertTrue(strings.contains("clip.saved.title"))
        XCTAssertTrue(strings.contains("clip.cap50.body"))
        XCTAssertTrue(strings.contains("clip.cap50.saved"))
        XCTAssertTrue(strings.contains("已存 50 個"))
        XCTAssertTrue(strings.contains("Saved 50"))
        XCTAssertTrue(
            strings.contains("Free limit\\nreached"),
            "cap50 English title must wrap so the last Caveat glyph is not clipped"
        )
        XCTAssertTrue(strings.contains("%@'s note"))
        XCTAssertTrue(clip.contains("clip.cap50.saved"))
        XCTAssertTrue(clip.contains("clip.cap50.title"))
        XCTAssertTrue(theme.contains("clip.friendNote"))
        XCTAssertTrue(clip.contains("clip.wordmark") || theme.contains("clip.wordmark"))
        XCTAssertGreaterThanOrEqual(clip.components(separatedBy: "ClipWordmarkPlate()").count - 1, 3)
        XCTAssertTrue(design.contains("preserve the pending journal and the current Unplaced/paywall recovery"))
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
            if let result = ClipListSavePlanner.onePlaceResult(status: status, data: data) {
                switch result {
                case .saved: return "saved"
                case .duplicate: return "duplicate"
                case .capReached: return "cap"
                case .failed: return "failed"
                }
            }
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
        XCTAssertEqual(
            parse(201, json: #"{"newly_saved":0,"already_saved":0,"over_cap":1,"remaining":0,"limit":50}"#),
            "cap"
        )
        XCTAssertEqual(
            parse(201, json: #"{"newly_saved":0,"already_saved":1,"over_cap":0,"remaining":0,"limit":50}"#),
            "duplicate"
        )
        XCTAssertNotEqual(
            parse(201, json: #"{"newly_saved":0,"already_saved":0,"over_cap":1,"remaining":0,"limit":50}"#),
            "saved"
        )
    }

    func testClipScreenshotRailForcesDarkBeforeFirstPaint() throws {
        let clipApp = try source(at: "SAV-EClip/SAV-EClipApp.swift")
        XCTAssertTrue(clipApp.contains("--uitest-force-dark"))
        XCTAssertTrue(clipApp.contains("--uitest-force-light"))
        XCTAssertTrue(clipApp.contains("overrideUserInterfaceStyle"))
        XCTAssertTrue(clipApp.contains("preferredColorScheme"))
        let shots = try source(at: "Tests/SAVEClipUITests/SAVEClipScreenshotTests.swift")
        XCTAssertTrue(shots.contains("-AppleInterfaceStyle"))
        XCTAssertTrue(shots.contains("--uitest-force-dark"))
        XCTAssertTrue(shots.contains("assertDarkCanvas"))
        XCTAssertTrue(shots.contains("place-zh-Hant-dark"))
        XCTAssertTrue(shots.contains("05-state-\\(screen)-dark"))
        XCTAssertTrue(shots.contains("19b-list-partial-en-dark"))
        XCTAssertTrue(shots.contains("19-list-saved-en-dark"))
        XCTAssertTrue(shots.contains("save-fail-en-dark"))
        XCTAssertTrue(shots.contains("skoverlay-en-dark"))
        XCTAssertTrue(shots.contains("cap50-en-dark"))
        XCTAssertTrue(shots.contains("clip.cap50.title"))
        XCTAssertTrue(shots.contains("Free limit reached"))
        XCTAssertTrue(shots.contains("friend-note-en"))
        XCTAssertTrue(shots.contains("clip.friendNote.by"))
        XCTAssertTrue(shots.contains("sharer-en-light"))
        XCTAssertTrue(shots.contains("sharer-en-dark"))
        XCTAssertTrue(shots.contains("assertSharerChipContrast"))
        XCTAssertTrue(shots.contains("heroSharerChipBand"))
        XCTAssertFalse(
            shots.contains("let chip = app.descendants(matching: .any)[\"clip.sharer\"]"),
            "do not query the overlay chip as an XCUI identifier"
        )
        let workflow = try source(at: ".github/workflows/ci.yml")
        XCTAssertTrue(workflow.contains("11-iansui-proof.md"))
        XCTAssertTrue(workflow.contains("Iansui-ClipTitles.ttf"))
        XCTAssertTrue(workflow.contains("Iansui-Regular"))
        XCTAssertTrue(workflow.contains("12-screenshot-manifest.md"))
        XCTAssertTrue(workflow.contains("appclip-doodle-screenshots-"))
        let proof = try source(at: "SAV-E/Resources/DisplayFont/11-iansui-proof.md")
        XCTAssertTrue(proof.contains("Iansui-ClipTitles.ttf"))
        XCTAssertTrue(proof.contains("cascadeList"))
        XCTAssertTrue(proof.contains("Caveat"))
    }

    func testClipCoralStaysF26B4AInDark() throws {
        let coral = try source(at: "SAV-EClip/Assets.xcassets/ClipCoral.colorset/Contents.json")
        XCTAssertTrue(coral.contains("\"red\": \"0.949\""))
        XCTAssertTrue(coral.contains("\"green\": \"0.420\""))
        XCTAssertTrue(coral.contains("\"blue\": \"0.290\""))
        XCTAssertTrue(coral.contains("\"value\": \"dark\""))
        XCTAssertEqual(coral.components(separatedBy: "0.949").count - 1, 2)
    }

    func testClipStickerInkCatalogDoesNotFlipInDark() throws {
        let ink = try source(at: "SAV-EClip/Assets.xcassets/ClipStickerInk.colorset/Contents.json")
        XCTAssertTrue(ink.contains("\"value\": \"dark\""))
        XCTAssertEqual(ink.components(separatedBy: "\"red\": \"0.184\"").count - 1, 2)
        XCTAssertEqual(ink.components(separatedBy: "\"green\": \"0.180\"").count - 1, 2)
        XCTAssertEqual(ink.components(separatedBy: "\"blue\": \"0.137\"").count - 1, 2)
        XCTAssertGreaterThan(
            ClipContrastEvidence.ratio(
                foreground: ClipContrastEvidence.stickerInk,
                background: ClipContrastEvidence.cream
            ),
            7.0,
            "Mina shared with you on cream must stay well above AA"
        )
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

enum ClipContrastEvidence {
    static let stickerInk = (47.0 / 255.0, 46.0 / 255.0, 35.0 / 255.0)
    static let cream = (1.0, 249.0 / 255.0, 235.0 / 255.0)
    static let plate = (234.0 / 255.0, 221.0 / 255.0, 198.0 / 255.0)

    static func ratio(
        foreground: (Double, Double, Double),
        background: (Double, Double, Double)
    ) -> Double {
        let a = luminance(foreground)
        let b = luminance(background)
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ rgb: (Double, Double, Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }
}
