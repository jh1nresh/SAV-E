#if SAVVY_CITY_MVP
import SwiftUI
import SceneKit
import simd

/// A local renderer fixture. It bypasses location/search, and therefore cannot
/// establish alignment or handoff with a live MapKit basemap.
struct CitySolidRevealPreview: View {
    @State private var phase = 0.5
    @State private var night = false
    @State private var ready = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            Text("Local renderer · MapKit alignment not tested")
                .font(.caption).padding(.top, 8)
            GeometryReader { geometry in
                Surface(phase: phase, night: night, viewport: geometry.size,
                        reduceMotion: reduceMotion, ready: $ready)
            }
            Text(ready ? "Ready" : "Preparing district")
                .accessibilityIdentifier("cityMVP.solidPreview.ready")
            HStack {
                ForEach([0.35, 0.7, 1.0], id: \.self) { value in
                    Button("\(Int(value * 100))%") { phase = value }
                        .accessibilityIdentifier("cityMVP.solidPreview.phase.\(Int(value * 100))")
                }
                Button(night ? "Day" : "Night") { night.toggle() }
                    .accessibilityIdentifier("cityMVP.solidPreview.lighting")
                    .accessibilityValue(night ? "Night" : "Day")
            }
            .buttonStyle(.bordered).padding(.bottom, 12)
        }
        .foregroundStyle(night ? Color.white : Color.primary)
        .background(night ? Color(red: 0.08, green: 0.11, blue: 0.17) : Color(red: 0.82, green: 0.87, blue: 0.91))
    }

    private struct Surface: UIViewRepresentable {
        let phase: Double
        let night: Bool
        let viewport: CGSize
        let reduceMotion: Bool
        @Binding var ready: Bool

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIView(context: Context) -> CityDistrictSurface {
            let view = CityDistrictSurface()
            context.coordinator.config = self
            context.coordinator.task = Task { @MainActor [weak view, weak coordinator = context.coordinator] in
                guard let view, let coordinator else { return }
                do {
                    let scene = try await CitySceneGeometry.prepareScene()
                    try Task.checkCancellation()
                    view.installScene(scene)
                    coordinator.config?.apply(to: view)
                    coordinator.config?.ready = true
                } catch {
                    CityDistrictTrace.write("solid-preview\tpreparation-failed")
                }
            }
            return view
        }

        func updateUIView(_ view: CityDistrictSurface, context: Context) {
            context.coordinator.config = self
            apply(to: view)
        }

        static func dismantleUIView(_ view: CityDistrictSurface, coordinator: Coordinator) {
            coordinator.task?.cancel()
            coordinator.task = nil
            view.uninstallScene()
        }

        private func apply(to view: CityDistrictSurface) {
            guard viewport.width > 0, viewport.height > 0 else { return }
            // Synthetic camera uses the nominal native-probe angles/distance.
            // It is still not a fitted or registered MapKit camera.
            let pitch = 35.0 * Double.pi / 180, heading = 20.0 * Double.pi / 180
            let target = SIMD3<Double>.zero
            let eye = target + 1_450 * SIMD3(sin(pitch) * sin(heading), cos(pitch), sin(pitch) * cos(heading))
            let forward = simd_normalize(target - eye)
            let right = simd_normalize(simd_cross(forward, SIMD3<Double>(0, 1, 0)))
            let up = simd_cross(right, forward)
            let projection = CityDistrictCamera.Projection(eye: eye, target: target, up: up,
                focalLength: viewport.height / (2 * tan(.pi / 8)),
                principalPoint: CGPoint(x: viewport.width / 2, y: viewport.height / 2), error: 0)
            let point = projection.point(at: CityLandmark101.pinContact)
            let pins = point.map { point in
                [CityScenePin(id: "landmark-101", contextID: "landmark-101", title: "台北 101",
                              symbol: "building.2", saved: false, selected: true,
                              placement: .init(point: point, contactOpacity: 1), reveal: 1,
                              photoDiameter: 50, titleOpacity: 1, titleAbove: false)]
            } ?? []
            view.update(projection: projection, sceneOpacity: phase, sceneBlend: nil,
                        night: night, movingTraffic: !reduceMotion, nativeDistance: 700,
                        pins: pins, reduceMotion: reduceMotion)
            view.isAccessibilityElement = true
            view.accessibilityIdentifier = "cityMVP.solidPreview.surface"
            view.accessibilityLabel = "District renderer"
            let sample: [String: Any] = ["phase": Int((phase * 100).rounded()), "night": night,
                "installed": view.hasInstalledScene, "width": viewport.width, "height": viewport.height,
                "materialTone": CitySceneView.usesMaterialTone,
                "syntheticPitch": 35, "syntheticHeading": 20, "syntheticDistance": 1450,
                "pinX": point?.x ?? -1, "pinY": point?.y ?? -1]
            if let data = try? JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys]) {
                view.accessibilityValue = String(decoding: data, as: UTF8.self)
            }
        }

        @MainActor
        final class Coordinator {
            var config: Surface?
            var task: Task<Void, Never>?
        }
    }
}
#endif
