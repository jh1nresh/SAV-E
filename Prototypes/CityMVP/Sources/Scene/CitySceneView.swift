#if SAVVY_CITY_MVP
import SwiftUI
import SceneKit

/// A visual layer. The native map beneath it owns every gesture and the camera.
struct CitySceneView: UIViewRepresentable {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let projection: CityDistrictCamera.Projection?
    let night: Bool
    let landmarkPoint: CGPoint?
    let nativeDistance: Double

    func makeUIView(context: Context) -> CityDistrictSurface {
        CityDistrictSurface()
    }

    func updateUIView(_ view: CityDistrictSurface, context: Context) {
        view.update(projection: projection, night: night,
                    movingTraffic: nativeDistance < 850 && scenePhase == .active && !reduceMotion)
        if projection != nil, let landmarkPoint, view.bounds.width > 0 {
            let rendered = view.projectPoint(SCNVector3(0, 0, 0))
            let error = hypot(Double(rendered.x) - landmarkPoint.x, Double(rendered.y) - landmarkPoint.y)
            CityDistrictTrace.write("render\t\(nativeDistance)\t\(error)")
        }
    }
}

@MainActor
final class CityDistrictSurface: SCNView {
    private let lens = SCNCamera()
    private let cameraNode = SCNNode()
    private var projection: CityDistrictCamera.Projection?
    private var usesNightLighting = false
    private var wantsTrafficMotion = false

    init() {
        super.init(frame: .zero, options: nil)
        let district = CitySceneGeometry.makeScene()
        scene = district
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        cameraNode.camera = lens
        lens.zNear = 1
        lens.zFar = 12_000
        lens.wantsHDR = false
        district.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
        antialiasingMode = .multisampling2X
        preferredFramesPerSecond = 30
        isPlaying = false
    }

    required init?(coder: NSCoder) { nil }

    func update(projection: CityDistrictCamera.Projection?, night: Bool, movingTraffic: Bool) {
        self.projection = projection
        wantsTrafficMotion = projection != nil && movingTraffic
        applyTrafficMotion()
        applyCamera()
        if night != usesNightLighting, let scene {
            usesNightLighting = night
            CitySceneGeometry.applyLighting(to: scene, night: night, animated: !UIAccessibility.isReduceMotionEnabled)
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
        let playing = wantsTrafficMotion && window != nil
        guard playing != isPlaying else { return }
        scene?.rootNode.childNode(withName: CityStreetTraffic.nodeName, recursively: false)?.isPaused = !playing
        isPlaying = playing
    }

    private func applyCamera() {
        guard let projection, bounds.width > 0, bounds.height > 0 else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        cameraNode.simdPosition = SIMD3<Float>(projection.eye)
        cameraNode.simdLook(at: SIMD3<Float>(projection.target),
                            up: SIMD3<Float>(projection.up), localFront: SIMD3(0, 0, -1))
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
        SCNTransaction.commit()
        setNeedsDisplay()
    }
}
#endif
