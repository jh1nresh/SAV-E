#if SAVVY_CITY_MVP
import UIKit
import SceneKit

/// Decorative traffic following the bundled Xinyi street geometry.
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

        func distance(atX x: CGFloat) -> CGFloat? {
            distance(at: x, along: \.x)
        }

        func distance(at value: CGFloat, along axis: KeyPath<CGPoint, CGFloat>) -> CGFloat? {
            for (i, a) in points.dropLast().enumerated() {
                let start = a[keyPath: axis], end = points[i + 1][keyPath: axis]
                guard start != end, min(start, end) <= value, value <= max(start, end) else { continue }
                let fraction = (value - start) / (end - start)
                return distances[i] + (distances[i + 1] - distances[i]) * fraction
            }
            return nil
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

    struct Pace {
        struct Sample {
            let distance: CGFloat
            let speed: CGFloat
            let time: CGFloat
        }

        let samples: [Sample]
        var duration: CGFloat { samples.last!.time }
        static let fadeLength: CGFloat = 14

        init(lane: Lane, cruiseSpeed: CGFloat, junctions: [CGFloat]) {
            let approach: CGFloat = 34
            let speedSteps: [CGFloat] = [-34, -24, -16, -8, 0, 8, 16, 24, 34]
            let landmarks = junctions.flatMap { crossing in speedSteps.map { crossing + $0 } }
            let distances = Set(lane.distances + landmarks + [Self.fadeLength, lane.length - Self.fadeLength])
                .filter { $0 >= 0 && $0 <= lane.length }.sorted()
            var result: [Sample] = []
            for distance in distances {
                let nearest = junctions.map { abs($0 - distance) }.min() ?? approach
                let t = min(1, nearest / approach)
                let speed = cruiseSpeed * (0.52 + 0.48 * t * t * (3 - 2 * t))
                let time = result.last.map { $0.time + 2 * (distance - $0.distance) / ($0.speed + speed) } ?? 0
                result.append(Sample(distance: distance, speed: speed, time: time))
            }
            samples = result
        }

        func startTimes(direction: Int) -> [CGFloat] {
            [0.08, 0.22, 0.41, 0.55, 0.76, 0.9].map { (CGFloat($0) + CGFloat(direction) * 0.06) * duration }
        }

        func sample(at time: CGFloat) -> Sample {
            if time <= 0 { return samples.first! }
            guard let i = samples.dropFirst().firstIndex(where: { $0.time >= time }) else { return samples.last! }
            let a = samples[i - 1], b = samples[i]
            let elapsed = time - a.time
            let acceleration = (b.speed - a.speed) / (b.time - a.time)
            return Sample(distance: a.distance + elapsed * (a.speed + acceleration * elapsed / 2),
                          speed: a.speed + acceleration * elapsed, time: time)
        }

        func opacity(at distance: CGFloat) -> CGFloat {
            max(0, min(1, distance / Self.fadeLength, (samples.last!.distance - distance) / Self.fadeLength))
        }
    }

    struct Flow {
        enum Street { case xinyi, songzhi, cityHall }

        let street: Street
        let lane: Lane
        let pace: Pace
        let cycle: CGFloat
        let starts: [CGFloat]

        func travelTime(for start: CGFloat, elapsed: CGFloat) -> CGFloat {
            (start + elapsed).truncatingRemainder(dividingBy: cycle)
        }
    }

    static func lanes(from roads: [CityStreetSurface.Road]) -> [Lane] {
        let byID = Dictionary(uniqueKeysWithValues: roads.map { ($0.id, $0) })
        return [[334841515, 334841513], [198645490, 334841514, 668037877, 229070522]].compactMap { ids in
            guard let path = connectedPath(ids, in: byID) else { return nil }
            return clippedLane(path, offset: 3.35, along: \.x, in: -274...302)
        }
    }

    static func flows(from roads: [CityStreetSurface.Road]) -> [Flow] {
        let through = lanes(from: roads).enumerated().map { direction, lane in
            let junctions = [CityStreetDetail.cityHall, CityStreetDetail.songzhi]
                .compactMap { lane.distance(atX: CGFloat(CityDistrictCamera.world($0).x)) }
            return (lane, Pace(lane: lane, cruiseSpeed: direction == 0 ? 10.8 : 11.6, junctions: junctions))
        }
        let byID = Dictionary(uniqueKeysWithValues: roads.map { ($0.id, $0) })
        let cycle: CGFloat = 78
        let songzhiX = CGFloat(CityDistrictCamera.world(CityStreetDetail.songzhi).x)
        let arterial = through.enumerated().compactMap { direction, pair in
            phasedFlow(.xinyi, lane: pair.0, pace: pair.1, cycle: cycle,
                       crossing: pair.0.distance(atX: songzhiX),
                       passages: [6, 12, 18, 24, 30, 36].map { $0 + CGFloat(direction) * 1.4 })
        }
        let songzhi = connectedPath([23403474, 1335559367, 1335559366], in: byID)
        let crossStreet = songzhi.map { path in
            [path, Array(path.reversed())].enumerated().compactMap { direction, path -> Flow? in
                guard let lane = clippedLane(path, offset: 2.3, along: \.y, in: 18...207),
                      let crossing = lane.distance(at: 118, along: \.y) else { return nil }
                let pace = Pace(lane: lane, cruiseSpeed: 8, junctions: [crossing])
                return phasedFlow(.songzhi, lane: lane, pace: pace, cycle: cycle, crossing: crossing,
                                  passages: [51, 64].map { $0 + CGFloat(direction) * 1.4 })
            }
        } ?? []
        // The conflicting movements must all share the same cycle.
        let mainFlows: [Flow]
        if arterial.count == 2 && crossStreet.count == 2 {
            mainFlows = arterial + crossStreet
        } else {
            mainFlows = through.enumerated().map { direction, pair in
                Flow(street: .xinyi, lane: pair.0, pace: pair.1, cycle: pair.1.duration,
                     starts: pair.1.startTimes(direction: direction))
            }
        }

        // City Hall Road ends at Xinyi. Keep these local movements north of
        // the junction until there is a separate set of turn paths.
        let approaches = [231534776, 252657368].enumerated().compactMap { direction, id -> Flow? in
            guard let path = byID[id]?.path,
                  let lane = clippedLane(path, offset: 0, along: \.y, in: 15...90) else { return nil }
            let pace = Pace(lane: lane, cruiseSpeed: 7, junctions: [])
            return Flow(street: .cityHall, lane: lane, pace: pace, cycle: cycle,
                        starts: [4, 30, 56].map { $0 + CGFloat(direction) * 4 })
        }
        return mainFlows + approaches
    }

    private static func phasedFlow(_ street: Flow.Street, lane: Lane, pace: Pace, cycle: CGFloat,
                                   crossing: CGFloat?, passages: [CGFloat]) -> Flow? {
        guard pace.duration < cycle, let crossing,
              let time = pace.samples.first(where: { $0.distance == crossing })?.time else { return nil }
        let starts = passages.map { (cycle + time - $0).truncatingRemainder(dividingBy: cycle) }
        return Flow(street: street, lane: lane, pace: pace, cycle: cycle, starts: starts)
    }

    private static func connectedPath(_ ids: [Int], in roads: [Int: CityStreetSurface.Road]) -> [CGPoint]? {
        var path: [CGPoint] = []
        for id in ids {
            guard let way = roads[id]?.path, let first = way.first else { return nil }
            if let last = path.last, hypot(last.x - first.x, last.y - first.y) > 0.2 { return nil }
            for point in way where path.last.map({ hypot($0.x - point.x, $0.y - point.y) > 0.2 }) ?? true {
                path.append(point)
            }
        }
        return path
    }

    private static func clippedLane(_ path: [CGPoint], offset: CGFloat, along axis: KeyPath<CGPoint, CGFloat>,
                                    in range: ClosedRange<CGFloat>) -> Lane? {
        let shifted = CityStreetSurface.offset(path, by: offset)
        var clipped: [CGPoint] = []
        for (a, b) in zip(shifted, shifted.dropFirst()) {
            let start = a[keyPath: axis], delta = b[keyPath: axis] - start
            guard abs(delta) > 0.01 else { continue }
            let t0 = (range.lowerBound - start) / delta, t1 = (range.upperBound - start) / delta
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

    static func add(to root: SCNNode, roads: [CityStreetSurface.Road]) {
        let layer = SCNNode()
        layer.name = nodeName
        layer.isPaused = true
        root.addChildNode(layer)
        let paint = [0xdeb54f, 0x4c7f82, 0xe4e1d8, 0xa65950, 0x748097]
        for (direction, flow) in flows(from: roads).enumerated() {
            let lane = flow.lane, pace = flow.pace
            let idle = flow.cycle - pace.duration
            let zero = lane.position(at: 0)
            let reset = SCNAction.group([
                .move(to: world(zero.point), duration: 0),
                .rotateTo(x: 0, y: zero.heading, z: 0, duration: 0, usesShortestUnitArc: true),
                .fadeOpacity(to: 0, duration: 0),
            ])
            let loop = SCNAction.repeatForever(.sequence([reset, travel(on: lane, pace: pace, from: 0),
                                                          .wait(duration: idle)]))
            for (i, start) in flow.starts.enumerated() {
                let taxi = (i + direction) % 4 == 0
                let color = taxi ? paint[0] : paint[1 + (i + direction) % (paint.count - 1)]
                let car = vehicleModel(color: color, taxi: taxi, tall: (i + direction) % 3 == 2)
                let distance = pace.sample(at: start).distance
                let first = lane.position(at: distance)
                car.position = world(first.point)
                car.eulerAngles.y = Float(first.heading)
                car.opacity = pace.opacity(at: distance)
                layer.addChildNode(car)
                let remaining = start < pace.duration
                    ? SCNAction.sequence([travel(on: lane, pace: pace, from: start), .wait(duration: idle)])
                    : SCNAction.wait(duration: flow.cycle - start)
                car.runAction(.sequence([remaining, loop]))
            }
        }
    }

    private static func travel(on lane: Lane, pace: Pace, from start: CGFloat) -> SCNAction {
        var previous = pace.sample(at: start)
        var actions: [SCNAction] = []
        for next in pace.samples where next.time > start {
            let end = lane.position(at: next.distance)
            let duration = next.time - previous.time
            let movement = SCNAction.move(to: world(end.point), duration: duration)
            // Match the speeds on either side of each checkpoint.
            let entry = Float(2 * previous.speed / (previous.speed + next.speed))
            movement.timingFunction = { @Sendable time in
                time * (entry + (1 - entry) * time)
            }
            actions.append(.group([
                movement,
                .rotateTo(x: 0, y: end.heading, z: 0, duration: min(0.2, duration), usesShortestUnitArc: true),
                .fadeOpacity(to: pace.opacity(at: next.distance), duration: duration),
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

    static func vehicleModel(color: Int, taxi: Bool, tall: Bool, parked: Bool = false) -> SCNNode {
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
        // A parked car never needs its body pieces transformed independently.
        // Keep the shared ground shadow separate from the opaque body mesh.
        let vehicle = parked ? car.flattenedClone() : car
        vehicle.addChildNode(shadow)
        return vehicle
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
