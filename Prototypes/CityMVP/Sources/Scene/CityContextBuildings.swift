#if SAVVY_CITY_MVP
import SceneKit
import UIKit

/// Low-detail public map context, separate from the hero district and saved places.
/// Geometry is merged spatially; it introduces no photos, textures or ground sheet.
@MainActor
enum CityContextBuildings {
    static let enabled = CityMVPPreviewConfiguration.enabled
        || (CityDistrictTrace.enabled && ProcessInfo.processInfo.arguments.contains("--verify-context-ring"))
    static let nodePrefix = "xinyi-context/"
    static let halfExtent = 1_500.0
    static let chunkSize = 300.0
    static let usesSurfaceDetail = CityMVPPreviewConfiguration.enabled
        && !(CityMVPPreviewConfiguration.inspectsPreview
             && ProcessInfo.processInfo.arguments.contains("--inspect-legacy-context-surface"))
    // Original illustrative roof aligned to the bundled stadium footprint.
    // The city's published Dome plan gives64m above ground; paneling and eaves
    // below are stylized, not surveyed architecture or place-memory evidence.
    // https://udd.gov.taipei/assets/162-8848/Documents/1080829遠雄簡報檔.pdf
    static let stadiumWayID = 442195153

    static var elements: [[String: Any]] {
        guard let url = Bundle.main.url(forResource: "taipei-context-buildings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = object["elements"] as? [[String: Any]] else { return [] }
        return elements
    }

    struct Footprint {
        let id: Int
        let ring: [CGPoint] // east/north metres, counterclockwise
        let height: Double // tag-derived or illustrative; not verified
        let roofTriangles: [Int32]
    }

    static func footprint(_ item: [String: Any], excluding heroIDs: Set<Int>) -> Footprint? {
        guard let id = item["id"] as? Int, !heroIDs.contains(id),
              let tags = item["tags"] as? [String: String],
              let building = tags["building"], building != "no", building != "roof",
              (Int(tags["layer"] ?? "0") == 0),
              tags["location"] != "underground", tags["tunnel"] != "yes",
              tags["bridge"] == nil || tags["bridge"] == "no",
              let geometry = item["geometry"] as? [[String: Double]],
              geometry.count >= 4, geometry.count <= 512 else { return nil }
        for key in ["min_height", "building:min_level"] {
            if let raw = tags[key] {
                guard let value = Double(raw.replacingOccurrences(of: " m", with: "")),
                      value.isFinite, value == 0 else { return nil }
            }
        }
        var ring: [CGPoint] = []
        for vertex in geometry {
            guard let lat = vertex["lat"], let lon = vertex["lon"], lat.isFinite, lon.isFinite else { return nil }
            let point = CGPoint(x: (lon - CityScenePlace.originLongitude) * 100850,
                                y: (lat - CityScenePlace.originLatitude) * 111195)
            guard abs(point.x) <= halfExtent, abs(point.y) <= halfExtent else { return nil }
            if let last = ring.last, hypot(last.x - point.x, last.y - point.y) < 0.001 { continue }
            ring.append(point)
        }
        guard let first = ring.first, let last = ring.last,
              hypot(first.x - last.x, first.y - last.y) < 0.01 else { return nil }
        ring.removeLast()
        guard ring.count >= 3, isSimple(ring) else { return nil }
        // Do not insert a new dataset's walls into the authored hero square.
        // A crossing polygon is excluded even if its vertices are outside it.
        let bounds = ring.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        guard !bounds.intersects(CGRect(x: -650, y: -650, width: 1300, height: 1300)) else { return nil }
        let area = signedArea(ring)
        guard abs(area) >= 1 else { return nil }
        if area < 0 { ring.reverse() }
        guard let triangles = triangulate(ring) else { return nil }
        let height = CitySceneData.buildingHeight(tags, way: id)
        guard height.isFinite, height > 0 else { return nil }
        return .init(id: id, ring: ring, height: height, roofTriangles: triangles)
    }

    private static func signedArea(_ ring: [CGPoint]) -> Double {
        zip(ring, ring.dropFirst() + [ring[0]]).reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y } / 2
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    /// Reject crossing/touching rings and overlapping reverse edges before
    /// tessellation. Removing a collinear roof vertex must not hide invalid walls.
    private static func isSimple(_ ring: [CGPoint]) -> Bool {
        let epsilon = 0.000001
        func onSegment(_ a: CGPoint, _ b: CGPoint, _ p: CGPoint) -> Bool {
            abs(cross(a, b, p)) <= epsilon
                && p.x >= min(a.x, b.x) - epsilon && p.x <= max(a.x, b.x) + epsilon
                && p.y >= min(a.y, b.y) - epsilon && p.y <= max(a.y, b.y) + epsilon
        }
        for i in ring.indices {
            let a = ring[i], b = ring[(i + 1) % ring.count], c = ring[(i + 2) % ring.count]
            if abs(cross(a, b, c)) <= epsilon,
               (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y) < 0 { return false }
            for j in ring.indices where j > i + 1 && !(i == 0 && j == ring.count - 1) {
                let c = ring[j], d = ring[(j + 1) % ring.count]
                let abC = cross(a, b, c), abD = cross(a, b, d)
                let cdA = cross(c, d, a), cdB = cross(c, d, b)
                let abCrosses = (abC > epsilon && abD < -epsilon) || (abC < -epsilon && abD > epsilon)
                let cdCrosses = (cdA > epsilon && cdB < -epsilon) || (cdA < -epsilon && cdB > epsilon)
                if (abCrosses && cdCrosses) || onSegment(a, b, c) || onSegment(a, b, d)
                    || onSegment(c, d, a) || onSegment(c, d, b) { return false }
            }
        }
        return true
    }

    /// Ear clipping preserves concave courtyards/notches; a fan would bridge them.
    private static func triangulate(_ ring: [CGPoint]) -> [Int32]? {
        var remaining = Array(ring.indices), result: [Int32] = []
        while remaining.count > 3 {
            var clipped = false
            for i in remaining.indices {
                let a = remaining[(i + remaining.count - 1) % remaining.count]
                let b = remaining[i], c = remaining[(i + 1) % remaining.count]
                let turn = cross(ring[a], ring[b], ring[c])
                if abs(turn) < 0.000001 {
                    remaining.remove(at: i); clipped = true; break
                }
                guard turn > 0 else { continue }
                let blocked = remaining.contains { p in
                    p != a && p != b && p != c
                        && cross(ring[a], ring[b], ring[p]) >= -0.000001
                        && cross(ring[b], ring[c], ring[p]) >= -0.000001
                        && cross(ring[c], ring[a], ring[p]) >= -0.000001
                }
                if !blocked {
                    result += [Int32(a), Int32(b), Int32(c)]
                    remaining.remove(at: i); clipped = true; break
                }
            }
            guard clipped, remaining.count >= 3 else { return nil }
        }
        guard cross(ring[remaining[0]], ring[remaining[1]], ring[remaining[2]]) > 0.000001 else { return nil }
        result += remaining.map(Int32.init)
        return result
    }

    final class Builder {
        private struct Mesh {
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var colors: [SIMD4<Float>] = []
            var indices: [Int32] = []
        }
        private var meshes: [String: Mesh] = [:]
        private var accepted = Set<Int>()
        private let heroIDs: Set<Int>
        private let details: Bool
        private(set) var vertexCount = 0
        var buildingCount: Int { accepted.count }
        var chunkCount: Int { meshes.count }

        init(heroElements: [[String: Any]], details: Bool = usesSurfaceDetail) {
            self.details = details
            heroIDs = Set(heroElements.compactMap { item in
                (item["tags"] as? [String: String])?["building"] != nil ? item["id"] as? Int : nil
            })
        }

        func append(_ item: [String: Any]) {
            guard let footprint = CityContextBuildings.footprint(item, excluding: heroIDs),
                  accepted.insert(footprint.id).inserted else { return }
            let ring = footprint.ring
            let center = ring.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let key = "\(Int(floor(center.x / Double(ring.count) / chunkSize)))/\(Int(floor(center.y / Double(ring.count) / chunkSize)))"
            var mesh = meshes.removeValue(forKey: key) ?? Mesh()
            let base = Int32(mesh.vertices.count), height = Float(footprint.height)
            let palette: [SIMD4<Float>] = [rgba(0xC9C3B7), rgba(0xC3C8C6), rgba(0xCAC3BC), rgba(0xBBC4CB)]
            let colorIndex = (footprint.id % palette.count + palette.count) % palette.count
            let wallColor = details ? palette[colorIndex] : SIMD4<Float>(repeating: 1)
            let roofColor = details ? rgba(0xD5D2C8) : SIMD4<Float>(repeating: 1)
            for p in ring {
                mesh.vertices.append(SCNVector3(Float(p.x), height, Float(-p.y)))
                mesh.normals.append(SCNVector3(0, 1, 0))
                mesh.colors.append(roofColor)
            }
            let dome = details && footprint.id == stadiumWayID
                && (item["tags"] as? [String: String])?["building"] == "stadium"
            if !dome { mesh.indices += footprint.roofTriangles.map { base + $0 } }
            for (a, b) in zip(ring, ring.dropFirst() + [ring[0]]) {
                let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
                guard length > 0.001 else { continue }
                let offset = Int32(mesh.vertices.count)
                mesh.vertices += [SCNVector3(Float(a.x), 0, Float(-a.y)), SCNVector3(Float(b.x), 0, Float(-b.y)),
                                  SCNVector3(Float(b.x), height, Float(-b.y)), SCNVector3(Float(a.x), height, Float(-a.y))]
                mesh.normals += Array(repeating: SCNVector3(Float(dy / length), 0, Float(dx / length)), count: 4)
                mesh.colors += Array(repeating: wallColor, count: 4)
                mesh.indices += [0, 1, 2, 0, 2, 3].map { offset + Int32($0) }
                if details && height >= 8 && length >= 6 {
                    // Two coarse glazing bands are enough at this outer-ring LOD.
                    // They stay in the same spatial mesh/material, no facade images.
                    let normal = SCNVector3(Float(dy / length), 0, Float(dx / length))
                    let first = CGPoint(x: a.x + dx * 0.12, y: a.y + dy * 0.12)
                    let last = CGPoint(x: a.x + dx * 0.88, y: a.y + dy * 0.88)
                    for fraction: Float in [0.34, 0.68] {
                        let middle = height * fraction, half = min(0.9, height * 0.055)
                        let start = Int32(mesh.vertices.count)
                        let ax = Float(first.x) + normal.x * 0.08, az = Float(-first.y) + normal.z * 0.08
                        let bx = Float(last.x) + normal.x * 0.08, bz = Float(-last.y) + normal.z * 0.08
                        mesh.vertices += [SCNVector3(ax, middle - half, az), SCNVector3(bx, middle - half, bz),
                                          SCNVector3(bx, middle + half, bz), SCNVector3(ax, middle + half, az)]
                        mesh.normals += Array(repeating: normal, count: 4)
                        mesh.colors += Array(repeating: rgba(0x687C87), count: 4)
                        mesh.indices += [0, 1, 2, 0, 2, 3].map { start + Int32($0) }
                    }
                }
            }
            if dome { appendDome(footprint, to: &mesh) }
            vertexCount += mesh.vertices.count - Int(base)
            meshes[key] = mesh
        }

        func add(to root: SCNNode) {
            let material = SCNMaterial()
            material.name = "city-context-neutral"
            material.diffuse.contents = details ? UIColor.white : UIColor(red: 0.76, green: 0.78, blue: 0.77, alpha: 1)
            material.lightingModel = .lambert
            for (key, mesh) in meshes.sorted(by: { $0.key < $1.key }) {
                let colors = mesh.colors.withUnsafeBytes { Data($0) }
                let colorSource = SCNGeometrySource(data: colors, semantic: .color, vectorCount: mesh.colors.count,
                    usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
                    dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
                let geometry = SCNGeometry(sources: [.init(vertices: mesh.vertices), .init(normals: mesh.normals), colorSource],
                                           elements: [.init(indices: mesh.indices, primitiveType: .triangles)])
                geometry.materials = [material]
                let node = SCNNode(geometry: geometry)
                node.name = nodePrefix + key
                root.addChildNode(node)
            }
            CityDistrictTrace.write("context-build\t\(buildingCount)\t\(chunkCount)\t\(vertexCount)")
        }

        private func rgba(_ rgb: UInt32) -> SIMD4<Float> {
            SIMD4(Float((rgb >> 16) & 255) / 255, Float((rgb >> 8) & 255) / 255, Float(rgb & 255) / 255, 1)
        }

        private func appendDome(_ footprint: Footprint, to mesh: inout Mesh) {
            // A shell spans the small entrance recesses; a convex roof outline
            // avoids folding strips into those notches. Wall footprints stay exact.
            let ring = domeOutline(footprint.ring), count = ring.count
            let bounds = ring.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let rx = Float(bounds.width / 2), rz = Float(bounds.height / 2)
            let eaves = Float(footprint.height), rise = max(1, 64 - eaves)
            let base = Int32(mesh.vertices.count), bands = 10
            for band in 0..<bands {
                let angle = Float(band) / Float(bands) * .pi / 2
                let scale = cos(angle), elevation = eaves + rise * sin(angle)
                for p in ring {
                    let x = Float(p.x - center.x) * scale, z = Float(center.y - p.y) * scale
                    let normal = simd_normalize(SIMD3(x / (rx * rx), sin(angle) / rise, z / (rz * rz)))
                    mesh.vertices.append(SCNVector3(Float(center.x) + x, elevation, Float(-center.y) + z))
                    mesh.normals.append(SCNVector3(normal))
                    mesh.colors.append(rgba(band.isMultiple(of: 2) ? 0xCFD4D8 : 0xC8CFD4))
                }
            }
            for band in 0..<(bands - 1) {
                for index in 0..<count {
                    let next = (index + 1) % count
                    let a = base + Int32(band * count + index), b = base + Int32(band * count + next)
                    let c = base + Int32((band + 1) * count + next), d = base + Int32((band + 1) * count + index)
                    mesh.indices += [a, b, c, a, c, d]
                }
            }
            let top = Int32(mesh.vertices.count)
            mesh.vertices.append(SCNVector3(Float(center.x), eaves + rise, Float(-center.y)))
            mesh.normals.append(SCNVector3(0, 1, 0)); mesh.colors.append(rgba(0xD4D9DD))
            for index in 0..<count {
                mesh.indices += [base + Int32((bands - 1) * count + index),
                                 base + Int32((bands - 1) * count + (index + 1) % count), top]
            }
        }

        private func domeOutline(_ points: [CGPoint]) -> [CGPoint] {
            let ordered = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
            func half(_ input: [CGPoint]) -> [CGPoint] {
                var result: [CGPoint] = []
                for point in input {
                    while result.count >= 2 && cross(result[result.count - 2], result[result.count - 1], point) <= 0 {
                        result.removeLast()
                    }
                    result.append(point)
                }
                return result
            }
            return Array(half(ordered).dropLast()) + Array(half(Array(ordered.reversed())).dropLast())
        }
    }
}
#endif
