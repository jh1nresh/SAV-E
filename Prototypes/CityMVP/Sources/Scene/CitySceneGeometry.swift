import UIKit
import SceneKit

/// Procedural illustration aligned to the bundled OpenStreetMap footprints.
@MainActor
enum CitySceneGeometry {
    private static let sunPosition = SIMD3<Float>(-700, 1_200, 500)
    private static let daySkyLight = UIColor(red: 0.89, green: 0.95, blue: 1, alpha: 1)
    private static let daySunLight = UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1)
    private static let daySkyIntensity: CGFloat = 310
    private static let daySunIntensity: CGFloat = 815

    private struct RoofMaterialKey: Hashable {
        let tint: Int
        let residential: Bool
    }

    private static var roofMaterials: [RoofMaterialKey: SCNMaterial] = [:]

    fileprivate static func genericRoofMaterial(tint: Int, residential: Bool) -> SCNMaterial {
        let key = RoofMaterialKey(tint: tint, residential: residential)
        if let material = roofMaterials[key] { return material }
        let material = cityMaterial(CityStreetSurface.color(tint))
        material.name = "city-generic-roof"
        if let texture = CityRoofDetails.surfaceTexture(tint: tint, residential: residential) {
            material.diffuse.contents = texture
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.mipFilter = .linear
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(2.0, 2.0, 1)
        }
        roofMaterials[key] = material
        return material
    }

    static func makeScene() -> SCNScene {
        let started = ProcessInfo.processInfo.systemUptime
        let builder = Builder()
        while builder.advance() != nil {}
        return builder.finish(started: started)
    }

    static func prepareScene() async throws -> SCNScene {
        let started = ProcessInfo.processInfo.systemUptime
        let builder = Builder()
        let tracing = CityDistrictTrace.enabled
        var stages: [Stage: StageTiming] = [:]
        var slice = 0
        var finished = false
        while !finished {
            var sliceStart = ProcessInfo.processInfo.systemUptime
            var items = 0
            var lastStage: Stage?
            repeat {
                try Task.checkCancellation()
                if let rasterStage = builder.pendingRasterStage {
                    sliceStart += try await builder.prepareRaster(rasterStage)
                    try Task.checkCancellation()
                }
                let stepStart = ProcessInfo.processInfo.systemUptime
                guard let stage = builder.advance() else {
                    finished = true
                    break
                }
                items += 1
                lastStage = stage
                if tracing {
                    stages[stage, default: StageTiming()].record(ProcessInfo.processInfo.systemUptime - stepStart)
                }
            } while ProcessInfo.processInfo.systemUptime - sliceStart < 0.007
            if tracing, let lastStage {
                let elapsed = (ProcessInfo.processInfo.systemUptime - sliceStart) * 1_000
                CityDistrictTrace.write("scene-slice\t\(slice)\t\(lastStage.rawValue)\t\(items)\t\(elapsed)")
            }
            slice += 1
            if !finished { try await Task.sleep(for: .milliseconds(8)) }
        }
        try Task.checkCancellation()
        for stage in Stage.allCases {
            guard let timing = stages[stage] else { continue }
            CityDistrictTrace.write("scene-stage\t\(stage.rawValue)\t\(timing.count)\t\(timing.total * 1_000)\t\(timing.maximum * 1_000)")
        }
        return builder.finish(started: started)
    }

    private enum Stage: String, CaseIterable {
        case dataset, lighting, districtGround, roadPlan, civicGround, civicFixtures, buildings, facades
        case landmark, civicTrees, cornerFixtures, trees, shadows, streetTexture, streetLights, streetFixtures, traffic, audit
    }

    private struct StageTiming {
        var count = 0
        var total = 0.0
        var maximum = 0.0

        mutating func record(_ elapsed: Double) {
            count += 1
            total += elapsed
            maximum = max(maximum, elapsed)
        }
    }

    @MainActor
    private final class Builder {
        private let scene = SCNScene()
        private let stages = Stage.allCases
        private var elements: [[String: Any]] = []
        private var roads: [CityStreetSurface.Road] = []
        private var crossingRoads: [CityStreetSurface.Road] = []
        private var casters: [CityStreetDetail.Caster] = []
        private let facadeBatch = CityFacadeBatch()
        private var treePlanner: CityCivicLandscape.TreePlanner?
        private var trees: [CityCivicLandscape.TreePosition] = []
        private var stageIndex = 0
        private var itemIndex = 0
        private var assetCounts: (nodes: Int, images: Int, bytes: Int)?

        private enum PreparedRaster {
            case ground(CGImage?)
            case civicGround(CGImage?)
            case shadows(CGImage?)
            case street(CityStreetSurface.RoadTextures?)
        }

        private var preparedRaster: PreparedRaster?

        var pendingRasterStage: Stage? {
            guard stageIndex < stages.count else { return nil }
            let stage = stages[stageIndex]
            switch stage {
            case .districtGround: return CitySceneData.elements == nil ? nil : stage
            case .civicGround, .shadows: return stage
            case .streetTexture: return roads.isEmpty ? nil : stage
            default: return nil
            }
        }

        private var skywalkShadows: [[SIMD3<Float>]] = []

        private var shadowInput: CityStreetDetail.ShadowInput {
            let sun = CitySceneGeometry.sunPosition
            let offset = CGPoint(x: CGFloat(-sun.x / sun.y), y: CGFloat(-sun.z / sun.y))
            return CityStreetDetail.ShadowInput(
                casters: casters + [.init(footprint: CityLandmark101.podiumFootprint,
                                          height: CityLandmark101.podiumHeight)],
                trees: trees, offset: offset,
                landmarkBands: CityLandmark101.shadowBands + CityNanShanArchitecture.shadowBands(in: scene.rootNode) + skywalkShadows
            )
        }

        func prepareRaster(_ stage: Stage) async throws -> TimeInterval {
            let started: TimeInterval
            switch stage {
            case .districtGround:
                let input = CityStreetSurface.districtGround(elements: elements)
                started = ProcessInfo.processInfo.systemUptime
                preparedRaster = .ground(try await CityStreetSurface.prepareDistrictGround(input))
            case .civicGround:
                let input = CityCivicLandscape.publicPaving(elements: elements)
                started = ProcessInfo.processInfo.systemUptime
                preparedRaster = .civicGround(try await CityCivicLandscape.preparePublicPaving(input))
            case .shadows:
                let input = shadowInput
                started = ProcessInfo.processInfo.systemUptime
                preparedRaster = .shadows(try await CityStreetDetail.prepareCornerShadows(input))
            case .streetTexture:
                let cycleway = CityStreetSurface.cyclewayPath
                started = ProcessInfo.processInfo.systemUptime
                preparedRaster = .street(try await CityStreetSurface.prepareRoadTexture(
                    roads: roads, crossings: crossingRoads, cycleway: cycleway
                ))
            default: return 0
            }
            let end = ProcessInfo.processInfo.systemUptime
            if CityDistrictTrace.enabled {
                CityDistrictTrace.write("scene-raster\t\(stage.rawValue)\t\(started)\t\(end)")
            }
            return end - started
        }

        func advance() -> Stage? {
            guard stageIndex < stages.count else { return nil }
            let stage = stages[stageIndex]
            let root = scene.rootNode
            switch stage {
            case .dataset: elements = CitySceneData.elements ?? []
            case .lighting:
                scene.background.contents = UIColor.clear
                scene.fogColor = CitySceneGeometry.hazeColor(night: false)
                scene.fogDensityExponent = 1.7
                CitySceneGeometry.addLights(to: root)
            case .districtGround:
                if case .ground(let image) = preparedRaster {
                    CityStreetSurface.addDistrictGround(image, to: root)
                    preparedRaster = nil
                } else if CitySceneData.elements != nil {
                    let input = CityStreetSurface.districtGround(elements: elements)
                    CityStreetSurface.addDistrictGround(CityStreetSurface.rasterizeDistrictGround(input), to: root)
                }
            case .roadPlan:
                roads = CityStreetSurface.roads()
                crossingRoads = CityStreetSurface.crossingRoads(roads: roads, elements: elements)
            case .civicGround:
                let image = if case .civicGround(let prepared) = preparedRaster {
                    prepared
                } else {
                    CityCivicLandscape.rasterizePublicPaving(CityCivicLandscape.publicPaving(elements: elements))
                }
                CityCivicLandscape.addPublicSpaces(image, to: root)
                preparedRaster = nil
            case .civicFixtures: skywalkShadows = CityCivicLandscape.addFixtures(to: root, elements: elements)
            case .buildings:
                if itemIndex < elements.count {
                    if let caster = addOSMBuilding(elements[itemIndex], to: root, facadeBatch: facadeBatch) {
                        casters.append(caster)
                    }
                    itemIndex += 1
                    return stage
                }
            case .facades: facadeBatch.add(to: root)
            case .landmark: CityLandmark101.add(to: root)
            case .civicTrees:
                if let cached = CityCivicLandscape.preparedTreePositions {
                    trees = CityStreetDetail.cornerTreePositions + cached
                } else {
                    let planner = treePlanner ?? CityCivicLandscape.TreePlanner(elements: elements)
                    treePlanner = planner
                    if planner.advance() { return stage }
                    trees = CityStreetDetail.cornerTreePositions + CityCivicLandscape.rememberTreePositions(planner.positions)
                    treePlanner = nil
                }
            case .cornerFixtures:
                CityStreetDetail.addCornerFixtures(to: root)
                // Add extra grove trees last so existing street trees keep their seeds.
                let groveStart = trees.firstIndex(where: \.supplemental) ?? trees.endIndex
                trees.insert(contentsOf: CityStreetDetail.forecourtTreePositions, at: groveStart)
            case .trees:
                if itemIndex < trees.count {
                    let point = trees[itemIndex]
                    CityStreetDetail.addTree(point, seed: itemIndex, to: root)
                    itemIndex += 1
                    return stage
                }
            case .shadows:
                let image = if case .shadows(let prepared) = preparedRaster {
                    prepared
                } else {
                    CityStreetDetail.rasterizeCornerShadows(shadowInput)
                }
                CityStreetDetail.addCornerShadows(image, to: root)
                preparedRaster = nil
            case .streetTexture:
                let image = if case .street(let prepared) = preparedRaster {
                    prepared
                } else {
                    CityStreetSurface.rasterizeRoadTexture(
                        roads: roads, crossings: crossingRoads, cycleway: CityStreetSurface.cyclewayPath
                    )
                }
                CityStreetSurface.addRoadTexture(image, to: root, roads: roads)
                preparedRaster = nil
            case .streetLights: CityStreetSurface.addNightLights(to: root, roads: roads, crossings: crossingRoads)
            case .streetFixtures: CityStreetSurface.addRoadFixtures(to: root, roads: roads)
            case .traffic: CityStreetTraffic.add(to: root, roads: roads)
            case .audit:
                if CityDistrictTrace.enabled { assetCounts = CitySceneGeometry.countAssets(in: root) }
            }
            stageIndex += 1
            itemIndex = 0
            return stage
        }

        func finish(started: TimeInterval) -> SCNScene {
            if let counts = assetCounts {
                let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1_000
                CityDistrictTrace.write("scene-build\t\(elapsed)\t\(counts.nodes)\t\(counts.images)\t\(counts.bytes)")
            }
            return scene
        }
    }

    private static func addLights(to root: SCNNode) {
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.name = "city-ambient"
        ambient.light?.intensity = daySkyIntensity
        ambient.light?.color = daySkyLight
        root.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional
        sun.name = "city-key-light"
        sun.light?.intensity = daySunIntensity
        sun.light?.color = daySunLight
        // Keep mobile fill cost bounded. Geometry/shading remain from the accepted demo.
        sun.simdPosition = sunPosition
        sun.look(at: SCNVector3(0, 0, 0))
        root.addChildNode(sun)
    }

    private static func countAssets(in root: SCNNode) -> (nodes: Int, images: Int, bytes: Int) {
        var images = Set<ObjectIdentifier>(), imageBytes = 0, geometryNodes = 0
        root.enumerateChildNodes { node, _ in
            if node.geometry != nil { geometryNodes += 1 }
            for material in node.geometry?.materials ?? [] {
                for property in [material.diffuse, material.emission] {
                    if let image = property.contents as? UIImage, let cg = image.cgImage,
                       images.insert(ObjectIdentifier(image)).inserted {
                        imageBytes += cg.bytesPerRow * cg.height
                    }
                }
            }
        }
        return (geometryNodes, images.count, imageBytes)
    }
    private static func hazeColor(night: Bool) -> UIColor {
        night ? UIColor(red: 0.09, green: 0.14, blue: 0.21, alpha: 1)
              : UIColor(red: 0.90, green: 0.92, blue: 0.94, alpha: 1)
    }

    static func applyLighting(to scene: SCNScene, night: Bool, animated: Bool) {
        let root = scene.rootNode
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.4 : 0
        scene.fogColor = hazeColor(night: night)
        let ambient = root.childNode(withName: "city-ambient", recursively: false)?.light
        ambient?.intensity = night ? 330 : daySkyIntensity
        ambient?.color = night ? UIColor(red: 0.53, green: 0.66, blue: 0.92, alpha: 1) : daySkyLight
        let key = root.childNode(withName: "city-key-light", recursively: false)?.light
        key?.intensity = night ? 225 : daySunIntensity
        key?.color = night ? UIColor(red: 0.56, green: 0.71, blue: 1, alpha: 1) : daySunLight
        root.childNode(withName: "xinyi-ground-shadows", recursively: false)?.opacity = night ? 0.35 : 1
        root.childNode(withName: CityStreetSurface.nightLightsName, recursively: false)?.opacity = night ? 1 : 0
        root.enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] where material.name == "city-lit-facade" {
                material.emission.intensity = night ? 0.75 : 0
            }
        }
        for node in root.childNodes where node.name == "city-window" {
            node.geometry?.firstMaterial?.emission.contents = night
                ? UIColor(red: 0.72, green: 0.51, blue: 0.24, alpha: 1) : UIColor.black
        }
        SCNTransaction.commit()
    }

}

private func cityVector(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 {
    SCNVector3(Float(x), Float(y), Float(z))
}

private func cityMaterial(_ color: UIColor) -> SCNMaterial {
    let m = SCNMaterial(); m.diffuse.contents = color; m.roughness.contents = 0.85
    m.lightingModel = .blinn; return m
}
private func xy(_ p: [String:Any]) -> CGPoint {
    CGPoint(x: ((p["lon"] as? Double ?? 121.564468)-121.564468)*100850,
            y: ((p["lat"] as? Double ?? 25.033968)-25.033968)*111195)
}
private func addOSMBuilding(_ item: [String: Any], to root: SCNNode,
                            facadeBatch: CityFacadeBatch) -> CityStreetDetail.Caster? {
    guard let tags = item["tags"] as? [String: String], tags["building"] != nil,
          let geometry = item["geometry"] as? [[String: Any]], geometry.count > 3 else { return nil }
    let points = geometry.map(xy)
    guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
          points.contains(where: { abs($0.x) < 650 && abs($0.y) < 650 }) else { return nil }
    let path = UIBezierPath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.addLine(to: $0) }
    path.close()
    // The separately modeled landmark occupies the real 101 coordinate.
    guard !path.contains(.zero), (Int(tags["layer"] ?? "0") ?? 0) == 0 else { return nil }
    let id = item["id"] as? Int ?? 0
    if CityNanShanArchitecture.add(way: id, footprint: path, to: root) { return nil }
    let authoredFinish = CityStreetDetail.finish(for: id)
    let isRoof = tags["building"] == "roof"
    let levels = tags["building:levels"].flatMap(Int.init)
    let height = CitySceneData.buildingHeight(tags, way: id)
    if id == CitySceneData.att4FunWayID,
       CityStreetDetail.addATT4Fun(footprint: points, outline: path, height: height, in: root) {
        return .init(footprint: points, height: height)
    }
    let finish = authoredFinish ?? CityStreetDetail.genericFinish(tags: tags, height: height, way: id)
    let shape = SCNShape(path: path, extrusionDepth: height)
    let wall = cityMaterial(finish.wall)
    if authoredFinish == nil && !isRoof {
        let tint = CityStreetDetail.genericRoofTint(for: finish, tag: tags["roof:colour"])
        shape.materials = [CitySceneGeometry.genericRoofMaterial(tint: tint, residential: finish.isHome), wall, wall]
    } else {
        shape.materials = [wall]
    }
    let node = SCNNode(geometry: shape)
    node.eulerAngles.x = -.pi / 2
    node.name = "surface-way/\(id)"
    node.position.y = Float(height / 2)
    root.addChildNode(node)
    guard !isRoof else { return nil }
    if id == CityStreetDetail.xinyiOfficeWayID,
       CityStreetDetail.addXinyiOffice(footprint: points, height: height, in: root) {
        return .init(footprint: points, height: height)
    }
    if authoredFinish != nil {
        CityStreetDetail.decorate(way: id, footprint: points, height: height, levels: levels,
                                  finish: finish, includeFacade: false, in: root)
    }
    if authoredFinish != nil || !CityStreetDetail.hasPlainWalls(tags) {
        facadeBatch.append(footprint: points, height: height, levels: levels, finish: finish, seed: id)
    }
    if id == CityCivicArchitecture.wayID {
        CityCivicArchitecture.add(footprint: points, height: height, levels: levels, to: root)
    }
    return .init(footprint: points, height: height)
}
