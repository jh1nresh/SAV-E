#if SAVVY_CITY_MVP
import SceneKit
import UIKit

/// Illustrative roof construction, constrained to the source footprint.
/// It adds depth at district scale without inventing businesses or changing heights.
@MainActor
enum CityRoofDetails {
    /// Shared, illustrative weathering on the existing roof caps. Keep the
    /// seams low contrast so the mip chain softens them at district scale.
    static func surfaceTexture(tint: Int, residential: Bool) -> UIImage? {
        let side = 64
        let course = residential ? 32 : 16
        let base = [tint >> 16 & 255, tint >> 8 & 255, tint & 255]
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        var seed: UInt32 = 0x6173a4b1
        for y in 0..<side {
            let row = y / course
            let stagger = residential && row.isMultiple(of: 2) ? course / 2 : 0
            for x in 0..<side {
                seed = 1_664_525 &* seed &+ 1_013_904_223
                let column = ((x + stagger) % side) / course
                let grain = Int(seed >> 25) % 9 - 4
                let courseTone = (row * 17 + column * 13) % 11 - 5
                let line = min(y % course, (x + stagger) % course)
                let seam = line == 0 ? -18 : line == 1 ? 6 : 1
                let offset = (y * side + x) * 4
                for channel in 0..<3 {
                    pixels[offset + channel] = UInt8(clamping: base[channel] + courseTone + grain + seam)
                }
            }
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let bitmap = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: side * 4, space: colorSpace,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return nil
        }
        return UIImage(cgImage: bitmap)
    }

    struct Fixture {
        let rect: CGRect
        let height: CGFloat
        let isHeadHouse: Bool
    }

    static func fixtures(in footprint: [CGPoint], seed: Int, excluding obstacles: [CGRect] = []) -> [Fixture] {
        guard footprint.count > 2 else { return [] }
        let path = outline(footprint)
        let bounds = path.bounds
        guard bounds.width > 18, bounds.height > 16 else { return [] }
        var result: [Fixture] = []
        let spacing = max(14, min(26, min(bounds.width, bounds.height) / 3))
        for row in 0..<Int(bounds.height / spacing) {
            for col in 0..<Int(bounds.width / spacing) {
                guard (row * 2 + col + seed) % 3 == 0 else { continue }
                let headHouse = result.isEmpty
                let width: CGFloat = headHouse ? 7.2 : 4.8
                let depth: CGFloat = headHouse ? 5.2 : 3.5
                let center = CGPoint(x: bounds.minX + spacing * (CGFloat(col) + 0.65),
                                     y: bounds.minY + spacing * (CGFloat(row) + 0.65))
                let rect = CGRect(x: center.x - width / 2, y: center.y - depth / 2, width: width, height: depth)
                // Margin and edge samples also reject concave notches between corners.
                let clearance = rect.insetBy(dx: -2, dy: -2)
                guard !obstacles.contains(where: { $0.intersects(clearance) }) else { continue }
                let points = [CGPoint(x: clearance.minX, y: clearance.minY), CGPoint(x: clearance.maxX, y: clearance.minY),
                              CGPoint(x: clearance.maxX, y: clearance.maxY), CGPoint(x: clearance.minX, y: clearance.maxY),
                              CGPoint(x: clearance.midX, y: clearance.minY), CGPoint(x: clearance.midX, y: clearance.maxY),
                              CGPoint(x: clearance.minX, y: clearance.midY), CGPoint(x: clearance.maxX, y: clearance.midY), center]
                guard points.allSatisfy(path.contains) else { continue }
                let ring = footprint.first == footprint.last ? Array(footprint.dropLast()) : footprint
                guard !zip(ring, ring.dropFirst() + [ring[0]]).contains(where: {
                    intersects($0.0, $0.1, rect: clearance)
                }) else { continue }
                result.append(Fixture(rect: rect, height: headHouse ? 3.1 : 1.5, isHeadHouse: headHouse))
                if result.count == 5 { return result }
            }
        }
        return result
    }

    static func add(footprint: [CGPoint], height: CGFloat, finish: CityStreetDetail.Finish, seed: Int, to root: SCNNode) {
        guard footprint.count > 2, height > 5 else { return }
        let ring = footprint.first == footprint.last ? Array(footprint.dropLast()) : footprint
        let parent = SCNNode()
        parent.name = "xinyi-roof-\(seed)"
        let cap = SCNShape(path: outline(ring), extrusionDepth: 0.12)
        cap.materials = [finish == .civic ? warmRoof : coolRoof]
        let deck = SCNNode(geometry: cap)
        deck.eulerAngles.x = -.pi / 2
        deck.position.y = Float(height + 0.08)
        parent.addChildNode(deck)
        let parapets = SCNNode()
        for (a, b) in zip(ring, ring.dropFirst() + [ring[0]]) {
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 1.2 else { continue }
            let curb = SCNBox(width: length, height: 0.78, length: 0.34, chamferRadius: 0.05)
            // A 5 cm bevel only needs two segments at district zoom. The
            // default ten make SceneKit's deferred mesh merge block the map.
            curb.chamferSegmentCount = 2
            curb.materials = [trim]
            let beam = SCNNode(geometry: curb)
            beam.position = SCNVector3(Float((a.x + b.x) / 2), Float(height + 0.40), Float(-(a.y + b.y) / 2))
            beam.eulerAngles.y = Float(atan2(b.y - a.y, b.x - a.x))
            parapets.addChildNode(beam)
        }
        // Repeated curb segments share one material and are flattened as one mesh.
        parent.addChildNode(parapets.flattenedClone())
        // The tower rises through the mall roof; leave its shaft clear.
        let obstacles = seed == 101 ? [CGRect(x: -33, y: -33, width: 66, height: 66)] : []
        for fixture in fixtures(in: ring, seed: seed, excluding: obstacles) {
            let r = fixture.rect
            let body = box(width: r.width, height: fixture.height, depth: r.height,
                           material: fixture.isHeadHouse ? stair : equipment)
            body.name = "roof-fixture"
            body.position = SCNVector3(Float(r.midX), Float(height + fixture.height / 2 + 0.15), Float(-r.midY))
            parent.addChildNode(body)
            let lid = box(width: r.width + 0.20, height: 0.18, depth: r.height + 0.20, material: trim)
            lid.position = SCNVector3(Float(r.midX), Float(height + fixture.height + 0.22), Float(-r.midY))
            parent.addChildNode(lid)
            if !fixture.isHeadHouse {
                for dx: CGFloat in [-1.1, 1.1] {
                    let vent = SCNCylinder(radius: 0.68, height: 0.09)
                    vent.radialSegmentCount = 12
                    vent.materials = [fan]
                    let rotor = SCNNode(geometry: vent)
                    rotor.position = SCNVector3(Float(r.midX + dx), Float(height + fixture.height + 0.36), Float(-r.midY))
                    parent.addChildNode(rotor)
                }
            }
        }
        root.addChildNode(parent)
    }

    static func intersects(_ a: CGPoint, _ b: CGPoint, rect: CGRect) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        var enter: CGFloat = 0, leave: CGFloat = 1
        for (p, q) in [(-dx, a.x - rect.minX), (dx, rect.maxX - a.x),
                       (-dy, a.y - rect.minY), (dy, rect.maxY - a.y)] {
            if abs(p) < 0.000_001 { if q < 0 { return false }; continue }
            let t = q / p
            if p < 0 { enter = max(enter, t) } else { leave = min(leave, t) }
            if enter > leave { return false }
        }
        return true
    }

    private static func outline(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first); points.dropFirst().forEach { path.addLine(to: $0) }; path.close()
        return path
    }
    private static func box(width: CGFloat, height: CGFloat, depth: CGFloat, material: SCNMaterial) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: depth, chamferRadius: 0.05)
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
    private static func material(_ rgb: UInt32) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                                           green: CGFloat((rgb >> 8) & 255) / 255,
                                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        material.lightingModel = .lambert
        material.roughness.contents = 0.94
        return material
    }
    private static let coolRoof = material(0x9ea9a6)
    private static let warmRoof = material(0xb7b09d)
    private static let trim = material(0xd5d5c7)
    private static let stair = material(0xbac1b5)
    private static let equipment = material(0x8f9e9a)
    private static let fan = material(0x465c5e)
}
#endif
