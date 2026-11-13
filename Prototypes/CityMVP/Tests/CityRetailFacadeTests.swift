import XCTest
import Metal
import SceneKit
import UIKit
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityRetailFacadeTests: XCTestCase {
    func testRetailVariantsShareOneBatchAndKeepAllEightImages() throws {
        let batch = CityFacadeBatch(), root = SCNNode()
        for variant in 0..<4 {
            let x = CGFloat(variant * 20)
            batch.append(footprint: [.init(x: x, y: 0), .init(x: x + 10, y: 0),
                                     .init(x: x + 10, y: 10), .init(x: x, y: 10)],
                         height: 12, levels: 4, finish: .retail, seed: variant)
        }
        batch.add(to: root)
        XCTAssertEqual(root.childNodes.count, 1)
        let geometry = try XCTUnwrap(root.childNodes.first?.geometry)
        XCTAssertEqual(geometry.sources(for: .texcoord).count, 2)
        let material = try XCTUnwrap(geometry.firstMaterial)
        let properties = CityRetailFacadeMaterial.textureProperties(in: material)
        XCTAssertEqual(properties.count, 8)
        for variant in 0..<4 {
            let pair = CityStreetDetail.repeatedFacade(finish: .retail, variant: variant)
            XCTAssertTrue(properties[variant * 2].contents as? UIImage === pair.0)
            XCTAssertTrue(properties[variant * 2 + 1].contents as? UIImage === pair.1)
        }
        for property in properties {
            XCTAssertEqual(property.wrapS, .repeat); XCTAssertEqual(property.wrapT, .repeat)
            XCTAssertEqual(property.mipFilter, .linear)
        }
        let scene = SCNScene(); scene.rootNode.addChildNode(root)
        CitySceneGeometry.applyLighting(to: scene, night: true, animated: false)
        XCTAssertEqual(material.emission.intensity, 0.75)
        CitySceneGeometry.applyLighting(to: scene, night: false, animated: false)
        XCTAssertEqual(material.emission.intensity, 0)
    }

    /// Real Metal, original material controls, all four variants, repeated UVs,
    /// mip minification, and the actual composed reveal/tone shader. No image mocks.
    func testMergedRetailMatchesOriginalOnGPUWithMSAA2XDayNightAndTone() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let phases: [(CGPoint, CGFloat)] = [(.zero, 1.5), (.init(x: 2, y: 5), 4),
                                            (.init(x: 3.25, y: 1.5), 12)]
        var captures: [String: [UInt8]] = [:]
        for (index, fixture) in phases.enumerated() {
            for tone in [false, true] {
                for night in [false, true] {
                    let key = "phase\(index)-tone\(tone)-night\(night)"
                    let original = try capture(device: device, merged: false, phase: fixture.0,
                                               span: fixture.1, tone: tone, night: night, name: key + "-original")
                    let merged = try capture(device: device, merged: true, phase: fixture.0,
                                             span: fixture.1, tone: tone, night: night, name: key + "-merged")
                    XCTAssertEqual(original.count, merged.count)
                    // Includes interiors, repeat seams and MSAA silhouette pixels.
                    let error = zip(original, merged).map { abs(Int($0) - Int($1)) }.max() ?? 255
                    XCTAssertLessThanOrEqual(error, 8, "8-bit channel tolerance, \(key)")
                    captures[key] = original
                }
            }
        }
        // Controls must actually exercise emission and tone, not render blank/equal scenes.
        for (a, b) in [("phase0-tonefalse-nightfalse", "phase0-tonefalse-nighttrue"),
                       ("phase0-tonefalse-nightfalse", "phase0-tonetrue-nightfalse")] {
            let first = try XCTUnwrap(captures[a]), second = try XCTUnwrap(captures[b])
            XCTAssertGreaterThan(zip(first, second).filter { abs(Int($0) - Int($1)) > 8 }.count, 100)
        }
    }

    private func capture(device: MTLDevice, merged: Bool, phase: CGPoint, span: CGFloat,
                         tone: Bool, night: Bool, name: String) throws -> [UInt8] {
        let scene = SCNScene(); scene.background.contents = UIColor.black
        let root = SCNNode(); scene.rootNode.addChildNode(root)
        var allVertices: [SCNVector3] = [], allUV: [CGPoint] = [], variants: [CGPoint] = [], indices: [Int32] = []
        for variant in 0..<4 {
            let x = Float(variant * 2) - 3.8
            let vertices = [SCNVector3(x, 5.2, 0), .init(x + 1.6, 5.2, 0),
                            .init(x + 1.6, 6.8, 0), .init(x, 6.8, 0)]
            let uv = [phase, CGPoint(x: phase.x + span, y: phase.y),
                      CGPoint(x: phase.x + span, y: phase.y + span), CGPoint(x: phase.x, y: phase.y + span)]
            if merged {
                let base = Int32(allVertices.count)
                allVertices += vertices; allUV += uv
                variants += Array(repeating: CGPoint(x: variant, y: 0), count: 4)
                indices += [0, 1, 2, 0, 2, 3].map { base + Int32($0) }
            } else {
                let geometry = mesh(vertices, uv: uv, variants: [], indices: [0, 1, 2, 0, 2, 3])
                geometry.materials = [originalMaterial(variant: variant)]
                root.addChildNode(SCNNode(geometry: geometry))
            }
        }
        if merged {
            let geometry = mesh(allVertices, uv: allUV, variants: variants, indices: indices)
            geometry.materials = [CityRetailFacadeMaterial.make()]
            root.addChildNode(SCNNode(geometry: geometry))
        }
        // Exercise the production intensity setter before installing the composed copy.
        CitySceneGeometry.applyLighting(to: scene, night: night, animated: false)
        let size = CGSize(width: 384, height: 96)
        let reveal = CitySceneReveal(mode: .materialTone)
        if tone {
            reveal.install(in: root, excluding: nil)
            reveal.update(.init(phase: 0.35, center: .zero, viewport: size), viewport: size, night: night)
            if merged {
                XCTAssertEqual(CityRetailFacadeMaterial.textureProperties(in:
                    try XCTUnwrap(root.childNodes.first?.geometry?.firstMaterial)).count, 8)
            }
        }
        // Lighting installed after the production setter: identical controlled Lambert fixture.
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 350; ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)
        let directional = SCNNode(); directional.light = SCNLight(); directional.light?.type = .directional
        directional.light?.intensity = 300; directional.light?.color = UIColor.white
        scene.rootNode.addChildNode(directional)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.position = .init(0, 6, 8); camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 1.1; camera.camera?.wantsHDR = false
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 20
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 1, with: size, antialiasingMode: .multisampling2X)
        let attachment = XCTAttachment(image: image); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let valid = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: cg.width, height: cg.height,
                                          bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: .init(x: 0, y: 0, width: cg.width, height: cg.height)); return true
        }
        XCTAssertTrue(valid)
        XCTAssertGreaterThan(stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 20 }.count, 500)
        return bytes
    }

    private func mesh(_ vertices: [SCNVector3], uv: [CGPoint], variants: [CGPoint], indices: [Int32]) -> SCNGeometry {
        var sources: [SCNGeometrySource] = [.init(vertices: vertices),
            .init(normals: Array(repeating: .init(0, 0, 1), count: vertices.count)), .init(textureCoordinates: uv)]
        if !variants.isEmpty { sources.append(.init(textureCoordinates: variants)) }
        return SCNGeometry(sources: sources, elements: [.init(indices: indices, primitiveType: .triangles)])
    }

    /// Verbatim material setup from the pre-merge CityFacadeBatch; independent control.
    private func originalMaterial(variant: Int) -> SCNMaterial {
        let pair = CityStreetDetail.repeatedFacade(finish: .retail, variant: variant)
        let material = SCNMaterial(); material.name = "city-lit-facade"
        material.diffuse.contents = pair.0; material.emission.contents = pair.1
        material.emission.intensity = 0; material.lightingModel = .lambert
        for property in [material.diffuse, material.emission] {
            property.wrapS = .repeat; property.wrapT = .repeat; property.mipFilter = .linear
        }
        let scale = CityStreetDetail.facadeLightScale
        material.emission.contentsTransform = SCNMatrix4MakeScale(scale, scale, 1)
        return material
    }
}
