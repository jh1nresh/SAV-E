#if SAVVY_CITY_MVP
import SwiftUI
import SceneKit

/// A visual layer. The native map beneath it owns every gesture and the camera.
struct CitySceneView: UIViewRepresentable {
    // The local preview uses the integrated route; comparisons retain their flags.
    static let usesNativeGroundOwner = CityMVPPreviewConfiguration.enabled
        || ProcessInfo.processInfo.arguments.contains("--verify-native-ground-owner")
    static let usesOpaqueReveal = CityMVPPreviewConfiguration.enabled
        || (CityDistrictTrace.enabled && ProcessInfo.processInfo.arguments.contains("--verify-opaque-reveal"))
    static let usesMaterialTone = usesOpaqueReveal
        && (CityMVPPreviewConfiguration.enabled || ProcessInfo.processInfo.arguments.contains("--verify-material-tone"))
    static let usesCloudHandoff = CityDistrictCamera.cloudHandoffEnabled
    // A single-layer ownership comparison, never a default or phone setting.
    static let hidesContextForInspection: Bool = {
#if targetEnvironment(simulator)
        CityMVPPreviewConfiguration.enabled && CityMVPPreviewConfiguration.inspectsPreview
            && ProcessInfo.processInfo.arguments.contains("--inspect-without-context-buildings")
#else
        false
#endif
    }()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cityMVPMapIsVisible) private var mapIsVisible

    let projection: CityDistrictCamera.Projection?
    let sceneOpacity: Double
    let sceneBlend: CityDistrictCamera.SceneBlend?
    let night: Bool
    let landmarkPoint: CGPoint?
    let nativeDistance: Double
    let registration: CityDistrictRegistration?
    let pins: [CityScenePin]
    var contextLabels: [CityContextLabel] = []
    var cloudPatches: [CityDistrictCamera.CloudPatch] = []
    var cloudOpacity: Double = 0
    var onLoading: () -> Void = {}
    var onReady: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CityDistrictSurface {
        let view = CityDistrictSurface()
        context.coordinator.onReady = onReady
        context.coordinator.onLoading = onLoading
        context.coordinator.prepare(for: view)
        context.coordinator.prepareBacking(for: view, registration: registration, night: night)
        return view
    }

    func updateUIView(_ view: CityDistrictSurface, context: Context) {
        context.coordinator.onReady = onReady
        context.coordinator.onLoading = onLoading
        view.isHidden = !mapIsVisible
        context.coordinator.prepareBacking(for: view, registration: registration, night: night)
        view.update(projection: projection, sceneOpacity: sceneOpacity, sceneBlend: sceneBlend, night: night,
                    movingTraffic: mapIsVisible && nativeDistance < 850 && scenePhase == .active && !reduceMotion,
                    nativeDistance: nativeDistance, pins: mapIsVisible ? pins : [], reduceMotion: reduceMotion,
                    contextLabels: mapIsVisible ? contextLabels : [],
                    cloudPatches: mapIsVisible ? cloudPatches : [], cloudOpacity: cloudOpacity)
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
        var onLoading: () -> Void = {}
        private var geometryReady = false
        private var backingReady = false
        private var generation = 0
        private var assembly: Task<Void, Never>?
        private var pendingScene: SCNScene?
        private var backing: Task<Void, Never>?
        private var backingKey: String?

        func prepareBacking(for view: CityDistrictSurface, registration: CityDistrictRegistration?, night: Bool) {
            if CitySceneView.usesNativeGroundOwner {
                guard !backingReady else { return }
                backingReady = true
                if geometryReady { onReady(true) }
                CityDistrictTrace.write("backing-skipped\tnative-ground-owner")
                return
            }
            guard let registration else { return }
            let key = "\(registration.latitudeOffset)|\(registration.longitudeOffset)|\(night)"
            guard key != backingKey else { return }
            backingKey = key
            backingReady = false
            backing?.cancel()
            // Old registration/palette evidence must never remain installed
            // while a new key loads or fails.
            view.clearBacking()
            backing = Task { @MainActor [weak self, weak view] in
                guard !Task.isCancelled, let self, self.backingKey == key else { return }
                self.onLoading()
                do {
                    let node = try await CityFlatMapBacking.prepare(registration: registration, night: night)
                    guard !Task.isCancelled, self.backingKey == key, let view else { return }
                    view.installBacking(node)
                    self.backingReady = true
                    if self.geometryReady { self.onReady(true) }
                    CityDistrictTrace.write("backing-ready\t\(night)")
                } catch {
                    guard !Task.isCancelled, self.backingKey == key else { return }
                    self.backingReady = false
                    self.onReady(false)
                    CityDistrictTrace.write("backing-unavailable\t\(String(describing: error))")
                }
            }
        }


        func prepare(for view: CityDistrictSurface) {
            guard view.supportsCloudComposite else {
                onReady(false)
                CityDistrictTrace.write("cloud-composite-unavailable")
                return
            }
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
            geometryReady = success
            if success { view.installScene(scene) }
            if !success { onReady(false) }
            else if backingReady { onReady(true) }
        }

        func cancel() {
            generation += 1
            assembly?.cancel()
            backing?.cancel()
            backing = nil
            assembly = nil
            pendingScene = nil
            onReady = { _ in }
            onLoading = {}
        }
    }
}

@MainActor
final class CityDistrictSurface: SCNView {
    private let lens = SCNCamera()
    private let cameraNode = SCNNode()
    private let pinOverlay = CityScenePins()
    private lazy var geographicClouds = CitySceneClouds(camera: cameraNode)
    private let solidReveal = CitySceneView.usesOpaqueReveal
        ? CitySceneReveal(mode: CitySceneView.usesMaterialTone ? .materialTone : .cloudCut) : nil
    private var backingNode: SCNNode?
    private var nativeDistance = Double.infinity
    private var observedUpdates = 0
    private var observedLayouts = 0
    private var authoredOpacities: [ObjectIdentifier: CGFloat] = [:]
    private var lastTracedArrival: CGFloat?
    private var lastCloudAudit: String?

    private var projection: CityDistrictCamera.Projection?
    private var sceneOpacity = 0.0
    private var sceneBlend: CityDistrictCamera.SceneBlend?
    private var wantsNightLighting = false
    private var usesNightLighting = false
    private var wantsTrafficMotion = false
    private(set) var hasInstalledScene = false
    var supportsCloudComposite: Bool { !CitySceneView.usesCloudHandoff || technique != nil }

    init() {
        super.init(frame: .zero, options: nil)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        cameraNode.camera = lens
        lens.zNear = 1
        lens.zFar = 12_000
        lens.wantsHDR = false
        if CitySceneView.usesCloudHandoff { technique = CitySceneComposite.makeTechnique() }
        antialiasingMode = .multisampling2X
        preferredFramesPerSecond = 30
        overlaySKScene = pinOverlay.scene
        if let solidReveal { pinOverlay.scene.addChild(solidReveal.cloud) }
        isPlaying = false
        pinOverlay.onAnimationStateChange = { [weak self] in self?.applyTrafficMotion() }
        CityMVPLatencyObservation.observeScene { [weak self] in
            guard let self else { return nil }
            return ["playing": self.isPlaying ? 1 : 0, "pinAnimating": self.pinOverlay.isAnimating ? 1 : 0,
                "trafficRequested": self.wantsTrafficMotion ? 1 : 0, "installed": self.hasInstalledScene ? 1 : 0,
                "visible": self.window != nil && !self.isHidden ? 1 : 0,
                "distance": self.nativeDistance.isFinite ? self.nativeDistance : -1,
                "updates": Double(self.observedUpdates), "layouts": Double(self.observedLayouts),
                "preferredFPS": Double(self.preferredFramesPerSecond)]
        }
    }

    required init?(coder: NSCoder) { nil }

    func installScene(_ district: SCNScene) {
        district.rootNode.addChildNode(cameraNode)
        scene = district
        pointOfView = cameraNode
        hasInstalledScene = true
        authoredOpacities = Dictionary(uniqueKeysWithValues: district.rootNode.childNodes.filter { $0 !== cameraNode }.map { (ObjectIdentifier($0), CGFloat($0.opacity)) })
        solidReveal?.install(in: district.rootNode, excluding: backingNode)
        if let backingNode { district.rootNode.addChildNode(backingNode) }
        applyLighting(animated: false)
        applyCamera()
        applyTrafficMotion()
    }

    func clearBacking() {
        backingNode?.removeFromParentNode()
        backingNode = nil
        applyCamera()
    }

    func installBacking(_ node: SCNNode) {
        backingNode?.removeFromParentNode()
        backingNode = node
        scene?.rootNode.addChildNode(node)
        applyCamera()
    }

    func uninstallScene() {
        isPlaying = false
        scene = nil
        hasInstalledScene = false
    }

    func update(projection: CityDistrictCamera.Projection?, sceneOpacity: Double, sceneBlend: CityDistrictCamera.SceneBlend?,
                night: Bool, movingTraffic: Bool, nativeDistance: Double, pins: [CityScenePin], reduceMotion: Bool,
                contextLabels: [CityContextLabel] = [],
                cloudPatches: [CityDistrictCamera.CloudPatch] = [], cloudOpacity: Double = 0) {
        if CityMVPLatencyObservation.isRecording { observedUpdates += 1 }
        self.nativeDistance = nativeDistance
        self.projection = projection
        self.sceneOpacity = sceneOpacity
        self.sceneBlend = sceneBlend
        wantsNightLighting = night
        wantsTrafficMotion = projection != nil && movingTraffic
        applyTrafficMotion()
        applyLighting(animated: !UIAccessibility.isReduceMotionEnabled)
        // One SCN transaction publishes camera, geometry opacity, and screen-space
        // pin sprites. No SwiftUI-visible pin can race the Metal scene frame.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        applyCamera()
        let hasGroundPrerequisite = CitySceneView.usesNativeGroundOwner || backingNode != nil
        pinOverlay.update(projection == nil || !hasGroundPrerequisite ? [] : pins, viewport: bounds.size, night: night, reduceMotion: reduceMotion,
                          labels: projection == nil || !hasGroundPrerequisite ? [] : contextLabels)
        geographicClouds.update(cloudPatches, opacity: cloudOpacity, viewport: bounds.size, night: night)
        SCNTransaction.commit()
        applyTrafficMotion()
        setNeedsDisplay()
        if ProcessInfo.processInfo.arguments.contains("--verify-cloud-consumer") {
            recordCloudAudit(format: colorPixelFormat.rawValue)
        }
    }

    private func recordCloudAudit(format: UInt) {
        guard CityDistrictTrace.enabled, CitySceneView.usesCloudHandoff, hasInstalledScene else { return }
        let key = "\(wantsNightLighting)-\(Int(nativeDistance / 100))-\(projection != nil)"
        guard key != lastCloudAudit else { return }
        lastCloudAudit = key
        var value = geographicClouds.diagnosticState(renderer: self)
        value["distance"] = nativeDistance
        value["night"] = wantsNightLighting
        value["format"] = format
        value["reverseZ"] = usesReverseZ
        value["fogStart"] = scene?.fogStartDistance ?? -1
        value["fogEnd"] = scene?.fogEndDistance ?? -1
        value["near"] = lens.zNear; value["far"] = lens.zFar
        value["viewHidden"] = isHidden
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            if let raw = String(data: data, encoding: .utf8) { CityDistrictTrace.write("cloud-consumer\t" + raw) }
        } catch {
            CityDistrictTrace.write("cloud-consumer-invalid\t\(error)\t\(value)")
        }
    }

    private func applyLighting(animated: Bool) {
        if wantsNightLighting != usesNightLighting, let scene, hasInstalledScene {
            usesNightLighting = wantsNightLighting
            // Restore unblended values before the palette updates its own light
            // and shadow opacities; never compound the camera fade each update.
            for node in scene.rootNode.childNodes {
                if let opacity = authoredOpacities[ObjectIdentifier(node)] { node.opacity = opacity }
            }
            CitySceneGeometry.applyLighting(to: scene, night: usesNightLighting, animated: animated)
            for node in scene.rootNode.childNodes where node !== cameraNode && node !== backingNode {
                authoredOpacities[ObjectIdentifier(node)] = CGFloat(node.opacity)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if CityMVPLatencyObservation.isRecording { observedLayouts += 1 }
        applyCamera()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyTrafficMotion()
    }

    private func applyTrafficMotion() {
        let visible = hasInstalledScene && window != nil && !isHidden
        scene?.rootNode.childNode(withName: CityStreetTraffic.nodeName, recursively: false)?.isPaused = !(visible && wantsTrafficMotion)
        // Preserve the existing traffic budget. Only the bounded local head
        // spring requests 60fps; camera-only/static/far scenes remain on demand.
        preferredFramesPerSecond = visible && pinOverlay.isAnimating ? 60 : 30
        isPlaying = visible && (wantsTrafficMotion || pinOverlay.isAnimating)
    }

    private func applyCamera() {
        guard hasInstalledScene, CitySceneView.usesNativeGroundOwner || backingNode != nil,
              let projection, bounds.width > 0, bounds.height > 0 else {
            solidReveal?.cloud.isHidden = true
            backingNode?.isHidden = true
            for node in scene?.rootNode.childNodes ?? [] where node !== cameraNode && node !== backingNode { node.isHidden = true }
            return
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        cameraNode.simdPosition = SIMD3<Float>(projection.eye)
        cameraNode.simdLook(at: SIMD3<Float>(projection.target),
                            up: SIMD3<Float>(projection.up), localFront: SIMD3(0, 0, -1))
        // Use the fitted scene camera, not the native map's nominal distance.
        // Keep the focal ground clear; haze begins 120m beyond it and still
        // softens the distant district over the existing 950m interval.
        // The background stays transparent; this does not move or mask any pin.
        let focalDistance = simd_length(projection.eye - projection.target)
        // Temporary prototype-only switch for same-binary fog A/B capture.
        let legacyFog = ProcessInfo.processInfo.arguments.contains("--verify-legacy-fog")
        let fogStart = legacyFog ? max(180, focalDistance * 0.88) : max(180, focalDistance + 120)
        scene?.fogStartDistance = CGFloat(fogStart)
        scene?.fogEndDistance = CGFloat(fogStart + 950)
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
        if let solidReveal {
            let tone = CitySceneView.usesCloudHandoff
                ? CityDistrictCamera.cloudHandoffTone(distance: nativeDistance) : sceneOpacity
            solidReveal.update(.init(phase: tone,
                                     center: sceneBlend?.center ?? CGPoint(x: bounds.midX, y: bounds.midY),
                                     viewport: bounds.size), viewport: bounds.size, night: wantsNightLighting)
            if CitySceneView.usesCloudHandoff { solidReveal.cloud.isHidden = true }
        }
        if let root = scene?.rootNode {
            let arrival = CitySceneView.usesCloudHandoff ? 1 : CitySceneView.usesMaterialTone
                ? CitySceneReveal.arrivalOpacity(distance: nativeDistance) : 1
            // The broad flat backing replaces native elevated geometry before
            // the authored scene enters. Original street textures stay intact.
            let fraction = min(1, max(0, (5_200 - nativeDistance) / 850))
            backingNode?.opacity = fraction * fraction * (3 - 2 * fraction)
            backingNode?.isHidden = false
            for node in root.childNodes where node !== cameraNode && node !== backingNode {
                node.isHidden = CitySceneView.hidesContextForInspection
                    && node.name?.hasPrefix(CityContextBuildings.nodePrefix) == true
                node.opacity = (authoredOpacities[ObjectIdentifier(node)] ?? 1)
                    * (solidReveal == nil ? CGFloat(sceneOpacity) : arrival)
            }
            CityStreetSurface.orientStreetNames(in: root, projection: projection, sceneOpacity: sceneOpacity, blend: sceneBlend)
            let traceChanged = lastTracedArrival.map { abs(arrival - $0) > 0.01 } ?? true
            if CitySceneView.usesMaterialTone, CityDistrictTrace.enabled, traceChanged {
                // Read actual node properties after applying the factor; this
                // is diagnostic data, never a second camera or animation clock.
                let applied = root.childNodes.compactMap { node -> CGFloat? in
                    guard node !== cameraNode, node !== backingNode,
                          let authored = authoredOpacities[ObjectIdentifier(node)], authored > 0 else { return nil }
                    return CGFloat(node.opacity) / authored
                }
                CityDistrictTrace.write("arrival\t\(nativeDistance)\t\(arrival)\t\(applied.min() ?? -1)\t\(applied.max() ?? -1)\t\(applied.count)")
                lastTracedArrival = arrival
            }
        }
        SCNTransaction.commit()
        setNeedsDisplay()
    }
}
#endif
