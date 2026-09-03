import CoreLocation
import XCTest
@testable import SAVE

final class SaveCollaborativeListTests: XCTestCase {
    @MainActor
    func testSharedListLinkRoundTripsViewerRole() throws {
        var list = SaveCollaborativeList(title: "Tokyo cafes", note: "For Saturday")
        list.add(.from(place: place(name: "Onibus Coffee", category: .cafe)))

        let url = try XCTUnwrap(list.shareURL(role: .viewer))
        let payload = try XCTUnwrap(SaveSharedListPayload.from(url: url))

        XCTAssertEqual(payload.role, .viewer)
        XCTAssertEqual(payload.list.viewerRole, .viewer)
        XCTAssertEqual(payload.list.title, "Tokyo cafes")
        XCTAssertEqual(payload.list.items.first?.title, "Onibus Coffee")
    }

    @MainActor
    func testListAcceptsSavedPlaceAndUnsavedMapCandidateSnapshots() {
        var list = SaveCollaborativeList(title: "OC weekend")
        let saved = place(name: "Maru Coffee", category: .cafe)
        let candidate = SaveMapCandidate(
            title: "Bright Coffee Bar",
            subtitle: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            category: .cafe,
            rating: 4.6,
            reviewCount: 120,
            sourceURL: "https://maps.apple.com/?q=Bright%20Coffee",
            photoURL: "https://example.com/bright.jpg",
            businessPhotoURLs: ["https://example.com/bright-2.jpg"],
            evidence: ["Apple Maps result"]
        )

        list.add(.from(place: saved))
        list.add(.from(candidate: candidate))

        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items.map(\.source), [.savedPlace, .mapCandidate])
        XCTAssertEqual(list.items.last?.photoURLs, ["https://example.com/bright.jpg", "https://example.com/bright-2.jpg"])
    }

    @MainActor
    func testViewerJoinedListCannotAddItems() {
        var list = SaveCollaborativeList(title: "Viewer list", viewerRole: .viewer)
        list.add(.from(place: place(name: "Viewer Coffee", category: .cafe)))

        XCTAssertTrue(list.items.isEmpty)
        XCTAssertFalse(list.canEdit)
    }

    @MainActor
    func testEditorJoinedListCanAddItems() {
        var list = SaveCollaborativeList(title: "Editor list", viewerRole: .editor)
        list.add(.from(place: place(name: "Editor Coffee", category: .cafe)))

        XCTAssertEqual(list.items.count, 1)
        XCTAssertTrue(list.canEdit)
    }

    @MainActor
    func testFriendCanSaveListItemIntoOwnSave() {
        let candidate = SaveMapCandidate(
            title: "List Ramen",
            subtitle: "Los Angeles, CA",
            latitude: 34.0522,
            longitude: -118.2437,
            category: .food,
            rating: 4.7,
            sourceURL: "https://maps.apple.com/?q=List%20Ramen",
            evidence: ["Apple Maps result"]
        )
        let item = SaveListItem.from(candidate: candidate, addedByDisplayName: "Ezven")
        let saved = item.asPlace()

        XCTAssertEqual(saved.name, "List Ramen")
        XCTAssertEqual(saved.category, .food)
        XCTAssertEqual(saved.googleRating, 4.7)
        XCTAssertEqual(saved.recommender, "Ezven")
        XCTAssertEqual(saved.sourceUrl, "https://maps.apple.com/?q=List%20Ramen")
    }

    @MainActor
    func testListItineraryKeepsUnsavedItemsSeparateFromPlaceIds() {
        var list = SaveCollaborativeList(title: "Mixed plan")
        let saved = place(name: "Saved Cafe", category: .cafe)
        let unsaved = SaveMapCandidate(
            title: "Unsaved Sushi",
            subtitle: "Costa Mesa, CA",
            latitude: 33.6638,
            longitude: -117.9047,
            category: .food
        )

        list.add(.from(place: saved))
        list.add(.from(candidate: unsaved))
        let response = list.itineraryResponse()

        XCTAssertEqual(response.componentType, .tripItinerary)
        XCTAssertEqual(response.placeIds, [saved.id.uuidString])
        XCTAssertEqual(response.itineraryDays.first?.stops.count, 2)
        XCTAssertTrue(response.itineraryDays.first?.stops.last?.note?.contains("Map result") == true)
    }

    @MainActor
    func testGooglePhotoKeyIsAddedOnlyForTheTransientRequest() throws {
        let service = GooglePlacesService(
            apiKey: "TEST_ONLY_NON_SECRET_VALUE",
            bundleIdentifier: "com.wanderly.app"
        )
        let persistedURL = try XCTUnwrap(service.photoURL(reference: "photo/reference+value", maxWidth: 900))
        let persistedItems = try XCTUnwrap(URLComponents(url: persistedURL, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertNil(persistedItems.first(where: { $0.name == "key" }))
        XCTAssertEqual(persistedItems.first(where: { $0.name == "photo_reference" })?.value, "photo/reference+value")
        XCTAssertTrue(persistedURL.absoluteString.contains("%2B"))
        XCTAssertFalse(persistedURL.absoluteString.contains("photo_reference=photo/reference+value"))

        let requestURL = try XCTUnwrap(service.authorizedPhotoURL(for: persistedURL))
        let requestItems = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(requestItems.first(where: { $0.name == "key" })?.value, "TEST_ONLY_NON_SECRET_VALUE")
        XCTAssertEqual(GooglePlacesPhotoURL.persistableURL(requestURL), persistedURL)

        let request = try XCTUnwrap(service.authorizedPhotoRequest(for: persistedURL))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier"), "com.wanderly.app")
    }

    @MainActor
    func testBusinessPhotoEnrichmentFallsBackWhenSavedGooglePlaceIDIsStale() async throws {
        var saved = place(name: "amamotobros", category: .food)
        saved.address = "No. 377, Section 4, Ren'ai Road, Taipei"
        saved.latitude = 25.0386
        saved.longitude = 121.5557
        saved.googlePlaceId = "stale-place-id"
        let service = StaleGooglePlaceIDService()

        let result = await PlaceBusinessEnricher.enrich(saved, service: service)
        let enriched = try XCTUnwrap(result)

        XCTAssertEqual(service.requestedDetailIDs, ["stale-place-id", "fresh-place-id"])
        XCTAssertEqual(enriched.businessPhotoURLStrings, ["https://example.com/amamotobros.jpg"])
        XCTAssertEqual(enriched.googleRating, 4.8)
    }

    @MainActor
    func testBusinessPhotosStayAheadOfSourceImageAndKeepTheirOrder() async throws {
        var saved = place(name: "Memory Cafe", category: .cafe)
        saved.sourceImageUrl = "https://example.com/social-post.jpg"
        saved.businessPhotoUrls = ["https://example.com/stable-cover.jpg"]

        let result = await PlaceBusinessEnricher.enrich(
            saved,
            service: ReorderedPhotoGooglePlacesService()
        )
        let enriched = try XCTUnwrap(result)

        XCTAssertEqual(enriched.businessPhotoURLStrings, [
            "https://example.com/stable-cover.jpg",
            "https://example.com/new-first.jpg",
            "https://example.com/social-post.jpg",
        ])
    }

    @MainActor
    func testBusinessPhotoLookupRejectsNearbyWrongBusiness() async {
        var saved = place(name: "Memory Cafe", category: .cafe)
        saved.latitude = 25.0330
        saved.longitude = 121.5654

        let enriched = await PlaceBusinessEnricher.enrich(
            saved,
            service: NearbyWrongBusinessGooglePlacesService()
        )

        XCTAssertNil(enriched)
    }

    @MainActor
    func testHomePhotoEnrichmentBackfillsOnlyMissingPhotosOncePerSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = HomePhotoGooglePlacesService()
        let map = MapViewModel(
            googlePlacesService: service,
            saveLocalVaultService: SaveLocalVaultService(
                overrideVaultURL: directory.appendingPathComponent("save-memory-records.json")
            ),
            usesRemotePersistence: false
        )
        let missing = place(name: "Memory Cafe", category: .cafe)
        var existing = place(name: "Existing Photo", category: .cafe)
        existing.sourceImageUrl = "https://example.com/existing.jpg"
        map.places = [missing, existing]

        await map.enrichMissingHomePlacePhotos()
        await map.enrichMissingHomePlacePhotos()

        XCTAssertEqual(
            map.places.first(where: { $0.id == missing.id })?.businessPhotoURLStrings,
            ["https://example.com/memory-cafe.jpg"]
        )
        XCTAssertEqual(
            map.places.first(where: { $0.id == existing.id })?.businessPhotoURLStrings,
            ["https://example.com/existing.jpg"]
        )
        XCTAssertEqual(service.searchCallCount, 1)
    }

    @MainActor
    func testPersistedMemoryAndSharedListsStripLegacyGooglePhotoKeys() throws {
        let legacyURL = "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=legacy-ref&key=TEST_ONLY_NON_SECRET_VALUE"
        let record = SaveMemoryRecord(
            state: .confirmedPlace,
            title: "Legacy Cafe",
            sourceImageUrl: legacyURL,
            businessPhotoUrls: [legacyURL]
        )
        XCTAssertFalse(try XCTUnwrap(record.sourceImageUrl).contains("key="))
        XCTAssertFalse(try XCTUnwrap(record.businessPhotoUrls?.first).contains("key="))

        var legacyPlace = place(name: "Legacy Cafe", category: .cafe)
        legacyPlace.sourceImageUrl = legacyURL
        legacyPlace.businessPhotoUrls = [legacyURL]
        var list = SaveCollaborativeList(title: "Safe list")
        list.add(.from(place: legacyPlace))

        let shareURL = try XCTUnwrap(list.shareURL())
        let payload = try XCTUnwrap(SaveSharedListPayload.from(url: shareURL))
        XCTAssertFalse(try XCTUnwrap(payload.list.items.first?.photoURLs.first).contains("key="))
    }

    // MARK: - Server short-code links (`?c=`)

    @MainActor
    func testShareCodeParsesServerListLinks() throws {
        let https = try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/list?c=Ab3_x-9Q"))
        XCTAssertEqual(SaveSharedListPayload.shareCode(from: https), "Ab3_x-9Q")
        XCTAssertTrue(SaveSharedListPayload.isListLink(https))

        let currentScheme = try XCTUnwrap(URL(string: "savvy://list?c=abcdef"))
        XCTAssertEqual(SaveSharedListPayload.shareCode(from: currentScheme), "abcdef")

        let legacyScheme = try XCTUnwrap(URL(string: "wanderly://list?c=abcdef"))
        XCTAssertEqual(SaveSharedListPayload.shareCode(from: legacyScheme), "abcdef")
    }

    @MainActor
    func testShareCodeRejectsMalformedOrLegacyLinks() throws {
        // Legacy embedded-snapshot link has no code.
        let legacy = try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/list?d=eyJ9&r=viewer"))
        XCTAssertNil(SaveSharedListPayload.shareCode(from: legacy))

        // Too short, bad characters, wrong host/path.
        XCTAssertNil(SaveSharedListPayload.shareCode(from: try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/list?c=abc"))))
        XCTAssertNil(SaveSharedListPayload.shareCode(from: try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/list?c=abc%20def1"))))
        XCTAssertNil(SaveSharedListPayload.shareCode(from: try XCTUnwrap(URL(string: "https://evil.example.com/list?c=abcdef"))))
        XCTAssertNil(SaveSharedListPayload.shareCode(from: try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/trip?c=abcdef"))))
    }

    // MARK: - Server row mapping

    @MainActor
    func testServerRowMapsToCollaborativeListAndRoundTripsItemPayload() throws {
        let item = SaveListItem.from(place: place(name: "Onibus Coffee", category: .cafe), addedByDisplayName: "Ezven")
        let listID = UUID()
        let row = SaveCollaborativeListServerRow(
            id: listID.uuidString.lowercased(),
            title: "Tokyo cafes",
            note: "Saturday",
            owner_id: "did:privy:owner",
            viewer_role: "editor",
            items: [SaveCollaborativeListServerItemRow(id: UUID().uuidString, payload: item, added_by: "did:privy:owner")],
            created_at: "2026-08-12T10:00:00Z",
            updated_at: "2026-08-12T11:30:00.123Z"
        )

        // Round trip the row itself the way the API layer does (plain coders).
        let data = try JSONEncoder.supabase.encode(row)
        let decodedRow = try JSONDecoder.supabase.decode(SaveCollaborativeListServerRow.self, from: data)
        let list = try XCTUnwrap(SaveCollaborativeList(serverRow: decodedRow))

        XCTAssertEqual(list.id, listID)
        XCTAssertEqual(list.title, "Tokyo cafes")
        XCTAssertEqual(list.note, "Saturday")
        XCTAssertEqual(list.viewerRole, .editor)
        XCTAssertTrue(list.serverBacked)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items.first?.title, "Onibus Coffee")
        XCTAssertEqual(list.items.first?.addedByDisplayName, "Ezven")
        XCTAssertEqual(list.createdAt, SaveCollaborativeList.serverDate("2026-08-12T10:00:00Z"))
        XCTAssertEqual(list.updatedAt, SaveCollaborativeList.serverDate("2026-08-12T11:30:00.123Z"))
    }

    @MainActor
    func testServerRowDropsUndecodableItemPayloadsInsteadOfFailing() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Lenient list",
          "viewer_role": "viewer",
          "items": [
            {"id": "x", "payload": {"unexpected": true}, "added_by": null, "created_at": null}
          ]
        }
        """
        let row = try JSONDecoder.supabase.decode(SaveCollaborativeListServerRow.self, from: Data(json.utf8))
        let list = try XCTUnwrap(SaveCollaborativeList(serverRow: row))

        XCTAssertTrue(list.items.isEmpty)
        XCTAssertEqual(list.viewerRole, .viewer)
        XCTAssertFalse(list.canEdit)
    }

    @MainActor
    func testServerRowWithNonUUIDIdIsRejected() {
        let row = SaveCollaborativeListServerRow(id: "not-a-uuid", title: "Bad", viewer_role: "owner")
        XCTAssertNil(SaveCollaborativeList(serverRow: row))
    }

    // MARK: - Merge + cache compatibility

    @MainActor
    func testMergeServerWinsByIdAndKeepsLocalOnlyLists() {
        let sharedID = UUID()
        let serverList = SaveCollaborativeList(
            id: sharedID,
            title: "Server title",
            viewerRole: .editor,
            updatedAt: Date(timeIntervalSinceNow: -10),
            serverBacked: true
        )
        let staleLocal = SaveCollaborativeList(id: sharedID, title: "Stale local title", updatedAt: Date())
        let localOnly = SaveCollaborativeList(title: "Offline list", updatedAt: Date(timeIntervalSinceNow: -100))

        let merged = MapViewModel.mergeCollaborativeLists(server: [serverList], local: [staleLocal, localOnly])

        XCTAssertEqual(merged.count, 2)
        let winner = merged.first(where: { $0.id == sharedID })
        XCTAssertEqual(winner?.title, "Server title")
        XCTAssertEqual(winner?.viewerRole, .editor)
        XCTAssertTrue(merged.contains(where: { $0.id == localOnly.id }))
        // Sorted by updatedAt descending.
        XCTAssertEqual(merged.map(\.id), [sharedID, localOnly.id])
    }

    @MainActor
    func testLegacyPersistedListsDecodeWithServerBackedDefaultingFalse() throws {
        // Snapshot of the pre-serverBacked persisted shape (plain JSONEncoder:
        // dates are seconds since the reference date).
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Legacy list",
          "ownerDisplayName": "You",
          "viewerRole": "owner",
          "items": [],
          "createdAt": 745000000,
          "updatedAt": 745000000
        }
        """
        let list = try JSONDecoder().decode(SaveCollaborativeList.self, from: Data(json.utf8))
        XCTAssertFalse(list.serverBacked)
        XCTAssertEqual(list.title, "Legacy list")

        // And the new field survives its own round trip.
        var backed = list
        backed.serverBacked = true
        let reencoded = try JSONEncoder().encode(backed)
        XCTAssertTrue(try JSONDecoder().decode(SaveCollaborativeList.self, from: reencoded).serverBacked)
    }

    // MARK: - Member + share-code row mapping

    @MainActor
    func testListMemberRowMapsRoleDateAndDisplayNameFallback() throws {
        let named = try JSONDecoder().decode(SaveListMemberRow.self, from: Data("""
        {"user_id": "did:privy:abc", "role": "owner", "display_name": "  Ezven  ", "created_at": "2026-08-01T10:20:30.123Z"}
        """.utf8))
        let info = SaveListMemberInfo(row: named)
        XCTAssertEqual(info.id, "did:privy:abc")
        XCTAssertEqual(info.role, .owner)
        XCTAssertEqual(info.displayName, "Ezven")
        XCTAssertNotNil(info.joinedAt)

        // Missing role/name/date degrade instead of dropping the row.
        let bare = SaveListMemberInfo(row: SaveListMemberRow(user_id: "did:privy:xyz"))
        XCTAssertEqual(bare.role, .viewer)
        XCTAssertEqual(bare.displayName, "Traveler")
        XCTAssertNil(bare.joinedAt)
    }

    @MainActor
    func testListShareCodeRowMapsAndNeverGrantsOwnerBadge() {
        let editor = SaveListShareCodeInfo(row: SaveListShareCodeInfoRow(
            code: "abc123",
            role: "editor",
            url: "https://sav-e-app.vercel.app/list?c=abc123",
            expires_at: "2026-09-01T00:00:00Z",
            created_at: "2026-08-01T00:00:00Z"
        ))
        XCTAssertEqual(editor.id, "abc123")
        XCTAssertEqual(editor.role, .editor)
        XCTAssertEqual(editor.url?.absoluteString, "https://sav-e-app.vercel.app/list?c=abc123")
        XCTAssertNotNil(editor.expiresAt)
        XCTAssertNotNil(editor.createdAt)

        // Share codes only ever grant viewer/editor; an "owner" (or unknown)
        // role from the server renders as the safer viewer badge.
        let owner = SaveListShareCodeInfo(row: SaveListShareCodeInfoRow(code: "own", role: "owner"))
        XCTAssertEqual(owner.role, .viewer)
        let unknown = SaveListShareCodeInfo(row: SaveListShareCodeInfoRow(code: "wat", role: "banana"))
        XCTAssertEqual(unknown.role, .viewer)
        XCTAssertNil(unknown.url)
        XCTAssertNil(unknown.expiresAt)
    }

    @MainActor
    private func place(name: String, category: PlaceCategory) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            googlePlaceId: nil,
            category: category,
            status: .wantToGo,
            rating: nil,
            note: "House pick",
            sourceUrl: "https://example.com/\(name)",
            sourcePlatform: .other,
            sourceImageUrl: nil,
            businessPhotoUrls: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }
}

@MainActor
private final class StaleGooglePlaceIDService: GooglePlacesServiceProtocol {
    private(set) var requestedDetailIDs: [String] = []

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        [
            GooglePlaceMatch(
                id: "fresh-place-id",
                name: "amamotobros",
                address: "No. 377, Section 4, Ren'ai Road, Taipei",
                latitude: 25.0386,
                longitude: 121.5557,
                rating: 4.8,
                photoReference: "amamotobros-photo"
            )
        ]
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        requestedDetailIDs.append(placeId)
        guard placeId == "fresh-place-id" else {
            throw URLError(.badServerResponse)
        }
        return GooglePlaceDetails(
            placeId: placeId,
            name: "amamotobros",
            formattedAddress: "No. 377, Section 4, Ren'ai Road, Taipei",
            latitude: 25.0386,
            longitude: 121.5557,
            rating: 4.8,
            priceLevel: nil,
            openingHours: nil,
            phoneNumber: nil,
            websiteUrl: nil,
            photoReferences: ["amamotobros-photo"]
        )
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        URL(string: "https://example.com/amamotobros.jpg")
    }
}

@MainActor
private final class HomePhotoGooglePlacesService: GooglePlacesServiceProtocol {
    private(set) var searchCallCount = 0

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        searchCallCount += 1
        return [
            GooglePlaceMatch(
                id: "memory-cafe",
                name: "Memory Cafe",
                address: "Irvine, CA",
                latitude: 33.6849,
                longitude: -117.8262,
                rating: 4.6,
                photoReference: "memory-cafe-photo"
            )
        ]
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        GooglePlaceDetails(
            placeId: placeId,
            name: "Memory Cafe",
            formattedAddress: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            rating: 4.6,
            priceLevel: nil,
            openingHours: nil,
            phoneNumber: nil,
            websiteUrl: nil,
            photoReferences: ["memory-cafe-photo"]
        )
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        URL(string: "https://example.com/memory-cafe.jpg")
    }
}

@MainActor
private final class ReorderedPhotoGooglePlacesService: GooglePlacesServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        [GooglePlaceMatch(
            id: "memory-cafe",
            name: "Memory Cafe",
            address: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            photoReference: "new-first"
        )]
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        GooglePlaceDetails(
            placeId: placeId,
            name: "Memory Cafe",
            formattedAddress: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            rating: 4.6,
            priceLevel: 2,
            openingHours: ["Monday: 9:00 AM – 5:00 PM"],
            phoneNumber: nil,
            websiteUrl: nil,
            photoReferences: ["new-first"]
        )
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        URL(string: "https://example.com/new-first.jpg")
    }
}

@MainActor
private final class NearbyWrongBusinessGooglePlacesService: GooglePlacesServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        [GooglePlaceMatch(
            id: "wrong-restaurant",
            name: "Different Restaurant",
            address: "Nearby",
            latitude: 25.0337,
            longitude: 121.5654,
            photoReference: "wrong-photo"
        )]
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        XCTFail("An unrelated nearby business must not be enriched")
        throw URLError(.resourceUnavailable)
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        URL(string: "https://example.com/wrong.jpg")
    }
}
