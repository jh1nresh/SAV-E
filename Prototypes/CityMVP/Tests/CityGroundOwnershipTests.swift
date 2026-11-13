import XCTest
import UIKit
import SceneKit
import Metal
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

/// Draft-only raster/coordinate checks. These do not prove MapKit label
/// occlusion, ground material compositing, or live visual acceptance.
@MainActor
final class CityGroundOwnershipTests: XCTestCase {
    func testOwnedCoreGroundDoesNotRevealBlackOrWhiteBackgroundThroughItsMaterial() throws {
        let (elements, coverage) = try fixture()
        let bitmap = try XCTUnwrap(CityStreetSurface.rasterizeDistrictGround(
            CityStreetSurface.districtGround(elements: elements, coverage: coverage)))
        // Retain the real scene's lights while isolating its actual ground
        // material. This is not a MapKit layer-ordering test.
        let scene = CitySceneGeometry.makeScene()
        for node in scene.rootNode.childNodes where node.light == nil { node.removeFromParentNode() }
        CityStreetSurface.addDistrictGround(bitmap, to: scene.rootNode)
        scene.fogStartDistance = 10_000; scene.fogEndDistance = 20_000
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 8
        camera.camera?.zFar = 2_000
        camera.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        var time = 0.0, records: [[String: Any]] = []
        for night in [false, true] {
            CitySceneGeometry.applyLighting(to: scene, night: night, animated: false)
            for (name, point, owned) in [("city-hall", CGPoint(x: 0, y: -240), true),
                                          ("101-core", CGPoint(x: 40, y: 85), true),
                                          ("unknown", CGPoint(x: 500, y: -620), false)] {
                camera.position = SCNVector3(Float(point.x), 1_000, Float(point.y))
                var samples: [[Int]] = []
                for (label, background) in [("black", UIColor.black), ("white", UIColor.white)] {
                    scene.background.contents = background; time += 1.0 / 30.0
                    let image = renderer.snapshot(atTime: time, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
                    let cg = try XCTUnwrap(image.cgImage)
                    samples.append(try rgba(cg, at: .init(x: 32, y: 32), extent: .init(x: 0, y: 0, width: 64, height: 64)))
                    let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
                    attachment.name = "ground-material-\(name)-\(night ? "night" : "day")-\(label)"
                    attachment.lifetime = .keepAlways; add(attachment)
                }
                let difference = zip(samples[0].prefix(3), samples[1].prefix(3)).map { abs($0 - $1) }.max() ?? 0
                if owned {
                    XCTAssertLessThanOrEqual(difference, 2, "Opaque core material must not reveal the changed background")
                    XCTAssertGreaterThan(samples[0].prefix(3).reduce(0, +), 30)
                } else {
                    XCTAssertGreaterThan(difference, 200, "The clear control must expose both backgrounds")
                }
                records.append(["name": name, "night": night, "owned": owned,
                                "black": samples[0], "white": samples[1], "difference": difference])
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ground-material-compositor-results"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func fixture() throws -> (elements: [[String: Any]], coverage: CityStreetSurface.GroundCoverage) {
        let elements = try XCTUnwrap(CitySceneData.elements, "Bundled public OSM fixture is required")
        let ring = try XCTUnwrap(elements.first { $0["id"] as? Int == 373794831 })
        let geometry = try XCTUnwrap(ring["geometry"] as? [[String: Double]])
        XCTAssertEqual(geometry.first?["lat"], geometry.last?["lat"])
        XCTAssertEqual(geometry.first?["lon"], geometry.last?["lon"])
        let coverage = try XCTUnwrap(CityStreetSurface.rasterizeGroundCoverage(
            CityStreetSurface.groundOwnership(elements: elements)))
        return (elements, coverage)
    }

    func testLoadedPublicCoreIsOpaqueAndUnknownLandIsClear() throws {
        let (elements, coverage) = try fixture()
        let ground = try XCTUnwrap(CityStreetSurface.rasterizeDistrictGround(
            CityStreetSurface.districtGround(elements: elements, coverage: coverage)))
        let extent = CGRect(x: -700, y: -700, width: 1400, height: 1400)
        // City Hall south forecourt is inside loaded closed sidewalk 373794831.
        // Its north courtyard was formerly cut by the global -568/-518 stripe.
        for p in [CGPoint(x: 0, y: -240), CGPoint(x: 0, y: -548),
                  CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 85)] {
            XCTAssertEqual(try rgba(ground, at: p, extent: extent)[3], 255, "Known core \(p)")
        }
        // Public fixture inspection: neither point lies in any loaded building,
        // public-space polygon or road corridor, well outside the 4 m feather.
        for p in [CGPoint(x: 650, y: -620), CGPoint(x: 500, y: -620)] {
            XCTAssertEqual(try rgba(ground, at: p, extent: extent)[3], 0, "Unknown land \(p)")
        }
    }

    func testEveryAtlasSamplesSameWorldCoverageIncludingShadowPixelTransform() throws {
        let (_, coverage) = try fixture()
        let configurations: [(CGRect, CGFloat, Bool)] = [
            (CGRect(x: -700, y: -700, width: 1400, height: 1400), 1, false),
            (CityStreetSurface.bounds, 2, false), // roads and civic paving
            (CGRect(x: -550, y: -695, width: 1100, height: 1050), 2, true),
        ]
        for (extent, scale, shadowConvention) in configurations {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
            let image = UIGraphicsImageRenderer(size: CGSize(width: extent.width * scale,
                                                              height: extent.height * scale), format: format).image { output in
                let g = output.cgContext
                UIColor.white.setFill(); g.fill(CGRect(x: 0, y: 0, width: extent.width * scale, height: extent.height * scale))
                // Shadow marks are already in pixels; the mask alone changes CTM.
                // Other atlases establish this same CTM before drawing their marks.
                if shadowConvention { g.saveGState() }
                g.scaleBy(x: scale, y: scale)
                g.translateBy(x: -extent.minX, y: -extent.minY)
                CityStreetSurface.applyGroundCoverage(coverage, to: g)
                if shadowConvention { g.restoreGState() }
            }.cgImage!
            for (point, alpha) in [(CGPoint(x: 0, y: -240), 255),
                                   (CGPoint(x: 0, y: -548), 255),
                                   (CGPoint(x: 500, y: -620), 0)] {
                XCTAssertEqual(try rgba(image, at: point, extent: extent)[3], alpha)
            }
        }
    }

    func testUnionHasNoOverlapSeamAndFeatherDoesNotFillUnknownLots() throws {
        // An asymmetric shape catches vertical image inversion; opposing winding
        // catches accidental even-odd or nonzero-winding holes in overlapping areas.
        let a: [CGPoint] = [.init(x: 10, y: -130), .init(x: 30, y: -130),
                            .init(x: 30, y: -110), .init(x: 10, y: -110)]
        let b = Array([CGPoint(x: 20, y: -125), CGPoint(x: 40, y: -125),
                       CGPoint(x: 40, y: -105), CGPoint(x: 20, y: -105)].reversed())
        let coverage = try XCTUnwrap(CityStreetSurface.rasterizeGroundCoverage(
            .init(polygons: [a, b], corridors: [])))
        XCTAssertEqual(try rgba(coverage.image, at: .init(x: 25, y: -120), extent: coverage.extent)[3], 255)
        XCTAssertEqual(try rgba(coverage.image, at: .init(x: 15, y: 120), extent: coverage.extent)[3], 0)
        let feather = try rgba(coverage.image, at: .init(x: 8, y: -120), extent: coverage.extent)[3]
        XCTAssertGreaterThan(feather, 0); XCTAssertLessThan(feather, 255)
        XCTAssertEqual(try rgba(coverage.image, at: .init(x: 4, y: -120), extent: coverage.extent)[3], 0)
    }

    func testInnerRoadAndForecourtPixelsRetainTheirExistingDetails() throws {
        let (elements, coverage) = try fixture()
        let roads = CityStreetSurface.roads()
        let crossings = CityStreetSurface.crossingRoads(roads: roads, elements: elements)
        let original = try XCTUnwrap(CityStreetSurface.rasterizeRoadTexture(
            roads: roads, crossings: crossings, cycleway: CityStreetSurface.cyclewayPath))
        let candidate = try XCTUnwrap(CityStreetSurface.rasterizeRoadTexture(
            roads: roads, crossings: crossings, cycleway: CityStreetSurface.cyclewayPath, coverage: coverage))
        // Xinyi carriageways use the same OSM paths as traffic/markings.
        for p in [CGPoint(x: -100, y: 104), CGPoint(x: 96, y: 128)] {
            XCTAssertEqual(try rgba(original.surface, at: p, extent: CityStreetSurface.bounds),
                           try rgba(candidate.surface, at: p, extent: CityStreetSurface.bounds))
        }
        let oldPaving = try XCTUnwrap(CityCivicLandscape.rasterizePublicPaving(
            CityCivicLandscape.publicPaving(elements: elements)))
        let newPaving = try XCTUnwrap(CityCivicLandscape.rasterizePublicPaving(
            CityCivicLandscape.publicPaving(elements: elements, coverage: coverage)))
        XCTAssertEqual(try rgba(oldPaving, at: .init(x: 40, y: 85), extent: CityStreetSurface.bounds),
                       try rgba(newPaving, at: .init(x: 40, y: 85), extent: CityStreetSurface.bounds))
    }

    private func rgba(_ image: CGImage, at point: CGPoint, extent: CGRect) throws -> [Int] {
        let x = Int((point.x - extent.minX) / extent.width * CGFloat(image.width))
        let y = Int((point.y - extent.minY) / extent.height * CGFloat(image.height))
        XCTAssertTrue((0..<image.width).contains(x) && (0..<image.height).contains(y))
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        let valid = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let g = CGContext(data: storage.baseAddress, width: 1, height: 1,
                                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            g.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1)); return true
        }
        XCTAssertTrue(valid)
        return bytes.map(Int.init)
    }
}
