#if SAVVY_CITY_MVP
import UIKit
import SceneKit

/// Decorative traffic on two non-intersecting one-way carriageways.
@MainActor
enum CityStreetTraffic {
    static let nodeName = "xinyi-street-traffic"

    struct Lane {
        let points: [CGPoint]
        let distances: [CGFloat]
        var length: CGFloat { distances.last ?? 0 }

        init(points: [CGPoint]) {
            self.points = points
            var lengths: [CGFloat] = [0]
            for (a, b) in zip(points, points.dropFirst()) {
                lengths.append((lengths.last ?? 0) + hypot(b.x - a.x, b.y - a.y))
            }
            distances = lengths
        }

        func position(at meters: CGFloat) -> (point: CGPoint, heading: CGFloat) {
            let i = distances.dropFirst().firstIndex { $0 >= meters } ?? points.count - 1
            let a = points[i - 1], b = points[i]
            let dx = b.x - a.x, dz = b.y - a.y
            let leg = distances[i] - distances[i - 1]
            let f = min(1, max(0, (meters - distances[i - 1]) / max(leg, 0.001)))
            return (CGPoint(x: a.x + dx * f, y: a.y + dz * f), atan2(dx, dz))
        }
    }

    static func lanes(from roads: [CityStreetSurface.Road]) -> [Lane] {
        let byID = Dictionary(uniqueKeysWithValues: roads.map { ($0.id, $0) })
        let lanes = [[334841515, 334841513], [198645490, 334841514, 668037877, 229070522]]
        return lanes.compactMap { ids in
            var path: [CGPoint] = []
            for id in ids {
                guard let road = byID[id] else { return nil }
                for point in road.path where path.last.map({ hypot($0.x - point.x, $0.y - point.y) > 0.2 }) ?? true {
                    path.append(point)
                }
            }
            guard path.count >= 2 else { return nil }
            // The outside lane of each carriageway, respecting its OSM direction.
            let offset = CityStreetSurface.offset(path, by: 3.35)
            var clipped: [CGPoint] = []
            for (a, b) in zip(offset, offset.dropFirst()) where abs(b.x - a.x) > 0.01 {
                let t0 = (-274 - a.x) / (b.x - a.x), t1 = (302 - a.x) / (b.x - a.x)
                let begin = max(0, min(t0, t1)), end = min(1, max(t0, t1))
                guard end > begin else { continue }
                for f in [begin, end] {
                    let point = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                    if clipped.last.map({ hypot($0.x - point.x, $0.y - point.y) > 0.08 }) ?? true {
                        clipped.append(point)
                    }
                }
            }
            return clipped.count >= 2 ? Lane(points: clipped) : nil
        }
    }

    static func add(to root: SCNNode, roads: [CityStreetSurface.Road]) {
        let layer = SCNNode()
        layer.name = nodeName
        layer.isPaused = true
        root.addChildNode(layer)
        let paint = [0xdeb54f, 0x4c7f82, 0xe4e1d8, 0xa65950, 0x748097]
        for (direction, lane) in lanes(from: roads).enumerated() {
            let carCount = 6
            for i in 0..<carCount {
                let taxi = (i + direction) % 4 == 0
                let color = taxi ? paint[0] : paint[1 + (i + direction) % (paint.count - 1)]
                let car = model(color: color, taxi: taxi, tall: (i + direction) % 3 == 2)
                let fraction = (CGFloat(i) + (direction == 0 ? 0.26 : 0.68)) / CGFloat(carCount)
                let start = lane.length * fraction
                let first = lane.position(at: start)
                car.position = world(first.point)
                car.eulerAngles.y = Float(first.heading)
                layer.addChildNode(car)
                let zero = lane.position(at: 0)
                let reset = SCNAction.group([
                    .move(to: world(zero.point), duration: 0),
                    .rotateTo(x: 0, y: zero.heading, z: 0, duration: 0, usesShortestUnitArc: true),
                    .fadeOpacity(to: 0, duration: 0),
                ])
                let speed: CGFloat = direction == 0 ? 10.8 : 11.6
                let loop = SCNAction.repeatForever(.sequence([reset, travel(on: lane, from: 0, speed: speed)]))
                car.runAction(.sequence([travel(on: lane, from: start, speed: speed), loop]))
            }
        }
    }

    private static func travel(on lane: Lane, from start: CGFloat, speed: CGFloat) -> SCNAction {
        let fadeLength: CGFloat = 14
        let stops = Set(lane.distances + [fadeLength, lane.length - fadeLength]).sorted().filter { $0 > start }
        var previous = start
        var actions: [SCNAction] = []
        for next in stops {
            let end = lane.position(at: next)
            let duration = (next - previous) / speed
            let opacity = max(0, min(1, next / fadeLength, (lane.length - next) / fadeLength))
            actions.append(.group([
                .move(to: world(end.point), duration: duration),
                .rotateTo(x: 0, y: end.heading, z: 0, duration: min(0.2, duration), usesShortestUnitArc: true),
                .fadeOpacity(to: opacity, duration: duration),
            ]))
            previous = next
        }
        return .sequence(actions)
    }

    private static func world(_ point: CGPoint) -> SCNVector3 {
        SCNVector3(Float(point.x), Float(CityStreetSurface.altitude), Float(point.y))
    }

    private static let wheel = { () -> SCNCylinder in
        let geometry = SCNCylinder(radius: 0.37, height: 0.26)
        geometry.radialSegmentCount = 10
        geometry.firstMaterial?.diffuse.contents = CityStreetSurface.color(0x25282e)
        return geometry
    }()

    private static func model(color: Int, taxi: Bool, tall: Bool) -> SCNNode {
        let car = SCNNode()
        let length: CGFloat = tall ? 5.15 : 4.6
        let width: CGFloat = tall ? 2.12 : 1.91
        let bodyHeight: CGFloat = tall ? 0.90 : 0.62
        func body(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                  _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ tint: Int, bevel: CGFloat = 0.07) {
            let geometry = SCNBox(width: w, height: h, length: d, chamferRadius: bevel)
            let material = SCNMaterial()
            material.diffuse.contents = CityStreetSurface.color(tint)
            material.lightingModel = .blinn
            geometry.firstMaterial = material
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(Float(x), Float(y), Float(z))
            car.addChildNode(node)
        }
        body(width, bodyHeight, length, 0, 0.52 + bodyHeight / 2, 0, color, bevel: 0.24)
        body(width * 0.79, tall ? 0.72 : 0.55, length * (tall ? 0.66 : 0.54), 0,
             tall ? 1.56 : 1.25, -0.27, 0x394a54, bevel: 0.19)
        body(width * 0.70, 0.15, length * (tall ? 0.63 : 0.41), 0,
             tall ? 1.92 : 1.54, -0.33, color, bevel: 0.05)
        for side: CGFloat in [-1, 1] {
            for end: CGFloat in [-1, 1] {
                let node = SCNNode(geometry: wheel)
                node.position = SCNVector3(Float(side * (width / 2 - 0.12)), 0.38, Float(end * length * 0.32))
                node.eulerAngles.z = .pi / 2
                car.addChildNode(node)
            }
            body(0.43, 0.15, 0.08, side * width * 0.31, 0.85, length / 2 - 0.08, 0xffefcd)
            body(0.37, 0.14, 0.08, side * width * 0.32, 0.84, 0.08 - length / 2, 0xb74943)
        }
        if taxi { body(0.53, 0.20, 0.25, 0, tall ? 2.08 : 1.69, 0, 0xf3e2a5) }
        let shadow = SCNNode(geometry: carShadow)
        shadow.eulerAngles.x = -.pi / 2
        shadow.position.y = 0.025
        shadow.renderingOrder = 2
        car.addChildNode(shadow)
        return car
    }

    private static let carShadow = { () -> SCNPlane in
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 64), format: format).image { renderer in
            let cg = renderer.cgContext
            cg.setShadow(offset: .zero, blur: 5, color: UIColor.black.withAlphaComponent(0.30).cgColor)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.38).cgColor)
            cg.fillEllipse(in: CGRect(x: 9, y: 9, width: 30, height: 46))
        }
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        let plane = SCNPlane(width: 3.6, height: 6.6)
        plane.firstMaterial = material
        return plane
    }()
}
#endif
