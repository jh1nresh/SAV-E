#if SAVVY_CITY_MVP
import UIKit
import SceneKit

/// Illustrative street dressing on the bundled OSM footprints.
@MainActor
enum CityStreetDetail {
    static let xinyiOfficeWayID = 226945262
    static let cityHall = CityDistrictCamera.coordinate(x: -94, z: 107)
    static let songzhi = CityDistrictCamera.coordinate(x: 96, z: 112)
    nonisolated static let podium: [CGPoint] = [
        .init(x: -62.5, y: -47.5), .init(x: 62.5, y: -47.5),
        .init(x: 62.5, y: 47.5), .init(x: -62.5, y: 47.5),
    ]

    enum Finish {
        case retail, office, stone, brick, plaster, sage, civic, transit

        var wall: UIColor {
            switch self {
            case .retail: rgb(0xa5a197)
            case .office: rgb(0x788b8d)
            case .stone: rgb(0xc6b391)
            case .brick: rgb(0xb48774)
            case .plaster: rgb(0xc5c2b4)
            case .sage: rgb(0x9caea1)
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
            case .plaster: rgb(0xe1ded0)
            case .sage: rgb(0xcbd4c5)
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
            case .plaster: rgb(0x576b71)
            case .sage: rgb(0x48636a)
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
            case .plaster: 3.5
            case .sage: 3.6
            case .civic: 5.7
            case .transit: 3.5
            }
        }
        var isHome: Bool { self == .stone || self == .brick || self == .plaster || self == .sage }

        var roofTint: Int {
            switch self {
            case .retail: 0x9c9588
            case .office: 0x929e9d
            case .stone: 0xb9aa93
            case .brick: 0xbda48f
            case .plaster: 0xa6a9a1
            case .sage: 0x899b98
            case .civic: 0xa69c90
            case .transit: 0x8e9892
            }
        }
    }

    static func finish(for way: Int) -> Finish? {
        switch way {
        case 1303423584: .transit
        case xinyiOfficeWayID, 226945263, 383731054, 137077756, 228938182: .office
        case 137077760: .stone
        case 142113976, 229737339: .civic
        case CitySceneData.att4FunWayID, 269773067, 274647896, 309155292, 391309615, 513491894, 663679150, 671744410: .retail
        case 453245221, 453245222, 453245225, 453245227, 453477004, 453477006,
             538402989, 1038703662: .stone
        case 453245223, 453245224, 453245226, 453245228, 453477005, 607932195,
             1038703659, 1038703660, 1038703661: .brick
        case 371297765, 441377762, 441377763: .civic
        case 137077752: .retail
        default: nil
        }
    }

    static func genericFinish(tags: [String: String], height: Double, way: Int) -> Finish {
        let kind = tags["building"] ?? ""
        if kind == "roof" || hasPlainWalls(tags) { return .transit }
        if ["glass", "mirror"].contains(tags["building:material"] ?? "") { return .office }
        if kind == "retail" || tags["shop"] == "mall" { return .retail }
        if kind == "hotel" || tags["tourism"] == "hotel" { return mappedFinish(tags["building:colour"]) ?? .stone }
        if kind == "office" || (kind == "commercial" && height >= 30) { return .office }
        if let tint = mappedFinish(tags["building:colour"]) { return tint }
        if kind == "apartments" || kind == "residential" {
            return way.isMultiple(of: 2) ? .stone : .brick
        }
        if kind == "school" || kind == "public" || kind == "temple" { return .civic }
        return kind == "yes" && height <= 20 ? .plaster : .office
    }

    static func hasPlainWalls(_ tags: [String: String]) -> Bool {
        ["construction", "industrial", "outbuilding", "service", "toilets"].contains(tags["building"] ?? "")
            || ["shelter", "toilets"].contains(tags["amenity"] ?? "")
    }

    static func genericRoofTint(for finish: Finish, tag: String?) -> Int {
        let name = tag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name == "grey" || name == "gray" || name == "silver" { return 0x919996 }
        return (mappedFinish(name) ?? finish).roofTint
    }

    private static func mappedFinish(_ tag: String?) -> Finish? {
        guard let color = tag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        switch color {
        case "lightpink": return .brick
        case "white", "silver", "grey", "gray": return .plaster
        default: break
        }
        // Use bounded families so source colors cannot create a material per building.
        guard color.first == "#", color.count == 7, color.dropFirst().allSatisfy(\.isHexDigit),
              let hex = UInt32(color.dropFirst(), radix: 16) else { return nil }
        let red = Int((hex >> 16) & 255), green = Int((hex >> 8) & 255), blue = Int(hex & 255)
        if red - green > 24 && red - blue > 22 { return .brick }
        if red - blue > 22 { return .stone }
        if max(green, blue) - red > 22 { return .sage }
        if max(red, green, blue) - min(red, green, blue) < 18, min(red, green, blue) > 140 { return .plaster }
        return nil
    }

    nonisolated struct Caster: Sendable {
        let footprint: [CGPoint]
        let height: Double
    }

    private struct Edge {
        let x: CGFloat
        let z: CGFloat
        let length: CGFloat
        let angle: CGFloat
    }

    private static func wallEdges(in ring: [CGPoint]) -> [Edge] {
        let pairs = zip(ring, ring.dropFirst() + [ring[0]])
        let area = pairs.reduce(CGFloat.zero) { $0 + $1.0.y * $1.1.x - $1.0.x * $1.1.y }
        return pairs.compactMap { a, b in
            let dx = b.x - a.x, dz = a.y - b.y
            let length = hypot(dx, dz)
            guard length >= 2.4 else { return nil }
            return Edge(x: (a.x + b.x) / 2, z: -(a.y + b.y) / 2, length: length,
                        angle: -atan2(dz, dx) + (area > 0 ? .pi : 0))
        }
    }

    static func decorate(way: Int, footprint: [CGPoint], height: Double, levels: Int?, finish: Finish, detailed: Bool = true, includeFacade: Bool = true, in root: SCNNode) {
        let ring = footprint.first == footprint.last ? Array(footprint.dropLast()) : footprint
        guard ring.count >= 3, height > 3 else { return }
        let edges = wallEdges(in: ring)
        let floors = max(1, min(22, levels ?? Int((height / (finish == .retail ? 5.0 : 3.2)).rounded())))
        let principalEdges = Set(edges.indices.sorted { edges[$0].length > edges[$1].length }.prefix(4))
        let storefrontEdges = Set(edges.indices.sorted { edges[$0].length > edges[$1].length }.prefix(2))
        for (i, edge) in edges.enumerated() {
            let wall = SCNNode()
            wall.position = vector(edge.x, 0, edge.z)
            wall.eulerAngles.y = Float(edge.angle)
            root.addChildNode(wall)
            if includeFacade {
                let columns = max(1, min(36, Int((edge.length / finish.bayWidth).rounded())))
                let size = CGSize(width: edge.length - 0.06, height: height - 0.35)
                let facade = SCNPlane(width: size.width, height: size.height)
                let seed = (way & 255) + i * 11
                let textures = detailed
                    ? (facadeTexture(columns: columns, floors: floors, finish: finish, seed: seed),
                       facadeTexture(columns: columns, floors: floors, finish: finish, seed: seed, illumination: true))
                    : repeatedFacade(finish: finish, variant: seed % 4)
                let skinMaterial = material(contents: textures.0)
                skinMaterial.emission.contents = textures.1
                skinMaterial.emission.intensity = 0
                skinMaterial.name = "city-lit-facade"
                if !detailed {
                    // Generic blocks reuse small atlas tiles; never allocate an image per wall.
                    for property in [skinMaterial.diffuse, skinMaterial.emission] {
                        property.wrapS = .repeat; property.wrapT = .repeat
                        property.contentsTransform = SCNMatrix4MakeScale(Float(columns) / 2, Float(floors) / 2, 1)
                    }
                    skinMaterial.emission.contentsTransform = SCNMatrix4MakeScale(
                        Float(columns) / Float(facadeLightCells), Float(floors) / Float(facadeLightCells), 1)
                }
                facade.firstMaterial = skinMaterial
                let skin = SCNNode(geometry: facade)
                skin.position = vector(0, height / 2, 0.13)
                wall.addChildNode(skin)
            }

            let storefront = detailed && storefrontEdges.contains(i) && height >= 7.5 && edge.length >= 15
                && (finish == .retail || finish == .office || (finish.isHome && i < 3))
            if detailed && principalEdges.contains(i) && edge.length >= 5 {
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
        if detailed, finish != .transit {
            CityRoofDetails.add(footprint: ring, height: height, finish: finish, seed: way, to: root)
        }
    }

    // The street elevation uses the stone grid and curved metal lobby in
    // Sunty's project photograph. The OSM shell remains the roof pin anchor.
    static func addXinyiOffice(footprint: [CGPoint], height: CGFloat, in root: SCNNode) -> Bool {
        let ring = footprint.first == footprint.last ? Array(footprint.dropLast()) : footprint
        guard ring.count == 4, height > 24 else { return false }
        let edges = wallEdges(in: ring)
        guard let street = edges.firstIndex(where: { $0.length > 60 && cos($0.angle) < -0.9 }),
              edges.count == 4, edges.allSatisfy({ $0.length > 16 }) else { return false }
        let detail = SCNNode()
        detail.name = "xinyi-office-detail"
        let sideStone = xinyiOfficeMaterial(columns: 4, entrance: false)
        for (index, edge) in edges.enumerated() {
            let wall = SCNNode()
            wall.position = vector(edge.x, 0, edge.z)
            wall.eulerAngles.y = Float(edge.angle)
            let entrance = index == street
            let facade = SCNPlane(width: edge.length - 0.04, height: height - 0.04)
            facade.firstMaterial = edge.length > 60 ? xinyiOfficeMaterial(columns: 15, entrance: entrance) : sideStone
            let skin = SCNNode(geometry: facade)
            skin.position = vector(0, height / 2, 0.08)
            wall.addChildNode(skin)
            if entrance {
                let center = -0.13 * edge.length
                let lobby = SCNCylinder(radius: 10.5, height: 15.4)
                lobby.radialSegmentCount = 32
                let cladding = material(contents: xinyiLobbyCladding())
                cladding.diffuse.mipFilter = .linear
                lobby.firstMaterial = cladding
                let curve = SCNNode(geometry: lobby)
                curve.name = "xinyi-office-curved-lobby"
                curve.position = vector(center, 7.7, -2.4)
                curve.scale.z = 0.49
                wall.addChildNode(curve)
                box(25.8, 3.2, 5.3, rgb(0x3f4b4d), x: center - 3.4,
                    y: height + 1.60, z: -13.1, in: wall)
                let sign = SCNPlane(width: 7.6, height: 1.35)
                sign.firstMaterial = material(contents: signTexture(title: "信義大樓", subtitle: "XINYI BUILDING",
                                                                     color: rgb(0x434a49)))
                let plaque = SCNNode(geometry: sign)
                plaque.position = vector(center + 12.6, 3.25, 0.12)
                wall.addChildNode(plaque)
            }
            detail.addChildNode(wall)
        }
        root.addChildNode(detail)
        return true
    }

    private static func xinyiOfficeMaterial(columns: Int, entrance: Bool) -> SCNMaterial {
        let stone = material(contents: xinyiOfficeTexture(columns: columns, entrance: entrance, night: false))
        stone.name = "city-lit-facade"
        stone.emission.contents = xinyiOfficeTexture(columns: columns, entrance: entrance, night: true)
        stone.emission.intensity = 0
        for property in [stone.diffuse, stone.emission] { property.mipFilter = .linear }
        return stone
    }

    private static func xinyiOfficeTexture(columns: Int, entrance: Bool, night: Bool) -> UIImage {
        let size = CGSize(width: columns == 15 ? 512 : 160, height: 256)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            let g = output.cgContext
            func paint(_ rect: CGRect, _ tint: Int) {
                g.setFillColor(rgb(tint).cgColor)
                g.fill(rect)
            }
            let width = size.width
            paint(CGRect(origin: .zero, size: size), night ? 0 : 0xa7826f)
            if !night {
                for y in stride(from: 8, to: 256, by: 8) {
                    paint(CGRect(x: 0, y: CGFloat(y), width: width, height: 0.62), 0x977462)
                }
                for x in stride(from: 6, to: Int(width), by: 9) {
                    paint(CGRect(x: CGFloat(x), y: 0, width: 0.56, height: 256), 0x9c7967)
                }
                if entrance {
                    paint(CGRect(x: width * 0.22, y: 121, width: width * 0.29, height: 135), 0x263336)
                }
            }
            let margin = width * (columns == 15 ? 0.071 : 0.11)
            let bay = (width - margin * 2) / CGFloat(columns)
            for floor in 0..<10 {
                for column in 0..<columns {
                    let x = margin + CGFloat(column) * bay
                    let y = 21 + CGFloat(floor) * 23.5
                    let lobbyBay = entrance && floor >= 5 && (3...7).contains(column)
                    let upperRecess = entrance && floor < 2 && (10...13).contains(column)
                    if upperRecess && (floor != 0 || !column.isMultiple(of: 2)) { continue }
                    let window = CGRect(x: x + bay * (lobbyBay ? 0.03 : 0.11), y: y,
                                        width: bay * (upperRecess ? 1.78 : lobbyBay ? 0.94 : 0.78),
                                        height: upperRecess ? 40 : lobbyBay ? 21.5 : 16.5)
                    let seed = Int(facadeNoise(seed: 39, column: column, row: floor) % 100)
                    if !night {
                        paint(window, lobbyBay ? 0x34464b : 0x353a39)
                        let glass = window.insetBy(dx: 2.5, dy: 2.5)
                        let glazing = upperRecess ? 0x3c5056 : [0x60777b, 0x53686e, 0x698083, 0x43565b][seed % 4]
                        paint(glass, glazing)
                        paint(CGRect(x: glass.midX, y: glass.minY, width: 1, height: glass.height), 0x394749)
                        paint(CGRect(x: window.minX, y: window.maxY - 1, width: window.width, height: 1), 0xc09c85)
                    } else if upperRecess {
                        // Only the interior edge catches light. Keep most of
                        // the double-height glass dark at street scale.
                        paint(CGRect(x: window.minX + 6, y: window.maxY - 9,
                                     width: window.width * 0.27, height: 3.5), 0x745f3e)
                    } else if seed < (lobbyBay ? 43 : 28) {
                        let pane = window.insetBy(dx: 3.5, dy: 3.5)
                        paint(pane, seed % 3 == 0 ? 0xa58755 : 0x745f3e)
                        paint(CGRect(x: pane.midX, y: pane.minY, width: 1, height: pane.height), 0)
                    }
                }
            }
        }
    }

    private static func xinyiLobbyCladding() -> UIImage {
        let size = CGSize(width: 192, height: 96)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            for column in 0..<24 {
                for row in 0..<8 {
                    let shade = Int(facadeNoise(seed: 27, column: column, row: row) % 18)
                    rgb(0x9daeb2 + shade * 0x010101).setFill()
                    output.fill(CGRect(x: column * 8, y: row * 12, width: 8, height: 12))
                    rgb(0x87999c).setFill()
                    output.fill(CGRect(x: column * 8, y: row * 12, width: 1, height: 12))
                    output.fill(CGRect(x: column * 8, y: row * 12, width: 8, height: 1))
                }
            }
        }
    }

    static func addATT4Fun(footprint: [CGPoint], outline: UIBezierPath, height: CGFloat, in root: SCNNode) -> Bool {
        let ring = footprint.first == footprint.last ? Array(footprint.dropLast()) : footprint
        guard ring.count > 3, height >= 30 else { return false }
        let bounds = outline.bounds
        guard bounds.width >= 40, bounds.height >= 65 else { return false }
        let roof = bounds.insetBy(dx: bounds.width * 0.17, dy: bounds.height * 0.16)
        let corners = [CGPoint(x: roof.minX, y: roof.minY), CGPoint(x: roof.minX, y: roof.maxY),
                       CGPoint(x: roof.maxX, y: roof.minY), CGPoint(x: roof.maxX, y: roof.maxY)]
        guard corners.allSatisfy(outline.contains) else { return false }

        let group = SCNNode()
        group.name = "surface-way/\(CitySceneData.att4FunWayID)"
        let bodyHeight = height * 0.83
        let base = SCNShape(path: outline, extrusionDepth: bodyHeight)
        let roofSurface = material(contents: rgb(0x777b77))
        if let tile = CityRoofDetails.surfaceTexture(tint: 0x777b77, residential: false) {
            roofSurface.diffuse.contents = tile
            roofSurface.diffuse.wrapS = .repeat
            roofSurface.diffuse.wrapT = .repeat
            roofSurface.diffuse.mipFilter = .linear
            roofSurface.diffuse.contentsTransform = SCNMatrix4MakeScale(4.0, 6.0, 1)
        }
        base.materials = [roofSurface, material(contents: rgb(0x565b5d)), material(contents: rgb(0x4f5759))]
        let mass = SCNNode(geometry: base)
        mass.eulerAngles.x = -.pi / 2
        mass.position = vector(0, bodyHeight / 2, 0)
        group.addChildNode(mass)

        let screen = attFacadeMaterial(.screen)
        let glazed = attFacadeMaterial(.glazing)
        let compact = attFacadeMaterial(.compact)
        let pavilionGlass = attFacadeMaterial(.pavilion)
        let bronze = rgb(0x62504a)
        let dark = rgb(0x434e52)
        let eaveGlow = material(contents: bronze)
        eaveGlow.name = "city-lit-facade"
        eaveGlow.emission.contents = rgb(0x74506a)
        eaveGlow.emission.intensity = 0
        let lettering = signTexture(title: "ATT 4 FUN", subtitle: "XINYI", color: dark)
        let signSurface = material(contents: lettering)
        signSurface.name = "city-lit-facade"
        signSurface.emission.contents = lettering
        signSurface.emission.intensity = 0
        for edge in wallEdges(in: ring) {
            let wall = SCNNode()
            wall.position = vector(edge.x, 0, edge.z)
            wall.eulerAngles.y = Float(edge.angle)
            let isBroad = edge.length >= 29
            let facesSongshou = cos(edge.angle) < -0.85
            if edge.length >= 7 {
                let facade = SCNPlane(width: edge.length - 0.03, height: bodyHeight - 0.02)
                facade.firstMaterial = isBroad ? (facesSongshou ? screen : glazed) : compact
                let skin = SCNNode(geometry: facade)
                skin.position = vector(0, bodyHeight / 2, 0.095)
                wall.addChildNode(skin)
            }
            if isBroad || (edge.length > 15 && cos(edge.angle) > 0.9) {
                let entranceWidth = min(16, edge.length * 0.34)
                if isBroad {
                    box(entranceWidth + 2, 0.38, 2.30, bronze, x: 0, y: 4.50, z: 0.85, in: wall)
                }
                let sign = SCNPlane(width: entranceWidth, height: 2.75)
                sign.firstMaterial = signSurface
                let board = SCNNode(geometry: sign)
                board.name = "att4fun-entrance-sign"
                board.position = vector(0, isBroad ? 6.18 : 12.2, 0.14)
                wall.addChildNode(board)
            }
            box(edge.length, 0.62, 1.02, bronze, x: 0, y: bodyHeight - 0.23, z: 0.07, in: wall)
            if edge.length > 7 {
                let strip = SCNPlane(width: edge.length - 0.10, height: 0.13)
                strip.firstMaterial = eaveGlow
                let line = SCNNode(geometry: strip)
                line.position = vector(0, bodyHeight - 0.44, 0.59)
                wall.addChildNode(line)
            }
            group.addChildNode(wall)
        }

        let crownHeight = height - bodyHeight
        let crown = SCNBox(width: roof.width - 1.1, height: crownHeight - 0.30,
                           length: roof.height - 1.1, chamferRadius: 0)
        crown.materials = [pavilionGlass, pavilionGlass, pavilionGlass, pavilionGlass,
                           material(contents: dark), material(contents: dark)]
        let pavilion = SCNNode(geometry: crown)
        pavilion.position = vector(roof.midX, bodyHeight + (crownHeight - 0.30) / 2, -roof.midY)
        group.addChildNode(pavilion)
        let rim = SCNBox(width: roof.width, height: 0.30, length: roof.height, chamferRadius: 0)
        let rimLight = material(contents: bronze)
        rimLight.name = "city-lit-facade"
        rimLight.emission.contents = rgb(0x498a80)
        rimLight.emission.intensity = 0
        rim.materials = [rimLight, rimLight, rimLight, rimLight, roofSurface, material(contents: dark)]
        let crownRoof = SCNNode(geometry: rim)
        crownRoof.name = "att4fun-terrace-roof"
        crownRoof.position = vector(roof.midX, height - 0.15, -roof.midY)
        group.addChildNode(crownRoof)
        root.addChildNode(group)
        return true
    }

    private enum ATTFacade { case screen, glazing, compact, pavilion }

    private static func attFacadeMaterial(_ style: ATTFacade) -> SCNMaterial {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: 384, height: 256)
        let rows = style == .pavilion ? 2 : 10
        let columns = style == .compact ? 5 : 16
        let bay = size.width / CGFloat(columns), floorHeight = 230 / CGFloat(rows)
        func texture(night: Bool) -> UIImage {
            UIGraphicsImageRenderer(size: size, format: format).image { output in
                func paint(_ rect: CGRect, _ tint: Int) {
                    rgb(tint).setFill(); output.fill(rect)
                }
                paint(CGRect(origin: .zero, size: size), night ? 0 : 0x677779)
                for floor in 0..<rows {
                    for column in 0..<columns {
                        let x = CGFloat(column) * bay, y = CGFloat(floor) * floorHeight + 9
                        let seed = Int(facadeNoise(seed: 183, column: column, row: floor) % 100)
                        let panel = CGRect(x: x + 0.75, y: y + 0.8, width: bay - 1.5, height: floorHeight - 1.6)
                        let lower = floor >= rows - 2 && style != .pavilion
                        if !night {
                            paint(panel, [0x45575a, 0x506265, 0x415254, 0x4c5e62][seed % 4])
                            if lower {
                                paint(panel.insetBy(dx: 3, dy: 3), [0x847a64, 0x536261, 0x696a5c][seed % 3])
                            }
                        } else if lower || (style == .pavilion ? seed < 36 : floor.isMultiple(of: 3) && seed < 24) {
                            paint(panel.insetBy(dx: 4, dy: 3), [0xa4895d, 0x876f50, 0x6a5d4b][seed % 3])
                        }
                    }
                }
                if style == .screen {
                    let display = CGRect(x: 22, y: 44, width: 270, height: 125)
                    paint(display, night ? 0x6c7973 : 0xd3d3c7)
                    paint(CGRect(x: 22, y: 44, width: 270, height: 16), night ? 0x5e7771 : 0xa7b6aa)
                    paint(CGRect(x: 22, y: 147, width: 270, height: 22), night ? 0x496d65 : 0x809f94)
                    paint(CGRect(x: 45, y: 74, width: 9, height: 52), night ? 0x7c573e : 0xb56a49)
                    paint(CGRect(x: 59, y: 74, width: 5, height: 52), night ? 0x665748 : 0xc49a73)
                    if !night {
                        ("ATT 4 FUN" as NSString).draw(at: CGPoint(x: 79, y: 82), withAttributes: [
                            .font: UIFont.systemFont(ofSize: 34, weight: .heavy), .foregroundColor: rgb(0x475654)
                        ])
                    }
                }
                if style != .pavilion {
                    paint(CGRect(x: 0, y: 193, width: 384, height: 3), night ? 0x6d5045 : 0x90766b)
                }
            }
        }
        let surface = material(contents: texture(night: false))
        surface.name = "city-lit-facade"
        surface.emission.contents = texture(night: true)
        surface.emission.intensity = 0
        for property in [surface.diffuse, surface.emission] { property.mipFilter = .linear }
        return surface
    }

    private static var facadeTiles: [String: (UIImage, UIImage)] = [:]
    private static let facadeLightCells = 12
    static var facadeLightScale: Float { 2 / Float(facadeLightCells) }

    static func repeatedFacade(finish: Finish, variant: Int) -> (UIImage, UIImage) {
        let key = "\(finish)-\(variant)"
        if let cached = facadeTiles[key] { return cached }
        let tile = (facadeDayTile(finish: finish, seed: variant),
                    facadeLightTile(finish: finish, seed: variant))
        facadeTiles[key] = tile
        return tile
    }

    static func facadePhase(way: Int, edge: Int) -> CGPoint {
        // A whole diffuse tile is two windows. Moving by whole tiles leaves
        // the daytime facade fixed while selecting a different light cluster.
        let bits = facadeNoise(seed: way, column: edge, row: 0)
        let phases = UInt32(facadeLightCells / 2)
        return CGPoint(x: Int(bits % phases), y: Int((bits >> 8) % phases))
    }

    static func facadeNoise(seed: Int, column: Int, row: Int) -> UInt32 {
        var bits = UInt32(truncatingIfNeeded: seed) ^ (UInt32(column) &* 0x9e3779b9) ^ (UInt32(row) &* 0x85ebca6b)
        bits ^= bits >> 16
        bits &*= 0x7feb352d
        bits ^= bits >> 15
        bits &*= 0x846ca68b
        return bits ^ (bits >> 16)
    }

    private static let facadeCell: CGFloat = 26

    private struct FacadeBay {
        let opening: CGRect
        let panes: [CGRect]
    }

    // The daylight tile repeats every two bays. The bigger light tile uses
    // the same openings, then varies occupancy over twelve bays and floors.
    private static func facadeBay(finish: Finish, seed: Int, column: Int, row: Int) -> FacadeBay {
        let variant = (seed + (column % 2) * 3 + (row % 2) * 2) % 4
        let width: CGFloat
        let height: CGFloat
        let top: CGFloat
        switch finish {
        case .office: (width, height, top) = (21.5, 18.5, 2.5)
        case .retail: (width, height, top) = (19.5, 17, 4)
        case .civic: (width, height, top) = (12, 16, 4)
        case .transit: (width, height, top) = (10, 9, 6)
        case .brick, .stone, .plaster, .sage:
            width = [12.5, 16.5, 14, 18][variant]
            height = [12, 14, 13, 15][variant]
            top = 5
        }
        let opening = CGRect(x: CGFloat(column) * facadeCell + (facadeCell - width) / 2,
                             y: CGFloat(row) * facadeCell + top, width: width, height: height)
        let glass = opening.insetBy(dx: 0.8, dy: 0.8)
        if (finish.isHome && variant.isMultiple(of: 2)) || finish == .transit {
            return FacadeBay(opening: opening, panes: [glass])
        }
        let split = glass.minX + glass.width * (finish.isHome ? 0.43 : 0.5)
        let left = CGRect(x: glass.minX, y: glass.minY, width: split - glass.minX - 0.55, height: glass.height)
        let right = CGRect(x: split + 0.55, y: glass.minY, width: glass.maxX - split - 0.55, height: glass.height)
        return FacadeBay(opening: opening, panes: [left, right])
    }

    private static func facadeDayTile(finish: Finish, seed: Int) -> UIImage {
        let side = facadeCell * 2
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let g = context.cgContext
            func fill(_ color: UIColor, _ rect: CGRect) {
                g.setFillColor(color.cgColor)
                g.fill(rect)
            }
            fill(finish.wall, CGRect(x: 0, y: 0, width: side, height: side))
            for row in 0..<2 {
                let y = CGFloat(row) * facadeCell
                // Dark spandrels on glazing, shallow masonry bands on homes.
                let belt = finish == .office ? rgb(0x506268).withAlphaComponent(0.55)
                    : finish.trim.withAlphaComponent(0.40)
                fill(belt, CGRect(x: 0, y: y + 23, width: side, height: finish == .office ? 3 : 1.4))
                if finish == .brick {
                    for line in 1..<5 {
                        fill(rgb(0x855d50).withAlphaComponent(0.25),
                             CGRect(x: 0, y: y + CGFloat(line * 5), width: side, height: 0.75))
                    }
                }
                for column in 0..<2 {
                    let bay = facadeBay(finish: finish, seed: seed, column: column, row: row)
                    let opening = bay.opening
                    fill(rgb(0x334348), opening.offsetBy(dx: 0, dy: 0.65))
                    fill(finish.trim.withAlphaComponent(finish.isHome ? 0.76 : 0.38), opening)
                    for (index, pane) in bay.panes.enumerated() {
                        fill(finish.glazing, pane)
                        let light = facadeNoise(seed: seed + index * 47, column: column, row: row)
                        let reflection = light.isMultiple(of: 3) ? rgb(0xd4b690) : rgb(0xa8cad1)
                        fill(reflection.withAlphaComponent(0.14 + CGFloat(light % 5) * 0.045),
                             CGRect(x: pane.minX, y: pane.minY, width: pane.width,
                                    height: pane.height * (finish == .office ? 0.58 : 0.33)))
                    }
                    if finish.isHome {
                        fill(finish.trim,
                             CGRect(x: opening.minX - 1.1, y: opening.maxY + 0.6, width: opening.width + 2.2, height: 1.5))
                    }
                }
            }
        }
    }

    private static func facadeLightTile(finish: Finish, seed: Int) -> UIImage {
        let side = CGFloat(facadeLightCells) * facadeCell
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0.5
        format.opaque = true
        let occupancy = finish == .civic ? 16 : finish.isHome ? 33 : finish == .retail ? 36 : 26
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            for row in 0..<facadeLightCells {
                for column in 0..<facadeLightCells {
                    let room = facadeNoise(seed: seed + 41, column: column, row: row)
                    let cluster = facadeNoise(seed: seed + 163, column: column / 3, row: row / 2)
                    let threshold = occupancy + Int(cluster % 29) - 14
                    guard Int(room % 100) < threshold else { continue }
                    let tint = (room >> 8) % 5 == 0 ? rgb(0x92b8cc) : rgb(0xf2c88a)
                    let brightness = 0.42 + CGFloat((room >> 16) % 45) / 100
                    let panes = facadeBay(finish: finish, seed: seed, column: column, row: row).panes
                    let index = Int(room % UInt32(panes.count))
                    cg.setFillColor(tint.withAlphaComponent(brightness).cgColor)
                    cg.fill(panes[index].insetBy(dx: 0.45, dy: 0.45))
                    if panes.count == 2 && (room >> 24) % 3 == 0 {
                        cg.fill(panes[1 - index].insetBy(dx: 0.45, dy: 0.45))
                    }
                }
            }
        }
    }

    private static func facadeTexture(columns: Int, floors: Int, finish: Finish, seed: Int, illumination: Bool = false) -> UIImage {
        let cell: CGFloat = 26
        let width = CGFloat(columns) * cell, height = CGFloat(floors) * cell
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0.7
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            func fill(_ c: UIColor, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                cg.setFillColor(c.cgColor); cg.fill(CGRect(x: x, y: y, width: w, height: h))
            }
            if illumination {
                fill(.black, 0, 0, width, height)
                for row in 0..<floors {
                    for column in 0..<columns {
                        let variant = (row * 31 + column * 17 + seed) % 13
                        guard variant < 5 else { continue }
                        let gutter: CGFloat = finish == .office ? 1.5 : finish == .retail ? 2.5
                            : finish == .civic ? 3.5 : finish == .brick ? 5 : 6
                        let wy: CGFloat = finish == .office ? 2 : 4.5
                        let wh: CGFloat = row == floors - 1 ? 19.5 : (finish.isHome ? 13 : 18)
                        fill(variant < 3 ? rgb(0xf4cf8c) : rgb(0x8bb7c7),
                             CGFloat(column) * cell + gutter + 0.5, CGFloat(row) * cell + wy,
                             cell - gutter * 2 - 1, wh)
                    }
                }
                return
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

    static let cornerTreePositions = ([
        (-154, 129), (-138, 130), (-122, 130), (-82, 133), (-65, 134), (-47, 134), (-30, 135),
        (-76, 90), (-61, 91), (-46, 91), (-30, 92), (-13, 92), (4, 93),
        (66, 137), (80, 138), (109, 139), (127, 139), (145, 140), (165, 140), (183, 141),
        (119, 97), (132, 98), (146, 98), (165, 99), (181, 100),
        // Inside the plaza boundary; preserve the circular pedestrian paths.
        (117, 58), (119, 45), (120, 30), (122, 17), (155, 13), (178, 14), (198, 16),
    ] as [(CGFloat, CGFloat)]).map { CityCivicLandscape.TreePosition(x: $0.0, z: $0.1) }

    static let forecourtTreePositions = ([41, 50, 60, 70, 79] as [CGFloat]).map {
        CityCivicLandscape.TreePosition(x: $0, z: 83)
    }

    static func addCornerFixtures(to root: SCNNode) {
        decorate(way: 101, footprint: podium, height: 25, levels: 5, finish: .retail, in: root)
        addSign(title: "市府路", subtitle: "CITY HALL RD.", x: -83, z: 127, in: root)
        addSign(title: "松智路", subtitle: "SONGZHI RD.", x: 113, z: 135, in: root)
        addSign(title: "信義路五段", subtitle: "XINYI RD. SEC. 5", x: 83, z: 93, in: root)
        addSign(title: "捷運 101 · 5", subtitle: "MRT EXIT 5", x: -119, z: 86, in: root)
    }

    private static let streetFoliage = foliage([0x476c30, 0x608540, 0x7b9b43, 0x91ab4f, 0x527a39])
    private static let parkFoliage = foliage([0x587e36, 0x77a13f, 0x99b54b, 0xb2c85c, 0x628e3b])

    private static func foliage(_ colors: [Int]) -> [SCNSphere] {
        colors.map { color in
            let mesh = SCNSphere(radius: 1)
            mesh.segmentCount = 10
            mesh.firstMaterial = material(contents: rgb(color))
            return mesh
        }
    }

    static func addTree(_ tree: CityCivicLandscape.TreePosition, seed: Int, to root: SCNNode) {
        let x = tree.x, z = tree.z
        let scale = 0.76 + CGFloat((seed * 17) % 9) * 0.064
        let tall = seed % 5 == 0
        let y = (tall ? 7.2 : 5.4) * scale
        if !tree.inLawn {
            box(3.4, 0.20, 3.0, rgb(0xa99c7c), x: x, y: 0.94, z: z, in: root)
            box(2.7, 0.06, 2.35, rgb(0x686347), x: x, y: 1.05, z: z, in: root)
        }
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
        let palette = tree.inLawn ? parkFoliage : streetFoliage
        let spread: CGFloat = (tall ? 0.83 : 1.17) * (tree.inLawn ? 1.12 : 1)
        for (index, c) in clusters.enumerated() {
            let leaf = SCNNode(geometry: palette[(seed * 3 + index) % palette.count])
            let r = c.3 * scale
            leaf.position = vector(x + c.0 * scale * spread, y + c.1 * scale, z + c.2 * scale * spread)
            leaf.scale = vector(r * spread, r * (tall ? 1.28 : 0.89), r * 0.92)
            leaf.eulerAngles.y = Float(seed % 7) * 0.55
            root.addChildNode(leaf)
        }
    }

    nonisolated struct ShadowInput: Sendable {
        let casters: [Caster]
        let trees: [CityCivicLandscape.TreePosition]
        let offset: CGPoint
        let landmarkBands: [[SIMD3<Float>]]
    }

    nonisolated private static let shadowBounds = CGRect(x: -550, y: -695, width: 1_100, height: 1_050)

    @concurrent nonisolated static func prepareCornerShadows(_ input: ShadowInput) async throws -> CGImage? {
        try Task.checkCancellation()
        let image = rasterizeCornerShadows(input)
        try Task.checkCancellation()
        return image
    }

    nonisolated static func rasterizeCornerShadows(_ input: ShadowInput) -> CGImage? {
        let bounds = shadowBounds
        let offset = input.offset
        let size = CGSize(width: bounds.width * 2, height: bounds.height * 2)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        func pixel(_ x: CGFloat, _ z: CGFloat) -> CGPoint {
            CGPoint(x: (x - bounds.minX) * 2, y: (z - bounds.minY) * 2)
        }
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let shade = rgb(0x282d4a)
            let buildings = CGMutablePath()
            func append(_ polygon: [CGPoint]) {
                guard let first = polygon.first, let last = polygon.last else { return }
                let area = zip(polygon, polygon.dropFirst()).reduce(last.x * first.y - first.x * last.y) {
                    $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y
                }
                guard abs(area) > 0.001 else { return }
                // Match winding before union fill so overlaps keep one shadow density.
                buildings.addLines(between: area > 0 ? polygon : Array(polygon.reversed()))
                buildings.closeSubpath()
            }
            for caster in input.casters + [Caster(footprint: podium, height: 25)] {
                let base = caster.footprint.map { pixel($0.x, -$0.y) }
                guard let first = base.first else { continue }
                let dx = offset.x * caster.height * 2, dz = offset.y * caster.height * 2
                append(base)
                // Sweeping the actual walls preserves recesses in concave buildings.
                for (a, b) in zip(base, base.dropFirst() + [first]) {
                    append([a, b, CGPoint(x: b.x + dx, y: b.y + dz), CGPoint(x: a.x + dx, y: a.y + dz)])
                }
            }
            for band in input.landmarkBands {
                append(hull(band.map { vertex in
                    pixel(CGFloat(vertex.x) + CGFloat(vertex.y) * offset.x,
                          CGFloat(vertex.z) + CGFloat(vertex.y) * offset.y)
                }))
            }
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 7, color: shade.withAlphaComponent(0.25).cgColor)
            cg.setFillColor(shade.withAlphaComponent(0.43).cgColor)
            cg.addPath(buildings); cg.fillPath()
            cg.restoreGState()
            for (i, tree) in input.trees.enumerated() {
                let p = pixel(tree.x + 5.8 * offset.x, tree.z + 5.8 * offset.y)
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 6, color: shade.withAlphaComponent(0.27).cgColor)
                cg.setFillColor(shade.withAlphaComponent(0.30).cgColor)
                let r = CGFloat(7 + i % 4 + (tree.inLawn ? 1 : 0))
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
            CityStreetSurface.fadeNorthernCoverage(cg, scale: 2, offset: -bounds.minY * 2)
        }.cgImage
    }

    static func addCornerShadows(_ bitmap: CGImage?, to root: SCNNode) {
        guard let bitmap else { return }
        let bounds = shadowBounds
        let plane = SCNPlane(width: bounds.width, height: bounds.height)
        let surface = material(contents: UIImage(cgImage: bitmap))
        surface.lightingModel = .constant
        surface.writesToDepthBuffer = false
        plane.firstMaterial = surface
        let node = SCNNode(geometry: plane)
        node.name = "xinyi-ground-shadows"
        node.position = vector(bounds.midX, 0.94, bounds.midY)
        node.eulerAngles.x = -.pi / 2
        node.renderingOrder = 3
        root.addChildNode(node)
    }

    nonisolated private static func hull(_ input: [CGPoint]) -> [CGPoint] {
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

    nonisolated private static func rgb(_ hex: Int) -> UIColor {
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
