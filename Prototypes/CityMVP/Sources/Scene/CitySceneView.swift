#if SAVVY_CITY_MVP
import SwiftUI
import SceneKit

/// A visual layer. The native map beneath it owns every gesture and the camera.
struct CitySceneView: UIViewRepresentable {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let projection: CityDistrictCamera.Projection?
    let sceneOpacity: Double
    let sceneBlend: CityDistrictCamera.SceneBlend?
    let night: Bool
    let landmarkPoint: CGPoint?
    let nativeDistance: Double
    var onReady: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CityDistrictSurface {
        let view = CityDistrictSurface()
        context.coordinator.onReady = onReady
        context.coordinator.prepare(for: view)
        return view
    }

    func updateUIView(_ view: CityDistrictSurface, context: Context) {
        context.coordinator.onReady = onReady
        view.update(projection: projection, sceneOpacity: sceneOpacity, sceneBlend: sceneBlend, night: night,
                    movingTraffic: nativeDistance < 850 && scenePhase == .active && !reduceMotion)
        if view.hasInstalledScene, projection != nil, let landmarkPoint, view.bounds.width > 0 {
            let rendered = view.projectPoint(SCNVector3(0, 0, 0))
            let error = hypot(Double(rendered.x) - landmarkPoint.x, Double(rendered.y) - landmarkPoint.y)
            CityDistrictTrace.write("render\t\(nativeDistance)\t\(error)")
        }
    }

    static func dismantleUIView(_ view: CityDistrictSurface, coordinator: Coordinator) {
        coordinator.cancel()
        view.uninstallScene()
    }

    @MainActor
    final class Coordinator {
        var onReady: (Bool) -> Void = { _ in }
        private var generation = 0
        private var assembly: Task<Void, Never>?
        private var pendingScene: SCNScene?

        func prepare(for view: CityDistrictSurface) {
            let generation = self.generation
            assembly = Task(priority: .utility) { @MainActor [weak self, weak view] in
                do {
                    let scene = try await CitySceneGeometry.prepareScene()
                    try Task.checkCancellation()
                    guard let self, let view, self.generation == generation else { return }
                    self.pendingScene = scene
                    let started = ProcessInfo.processInfo.systemUptime
                    view.prepare([scene]) { [weak self, weak view] success in
                        Task { @MainActor [weak self, weak view] in
                            guard let self, let view, self.generation == generation else { return }
                            self.complete(for: view, success: success, started: started)
                        }
                    }
                    self.assembly = nil
                } catch {
                    guard !Task.isCancelled, let self, self.generation == generation else { return }
                    self.assembly = nil
                    self.onReady(false)
                }
            }
        }

        private func complete(for view: CityDistrictSurface, success: Bool, started: TimeInterval) {
            guard let scene = pendingScene else { return }
            pendingScene = nil
            if CityDistrictTrace.enabled {
                let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1_000
                CityDistrictTrace.write("scene-prepare\t\(elapsed)\t\(success)")
            }
            if success { view.installScene(scene) }
            onReady(success)
        }

        func cancel() {
            generation += 1
            assembly?.cancel()
            assembly = nil
            pendingScene = nil
            onReady = { _ in }
        }
    }
}

@MainActor
final class CityDistrictSurface: SCNView {
    private let lens = SCNCamera()
    private let cameraNode = SCNNode()
    private var projection: CityDistrictCamera.Projection?
    private var sceneOpacity = 0.0
    private var sceneBlend: CityDistrictCamera.SceneBlend?
    private var wantsNightLighting = false
    private var usesNightLighting = false
    private var wantsTrafficMotion = false
    private(set) var hasInstalledScene = false

    init() {
        super.init(frame: .zero, options: nil)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        cameraNode.camera = lens
        lens.zNear = 1
        lens.zFar = 12_000
        lens.wantsHDR = false
        antialiasingMode = .multisampling2X
        preferredFramesPerSecond = 30
        isPlaying = false
    }

    required init?(coder: NSCoder) { nil }

    func installScene(_ district: SCNScene) {
        district.rootNode.addChildNode(cameraNode)
        scene = district
        pointOfView = cameraNode
        hasInstalledScene = true
        applyLighting(animated: false)
        applyCamera()
        applyTrafficMotion()
    }

    func uninstallScene() {
        isPlaying = false
        scene = nil
        hasInstalledScene = false
    }

    func update(projection: CityDistrictCamera.Projection?, sceneOpacity: Double, sceneBlend: CityDistrictCamera.SceneBlend?,
                night: Bool, movingTraffic: Bool) {
        self.projection = projection
        self.sceneOpacity = sceneOpacity
        self.sceneBlend = sceneBlend
        wantsNightLighting = night
        wantsTrafficMotion = projection != nil && movingTraffic
        applyTrafficMotion()
        applyCamera()
        applyLighting(animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func applyLighting(animated: Bool) {
        if wantsNightLighting != usesNightLighting, let scene, hasInstalledScene {
            usesNightLighting = wantsNightLighting
            CitySceneGeometry.applyLighting(to: scene, night: usesNightLighting, animated: animated)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyCamera()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyTrafficMotion()
    }

    private func applyTrafficMotion() {
        let playing = hasInstalledScene && wantsTrafficMotion && window != nil
        guard playing != isPlaying else { return }
        scene?.rootNode.childNode(withName: CityStreetTraffic.nodeName, recursively: false)?.isPaused = !playing
        isPlaying = playing
    }

    private func applyCamera() {
        guard hasInstalledScene, let projection, bounds.width > 0, bounds.height > 0 else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        cameraNode.simdPosition = SIMD3<Float>(projection.eye)
        cameraNode.simdLook(at: SIMD3<Float>(projection.target),
                            up: SIMD3<Float>(projection.up), localFront: SIMD3(0, 0, -1))
        // Use the fitted scene camera, not the native map's nominal distance.
        // Haze starts just before the ground focal point, preserving foreground
        // storefronts and tall landmarks while softening the distant district.
        // The background stays transparent; this does not move or mask any pin.
        let focalDistance = simd_length(projection.eye - projection.target)
        scene?.fogStartDistance = CGFloat(max(180, focalDistance * 0.88))
        scene?.fogEndDistance = CGFloat(max(180, focalDistance * 0.88) + 950)
        let near: Float = 1
        let far: Float = 12_000
        var matrix = SCNMatrix4Identity
        matrix.m11 = Float(2 * projection.focalLength / bounds.width)
        matrix.m22 = Float(2 * projection.focalLength / bounds.height)
        matrix.m31 = Float(1 - 2 * projection.principalPoint.x / bounds.width)
        matrix.m32 = Float(2 * projection.principalPoint.y / bounds.height - 1)
        matrix.m33 = -(far + near) / (far - near)
        matrix.m34 = -1
        matrix.m43 = -(2 * far * near) / (far - near)
        matrix.m44 = 0
        lens.projectionTransform = matrix
        if let root = scene?.rootNode {
            CityStreetSurface.orientStreetNames(in: root, projection: projection, sceneOpacity: sceneOpacity, blend: sceneBlend)
        }
        SCNTransaction.commit()
        setNeedsDisplay()
    }
}
#endif
