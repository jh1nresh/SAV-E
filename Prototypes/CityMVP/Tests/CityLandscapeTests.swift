import XCTest
import UIKit
import SceneKit
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityLandscapeTests: XCTestCase {
    func testRepeatedFacadesStayWithinThePhoneTextureBudget() {
        autoreleasepool {
            let scene = CitySceneGeometry.makeScene()
            var images = Set<ObjectIdentifier>(), bytes = 0
            scene.rootNode.enumerateChildNodes { node, _ in
                for material in node.geometry?.materials ?? [] {
                    for property in [material.diffuse, material.emission] + CityRetailFacadeMaterial.textureProperties(in: material) {
                        if let image = property.contents as? UIImage, let cg = image.cgImage,
                           images.insert(ObjectIdentifier(image)).inserted {
                            bytes += cg.bytesPerRow * cg.height
                        }
                    }
                }
            }
            let batches = scene.rootNode.childNodes.filter { $0.name?.hasPrefix("xinyi-facade-batch-") == true }
            let materialIDs = Set(batches.flatMap { $0.geometry?.materials ?? [] }.map(ObjectIdentifier.init))
            let receipt: [String: Int] = ["facadeBatches": batches.count, "facadeMaterials": materialIDs.count,
                                         "textureImages": images.count, "textureBytes": bytes]
            if let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "district-facade-resource-budget"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertFalse(batches.isEmpty)
            XCTAssertLessThanOrEqual(batches.count, 24)
            XCTAssertLessThanOrEqual(materialIDs.count, 24)
            XCTAssertLessThan(bytes, 150 * 1_024 * 1_024, "Per-wall textures would exceed the phone budget")
            XCTAssertNotNil(scene.rootNode.childNode(withName: "xinyi-raised-walkways", recursively: false))
            let lights = scene.rootNode.childNode(withName: CityStreetSurface.nightLightsName, recursively: false)
            XCTAssertEqual(lights?.opacity, 0)
            XCTAssertEqual(lights?.geometry?.firstMaterial?.writesToDepthBuffer, false)
            let lamps = scene.rootNode.childNodes.filter { $0.name == "city-lamp" }
            XCTAssertEqual(lamps.count, CityCivicLandscape.lampLightCenters.count)
            XCTAssertGreaterThanOrEqual(lamps.count, 25)
            for obstructed in [CGPoint(x: -109.5, y: -525), CGPoint(x: 234.5, y: -231),
                               CGPoint(x: 270.5, y: -231)] {
                XCTAssertFalse(CityCivicLandscape.lampLightCenters.contains(obstructed))
            }
            CitySceneGeometry.applyLighting(to: scene, night: true, animated: false)
            XCTAssertEqual(lights?.opacity, 1)
            CitySceneGeometry.applyLighting(to: scene, night: false, animated: false)
            XCTAssertEqual(lights?.opacity, 0)
        }
    }

    func testSkywalksKeepDecksOverTheRoadAndOnlyAddCanopiesForLoadedRoutes() throws {
        let elements = try XCTUnwrap(CitySceneData.elements)
        let root = SCNNode()
        let bands = CityCivicLandscape.addSkywalks(to: root, elements: elements)
        let layer = try XCTUnwrap(root.childNode(withName: "xinyi-raised-walkways", recursively: false))
        let names = Set(layer.childNodes.compactMap(\.name))
        XCTAssertEqual(names.filter { $0.hasPrefix("skywalk-way/") }.count, 8)
        XCTAssertEqual(names.filter { $0.hasPrefix("skywalk-canopy/") }.count, 4)
        let roads = CityStreetSurface.groundCarriageways(CityStreetSurface.groundCarriagewayRoutes(in: elements))
        var deckCount = 0, pierCount = 0
        layer.enumerateChildNodes { node, _ in
            if node.name == "skywalk-deck" {
                deckCount += 1
                XCTAssertEqual(node.convertPosition(.init(0, -0.25, 0), to: root).y, 5.75, accuracy: 0.001)
            } else if node.name == "skywalk-pier" {
                pierCount += 1
                let p = node.convertPosition(.init(), to: root)
                let clearance = CGRect(x: CGFloat(p.x) - 0.5, y: CGFloat(p.z) - 0.5, width: 1, height: 1)
                XCTAssertFalse(roads.intersects(CGPath(rect: clearance, transform: nil)))
            }
        }
        XCTAssertGreaterThan(pierCount, 0)
        XCTAssertEqual(deckCount, bands.count)
        let missing = SCNNode()
        _ = CityCivicLandscape.addSkywalks(to: missing, elements: elements.filter { $0["id"] as? Int != 136847471 })
        XCTAssertNil(missing.childNode(withName: "skywalk-canopy/1339487709", recursively: true))
    }

    func testRooftopEquipmentStaysInsideConcaveFootprintsWithClearance() {
        let footprint: [CGPoint] = [.init(x: 0, y: 0), .init(x: 80, y: 0),
            .init(x: 80, y: 20), .init(x: 28, y: 20), .init(x: 28, y: 65), .init(x: 0, y: 65)]
        let outline = UIBezierPath()
        outline.move(to: footprint[0]); footprint.dropFirst().forEach { outline.addLine(to: $0) }; outline.close()
        for seed in 0..<12 {
            let fixtures = CityRoofDetails.fixtures(in: footprint, seed: seed)
            XCTAssertFalse(fixtures.isEmpty)
            XCTAssertLessThanOrEqual(fixtures.count, 5)
            for fixture in fixtures {
                let rect = fixture.rect.insetBy(dx: -1.9, dy: -1.9)
                for x in stride(from: rect.minX, through: rect.maxX, by: 1) {
                    for y in stride(from: rect.minY, through: rect.maxY, by: 1) {
                        XCTAssertTrue(outline.contains(.init(x: x, y: y)), "Equipment extends into a concave roof void")
                    }
                }
            }
        }
        let shaft = CGRect(x: -33, y: -33, width: 66, height: 66)
        let podiumEquipment = CityRoofDetails.fixtures(in: CityStreetDetail.podium, seed: 101, excluding: [shaft])
        XCTAssertFalse(podiumEquipment.isEmpty)
        XCTAssertTrue(podiumEquipment.allSatisfy { !$0.rect.intersects(shaft) })
        XCTAssertTrue(CityRoofDetails.fixtures(in: [.zero, .init(x: 8, y: 0), .init(x: 8, y: 8)], seed: 1).isEmpty)
    }

    func testNorthCorridorContainsConnectedCityHallAndSongshouRoads() throws {
        let roads = Dictionary(uniqueKeysWithValues: CityStreetSurface.roads().map { ($0.id, $0) })
        for ids in [[1335559372, 1335559371], [1335559367, 1335559366, 1335559368, 1335559365],
                    [1335559375, 1335559369, 1335559364, 1335559363, 1335559362]] {
            for (a, b) in zip(ids, ids.dropFirst()) {
                let first = try XCTUnwrap(roads[a]), second = try XCTUnwrap(roads[b])
                let endsA = [try XCTUnwrap(first.path.first), try XCTUnwrap(first.path.last)]
                let endsB = [try XCTUnwrap(second.path.first), try XCTUnwrap(second.path.last)]
                let separation = endsA.flatMap { a in endsB.map { hypot(a.x - $0.x, a.y - $0.y) } }.min()!
                XCTAssertLessThan(separation, 1, "Broken street join between \(a) and \(b)")
            }
        }
        XCTAssertTrue(CityStreetSurface.bounds.contains(CGPoint(x: -5, y: -398)))
        XCTAssertGreaterThan(try XCTUnwrap(roads[1335559371]).width, 20)
        XCTAssertLessThan(try XCTUnwrap(roads[1335559367]).width, 12)
    }

    func testGroundRoadsExcludeTunnelsAndRaisedSkywalks() throws {
        let elements = try XCTUnwrap(CitySceneData.elements)
        for id in [1457382191, 1457382192, 49153827, 49153830, 327579459, 1339401653, 257896676, 462045632] {
            let element = try XCTUnwrap(elements.first { ($0["id"] as? Int) == id })
            let tags = try XCTUnwrap(element["tags"] as? [String: String])
            XCTAssertFalse(CityStreetSurface.isGround(tags), "\(id) is not a surface road")
        }
    }

    func testRoadDetailLeavesConnectedCarriagewaysOpen() throws {
        let elements = try XCTUnwrap(CitySceneData.elements)
        let crossings = CityStreetSurface.crossingRoads(roads: CityStreetSurface.roads(), elements: elements)
        let mask = CityStreetSurface.crossingCarriageways(crossings)
        XCTAssertTrue(mask.contains(CGPoint(x: -303, y: -212)), "Keelung Road at Songshou Road")
        XCTAssertTrue(mask.contains(CGPoint(x: -477, y: 91)), "Keelung Road at Xinyi Road")
        XCTAssertFalse(mask.contains(CGPoint(x: -86.28, y: -575.62)), "Unmatched end of City Hall Road")
        XCTAssertFalse(mask.contains(CGPoint(x: -99, y: 113)), "Detailed Xinyi Road intersection")
    }

    func testPlantedNorthSquaresRetainAnOpenCivicCenter() {
        let trees = CityCivicLandscape.treePositions
        XCTAssertGreaterThan(trees.filter { $0.z < -230 }.count, 15)
        XCTAssertFalse(trees.contains { $0.x > -210 && $0.x < -135 && $0.z > -500 && $0.z < -300 },
                       "Civic forecourt should remain open")
        XCTAssertTrue(trees.allSatisfy { CityStreetSurface.bounds.contains(CGPoint(x: $0.x, y: $0.z)) })
    }
    func testNewGroveTreesStayInsideLawnParksAndOffRoads() throws {
        let elements = try XCTUnwrap(CitySceneData.elements)
        let parks = elements.filter { [186083454, 555866062].contains($0["id"] as? Int ?? 0) }
        let parkOutlines = parks.map {
            CityStreetSurface.polyline(CityCivicLandscape.points($0), closed: true)
        }
        let roadMask = CityStreetSurface.groundCarriageways(CityStreetSurface.groundCarriagewayRoutes(in: elements))
        let grove = CityCivicLandscape.treePositions.filter(\.supplemental)
        XCTAssertGreaterThanOrEqual(grove.count, 12)
        XCTAssertTrue(parkOutlines.allSatisfy { park in
            grove.contains { park.contains(CGPoint(x: $0.x, y: $0.z)) }
        })
        for tree in grove {
            let point = CGPoint(x: tree.x, y: tree.z)
            XCTAssertTrue(tree.inLawn)
            XCTAssertTrue(parkOutlines.contains { $0.contains(point) })
            XCTAssertFalse(roadMask.contains(point))
        }
    }

    func testRetailTreesAvoidBuildingsGroundPathsAndSkywalks() throws {
        let elements = try XCTUnwrap(CitySceneData.elements)
        let planner = CityCivicLandscape.TreePlanner(elements: elements)
        while planner.advance() {}
        let trees = planner.positions.filter(\.inRetailWalk)
        XCTAssertFalse(trees.isEmpty)
        let obstacles = elements.compactMap { item -> CGPath? in
            guard let tags = item["tags"] as? [String: String] else { return nil }
            let route = CityCivicLandscape.points(item)
            if tags["bridge"] == "yes", tags["highway"] == "footway" {
                return CityStreetSurface.polyline(route).copy(strokingWithWidth: 16,
                                                              lineCap: .round, lineJoin: .round, miterLimit: 2)
            }
            guard CityStreetSurface.isGround(tags) else { return nil }
            if tags["building"] != nil { return CityStreetSurface.polyline(route, closed: true) }
            guard tags["highway"] != nil else { return nil }
            return CityStreetSurface.polyline(route).copy(strokingWithWidth: CityStreetSurface.roadWidth(tags) + 5,
                                                         lineCap: .round, lineJoin: .round, miterLimit: 2)
        }
        for tree in trees {
            XCTAssertFalse(tree.supplemental, "Existing lawn-grove flag retains its meaning")
            for x in [tree.x - 1.8, tree.x, tree.x + 1.8] {
                for z in [tree.z - 1.8, tree.z, tree.z + 1.8] {
                    XCTAssertFalse(obstacles.contains { $0.contains(CGPoint(x: x, y: z)) })
                }
            }
        }
        let retailIDs: Set<Int> = [136814873, 327941538, 328519339, 662278606]
        for tag in ["bridge": "yes", "layer": "-1"] {
            let nonGround = elements.map { item -> [String: Any] in
                guard retailIDs.contains(item["id"] as? Int ?? 0) else { return item }
                var copy = item
                var tags = item["tags"] as? [String: String] ?? [:]
                tags[tag.key] = tag.value
                copy["tags"] = tags
                return copy
            }
            let excluded = CityCivicLandscape.TreePlanner(elements: nonGround)
            while excluded.advance() {}
            XCTAssertFalse(excluded.positions.contains(where: \.inRetailWalk))
        }
    }

}
