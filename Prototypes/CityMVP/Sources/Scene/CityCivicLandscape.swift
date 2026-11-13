#if SAVVY_CITY_MVP
import UIKit
import SceneKit

/// Original illustrative dressing on public OSM footprints. No navigation or entrance claims.
@MainActor
enum CityCivicLandscape {
    private static let pavedParkIDs: Set<Int> = [309157011, 1341042550, 555117276]
    // Includes 眷村文化公園 and 松仁綠地 in the southern blocks.
    private static let lawnParkIDs: Set<Int> = [186083454, 555866062]
    private static let parkIDs = pavedParkIDs.union(lawnParkIDs).union([233666147, 261647304])
    // Source footways define the retail spine. Width and planting are illustrative.
    private static let retailWalkWidths: [Int: CGFloat] = [
        136814873: 9, 327941538: 9, 328519339: 9, 662278606: 6,
    ]
    nonisolated private static let pavingColors = [0xc7b69f, 0xcbbba3, 0xd2c0a9, 0xbfad96, 0xcdbca6]
    nonisolated private static let walkPavingColors = [0xd6b999, 0xdbc2a7, 0xe1c7ac, 0xcab193, 0xddc4aa]
    nonisolated private static let concretePavingColors = [0xd9d0bc, 0xd4cbb7, 0xe2d9c7, 0xdad2c2]
    nonisolated private static let extent = CGRect(x: -540, y: -650, width: 1_100, height: 1_030)

    static func points(_ item: [String: Any]) -> [CGPoint] {
        (item["geometry"] as? [[String: Double]] ?? []).compactMap {
            guard let lat = $0["lat"], let lon = $0["lon"], lat.isFinite, lon.isFinite else { return nil }
            return CGPoint(x: (lon - CityScenePlace.originLongitude) * 100_850,
                           y: -(lat - CityScenePlace.originLatitude) * 111_195)
        }
    }

    private static func path(_ points: [CGPoint], closed: Bool = false) -> UIBezierPath {
        let line = UIBezierPath()
        guard let first = points.first else { return line }
        line.move(to: first)
        for point in points.dropFirst() { line.addLine(to: point) }
        if closed { line.close() }
        return line
    }

    nonisolated struct TreePosition: Sendable {
        let x: CGFloat
        let z: CGFloat
        var inLawn = false
        var supplemental = false
        var inRetailWalk = false
    }
    private(set) static var preparedTreePositions: [TreePosition]?

    static var treePositions: [TreePosition] {
        if let preparedTreePositions { return preparedTreePositions }
        let planner = TreePlanner(elements: CitySceneData.elements ?? [])
        while planner.advance() {}
        return rememberTreePositions(planner.positions)
    }

    @discardableResult
    static func rememberTreePositions(_ positions: [TreePosition]) -> [TreePosition] {
        if let preparedTreePositions { return preparedTreePositions }
        preparedTreePositions = positions
        return positions
    }

    @MainActor
    final class TreePlanner {
        private struct Obstruction {
            let bounds: CGRect
            let path: CGPath

            init(_ path: CGPath) {
                bounds = path.boundingBoxOfPath.insetBy(dx: -0.01, dy: -0.01)
                self.path = path
            }

            func contains(_ point: CGPoint) -> Bool {
                bounds.contains(point) && path.contains(point)
            }
        }

        private let elements: [[String: Any]]
        private var obstructions: [Obstruction] = []
        private var overheadObstructions: [Obstruction] = []
        private var candidates: [TreePosition] = []
        private var groveCandidates: [TreePosition] = []
        private var retailCandidates: [TreePosition] = []
        private var nextElement = 0
        private var nextCandidate = 0
        private(set) var positions: [TreePosition] = []

        init(elements: [[String: Any]]) {
            self.elements = elements
        }

        func advance() -> Bool {
            if nextElement < elements.count {
                index(elements[nextElement])
                nextElement += 1
                if nextElement == elements.count { candidates += groveCandidates + retailCandidates }
                return true
            }
            guard nextCandidate < candidates.count else { return false }
            let candidate = candidates[nextCandidate]
            nextCandidate += 1
            let point = CGPoint(x: candidate.x, y: candidate.z)
            let spacing: CGFloat = candidate.supplemental ? 9 : 11
            let base = candidate.inRetailWalk
                ? [point, CGPoint(x: point.x - 1.8, y: point.y - 1.8),
                   CGPoint(x: point.x + 1.8, y: point.y - 1.8),
                   CGPoint(x: point.x - 1.8, y: point.y + 1.8),
                   CGPoint(x: point.x + 1.8, y: point.y + 1.8)]
                : [point]
            let blockedOverhead = candidate.inRetailWalk
                && overheadObstructions.contains { obstruction in base.contains(where: obstruction.contains) }
            if !blockedOverhead,
               !obstructions.contains(where: { obstruction in base.contains(where: obstruction.contains) }),
               !positions.contains(where: { hypot($0.x - point.x, $0.z - point.y) < spacing }) {
                positions.append(candidate)
            }
            return true
        }

        private func index(_ item: [String: Any]) {
            if let tags = item["tags"] as? [String: String],
               tags["bridge"] == "yes", tags["highway"] == "footway" {
                // A street tree can reach the deck even when its base is on
                // clear pavement. Reserve the span plus room for its crown.
                let route = CityCivicLandscape.path(CityCivicLandscape.points(item))
                overheadObstructions.append(Obstruction(route.cgPath.copy(strokingWithWidth: 16, lineCap: .round,
                                                                          lineJoin: .round, miterLimit: 2)))
            }
            if let tags = item["tags"] as? [String: String], CityStreetSurface.isGround(tags) {
                if tags["building"] != nil {
                    let footprint = CityCivicLandscape.path(CityCivicLandscape.points(item), closed: true)
                    obstructions.append(Obstruction(footprint.cgPath))
                }
                if tags["highway"] != nil {
                    let width = CityStreetSurface.roadWidth(tags) + 5
                    let route = CityCivicLandscape.path(CityCivicLandscape.points(item))
                    let stroke = route.cgPath.copy(strokingWithWidth: width, lineCap: .round,
                                                   lineJoin: .round, miterLimit: 2)
                    obstructions.append(Obstruction(stroke))
                }
            }
            if let id = item["id"] as? Int, id != 662278606,
               CityCivicLandscape.retailWalkWidths[id] != nil,
               let tags = item["tags"] as? [String: String],
               tags["highway"] == "footway", CityStreetSurface.isGround(tags) {
                let route = CityCivicLandscape.points(item)
                for (a, b) in zip(route, route.dropFirst()) {
                    let length = hypot(b.x - a.x, b.y - a.y)
                    guard length > 18 else { continue }
                    let dx = (b.x - a.x) / length, dz = (b.y - a.y) / length
                    for along in stride(from: CGFloat(9), to: length - 7, by: 18) {
                        for side in [CGFloat(-6.3), 6.3] {
                            retailCandidates.append(TreePosition(x: a.x + dx * along - dz * side,
                                                                 z: a.y + dz * along + dx * side,
                                                                 inRetailWalk: true))
                        }
                    }
                }
            }
            guard let id = item["id"] as? Int, CityCivicLandscape.parkIDs.contains(id) else { return }
            let polygon = CityCivicLandscape.path(CityCivicLandscape.points(item), closed: true)
            let bounds = polygon.bounds
            let civic = id == 309157011 || id == 1341042550
            let lawn = CityCivicLandscape.lawnParkIDs.contains(id)
            let interior = CityCivicLandscape.extent.insetBy(dx: 25, dy: 25)
            var row = 0
            for z in stride(from: bounds.minY + 7, to: bounds.maxY - 5, by: 17) {
                row += 1
                for x in stride(from: bounds.minX + 6, to: bounds.maxX - 5, by: 17) {
                    let p = CGPoint(x: x + CGFloat(row % 3) * 2.1, y: z)
                    // Preserve the broad open centre of civic and fountain plazas.
                    if civic && x > bounds.minX + 23 && x < bounds.maxX - 23 { continue }
                    if interior.contains(p), polygon.contains(p) {
                        candidates.append(TreePosition(x: p.x, z: p.y, inLawn: lawn))
                    }
                    // Fill the gaps between existing lawn trees after the primary
                    // rows have reserved their space and the road mask is complete.
                    if lawn {
                        let grove = CGPoint(x: x + 8.5, y: z + 8.5)
                        if interior.contains(grove), polygon.contains(grove) {
                            groveCandidates.append(TreePosition(x: grove.x, z: grove.y,
                                                                inLawn: true, supplemental: true))
                        }
                    }
                }
            }
        }
    }

    static func addFixtures(to root: SCNNode, elements: [[String: Any]]) -> [[SIMD3<Float>]] {
        let skywalkShadows = addSkywalks(to: root, elements: elements)
        addParkedVehicles(to: root)
        // A layered west-facing entrance and cornice for the OSM civic footprint.
        for i in 0..<4 {
            box(3.0 + CGFloat(i) * 1.4, 0.22, 29 + CGFloat(i) * 2.6,
                x: -73 - CGFloat(i) * 0.7, y: 0.25 + CGFloat(3 - i) * 0.22, z: -397,
                color: 0xcfc6b3, to: root)
        }
        box(4.4, 0.7, 33, x: -74, y: 6.6, z: -397, color: 0x9d927e, to: root)
        for z in stride(from: -410.0, through: -384, by: 6.5) {
            box(0.75, 6, 0.75, x: -75.2, y: 3.3, z: z, color: 0xe2d7c1, to: root)
        }
        for lamp in lampBases {
            addLamp(x: lamp.x, z: lamp.y, to: root)
        }
        return skywalkShadows
    }

    private static let lampArmReach: CGFloat = 1.5
    private static let lampBases: [CGPoint] = {
        let candidates = stride(from: -525.0, through: -255, by: 34).flatMap { z in
            [CGPoint(x: -111, y: z), CGPoint(x: 113, y: z)]
        } + stride(from: -235.0, through: 315, by: 36).map { CGPoint(x: $0, y: -231) }
        let footprints: [CGPath] = (CitySceneData.elements ?? []).compactMap { element in
            guard let tags = element["tags"] as? [String: String],
                  tags["building"] != nil, CityStreetSurface.isGround(tags) else { return nil }
            let ring = points(element)
            guard ring.count >= 3 else { return nil }
            let outline = CGMutablePath()
            outline.addLines(between: ring)
            outline.closeSubpath()
            return outline
        }
        return candidates.filter { base in
            let lens = CGPoint(x: base.x + lampArmReach, y: base.y)
            return !footprints.contains { $0.contains(base) || $0.contains(lens) }
        }
    }()

    static var lampLightCenters: [CGPoint] {
        lampBases.map { CGPoint(x: $0.x + lampArmReach, y: $0.y) }
    }

    static func addSkywalks(to root: SCNNode, elements: [[String: Any]]) -> [[SIMD3<Float>]] {
        // The data supplies routes and canopy footprints. Deck and canopy elevations are illustrative.
        let routeIDs = [136814879, 136847471, 1339401653, 513491895, 513491896, 257896676, 1339401656, 1339394552]
        let canopyRoutes = [1339487716: 136814879, 1339487709: 136847471,
                            1339401632: 1339401653, 1339263101: 513491896]
        var routes: [Int: [CGPoint]] = [:], roofs: [Int: [CGPoint]] = [:]
        for item in elements {
            guard let id = item["id"] as? Int, let tags = item["tags"] as? [String: String] else { continue }
            if routeIDs.contains(id), tags["bridge"] == "yes", tags["highway"] == "footway" {
                let route = points(item)
                if route.count >= 2 { routes[id] = route }
            } else if canopyRoutes[id] != nil, tags["building"] == "roof", tags["layer"] == "2" {
                let outline = points(item)
                if outline.count >= 4, outline.first == outline.last { roofs[id] = outline }
            }
        }
        let bridge = SCNNode()
        bridge.name = "xinyi-raised-walkways"
        root.addChildNode(bridge)
        let deckHeight: CGFloat = 6, canopyHeight: CGFloat = 8.95, halfWidth: CGFloat = 2.15
        let carriageways = CityStreetSurface.groundCarriageways(CityStreetSurface.groundCarriagewayRoutes(in: elements))

        func material(_ tint: Int) -> SCNMaterial {
            let surface = SCNMaterial()
            surface.diffuse.contents = CityStreetSurface.color(tint)
            return surface
        }
        let deck = material(0xa8a799), framing = material(0x647573), glass = material(0x91aca7)
        let roofTint = 0xc3c6ba
        let roofTexture = CityRoofDetails.surfaceTexture(tint: roofTint, residential: false)
        let support = material(0xa6a99c)
        let light = material(0xe1cf9c)
        light.name = "city-lit-facade"
        light.emission.contents = CityStreetSurface.color(0xba914d)
        light.emission.intensity = 0

        let canopies = roofs.keys.sorted().compactMap { id -> UIBezierPath? in
            guard let routeID = canopyRoutes[id], routes[routeID] != nil, let outline = roofs[id] else { return nil }
            let outlinePath = path(outline, closed: true)
            let roofShape = SCNShape(path: path(outline.map { CGPoint(x: $0.x, y: -$0.y) }, closed: true),
                                     extrusionDepth: 0.28)
            let roof = material(roofTint)
            if let roofTexture {
                let bounds = outlinePath.bounds
                roof.diffuse.contents = roofTexture
                roof.diffuse.wrapS = .repeat
                roof.diffuse.wrapT = .repeat
                roof.diffuse.mipFilter = .linear
                roof.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(bounds.width / 15),
                                                                    Float(bounds.height / 15), 1)
            }
            roofShape.materials = [roof, deck, framing]
            let node = SCNNode(geometry: roofShape)
            node.name = "skywalk-canopy/\(id)"
            node.eulerAngles.x = -.pi / 2
            node.position.y = Float(canopyHeight)
            bridge.addChildNode(node)
            return outlinePath
        }

        var shadowBands: [[SIMD3<Float>]] = []
        for id in routeIDs {
            guard var route = routes[id] else { continue }
            // Meet the modeled podium where the mapped landmark outline is deeper.
            if id == 1339401653 || id == 136814879 {
                let atStart = id == 1339401653
                let end = atStart ? route[0] : route[route.count - 1]
                if abs(end.x) < 60, (-68 ... -47.5).contains(end.y) {
                    route.insert(CGPoint(x: end.x, y: -47), at: atStart ? 0 : route.count)
                }
            }
            let span = SCNNode()
            span.name = "skywalk-way/\(id)"
            bridge.addChildNode(span)
            for (a, b) in zip(route, route.dropFirst()) {
                let dx = b.x - a.x, dz = b.y - a.y
                let length = hypot(dx, dz)
                guard length > 0.3 else { continue }
                let midpoint = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let cross = CGPoint(x: -dz / length, y: dx / length)
                let section = SCNNode()
                section.position = SCNVector3(Float(midpoint.x), Float(deckHeight), Float(midpoint.y))
                section.eulerAngles.y = Float(-atan2(dz, dx))
                span.addChildNode(section)

                func member(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, x: CGFloat = 0, y: CGFloat,
                            z: CGFloat = 0, _ surface: SCNMaterial, name: String? = nil) {
                    let shape = SCNBox(width: w, height: h, length: d, chamferRadius: 0)
                    shape.firstMaterial = surface
                    let node = SCNNode(geometry: shape)
                    node.position = SCNVector3(Float(x), Float(y), Float(z))
                    node.name = name
                    section.addChildNode(node)
                }
                member(length + 0.2, 0.50, halfWidth * 2, y: 0, deck, name: "skywalk-deck")
                for side: CGFloat in [-1, 1] {
                    let edge = side * (halfWidth - 0.12)
                    member(length + 0.15, 0.85, 0.13, y: 0.68, z: edge, glass)
                    member(length + 0.15, 0.12, 0.23, y: 1.15, z: edge, framing)
                }
                if length >= 8 {
                    let posts = max(1, Int(length / 9))
                    for i in 0..<posts {
                        let x = length * ((CGFloat(i) + 0.5) / CGFloat(posts) - 0.5)
                        let sample = CGPoint(x: midpoint.x + dx / length * x, y: midpoint.y + dz / length * x)
                        let sides = [-halfWidth, halfWidth].map { side in
                            CGPoint(x: sample.x + cross.x * side, y: sample.y + cross.y * side)
                        }
                        guard canopies.contains(where: { roof in sides.allSatisfy(roof.contains) }) else { continue }
                        for side: CGFloat in [-1, 1] {
                            member(0.21, 2.60, 0.24, x: x, y: 1.55, z: side * (halfWidth - 0.12), framing)
                        }
                        member(0.38, 0.15, 3.7, x: x, y: 2.74, light)
                    }
                }
                if length > 14 {
                    // Check the whole pier footprint against ground carriageways.
                    let footprint = CGRect(x: midpoint.x - 0.55, y: midpoint.y - 0.55, width: 1.1, height: 1.1)
                    if !carriageways.intersects(CGPath(rect: footprint, transform: nil)) {
                        member(0.68, 5.75, 0.68, y: -3.125, support, name: "skywalk-pier")
                    }
                }
                let shadowHalfWidth = canopies.contains(where: { $0.contains(midpoint) }) ? halfWidth + 0.4 : halfWidth
                shadowBands.append([a, b].flatMap { point in
                    [-shadowHalfWidth, shadowHalfWidth].map { side in
                        SIMD3(Float(point.x + cross.x * side), Float(deckHeight),
                              Float(point.y + cross.y * side))
                    }
                })
            }
        }
        return shadowBands
    }

    nonisolated fileprivate struct PavingFeature: Sendable {
        enum Style: Sendable {
            case crossing(zebra: Bool), plaza, stone(CGFloat), concrete(CGFloat), path(CGFloat)
        }

        let route: [CGPoint]
        let style: Style
        var retailWidth: CGFloat?
    }

    nonisolated struct PavingInput: Sendable {
        let coverage: CityStreetSurface.GroundCoverage?
        fileprivate let features: [PavingFeature]
        fileprivate let carriageways: [CityStreetSurface.Road]
    }

    static func publicPaving(elements: [[String: Any]], coverage: CityStreetSurface.GroundCoverage? = nil) -> PavingInput {
        let features = elements.compactMap { item -> PavingFeature? in
            guard let tags = item["tags"] as? [String: String], CityStreetSurface.isGround(tags) else { return nil }
            let isPavedPlaza = (item["id"] as? Int).map { pavedParkIDs.contains($0) } == true
            let isWalk = ["footway", "pedestrian", "path"].contains(tags["highway"] ?? "")
            guard isPavedPlaza || isWalk else { return nil }
            let route = points(item)
            guard route.count >= 2 else { return nil }
            if tags["footway"] == "crossing" {
                let zebra = tags["crossing"] == "zebra" || tags["crossing:markings"] == "zebra"
                let marked = zebra || tags["crossing"] == "marked" || tags["crossing:markings"] == "yes"
                return marked ? PavingFeature(route: route, style: .crossing(zebra: zebra)) : nil
            }
            if isPavedPlaza, route.count >= 4, route.first == route.last {
                return PavingFeature(route: route, style: .plaza)
            }
            guard isWalk else { return nil }
            let retailWidth = tags["highway"] == "footway"
                ? (item["id"] as? Int).flatMap { retailWalkWidths[$0] } : nil
            let stone = tags["surface"] == "paving_stones" || tags["footway"] == "sidewalk"
            let width: CGFloat = tags["name"] == "香緹大道" ? 9 : stone ? 4.2 : 2.7
            let style: PavingFeature.Style = if stone {
                .stone(width)
            } else if tags["surface"] == "concrete" {
                .concrete(width)
            } else {
                .path(width)
            }
            return PavingFeature(route: route, style: style, retailWidth: retailWidth)
        }
        return PavingInput(coverage: coverage, features: features, carriageways: CityStreetSurface.groundCarriagewayRoutes(in: elements))
    }

    @concurrent nonisolated static func preparePublicPaving(_ input: PavingInput) async throws -> CGImage? {
        try Task.checkCancellation()
        let image = rasterizePublicPaving(input)
        try Task.checkCancellation()
        return image
    }

    nonisolated static func rasterizePublicPaving(_ input: PavingInput) -> CGImage? {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: extent.width * 2, height: extent.height * 2), format: format).image { output in
            let g = output.cgContext
            g.scaleBy(x: 2, y: 2); g.translateBy(x: -extent.minX, y: -extent.minY)
            drawPublicPaving(g, input: input)
            if let coverage = input.coverage { CityStreetSurface.applyGroundCoverage(coverage, to: g) }
            else { CityStreetSurface.fadeNorthernCoverage(g) }
        }.cgImage
    }

    static func addPublicSpaces(_ bitmap: CGImage?, to root: SCNNode) {
        guard let bitmap else { return }
        let image = UIImage(cgImage: bitmap)
        let plane = SCNPlane(width: extent.width, height: extent.height)
        let material = SCNMaterial(); material.diffuse.contents = image
        material.lightingModel = .lambert; material.writesToDepthBuffer = false
        plane.firstMaterial = material
        let node = SCNNode(geometry: plane)
        node.name = "xinyi-civic-landscape"
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(Float(extent.midX), 0.1, Float(extent.midY))
        root.addChildNode(node)
    }

    nonisolated private static func drawPublicPaving(_ g: CGContext, input: PavingInput) {
        draw101Forecourt(g)
        drawSurfaceParking(g)
        let stoneWalks = CGMutablePath()
        let concreteWalks = CGMutablePath()
        let retailWalks = CGMutablePath()
        let retailEdges = CGMutablePath()
        var markedCrossings: [(line: CGPath, zebra: Bool)] = []
        for feature in input.features {
            if let width = feature.retailWidth {
                let line = CityStreetSurface.polyline(feature.route)
                retailWalks.addPath(line.copy(strokingWithWidth: width, lineCap: .round,
                                              lineJoin: .round, miterLimit: 2))
                retailEdges.addPath(line.copy(strokingWithWidth: width + 1.1, lineCap: .round,
                                              lineJoin: .round, miterLimit: 2))
            }
            switch feature.style {
            case .crossing(let zebra):
                markedCrossings.append((CityStreetSurface.polyline(feature.route), zebra))
            case .plaza:
                let polygon = CityStreetSurface.polyline(feature.route, closed: true)
                g.saveGState(); g.addPath(polygon); g.clip()
                CityStreetSurface.drawPavers(g, origin: extent.origin, colors: pavingColors)
                g.setStrokeColor(CityStreetSurface.color(0xe5deca).cgColor)
                g.setLineWidth(3.2)
                g.addPath(polygon); g.strokePath()
                g.restoreGState()
            case .stone(let width), .concrete(let width):
                let line = CityStreetSurface.polyline(feature.route)
                let outline = line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 2)
                if case .stone = feature.style {
                    stoneWalks.addPath(outline)
                } else {
                    concreteWalks.addPath(outline)
                }
            case .path(let width):
                g.setLineWidth(width); g.setLineCap(.round); g.setLineJoin(.round)
                g.setStrokeColor(CityStreetSurface.color(0xe9dfc9).cgColor)
                g.addPath(CityStreetSurface.polyline(feature.route)); g.strokePath()
            }
        }
        g.setFillColor(CityStreetSurface.color(0x9a9687).cgColor)
        g.addPath(retailEdges); g.fillPath()
        for (walks, colors, grout) in [(concreteWalks, concretePavingColors, 0xc8bfab),
                                      (stoneWalks, walkPavingColors, 0xc8ae93),
                                      (retailWalks, walkPavingColors, 0xc8ae93)] where !walks.isEmpty {
            g.saveGState(); g.addPath(walks); g.clip()
            CityStreetSurface.drawPavers(g, origin: extent.origin, colors: colors, grout: grout)
            g.restoreGState()
        }

        // Preserve the same asphalt widths used by the underlying map. The
        // public-space texture is transparent wherever a mapped road crosses it.
        let carriageways = CityStreetSurface.groundCarriageways(input.carriageways)
        g.saveGState()
        g.setBlendMode(.destinationOut)
        g.setFillColor(UIColor.black.cgColor)
        g.addPath(carriageways); g.fillPath()
        g.restoreGState()

        g.saveGState(); g.addPath(carriageways); g.clip()
        for crossing in markedCrossings {
            g.setLineCap(.butt)
            g.setLineWidth(2.7)
            g.setLineDash(phase: 0, lengths: crossing.zebra ? [0.55, 0.6] : [])
            g.setStrokeColor(CityStreetSurface.color(0xe9dfc9).withAlphaComponent(crossing.zebra ? 0.88 : 0.36).cgColor)
            g.addPath(crossing.line); g.strokePath()
        }
        g.restoreGState()
    }

    // Surface use is corroborated by Taipei parking dataset TPE1667 and the
    // 2024 NLSC orthophoto. Bays and parked vehicles are illustrative.
    nonisolated private struct ParkingRow: Sendable {
        let start: CGPoint
        let count: Int
        var alongZ = false

        func center(_ index: Int) -> CGPoint {
            let distance = CGFloat(index) * 2.7
            return alongZ ? .init(x: start.x, y: start.y + distance) : .init(x: start.x + distance, y: start.y)
        }
    }

    nonisolated private static let parkingRows = [
        ParkingRow(start: .init(x: 4, y: 143), count: 14),
        ParkingRow(start: .init(x: 5, y: 154), count: 16),
        ParkingRow(start: .init(x: 5, y: 160), count: 16),
        ParkingRow(start: .init(x: 4, y: 172), count: 16),
        ParkingRow(start: .init(x: 37, y: 181), count: 8, alongZ: true),
        ParkingRow(start: .init(x: 51, y: 181), count: 8, alongZ: true),
        ParkingRow(start: .init(x: 68, y: 183), count: 7, alongZ: true),
    ]

    nonisolated static let surfaceParkingPolygon: [CGPoint] = [
            .init(x: -3, y: 138), .init(x: 58, y: 138), .init(x: 66, y: 148),
            .init(x: 66, y: 174), .init(x: 78, y: 178), .init(x: 78, y: 204),
            .init(x: 24, y: 204), .init(x: 24, y: 177), .init(x: -3, y: 177),
    ]

    nonisolated private static func drawSurfaceParking(_ g: CGContext) {
        let outline = CityStreetSurface.polyline(surfaceParkingPolygon, closed: true)
        g.saveGState()
        g.addPath(outline); g.clip()
        g.setFillColor(CityStreetSurface.color(0x737477).cgColor)
        g.fill(outline.boundingBoxOfPath)
        g.setStrokeColor(CityStreetSurface.color(0xa4a09a).cgColor)
        g.setLineWidth(1.4)
        g.addPath(outline); g.strokePath()
        g.setStrokeColor(CityStreetSurface.color(0xd8d1bc).withAlphaComponent(0.8).cgColor)
        g.setLineWidth(0.23)
        for row in parkingRows {
            for index in 0..<row.count {
                let center = row.center(index)
                let size = row.alongZ ? CGSize(width: 5.4, height: 2.7) : CGSize(width: 2.7, height: 5.4)
                g.stroke(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                width: size.width, height: size.height))
            }
        }
        g.restoreGState()
    }

    private static func addParkedVehicles(to root: SCNNode) {
        let layer = SCNNode()
        layer.name = "xinyi-surface-parking"
        let fleet = [0xe2e1d9, 0xaeb6bd, 0x515c6b, 0x915a51, 0x596e6b].enumerated().map { index, color in
            CityStreetTraffic.vehicleModel(color: color, taxi: false, tall: index == 2, parked: true)
        }
        for (rowIndex, row) in parkingRows.enumerated() {
            for index in 0..<row.count {
                let seed = rowIndex * 31 + index * 17
                guard seed % 11 < 4 else { continue }
                let center = row.center(index)
                let car = fleet[(seed / 3) % fleet.count].clone()
                car.simdPosition = SIMD3(Float(center.x), 0.12, Float(center.y))
                car.eulerAngles.y = (row.alongZ ? .pi / 2 : 0) + (seed.isMultiple(of: 2) ? .pi : 0)
                layer.addChildNode(car)
            }
        }
        root.addChildNode(layer)
    }

    // Paved areas flank the podium at the two road corners.
    nonisolated static let forecourtPolygons: [[CGPoint]] = [
            [.init(x: -84, y: 59), .init(x: -64, y: 53), .init(x: -57, y: 82), .init(x: -17, y: 90),
             .init(x: -19, y: 95), .init(x: -82, y: 92)],
            [.init(x: 20, y: 73), .init(x: 78, y: 69), .init(x: 85, y: 90), .init(x: 79, y: 97),
             .init(x: 24, y: 95)],
    ]

    nonisolated private static func draw101Forecourt(_ g: CGContext) {
        g.saveGState()
        for court in forecourtPolygons { g.addPath(CityStreetSurface.polyline(court, closed: true)) }
        g.clip()
        CityStreetSurface.drawPavers(g, origin: extent.origin,
                                    colors: [0xc0b7aa, 0xbbb0a3, 0xcac0b0, 0xb5aa9e], grout: 0xaa9d8f)
        for bed in [CGRect(x: 38, y: 80, width: 43, height: 5.8),
                    CGRect(x: 48, y: 91, width: 26, height: 3.5)] {
            let border = CGPath(roundedRect: bed, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            g.setFillColor(CityStreetSurface.color(0xe1d3b7).cgColor)
            g.addPath(border); g.fillPath()
            let soil = CGPath(roundedRect: bed.insetBy(dx: 0.6, dy: 0.6), cornerWidth: 1, cornerHeight: 1,
                              transform: nil)
            g.setFillColor(CityStreetSurface.color(0x647651).cgColor)
            g.addPath(soil); g.fillPath()
        }
        g.restoreGState()
    }

    private static func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, x: CGFloat, y: CGFloat, z: CGFloat,
                            color: Int, to root: SCNNode) {
        let shape = SCNBox(width: w, height: h, length: d, chamferRadius: min(0.12, h / 4))
        shape.firstMaterial?.diffuse.contents = CityStreetSurface.color(color)
        let node = SCNNode(geometry: shape)
        node.position = SCNVector3(Float(x), Float(y), Float(z)); root.addChildNode(node)
    }

    private static func addLamp(x: CGFloat, z: CGFloat, to root: SCNNode) {
        box(0.19, 6.4, 0.19, x: x, y: 3.2, z: z, color: 0x5c6a68, to: root)
        box(1.9, 0.16, 0.17, x: x + 0.8, y: 6.25, z: z, color: 0x6b7570, to: root)
        let lens = SCNPlane(width: 1.5, height: 0.47)
        let material = SCNMaterial(); material.diffuse.contents = CityStreetSurface.color(0xf3df9c)
        material.lightingModel = .constant; lens.firstMaterial = material
        let node = SCNNode(geometry: lens); node.name = "city-lamp"
        node.eulerAngles.x = -.pi / 2; node.position = SCNVector3(Float(x + lampArmReach), 6.15, Float(z))
        root.addChildNode(node)
    }
}
#endif
