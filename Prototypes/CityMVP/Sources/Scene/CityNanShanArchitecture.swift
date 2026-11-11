#if SAVVY_CITY_MVP
import UIKit
import SceneKit
import simd

/// Original illustrative massing, aligned to the two bundled Nan Shan ways.
@MainActor
enum CityNanShanArchitecture {
    private static let officeWay = 383731054
    private static let mallWay = 513491894

    private enum Finish {
        case glass, crown, screen, metal, roof, planted
    }

    private struct Volume {
        let name: String
        let rings: [[SIMD3<Float>]]
        let wall: Finish
        var roof: Finish = .roof
    }

    private static let office: [Volume] = {
        let tower = SIMD2<Float>(269, -49)
        return [
            Volume(name: "tapered-office", rings: [
                ring(at: tower, y: 0, width: 49, depth: 51, cut: 6),
                ring(at: tower, y: 22, width: 55, depth: 50, cut: 6),
                ring(at: tower, y: 224, width: 32, depth: 57.5, cut: 4),
            ], wall: .glass, roof: .glass),
            Volume(name: "split-crown", rings: [
                ring(at: tower, y: 224, width: 32, depth: 57.5, cut: 4),
                ring(at: tower, y: 253, width: 31, depth: 58, cut: 3),
                ring(at: tower, y: 253, width: 31, depth: 58, cut: 3, wings: true),
            ], wall: .crown),
            box("west-lobby-link", center: .init(243.5, -49), size: .init(9, 22), from: 0, to: 13, wall: .glass),
            box("east-lobby-link", center: .init(300, -47), size: .init(15, 15), from: 0, to: 10, wall: .glass),
            Volume(name: "folded-cultural-hall", rings: [
                ring(at: .init(333, -47), y: 0, width: 56, depth: 21, cut: 5),
                ring(at: .init(334, -47), y: 7, width: 60, depth: 24, cut: 6),
                ring(at: .init(334, -47), y: 18, width: 69, depth: 35, cut: 8),
                ring(at: .init(332, -47), y: 24, width: 64, depth: 26, cut: 7),
            ], wall: .metal),
        ]
    }()

    private static let mall: [Volume] = [
        box("retail-base", center: .init(166, -46), size: .init(65, 47), from: 0, to: 8, wall: .glass),
        box("retail-connector", center: .init(220, -49), size: .init(38, 25), from: 0, to: 14, wall: .glass),
        box("retail-terrace-low", center: .init(166, -45), size: .init(75, 54), from: 8, to: 15, wall: .screen),
        box("retail-glass-middle", center: .init(165, -47), size: .init(63, 45), from: 15, to: 18, wall: .glass),
        box("retail-terrace-middle", center: .init(164, -48), size: .init(68, 46), from: 18, to: 25, wall: .screen),
        box("retail-glass-high", center: .init(161, -49), size: .init(53, 37), from: 25, to: 29, wall: .glass),
        box("retail-terrace-high", center: .init(159, -49), size: .init(60, 40), from: 29, to: 38, wall: .screen),
        box("retail-roof-garden", center: .init(151, -49), size: .init(34, 30), from: 38, to: 38.3, wall: .planted, roof: .planted),
    ]

    static func add(way: Int, footprint: UIBezierPath, to root: SCNNode) -> Bool {
        let volumes: [Volume]
        let anchor: CGPoint
        switch way {
        case officeWay: volumes = office; anchor = .init(x: 269, y: 49)
        case mallWay: volumes = mall; anchor = .init(x: 166, y: 46)
        default: return false
        }
        guard footprint.contains(anchor) else { return false }
        let group = SCNNode()
        group.name = "surface-way/\(way)"
        let glazing = glassMaterial()
        let screen = finish(0xb0a08a)
        screen.name = "city-lit-facade"
        screen.emission.contents = CityStreetSurface.color(0x63401c)
        screen.emission.intensity = 0
        for volume in volumes {
            group.addChildNode(node(for: volume, glass: glazing, screen: screen))
        }
        root.addChildNode(group)
        return true
    }

    static func shadowBands(in root: SCNNode) -> [[SIMD3<Float>]] {
        [(officeWay, office), (mallWay, mall)].flatMap { way, volumes -> [[SIMD3<Float>]] in
            guard let group = root.childNode(withName: "surface-way/\(way)", recursively: false),
                  group.geometry == nil else { return [] }
            return volumes.flatMap { volume in
                zip(volume.rings, volume.rings.dropFirst()).map { lower, upper in lower + upper }
            }
        }
    }

    private static func ring(at center: SIMD2<Float>, y: Float, width: Float, depth: Float,
                             cut: Float, wings: Bool = false) -> [SIMD3<Float>] {
        let x = width / 2, z = depth / 2
        let corners: [SIMD2<Float>] = [
            .init(-x + cut, -z), .init(0, -z), .init(x - cut, -z), .init(x, -z + cut),
            .init(x, z - cut), .init(x - cut, z), .init(0, z), .init(-x + cut, z),
            .init(-x, z - cut), .init(-x, -z + cut),
        ]
        return corners.map { corner in
            let height: Float
            if wings {
                height = y + abs(corner.x) / x * (corner.x < 0 ? 19 : 16)
            } else {
                height = y
            }
            return .init(center.x + corner.x, height, center.y + corner.y)
        }
    }

    private static func box(_ name: String, center: SIMD2<Float>, size: SIMD2<Float>,
                            from bottom: Float, to top: Float, wall: Finish, roof: Finish = .roof) -> Volume {
        let rings = [bottom, top].map {
            ring(at: center, y: $0, width: size.x, depth: size.y, cut: 0.7)
        }
        return Volume(name: name, rings: rings, wall: wall, roof: roof)
    }

    private static func node(for volume: Volume, glass: SCNMaterial, screen: SCNMaterial) -> SCNNode {
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], uv: [CGPoint] = []
        var walls: [Int32] = [], roof: [Int32] = []
        func append(_ points: [SIMD3<Float>], normal: SIMD3<Float>, coordinates: [CGPoint]) -> Int32 {
            let start = Int32(positions.count)
            positions += points.map { SCNVector3($0.x, $0.y, $0.z) }
            normals += Array(repeating: SCNVector3(normal.x, normal.y, normal.z), count: points.count)
            uv += coordinates
            return start
        }
        let baseY = volume.rings[0][0].y
        for (lower, upper) in zip(volume.rings, volume.rings.dropFirst()) {
            for i in lower.indices {
                let j = (i + 1) % lower.count
                let a = lower[i], b = lower[j], c = upper[j], d = upper[i]
                let span = CGFloat(simd_length(b - a) / 12)
                // Whole tile shifts leave the glazing pattern fixed and
                // sample different rooms from the larger night texture.
                let phase = CGFloat(i % 3) / 3 + CGFloat(i * 3 % 4)
                let vertical = [a.y, b.y, c.y, d.y].map { CGFloat(($0 - baseY) / 19.2) + CGFloat(i % 4) }
                let corners = [a, b, c, d]
                for triangle in [[0, 2, 1], [0, 3, 2]] {
                    let points = triangle.map { corners[$0] }
                    let cross = simd_cross(points[1] - points[0], points[2] - points[0])
                    guard simd_length_squared(cross) > 0.0001 else { continue }
                    let coordinates = triangle.map {
                        CGPoint(x: phase + ($0 == 1 || $0 == 2 ? span : 0), y: vertical[$0])
                    }
                    let start = append(points, normal: simd_normalize(cross), coordinates: coordinates)
                    walls += [start, start + 1, start + 2]
                }
            }
        }
        if let top = volume.rings.last, let lowest = top.map(\.y).min() {
            var center = top.reduce(.zero, +) / Float(top.count)
            center.y = lowest
            for i in top.indices {
                let a = top[(i + 1) % top.count], b = top[i]
                let cross = simd_cross(a - center, b - center)
                let start = append([center, a, b], normal: simd_normalize(cross), coordinates: [.zero, .zero, .zero])
                roof += [start, start + 1, start + 2]
            }
        }
        if volume.wall == .screen, let bottom = volume.rings.first {
            let center = bottom.reduce(.zero, +) / Float(bottom.count)
            for i in bottom.indices {
                let a = bottom[i], b = bottom[(i + 1) % bottom.count]
                let start = append([center, a, b], normal: .init(0, -1, 0), coordinates: [.zero, .zero, .zero])
                roof += [start, start + 1, start + 2]
            }
        }
        let geometry = SCNGeometry(
            sources: [.init(vertices: positions), .init(normals: normals), .init(textureCoordinates: uv)],
            elements: [walls, roof].map { SCNGeometryElement(indices: $0, primitiveType: .triangles) }
        )
        geometry.materials = [volume.wall, volume.roof].map { material($0, glass: glass, screen: screen) }
        let node = SCNNode(geometry: geometry)
        node.name = "nanshan-\(volume.name)"
        return node
    }

    private static let glassTextures: (UIImage, UIImage) = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let daySize = CGSize(width: 96, height: 96)
        let day = UIGraphicsImageRenderer(size: daySize, format: format).image { output in
            let cg = output.cgContext
            cg.setFillColor(CityStreetSurface.color(0x8399a0).cgColor)
            cg.fill(CGRect(origin: .zero, size: daySize))
            let panes = [0x385666, 0x4b6776, 0x587482, 0x455c6b]
            for row in 0..<4 {
                for column in 0..<4 {
                    cg.setFillColor(CityStreetSurface.color(panes[(column * 3 + row * 2) % panes.count]).cgColor)
                    cg.fill(CGRect(x: column * 24 + 2, y: row * 24 + 1, width: 21, height: 21))
                }
            }
        }
        let nightSize = CGSize(width: 192, height: 192)
        let night = UIGraphicsImageRenderer(size: nightSize, format: format).image { output in
            let cg = output.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: nightSize))
            for row in 0..<16 {
                for column in 0..<16 {
                    let room = CityStreetDetail.facadeNoise(seed: officeWay, column: column, row: row)
                    let cluster = CityStreetDetail.facadeNoise(seed: mallWay, column: column / 3, row: row / 2)
                    guard Int(room % 100) < 12 + Int(cluster % 23) else { continue }
                    let tint = (room >> 8) % 5 == 0 ? 0x9dc4cf : 0xe9c795
                    let brightness = 0.42 + CGFloat((room >> 16) % 32) / 100
                    cg.setFillColor(CityStreetSurface.color(tint).withAlphaComponent(brightness).cgColor)
                    let x = CGFloat(column) * 12 + (room.isMultiple(of: 2) ? 1.8 : 6.2)
                    cg.fill(CGRect(x: x, y: CGFloat(row) * 12 + 1.7, width: 4.1, height: 7.7))
                }
            }
        }
        return (day, night)
    }()

    private static func glassMaterial() -> SCNMaterial {
        let material = finish(0x426472)
        material.name = "city-lit-facade"
        material.diffuse.contents = glassTextures.0
        material.emission.contents = glassTextures.1
        material.emission.contentsTransform = SCNMatrix4MakeScale(0.25, 0.25, 1)
        material.emission.intensity = 0
        for channel in [material.diffuse, material.emission] {
            channel.wrapS = .repeat; channel.wrapT = .repeat; channel.mipFilter = .linear
        }
        return material
    }

    private static func material(_ kind: Finish, glass: SCNMaterial, screen: SCNMaterial) -> SCNMaterial {
        switch kind {
        case .glass: glass
        case .screen: screen
        case .crown: finish(0x637f8d)
        case .metal: finish(0x9da1a6)
        case .roof: finish(0x797f82)
        case .planted: finish(0x607951)
        }
    }

    private static func finish(_ color: Int) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = CityStreetSurface.color(color)
        material.lightingModel = .lambert
        return material
    }
}
#endif
