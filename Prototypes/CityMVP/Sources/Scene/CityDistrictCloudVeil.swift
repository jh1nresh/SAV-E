#if SAVVY_CITY_MVP
import SwiftUI

/// Soft clouds between the map renderers and their shared place pins.
struct CityDistrictCloudVeil: View {
    let patches: [CityDistrictCamera.CloudPatch]
    let night: Bool

    var body: some View {
        Canvas { context, _ in
            let shade = night
                ? Color(red: 0.25, green: 0.30, blue: 0.48)
                : Color(red: 0.68, green: 0.76, blue: 0.86)
            let cloud = night
                ? Color(red: 0.53, green: 0.59, blue: 0.76)
                : Color(red: 0.98, green: 0.99, blue: 1.00)
            for patch in patches {
                let side: CGFloat = patch.mirrorsContour ? -1 : 1
                var layer = context
                layer.concatenate(CGAffineTransform(
                    a: patch.east.dx, b: patch.east.dy, c: patch.south.dx, d: patch.south.dy,
                    tx: patch.center.x, ty: patch.center.y
                ))
                drawLobe(in: layer, at: CGPoint(x: 0, y: 0.21), radius: 1.12,
                         verticalScale: 0.76, tint: shade.opacity(0.72))
                drawLobe(in: layer, at: .zero, radius: 1.10,
                         verticalScale: 0.70, tint: cloud.opacity(0.74))
                drawLobe(in: layer, at: CGPoint(x: -0.47 * side, y: -0.17), radius: 0.68,
                         verticalScale: 0.83, tint: cloud.opacity(0.86))
                drawLobe(in: layer, at: CGPoint(x: 0.14 * side, y: -0.29), radius: 0.59,
                         verticalScale: 0.92, tint: cloud.opacity(0.88))
                drawLobe(in: layer, at: CGPoint(x: 0.66 * side, y: 0.01), radius: 0.45,
                         verticalScale: 0.61, tint: cloud.opacity(0.57))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawLobe(in context: GraphicsContext, at center: CGPoint, radius: CGFloat,
                          verticalScale: CGFloat, tint: Color) {
        var lobe = context
        lobe.translateBy(x: center.x, y: center.y)
        lobe.scaleBy(x: 1, y: verticalScale)
        let bounds = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        let gradient = Gradient(stops: [
            .init(color: tint, location: 0),
            .init(color: tint.opacity(0.82), location: 0.45),
            .init(color: tint.opacity(0.23), location: 0.78),
            .init(color: tint.opacity(0), location: 1),
        ])
        lobe.fill(Path(ellipseIn: bounds),
                  with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: radius))
    }
}
/// A spatial blend for the map handoff. The pin reads the same local opacity.
struct CityDistrictSceneMask: View {
    let frame: CityDistrictCamera

    var body: some View {
        if let blend = frame.sceneBlend {
            RadialGradient(
                colors: [.white, .white.opacity(blend.outerStrength)],
                center: UnitPoint(x: blend.center.x / frame.viewport.width, y: blend.center.y / frame.viewport.height),
                startRadius: blend.innerRadius,
                endRadius: blend.outerRadius
            )
        } else {
            Color.white
        }
    }
}
#endif
