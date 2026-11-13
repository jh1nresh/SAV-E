#if SAVVY_CITY_MVP
import UIKit
import SceneKit
import simd

/// A bounded street atlas. Surface marks and the moving cars use the same OSM lane paths.
@MainActor
enum CityStreetSurface {
    static let altitude: CGFloat = 0.87
    nonisolated static let bounds = CGRect(x: -540, y: -650, width: 1_100, height: 1_030)
    static let nightLightsName = "xinyi-street-light-atlas"
    nonisolated private static let asphalt = color(0x565568)
    nonisolated private static let paint = color(0xf2ece0)
    // The eastbound and westbound carriageways end inside the ground feather.
    nonisolated private static let easternHandoffWays: Set<Int> = [229070402, 138265881]
    // These southern caps meet streets that continue in the native map.
    nonisolated private static let southernHandoffWays: Set<Int> = [454679253, 258816631]
    nonisolated private static let easternRampWay = 49749048
    private static let detailedRoadNames: Set<String> = [
        "信義路五段", "市府路", "松智路", "松勤街", "松壽路", "松廉路", "松仁路", "仁愛路四段",
    ]

    nonisolated fileprivate enum GroundRoadKind: Int, Sendable {
        case footpath, service, local, arterial

        var tint: UIColor {
            switch self {
            case .footpath: color(0xf2ede0)
            case .service: color(0xaaa295)
            case .local: color(0x797584)
            case .arterial: asphalt
            }
        }
    }

    nonisolated struct Road: Sendable {
        let id: Int
        let name: String
        let path: [CGPoint] // east, south
        let width: CGFloat

        var isBoulevard: Bool { name == "信義路五段" }
        var isSideStreet: Bool { name == "松智路" || name == "市府路" }
    }

    private struct GroundVertex: Hashable {
        let x: CGFloat
        let z: CGFloat

        init(_ point: CGPoint) {
            x = point.x
            z = point.y
        }
    }

    /// Public source geometry only; the atlas rectangle carries no ownership.
    /// Closed City Hall sidewalk 373794831 bounds its known civic forecourt.
    nonisolated struct GroundOwnership: Sendable {
        let polygons: [[CGPoint]]
        let corridors: [Road]
    }

    /// One immutable world-space alpha field is sampled by every ground atlas.
    nonisolated struct GroundCoverage: Sendable {
        let image: CGImage
        let extent: CGRect
        let feather: CGFloat
    }

    static func groundOwnership(elements: [[String: Any]]) -> GroundOwnership {
        var polygons: [[CGPoint]] = []
        var corridors: [Road] = []
        for element in elements {
            guard let tags = element["tags"] as? [String: String],
                  let geometry = element["geometry"] as? [[String: Double]] else { continue }
            let points = groundPath(geometry)
            guard points.count == geometry.count, points.count >= 2 else { continue }
            let id = element["id"] as? Int
            let closed = points.count >= 4 && points.first == points.last
            let building = tags["building"] != nil && tags["building"] != "no"
            let publicArea = ["park", "garden"].contains(tags["leisure"] ?? "")
                || (tags["area"] == "yes" && tags["highway"] == "pedestrian")
                || id == 373794831
            if closed && (building || (publicArea && isGround(tags))) { polygons.append(points) }
            if let style = groundRoadStyle(tags) {
                // Exactly the detailed atlas's 5 m sidewalk on either side.
                // Footpaths use their mapped/illustrative width, not a road-size buffer.
                let width = style.width + (style.kind == .arterial || style.kind == .local ? 10 : 0)
                corridors.append(Road(id: id ?? 0, name: tags["name"] ?? "", path: points, width: width))
            }
        }
        // Reuse existing authored, source-documented public-space outlines.
        // They are geometry detail, not new navigation/entrance claims.
        polygons.append(contentsOf: CityCivicLandscape.forecourtPolygons)
        polygons.append(CityCivicLandscape.surfaceParkingPolygon)
        return GroundOwnership(polygons: polygons, corridors: corridors)
    }

    @concurrent nonisolated static func prepareGroundCoverage(_ ownership: GroundOwnership) async throws -> GroundCoverage? {
        try Task.checkCancellation()
        let coverage = rasterizeGroundCoverage(ownership)
        try Task.checkCancellation()
        return coverage
    }

    nonisolated static func rasterizeGroundCoverage(_ ownership: GroundOwnership) -> GroundCoverage? {
        // Include every known feature plus padding: storage edges cannot turn
        // into an invented district boundary. 1 px/m is shared by all atlases.
        var extent = districtExtent
        for polygon in ownership.polygons {
            for p in polygon { extent = extent.union(CGRect(x: p.x, y: p.y, width: 1, height: 1)) }
        }
        for road in ownership.corridors {
            for p in road.path {
                extent = extent.union(CGRect(x: p.x - road.width / 2, y: p.y - road.width / 2,
                                              width: road.width, height: road.width))
            }
        }
        let feather: CGFloat = 4
        extent = extent.insetBy(dx: -feather - 2, dy: -feather - 2).integral
        // Validate before converting to Int: finite but distant source coordinates
        // must fail explicitly instead of overflowing or allocating unbounded memory.
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0,
              extent.width <= 4096, extent.height <= 4096 else { return nil }
        let width = Int(extent.width), height = Int(extent.height)
        var bytes = [UInt8](repeating: 0, count: width * height)
        let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let g = CGContext(data: storage.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            // Raw bitmap contexts use an upward y-axis; every existing atlas
            // uses UIKit's downward y-axis / north-first image rows.
            g.translateBy(x: 0, y: CGFloat(height))
            g.scaleBy(x: 1, y: -1)
            g.translateBy(x: -extent.minX, y: -extent.minY)
            g.setShouldAntialias(false)
            g.setFillColor(gray: 1, alpha: 1)
            // Fill separately: opposite source windings cannot punch holes in a union.
            for polygon in ownership.polygons {
                g.addPath(polyline(polygon, closed: true)); g.fillPath()
            }
            for road in ownership.corridors {
                g.addPath(polyline(road.path).copy(strokingWithWidth: road.width,
                           lineCap: .round, lineJoin: .round, miterLimit: 2)); g.fillPath()
            }
            return true
        }
        guard drawn else { return nil }
        // Distance to the UNION, not to each overlapping shape. Known surfaces
        // stay fully opaque, including narrow footpaths. Only a bounded 4 m
        // transition outside their actual edges fades; unknown lots stay clear.
        var distance = bytes.map { $0 == 0 ? Float(feather) : Float(0) }
        let diagonal: Float = 1.41421356
        for y in 1..<height {
            for x in 1..<(width - 1) {
                let i = y * width + x
                distance[i] = min(distance[i], distance[i - 1] + 1,
                                  distance[i - width] + 1,
                                  min(distance[i - width - 1], distance[i - width + 1]) + diagonal)
            }
        }
        for y in stride(from: height - 2, through: 0, by: -1) {
            for x in stride(from: width - 2, through: 1, by: -1) {
                let i = y * width + x
                distance[i] = min(distance[i], distance[i + 1] + 1,
                                  distance[i + width] + 1,
                                  min(distance[i + width - 1], distance[i + width + 1]) + diagonal)
            }
        }
        for i in bytes.indices {
            let t = 1 - min(1, max(0, distance[i] / Float(feather)))
            bytes[i] = UInt8((255 * t * t * (3 - 2 * t)).rounded())
        }
        // Premultiplied white RGBA carries actual alpha (not grayscale luminance).
        var rgba = [UInt8](repeating: 0, count: bytes.count * 4)
        for i in bytes.indices { for channel in 0..<4 { rgba[i * 4 + channel] = bytes[i] } }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return GroundCoverage(image: image, extent: extent, feather: feather)
    }

    nonisolated static func applyGroundCoverage(_ coverage: GroundCoverage, to g: CGContext) {
        g.saveGState()
        g.setBlendMode(.destinationIn)
        // The shared image contains every atlas extent, including transparent
        // unknown land, so destination-in clears the entire complement too.
        UIImage(cgImage: coverage.image).draw(in: coverage.extent, blendMode: .destinationIn, alpha: 1)
        g.restoreGState()
    }

    nonisolated struct DistrictGround: Sendable {
        let coverage: GroundCoverage?
        fileprivate let parks: [[CGPoint]]
        fileprivate let roads: [(id: Int?, path: [CGPoint], kind: GroundRoadKind, width: CGFloat)]
    }

    nonisolated private static let districtExtent: CGRect = {
        let halfExtent = CGFloat(CityDistrictCamera.groundHalfExtent)
        return CGRect(x: -halfExtent, y: -halfExtent, width: halfExtent * 2, height: halfExtent * 2)
    }()

    @concurrent nonisolated static func prepareDistrictGround(_ ground: DistrictGround) async throws -> CGImage? {
        try Task.checkCancellation()
        let image = rasterizeDistrictGround(ground)
        try Task.checkCancellation()
        return image
    }

    nonisolated static func rasterizeDistrictGround(_ ground: DistrictGround) -> CGImage? {
        let extent = districtExtent
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: extent.size, format: format).image { output in
            let g = output.cgContext
            g.translateBy(x: -extent.minX, y: -extent.minY)
            drawDistrictGround(g, ground: ground, extent: extent)
        }.cgImage
    }

    static func addDistrictGround(_ bitmap: CGImage?, to root: SCNNode) {
        guard let bitmap else { return }
        let ground = addGroundPlane(UIImage(cgImage: bitmap), in: districtExtent,
                                    height: 0, renderingOrder: -1, to: root)
        // The district floor is the first surface over the clear SceneKit background.
        // Premultiply its shaded color so feathered pixels reveal the native map.
        ground.geometry?.firstMaterial?.shaderModifiers = [.fragment: """
        #pragma transparent
        #pragma body
        _output.color.rgb *= _output.color.a;
        """]
    }

    static func districtGround(elements: [[String: Any]], coverage: GroundCoverage? = nil) -> DistrictGround {
        var parks: [[CGPoint]] = []
        var roads: [(id: Int?, path: [CGPoint], kind: GroundRoadKind, width: CGFloat)] = []
        for element in elements {
            guard let tags = element["tags"] as? [String: String],
                  tags["leisure"] == "park" || tags["highway"] != nil,
                  let geometry = element["geometry"] as? [[String: Double]] else { continue }
            let path = groundPath(geometry)
            guard path.count == geometry.count, path.count >= 2 else { continue }
            if tags["leisure"] == "park", path.count >= 4 {
                parks.append(path)
            } else if let style = groundRoadStyle(tags) {
                roads.append((element["id"] as? Int, path, style.kind, style.width))
            }
        }

        return DistrictGround(coverage: coverage, parks: parks, roads: roads)
    }

    nonisolated private static func drawDistrictGround(_ g: CGContext, ground: DistrictGround, extent: CGRect) {
        let roads = ground.roads
        drawGroundGrain(g, in: extent, tint: 0xe0d8c9)
        g.saveGState()
        for park in ground.parks {
            g.addPath(polyline(park))
        }
        g.clip()
        // Public streets still draw above parks whose source outlines overlap the carriageway.
        drawGroundGrain(g, in: extent, tint: 0x86a668)
        g.restoreGState()
        for road in roads.sorted(by: {
            ($0.kind.rawValue, $0.width) < ($1.kind.rawValue, $1.width)
        }) {
            stroke(g, road.path, width: road.width, color: road.kind.tint)
        }
        let feather = CGFloat(CityDistrictCamera.groundFeather)
        g.saveGState()
        if let ramp = roads.first(where: { $0.id == easternRampWay }) {
            let region = CGMutablePath()
            region.addRect(extent)
            region.addPath(polyline(ramp.path).copy(strokingWithWidth: ramp.width + 1,
                                                    lineCap: .round, lineJoin: .round, miterLimit: 2))
            // The ramp remains mapped beyond both carriageway endpoints.
            g.addPath(region); g.clip(using: .evenOdd)
        }
        for road in roads {
            guard let id = road.id, let first = road.path.first, let last = road.path.last else { continue }
            let east = easternHandoffWays.contains(id)
            guard east || southernHandoffWays.contains(id) else { continue }
            func outwardCoordinate(_ point: CGPoint) -> CGFloat { east ? point.x : point.y }
            let outwardAtStart = outwardCoordinate(first) > outwardCoordinate(last)
            let end = outwardAtStart ? first : last
            let inside = outwardAtStart ? road.path[1] : road.path[road.path.count - 2]
            let limit = east ? extent.maxX : extent.maxY
            guard outwardCoordinate(end) > limit - feather, outwardCoordinate(end) > outwardCoordinate(inside),
                  !roads.contains(where: { $0.id != id && $0.kind != .footpath && $0.path.contains(end) }) else { continue }
            revealNativeRoad(g, end: end, inside: inside, roadWidth: road.width,
                             feather: feather, returnsAfterJunction: !east)
        }
        g.restoreGState()
        if let coverage = ground.coverage { applyGroundCoverage(coverage, to: g) }
        else {
            fadeNorthernCoverage(g)
            fadeBoundary(g, bounds: extent, horizontal: feather, vertical: feather)
        }
    }

    nonisolated private static func revealNativeRoad(_ g: CGContext, end: CGPoint, inside: CGPoint,
                                         roadWidth: CGFloat, feather: CGFloat, returnsAfterJunction: Bool) {
        let dx = end.x - inside.x, dz = end.y - inside.y
        let lead = min(64, hypot(dx, dz))
        guard lead > 8 else { return }
        let innerWidth = roadWidth / 2 + 1.5
        let outerWidth = innerWidth + (returnsAfterJunction ? 10 : 6)
        let space = CGColorSpaceCreateDeviceRGB()
        let black = UIColor.black.cgColor, clear = UIColor.clear.cgColor
        let sideFeather = (outerWidth - innerWidth) / (outerWidth * 2)
        let tail = returnsAfterJunction ? 36 : feather
        let alongEnd: CGFloat = returnsAfterJunction ? tail : -4
        let alongColors = returnsAfterJunction ? [clear, black, black, clear] : [clear, black]
        let alongLocations: [CGFloat] = returnsAfterJunction
            ? [0, (lead - 4) / (lead + tail), (lead + 7) / (lead + tail), 1] : [0, 1]
        guard let along = CGGradient(colorsSpace: space, colors: alongColors as CFArray,
                                     locations: alongLocations),
              let across = CGGradient(colorsSpace: space, colors: [clear, black, black, clear] as CFArray,
                                      locations: [0, sideFeather, 1 - sideFeather, 1]) else { return }

        g.saveGState()
        g.translateBy(x: end.x, y: end.y)
        g.rotate(by: atan2(dz, dx))
        g.clip(to: CGRect(x: -lead, y: -outerWidth, width: lead + tail, height: outerWidth * 2))
        g.setBlendMode(.destinationOut)
        // The southern reveal opens the native junction locally and softens
        // back into the surrounding parcel beyond it.
        g.beginTransparencyLayer(auxiliaryInfo: nil)
        g.drawLinearGradient(along, start: .init(x: -lead, y: 0), end: .init(x: alongEnd, y: 0),
                             options: returnsAfterJunction ? [] : [.drawsAfterEndLocation])
        g.setBlendMode(.destinationIn)
        g.drawLinearGradient(across, start: .init(x: 0, y: -outerWidth), end: .init(x: 0, y: outerWidth), options: [])
        g.endTransparencyLayer()
        g.restoreGState()
    }

    private static func groundRoadStyle(_ tags: [String: String]) -> (kind: GroundRoadKind, width: CGFloat)? {
        guard let highway = tags["highway"], isGround(tags) else { return nil }
        let width = roadWidth(tags)
        if let name = tags["name"], detailedRoadNames.contains(name) { return (.arterial, width) }
        switch highway {
        case "footway", "path", "pedestrian", "steps", "cycleway":
            return (.footpath, width)
        case "platform":
            return (.footpath, 3)
        case "service":
            // Driveways are visible connections but should not read like public streets.
            let taggedWidth = tags["width"].flatMap { Double($0.replacingOccurrences(of: " m", with: "")) }
            let typicalWidth: Double
            switch tags["service"] {
            case "driveway": typicalWidth = 4.2
            case "alley": typicalWidth = 3.5
            default: typicalWidth = 5.4
            }
            let actual = taggedWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? typicalWidth
            return (.service, CGFloat(min(6.5, max(2.7, actual))))
        case "residential", "unclassified", "living_street", "road":
            return (.local, width)
        case "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
             "secondary", "secondary_link", "tertiary", "tertiary_link", "busway":
            return (.arterial, width)
        default:
            return nil
        }
    }

    private static func groundPath(_ geometry: [[String: Double]]) -> [CGPoint] {
        geometry.compactMap { point in
            guard let lon = point["lon"], let lat = point["lat"], lon.isFinite, lat.isFinite else { return nil }
            return CGPoint(x: (lon - CityScenePlace.originLongitude) * 100_850,
                           y: -(lat - CityScenePlace.originLatitude) * 111_195)
        }
    }

    static func isGround(_ tags: [String: String]) -> Bool {
        let layer = Double(tags["layer"] ?? "0") ?? 0
        let level = tags["level"].flatMap(Double.init)
        return layer >= 0 && (layer == 0 || level == 0) && tags["tunnel"] != "yes"
            && tags["bridge"] != "yes" && (level ?? 0) == 0
    }

    static func roadWidth(_ tags: [String: String]) -> CGFloat {
        if tags["name"] == "信義路五段" { return 13.4 }
        if tags["name"] == "松勤街" { return 8.2 }
        if ["footway", "path", "pedestrian", "steps", "cycleway"].contains(tags["highway"] ?? "") { return 3 }
        if let lanes = tags["lanes"].flatMap(Int.init), lanes > 0 { return CGFloat(min(lanes, 8)) * 3.05 + 1.4 }
        return ["primary", "secondary", "trunk"].contains(tags["highway"] ?? "") ? 13.4 : 9.4
    }

    private static let streetNamesNode = "xinyi-street-names"
    nonisolated private static let streetNameHeight: CGFloat = 8.8
    nonisolated private final class StreetNameAnchor: SCNNode {
        let alongLimit: Double
        let acrossLimit: Double

        init(alongLimit: CGFloat, acrossLimit: CGFloat) {
            self.alongLimit = Double(alongLimit)
            self.acrossLimit = Double(acrossLimit)
            super.init()
        }

        required init?(coder: NSCoder) { nil }
    }

    // The hints distribute repeated names across the street grid. Each
    // decal still needs a nearby straight section in the bundled road data.
    nonisolated private static let streetNameHints: [(String, CGPoint)] = [
        ("市府路", .init(x: -92, y: 43)), ("市府路", .init(x: -90, y: -335)),
        ("松智路", .init(x: 96, y: 57)), ("松智路", .init(x: 103, y: -326)),
        ("松壽路", .init(x: 10, y: -213)), ("松廉路", .init(x: 170, y: -4)),
        ("信義路五段", .init(x: -151, y: 106)), ("信義路五段", .init(x: 0, y: 111)),
        ("信義路五段", .init(x: 150, y: 114)), ("松仁路", .init(x: 400, y: -340)),
    ]

    nonisolated private static func streetNameWidth(_ name: String) -> CGFloat {
        CGFloat(name.count) * 8 + 4
    }

    private static func addStreetNames(to root: SCNNode, roads: [Road], images: [String: CGImage]) {
        let group = SCNNode()
        group.name = streetNamesNode
        var textures: [String: SCNMaterial] = [:]
        for (name, hint) in streetNameHints {
            let width = streetNameWidth(name)
            var closest = 16.0
            var placement: (center: CGPoint, angle: CGFloat, along: CGFloat, across: CGFloat)?
            for road in roads where road.name == name && road.width >= streetNameHeight {
                for (a, b) in zip(road.path, road.path.dropFirst()) {
                    let dx = b.x - a.x, dz = b.y - a.y
                    let length = hypot(dx, dz)
                    guard length >= width + 8 else { continue }
                    let margin = (width / 2 + 4) / length
                    let t = ((hint.x - a.x) * dx + (hint.y - a.y) * dz) / (length * length)
                    let along = min(1 - margin, max(margin, t))
                    let center = CGPoint(x: a.x + along * dx, y: a.y + along * dz)
                    let distance = hypot(center.x - hint.x, center.y - hint.y)
                    if distance < closest {
                        closest = distance
                        let room = 2 * min(along, 1 - along) * length - 3
                        placement = (center, atan2(dz, dx), max(1, room / width),
                                     max(1, (road.width - 0.5) / streetNameHeight))
                    }
                }
            }
            guard let placement, let image = images[name] else { continue }
            let material = textures[name] ?? streetNameMaterial(image)
            textures[name] = material
            let plane = SCNPlane(width: width, height: streetNameHeight)
            plane.firstMaterial = material
            let anchor = StreetNameAnchor(alongLimit: placement.along, acrossLimit: placement.across)
            anchor.name = name
            anchor.simdPosition = SIMD3(Float(placement.center.x), 0.96, Float(placement.center.y))
            anchor.simdOrientation = simd_quatf(angle: -Float(placement.angle), axis: SIMD3(0, 1, 0))
                * simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
            let decal = SCNNode(geometry: plane)
            decal.opacity = 0
            decal.renderingOrder = 4
            anchor.addChildNode(decal)
            group.addChildNode(anchor)
        }
        root.addChildNode(group)
    }

    nonisolated private static func rasterizeStreetName(_ name: String) -> CGImage? {
        let size = CGSize(width: streetNameWidth(name) * 6, height: streetNameHeight * 6)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let font = UIFont.systemFont(ofSize: 40, weight: .bold)
            let text = name as NSString
            let metrics = text.size(withAttributes: [.font: font])
            let origin = CGPoint(x: (size.width - metrics.width) / 2, y: (size.height - metrics.height) / 2)
            let fill = color(0xfdf9ec)
            text.draw(at: origin, withAttributes: [.font: font, .strokeColor: color(0x35363f), .strokeWidth: 6])
            text.draw(at: origin, withAttributes: [.font: font, .foregroundColor: fill])
        }.cgImage
    }

    private static func streetNameMaterial(_ image: CGImage) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = UIImage(cgImage: image)
        material.diffuse.mipFilter = .linear
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        return material
    }

    static func streetNameDisplay(glyphWidth: Double, sceneCoverage: Double, alongLimit: Double,
                                  acrossLimit: Double) -> (along: Double, across: Double, opacity: Double) {
        let magnification = min(1.65, max(1, 7.6 / max(0.1, glyphWidth)))
        let across = min(magnification, acrossLimit)
        let along = min(magnification, alongLimit, across * 1.35)
        func fade(_ value: Double) -> Double {
            let t = min(1, max(0, value))
            return t * t * (3 - 2 * t)
        }
        let readable = fade((glyphWidth * along - 4.3) / 3.3)
        // A native road label can still show through the partly visible model.
        let covered = fade((sceneCoverage - 0.82) / 0.16)
        return (along, across, readable * covered)
    }

    static func orientStreetNames(in root: SCNNode, projection: CityDistrictCamera.Projection,
                                  sceneOpacity: Double, blend: CityDistrictCamera.SceneBlend?) {
        guard let group = root.childNode(withName: streetNamesNode, recursively: false) else { return }
        for node in group.childNodes {
            guard let anchor = node as? StreetNameAnchor, let decal = anchor.childNodes.first else { continue }
            let center = SIMD3<Double>(anchor.simdPosition)
            let axis = SIMD3<Double>(anchor.simdOrientation.act(SIMD3(1, 0, 0)))
            guard let a = projection.point(at: center - 6 * axis),
                  let b = projection.point(at: center + 6 * axis),
                  let point = projection.point(at: center) else {
                decal.opacity = 0
                continue
            }
            let angle = atan2(b.y - a.y, b.x - a.x)
            // Prefer vertical text that reads from bottom to top. Fade across
            // the two flip points so rotating the map cannot snap the glyphs.
            let upright = cos(angle + .pi / 18)
            decal.eulerAngles.z = upright < 0 ? .pi : 0
            let glyphWidth = hypot(b.x - a.x, b.y - a.y) * 8 / 12
            let coverage = blend?.opacity(at: point) ?? sceneOpacity
            let display = streetNameDisplay(glyphWidth: glyphWidth, sceneCoverage: coverage,
                                            alongLimit: anchor.alongLimit, acrossLimit: anchor.acrossLimit)
            decal.scale = SCNVector3(Float(display.along), Float(display.across), 1)
            let turning = min(1, abs(upright) / 0.10)
            decal.opacity = display.opacity * turning
        }
    }

    static func roads() -> [Road] {
        (CitySceneData.elements ?? []).compactMap { element in
            guard let tags = element["tags"] as? [String: String],
                  let name = tags["name"],
                  detailedRoadNames.contains(name),
                  isGround(tags),
                  let id = element["id"] as? Int, let points = element["geometry"] as? [[String: Double]] else { return nil }
            let path = groundPath(points)
            guard path.count == points.count, path.count >= 2 else { return nil }
            let width = roadWidth(tags)
            return Road(id: id, name: name, path: path, width: width)
        }
    }

    static func crossingRoads(roads: [Road], elements: [[String: Any]]) -> [Road] {
        let vertices = Set(roads.flatMap { $0.path.map(GroundVertex.init) })
        return elements.compactMap { element in
            guard let tags = element["tags"] as? [String: String],
                  !detailedRoadNames.contains(tags["name"] ?? ""),
                  let style = groundRoadStyle(tags), style.kind == .local || style.kind == .arterial,
                  let geometry = element["geometry"] as? [[String: Double]] else { return nil }
            let path = groundPath(geometry)
            guard path.count == geometry.count, path.count >= 2,
                  path.contains(where: { vertices.contains(GroundVertex($0)) }) else { return nil }
            return Road(id: element["id"] as? Int ?? 0, name: tags["name"] ?? "", path: path, width: style.width)
        }
    }

    nonisolated static func crossingCarriageways(_ roads: [Road]) -> CGPath {
        union(roads, extra: 0.7)
    }

    static func groundCarriagewayRoutes(in elements: [[String: Any]]) -> [Road] {
        elements.compactMap { item in
            guard let tags = item["tags"] as? [String: String],
                  let style = groundRoadStyle(tags), style.kind != .footpath,
                  let geometry = item["geometry"] as? [[String: Double]] else { return nil }
            let points = groundPath(geometry)
            guard points.count == geometry.count, points.count >= 2 else { return nil }
            return Road(id: item["id"] as? Int ?? 0, name: tags["name"] ?? "", path: points, width: style.width)
        }
    }

    nonisolated static func groundCarriageways(_ roads: [Road]) -> CGPath {
        union(roads, extra: 0.5)
    }

    static var cyclewayPath: [CGPoint] {
        guard let element = CitySceneData.elements?.first(where: { ($0["id"] as? Int) == 1339835158 }),
              let geometry = element["geometry"] as? [[String: Double]] else { return [] }
        return groundPath(geometry)
    }

    nonisolated struct RoadTextures: Sendable {
        let surface: CGImage
        let names: [String: CGImage]
    }

    // Transfer immutable bitmaps. Scene nodes and the untyped source
    // dataset stay on MainActor.
    @concurrent nonisolated static func prepareRoadTexture(roads: [Road], crossings: [Road],
                                                           cycleway: [CGPoint], coverage: GroundCoverage? = nil) async throws -> RoadTextures? {
        try Task.checkCancellation()
        let textures = rasterizeRoadTexture(roads: roads, crossings: crossings, cycleway: cycleway, coverage: coverage)
        try Task.checkCancellation()
        return textures
    }

    nonisolated static func rasterizeRoadTexture(roads: [Road], crossings: [Road], cycleway: [CGPoint], coverage: GroundCoverage? = nil) -> RoadTextures? {
        guard !roads.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let surface = UIGraphicsImageRenderer(size: size, format: format).image { output in
            let g = output.cgContext
            g.scaleBy(x: scale, y: scale)
            g.translateBy(x: -bounds.minX, y: -bounds.minY)

            let walk = union(roads, extra: 10)
            g.saveGState()
            g.addPath(walk); g.clip()
            drawPavers(g, origin: bounds.origin, colors: [0xc6ae95, 0xcdb69d, 0xd4bda3, 0xbea78f, 0xd2baa1],
                       grout: 0xb8a18a)
            // A separate strip beside the curb reads as pedestrian space
            // even when the larger pavers are small on screen.
            g.addPath(union(roads, extra: 4.6)); g.clip()
            drawPavers(g, origin: bounds.origin, colors: [0xd7c4ab, 0xd3bea4, 0xddcbb1], grout: 0xc9b69e)
            g.restoreGState()

            for road in roads {
                stroke(g, road.path, width: road.width + 1.55, color: color(0x81796b))
            }
            for road in roads {
                stroke(g, road.path, width: road.width + 0.85, color: color(0xc9bda9))
            }
            // Reveal the base asphalt where a public road crosses the detailed sidewalk.
            g.saveGState()
            g.setBlendMode(.destinationOut)
            g.setFillColor(UIColor.black.cgColor)
            g.addPath(crossingCarriageways(crossings)); g.fillPath()
            g.restoreGState()
            let driving = union(roads, extra: 0)
            g.setFillColor(asphalt.cgColor); g.addPath(driving); g.fillPath()
            g.saveGState()
            g.addPath(driving); g.clip()
            drawAsphalt(g)
            drawLaneLines(g, roads: roads)
            drawJunctions(g)
            g.restoreGState()
            drawCycleway(g, path: cycleway)
            drawSidewalkDetails(g)
            if let coverage { applyGroundCoverage(coverage, to: g) }
            else {
                fadeNorthernCoverage(g)
                fadeBoundary(g, bounds: bounds, horizontal: 20, vertical: 16)
            }
        }.cgImage
        guard let surface else { return nil }
        var names: [String: CGImage] = [:]
        let supportedNames = Set(roads.map(\.name))
        for name in Set(streetNameHints.map(\.0)).intersection(supportedNames).sorted() {
            names[name] = rasterizeStreetName(name)
        }
        return RoadTextures(surface: surface, names: names)
    }

    static func addRoadTexture(_ textures: RoadTextures?, to root: SCNNode, roads: [Road]) {
        guard let textures else { return }
        addGroundPlane(UIImage(cgImage: textures.surface), in: bounds, height: altitude, renderingOrder: 1, to: root)
        addStreetNames(to: root, roads: roads, images: textures.names)
    }

    static func addRoadFixtures(to root: SCNNode, roads: [Road]) {
        guard !roads.isEmpty else { return }
        addBoulevardMedians(roads, to: root)

        for (x, z, rotation) in [(-80.0, 130.0, 0.0), (-111, 95, .pi), (110, 132, 0), (80, 100, .pi)] {
            addSignal(x: x, z: z, rotation: rotation, to: root)
        }
    }

    static func addNightLights(to root: SCNNode, roads: [Road], crossings: [Road]) {
        guard !roads.isEmpty, let image = CityStreetLightAtlas.make(
            bounds: bounds, shoulders: union(roads, extra: 5.6), curbs: union(roads, extra: 1.9),
            carriageway: union(roads, extra: -0.55), crossings: crossingCarriageways(crossings),
            lamps: CityCivicLandscape.lampLightCenters
        ) else { return }
        let lights = addGroundPlane(UIImage(cgImage: image), in: bounds, height: altitude + 0.02,
                                    renderingOrder: 2, to: root)
        lights.name = nightLightsName
        lights.opacity = 0
        lights.geometry?.firstMaterial?.lightingModel = .constant
    }

    @discardableResult
    private static func addGroundPlane(_ image: UIImage, in extent: CGRect, height: CGFloat,
                                       renderingOrder: Int, to root: SCNNode) -> SCNNode {
        let geometry = SCNPlane(width: extent.width, height: extent.height)
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.diffuse.mipFilter = .linear
        material.lightingModel = .lambert
        material.writesToDepthBuffer = false
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(Float(extent.midX), Float(height), Float(extent.midY))
        node.renderingOrder = renderingOrder
        root.addChildNode(node)
        return node
    }

    nonisolated private static func drawCycleway(_ g: CGContext, path: [CGPoint]) {
        guard path.count >= 2 else { return }
        stroke(g, path, width: 2.75, color: color(0xa1a291))
        stroke(g, path, width: 2.25, color: color(0x818f7d))
        stroke(g, path, width: 0.14, color: paint.withAlphaComponent(0.7), dash: [1.3, 3.2])
    }

    private static func addBoulevardMedians(_ roads: [Road], to root: SCNNode) {
        let segments = roads.filter(\.isBoulevard).flatMap { Array(zip($0.path, $0.path.dropFirst())) }
        func midpoint(_ x: CGFloat) -> CGFloat? {
            let crossings = segments.compactMap { a, b -> CGFloat? in
                guard x >= min(a.x, b.x), x <= max(a.x, b.x), abs(b.x - a.x) > 0.01 else { return nil }
                return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
            }
            guard let north = crossings.min(), let south = crossings.max(), south - north > 10 else { return nil }
            return (north + south) / 2
        }
        let leaf = SCNSphere(radius: 0.66)
        leaf.segmentCount = 8
        leaf.firstMaterial?.diffuse.contents = color(0x788463)
        for (start, end) in [(-246.0, -132.0), (-66, 67), (128, 274)] {
            for x in stride(from: start, to: end - 9, by: 13) {
                guard let a = midpoint(x), let b = midpoint(x + 9.5) else { continue }
                let curb = SCNBox(width: hypot(9.5, b - a), height: 0.27, length: 2.05, chamferRadius: 0.12)
                curb.firstMaterial?.diffuse.contents = color(0xc3b58e)
                let island = SCNNode(geometry: curb)
                island.position = SCNVector3(Float(x + 4.75), Float(altitude + 0.13), Float((a + b) / 2))
                island.eulerAngles.y = Float(-atan2(b - a, 9.5))
                root.addChildNode(island)
                for i in -2...2 {
                    let shrub = SCNNode(geometry: leaf)
                    shrub.position = SCNVector3(Float(i) * 1.66, 0.45, Float(i % 2) * 0.14)
                    shrub.scale = SCNVector3(1.3, 0.58, 1.06)
                    island.addChildNode(shrub)
                }
            }
        }
    }

    nonisolated private static func union(_ roads: [Road], extra: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for road in roads {
            path.addPath(polyline(road.path).copy(strokingWithWidth: road.width + extra,
                                                 lineCap: .round, lineJoin: .round, miterLimit: 2))
        }
        return path
    }

    nonisolated static func polyline(_ points: [CGPoint], closed: Bool = false) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        if closed { path.closeSubpath() }
        return path
    }

    nonisolated private static func stroke(_ g: CGContext, _ points: [CGPoint], width: CGFloat,
                               color: UIColor, dash: [CGFloat] = []) {
        g.setStrokeColor(color.cgColor)
        g.setLineWidth(width)
        g.setLineCap(dash.isEmpty && width > 1 ? .round : .butt)
        g.setLineJoin(.round)
        g.setLineDash(phase: 0, lengths: dash)
        g.addPath(polyline(points))
        g.strokePath()
    }

    nonisolated private static func fill(_ g: CGContext, _ x: CGFloat, _ z: CGFloat, _ w: CGFloat, _ d: CGFloat, _ c: UIColor) {
        g.setFillColor(c.cgColor); g.fill(CGRect(x: x, y: z, width: w, height: d))
    }

    nonisolated private static func drawGroundGrain(_ g: CGContext, in extent: CGRect, tint: Int) {
        let side = 128
        var state: UInt32 = 0x243961ce
        func grid(_ count: Int) -> [Double] {
            (0..<(count * count)).map { _ in
                state = 1_664_525 &* state &+ 1_013_904_223
                return Double(state >> 8) / 8_388_608 - 1
            }
        }
        let coarse = grid(8), fine = grid(32), grain = grid(64)
        func noise(_ grid: [Double], count: Int, x: Int, z: Int) -> Double {
            let stride = side / count
            let ix = x / stride, iz = z / stride
            let nextX = (ix + 1) % count, nextZ = (iz + 1) % count
            let tx = Double(x % stride) / Double(stride), tz = Double(z % stride) / Double(stride)
            let u = tx * tx * (3 - 2 * tx), v = tz * tz * (3 - 2 * tz)
            let a = grid[iz * count + ix] * (1 - u) + grid[iz * count + nextX] * u
            let b = grid[nextZ * count + ix] * (1 - u) + grid[nextZ * count + nextX] * u
            return a * (1 - v) + b * v
        }
        // Periodic continuous variation reads as material at street scale,
        // without opaque blotches or a visible repeating edge.
        let rgb = [tint >> 16 & 255, tint >> 8 & 255, tint & 255]
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for z in 0..<side {
            for x in 0..<side {
                let value = 2.1 * noise(coarse, count: 8, x: x, z: z)
                          + 2.4 * noise(fine, count: 32, x: x, z: z)
                          + 1.8 * noise(grain, count: 64, x: x, z: z)
                let offset = (z * side + x) * 4
                for channel in 0..<3 {
                    pixels[offset + channel] = UInt8(clamping: rgb[channel] + Int(value.rounded()))
                }
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            g.setFillColor(color(tint).cgColor); g.fill(extent)
            return
        }
        g.saveGState()
        g.clip(to: extent)
        g.draw(image, in: CGRect(origin: extent.origin, size: CGSize(width: side, height: side)), byTiling: true)
        g.restoreGState()
    }

    nonisolated static func drawPavers(_ g: CGContext, origin: CGPoint, colors: [Int], grout: Int = 0xb7ab98) {
        // Draw the same staggered paving as a small repeating swatch. Painting
        // 330,000 clipped rectangles across the district stalled the map thread.
        // Integral raster edges prevent the opaque renderer's padded edge
        // pixels from repeating as dark seams along the entire sidewalk.
        let tileSize = CGSize(width: 40, height: 22)
        let cell = CGSize(width: tileSize.width / 16, height: tileSize.height / 16)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let tile = UIGraphicsImageRenderer(size: tileSize, format: format).image { output in
            let canvas = output.cgContext
            canvas.setFillColor(color(grout).cgColor)
            canvas.fill(CGRect(origin: .zero, size: tileSize))
            let colors = colors.map(color)
            for row in 0..<16 {
                for col in 0...16 {
                    let x = CGFloat(col) * cell.width - (row.isMultiple(of: 2) ? 0 : cell.width / 2)
                    let seed = (row * 149 + (col % 16) * 73) ^ ((col % 16) * 17 + row)
                    fill(canvas, x, CGFloat(row) * cell.height, cell.width - 0.1, cell.height - 0.1, colors[seed % colors.count])
                }
            }
        }
        guard let image = tile.cgImage else { return }
        g.draw(image, in: CGRect(origin: origin, size: tileSize), byTiling: true)
    }

    nonisolated private static func drawAsphalt(_ g: CGContext) {
        // Repeatable aggregate and patches, faint at browsing scale.
        var state: UInt32 = 0x51ba4911
        func next() -> CGFloat {
            state = 1_664_525 &* state &+ 1_013_904_223
            return CGFloat(state >> 8) / 16_777_216
        }
        let dark = color(0x282b35).withAlphaComponent(0.18)
        let light = color(0x8d8a89).withAlphaComponent(0.19)
        for i in 0..<15_000 {
            let x = bounds.minX + next() * bounds.width
            let z = bounds.minY + next() * bounds.height
            let r = 0.15 + next() * 0.48
            fill(g, x, z, r * 1.7, r, i.isMultiple(of: 3) ? light : dark)
        }
        for (x, z) in [(-162.0, 106.0), (-63, 119), (23, 112), (148, 128), (90, 192), (202, 116)] {
            fill(g, x, z, 2.1, 1.5, color(0x454954).withAlphaComponent(0.6))
            g.setFillColor(color(0x313644).cgColor)
            g.fillEllipse(in: CGRect(x: x + 0.5, y: z + 0.21, width: 1.05, height: 1.05))
        }
    }

    nonisolated private static func drawLaneLines(_ g: CGContext, roads: [Road]) {
        g.saveGState()
        let region = CGMutablePath()
        region.addRect(bounds)
        region.addRect(CGRect(x: -114, y: 92, width: 36, height: 40))
        region.addRect(CGRect(x: 82, y: 96, width: 31, height: 44))
        region.addRect(CGRect(x: 88, y: 212, width: 16, height: 22))
        g.addPath(region); g.clip(using: .evenOdd)
        for road in roads {
            if road.isBoulevard || road.name == "市府路" {
                let offsets: [CGFloat] = road.isBoulevard ? [-2.1, 2.1] : [0]
                for distance in offsets {
                    stroke(g, offset(road.path, by: distance), width: 0.16,
                           color: paint.withAlphaComponent(0.84), dash: [2.1, 2.5])
                }
            } else {
                for distance: CGFloat in [-0.16, 0.16] {
                    stroke(g, offset(road.path, by: distance), width: 0.12, color: color(0xd1b56d))
                }
            }
            for sign: CGFloat in [-1, 1] {
                stroke(g, offset(road.path, by: sign * (road.width / 2 - 0.33)), width: 0.11,
                       color: paint.withAlphaComponent(0.68))
            }
        }
        g.restoreGState()
    }

    nonisolated static func offset(_ points: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        points.indices.map { i in
            let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
            let dx = b.x - a.x, dz = b.y - a.y
            let length = max(hypot(dx, dz), 0.001)
            return CGPoint(x: points[i].x - dz / length * distance, y: points[i].y + dx / length * distance)
        }
    }

    nonisolated private static func drawJunctions(_ g: CGContext) {
        for (x, z, depth) in [(-119.0, 112.0, 22.0), (-77, 114, 22), (81, 118, 23), (111, 119, 23)] {
            for row in -6...6 {
                fill(g, x - 2.2, z + CGFloat(row) * depth / 13, 4.4, 0.82, paint)
            }
            let direction: CGFloat = (x == -119 || x == 81) ? -1 : 1
            fill(g, x + 4.1 * direction, z - depth / 2, 0.32, depth, paint)
        }
        for (x, z, width) in [(-100.0, 96.0, 21.0), (96, 98, 8), (95, 136, 8), (95, 212, 8), (95, 233, 8)] {
            let stripes = Int(width / 1.4)
            for i in 0..<stripes {
                fill(g, x - width / 2 + CGFloat(i) * 1.42, z - 2.4, 0.76, 4.8, paint)
            }
        }
        for (x, z, width) in [(-91.0, -233.0, 24.0), (-98, -196, 17), (100, -226, 9), (98, -200, 9)] {
            for i in 0..<Int(width / 1.5) {
                fill(g, x - width / 2 + CGFloat(i) * 1.5, z - 2.6, 0.78, 5.2, paint)
            }
        }
        for (x, z, width) in [(-111.0, -214.0, 19.0), (-70, -214, 9), (87, -212, 9), (115, -212, 9)] {
            for i in 0..<Int(width / 1.5) {
                fill(g, x - 2.6, z - width / 2 + CGFloat(i) * 1.5, 5.2, 0.78, paint)
            }
        }
        for (x, z, direction) in [(-145.0, 117.0, 1.0), (-51, 109, -1), (46, 123, 1), (142, 115, -1)] {
            g.saveGState()
            g.translateBy(x: x, y: z)
            if direction < 0 { g.rotate(by: .pi) }
            g.setFillColor(paint.withAlphaComponent(0.86).cgColor)
            g.addLines(between: [CGPoint(x: -3.5, y: -0.23), CGPoint(x: 0.9, y: -0.23),
                                 CGPoint(x: 0.9, y: -1.0), CGPoint(x: 3.5, y: 0),
                                 CGPoint(x: 0.9, y: 1.0), CGPoint(x: 0.9, y: 0.23),
                                 CGPoint(x: -3.5, y: 0.23)])
            g.closePath(); g.fillPath(); g.restoreGState()
        }
    }

    nonisolated private static func drawSidewalkDetails(_ g: CGContext) {
        let brass = color(0xc9a86b)
        for (x, z) in [(-119.0, 97.0), (-77, 99), (-77, 130), (81, 104), (111, 104), (111, 134), (81, 134)] {
            fill(g, x - 2.45, z - 0.75, 4.9, 1.5, brass)
            for i in 0..<10 {
                fill(g, x - 2.25 + CGFloat(i) * 0.45, z - 0.43, 0.11, 0.86, color(0xe0c58b))
            }
        }
        for (x, z) in [(-52.0, 128.5), (29, 131), (128, 135), (157, 136), (-136, 95), (147, 106)] {
            fill(g, x, z, 2.0, 0.57, color(0x686966))
            for i in 0..<5 {
                fill(g, x + CGFloat(i) * 0.36 + 0.18, z + 0.14, 0.15, 0.28, color(0x303640))
            }
        }
    }

    nonisolated static func fadeNorthernCoverage(_ g: CGContext, scale: CGFloat = 1, offset: CGFloat = 0) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [UIColor.black.cgColor, UIColor.clear.cgColor] as CFArray,
                                        locations: [0, 1]) else { return }
        let edge = offset + scale * CGFloat(CityDistrictCamera.northernGroundLimit)
        let opaque = offset + scale * CGFloat(CityDistrictCamera.northernOpaqueLimit)
        g.saveGState()
        g.setBlendMode(.destinationOut)
        g.drawLinearGradient(gradient, start: CGPoint(x: 0, y: edge), end: CGPoint(x: 0, y: opaque),
                             options: .drawsBeforeStartLocation)
        g.restoreGState()
    }

    nonisolated private static func fadeBoundary(_ g: CGContext, bounds: CGRect, horizontal: CGFloat, vertical: CGFloat) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [UIColor.black.cgColor, UIColor.clear.cgColor] as CFArray,
                                        locations: [0, 1]) else { return }
        g.setBlendMode(.destinationOut)
        for (a, b) in [
            (CGPoint(x: bounds.minX, y: 0), CGPoint(x: bounds.minX + horizontal, y: 0)),
            (CGPoint(x: bounds.maxX, y: 0), CGPoint(x: bounds.maxX - horizontal, y: 0)),
            (CGPoint(x: 0, y: bounds.minY), CGPoint(x: 0, y: bounds.minY + vertical)),
            (CGPoint(x: 0, y: bounds.maxY), CGPoint(x: 0, y: bounds.maxY - vertical)),
        ] {
            g.drawLinearGradient(gradient, start: a, end: b, options: [])
        }
    }

    private static func addSignal(x: Double, z: Double, rotation: Double, to root: SCNNode) {
        let fixture = SCNNode()
        fixture.position = SCNVector3(Float(x), 0.75, Float(z))
        fixture.eulerAngles.y = Float(rotation)
        root.addChildNode(fixture)
        func block(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ x: Float, _ y: Float, _ z: Float, _ tint: UIColor) {
            let shape = SCNBox(width: w, height: h, length: d, chamferRadius: 0.06)
            shape.firstMaterial?.diffuse.contents = tint
            let node = SCNNode(geometry: shape); node.position = SCNVector3(x, y, z)
            fixture.addChildNode(node)
        }
        let metal = color(0x7c8382)
        block(0.23, 6.2, 0.24, 0, 3.1, 0, metal)
        block(2.2, 0.17, 0.18, 1.02, 5.8, 0, metal)
        block(1.5, 0.55, 0.4, 2.0, 5.48, 0, color(0x282e33))
        for (i, tint) in [0x5c4949, 0x5d513c, 0x6ba997].enumerated() {
            block(0.27, 0.27, 0.1, 1.57 + Float(i) * 0.43, 5.48, 0.23, color(tint))
        }
    }

    nonisolated static func color(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
#endif
