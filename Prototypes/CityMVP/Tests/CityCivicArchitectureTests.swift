import XCTest
import UIKit
import SceneKit
import CoreLocation
@testable import SavvyCityMVP

@MainActor
final class CityCivicArchitectureTests: XCTestCase {
    func testRoofJointsDoNotCrossConcaveCourtyard() {
        let ring: [CGPoint] = [.init(x: 0, y: 0), .init(x: 80, y: 0), .init(x: 80, y: 80),
                               .init(x: 56, y: 80), .init(x: 56, y: 24), .init(x: 24, y: 24),
                               .init(x: 24, y: 80), .init(x: 0, y: 80)]
        let polygon = UIBezierPath()
        polygon.move(to: ring[0]); ring.dropFirst().forEach { polygon.addLine(to: $0) }; polygon.close()
        let joints = CityCivicArchitecture.roofJoints(in: ring)
        XCTAssertGreaterThan(joints.count, 20)
        for (a, b) in joints {
            for fraction: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                let point = CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
                XCTAssertTrue(polygon.contains(point), "Roof line escapes concave footprint: \(point)")
            }
        }
        let reversed = CityCivicArchitecture.roofJoints(in: Array(ring.reversed()))
        XCTAssertEqual(joints.count, reversed.count)
        XCTAssertTrue(CityCivicArchitecture.roofJoints(in: []).isEmpty)
    }

    func testCityHallRoofJointsFitAcrossTheirFullWidth() throws {
        let way = try XCTUnwrap(CitySceneData.elements?.first { $0["id"] as? Int == CityCivicArchitecture.wayID })
        let ring = CityCivicLandscape.points(way).map { CGPoint(x: $0.x, y: -$0.y) }
        let polygon = UIBezierPath()
        polygon.move(to: try XCTUnwrap(ring.first))
        ring.dropFirst().forEach { polygon.addLine(to: $0) }
        polygon.close()
        let joints = CityCivicArchitecture.roofJoints(in: ring)
        XCTAssertGreaterThan(joints.count, 60)
        for (a, b) in joints {
            let dx = a.x == b.x ? 0.06 : 0.0
            let dy = a.y == b.y ? 0.06 : 0.0
            for point in [a, b] {
                XCTAssertTrue(polygon.contains(CGPoint(x: point.x - dx, y: point.y - dy)))
                XCTAssertTrue(polygon.contains(CGPoint(x: point.x + dx, y: point.y + dy)))
            }
        }
    }

    func testStoneworkStaysOutsideFacadeAndIsBatchedForBothWindings() throws {
        let ring: [CGPoint] = [.init(x: 0, y: 0), .init(x: 80, y: 0),
                               .init(x: 80, y: 80), .init(x: 0, y: 80)]
        for footprint in [ring, Array(ring.reversed())] {
            let root = SCNNode()
            CityCivicArchitecture.add(footprint: footprint, height: 38.4, levels: 12, to: root)
            XCTAssertEqual(root.childNodes.count, 2)
            let stone = try XCTUnwrap(root.childNode(withName: "xinyi-city-hall-stonework", recursively: false))
            let source = try XCTUnwrap(stone.geometry?.sources(for: .vertex).first)
            let centers = worldVertices(source)
            // The middle of each outer face must include projecting trim beyond the skin at 0.13m.
            XCTAssertTrue(centers.contains { $0.z > 0.60 && $0.x > 10 && $0.x < 70 })
            XCTAssertTrue(centers.contains { $0.z < -80.60 && $0.x > 10 && $0.x < 70 })
            XCTAssertTrue(centers.contains { $0.x < -0.60 && $0.z < -10 && $0.z > -70 })
            XCTAssertTrue(centers.contains { $0.x > 80.60 && $0.z < -10 && $0.z > -70 })
            XCTAssertLessThanOrEqual(stone.geometry?.elementCount ?? 99, 3)
            let roof = try XCTUnwrap(root.childNode(withName: "xinyi-city-hall-roof-joints", recursively: false))
            XCTAssertGreaterThan(roof.boundingBox.min.y, 38.54)
        }
    }

    func testXinyiOfficeLobbyFacesTheStreetAndStaysOffItsCarriageways() throws {
        let way = try XCTUnwrap(CitySceneData.elements?.first { $0["id"] as? Int == CityStreetDetail.xinyiOfficeWayID })
        let ring = CityCivicLandscape.points(way).map { CGPoint(x: $0.x, y: -$0.y) }
        let road = CityStreetSurface.groundCarriageways(CityStreetSurface.roads())
        let root = SCNNode()
        XCTAssertFalse(CityStreetDetail.addXinyiOffice(footprint: [], height: 32, in: root))
        XCTAssertTrue(root.childNodes.isEmpty)
        XCTAssertTrue(CityStreetDetail.addXinyiOffice(footprint: ring, height: 32, in: root))
        let detail = try XCTUnwrap(root.childNode(withName: "xinyi-office-detail", recursively: false))
        XCTAssertEqual(detail.childNodes.count, 4)
        let lobby = try XCTUnwrap(detail.childNode(withName: "xinyi-office-curved-lobby", recursively: true))
        let outward = lobby.convertPosition(SCNVector3(0, 0, lobby.boundingBox.max.z), to: root)
        XCTAssertGreaterThan(outward.x, 103)
        XCTAssertLessThan(outward.x, 184)
        XCTAssertLessThan(outward.z, 149)
        XCTAssertGreaterThan(outward.z, 145)
        for x in [lobby.boundingBox.min.x, lobby.boundingBox.max.x] {
            let edge = lobby.convertPosition(SCNVector3(x, 0, lobby.boundingBox.max.z), to: root)
            XCTAssertFalse(road.contains(CGPoint(x: CGFloat(edge.x), y: CGFloat(edge.z))))
        }
    }

    func testATT4FunRoofAndPhotoPinShareTheSameHeight() throws {
        let id = CitySceneData.att4FunWayID
        let way = try XCTUnwrap(CitySceneData.elements?.first { $0["id"] as? Int == id })
        let tags = try XCTUnwrap(way["tags"] as? [String: String])
        let height = CitySceneData.buildingHeight(tags, way: id)
        XCTAssertEqual(height, 42)
        XCTAssertEqual(CitySceneData.buildingHeight(["height": "46 m"], way: id), 46)
        XCTAssertEqual(CitySceneData.buildingHeight([:], way: -1), 16)

        let scene = CitySceneGeometry.makeScene()
        let group = try XCTUnwrap(scene.rootNode.childNode(withName: "surface-way/\(id)", recursively: false))
        let roof = try XCTUnwrap(group.childNode(withName: "att4fun-terrace-roof", recursively: false))
        let place = try XCTUnwrap(CityMVPPlaceBridge.context.first { $0.id == "way/\(id)" })
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let contact = try XCTUnwrap(CityMVPPlaceBridge.modelContact(for: place.id, at: coordinate))
        let roofPoint = roof.convertPosition(SCNVector3(Float(contact.x), Float(contact.y), Float(contact.z)),
                                             from: scene.rootNode)
        XCTAssertEqual(roofPoint.y, roof.boundingBox.max.y, accuracy: 0.001)
        XCTAssertGreaterThan(roofPoint.x, roof.boundingBox.min.x)
        XCTAssertLessThan(roofPoint.x, roof.boundingBox.max.x)
        XCTAssertGreaterThan(roofPoint.z, roof.boundingBox.min.z)
        XCTAssertLessThan(roofPoint.z, roof.boundingBox.max.z)
    }

    private func worldVertices(_ source: SCNGeometrySource) -> [SIMD3<Float>] {
        source.data.withUnsafeBytes { bytes in
            (0..<source.vectorCount).map { index in
                let offset = source.dataOffset + index * source.dataStride
                return .init(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self),
                             bytes.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                             bytes.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
            }
        }
    }
}
