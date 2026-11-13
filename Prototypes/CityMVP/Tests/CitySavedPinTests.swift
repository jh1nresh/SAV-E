import XCTest
import SwiftUI
import MapKit
import SpriteKit
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CitySavedPinTests: XCTestCase {
    private let registration = CityDistrictRegistration(latitudeOffset: 0, longitudeOffset: 0)

    func testPublicShowcaseBuildingsHaveNoPersonalPinUntilConfirmed() throws {
        let pins = CityMVPPlaceBridge.contextPins(in: [], registration: registration)
        XCTAssertEqual(pins.map(\.id), [CityMVPPlaceBridge.landmarkID])
        XCTAssertNil(CityMVPPlaceBridge.cityHallPlace(in: []))
        for id in ["way/137077760", "way/234589397", "way/226945262", CityMVPPlaceBridge.cityHallID] {
            let source = try XCTUnwrap(CityMVPPlaceBridge.context.first { $0.id == id })
            var saved = place(source: CityMVPPlaceBridge.sourceURL(for: source))
            saved.latitude = source.latitude; saved.longitude = source.longitude
            let actual = CityMVPPlaceBridge.contextPins(in: [saved], registration: registration)
            XCTAssertEqual(actual.filter { $0.id == id }.count, 1)
            XCTAssertEqual(CityMVPPlaceBridge.savedMatch(for: source, in: [saved])?.id, saved.id)
        }
    }

    func testArbitrarySaveGetsNativeCameraAnchorAndExactIdentityWithoutBorrowedPhoto() throws {
        let first = place(source: nil)
        var second = place(source: "https://example.com/branch-b")
        second.longitude += 0.001
        let pins = CityMVPPlaceBridge.contextPins(in: [first, second], registration: registration)
        let id = "saved:\(first.id.uuidString)"
        let pin = try XCTUnwrap(pins.first { $0.id == id })
        XCTAssertEqual(pin.coordinate.latitude, first.latitude)
        XCTAssertEqual(pin.coordinate.longitude, first.longitude)
        XCTAssertNil(pin.modelContact)
        XCTAssertNil(CityPinArtwork.photo(for: id))
        let vm = MapViewModel(usesRemotePersistence: false)
        vm.places = [first, second]
        vm.selectPlace(first, enrichPhoto: false)
        let selected = try XCTUnwrap(CityMVPSelectedPin(viewModel: vm, registration: registration))
        XCTAssertEqual(selected.contextID, id)
        XCTAssertEqual(selected.symbol, first.category.mapMarkerSymbol)
        XCTAssertTrue(selected.isSaved)
        XCTAssertEqual(selected.anchor.coordinate.latitude, first.latitude)
        XCTAssertEqual(selected.anchor.coordinate.longitude, first.longitude)
        XCTAssertEqual(Set(pins.map(\.id)).count, 3)
        let rendered = CityMVPPlaceBridge.places(context: [], saved: [first, second])
        XCTAssertEqual(rendered.filter(\.isSaved).count, 2)
        XCTAssertEqual(CityMVPPlaceBridge.symbol(for: rendered[0].category), first.category.mapMarkerSymbol)
        XCTAssertEqual(CityMVPPlaceBridge.symbol(for: rendered[1].category), second.category.mapMarkerSymbol)
        XCTAssertEqual(CityMVPPlaceBridge.savedMatch(for: rendered[0], in: [second, first])?.id, first.id)
        XCTAssertEqual(CityMVPPlaceBridge.sourceURL(for: rendered[0]), "")
        for (distance, heading) in [(1450.0, 20.0), (2600, 90), (1450, 220), (3799, 20), (3801, 20), (4151, 20)] {
            let camera = MapCamera(centerCoordinate: first.coordinate, distance: distance, heading: heading, pitch: 35)
            let frame = CityDistrictCamera(camera: camera, registration: registration,
                viewport: CGSize(width: 393, height: 852), contextPins: pins) { coordinate in
                let point = CityDistrictCamera.world(coordinate)
                return CGPoint(x: 190 + point.x / 3, y: 380 + point.z / 3)
            }
            let expected = CityDistrictCamera.world(first.coordinate)
            let placement = try XCTUnwrap(frame.contextPlacement(for: pin))
            XCTAssertEqual(placement.point.x, 190 + expected.x / 3, accuracy: 0.001)
            XCTAssertEqual(placement.point.y, 380 + expected.z / 3, accuracy: 0.001)
            XCTAssertTrue(CityMVPPlaceBridge.projectsSavedPin(first, in: frame, registration: registration))
        }
    }

    func testProviderNativeCoordinateIsNotRegisteredTwice() throws {
        let offset = try XCTUnwrap(CityDistrictRegistration.fromLandmark(.init(latitude: 25.030941, longitude: 121.568341)))
        let saved = place(source: "https://example.com/place")
        let pin = try XCTUnwrap(CityMVPPlaceBridge.contextPins(in: [saved], registration: offset)
            .first { $0.id == "saved:\(saved.id.uuidString)" })
        XCTAssertEqual(pin.coordinate.latitude, saved.latitude)
        XCTAssertEqual(pin.coordinate.longitude, saved.longitude)
        XCTAssertNotEqual(pin.coordinate.latitude, offset.mapCoordinate(saved.coordinate).latitude)
    }

    func testOnlyExactLicensedIdentityResolvesPhoto() throws {
        let att = try XCTUnwrap(CityMVPPlaceBridge.context.first { $0.id == "way/234589397" })
        var saved = place(source: CityMVPPlaceBridge.sourceURL(for: att))
        saved.latitude = att.latitude; saved.longitude = att.longitude
        XCTAssertNotNil(CityPinArtwork.photo(for: CityMVPPlaceBridge.contextID(for: saved)))
        saved.sourceUrl = nil // Same name/coordinates cannot authorize a photo join.
        XCTAssertNil(CityPinArtwork.photo(for: CityMVPPlaceBridge.contextID(for: saved)))
    }

    func testCircularCategorySelectionUsesSameAnchorAndInterruptedSpringAsPhotos() throws {
        let overlay = CityScenePins()
        let viewport = CGSize(width: 393, height: 852)
        func pin(_ selected: Bool) -> CityScenePin {
            .init(id: "saved:fixture", contextID: "saved:fixture", title: "Fixture café", symbol: "cup.and.saucer.fill",
                saved: true, selected: selected, placement: .init(point: CGPoint(x: 190, y: 380), contactOpacity: 0),
                reveal: 1, photoDiameter: 58, titleOpacity: 1, titleAbove: false)
        }
        // Ownership return is not a new user selection. A category circle
        // must mount at its full size, just like a selected photograph.
        overlay.update([pin(true)], viewport: viewport, night: false, reduceMotion: false)
        let mounted = try XCTUnwrap(overlay.scene.childNode(withName: "saved:fixture") as? SKSpriteNode)
        XCTAssertEqual(mounted.xScale, 1)
        XCTAssertFalse(overlay.isAnimating)
        overlay.update([], viewport: viewport, night: false, reduceMotion: false)
        overlay.update([pin(true)], viewport: viewport, night: false, reduceMotion: false)
        XCTAssertEqual(try XCTUnwrap(overlay.scene.childNode(withName: "saved:fixture") as? SKSpriteNode).xScale, 1)
        XCTAssertFalse(overlay.isAnimating)
        overlay.update([], viewport: viewport, night: false, reduceMotion: false)
        overlay.update([pin(false)], viewport: viewport, night: false, reduceMotion: false)
        let head = try XCTUnwrap(overlay.scene.childNode(withName: "saved:fixture") as? SKSpriteNode)
        let position = head.position
        overlay.update([pin(true)], viewport: viewport, night: false, reduceMotion: false)
        XCTAssertEqual(head.xScale * 62, CityPinArtwork.categoryDiameter, accuracy: 0.001)
        XCTAssertEqual(head.position, position)
        head.setScale(0.91)
        overlay.update([pin(false)], viewport: viewport, night: true, reduceMotion: false)
        XCTAssertEqual(head.xScale * CityPinArtwork.categoryDiameter, 62 * 0.91, accuracy: 0.001)
        XCTAssertEqual(head.position, position)
        overlay.update([pin(false)], viewport: viewport, night: true, reduceMotion: true)
        XCTAssertEqual(head.xScale, 1)
        XCTAssertFalse(overlay.isAnimating)
        for selected in [false, true] {
            for night in [false, true] {
                let image = CityPinRaster.head(pin(selected), night: night, reduceMotion: true)
                XCTAssertEqual(image.size, CGSize(width: 140, height: 92))
                let attachment = XCTAttachment(image: image)
                attachment.name = "saved-circle-\(selected ? "selected" : "browse")-\(night ? "night" : "day")"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

    func testSavedStatusRefreshesPhotoAndCategoryWithoutMovingOrReselecting() throws {
        XCTAssertNil(CityPinArtwork.savedBadgeSymbol(saved: false, visited: true))
        XCTAssertEqual(CityPinArtwork.savedBadgeSymbol(saved: true, visited: false), "bookmark.fill")
        XCTAssertEqual(CityPinArtwork.savedBadgeSymbol(saved: true, visited: true), "checkmark")
        XCTAssertEqual(CityPinArtwork.stateDescription(saved: true, visited: true), "Map Stamp · visited")
        XCTAssertFalse(CityPinArtwork.stateDescription(saved: true, visited: true).contains("verified"))
        let vm = MapViewModel(usesRemotePersistence: false)
        var saved = place(source: nil); saved.status = .visited
        vm.places = [saved]; vm.selectPlace(saved, enrichPhoto: false)
        XCTAssertTrue(try XCTUnwrap(CityMVPSelectedPin(viewModel: vm, registration: registration)).isVisited)
        for contextID in ["landmark-101", "saved:status-fixture"] {
            for night in [false, true] {
                let overlay = CityScenePins()
                let viewport = CGSize(width: 393, height: 852)
                var pin = CityScenePin(id: "status-fixture", contextID: contextID, title: "Fixture", symbol: "cup.and.saucer.fill",
                    saved: true, selected: true, placement: .init(point: CGPoint(x: 190, y: 380), contactOpacity: 0),
                    reveal: 1, photoDiameter: 58, titleOpacity: 1, titleAbove: false)
                overlay.update([pin], viewport: viewport, night: night, reduceMotion: false)
                let head = try XCTUnwrap(overlay.scene.childNode(withName: pin.id) as? SKSpriteNode)
                let wantedTexture = head.texture
                head.setScale(1.05)
                let position = head.position, anchor = head.anchorPoint
                pin.visited = true
                overlay.update([pin], viewport: viewport, night: night, reduceMotion: false)
                XCTAssertFalse(head.texture === wantedTexture, "Same-ID visit changes must invalidate the head texture")
                XCTAssertEqual(head.xScale, 1.05, accuracy: 0.000001); XCTAssertEqual(head.position, position); XCTAssertEqual(head.anchorPoint, anchor)
                XCTAssertFalse(overlay.isAnimating, "A status change must not pretend to be a new selection")
                let sceneImage = CityPinRaster.head(pin, night: night, reduceMotion: true)
                var native = pin.artwork; native.rendersStaticFrame = true
                let renderer = ImageRenderer(content: native.environment(\.colorScheme, night ? .dark : .light))
                let nativeImage = try XCTUnwrap(renderer.uiImage)
                for (name, image) in [("scene", sceneImage), ("native", nativeImage)] {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "visited-\(name)-\(contextID == "landmark-101" ? "photo" : "category")-\(night ? "night" : "day")"
                    attachment.lifetime = .keepAlways; add(attachment)
                }
                pin.visited = false
                overlay.update([pin], viewport: viewport, night: night, reduceMotion: false)
                XCTAssertTrue(head.texture === wantedTexture)
                XCTAssertEqual(head.xScale, 1.05, accuracy: 0.000001); XCTAssertEqual(head.position, position)
                XCTAssertFalse(overlay.isAnimating)
            }
        }
    }

    func testConfirmRetainsRegisteredCameraInsteadOfSharedImportFocusRegion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pin-confirm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vm = MapViewModel(mapCandidateUserIDProvider: { nil },
            pendingImportService: PendingPlaceImportService(overrideContainerURL: directory),
            saveLocalVaultService: SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json")),
            correctionEventStore: SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("corrections.json")),
            usesRemotePersistence: false)
        let source = try XCTUnwrap(CityMVPPlaceBridge.context.first { $0.id == CityMVPPlaceBridge.cityHallID })
        let candidate = CityMVPPlaceBridge.candidate(for: source)
        let nativeCenter = CLLocationCoordinate2D(latitude: 25.0345158, longitude: 121.5682904)
        let camera = MapCamera(centerCoordinate: nativeCenter, distance: 550, heading: 180, pitch: 49)
        vm.cameraPosition = .camera(camera)
        let saved = try await CityMVPPlaceBridge.confirm(candidate, in: vm, retaining: camera)
        let after = try XCTUnwrap(vm.cameraPosition.camera)
        XCTAssertEqual(after.centerCoordinate.latitude, nativeCenter.latitude)
        XCTAssertEqual(after.centerCoordinate.longitude, nativeCenter.longitude)
        XCTAssertEqual(after.distance, camera.distance)
        XCTAssertEqual(after.heading, camera.heading); XCTAssertEqual(after.pitch, camera.pitch)
        XCTAssertEqual(vm.selectedPlace?.id, saved.id)
        XCTAssertEqual(saved.sourceUrl, candidate.sourceURL)
        XCTAssertNotEqual(after.centerCoordinate.latitude, saved.latitude, "Source and native domains must remain distinct")
        XCTAssertEqual(try SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json")).confirmedPlaces().count, 1)
        // The shared duplicate path focuses the raw-source region before it
        // throws. Preserve the typed error and the registered camera together.
        do {
            try await CityMVPPlaceBridge.confirm(candidate, in: vm, retaining: camera)
            XCTFail("An existing exact stamp must retain the already-saved error")
        } catch let error as ReviewCandidateError {
            guard case .alreadySavedMapStamp = error else { return XCTFail("Unexpected review error: \(error)") }
        }
        let afterDuplicate = try XCTUnwrap(vm.cameraPosition.camera)
        XCTAssertEqual(afterDuplicate.centerCoordinate.latitude, nativeCenter.latitude)
        XCTAssertEqual(afterDuplicate.centerCoordinate.longitude, nativeCenter.longitude)
        XCTAssertEqual(afterDuplicate.distance, camera.distance)
        XCTAssertEqual(afterDuplicate.heading, camera.heading); XCTAssertEqual(afterDuplicate.pitch, camera.pitch)
        XCTAssertEqual(try SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json")).confirmedPlaces().count, 1)
    }

    func testFarSavedOwnershipIsNativeEvenWhenConversionIsUnavailable() throws {
        let saved = place(source: nil)
        let pins = CityMVPPlaceBridge.contextPins(in: [saved], registration: registration)
        let pin = try XCTUnwrap(pins.first { $0.id == "saved:\(saved.id.uuidString)" })
        let camera = MapCamera(centerCoordinate: saved.coordinate, distance: 12_000, heading: 0, pitch: 35)
        func frame(_ point: CGPoint?, style: CityDistrictMapStyle = .city) -> CityDistrictCamera {
            CityDistrictCamera(camera: camera, registration: registration, style: style,
                viewport: CGSize(width: 393, height: 852), contextPins: [pin], cloudHandoff: true) { _ in point }
        }
        let missing = frame(nil)
        XCTAssertNil(missing.projection)
        XCTAssertNil(missing.contextPlacement(for: pin))
        XCTAssertFalse(CityMVPPlaceBridge.projectsSavedPin(saved, in: missing, registration: registration), "Far pins use the native presentation clock regardless of conversion availability")
        XCTAssertTrue(missing.needsProjectionRefresh, "Browse-only gaps need the existing one-shot refresh too")
        let recovered = frame(CGPoint(x: 190, y: 340))
        XCTAssertEqual(recovered.contextPlacement(for: pin)?.point, CGPoint(x: 190, y: 340))
        XCTAssertFalse(recovered.needsProjectionRefresh)
        let offscreen = frame(CGPoint(x: -800, y: -800))
        XCTAssertNil(offscreen.contextPlacement(for: pin))
        XCTAssertFalse(offscreen.needsProjectionRefresh, "A finite offscreen point is not a conversion failure")
        XCTAssertFalse(CityMVPPlaceBridge.projectsSavedPin(saved, in: offscreen, registration: registration))
        let world = frame(nil, style: .globe)
        XCTAssertFalse(CityMVPPlaceBridge.projectsSavedPin(saved, in: world, registration: registration), "Globe keeps a single native saved owner")
        let vm = MapViewModel(usesRemotePersistence: false); vm.selectPlace(saved, enrichPhoto: false)
        let selected = try XCTUnwrap(CityMVPSelectedPin(viewModel: vm, registration: registration))
        XCTAssertTrue(selected.usesGeographicOverlay(style: .city, hasRegistration: true, geographicPinsEnabled: true))
        XCTAssertFalse(selected.usesGeographicOverlay(style: .globe, hasRegistration: true, geographicPinsEnabled: true))
        XCTAssertFalse(selected.usesGeographicOverlay(style: .city, hasRegistration: false, geographicPinsEnabled: true))
    }

    func testSelectedAndSavedOwnersSwitchOnlyAtTheModelDistanceBoundary() throws {
        let saved = place(source: nil)
        let vm = MapViewModel(usesRemotePersistence: false)
        vm.selectPlace(saved, enrichPhoto: false)
        let selected = try XCTUnwrap(CityMVPSelectedPin(viewModel: vm, registration: registration))
        let identity = selected.anchor.id
        for (distance, expectsOverlay) in [(8_999.999, true), (9_000.0, false), (9_000.001, false), (12_000.0, false)] {
            for point in [CGPoint?.none, CGPoint(x: 190, y: 340)] {
                let frame = CityDistrictCamera(camera: MapCamera(centerCoordinate: saved.coordinate,
                    distance: distance, heading: 20, pitch: 35), registration: registration,
                    viewport: CGSize(width: 393, height: 852), selectedPin: selected.anchor,
                    cloudHandoff: true) { _ in point }
                XCTAssertEqual(frame.usesGeographicPinOverlay, expectsOverlay)
                XCTAssertEqual(CityMVPPlaceBridge.projectsSavedPin(saved, in: frame, registration: registration), expectsOverlay)
                let overlaySelected = selected.usesGeographicOverlay(style: frame.style, hasRegistration: true,
                    geographicPinsEnabled: frame.usesGeographicPinOverlay)
                XCTAssertEqual(overlaySelected, expectsOverlay)
                XCTAssertEqual(selected.anchor.id, identity)
                if point == nil { XCTAssertNil(frame.projection) }
            }
        }
        let legacy = CityDistrictCamera(camera: MapCamera(centerCoordinate: saved.coordinate,
            distance: 12_000, heading: 20, pitch: 35), registration: registration,
            viewport: CGSize(width: 393, height: 852), cloudHandoff: false) { _ in nil }
        XCTAssertTrue(legacy.usesGeographicPinOverlay, "Historical comparison ownership is unchanged")
        XCTAssertEqual(selected.anchor.coordinate.latitude, saved.latitude)
        XCTAssertEqual(selected.anchor.coordinate.longitude, saved.longitude)
    }

    func testSourceIDsReleaseTheirCaptionWhenTheirPinLeavesTheFrame() {
        let overlay = CityScenePins()
        let viewport = CGSize(width: 393, height: 852)
        for id in ["way/142113976", "way/234589397", "node/123456", "saved:fixture"] {
            let pin = CityScenePin(id: id, contextID: id, title: "Fixture caption", symbol: "mappin",
                saved: true, selected: true, placement: .init(point: CGPoint(x: 190, y: 340), contactOpacity: 0),
                reveal: 1, photoDiameter: 42, titleOpacity: 1, titleAbove: false)
            for _ in 0..<3 {
                overlay.update([pin], viewport: viewport, night: false, reduceMotion: true)
                XCTAssertEqual(overlay.scene.children.filter { $0.name == "title-" + id }.count, 1)
                overlay.update([], viewport: viewport, night: false, reduceMotion: true)
                XCTAssertEqual(overlay.scene.children.filter { $0.name == id }.count, 0)
                XCTAssertEqual(overlay.scene.children.filter { $0.name == "title-" + id }.count, 0,
                    "A removed geographic pin must not leave a detached caption")
            }
        }
    }

    func testNativeSelectedPriorityIsScopedToItsAnnotationAndRestoresOnReuse() {
        let first = MKAnnotationView(annotation: nil, reuseIdentifier: "first")
        first.displayPriority = .defaultLow; first.zPriority = .min; first.selectedZPriority = .defaultUnselected
        let second = MKAnnotationView(annotation: nil, reuseIdentifier: "second")
        second.displayPriority = .defaultHigh; second.zPriority = .defaultUnselected; second.selectedZPriority = .min
        let host = CityNativePinPriorityHost(frame: .zero)
        first.addSubview(host)
        XCTAssertEqual(first.displayPriority, .required); XCTAssertEqual(first.zPriority, .max)
        XCTAssertEqual(first.selectedZPriority, .max)
        second.addSubview(host)
        XCTAssertEqual(first.displayPriority, .defaultLow); XCTAssertEqual(first.zPriority, .min)
        XCTAssertEqual(first.selectedZPriority, .defaultUnselected)
        XCTAssertEqual(second.displayPriority, .required); XCTAssertEqual(second.zPriority, .max)
        host.removeFromSuperview()
        XCTAssertEqual(second.displayPriority, .defaultHigh); XCTAssertEqual(second.zPriority, .defaultUnselected)
        XCTAssertEqual(second.selectedZPriority, .min)
        XCTAssertEqual(CityPinArtwork.nativeSelectedAnchor.y * CityPinArtwork.nativeSelectedHeight, CityPinArtwork.height, accuracy: 0.0001)
    }

    func testOverlappingNativePriorityHostsRestoreOnlyAfterLastOwnerReleases() {
        for oldOwnerFirst in [true, false] {
            let annotation = MKAnnotationView(annotation: nil, reuseIdentifier: nil)
            annotation.displayPriority = .defaultLow
            annotation.zPriority = .min
            annotation.selectedZPriority = .defaultUnselected
            let old = CityNativePinPriorityHost(frame: .zero)
            let replacement = CityNativePinPriorityHost(frame: .zero)
            annotation.addSubview(old); annotation.addSubview(replacement)
            (oldOwnerFirst ? old : replacement).removeFromSuperview()
            XCTAssertEqual(annotation.displayPriority, .required)
            XCTAssertEqual(annotation.zPriority, .max)
            XCTAssertEqual(annotation.selectedZPriority, .max)
            (oldOwnerFirst ? replacement : old).removeFromSuperview()
            XCTAssertEqual(annotation.displayPriority, .defaultLow)
            XCTAssertEqual(annotation.zPriority, .min)
            XCTAssertEqual(annotation.selectedZPriority, .defaultUnselected)
        }
    }

    private func place(source: String?) -> Place {
        Place(id: UUID(), name: "Fixture café", address: "Taipei", latitude: 25.034, longitude: 121.564,
              category: .cafe, status: .wantToGo, rating: nil, note: nil, sourceUrl: source, sourcePlatform: .other,
              createdAt: Date())
    }
}
