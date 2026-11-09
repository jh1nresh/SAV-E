#if SAVVY_CITY_MVP
import UIKit
import SceneKit

/// Illustrative street dressing on the bundled OSM footprints.
@MainActor
enum CityStreetDetail {
    static let cityHall = CityDistrictCamera.coordinate(x: -94, z: 107)
    static let songzhi = CityDistrictCamera.coordinate(x: 96, z: 112)
    static let podium: [CGPoint] = [
        .init(x: -62.5, y: -47.5), .init(x: 62.5, y: -47.5),
        .init(x: 62.5, y: 47.5), .init(x: -62.5, y: 47.5),
    ]

    enum Finish {
        case retail, office, stone, brick, civic, transit

        var wall: UIColor {
            switch self {
            case .retail: rgb(0xa5a197)
            case .office: rgb(0x788b8d)
            case .stone: rgb(0xc6b391)
            case .brick: rgb(0xb48774)
            case .civic: rgb(0xaf8778)
            case .transit: rgb(0x8f9a91)
            }
        }
        var trim: UIColor {
            switch self {
            case .retail: rgb(0x615956)
            case .office: rgb(0xadb8b6)
            case .stone: rgb(0xe5d7be)
            case .brick: rgb(0xdab29a)
            case .civic: rgb(0xe7d1aa)
            case .transit: rgb(0x526c67)
            }
        }
        var glazing: UIColor {
            switch self {
            case .retail: rgb(0x314b50)
            case .office: rgb(0x426b75)
            case .stone: rgb(0x5a6665)
            case .brick: rgb(0x4c5f63)
            case .civic: rgb(0x475c5b)
            case .transit: rgb(0x526d67)
            }
        }
        var bayWidth: CGFloat {
            switch self {
            case .retail: 6.8
            case .office: 4.7
            case .stone: 3.0
            case .brick: 4.0
            case .civic: 5.7
            case .transit: 3.5
            }
        }
        var isHome: Bool { self == .stone || self == .brick }
    }

    static func finish(for way: Int) -> Finish? {
        switch way {
        case 1303423584: .transit
        case 226945262, 226945263: .office
        case 453245221, 453245222, 453245225, 453245227, 453477004, 453477006,
             538402989, 1038703662: .stone
        case 453245223, 453245224, 453245226, 453245228, 453477005, 607932195,
             1038703659, 1038703660, 1038703661: .brick
        case 371297765, 441377762, 441377763: .civic
        case 137077752: .retail
        default: nil
        }
    }

    struct Caster {
        let footprint: [CGPoint]
        let height: Double
    }

    private struct Edge {
        let x: CGFloat
        let z: CGFloat
        let length: CGFloat
        let angle: CGFloat
    }

    static func decorate(way: Int, footprint: [CGPoint], height: Double, levels: Int?, finish: Finish, in root: SCNNode) {
        let ring = footprint.first == footprint.last ? Array(footprint.dropLast()) : footprint
        guard ring.count >= 3, height > 3 else { return }
        let pairs = zip(ring, ring.dropFirst() + [ring[0]])
        let area = pairs.reduce(CGFloat.zero) { $0 + $1.0.y * $1.1.x - $1.0.x * $1.1.y }
        let edges: [Edge] = pairs.compactMap { a, b in
            let dx = b.x - a.x, dz = a.y - b.y
            let length = hypot(dx, dz)
            guard length >= 2.4 else { return nil }
            return Edge(x: (a.x + b.x) / 2, z: -(a.y + b.y) / 2, length: length,
                        angle: -atan2(dz, dx) + (area > 0 ? .pi : 0))
        }
        let floors = max(1, min(22, levels ?? Int((height / (finish == .retail ? 5.0 : 3.2)).rounded())))
        for (i, edge) in edges.enumerated() {
            let wall = SCNNode()
            wall.position = vector(edge.x, 0, edge.z)
            wall.eulerAngles.y = Float(edge.angle)
            root.addChildNode(wall)
            let columns = max(1, min(36, Int((edge.length / finish.bayWidth).rounded())))
            let size = CGSize(width: edge.length - 0.06, height: height - 0.35)
            let facade = SCNPlane(width: size.width, height: size.height)
            facade.firstMaterial = material(contents: facadeTexture(columns: columns, floors: floors, finish: finish,
                                                                     seed: (way & 255) + i * 11))
            let skin = SCNNode(geometry: facade)
            skin.position = vector(0, height / 2, 0.13)
            wall.addChildNode(skin)

            let storefront = height >= 7.5 && edge.length >= 15
                && (finish == .retail || finish == .office || (finish.isHome && i < 3))
            if edge.length >= 5 {
                box(edge.length, 0.7, 0.60, finish.trim, x: 0, y: height - 0.30, z: 0.07, in: wall)
                if finish == .office {
                    for fraction in [-0.43, -0.22, 0.22, 0.43] {
                        box(0.56, height - 1, 0.65, finish.trim, x: edge.length * fraction,
                            y: height / 2, z: 0.27, in: wall)
                    }
                } else if finish.isHome && edge.length >= 9 {
                    let step = height / Double(floors)
                    let balconyColumns = min(3, max(1, Int(edge.length / 8)))
                    for floor in stride(from: 2, to: floors, by: 2) {
                        for bay in 0..<balconyColumns where (bay + floor + i) % 4 != 1 {
                            let x = edge.length * ((Double(bay) + 0.5) / Double(balconyColumns) - 0.5)
                            let width = min(4.0, edge.length / Double(balconyColumns) * 0.65)
                            let y = Double(floor) * step
                            box(width, 0.30, 1.36, finish.trim, x: x, y: y, z: 0.65, in: wall)
                            box(width, 0.64, 0.14, rgb(0x525d56), x: x, y: y + 0.42, z: 1.27, in: wall)
                        }
                    }
                }
            }
            if storefront { addStorefront(length: edge.length, finish: finish, seed: (way & 255) + i, in: wall) }
        }
        if finish != .transit, let lo = ring.min(by: { $0.x < $1.x }),
           let hi = ring.max(by: { $0.x < $1.x }), hi.x - lo.x > 15 {
            let center = ring.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let cx = center.x / CGFloat(ring.count), cy = center.y / CGFloat(ring.count)
            let path = UIBezierPath()
            path.move(to: ring[0]); ring.dropFirst().forEach { path.addLine(to: $0) }; path.close()
            if [CGPoint(x: cx - 3, y: cy - 2), CGPoint(x: cx - 3, y: cy + 2),
                CGPoint(x: cx + 3, y: cy - 2), CGPoint(x: cx + 3, y: cy + 2)].allSatisfy(path.contains) {
                box(5.8, 1.75, 3.5, finish.trim, x: cx, y: height + 0.86, z: -cy, in: root)
                box(3.0, 0.27, 1.1, rgb(0x6f7267), x: cx, y: height + 1.84, z: -cy, in: root)
            }
        }
    }

    private static func facadeTexture(columns: Int, floors: Int, finish: Finish, seed: Int) -> UIImage {
        let cell: CGFloat = 26
        let width = CGFloat(columns) * cell, height = CGFloat(floors) * cell
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            func fill(_ c: UIColor, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                cg.setFillColor(c.cgColor); cg.fill(CGRect(x: x, y: y, width: w, height: h))
            }
            fill(finish.wall, 0, 0, width, height)
            for row in 0..<floors {
                let y = CGFloat(row) * cell
                if finish == .brick {
                    for band in 0..<5 {
                        let by = y + CGFloat(band) * 5
                        fill(rgb(0x885b51).withAlphaComponent(0.38), 0, by, width, 1)
                        for col in 0..<(columns * 2) {
                            fill(rgb(0x885b51).withAlphaComponent(0.30), CGFloat(col * 13 + band % 2 * 6), by, 1, 5)
                        }
                    }
                }
                let gutter: CGFloat = finish == .office ? 1.5 : finish == .retail ? 2.5
                    : finish == .civic ? 3.5 : finish == .brick ? 5.0 : 6.0
                let wy: CGFloat = finish == .office ? 2.0 : 4.5
                let wh: CGFloat = row == floors - 1 ? 19.5 : (finish.isHome ? 13 : 18)
                fill(finish.trim, 0, y + 23, width, finish == .office ? 2 : 2.7)
                for column in 0..<columns {
                    let x = CGFloat(column) * cell + gutter
                    let w = cell - gutter * 2
                    let variant = (row * 31 + column * 17 + seed) % 13
                    fill(rgb(0x353f3d), x - 0.6, y + wy - 0.7, w + 1.2, wh + 1.1)
                    fill(finish.glazing, x, y + wy, w, wh)
                    fill((variant < 3 ? rgb(0xd8be8d) : rgb(0xadd0d5)).withAlphaComponent(variant < 3 ? 0.57 : 0.21),
                         x + 0.5, y + wy, w * (variant < 5 ? 0.65 : 0.94), wh * 0.44)
                    if finish == .office || finish == .retail || finish == .civic || variant % 2 == 0 {
                        fill(finish.trim.withAlphaComponent(0.84), x + w / 2 - 0.6, y + wy, 1.2, wh)
                    }
                    if finish.isHome {
                        fill(finish.trim, x - 1.2, y + wy + wh, w + 2.4, 1.7)
                    }
                }
            }
        }
    }

    private static func addStorefront(length: CGFloat, finish: Finish, seed: Int, in wall: SCNNode) {
        let number = min(3, max(1, Int(length / 15)))
        let spacing = min(20, length / CGFloat(number))
        let storefronts: [(String, String, Int)] = [
            ("咖啡", "COFFEE", 0x285a52), ("麵包", "BAKERY", 0xa6583f),
            ("花店", "FLOWERS", 0x735357), ("便利商店", "CORNER SHOP", 0x405679),
        ]
        for index in 0..<number {
            let w = spacing * 0.79
            let x = (CGFloat(index) - CGFloat(number - 1) / 2) * spacing
            let theme = storefronts[(seed + index) % storefronts.count]
            let main = index == number / 2
            let store = finish == .retail && main ? ("商場入口", "MALL ENTRANCE", 0x343e47)
                : finish == .office && main ? ("大樓入口", "OFFICE LOBBY", 0x314e56) : theme
            let tint = rgb(store.2)
            box(w, 4.5, 0.44, rgb(0x343f42), x: x, y: 2.4, z: 0.33, in: wall)
            box(w, 0.22, 1.8, rgb(0xafa18e), x: x, y: 0.8, z: 0.93, in: wall)
            for pane in 0..<3 {
                let paneX = x + (CGFloat(pane) - 1) * w / 3
                let glass = SCNPlane(width: w * 0.29, height: 3.7)
                let m = material(contents: shopWindow(door: pane == 1, tint: tint, seed: seed + index + pane))
                glass.firstMaterial = m
                let surface = SCNNode(geometry: glass)
                surface.position = vector(paneX, 2.56, 0.58)
                wall.addChildNode(surface)
            }
            let storefront = finish.isHome || !main
            let canopy = SCNBox(width: w + 0.66, height: 0.42, length: 2.45, chamferRadius: 0.12)
            let trim = material(contents: tint)
            let stripe = storefront ? material(contents: awningFabric(tint)) : trim
            canopy.materials = [stripe, trim, trim, trim, stripe, trim]
            let awning = SCNNode(geometry: canopy)
            awning.position = vector(x, 4.45, 1.45)
            awning.eulerAngles.x = storefront ? 0.13 : 0
            wall.addChildNode(awning)
            let sign = SCNPlane(width: w, height: 2.06)
            sign.firstMaterial = material(contents: signTexture(title: store.0, subtitle: store.1, color: tint))
            let board = SCNNode(geometry: sign)
            board.position = vector(x, 5.72, 0.39)
            wall.addChildNode(board)
        }
    }

    private static func shopWindow(door: Bool, tint: UIColor, seed: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 128, height: 104), format: format).image { output in
            let g = output.cgContext
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: UIColor) {
                g.setFillColor(color.cgColor); g.fill(CGRect(x: x, y: y, width: w, height: h))
            }
            rect(0, 0, 128, 104, rgb(0x343b3f))
            rect(3, 4, 122, 97, rgb(door ? 0x596969 : 0x725844))
            rect(7, 8, 114, 14, rgb(0xa9916c))
            if door {
                rect(12, 12, 104, 90, rgb(0x435b61))
                rect(63, 9, 3, 93, rgb(0xbdb7a4))
                rect(54, 60, 3, 16, rgb(0xcec4a9))
                rect(72, 60, 3, 16, rgb(0xcec4a9))
            } else {
                for row in 0..<2 {
                    let y = CGFloat(row) * 27 + 50
                    rect(9, y, 110, 2, rgb(0xc9aa83))
                    for i in 0..<5 {
                        let c = [0xc29867, 0xb8aa7e, 0x7f7155, 0xd6bd86][(seed + i + row * 2) % 4]
                        rect(12 + CGFloat(i * 21), y - 9 - CGFloat(i % 3) * 3, 11, 9 + CGFloat(i % 3) * 3, rgb(c))
                    }
                }
                rect(11, 26, 30, 21, tint)
                rect(15, 30, 22, 2, rgb(0xe2d3b4))
                rect(15, 36, 17, 2, rgb(0xe2d3b4))
            }
            g.setFillColor(UIColor.white.withAlphaComponent(0.13).cgColor)
            g.addLines(between: [.init(x: 4, y: 12), .init(x: 124, y: 42), .init(x: 124, y: 52), .init(x: 4, y: 24)])
            g.closePath(); g.fillPath()
            rect(2, 88, 124, 2, rgb(0x514940))
        }
    }

    private static func awningFabric(_ tint: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 144, height: 48), format: format).image { output in
            tint.setFill(); output.fill(CGRect(x: 0, y: 0, width: 144, height: 48))
            rgb(0xd1bb96).setFill()
            for x in stride(from: 0, to: 144, by: 18) {
                output.fill(CGRect(x: x, y: 0, width: 5, height: 48))
            }
        }
    }

    private static func signTexture(title: String, subtitle: String, color: UIColor) -> UIImage {
        let size = CGSize(width: 256, height: 68)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.30).setFill()
            context.fill(CGRect(x: 7, y: 6, width: 242, height: 1))
            let p = NSMutableParagraphStyle(); p.alignment = .center
            (title as NSString).draw(in: CGRect(x: 4, y: 8, width: 248, height: 34), withAttributes: [
                .font: UIFont.systemFont(ofSize: 30, weight: .heavy), .foregroundColor: UIColor.white, .paragraphStyle: p,
            ])
            (subtitle as NSString).draw(in: CGRect(x: 5, y: 46, width: 246, height: 15), withAttributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: UIColor.white, .paragraphStyle: p,
            ])
        }
    }

    private static let treePositions: [(CGFloat, CGFloat)] = [
        (-154, 129), (-138, 130), (-122, 130), (-82, 133), (-65, 134), (-47, 134), (-30, 135),
        (-76, 90), (-61, 91), (-46, 91), (-30, 92), (-13, 92), (4, 93),
        (66, 137), (80, 138), (109, 139), (127, 139), (145, 140), (165, 140), (183, 141),
        (119, 97), (132, 98), (146, 98), (165, 99), (181, 100),
        // Inside the plaza boundary; preserve the circular pedestrian paths.
        (117, 58), (119, 45), (120, 30), (122, 17), (155, 13), (178, 14), (198, 16),
    ]

    static func addCorners(to root: SCNNode, casters: [Caster]) {
        decorate(way: 101, footprint: podium, height: 25, levels: 5, finish: .retail, in: root)
        addSign(title: "市府路", subtitle: "CITY HALL RD.", x: -83, z: 127, in: root)
        addSign(title: "松智路", subtitle: "SONGZHI RD.", x: 113, z: 135, in: root)
        addSign(title: "信義路五段", subtitle: "XINYI RD. SEC. 5", x: 83, z: 93, in: root)
        addSign(title: "捷運 101 · 5", subtitle: "MRT EXIT 5", x: -119, z: 86, in: root)
        for (index, point) in treePositions.enumerated() {
            addTree(x: point.0, z: point.1, seed: index, to: root)
        }
        addShadows(casters + [Caster(footprint: podium, height: 25),
                              Caster(footprint: [.init(x: -30, y: -30), .init(x: 30, y: -30),
                                                 .init(x: 30, y: 30), .init(x: -30, y: 30)], height: 370)], to: root)
    }

    private static let foliage: [SCNSphere] = [0x446536, 0x59783f, 0x69874a, 0x7e934d, 0x466943].map { color in
        let mesh = SCNSphere(radius: 1)
        mesh.segmentCount = 10
        mesh.firstMaterial = material(contents: rgb(color))
        return mesh
    }

    private static func addTree(x: CGFloat, z: CGFloat, seed: Int, to root: SCNNode) {
        let scale = 0.76 + CGFloat((seed * 17) % 9) * 0.064
        let tall = seed % 5 == 0
        let y = (tall ? 7.2 : 5.4) * scale
        box(3.4, 0.20, 3.0, rgb(0xa99c7c), x: x, y: 0.94, z: z, in: root)
        box(2.7, 0.06, 2.35, rgb(0x686347), x: x, y: 1.05, z: z, in: root)
        let trunk = SCNCylinder(radius: 0.24 * scale, height: y)
        trunk.radialSegmentCount = 7
        trunk.firstMaterial = material(contents: rgb(0x665447))
        let stem = SCNNode(geometry: trunk)
        stem.position = vector(x, y / 2, z)
        stem.eulerAngles.z = Float(seed % 3 - 1) * 0.055
        root.addChildNode(stem)
        let clusters: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, 0.75, 0.2, 2.8), (-1.55, 0.14, 0.75, 2.2), (1.95, 0.12, -0.4, 2.16),
            (0.55, 0.63, 1.48, 2.01), (-0.5, 1.18, -1.65, 1.93), (-1.1, 1.93, -0.3, 1.84),
        ]
        for (index, c) in clusters.enumerated() {
            let leaf = SCNNode(geometry: foliage[(seed * 3 + index) % foliage.count])
            let spread: CGFloat = tall ? 0.83 : 1.17
            let r = c.3 * scale
            leaf.position = vector(x + c.0 * scale * spread, y + c.1 * scale, z + c.2 * scale * spread)
            leaf.scale = vector(r * spread, r * (tall ? 1.28 : 0.89), r * 0.92)
            leaf.eulerAngles.y = Float(seed % 7) * 0.55
            root.addChildNode(leaf)
        }
    }

    private static func addShadows(_ casters: [Caster], to root: SCNNode) {
        let width: CGFloat = 640, depth: CGFloat = 540
        let centerX: CGFloat = 0, centerZ: CGFloat = 73
        let size = CGSize(width: width * 2, height: depth * 2)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        func pixel(_ x: CGFloat, _ z: CGFloat) -> CGPoint {
            CGPoint(x: (x - centerX + width / 2) * 2, y: (z - centerZ + depth / 2) * 2)
        }
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let shade = rgb(0x262f43)
            for caster in casters {
                let reach = caster.height * 0.55
                let original = caster.footprint.map { pixel($0.x, -$0.y) }
                let shifted = caster.footprint.map { pixel($0.x + reach, -$0.y - reach * 0.68) }
                let silhouette = hull(original + shifted)
                guard let first = silhouette.first else { continue }
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 8, color: shade.withAlphaComponent(0.25).cgColor)
                cg.setFillColor(shade.withAlphaComponent(0.25).cgColor)
                cg.beginPath(); cg.move(to: first)
                silhouette.dropFirst().forEach { cg.addLine(to: $0) }
                cg.closePath(); cg.fillPath()
                cg.restoreGState()
            }
            for (i, tree) in treePositions.enumerated() {
                let p = pixel(tree.0 + 3.0, tree.1 - 1.5)
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 6, color: shade.withAlphaComponent(0.27).cgColor)
                cg.setFillColor(shade.withAlphaComponent(0.30).cgColor)
                let r = CGFloat(7 + i % 4)
                cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.63, width: r * 2, height: r * 1.3))
                cg.restoreGState()
            }
            // Fade the finite texture at its boundary.
            cg.setBlendMode(.destinationOut)
            let clear = UIColor.black.withAlphaComponent(0).cgColor
            let solid = UIColor.black.cgColor
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [solid, clear] as CFArray, locations: [0, 1]) {
                for (start, end) in [(CGPoint.zero, CGPoint(x: 90, y: 0)),
                                     (CGPoint(x: size.width, y: 0), CGPoint(x: size.width - 90, y: 0)),
                                     (CGPoint.zero, CGPoint(x: 0, y: 90)),
                                     (CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: size.height - 90))] {
                    cg.drawLinearGradient(gradient, start: start, end: end, options: [])
                }
            }
        }
        let plane = SCNPlane(width: width, height: depth)
        let surface = material(contents: image)
        surface.lightingModel = .constant
        surface.writesToDepthBuffer = false
        plane.firstMaterial = surface
        let node = SCNNode(geometry: plane)
        node.name = "xinyi-ground-shadows"
        node.position = vector(centerX, 0.94, centerZ)
        node.eulerAngles.x = -.pi / 2
        node.renderingOrder = 3
        root.addChildNode(node)
    }

    private static func hull(_ input: [CGPoint]) -> [CGPoint] {
        let sorted = input.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func half(_ points: [CGPoint]) -> [CGPoint] {
            var result: [CGPoint] = []
            for c in points {
                while result.count >= 2 {
                    let a = result[result.count - 2], b = result[result.count - 1]
                    if (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) > 0 { break }
                    result.removeLast()
                }
                result.append(c)
            }
            return result
        }
        return Array(half(sorted).dropLast() + half(Array(sorted.reversed())).dropLast())
    }

    private static func rgb(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    private static func vector(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 {
        SCNVector3(Float(x), Float(y), Float(z))
    }

    private static func material(contents: Any) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = contents
        m.lightingModel = .blinn
        return m
    }

    private static func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ color: UIColor,
                            x: CGFloat, y: CGFloat, z: CGFloat, in parent: SCNNode) {
        let shape = SCNBox(width: w, height: h, length: d, chamferRadius: 0)
        shape.firstMaterial = material(contents: color)
        let node = SCNNode(geometry: shape)
        node.position = vector(x, y, z)
        parent.addChildNode(node)
    }

    private static func addSign(title: String, subtitle: String, x: Float, z: Float, in root: SCNNode) {
        let size = CGSize(width: 300, height: 107)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.12, green: 0.31, blue: 0.40, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let white = UIColor(white: 0.97, alpha: 1)
            (title as NSString).draw(at: CGPoint(x: 15, y: 8), withAttributes: [
                .font: UIFont.systemFont(ofSize: 43, weight: .bold), .foregroundColor: white,
            ])
            (subtitle as NSString).draw(at: CGPoint(x: 17, y: 65), withAttributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: white,
            ])
        }
        let post = SCNCylinder(radius: 0.13, height: 5.6)
        post.firstMaterial?.diffuse.contents = UIColor(white: 0.54, alpha: 1)
        let pole = SCNNode(geometry: post)
        pole.position = SCNVector3(x, 2.8, z)
        root.addChildNode(pole)
        let board = SCNPlane(width: 11, height: 3.9)
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.isDoubleSided = true
        board.firstMaterial = material
        let node = SCNNode(geometry: board)
        node.position = SCNVector3(x, 6.6, z)
        root.addChildNode(node)
    }
}
#endif
