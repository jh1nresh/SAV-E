#if SAVVY_CITY_MVP
import SceneKit
import UIKit

/// One mesh per repeated facade palette instead of one draw call and image per wall.
@MainActor
final class CityFacadeBatch {
    private struct Mesh {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var coordinates: [CGPoint] = []
        var indices: [Int32] = []
        let material: SCNMaterial
    }
    private var groups: [String: Mesh] = [:]

    func append(footprint: [CGPoint], height: CGFloat, levels: Int?, finish: CityStreetDetail.Finish, seed: Int) {
        let ring = footprint.first == footprint.last ? Array(footprint.dropLast()) : footprint
        guard ring.count > 2 else { return }
        let pairs = Array(zip(ring, ring.dropFirst() + [ring[0]]))
        let area = pairs.reduce(CGFloat.zero) { $0 + $1.0.y * $1.1.x - $1.0.x * $1.1.y }
        let key = "\(finish)-\(seed % 4)"
        var mesh: Mesh
        if let existing = groups[key] {
            mesh = existing
            groups[key] = nil // Keep array storage uniquely owned while appending.
        } else {
            let textures = CityStreetDetail.repeatedFacade(finish: finish, variant: seed % 4)
            let material = SCNMaterial()
            material.name = "city-lit-facade"
            material.diffuse.contents = textures.0; material.emission.contents = textures.1
            material.emission.intensity = 0; material.lightingModel = .lambert
            for property in [material.diffuse, material.emission] {
                property.wrapS = .repeat
                property.wrapT = .repeat
                property.mipFilter = .linear
            }
            let lightScale = CityStreetDetail.facadeLightScale
            material.emission.contentsTransform = SCNMatrix4MakeScale(lightScale, lightScale, 1)
            mesh = Mesh(material: material)
        }
        let floors = max(1, min(22, levels ?? Int((height / 3.2).rounded())))
        for (edge, pair) in pairs.enumerated() {
            let (a, b) = pair
            let dx = b.x - a.x, dz = a.y - b.y, length = hypot(dx, dz)
            guard length > 2.4 else { continue }
            let sign: CGFloat = area > 0 ? 1 : -1
            let nx = dz / length * sign, nz = -dx / length * sign
            let ax = a.x + nx * 0.13, az = -a.y + nz * 0.13
            let bx = b.x + nx * 0.13, bz = -b.y + nz * 0.13
            let base = Int32(mesh.vertices.count)
            mesh.vertices += [SCNVector3(Float(ax), 0.18, Float(az)), SCNVector3(Float(bx), 0.18, Float(bz)),
                              SCNVector3(Float(bx), Float(height - 0.18), Float(bz)), SCNVector3(Float(ax), Float(height - 0.18), Float(az))]
            mesh.normals += Array(repeating: SCNVector3(Float(nx), 0, Float(nz)), count: 4)
            let columns = CGFloat(max(1, min(36, Int((length / finish.bayWidth).rounded()))))
            let phase = CityStreetDetail.facadePhase(way: seed, edge: edge)
            let right = phase.x + columns / 2
            let top = phase.y + CGFloat(floors) / 2
            mesh.coordinates += [phase, .init(x: right, y: phase.y),
                                 .init(x: right, y: top), .init(x: phase.x, y: top)]
            mesh.indices += (area > 0 ? [0, 2, 1, 0, 3, 2] : [0, 1, 2, 0, 2, 3]).map { base + Int32($0) }
        }
        groups[key] = mesh
    }

    func add(to root: SCNNode) {
        for (key, mesh) in groups where !mesh.indices.isEmpty {
            let geometry = SCNGeometry(sources: [.init(vertices: mesh.vertices), .init(normals: mesh.normals),
                                                 .init(textureCoordinates: mesh.coordinates)],
                                       elements: [SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)])
            geometry.materials = [mesh.material]
            let node = SCNNode(geometry: geometry); node.name = "xinyi-facade-batch-\(key)"
            root.addChildNode(node)
        }
    }
}
#endif
