#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import SwiftUI
import MapKit
import UIKit
import XCTest
@testable import SAVE

/// Simulator-hosted component evidence, not a full-app UI or account integration test.
@MainActor
final class LivePlanningSurfaceTests: XCTestCase {
    func testPublicDiscoverySummaryAndDetailLightAndDark() async throws {
        let now = Date()
        let raw = try LivePublicDiscoveryModelTests.page(now: now)
        let page = try raw.validated(at: now)
        let model = LivePublicDiscoveryModel(backend: DiscoveryComponentBackend(page: raw),
                                            sessionIsCurrent: { true }, now: { now })
        await model.refresh(try LivePublicDiscoveryModelTests.viewport())
        XCTAssertEqual(model.page?.venues.count, 1)
        try await recordComponent("public-discovery-summary") {
            VStack { Spacer(); LivePublicDiscoverySummary(model: model,
                onRetry: { XCTFail("Rendering must not reload") },
                onMore: { XCTFail("Rendering must not paginate") }).demoCard() }
        }
        let venue = try XCTUnwrap(page.venues.first)
        try await recordComponent("public-discovery-detail") {
            LivePublicDiscoveryDetail(venue: venue, ownerSubject: "component-fixture", sessionGeneration: 0,
                alreadySaved: false, isSaving: false, saveError: nil,
                onSave: { XCTFail("Rendering must not save") },
                onDirections: { XCTFail("Rendering must not navigate") },
                onClose: { XCTFail("Rendering must not dismiss") })
        }
        model.clear()
    }

    func testGuideReadyAndProgressComponentsLightAndDark() async throws {
        let model = LiveRoutePlan(ownerSubject: "component-fixture", sessionGeneration: 0,
                                  makeDirections: { _ in GuideComponentDirections() }, sessionIsCurrent: { true })
        let stops = try fixtures.prefix(2).map { try XCTUnwrap(LiveMapPlace.saved($0)) }
        model.beginsAt = Date(timeIntervalSince1970: 1_800_000_000)
        await model.build(stops, listID: UUID())
        XCTAssertTrue(model.isAccessValidated)
        try await recordComponent("guide-ready") {
            LiveGuidePanel(title: "週六下午", plan: model,
                           onManage: { XCTFail("Rendering must not open team settings") },
                           onSelect: { _ in XCTFail("Rendering must not open stop") })
                .frame(height: 485).demoCard()
        }
        model.start(); model.advance()
        try await recordComponent("guide-progress") {
            LiveGuidePanel(title: "週六下午", plan: model,
                           onManage: { XCTFail("Rendering must not open team settings") },
                           onSelect: { _ in XCTFail("Rendering must not open stop") })
                .frame(height: 485).demoCard()
        }
        XCTAssertEqual(model.currentIndex, 1)
    }

    func testLibraryComponentLightAndDark() async throws {
        try await recordComponent("library") {
            LivePlanningLibraryView(places: fixtures, isLoading: false,
                                    onOpen: { _ in XCTFail("Rendering must not open a place") },
                                    onCapture: { XCTFail("Rendering must not start capture") })
        }
    }

    func testPassportComponentLightAndDark() async throws {
        try await recordComponent("passport") {
            LivePlanningPassportView(places: fixtures,
                                     onOpenLibrary: { XCTFail("Rendering must not navigate") },
                                     onOpenAccount: { XCTFail("Rendering must not open account settings") })
        }
    }

    func testPlaceDetailComponentLightAndDark() async throws {
        var place = fixtures[0]
        place.note = "手寫筆記：想坐窗邊，先散步再來喝咖啡。\n這段原文必須保留。\n和朋友確認集合時間。\n備案留到下雨時使用。\n下一行應該可展開閱讀。"
        place.sourceUrl = "https://example.invalid/posts/saved-place"
        let pin = try XCTUnwrap(LiveMapPlace.saved(place))
        try await recordComponent("place-detail") {
            LivePlaceDetail(pin: pin, isSaving: false, saveError: nil,
                onSave: nil, onOpenSaved: { XCTFail("Render must not open saved editor") },
                onDirections: { XCTFail("Render must not start navigation") },
                onAddToOuting: nil, canAddToOuting: false,
                onClose: { XCTFail("Render must not close detail") })
        }
    }

    func testSourceLinkDoesNotPromotePrivateNoteURLs() throws {
        var place = fixtures[0]
        place.note = "Private note https://example.invalid/personal"
        let pin = try XCTUnwrap(LiveMapPlace.saved(place))
        XCTAssertNil(LivePlaceSourceLink.url(for: pin))
        XCTAssertEqual(pin.place.note, place.note)
    }

    func testSourceLinksAcceptExplicitWebSourcesAndRejectCredentialsOrSchemes() throws {
        var place = fixtures[0]
        for value in ["javascript:alert(1)", "file:///private/note", "https://user:pass@example.invalid/source"] {
            place.sourceUrl = value
            XCTAssertNil(LivePlaceSourceLink.url(for: try XCTUnwrap(LiveMapPlace.saved(place))))
        }
        place.sourceUrl = " https://example.invalid/posts/saved-place "
        XCTAssertEqual(LivePlaceSourceLink.url(for: try XCTUnwrap(LiveMapPlace.saved(place)))?.host, "example.invalid")
    }

    func testFriendsMapComponentLightAndDark() async throws {
        let json = #"""
        [{"id":"11111111-1111-4111-8111-111111111111","name":"測試咖啡店","address":"測試街1號","latitude":25.03,"longitude":121.54,"coordinate_system":"WGS84","location_provider":"apple_maps","category":"cafe","status":"visited","stars":null,"caption":null,"shared_at":"2026-11-14T10:00:00Z","author_id":"fixture-a","author_name":"名字非常長的測試朋友小安","author_handle":null,"author_avatar_url":null,"visible_to_followers":true},
         {"id":"22222222-2222-4222-8222-222222222222","name":"測試咖啡店","address":"測試街1號","latitude":25.03,"longitude":121.54,"coordinate_system":"WGS84","location_provider":"apple_maps","category":"cafe","status":"wantToGo","stars":null,"caption":null,"shared_at":"2026-11-14T10:00:00Z","author_id":"fixture-b","author_name":"小明","author_handle":null,"author_avatar_url":null,"visible_to_followers":true}]
        """#
        let posts = try JSONDecoder().decode([SharedPlacePost].self, from: Data(json.utf8))
        let friends = LiveFriendMapPlace.projections(posts: posts)
        let pins = LiveFriendMapPlace.groupedByVenue(friends).compactMap { $0.first?.pin }
        XCTAssertEqual(pins.count, 1)
        XCTAssertEqual(friends.count, 2)
        try await recordComponent("friends-map") {
            LiveInteractiveMapSurface(
                position: .constant(.region(MKCoordinateRegion(center: .init(latitude: 25.03, longitude: 121.54),
                    span: .init(latitudeDelta: 0.008, longitudeDelta: 0.008)))),
                pins: pins, routes: [], activePinID: nil, friends: friends,
                ownerSubject: "component-fixture", sessionGeneration: 0,
                onSelect: { _ in XCTFail("Rendering must not select a friend venue") },
                onCameraSettled: { _, _ in })
        }
    }

    private func recordComponent<Content: View>(
        _ name: String, @ViewBuilder content: () -> Content
    ) async throws {
#if targetEnvironment(simulator)
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive },
            "Component proof requires the simulator test host's foreground UIWindowScene"
        )
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("live-planning-ui-proof", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Read-only, isolated defaults: no standard preference is read or changed. A fresh
        // suite has no app language value, so the injected supported language determines it.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "live-planning-proof.\(UUID().uuidString)"))
        let language = AppLanguageSettings(userDefaults: defaults, preferredLanguages: { ["zh-Hant"] })
        XCTAssertEqual(language.language, .traditionalChinese)
        let size = CGSize(width: 393, height: 852)

        for (label, scheme, style) in [
            ("light", ColorScheme.light, UIUserInterfaceStyle.light),
            ("dark", ColorScheme.dark, UIUserInterfaceStyle.dark)
        ] {
            let root = ZStack {
                DateTheme.canvas.ignoresSafeArea()
                content().padding(16)
            }
            .frame(width: size.width, height: size.height)
            .environment(\.appLanguageSettings, language)
            .environment(\.locale, Locale(identifier: "zh-Hant"))
            .environment(\.dynamicTypeSize, .large)
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(scheme)
            let host = UIHostingController(rootView: root)
            host.overrideUserInterfaceStyle = style
            host.safeAreaRegions = []
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.overrideUserInterfaceStyle = style
            window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.backgroundColor = UIColor(DateTheme.canvas)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            // Yield to UIKit/SwiftUI so TextField and the lazy collection actually mount.
            try await Task.sleep(nanoseconds: ["place-detail", "friends-map"].contains(name) ? 1_000_000_000 : 150_000_000)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            XCTAssertTrue(host.view.window === window)
            XCTAssertEqual(host.view.bounds.size, size)
            XCTAssertEqual(host.traitCollection.userInterfaceStyle, style)

            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            format.opaque = true
            format.preferredRange = .standard
            var complete = false
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor(DateTheme.canvas).resolvedColor(with: host.traitCollection).setFill()
                context.cgContext.fill(CGRect(origin: .zero, size: size))
                complete = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            XCTAssertTrue(complete, "UIKit reported an incomplete \(name)/\(label) hierarchy draw")
            try assertVisibleRender(image)
            let png = try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(png.count, 1_024, "A valid component capture must contain image content")
            let filename = "component-only-\(name)-\(label)-393x852pt-2x.png"
            try png.write(to: directory.appendingPathComponent(filename), options: .atomic)
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = filename
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let receipt = XCTAttachment(string: "Component-only proof; real views, synthetic URL-free Places; "
            + "UIKit drawHierarchy; 393x852 points at 2x; Dynamic Type large; zh-Hant; "
            + "light and dark. Not full-app UI, live data, interaction or account proof. Output: \(directory.path)")
        receipt.name = "component-only-\(name)-receipt"
        receipt.lifetime = .keepAlways
        add(receipt)
        print("LIVE_PLANNING_COMPONENT_PROOF \(directory.path)")
#else
        throw XCTSkip("Component render proof runs only in the simulator test host; no device windows")
#endif
    }

    private func assertVisibleRender(_ image: UIImage) throws {
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cgImage.width, 786)
        XCTAssertEqual(cgImage.height, 1_704)
        // A broad content check, not a visual baseline: reject uniform/empty canvases.
        let width = 64, height = 128
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        XCTAssertTrue(rendered)
        var darkest = 255, lightest = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let brightness = (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
            darkest = min(darkest, brightness)
            lightest = max(lightest, brightness)
        }
        XCTAssertGreaterThan(lightest - darkest, 32, "Capture must contain visible foreground content")
    }

    private var fixtures: [Place] {
        let names = ["測試咖啡店", "測試公園", "測試餐廳", "測試書店"]
        let categories: [PlaceCategory] = [.cafe, .attraction, .food, .shopping]
        return names.indices.map { index in
            Place(id: UUID(uuidString: "00000000-0000-4000-8000-00000000000\(index + 1)")!,
                  name: names[index], address: "測試街 \(index + 1) 號",
                  latitude: 25.03 + Double(index) * 0.001, longitude: 121.54,
                  googlePlaceId: nil, category: categories[index],
                  status: index.isMultiple(of: 2) ? .wantToGo : .visited,
                  rating: nil, note: nil, sourceUrl: nil, sourcePlatform: .other,
                  coordinateSystem: .wgs84, sourceImageUrl: nil, extractedDishes: nil,
                  priceRange: nil, recommender: nil, googleRating: nil,
                  googlePriceLevel: nil, openingHours: nil,
                  createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        }
    }
}

@MainActor
private final class GuideComponentDirections: LiveWalkingDirections {
    func route() async throws -> MKRoute { MKRoute() }
    func cancel() {}
}

@MainActor
private struct DiscoveryComponentBackend: LivePublicDiscoveryBackend {
    let page: LivePublicDiscoveryPage
    func fetchPublicDiscovery(viewport: LivePublicDiscoveryViewport, cursor: String?) async throws -> LivePublicDiscoveryPage { page }
}
#endif
