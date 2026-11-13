#if SAVVY_CITY_MVP
import SwiftUI
import SpriteKit

/// Immutable camera-sample payload shared with the invisible SwiftUI controls.
struct CityScenePin: Identifiable {
    let id: String
    let contextID: String?
    let title: String
    let symbol: String
    let saved: Bool
    let selected: Bool
    let placement: CityDistrictCamera.PinPlacement
    let reveal: Double
    let photoDiameter: CGFloat
    let titleOpacity: Double
    let titleAbove: Bool
    var visited = false

    var artwork: CityPinArtwork {
        CityPinArtwork(id: contextID, title: title, symbol: symbol, saved: saved, selected: selected, visited: visited,
                       contactOpacity: placement.contactOpacity, browsePhotoDiameter: photoDiameter,
                       zoomReveal: reveal, titleOpacity: titleOpacity)
    }
}

/// SpriteKit is composited by the same SCNView render pass as the buildings.
/// Camera coordinates never animate; photo heads settle locally on selection
/// and release, while glyphs keep their existing selection entrance.
@MainActor
final class CityScenePins {
    let scene = SKScene()
    private struct Entry {
        let head: SKSpriteNode
        let title: SKSpriteNode
        var textureKey: String
        var selected: Bool
        var photoDiameter: CGFloat?
    }
    private var entries: [String: Entry] = [:]
    private var textures: [String: SKTexture] = [:]
    private var night = false
    private let contextLabels = CityContextLabelSprites()
    var onAnimationStateChange: () -> Void = {}
    var isAnimating: Bool { entries.values.contains { $0.head.hasActions() } }

    init() {
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        scene.isUserInteractionEnabled = false
    }

    func update(_ pins: [CityScenePin], viewport: CGSize, night: Bool, reduceMotion: Bool, labels: [CityContextLabel] = []) {
        contextLabels.update(labels, scene: scene, viewport: viewport, night: night)
        self.night = night
        scene.size = viewport
        let ids = Set(pins.map(\.id))
        for id in Array(entries.keys) where !ids.contains(id) {
            if let removed = entries.removeValue(forKey: id) {
                removed.head.removeFromParent()
                removed.title.removeFromParent()
            }
        }
        for pin in pins {
            let key = "\(pin.contextID ?? pin.id)|\(pin.symbol)|\(pin.saved)|\(pin.visited)|\(pin.selected)|\(night)|\(Int(pin.photoDiameter.rounded()))|\(Int((pin.placement.contactOpacity * 10).rounded()))|\(Int((pin.reveal * 100).rounded()))|\(reduceMotion)"
            let previous = entries[pin.id]
            let head = previous?.head ?? SKSpriteNode()
            let priorScale = head.xScale
            let priorYScale = head.yScale
            let hasPhoto = CityPinArtwork.photo(for: pin.contextID) != nil
            let photoDiameter = CityPinRaster.photoMetrics(
                selected: pin.selected,
                browseDiameter: CityPinArtwork.headDiameter(hasPhoto: hasPhoto, selected: false, browseDiameter: pin.photoDiameter),
                reveal: pin.reveal, reduceMotion: reduceMotion)?.renderedDiameter
            let title = previous?.title ?? SKSpriteNode()
            if previous == nil {
                head.name = pin.id
                title.name = "title-\(pin.id)"
                // The contact lies 72pt down in the 92pt raster (20pt below it
                // is transparent). SpriteKit's texture coordinates run upward.
                head.anchorPoint = CGPoint(x: 0.5, y: 20.0 / 92.0)
                title.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                scene.addChild(head)
                scene.addChild(title)
            }
            if previous?.textureKey != key {
                head.texture = texture(key: key) { CityPinRaster.head(pin, night: night, reduceMotion: reduceMotion) }
                // SpriteKit size is in parent coordinates. Preserve the
                // intrinsic canvas when replacing a texture mid-spring.
                head.size = CGSize(width: 140 * priorScale, height: 92 * priorYScale)
            }
            let titleKey = "title|\(pin.title)|\(pin.selected)|\(night)"
            title.texture = texture(key: titleKey) { CityPinRaster.title(pin, night: night) }
            title.size = CGSize(width: 140, height: 40)
            let point = pin.placement.point
            head.position = CGPoint(x: point.x, y: viewport.height - point.y)
            let titleBounds = CityPinLabelLayout.title(pin.title, at: point, selected: pin.selected, above: pin.selected && pin.titleAbove)
            title.position = CGPoint(x: point.x, y: viewport.height - titleBounds.midY)
            head.alpha = pin.reveal
            title.alpha = pin.reveal * (pin.selected ? 1 : pin.titleOpacity)
            head.zPosition = pin.selected ? 3 : 1
            title.zPosition = pin.selected ? 4 : 2
            if reduceMotion {
                head.removeAllActions()
                head.setScale(1)
            } else if previous?.selected != pin.selected {
                head.removeAllActions()
                let photoStart: CGFloat?
                if let previousDiameter = previous?.photoDiameter, let photoDiameter {
                    photoStart = CityPinPhotoTransition.startScale(
                        previousDiameter: previousDiameter, currentScale: priorScale,
                        nextDiameter: photoDiameter, reduceMotion: reduceMotion)
                } else {
                    // A newly owned selected entry is not a new user selection.
                    // Keep its final size when returning from the native map.
                    photoStart = nil
                }
                if !reduceMotion, let start = photoStart {
                    let period = CityPinPhotoTransition.response
                    let damping = CityPinPhotoTransition.damping
                    let duration = CityPinPhotoTransition.duration
                    head.setScale(start)
                    // SpriteKit executes these callbacks on SceneKit's render
                    // queue. Do not inherit this method's MainActor isolation.
                    head.run(.sequence([.customAction(withDuration: duration) { @Sendable node, elapsed in
                        let t = Double(elapsed)
                        let omega = 2 * Double.pi / period
                        let wd = omega * sqrt(1 - damping * damping)
                        let response = exp(-damping * omega * t) * (cos(wd * t) + damping * omega / wd * sin(wd * t))
                        node.setScale(1 - (1 - start) * response)
                    }, .scale(to: 1, duration: 0), .run { @Sendable [weak self] in
                        // Only the Sendable actor reference crosses queues;
                        // UIKit playback changes stay on MainActor.
                        Task { @MainActor [weak self] in self?.onAnimationStateChange() }
                    }]))
                } else { head.setScale(1) }
            }
            entries[pin.id] = Entry(head: head, title: title, textureKey: key,
                                    selected: pin.selected, photoDiameter: photoDiameter)
        }
        // Bound camera-dependent size/contact variants; active textures remain
        // retained by their sprites when the lookup cache is cleared.
        if textures.count > 180 { textures.removeAll(keepingCapacity: true) }
    }


    private func texture(key: String, image: () -> UIImage) -> SKTexture {
        if let cached = textures[key] { return cached }
        let started = ProcessInfo.processInfo.systemUptime
        CityDistrictTrace.write("pin-raster\tstart")
        let texture = SKTexture(image: image())
        textures[key] = texture
        CityDistrictTrace.write("pin-raster\tend\t\((ProcessInfo.processInfo.systemUptime - started) * 1_000)")
        return texture
    }
}

/// C0 diameter continuity only. A retarget starts a new spring and does not
/// claim to preserve the interrupted spring's velocity.
enum CityPinPhotoTransition {
    static let response = 0.46
    static let damping = 0.61
    static let duration = 0.72

    static func startScale(previousDiameter: CGFloat, currentScale: CGFloat,
                           nextDiameter: CGFloat, reduceMotion: Bool) -> CGFloat? {
        if reduceMotion { return 1 }
        guard previousDiameter.isFinite, previousDiameter > 0,
              currentScale.isFinite, currentScale > 0,
              nextDiameter.isFinite, nextDiameter > 0 else { return nil }
        let scale = previousDiameter * currentScale / nextDiameter
        return scale.isFinite && scale > 0 ? scale : nil
    }
}
#endif
