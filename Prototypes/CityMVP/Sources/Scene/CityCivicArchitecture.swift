#if SAVVY_CITY_MVP
import UIKit
import SceneKit
import simd

/// Original illustrative stonework on the existing civic footprint, not a survey.
@MainActor
enum CityCivicArchitecture {
    static let wayID = 142113976
    private static let jointWidth: CGFloat = 0.12

    static func add(footprint: [CGPoint], height: CGFloat, levels: Int?, to root: SCNNode) {
        let ring = footprint.first == footprint.last ? Array(footprint.dropLast()) : footprint
        guard ring.count > 2, height > 6 else { return }
        let edges = Array(zip(ring, ring.dropFirst() + [ring[0]]))
        let area = edges.reduce(CGFloat.zero) { $0 + $1.0.y * $1.1.x - $1.0.x * $1.1.y }
        let courses = max(2, min(18, levels ?? Int(height / 3.2)))
        let storey = height / CGFloat(courses)
        var stonework = BoxMesh()
        for (a, b) in edges {
            let dx = b.x - a.x, dz = a.y - b.y, length = hypot(dx, dz)
            guard length > 2.4 else { continue }
            let right = SIMD3(Float(dx / length), 0, Float(dz / length))
            let forward = SIMD3(-right.z, 0, right.x)
            let origin = SIMD3(Float((a.x + b.x) / 2), 0, Float(-(a.y + b.y) / 2))
            let outward: Float = area > 0 ? -1 : 1
            func beam(_ width: CGFloat, _ h: CGFloat, _ depth: CGFloat,
                      x: CGFloat = 0, y: CGFloat, offset: CGFloat, material: Finish) {
                let center = origin + right * Float(x) + forward * (outward * Float(offset))
                    + SIMD3(0, Float(y), 0)
                stonework.add(width, h, depth, center: center, right: right, finish: material)
            }
            // Narrow end faces read as solid service cores instead of tiny repeated windows.
            if length < 13 {
                beam(length - 0.08, height - 0.3, 0.22, y: height / 2, offset: 0.28, material: .stone)
                for floor in 1..<courses {
                    beam(length - 0.08, 0.08, 0.03, y: CGFloat(floor) * storey,
                         offset: 0.405, material: .joint)
                }
                continue
            }
            // The existing glazing remains behind raised stone brows and slender piers.
            for floor in 1..<courses {
                beam(length - 0.10, 0.50, 0.64, y: CGFloat(floor) * storey,
                     offset: 0.30, material: .stone)
                beam(length - 0.10, 0.12, 0.72, y: CGFloat(floor) * storey + 0.31,
                     offset: 0.34, material: .edgeStone)
            }
            let bays = max(2, Int((length / 5.7).rounded()))
            for column in 0...bays {
                let x = -length / 2 + CGFloat(column) * length / CGFloat(bays)
                beam(0.48, height - 0.7, 0.72, x: x, y: height / 2,
                     offset: 0.36, material: .edgeStone)
            }
            beam(length, 0.9, 0.86, y: height - 0.28, offset: 0.30, material: .stone)
        }
        stonework.install(named: "xinyi-city-hall-stonework", in: root)

        var roof = BoxMesh()
        for (a, b) in roofJoints(in: ring) {
            let dx = b.x - a.x, dz = a.y - b.y
            let length = hypot(dx, dz)
            let right = SIMD3(Float(dx / length), 0, Float(dz / length))
            let center = SIMD3(Float((a.x + b.x) / 2), Float(height + 0.165), Float(-(a.y + b.y) / 2))
            roof.add(length, 0.035, jointWidth, center: center, right: right, finish: .joint)
        }
        roof.install(named: "xinyi-city-hall-roof-joints", in: root)
    }

    /// Clip construction joints to each interior span, preserving concave roof notches.
    static func roofJoints(in ring: [CGPoint]) -> [(CGPoint, CGPoint)] {
        guard ring.count > 2 else { return [] }
        var result: [(CGPoint, CGPoint)] = []
        for transpose in [false, true] {
            let points = ring.map { transpose ? CGPoint(x: $0.y, y: $0.x) : $0 }
            let edges = Array(zip(points, points.dropFirst() + [points[0]]))
            let low = points.map(\.y).min()!, high = points.map(\.y).max()!
            for y in stride(from: ceil(low / 8) * 8, to: high, by: 8) {
                guard y > low + 0.65, y < high - 0.65 else { continue }
                var crossings: [CGFloat] = []
                for (a, b) in edges {
                    guard (a.y <= y && b.y > y) || (b.y <= y && a.y > y) else { continue }
                    crossings.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
                }
                crossings.sort()
                for index in stride(from: 0, to: crossings.count - 1, by: 2) {
                    let start = crossings[index] + 0.65, end = crossings[index + 1] - 0.65
                    guard end > start else { continue }
                    // The centerline is inside, but a short notch can intersect the box flank.
                    let halfWidth = jointWidth / 2 + 0.001
                    let strip = CGRect(x: start, y: y - halfWidth, width: end - start, height: halfWidth * 2)
                    guard !edges.contains(where: { CityRoofDetails.intersects($0.0, $0.1, rect: strip) }) else { continue }
                    result.append(transpose
                        ? (CGPoint(x: y, y: start), CGPoint(x: y, y: end))
                        : (CGPoint(x: start, y: y), CGPoint(x: end, y: y)))
                }
            }
        }
        return result
    }

    private enum Finish: Int, CaseIterable {
        case stone, edgeStone, joint
    }

    /// Write the ledges directly into one geometry rather than allocating thousands of scene nodes.
    private struct BoxMesh {
        private var vertices: [SCNVector3] = []
        private var normals: [SCNVector3] = []
        private var indices = Array(repeating: [Int32](), count: Finish.allCases.count)

        mutating func add(_ width: CGFloat, _ height: CGFloat, _ depth: CGFloat,
                          center: SIMD3<Float>, right: SIMD3<Float>, finish: Finish) {
            let up = SIMD3<Float>(0, 1, 0)
            let front = SIMD3(-right.z, 0, right.x)
            let x = right * Float(width / 2)
            let y = up * Float(height / 2)
            let z = front * Float(depth / 2)
            face(center + z, across: x, vertical: y, normal: front, finish: finish)
            face(center - z, across: -x, vertical: y, normal: -front, finish: finish)
            face(center + x, across: -z, vertical: y, normal: right, finish: finish)
            face(center - x, across: z, vertical: y, normal: -right, finish: finish)
            face(center + y, across: x, vertical: -z, normal: up, finish: finish)
            face(center - y, across: x, vertical: z, normal: -up, finish: finish)
        }

        private mutating func face(_ center: SIMD3<Float>, across u: SIMD3<Float>, vertical v: SIMD3<Float>,
                                   normal: SIMD3<Float>, finish: Finish) {
            let first = Int32(vertices.count)
            for point in [center - u - v, center + u - v, center + u + v, center - u + v] {
                vertices.append(SCNVector3(point.x, point.y, point.z))
                normals.append(SCNVector3(normal.x, normal.y, normal.z))
            }
            indices[finish.rawValue].append(contentsOf: [first, first + 1, first + 2, first, first + 2, first + 3])
        }

        @MainActor
        func install(named name: String, in root: SCNNode) {
            guard !vertices.isEmpty else { return }
            let active = Finish.allCases.filter { !indices[$0.rawValue].isEmpty }
            let geometry = SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals)],
                                       elements: active.map {
                                           SCNGeometryElement(indices: indices[$0.rawValue], primitiveType: .triangles)
                                       })
            let materials = [stone, edgeStone, joint]
            geometry.materials = active.map { materials[$0.rawValue] }
            let node = SCNNode(geometry: geometry)
            node.name = name
            root.addChildNode(node)
        }
    }
    private static func material(_ rgb: Int) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = CityStreetSurface.color(rgb)
        material.lightingModel = .lambert
        material.roughness.contents = 0.95
        return material
    }
    private static let stone = material(0xbda698)
    private static let edgeStone = material(0xd1bfa9)
    private static let joint = material(0x969688)
}
#endif
