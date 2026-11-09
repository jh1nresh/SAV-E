#if SAVVY_CITY_MVP
import UIKit
import SceneKit

/// A bounded street atlas. Surface marks and the moving cars use the same OSM lane paths.
@MainActor
enum CityStreetSurface {
    static let altitude: CGFloat = 0.87
    private static let bounds = CGRect(x: -286, y: -74, width: 600, height: 370)
    private static let asphalt = color(0x53565e)
    private static let paint = color(0xf2ece0)

    struct Road {
        let id: Int
        let name: String
        let path: [CGPoint] // east, south
        let width: CGFloat

        var isBoulevard: Bool { name == "信義路五段" }
        var isSideStreet: Bool { name == "松智路" || name == "市府路" }
    }

    static func roads() -> [Road] {
        (CitySceneData.elements ?? []).compactMap { element in
            guard let tags = element["tags"] as? [String: String],
                  let name = tags["name"],
                  ["信義路五段", "市府路", "松智路", "松勤街"].contains(name),
                  let id = element["id"] as? Int, let points = element["geometry"] as? [[String: Double]] else { return nil }
            let path = points.compactMap { point -> CGPoint? in
                guard let lon = point["lon"], let lat = point["lat"] else { return nil }
                return CGPoint(x: (lon - CityScenePlace.originLongitude) * 100_850,
                               y: -(lat - CityScenePlace.originLatitude) * 111_195)
            }
            guard path.count >= 2, path.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
            let width: CGFloat = name == "信義路五段" ? 13.4 : name == "松勤街" ? 8.2 : 9.4
            return Road(id: id, name: name, path: path, width: width)
        }
    }

    static func add(to root: SCNNode, roads: [Road]) {
        guard !roads.isEmpty else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scale: CGFloat = 3
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { output in
            let g = output.cgContext
            g.scaleBy(x: scale, y: scale)
            g.translateBy(x: -bounds.minX, y: -bounds.minY)

            let walk = union(roads, extra: 10)
            g.setFillColor(color(0xb7ab98).cgColor); g.addPath(walk); g.fillPath()
            g.saveGState()
            g.addPath(walk); g.clip()
            drawPavers(g)
            g.restoreGState()

            for road in roads {
                stroke(g, road.path, width: road.width + 1.55, color: color(0x81796b))
            }
            for road in roads {
                stroke(g, road.path, width: road.width + 0.85, color: color(0xc9bda9))
            }
            let driving = union(roads, extra: 0)
            g.setFillColor(asphalt.cgColor); g.addPath(driving); g.fillPath()
            g.saveGState()
            g.addPath(driving); g.clip()
            drawAsphalt(g)
            drawLaneLines(g, roads: roads)
            drawJunctions(g)
            g.restoreGState()
            drawCycleway(g)
            drawSidewalkDetails(g)
            fadeBoundary(g)
        }
        let geometry = SCNPlane(width: bounds.width, height: bounds.height)
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.diffuse.mipFilter = .linear
        material.lightingModel = .lambert
        material.writesToDepthBuffer = false
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(Float(bounds.midX), Float(altitude), Float(bounds.midY))
        node.renderingOrder = 1
        root.addChildNode(node)
        addBoulevardMedians(roads, to: root)

        for (x, z, rotation) in [(-80.0, 130.0, 0.0), (-111, 95, .pi), (110, 132, 0), (80, 100, .pi)] {
            addSignal(x: x, z: z, rotation: rotation, to: root)
        }
    }

    private static func drawCycleway(_ g: CGContext) {
        // OSM way 1339835158, the segregated path alongside Songzhi.
        let path = [CGPoint(x: 113, y: -74), CGPoint(x: 111.4, y: 7.6),
                    CGPoint(x: 110.4, y: 13.8), CGPoint(x: 109, y: 94.5),
                    CGPoint(x: 108.7, y: 99.4)]
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

    private static func union(_ roads: [Road], extra: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for road in roads {
            path.addPath(polyline(road.path).copy(strokingWithWidth: road.width + extra,
                                                 lineCap: .round, lineJoin: .round, miterLimit: 2))
        }
        return path
    }

    private static func polyline(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        return path
    }

    private static func stroke(_ g: CGContext, _ points: [CGPoint], width: CGFloat,
                               color: UIColor, dash: [CGFloat] = []) {
        g.setStrokeColor(color.cgColor)
        g.setLineWidth(width)
        g.setLineCap(dash.isEmpty && width > 1 ? .round : .butt)
        g.setLineJoin(.round)
        g.setLineDash(phase: 0, lengths: dash)
        g.addPath(polyline(points))
        g.strokePath()
    }

    private static func fill(_ g: CGContext, _ x: CGFloat, _ z: CGFloat, _ w: CGFloat, _ d: CGFloat, _ c: UIColor) {
        g.setFillColor(c.cgColor); g.fill(CGRect(x: x, y: z, width: w, height: d))
    }

    private static func drawPavers(_ g: CGContext) {
        let colors = [0xb4a897, 0xc1b3a1, 0xb9ab9a, 0xc5b8a6, 0xb1a594].map(color)
        for row in 0..<Int(bounds.height / 1.35 + 2) {
            for col in 0..<Int(bounds.width / 2.55 + 2) {
                let x = bounds.minX + CGFloat(col) * 2.55 - (row.isMultiple(of: 2) ? 0 : 1.28)
                let z = bounds.minY + CGFloat(row) * 1.35
                let seed = (row * 149 + col * 73) ^ (col * 17 + row)
                fill(g, x, z, 2.45, 1.25, colors[seed % colors.count])
            }
        }
    }

    private static func drawAsphalt(_ g: CGContext) {
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

    private static func drawLaneLines(_ g: CGContext, roads: [Road]) {
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

    static func offset(_ points: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        points.indices.map { i in
            let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
            let dx = b.x - a.x, dz = b.y - a.y
            let length = max(hypot(dx, dz), 0.001)
            return CGPoint(x: points[i].x - dz / length * distance, y: points[i].y + dx / length * distance)
        }
    }

    private static func drawJunctions(_ g: CGContext) {
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

    private static func drawSidewalkDetails(_ g: CGContext) {
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

    private static func fadeBoundary(_ g: CGContext) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [UIColor.black.cgColor, UIColor.clear.cgColor] as CFArray,
                                        locations: [0, 1]) else { return }
        g.setBlendMode(.destinationOut)
        for (a, b) in [
            (CGPoint(x: bounds.minX, y: 0), CGPoint(x: bounds.minX + 20, y: 0)),
            (CGPoint(x: bounds.maxX, y: 0), CGPoint(x: bounds.maxX - 20, y: 0)),
            (CGPoint(x: 0, y: bounds.minY), CGPoint(x: 0, y: bounds.minY + 16)),
            (CGPoint(x: 0, y: bounds.maxY), CGPoint(x: 0, y: bounds.maxY - 16)),
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

    static func color(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
#endif
