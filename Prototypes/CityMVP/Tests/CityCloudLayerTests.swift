import XCTest
import SceneKit
import SpriteKit
import Metal
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityCloudLayerTests: XCTestCase {
    func testCloudsRemainBehindActualSelectedPhotoInTheSceneRenderPass() throws {
        let pins = CityScenePins()
        let pin = CityScenePin(id: "cloud-photo", contextID: "landmark-101", title: "Taipei 101", symbol: "photo",
                               saved: false, selected: true,
                               placement: .init(point: .init(x: 128, y: 170), contactOpacity: 1),
                               reveal: 1, photoDiameter: 58, titleOpacity: 1, titleAbove: false)
        let renderer = try renderer(overlay: pins.scene)
        let clouds = CitySceneClouds(camera: try XCTUnwrap(renderer.pointOfView))
        for night in [false, true] {
            pins.update([pin], viewport: size, night: night, reduceMotion: true)
            clouds.update([], opacity: 0, viewport: size, night: night)
            renderer.technique = nil
            let original = try capture(renderer, name: "photo-no-cloud-\(night)")
            renderer.technique = try XCTUnwrap(CitySceneComposite.makeTechnique())
            let corrected = try capture(renderer, name: "photo-corrected-no-cloud-\(night)")
            for y in stride(from: 64, through: 208, by: 4) {
                for x in stride(from: 64, through: 192, by: 4) {
                    let a = try pixel(original, x: x, y: y), b = try pixel(corrected, x: x, y: y)
                    XCTAssertLessThanOrEqual(zip(a, b).map { abs($0 - $1) }.max() ?? 255, 2,
                                             "The composition pass must preserve photo/caption interiors, edges and shadows")
                }
            }
            clouds.update([patch(center: .init(x: 128, y: 128), radius: 80)], opacity: 1, viewport: size, night: night)
            let covered = try capture(renderer, name: "photo-above-cloud-\(night)")
            for x in stride(from: 120, through: 136, by: 4) {
                for y in stride(from: 120, through: 136, by: 4) {
                    let a = try pixel(original, x: x, y: y), b = try pixel(covered, x: x, y: y)
                    XCTAssertLessThanOrEqual(zip(a, b).map { abs($0 - $1) }.max() ?? 255, 2,
                                             "An opaque cloud must not wash out the selected photo")
                }
            }
            let a = try pixel(original, x: 80, y: 128), b = try pixel(covered, x: 80, y: 128)
            XCTAssertGreaterThan(zip(a, b).map { abs($0 - $1) }.max() ?? 0, 30,
                                 "Clouds must actually change the surrounding background")
        }
    }

    func testRenderedCloudFollowsTheNativeTranslationAndRotation() throws {
        let overlay = SKScene(size: size)
        overlay.backgroundColor = .clear
        let renderer = try renderer(overlay: overlay)
        renderer.technique = try XCTUnwrap(CitySceneComposite.makeTechnique())
        let clouds = CitySceneClouds(camera: try XCTUnwrap(renderer.pointOfView))
        clouds.update([patch(center: .init(x: 96, y: 96), radius: 40)], opacity: 1, viewport: size, night: false)
        let base = try capture(renderer, name: "cloud-registered")
        clouds.update([patch(center: .init(x: 136, y: 116), radius: 40)], opacity: 1, viewport: size, night: false)
        let moved = try capture(renderer, name: "cloud-translated")
        let rotatedPatch = CityDistrictCamera.CloudPatch(center: .init(x: 160, y: 96),
                                                        east: .init(dx: 0, dy: 40), south: .init(dx: -40, dy: 0),
                                                        mirrorsContour: false)
        clouds.update([rotatedPatch], opacity: 1, viewport: size, night: false)
        let rotated = try capture(renderer, name: "cloud-rotated")
        for (x, y) in [(80, 80), (96, 96), (110, 96), (96, 110)] {
            let reference = try pixel(base, x: x, y: y)
            let translated = try pixel(moved, x: x + 40, y: y + 20)
            let turned = try pixel(rotated, x: 255 - y, y: x)
            XCTAssertLessThanOrEqual(zip(reference, translated).map { abs($0 - $1) }.max() ?? 255, 4)
            XCTAssertLessThanOrEqual(zip(reference, turned).map { abs($0 - $1) }.max() ?? 255, 4)
        }
    }

    func testTransparentCloudPassMatchesNativeCompositing() throws {
        let overlay = SKScene(size: size)
        overlay.backgroundColor = .clear
        let renderer = try renderer(overlay: overlay)
        let clouds = CitySceneClouds(camera: try XCTUnwrap(renderer.pointOfView))
        renderer.scene?.background.contents = UIColor.clear
        renderer.technique = try XCTUnwrap(CitySceneComposite.makeTechnique())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.preferredRange = .standard
        let backgrounds = [UIColor(red: 0.32, green: 0.58, blue: 0.22, alpha: 1),
                           UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)]
        var metrics: [[String: Any]] = []
        for night in [false, true] {
            for opacity in [0.15, 0.53, 0.98] {
                clouds.update([patch(center: .init(x: 128, y: 128), radius: 80)], opacity: opacity,
                              viewport: size, night: night)
                let tag = "\(night)-\(opacity)"
                let transparent = try capture(renderer, name: "transparent-cloud-\(tag)")
                XCTAssertLessThanOrEqual(try pixel(transparent, x: 20, y: 20)[3], 1,
                                         "The diagnostic must preserve clear pixels before comparing compositing")
                for (index, background) in backgrounds.enumerated() {
                    func composite(_ image: UIImage, alpha: Double) -> UIImage {
                        UIGraphicsImageRenderer(size: size, format: format).image { output in
                            background.setFill(); output.fill(CGRect(origin: .zero, size: size))
                            image.draw(at: .zero, blendMode: .normal, alpha: alpha)
                        }
                    }
                    let actual = composite(UIImage(cgImage: transparent), alpha: 1)
                    let expected = composite(CitySceneClouds.image(night: night, mirrored: false), alpha: opacity)
                    for (name, image) in [("scene-composited", actual), ("native-composited", expected)] {
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "\(name)-\(tag)-\(index)"; attachment.lifetime = .keepAlways; add(attachment)
                    }
                    let a = try XCTUnwrap(actual.cgImage), b = try XCTUnwrap(expected.cgImage)
                    for (x, y) in [(20, 20), (80, 96), (128, 128), (160, 128), (180, 160)] {
                        let observed = try pixel(a, x: x, y: y), reference = try pixel(b, x: x, y: y)
                        let difference = zip(observed, reference).map { abs($0 - $1) }.max() ?? 255
                        metrics.append(["night": night, "opacity": opacity, "background": index,
                                        "x": x, "y": y, "actual": observed, "expected": reference,
                                        "raw": try pixel(transparent, x: x, y: y), "difference": difference,
                                        "rendererFormat": renderer.colorPixelFormat.rawValue,
                                        "alphaInfo": transparent.alphaInfo.rawValue,
                                        "colorSpace": transparent.colorSpace?.name as String? ?? "unknown"])
                        XCTAssertLessThanOrEqual(difference, 8,
                                                "The transparent scene must not wash out the underlying map")
                    }
                }
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "transparent-composite-metrics"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testDisplayAlphaPassPreservesOpaqueGeometryColorAndDepth() throws {
        let renderer = try renderer(overlay: SKScene(size: size))
        let scene = try XCTUnwrap(renderer.scene)
        scene.background.contents = UIColor.green
        // Draw the front first so painter order cannot substitute for depth.
        for (width, z, color) in [(0.8, 1.0, UIColor.blue), (2.0, 0.0, UIColor.red)] {
            let plane = SCNPlane(width: width, height: width)
            let material = SCNMaterial(); material.lightingModel = .constant
            material.diffuse.contents = color; plane.materials = [material]
            let node = SCNNode(geometry: plane); node.position.z = Float(z)
            scene.rootNode.addChildNode(node)
        }
        let original = try capture(renderer, name: "opaque-depth-original")
        renderer.technique = try XCTUnwrap(CitySceneComposite.makeTechnique())
        let corrected = try capture(renderer, name: "opaque-depth-corrected")
        let front = try pixel(corrected, x: 128, y: 128)
        XCTAssertGreaterThan(front[2], 240, "The blue front surface must occlude the red rear surface")
        let rear = try pixel(corrected, x: 90, y: 128)
        XCTAssertGreaterThan(rear[0], 240, "The exposed red rear surface must actually be rendered")
        for y in stride(from: 80, through: 176, by: 2) {
            for x in stride(from: 80, through: 176, by: 2) {
                let a = try pixel(original, x: x, y: y), b = try pixel(corrected, x: x, y: y)
                XCTAssertLessThanOrEqual(zip(a, b).map { abs($0 - $1) }.max() ?? 255, 2)
            }
        }
    }

    func testFarWorldCameraKeepsCloudsVisibleAndRegistered() throws {
        let renderer = try renderer(overlay: SKScene(size: size))
        renderer.scene?.background.contents = UIColor.clear
        renderer.technique = try XCTUnwrap(CitySceneComposite.makeTechnique())
        let camera = try XCTUnwrap(renderer.pointOfView)
        let clouds = CitySceneClouds(camera: camera)
        var matrix = try XCTUnwrap(camera.camera).projectionTransform
        matrix.m11 = 7.5; matrix.m22 = 3.46
        camera.camera?.projectionTransform = matrix
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.preferredRange = .standard
        let background = UIColor(red: 0.19, green: 0.25, blue: 0.33, alpha: 1)
        for (index, position) in [SIMD3<Float>(-1584, 6553, 4136), SIMD3<Float>(2500, 6500, 6000),
                                  SIMD3<Float>(-3000, 5000, 7000)].enumerated() {
            camera.simdPosition = position
            camera.simdLook(at: SIMD3<Float>(-15, 0, -175))
            for night in [false, true] {
                clouds.update([patch(center: .init(x: 128, y: 128), radius: 80)], opacity: 0.98,
                              viewport: size, night: night)
                let raw = try capture(renderer, name: "far-camera-\(index)-\(night)")
                let actual = UIGraphicsImageRenderer(size: size, format: format).image { output in
                    background.setFill(); output.fill(CGRect(origin: .zero, size: size))
                    UIImage(cgImage: raw).draw(at: .zero)
                }
                let expected = UIGraphicsImageRenderer(size: size, format: format).image { output in
                    background.setFill(); output.fill(CGRect(origin: .zero, size: size))
                    CitySceneClouds.image(night: night, mirrored: false).draw(at: .zero, blendMode: .normal, alpha: 0.98)
                }
                let a = try XCTUnwrap(actual.cgImage), b = try XCTUnwrap(expected.cgImage)
                for (x, y) in [(80, 96), (128, 128), (160, 128), (180, 160)] {
                    let observed = try pixel(a, x: x, y: y), reference = try pixel(b, x: x, y: y)
                    XCTAssertLessThanOrEqual(zip(observed, reference).map { abs($0 - $1) }.max() ?? 255, 8,
                                             "An8km-world camera must retain the same visible geographic cloud")
                }
            }
        }
    }

    private let size = CGSize(width: 256, height: 256)
    private var time = 0.0

    private func patch(center: CGPoint, radius: CGFloat) -> CityDistrictCamera.CloudPatch {
        .init(center: center, east: .init(dx: radius, dy: 0), south: .init(dx: 0, dy: radius), mirrorsContour: false)
    }

    private func renderer(overlay: SKScene) throws -> SCNRenderer {
        let scene = SCNScene()
        scene.background.contents = UIColor.blue
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position.z = 3
        var matrix = SCNMatrix4Identity
        matrix.m33 = -1.0001667; matrix.m34 = -1; matrix.m43 = -2.0001667; matrix.m44 = 0
        camera.camera?.projectionTransform = matrix
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
        renderer.scene = scene; renderer.pointOfView = camera; renderer.overlaySKScene = overlay
        return renderer
    }

    private func capture(_ renderer: SCNRenderer, name: String) throws -> CGImage {
        time += 1.0 / 30
        let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling2X)
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        return try XCTUnwrap(image.cgImage)
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [Int] {
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        let valid = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let g = CGContext(data: storage.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            g.draw(crop, in: .init(x: 0, y: 0, width: 1, height: 1)); return true
        }
        XCTAssertTrue(valid)
        return bytes.map(Int.init)
    }
}
