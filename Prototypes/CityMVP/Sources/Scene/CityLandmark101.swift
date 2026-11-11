#if SAVVY_CITY_MVP
import UIKit
import SceneKit
import simd

/// Original architectural illustration on the district's existing ground anchor.
@MainActor
enum CityLandmark101 {
    private enum Finish: Int, CaseIterable {
        case glass, recess, fascia, roof
    }

    private struct Ring {
        let y: Float
        let halfSpan: Float
        let cut: Float
        let finishBelow: Finish

        init(_ y: Float, _ halfSpan: Float, _ cut: Float, _ finishBelow: Finish = .recess) {
            self.y = y
            self.halfSpan = halfSpan
            self.cut = cut
            self.finishBelow = finishBelow
        }

        var corners: [SIMD3<Float>] {
            let h = halfSpan
            let k = h - cut
            return [
                .init(-k, y, -h), .init(k, y, -h), .init(h, y, -k), .init(h, y, k),
                .init(k, y, h), .init(-k, y, h), .init(-h, y, k), .init(-h, y, -k),
            ]
        }
    }

    private struct ShellProfile {
        let name: String
        let rings: [Ring]
        var capTop = false
    }

    static let podiumHeight = 25.0
    // East/north coordinates, shared by the mesh, storefronts and shadow caster.
    static let podiumFootprint: [CGPoint] = {
        let fallback: [CGPoint] = [
            .init(x: -62.5, y: -47.5), .init(x: 62.5, y: -47.5),
            .init(x: 62.5, y: 47.5), .init(x: -62.5, y: 47.5),
        ]
        guard let way = CitySceneData.elements?.first(where: { $0["id"] as? Int == 1_159_328_965 }),
              let geometry = way["geometry"] as? [[String: Double]], geometry.count >= 4 else { return fallback }
        var points: [CGPoint] = []
        for vertex in geometry {
            guard let lat = vertex["lat"], let lon = vertex["lon"], lat.isFinite, lon.isFinite else { return fallback }
            let point = CGPoint(x: (lon - CityScenePlace.originLongitude) * 100_850,
                                y: (lat - CityScenePlace.originLatitude) * 111_195)
            guard abs(point.x) < 250, abs(point.y) < 250 else { return fallback }
            points.append(point)
        }
        if points.first == points.last { points.removeLast() }
        return points.count >= 3 ? points : fallback
    }()
    private static let podiumPath: UIBezierPath = {
        let path = UIBezierPath()
        path.move(to: podiumFootprint[0])
        podiumFootprint.dropFirst().forEach { path.addLine(to: $0) }
        path.close()
        return path
    }()
    // Preserve the existing roof contact while the source footprint replaces the box.
    static let pinContact = SIMD3(0.0, podiumHeight, 41.5)
    private static let mastSides = 12
    private static let mast: [(bottom: Float, top: Float, foot: Double, tip: Double, collar: Bool)] = [
        (468, 473, 2.30, 2.00, true),
        (473, 488, 2.00, 1.28, false),
        (488, 490, 1.38, 1.32, true),
        (490, 508, 1.27, 0.22, false),
    ]

    private static let shells: [ShellProfile] = {
        let shaft = ShellProfile(name: "city-101-shaft", rings: [
            Ring(25, 32.5, 4.6),
            Ring(27, 32.5, 4.6, .recess),
            Ring(74, 32.0, 5.4, .glass),
            Ring(77, 32.2, 5.4, .fascia),
            Ring(83, 30.8, 5.1, .glass),
            Ring(90, 22.6, 4.6, .roof),
        ])

        let tiers = (0..<8).map { index in
            let base = Float(90 + index * 42)
            // A recessed foot, flared curtain wall and slim projecting collar
            // give each of the eight tiers a distinct shoulder.
            return ShellProfile(name: "city-101-tier-\(index + 1)", rings: [
                Ring(base, 22.6, 4.6),
                Ring(base + 2.0, 22.6, 4.6, .recess),
                Ring(base + 35.5, 28.6, 5.8, .glass),
                Ring(base + 36.2, 29.2, 6.0, .recess),
                Ring(base + 38.1, 29.4, 6.0, .fascia),
                Ring(base + 39.6, 28.7, 5.8, .roof),
                Ring(base + 41.2, 22.6, 4.6, .roof),
                Ring(base + 42.0, 22.6, 4.6, .recess),
            ])
        }

        let crown = ShellProfile(name: "city-101-crown", rings: [
            Ring(426, 22.6, 4.6),
            Ring(429, 19.2, 4.3, .roof),
            Ring(433, 16.8, 4.2, .fascia),
            Ring(442, 15.2, 3.8, .glass),
            Ring(444, 15.4, 3.8, .fascia),
            Ring(450, 13.2, 3.6, .recess),
            Ring(457, 12.0, 3.2, .glass),
            Ring(460, 10.5, 3.0, .roof),
            Ring(462, 10.5, 3.0, .fascia),
            Ring(468, 5.0, 1.5, .roof),
        ], capTop: true)
        return [shaft] + tiers + [crown]
    }()

    static var shadowBands: [[SIMD3<Float>]] {
        shells.flatMap { shell in
            zip(shell.rings, shell.rings.dropFirst()).map { lower, upper in
                lower.corners + upper.corners
            }
        }
    }

    static func containsInterior(_ eye: SIMD3<Double>) -> Bool {
        guard eye.x.isFinite, eye.y.isFinite, eye.z.isFinite, eye.y > 0 else { return false }
        let x = abs(eye.x), y = eye.y, z = abs(eye.z)
        if y < podiumHeight {
            return podiumPath.contains(CGPoint(x: eye.x, y: -eye.z))
        }

        for profile in shells {
            guard let bottom = profile.rings.first, let top = profile.rings.last,
                  y >= Double(bottom.y), y < Double(top.y) else { continue }
            for (lower, upper) in zip(profile.rings, profile.rings.dropFirst()) where y < Double(upper.y) {
                let fraction = (y - Double(lower.y)) / Double(upper.y - lower.y)
                let halfSpan = Double(lower.halfSpan) + fraction * Double(upper.halfSpan - lower.halfSpan)
                let cut = Double(lower.cut) + fraction * Double(upper.cut - lower.cut)
                return max(x, z) < halfSpan && x + z < 2 * halfSpan - cut
            }
        }

        for (index, part) in mast.enumerated() where y >= Double(part.bottom) && y < Double(part.top) {
            let fraction = (y - Double(part.bottom)) / Double(part.top - part.bottom)
            var radius = part.foot + fraction * (part.tip - part.foot)
            if index > 0, y == Double(part.bottom) { radius = min(radius, mast[index - 1].tip) }
            // The incircle is inside all twelve sides regardless of the primitive's rotation.
            return hypot(x, z) < radius * cos(.pi / Double(mastSides))
        }
        return false
    }

    static func hidesPinContact(from eye: SIMD3<Double>) -> Bool {
        let delta = eye - pinContact
        let length = simd_length(delta)
        guard length > 2, delta.z < 0, eye.y > podiumHeight else { return false }
        let direction = delta / length
        let towerHalfSpan = Double(shells.flatMap(\.rings).map(\.halfSpan).max() ?? 0)
        let limit = min(length, (pinContact.z + towerHalfSpan) / -direction.z,
                        (Double(mast.last!.top) - pinContact.y) / direction.y)
        // Sample the ray only where it can intersect the tower's actual shells.
        for distance in stride(from: 2.0, to: limit, by: 3) {
            if containsInterior(pinContact + direction * distance) { return true }
        }
        return false
    }

    static func add(to root: SCNNode) {
        let tower = SCNNode()
        tower.name = "surface-landmark-101"
        root.addChildNode(tower)

        let shape = SCNShape(path: podiumPath, extrusionDepth: podiumHeight)
        let wall = material(0xa5a197)
        shape.materials = [material(0xb7b9a6), wall, wall]
        let podiumNode = SCNNode(geometry: shape)
        podiumNode.name = "city-101-podium"
        podiumNode.eulerAngles.x = -.pi / 2
        podiumNode.position.y = Float(podiumHeight / 2)
        tower.addChildNode(podiumNode)

        let finishes = makeFinishes()
        for (index, profile) in shells.enumerated() {
            let glassPhase = CGFloat((index * 3) % 16) / 16
            tower.addChildNode(shell(profile.name, profile.rings, finishes: finishes,
                                     glassPhase: glassPhase, capTop: profile.capTop))
        }

        let antenna = material(0xc7cfce)
        let joint = material(0x647c7d)
        for (index, part) in mast.enumerated() {
            let cone = SCNCone(topRadius: CGFloat(part.tip), bottomRadius: CGFloat(part.foot),
                               height: CGFloat(part.top - part.bottom))
            cone.radialSegmentCount = mastSides
            cone.firstMaterial = part.collar ? joint : antenna
            let node = SCNNode(geometry: cone)
            node.name = "city-101-antenna-\(index + 1)"
            node.position.y = (part.bottom + part.top) / 2
            tower.addChildNode(node)
        }
    }

    private static func shell(_ name: String, _ rings: [Ring], finishes: [SCNMaterial],
                              glassPhase: CGFloat, capTop: Bool) -> SCNNode {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var indices = Array(repeating: [Int32](), count: Finish.allCases.count)

        func append(_ points: [SIMD3<Float>], normal: SIMD3<Float>, uv: [CGPoint],
                    faces: [Int32], finish: Finish) {
            let start = Int32(positions.count)
            positions += points.map { SCNVector3($0.x, $0.y, $0.z) }
            normals += Array(repeating: SCNVector3(normal.x, normal.y, normal.z), count: points.count)
            texcoords += uv
            indices[finish.rawValue] += faces.map { start + $0 }
        }

        for (lower, upper) in zip(rings, rings.dropFirst()) {
            let bottom = lower.corners
            let top = upper.corners
            let floors = CGFloat((upper.y - lower.y) / 34)
            for side in bottom.indices {
                let next = (side + 1) % bottom.count
                let lowerEdge = bottom[next] - bottom[side]
                let rise = top[side] - bottom[side]
                let normal = simd_normalize(simd_cross(rise, lowerEdge))
                let width = side.isMultiple(of: 2) ? CGFloat(1) : 0.18
                let finish = upper.finishBelow
                let sidePhase: CGFloat = side.isMultiple(of: 4) ? 0 : 0.25
                // Offset whole window bays so the same panes do not light up on every tier.
                let offset = sidePhase + (finish == .glass ? glassPhase : 0)
                let verticalSpan = finish == .fascia ? 1 : floors
                append([bottom[side], bottom[next], top[next], top[side]], normal: normal,
                       uv: [.init(x: offset, y: 0), .init(x: offset + width, y: 0),
                            .init(x: offset + width, y: verticalSpan), .init(x: offset, y: verticalSpan)],
                       faces: [0, 2, 1, 0, 3, 2], finish: finish)
            }
        }

        if capTop, let top = rings.last {
            let corners = top.corners
            for side in corners.indices {
                let next = (side + 1) % corners.count
                append([.init(0, top.y, 0), corners[next], corners[side]], normal: .init(0, 1, 0),
                       uv: [.zero, .zero, .zero], faces: [0, 1, 2], finish: .roof)
            }
        }

        let groups = indices.indices.filter { !indices[$0].isEmpty }
        let mesh = SCNGeometry(
            sources: [.init(vertices: positions), .init(normals: normals), .init(textureCoordinates: texcoords)],
            elements: groups.map { SCNGeometryElement(indices: indices[$0], primitiveType: .triangles) }
        )
        mesh.materials = groups.map { finishes[$0] }
        let node = SCNNode(geometry: mesh)
        node.name = name
        return node
    }

    private static func makeFinishes() -> [SCNMaterial] {
        let glass = material(0x31585a)
        glass.name = "city-lit-facade"
        glass.diffuse.contents = glassImage
        glass.emission.contents = lightImage
        glass.emission.intensity = 0
        glass.specular.contents = UIColor(white: 0.30, alpha: 1)
        glass.shininess = 0.27
        for property in [glass.diffuse, glass.emission] {
            property.wrapS = .repeat
            property.wrapT = .repeat
            property.mipFilter = .linear
        }
        let collar = material(0x7b9693)
        collar.diffuse.contents = collarImage
        collar.diffuse.wrapS = .repeat
        collar.diffuse.mipFilter = .linear
        return [glass, material(0x3c5353), collar, material(0x617a72)]
    }

    private static func material(_ hex: Int) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = color(hex)
        material.roughness.contents = 0.72
        return material
    }

    private static func color(_ hex: Int) -> UIColor {
        .init(red: CGFloat((hex >> 16) & 255) / 255,
              green: CGFloat((hex >> 8) & 255) / 255,
              blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    private static let glassImage = facadeTexture(emissive: false)
    private static let lightImage = facadeTexture(emissive: true)
    private static let collarImage: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 128, height: 32)
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            let g = output.cgContext
            g.setFillColor(color(0x9aafa6).cgColor)
            g.fill(CGRect(origin: .zero, size: size))
            g.setFillColor(color(0xb2c1b6).cgColor)
            g.fill(CGRect(x: 0, y: 2, width: size.width, height: 4))
            g.setFillColor(color(0x6a827d).cgColor)
            g.fill(CGRect(x: 0, y: 25, width: size.width, height: 5))
            for seam in stride(from: 0, to: 128, by: 8) {
                g.fill(CGRect(x: seam, y: 7, width: 1, height: 17))
            }
        }
    }()

    private static func facadeTexture(emissive: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 224, height: 192)
        let panes = [0x305051, 0x3b6464, 0x486f6b, 0x507a76, 0x5b8581, 0x66918a].map(color)
        let warm = [0x60482e, 0x89673b, 0xa3804e, 0x695443].map(color)
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            let g = output.cgContext
            g.setFillColor((emissive ? UIColor.black : color(0x304d4c)).cgColor)
            g.fill(CGRect(origin: .zero, size: size))
            for row in 0..<8 {
                for column in 0..<16 {
                    let variation = (row * 11 + column * 17 + row * column * 3) % 23
                    let x = CGFloat(column * 14)
                    let y = CGFloat(row * 24)
                    if emissive {
                        guard variation < 6 else { continue }
                        g.setFillColor(warm[variation % warm.count].cgColor)
                        g.fill(CGRect(x: x + 3, y: y + 4, width: 8, height: 12))
                    } else {
                        g.setFillColor(panes[variation % panes.count].cgColor)
                        g.fill(CGRect(x: x + 1, y: y + 2, width: 12, height: 19))
                        g.setFillColor(color(0x8fa9a2).withAlphaComponent(0.52).cgColor)
                        g.fill(CGRect(x: x + 1, y: y + 2, width: 1, height: 19))
                        g.fill(CGRect(x: x + 2, y: y + 2, width: 11, height: 1))
                        if column.isMultiple(of: 4) {
                            g.setFillColor(color(0x7e9993).withAlphaComponent(0.72).cgColor)
                            g.fill(CGRect(x: x, y: y, width: 1, height: 24))
                        }
                    }
                }
                if !emissive {
                    g.setFillColor(color(row.isMultiple(of: 2) ? 0x637b7e : 0x4c6669).cgColor)
                    g.fill(CGRect(x: 0, y: CGFloat(row * 24 + 21), width: size.width, height: 1))
                }
            }
        }
    }
}
#endif
