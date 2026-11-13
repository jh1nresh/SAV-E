#if SAVVY_CITY_MVP
import SwiftUI
import SpriteKit
import simd

/// The same immutable bounds feed the scene sprites and native tap observer.
struct CityContextLabel: Identifiable {
    let place: CityContextPlace
    let bounds: CGRect
    var id: String { place.id }
}

@MainActor
enum CityContextLabels {
    static let maximumVisible = 24
    static let maximumProjected = 384
    private struct Indexed {
        let place: CityContextPlace
        let world: SIMD3<Double>
    }
    private struct Cell: Hashable { let x: Int; let z: Int }
    private static let cells: [Cell: [Indexed]] = {
        Dictionary(grouping: (CityContextPlace.catalogue?.records ?? []).map {
            Indexed(place: $0, world: CityDistrictCamera.world(.init(latitude: $0.latitude, longitude: $0.longitude)))
        }) { Cell(x: Int(floor($0.world.x / 150)), z: Int(floor($0.world.z / 150))) }
    }()

    static func projected(frame: CityDistrictCamera, registration: CityDistrictRegistration,
                          excluding: Set<String>, reserved: [CGRect]) -> [CityContextLabel] {
        guard let projection = frame.projection, frame.distance < 8_500 else { return [] }
        let center = CityDistrictCamera.world(registration.sceneCoordinate(frame.mapCamera.centerCoordinate))
        let radius = min(1_200, max(240, frame.distance * 0.45))
        var nearby: [Indexed] = []
        for x in Int(floor((center.x-radius)/150))...Int(floor((center.x+radius)/150)) {
            for z in Int(floor((center.z-radius)/150))...Int(floor((center.z+radius)/150)) {
                nearby += cells[Cell(x: x, z: z)] ?? []
            }
        }
        // At most 384 pure projections; no MapProxy or per-record native views.
        let nearest = nearby.filter { !excluding.contains($0.place.id) }.sorted {
            let a = simd_distance_squared($0.world, center), b = simd_distance_squared($1.world, center)
            return a == b ? $0.place.id < $1.place.id : a < b
        }.prefix(maximumProjected)
        let projected = nearest.compactMap { item -> CityContextLabel? in
            guard let point = projection.point(at: item.world) else { return nil }
            let bilingual = item.place.title != item.place.originalName
            let width = min(CGFloat(156), max(64, CGFloat(min(item.place.title.count, 18)) * 6.5 + 24))
            return .init(place: item.place, bounds: CGRect(x: point.x - width/2, y: point.y - 22,
                                                          width: width, height: bilingual ? 52 : 44))
        }
        return declutter(projected, viewport: frame.viewport, reserved: reserved)
    }

    /// Screen-space collision is separate from source identity and geography.
    static func declutter(_ candidates: [CityContextLabel], viewport: CGSize,
                          reserved: [CGRect]) -> [CityContextLabel] {
        guard viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0 else { return [] }
        let usable = CGRect(origin: .zero, size: viewport).insetBy(dx: 12, dy: 12)
        var occupied = reserved.map { $0.insetBy(dx: -6, dy: -6) }
        var ids = Set<String>()
        var result: [CityContextLabel] = []
        for label in candidates.sorted(by: {
            let a = priority($0.place.category), b = priority($1.place.category)
            return a == b ? $0.id < $1.id : a > b
        }) {
            let rect = label.bounds
            guard !rect.isNull, !rect.isInfinite,
                  rect.origin.x.isFinite, rect.origin.y.isFinite,
                  rect.width >= 44, rect.height >= 44,
                  usable.contains(rect), !occupied.contains(where: { $0.intersects(rect) }),
                  ids.insert(label.id).inserted else { continue }
            result.append(label); occupied.append(rect.insetBy(dx: -4, dy: -4))
            if result.count == maximumVisible { break }
        }
        return result
    }
    private static func priority(_ category: CityContextPlace.Category) -> Int {
        switch category {
        case .transit: 4
        case .sight, .park: 3
        case .cafe, .food, .shopping, .hotel: 2
        case .building, .service: 1
        }
    }

    static func image(_ label: CityContextLabel, night: Bool) -> UIImage {
        let size = label.bounds.size
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let color: Color = switch label.place.category {
            case .transit: night ? Color(red: 0.55, green: 0.74, blue: 1) : Color(red: 0.18, green: 0.40, blue: 0.66)
            case .park: night ? Color(red: 0.55, green: 0.85, blue: 0.65) : Color(red: 0.22, green: 0.46, blue: 0.29)
            case .cafe, .food: night ? Color(red: 0.98, green: 0.75, blue: 0.56) : Color(red: 0.54, green: 0.31, blue: 0.18)
            case .shopping, .hotel, .sight: night ? Color(red: 0.96, green: 0.83, blue: 0.56) : Color(red: 0.52, green: 0.39, blue: 0.17)
            case .service, .building: night ? Color(red: 0.76, green: 0.80, blue: 0.92) : Color(red: 0.28, green: 0.35, blue: 0.43)
            }
            let tint = UIColor(color)
            let bilingual = label.place.title != label.place.originalName
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail; paragraph.alignment = .center
            func text(_ text: String, y: CGFloat, font: UIFont, color: UIColor) {
                let rect = CGRect(x: 2, y: y, width: size.width-4, height: 18)
                let common: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
                var halo = common
                halo[.foregroundColor] = night ? UIColor(white: 0.08, alpha: 0.96) : UIColor(white: 1, alpha: 0.95)
                // A translated silhouette protects dense CJK interiors; font
                // stroke attributes hollowed the 10pt fallback glyphs at night.
                for offset in [CGPoint(x:-0.75,y:0),CGPoint(x:0.75,y:0),CGPoint(x:0,y:-0.75),CGPoint(x:0,y:0.75)] {
                    (text as NSString).draw(in: rect.offsetBy(dx:offset.x,dy:offset.y), withAttributes: halo)
                }
                var fill = common; fill[.foregroundColor] = color
                (text as NSString).draw(in: rect, withAttributes: fill)
            }
            let badge = CGRect(x: size.width/2-6, y: 1, width: 12, height: 12)
            cg.setFillColor(tint.cgColor); cg.fillEllipse(in: badge)
            cg.setStrokeColor(UIColor.white.cgColor); cg.setLineWidth(1); cg.strokeEllipse(in: badge)
            let symbol = UIImage(systemName: label.place.symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .bold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            symbol?.draw(in: badge.insetBy(dx: 2, dy: 2))
            text(label.place.title, y: 17, font: .systemFont(ofSize: 12, weight: .bold), color: tint)
            if bilingual { text(label.place.originalName, y: 33, font: .systemFont(ofSize: 12, weight: .bold), color: tint) }
        }
    }
}

/// Bounded raster cache; labels never run independent position animations.
@MainActor
final class CityContextLabelSprites {
    private var nodes: [String: SKSpriteNode] = [:]
    private var textures: [String: SKTexture] = [:]
    func update(_ labels: [CityContextLabel], scene: SKScene, viewport: CGSize, night: Bool) {
        let ids = Set(labels.map(\.id))
        for id in Array(nodes.keys) where !ids.contains(id) { nodes.removeValue(forKey: id)?.removeFromParent() }
        for label in labels {
            let node = nodes[label.id] ?? SKSpriteNode()
            if node.parent == nil { scene.addChild(node); node.zPosition = 0 }
            let key = "\(label.id)|\(night)|\(Int(label.bounds.width))"
            if textures[key] == nil {
                if textures.count >= 64 { textures.removeAll(keepingCapacity: true) }
                textures[key] = SKTexture(image: CityContextLabels.image(label, night: night))
            }
            node.texture = textures[key]; node.size = label.bounds.size
            node.position = CGPoint(x: label.bounds.midX, y: viewport.height-label.bounds.midY)
            nodes[label.id] = node
        }
    }
}
#endif
