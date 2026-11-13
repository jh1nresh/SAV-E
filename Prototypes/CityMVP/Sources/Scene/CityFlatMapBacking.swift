#if SAVVY_CITY_MVP
import MapKit
import SceneKit

/// A north-up, zero-pitch native snapshot is a ground texture, never a second
/// tilted map. The authored street atlas and buildings remain above this plane.
@MainActor
enum CityFlatMapBacking {
    static let name = "xinyi-flat-native-backing"
    static let halfExtent = 2_500.0

    static func prepare(registration: CityDistrictRegistration, night: Bool) async throws -> SCNNode {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: registration.mapCoordinate(CityDistrictCamera.coordinate(x: 0, z: 0)),
                                            latitudinalMeters: 5_400, longitudinalMeters: 5_400)
        options.size = CGSize(width: 2048, height: 2048)
        options.scale = 1
        options.mapType = .standard
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: night ? .dark : .light)
        // The global-actor holder is Sendable. Its MapKit object never crosses
        // into the cancellation handler's arbitrary executor.
        let request = CityFlatMapSnapshotRequest(options: options)
        try await withTaskCancellationHandler(operation: { @MainActor in
            try Task.checkCancellation()
            try await request.start()
        }, onCancel: {
            request.cancel()
        }, isolation: MainActor.shared)
        try Task.checkCancellation()
        let snapshot = try request.completedSnapshot()
        let e = halfExtent
        let corners = [SIMD3(-e, -0.4, -e), SIMD3(e, -0.4, -e), SIMD3(e, -0.4, e), SIMD3(-e, -0.4, e)]
        let uv = corners.map { world in
            let point = snapshot.point(for: registration.mapCoordinate(CityDistrictCamera.coordinate(x: world.x, z: world.z)))
            return CGPoint(x: point.x / options.size.width, y: point.y / options.size.height)
        }
        let minU = uv.map(\.x).min() ?? 0
        let maxU = uv.map(\.x).max() ?? 1
        let minV = uv.map(\.y).min() ?? 0
        let maxV = uv.map(\.y).max() ?? 1
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: corners.map { SCNVector3(Float($0.x), Float($0.y), Float($0.z)) }),
                                             SCNGeometrySource(textureCoordinates: uv)],
                                   elements: [SCNGeometryElement(indices: [Int32(0), 2, 1, 0, 3, 2], primitiveType: .triangles)])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = snapshot.image
        material.isDoubleSided = true
        material.writesToDepthBuffer = true
        // Feather the 5km boundary in world space; there is no rectangular opaque
        // edge. The inner 4km remains fully opaque before model blending begins.
        material.shaderModifiers = [.surface: """
        float2 uv = _surface.diffuseTexcoord;
        float2 normalized = (uv - float2(\(minU), \(minV))) / float2(\(maxU - minU), \(maxV - minV));
        float edge = min(min(normalized.x, 1.0 - normalized.x), min(normalized.y, 1.0 - normalized.y));
        _surface.diffuse.a *= smoothstep(0.0, 0.10, edge);
        """]
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.renderingOrder = -2
        return node
    }
}
/// Owns the non-Sendable MapKit request on the UI actor for its whole lifetime.
@MainActor
private final class CityFlatMapSnapshotRequest {
    private let snapshotter: MKMapSnapshotter
    private var result: MKMapSnapshotter.Snapshot?

    init(options: MKMapSnapshotter.Options) {
        snapshotter = MKMapSnapshotter(options: options)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            snapshotter.start { [self] snapshot, error in
                if let snapshot {
                    // Keep MapKit's non-Sendable result on the UI actor. Only
                    // completion crosses the continuation, never the snapshot.
                    result = snapshot
                    continuation.resume()
                }
                else { continuation.resume(throwing: error ?? MKError(.unknown)) }
            }
        }
    }

    func completedSnapshot() throws -> MKMapSnapshotter.Snapshot {
        guard let result else { throw MKError(.unknown) }
        return result
    }

    nonisolated func cancel() {
        Task { @MainActor [self] in snapshotter.cancel() }
    }
}
#endif
