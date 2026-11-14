#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import MapKit
import SwiftUI
import UIKit
import XCTest
@testable import SAVE

/// Explicit public-place read-only probe; never runs against an account or during ordinary units.
@MainActor
final class LivePlaceNativeProbeTests: XCTestCase {
    func testLiveAppleVenueAndWebsiteImageReadOnlyProbe() async throws {
        guard ProcessInfo.processInfo.environment["SAVE_LIVE_APPLE_PLACE_PROBE"] == "1" else {
            throw XCTSkip("Opt-in public Apple place-card probe; no network in the ordinary unit suite")
        }
        guard #available(iOS 18.0, *) else { throw XCTSkip("Native place cards need iOS18") }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "Apple 台北101"
        let center = CLLocationCoordinate2D(latitude: 25.03396, longitude: 121.56447)
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 800, longitudinalMeters: 800)
        request.resultTypes = .pointOfInterest
        let search = MKLocalSearch(request: request)
        defer { search.cancel() }
        let result = try await search.start()
        let item = try XCTUnwrap(result.mapItems.first {
            ($0.name ?? "").lowercased().contains("apple") && ($0.name ?? "").contains("101") && CLLocation(latitude: center.latitude, longitude: center.longitude)
                .distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude,
                                          longitude: $0.placemark.coordinate.longitude)) < 300
        }, "The live probe needs an actual Apple result for the public Apple Taipei101 store")
        let pin = try XCTUnwrap(LiveMapPlace.search(item))
        let model = LivePlaceInformationModel(reader: NoLookupReader(), sessionIsCurrent: { _, _ in true })
        let photo = LiveBusinessWebsitePhotoModel(sessionIsCurrent: { _, _ in true })
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "native-place-proof.\(UUID())"))
        let language = AppLanguageSettings(userDefaults: defaults, preferredLanguages: { ["zh-Hant"] })
        let root = LivePlaceDetail(pin: pin, isSaving: false, saveError: nil,
            ownerSubject: "public-probe", sessionGeneration: 0, informationModel: model, websitePhotoModel: photo,
            onSave: { XCTFail("Probe must never save") }, onOpenSaved: nil,
            onDirections: { XCTFail("Probe must not start navigation") },
            onAddToOuting: nil, canAddToOuting: false, onClose: {})
            .environment(\.appLanguageSettings, language)
            .environment(\.dynamicTypeSize, .large)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let host = UIHostingController(rootView: root)
        host.safeAreaRegions = []
        let size = CGSize(width: 393, height: 852)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        window.rootViewController = host
        window.isHidden = false
        defer { model.cancel(); photo.cancel(); window.isHidden = true; window.rootViewController = nil }
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        // Allow the system's own card to retrieve its public-place imagery and metadata.
        try await Task.sleep(nanoseconds: 12_000_000_000)
        XCTAssertTrue(model.item === item)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error)
        XCTAssertFalse(photo.isLoading)
        let receipt = XCTAttachment(string: "Public Apple venue only; website=\(item.url?.absoluteString ?? "none"); imageLoaded=\(photo.image != nil)")
        receipt.name = "public-business-photo-availability"
        receipt.lifetime = .keepAlways
        add(receipt)
        print("LIVE_BUSINESS_PHOTO_AVAILABILITY website=\(item.url?.absoluteString ?? "none") imageLoaded=\(photo.image != nil)")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let data = try XCTUnwrap(image.pngData())
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("native-apple-place-card-public-probe.png")
        try data.write(to: file, options: .atomic)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "native-apple-place-card-public-probe"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("LIVE_NATIVE_PLACE_PROOF \(file.path)")
    }

    private final class NoLookupReader: LivePlaceInformationReading {
        func appleItem(identifier: String) async throws -> MKMapItem? { XCTFail("Provided item must be reused"); return nil }
        func search(name: String, address: String, coordinate: CLLocationCoordinate2D) async throws -> [MKMapItem] {
            XCTFail("Provided item must be reused"); return []
        }
        func cancel() {}
    }
}
#endif
