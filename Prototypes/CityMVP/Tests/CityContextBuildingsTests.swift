import XCTest
import SceneKit
import UIKit
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityContextBuildingsTests: XCTestCase {
    private func way(_ ring: [CGPoint], id: Int = 1, tags: [String: String] = [:]) -> [String: Any] {
        var tags = tags; tags["building"] = tags["building"] ?? "yes"
        return ["id": id, "tags": tags, "geometry": (ring + [ring[0]]).map {
            ["lon": CityScenePlace.originLongitude + $0.x / 100850,
             "lat": CityScenePlace.originLatitude + $0.y / 111195]
        }]
    }
    private let square: [CGPoint] = [.init(x: 800, y: 0), .init(x: 840, y: 0),
                                     .init(x: 840, y: 40), .init(x: 800, y: 40)]

    func testHeroAndUnsafeGeometryNeverBecomeOuterBuildings() throws {
        XCTAssertNotNil(CityContextBuildings.footprint(way(square), excluding: []))
        XCTAssertNil(CityContextBuildings.footprint(way(square), excluding: [1]))
        for tags in [["layer": "1"], ["layer": "bad"], ["location": "underground"],
                     ["tunnel": "yes"], ["building": "roof"], ["building": "no"],
                     ["min_height": "12"], ["building:min_level": "3"], ["bridge": "yes"],
                     ["min_height": "unknown"], ["building:min_level": "-1"]] {
            XCTAssertNil(CityContextBuildings.footprint(way(square, tags: tags), excluding: []))
        }
        for ring in [square.map { CGPoint(x: $0.x - 600, y: $0.y) },
                     square.map { CGPoint(x: $0.x + 800, y: $0.y) },
                     [CGPoint(x: -800, y: -800), .init(x: 800, y: -800),
                      .init(x: 800, y: 800), .init(x: -800, y: 800)]] {
            XCTAssertNil(CityContextBuildings.footprint(way(ring), excluding: []))
        }
        var open = way(square)
        open["geometry"] = (open["geometry"] as? [[String: Double]])?.dropLast().map { $0 }
        XCTAssertNil(CityContextBuildings.footprint(open, excluding: []))
    }

    func testCrossingsTouchesAndBacktrackingNeverProduceRoofsOrWalls() {
        let invalid: [[CGPoint]] = [
            [(829,32),(889,77),(840,95),(805,31),(849,19),(839,92),(837,64)].map { CGPoint(x: $0.0, y: $0.1) },
            [(800,0),(880,0),(840,0),(840,40),(800,40)].map { CGPoint(x: $0.0, y: $0.1) },
            [(800,0),(880,0),(840,20),(880,40),(800,40),(840,20)].map { CGPoint(x: $0.0, y: $0.1) }
        ]
        for ring in invalid { XCTAssertNil(CityContextBuildings.footprint(way(ring), excluding: [])) }
        // A harmless forward collinear vertex remains valid.
        let straight = [(800,0),(820,0),(840,0),(840,40),(800,40)].map { CGPoint(x: $0.0, y: $0.1) }
        XCTAssertNotNil(CityContextBuildings.footprint(way(straight), excluding: []))
    }

    func testConcaveRoofDoesNotBridgeItsNotchOrReverseItsNormals() throws {
        let ring: [CGPoint] = [.init(x: 800, y: 0), .init(x: 880, y: 0), .init(x: 880, y: 20),
                               .init(x: 828, y: 20), .init(x: 828, y: 65), .init(x: 800, y: 65)]
        for input in [ring, Array(ring.reversed())] {
            let footprint = try XCTUnwrap(CityContextBuildings.footprint(way(input), excluding: []))
            var area = 0.0
            for offset in stride(from: 0, to: footprint.roofTriangles.count, by: 3) {
                let p = (0..<3).map { footprint.ring[Int(footprint.roofTriangles[offset + $0])] }
                let cross = (p[1].x - p[0].x) * (p[2].y - p[0].y) - (p[1].y - p[0].y) * (p[2].x - p[0].x)
                XCTAssertGreaterThan(cross, 0, "Roof winding must face the sky")
                area += cross / 2
                let center = CGPoint(x: p.reduce(0) { $0 + $1.x } / 3, y: p.reduce(0) { $0 + $1.y } / 3)
                XCTAssertFalse(center.x > 828.001 && center.y > 20.001)
            }
            XCTAssertEqual(area, 2860, accuracy: 0.01)
        }
    }

    func testCompleteBundledContextUsesBoundedChunksAndNoFacadeTextures() throws {
        let hero = try XCTUnwrap(CitySceneData.elements)
        let rows = CityContextBuildings.elements
        XCTAssertEqual(rows.count, 7602, "Missing or truncated bundled context")
        let builder = CityContextBuildings.Builder(heroElements: hero)
        for row in rows { builder.append(row) }
        let count = builder.buildingCount
        XCTAssertGreaterThan(count, 5_500)
        XCTAssertLessThanOrEqual(count, 6_971)
        for row in rows { builder.append(row) }
        XCTAssertEqual(builder.buildingCount, count, "Repeated way IDs must not duplicate geometry")
        XCTAssertLessThanOrEqual(builder.chunkCount, 100)
        XCTAssertLessThan(builder.vertexCount, 1_000_000)
        let root = SCNNode(); builder.add(to: root)
        XCTAssertEqual(root.childNodes.count, builder.chunkCount)
        var materials = Set<ObjectIdentifier>()
        for node in root.childNodes {
            XCTAssertTrue(node.name?.hasPrefix(CityContextBuildings.nodePrefix) == true)
            let geometry = try XCTUnwrap(node.geometry)
            XCTAssertEqual(geometry.elements.count, 1)
            XCTAssertNil(geometry.sources(for: .texcoord).first)
            for material in geometry.materials {
                materials.insert(ObjectIdentifier(material))
                XCTAssertTrue(material.diffuse.contents is UIColor)
                XCTAssertFalse(material.emission.contents is UIImage)
                XCTAssertEqual(material.transparency, 1)
            }
        }
        XCTAssertEqual(materials.count, 1)
    }

    func testDetailedOuterRingKeepsChunkAndTextureBudgetWithActualVertexColors() throws {
        let builder = CityContextBuildings.Builder(heroElements: try XCTUnwrap(CitySceneData.elements), details: true)
        CityContextBuildings.elements.forEach { builder.append($0) }
        XCTAssertGreaterThan(builder.buildingCount, 5_500)
        XCTAssertLessThanOrEqual(builder.chunkCount, 100)
        XCTAssertLessThan(builder.vertexCount, 1_000_000)
        let root = SCNNode(); builder.add(to: root)
        var materials = Set<ObjectIdentifier>()
        for node in root.childNodes {
            let geometry = try XCTUnwrap(node.geometry)
            let positions = try XCTUnwrap(geometry.sources(for: .vertex).first)
            let colors = try XCTUnwrap(geometry.sources(for: .color).first)
            XCTAssertEqual(colors.vectorCount, positions.vectorCount)
            XCTAssertEqual(colors.componentsPerVector, 4)
            XCTAssertEqual(geometry.elements.count, 1)
            XCTAssertTrue(geometry.sources(for: .texcoord).isEmpty)
            for material in geometry.materials {
                materials.insert(ObjectIdentifier(material))
                XCTAssertTrue(material.diffuse.contents is UIColor)
                XCTAssertFalse(material.emission.contents is UIImage)
            }
        }
        XCTAssertEqual(materials.count, 1, "Color and window detail must remain spatially batched")
    }

    func testStadiumShellReplacesFlatBoxWithoutChangingFootprintOrFoldingRoof() throws {
        let stadium = try XCTUnwrap(CityContextBuildings.elements.first { $0["id"] as? Int == CityContextBuildings.stadiumWayID })
        let footprint = try XCTUnwrap(CityContextBuildings.footprint(stadium, excluding: []))
        let builder = CityContextBuildings.Builder(heroElements: [], details: true)
        builder.append(stadium)
        let root = SCNNode(); builder.add(to: root)
        let geometry = try XCTUnwrap(root.childNodes.first?.geometry)
        let source = try XCTUnwrap(geometry.sources(for: .vertex).first)
        let points: [SIMD3<Float>] = (0..<source.vectorCount).map { index in
            source.data.withUnsafeBytes { bytes in
                let offset = source.dataOffset + index * source.dataStride
                return SIMD3((0..<3).map { bytes.loadUnaligned(fromByteOffset: offset + $0 * 4, as: Float.self) })
            }
        }
        XCTAssertEqual(points.map(\.y).max() ?? 0, 64, accuracy: 0.01)
        XCTAssertGreaterThan(Set(points.map { Int(($0.y * 100).rounded()) }).count, 10)
        let bounds = footprint.ring.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }.insetBy(dx: -0.1, dy: -0.1)
        for point in points {
            XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite)
            XCTAssertTrue(bounds.contains(CGPoint(x: CGFloat(point.x), y: CGFloat(-point.z))))
        }
        let element = try XCTUnwrap(geometry.elements.first)
        let indices: [Int32] = element.data.withUnsafeBytes { bytes in
            (0..<(element.primitiveCount * 3)).map { bytes.loadUnaligned(fromByteOffset: $0 * 4, as: Int32.self) }
        }
        var roofTriangles = 0
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let a = points[Int(indices[offset])], b = points[Int(indices[offset + 1])], c = points[Int(indices[offset + 2])]
            if max(a.y, b.y, c.y) > Float(footprint.height) + 0.1 {
                XCTAssertGreaterThan(simd_cross(b - a, c - a).y, 0, "Roof strips must face upward without folded entrance notches")
                roofTriangles += 1
            }
        }
        XCTAssertGreaterThan(roofTriangles, 500)
    }
}
