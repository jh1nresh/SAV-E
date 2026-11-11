import XCTest
import UIKit
import SceneKit
@testable import SavvyCityMVP

@MainActor
final class CityLandmarkTests: XCTestCase {
    func testLandmarkKeepsItsGroundAnchorAndEightFlaredTiers() throws {
        let scene = SCNScene()
        CityLandmark101.add(to: scene.rootNode)
        let landmark = try XCTUnwrap(scene.rootNode.childNode(withName: "surface-landmark-101", recursively: false))
        XCTAssertEqual(landmark.simdPosition, .zero)
        let (lower, upper) = landmark.boundingBox
        XCTAssertEqual(lower.y, 0, accuracy: 0.001)
        XCTAssertEqual(upper.y, 508, accuracy: 0.001)

        let podium = try XCTUnwrap(landmark.childNode(withName: "city-101-podium", recursively: false))
        let box = try XCTUnwrap(podium.geometry as? SCNBox)
        XCTAssertEqual(box.width, 125, accuracy: 0.001)
        XCTAssertEqual(box.length, 95, accuracy: 0.001)
        XCTAssertEqual(box.height, 25, accuracy: 0.001)
        XCTAssertEqual(podium.position.y, 12.5, accuracy: 0.001)

        let tiers = landmark.childNodes.filter { $0.name?.hasPrefix("city-101-tier-") == true }
        XCTAssertEqual(tiers.count, 8)
        for index in 0..<8 {
            let tier = try XCTUnwrap(landmark.childNode(withName: "city-101-tier-\(index + 1)", recursively: false))
            let (base, top) = tier.boundingBox
            let y = Float(90 + index * 42)
            XCTAssertEqual(base.y, y, accuracy: 0.001)
            XCTAssertEqual(top.y, y + 42, accuracy: 0.001)

            let geometry = try XCTUnwrap(tier.geometry)
            let source = try XCTUnwrap(geometry.sources(for: .vertex).first)
            XCTAssertLessThanOrEqual(geometry.elementCount, 4)
            let foot = ringVertices(at: y, in: source)
            let collar = ringVertices(at: y + 38.1, in: source)
            XCTAssertEqual(foot.map { abs($0.x) }.max() ?? 0, 22.6, accuracy: 0.001)
            XCTAssertEqual(collar.map { abs($0.x) }.max() ?? 0, 29.4, accuracy: 0.001)
            XCTAssertTrue(collar.contains { abs(abs($0.x) - 23.4) < 0.001 && abs(abs($0.z) - 29.4) < 0.001 })
        }
    }

    func testLandmarkSharesTwoTexturesAndUsesDistrictNightLighting() throws {
        let scene = SCNScene()
        CityLandmark101.add(to: scene.rootNode)
        let landmark = try XCTUnwrap(scene.rootNode.childNode(withName: "surface-landmark-101", recursively: false))
        let geometry = landmark.childNodes.compactMap(\.geometry)
        XCTAssertLessThanOrEqual(geometry.count, 15)
        XCTAssertLessThanOrEqual(geometry.reduce(0) { $0 + $1.elementCount }, 64)

        let glazing = geometry.flatMap(\.materials).filter { $0.name == "city-lit-facade" }
        XCTAssertGreaterThanOrEqual(glazing.count, 8)
        XCTAssertEqual(Set(glazing.map(ObjectIdentifier.init)).count, 1)
        let material = try XCTUnwrap(glazing.first)
        let diffuse = try XCTUnwrap(material.diffuse.contents as? UIImage)
        let emission = try XCTUnwrap(material.emission.contents as? UIImage)
        XCTAssertFalse(diffuse === emission)
        for image in [diffuse, emission] {
            let pixels = try XCTUnwrap(image.cgImage)
            XCTAssertLessThanOrEqual(pixels.width * pixels.height, 224 * 192)
        }
        XCTAssertEqual(material.emission.intensity, 0)
        CitySceneGeometry.applyLighting(to: scene, night: true, animated: false)
        XCTAssertEqual(material.emission.intensity, 0.75)
        CitySceneGeometry.applyLighting(to: scene, night: false, animated: false)
        XCTAssertEqual(material.emission.intensity, 0)
    }

    func testInteriorFollowsTheFlaredAndChamferedShellProfiles() {
        XCTAssertTrue(CityLandmark101.containsInterior(.init(20, 120, 20)))
        XCTAssertTrue(CityLandmark101.containsInterior(.init(-20, 120, -20)))
        XCTAssertTrue(CityLandmark101.containsInterior(.init(17, 430, 0)))
        XCTAssertFalse(CityLandmark101.containsInterior(.init(11, 466, 0)))
        XCTAssertFalse(CityLandmark101.containsInterior(.init(27, 120, 27)))
        XCTAssertFalse(CityLandmark101.containsInterior(.init(32, 120, 0)))
    }

    func testInteriorRespectsPodiumRoundingMastAndFiniteBounds() {
        XCTAssertTrue(CityLandmark101.containsInterior(.init(61, 12.5, 46)))
        XCTAssertFalse(CityLandmark101.containsInterior(.init(62.4, 1, 47.4)))
        XCTAssertTrue(CityLandmark101.containsInterior(.init(0, 25, 0)))
        XCTAssertTrue(CityLandmark101.containsInterior(.init(1.7, 470, 0)))
        XCTAssertFalse(CityLandmark101.containsInterior(.init(1.7, 500, 0)))
        XCTAssertFalse(CityLandmark101.containsInterior(.init(0, 0, 0)))
        XCTAssertFalse(CityLandmark101.containsInterior(.init(0, 508, 0)))
        XCTAssertFalse(CityLandmark101.containsInterior(.init(.nan, 120, 0)))
        XCTAssertFalse(CityLandmark101.containsInterior(.init(0, .infinity, 0)))
    }

    private func ringVertices(at height: Float, in source: SCNGeometrySource) -> [SIMD3<Float>] {
        let componentSize = MemoryLayout<Float>.size
        XCTAssertEqual(source.bytesPerComponent, componentSize)
        XCTAssertEqual(source.componentsPerVector, 3)
        return source.data.withUnsafeBytes { bytes in
            (0..<source.vectorCount).compactMap { index in
                let start = source.dataOffset + index * source.dataStride
                let y = bytes.loadUnaligned(fromByteOffset: start + componentSize, as: Float.self)
                guard abs(y - height) < 0.001 else { return nil }
                return SIMD3(
                    bytes.loadUnaligned(fromByteOffset: start, as: Float.self), y,
                    bytes.loadUnaligned(fromByteOffset: start + 2 * componentSize, as: Float.self)
                )
            }
        }
    }
}
