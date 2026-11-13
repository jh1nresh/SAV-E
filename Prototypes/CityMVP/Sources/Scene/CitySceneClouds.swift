#if SAVVY_CITY_MVP
import SceneKit
import UIKit
import SwiftUI

/// Geographic cloud quads share the fitted camera transaction with geometry.
/// The transparent display-alpha pass runs beneath the photo/title overlay.
@MainActor
final class CitySceneClouds {
    private let root = SCNNode()
    private weak var camera: SCNNode?
    private var nodes: [SCNNode] = []
    private var verticesByNode: [[SCNVector3]] = []

    init(camera: SCNNode) {
        self.camera = camera
        root.name = "city-geographic-cloud-planes"
        camera.addChildNode(root)
    }

    func update(_ patches: [CityDistrictCamera.CloudPatch], opacity: Double, viewport: CGSize, night: Bool) {
        guard let matrix = camera?.camera?.projectionTransform, viewport.width > 0, viewport.height > 0,
              abs(matrix.m11) > 0.0001, abs(matrix.m22) > 0.0001 else { root.isHidden = true; return }
        root.isHidden = patches.isEmpty || opacity <= 0
        while nodes.count > patches.count {
            nodes.removeLast().removeFromParentNode(); verticesByNode.removeLast()
        }
        // Keep the overlay comfortably inside the clip volume. At depth2,
        // the custom projection places it near z=0; far-world Float matrix
        // cancellation can push whole cloud vertices outside the clip range.
        // XY scales with depth below, retaining the same screen-space anchor.
        let depth: Float = 8
        let uv = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]
        for (index, patch) in patches.enumerated() {
            if nodes.count <= index {
                let node = SCNNode()
                node.renderingOrder = 10_000 + index
                node.castsShadow = false
                root.addChildNode(node); nodes.append(node); verticesByNode.append([])
            }
            let corners: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (-1, 1), (1, 1)]
            let vertices = corners.map { x, y -> SCNVector3 in
                let px = patch.center.x + 1.6 * (x * patch.east.dx + y * patch.south.dx)
                let py = patch.center.y + 1.6 * (x * patch.east.dy + y * patch.south.dy)
                let nx = Float(2 * px / viewport.width - 1)
                let ny = Float(1 - 2 * py / viewport.height)
                return SCNVector3((nx + matrix.m31) * depth / matrix.m11,
                                  (ny + matrix.m32) * depth / matrix.m22, -depth)
            }
            let geometry = SCNGeometry(sources: [.init(vertices: vertices), .init(textureCoordinates: uv)],
                                       elements: [.init(indices: [Int32(0), 2, 1, 1, 2, 3], primitiveType: .triangles)])
            let material = nodes[index].geometry?.firstMaterial ?? SCNMaterial()
            material.lightingModel = .constant
            let textureKey = "\(night)-\(patch.mirrorsContour)"
            if nodes[index].name != textureKey {
                material.diffuse.contents = Self.image(night: night, mirrored: patch.mirrorsContour)
                nodes[index].name = textureKey
            }
            material.transparency = CGFloat(min(1, max(0, opacity)))
            material.transparencyMode = .singleLayer
            material.blendMode = .alpha
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            geometry.materials = [material]
            nodes[index].geometry = geometry
            verticesByNode[index] = vertices
        }
    }

    /// Verification-only CPU/presentation state at the camera update boundary.
    /// These positions and material values do not prove GPU pixel visibility.
    func diagnosticState(renderer: SCNSceneRenderer) -> [String: Any] {
        let samples: [[String: Any]] = nodes.enumerated().map { index, node in
            let bounds = node.boundingBox
            let center = SCNVector3((bounds.min.x + bounds.max.x) / 2,
                                    (bounds.min.y + bounds.max.y) / 2,
                                    (bounds.min.z + bounds.max.z) / 2)
            let world = node.convertPosition(center, to: nil)
            let screen = renderer.projectPoint(world)
            let material = node.geometry?.firstMaterial
            var inheritedHidden = false
            var inheritedOpacity: CGFloat = 1
            var parent: SCNNode? = node
            while let current = parent {
                inheritedHidden = inheritedHidden || current.isHidden
                inheritedOpacity *= current.opacity
                parent = current.parent
            }
            return ["textureKey": node.name ?? "none", "screenX": screen.x, "screenY": screen.y,
                    "screenZ": screen.z,
                    "corners": verticesByNode[index].map { vertex in
                        let point = renderer.projectPoint(node.convertPosition(vertex, to: nil))
                        return ["x": point.x, "y": point.y, "z": point.z]
                    },
                    "inFrustum": camera.map { renderer.isNode(node, insideFrustumOf: $0) } ?? false,
                    "hidden": inheritedHidden, "opacity": inheritedOpacity,
                    "presentationOpacity": node.presentation.opacity,
                    "materialOpacity": material?.transparency ?? -1,
                    "lighting": material?.lightingModel.rawValue ?? "none",
                    "surfaceModifier": material?.shaderModifiers?[.surface] ?? "none",
                    "readsDepth": material?.readsFromDepthBuffer ?? true,
                    "writesDepth": material?.writesToDepthBuffer ?? true,
                    "imageWidth": (material?.diffuse.contents as? UIImage)?.cgImage?.width ?? 0,
                    "imageHeight": (material?.diffuse.contents as? UIImage)?.cgImage?.height ?? 0]
        }
        let position = camera?.worldPosition ?? SCNVector3Zero
        let orientation = camera?.worldOrientation ?? SCNVector4(0, 0, 0, 1)
        var state: [String: Any] = ["rootHidden": root.isHidden, "rootPresentationHidden": root.presentation.isHidden,
                                   "rootOpacity": root.opacity, "rootPresentationOpacity": root.presentation.opacity,
                                   "cameraOpacity": camera?.opacity ?? -1, "nodes": samples,
                                   "cameraWorld": [position.x, position.y, position.z],
                                   "cameraOrientation": [orientation.x, orientation.y, orientation.z, orientation.w]]
        if let matrix = camera?.camera?.projectionTransform {
            state["projection"] = [matrix.m11, matrix.m22, matrix.m31, matrix.m32,
                                   matrix.m33, matrix.m34, matrix.m43, matrix.m44]
        }
        return state
    }

    private static var images: [String: UIImage] = [:]

    static func image(night: Bool, mirrored: Bool) -> UIImage {
        let key = "\(night)-\(mirrored)"
        if let cached = images[key] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { output in
            let g = output.cgContext
            let side: CGFloat = mirrored ? -1 : 1
            let shade = night ? UIColor(red: 0.25, green: 0.30, blue: 0.48, alpha: 1)
                              : UIColor(red: 0.68, green: 0.76, blue: 0.86, alpha: 1)
            let cloud = night ? UIColor(red: 0.53, green: 0.59, blue: 0.76, alpha: 1)
                              : UIColor(red: 0.98, green: 0.99, blue: 1, alpha: 1)
            func lobe(x: CGFloat, y: CGFloat, radius: CGFloat, vertical: CGFloat, color: UIColor, alpha: CGFloat) {
                g.saveGState()
                g.translateBy(x: 128 + x * 80, y: 128 + y * 80)
                g.scaleBy(x: 80, y: 80 * vertical)
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [alpha, alpha * 0.82, alpha * 0.23, 0].map { color.withAlphaComponent($0).cgColor } as CFArray,
                    locations: [0, 0.45, 0.78, 1])!
                g.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                     endCenter: .zero, endRadius: radius, options: [])
                g.restoreGState()
            }
            lobe(x: 0, y: 0.21, radius: 1.12, vertical: 0.76, color: shade, alpha: 0.72)
            lobe(x: 0, y: 0, radius: 1.10, vertical: 0.70, color: cloud, alpha: 0.74)
            lobe(x: -0.47 * side, y: -0.17, radius: 0.68, vertical: 0.83, color: cloud, alpha: 0.86)
            lobe(x: 0.14 * side, y: -0.29, radius: 0.59, vertical: 0.92, color: cloud, alpha: 0.88)
            lobe(x: 0.66 * side, y: 0.01, radius: 0.45, vertical: 0.61, color: cloud, alpha: 0.57)
        }
        images[key] = image
        return image
    }
}

/// The native-only owner uses the same cached cloud image and affine axes.
/// The display-alpha scene pass matches this source-over composition.
/// Both owners consume the same camera sample without a cloud animation clock.
struct CityGeographicCloudFallback: UIViewRepresentable {
    let patches: [CityDistrictCamera.CloudPatch]
    let opacity: Double
    let night: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        while view.subviews.count > patches.count { view.subviews.last?.removeFromSuperview() }
        for (index, patch) in patches.enumerated() {
            let imageView: UIImageView
            if index < view.subviews.count {
                imageView = view.subviews[index] as! UIImageView
            } else {
                imageView = UIImageView()
                imageView.isUserInteractionEnabled = false
                view.addSubview(imageView)
            }
            imageView.image = CitySceneClouds.image(night: night, mirrored: patch.mirrorsContour)
            imageView.bounds = CGRect(x: 0, y: 0, width: 256, height: 256)
            imageView.center = patch.center
            imageView.transform = CGAffineTransform(a: patch.east.dx / 80, b: patch.east.dy / 80,
                                                   c: patch.south.dx / 80, d: patch.south.dy / 80,
                                                   tx: 0, ty: 0)
            imageView.alpha = CGFloat(min(1, max(0, opacity)))
        }
    }
}
#endif
