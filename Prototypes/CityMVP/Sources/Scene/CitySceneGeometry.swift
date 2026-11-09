import UIKit
import SceneKit

/// Procedural illustration aligned to the bundled OpenStreetMap footprints.
@MainActor
enum CitySceneGeometry {
    static func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let root = scene.rootNode
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.name = "city-ambient"
        ambient.light?.intensity = 400; root.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional
        sun.name = "city-key-light"
        sun.light?.intensity = 700
        // Keep mobile fill cost bounded. Geometry/shading remain from the accepted demo.
        sun.position = SCNVector3(-700, 1200, 500); sun.look(at: SCNVector3(0, 0, 0)); root.addChildNode(sun)
        let ground = cityBox(1400, 8, 1400, UIColor(red: 0.89, green: 0.86, blue: 0.80, alpha: 1))
        ground.position.y = -5; root.addChildNode(ground)
        let casters = loadOSM(into: root)
        add101(to: root)
        CityStreetDetail.addCorners(to: root, casters: casters)
        let roads = CityStreetSurface.roads()
        CityStreetSurface.add(to: root, roads: roads)
        CityStreetTraffic.add(to: root, roads: roads)
        return scene
    }
    static func applyLighting(to scene: SCNScene, night: Bool, animated: Bool) {
        let root = scene.rootNode
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.4 : 0
        let ambient = root.childNode(withName: "city-ambient", recursively: false)?.light
        ambient?.intensity = night ? 330 : 400
        ambient?.color = night ? UIColor(red: 0.53, green: 0.66, blue: 0.92, alpha: 1) : UIColor.white
        let key = root.childNode(withName: "city-key-light", recursively: false)?.light
        key?.intensity = night ? 225 : 700
        key?.color = night ? UIColor(red: 0.56, green: 0.71, blue: 1, alpha: 1) : UIColor.white
        root.childNode(withName: "xinyi-ground-shadows", recursively: false)?.opacity = night ? 0.35 : 1
        for node in root.childNodes where node.name == "city-window" {
            node.geometry?.firstMaterial?.emission.contents = night
                ? UIColor(red: 0.72, green: 0.51, blue: 0.24, alpha: 1) : UIColor.black
        }
        SCNTransaction.commit()
    }

}

private func cityVector(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 {
    SCNVector3(Float(x), Float(y), Float(z))
}

private func cityMaterial(_ color: UIColor) -> SCNMaterial {
    let m = SCNMaterial(); m.diffuse.contents = color; m.roughness.contents = 0.85
    m.lightingModel = .blinn; return m
}
private func cityBox(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ color: UIColor) -> SCNNode {
    let g = SCNBox(width: w, height: h, length: d, chamferRadius: min(1.4,h/10))
    g.materials = [cityMaterial(color)]; return SCNNode(geometry:g)
}
private func xy(_ p: [String:Any]) -> CGPoint {
    CGPoint(x: ((p["lon"] as? Double ?? 121.564468)-121.564468)*100850,
            y: ((p["lat"] as? Double ?? 25.033968)-25.033968)*111195)
}
private func loadOSM(into root: SCNNode) -> [CityStreetDetail.Caster] {
    guard let elements = CitySceneData.elements else { return [] }
    var casters: [CityStreetDetail.Caster] = []
    for item in elements {
        guard let tags = item["tags"] as? [String:String], let geometry = item["geometry"] as? [[String:Any]], geometry.count > 1 else { continue }
        let points = geometry.map(xy)
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { continue }
        guard points.contains(where: { abs($0.x)<650 && abs($0.y)<650 }) else { continue }
        if tags["building"] != nil || tags["leisure"] == "park" {
            guard points.count > 3 else { continue }
            let isPark = tags["leisure"] == "park"
            let path = UIBezierPath(); path.move(to:points[0]); points.dropFirst().forEach { path.addLine(to:$0) }; path.close()
            // Omit the 101 footprint; the separately modeled landmark occupies its real coordinate.
            if !isPark && path.contains(.zero) { continue }
            let id = item["id"] as? Int ?? 0
            let finish = isPark ? nil : CityStreetDetail.finish(for: id)
            let levels = tags["building:levels"].flatMap(Int.init)
            let fallback = (Double(tags["building:levels"] ?? "") ?? 5) * 3.2
            let height = isPark ? 0.8 : min(260, max(finish == nil ? 8 : 4,
                Double(tags["height"]?.replacingOccurrences(of: " m", with: "") ?? "") ?? fallback))
            let shape = SCNShape(path:path,extrusionDepth:height)
            let colors: [UIColor] = [.init(red:0.76,green:0.80,blue:0.85,alpha:1),.init(red:0.89,green:0.81,blue:0.74,alpha:1),.init(red:0.73,green:0.77,blue:0.83,alpha:1)]
            shape.materials = [cityMaterial(isPark ? .init(red:0.48,green:0.64,blue:0.45,alpha:1) : (finish?.wall ?? colors[abs(id)%3]))]
            let node = SCNNode(geometry:shape); node.eulerAngles.x = -.pi/2
            node.name = "surface-way/\(id)"
            node.position.y = isPark ? 0 : Float(height/2)
            root.addChildNode(node)
            if let finish {
                CityStreetDetail.decorate(way: id, footprint: points, height: height, levels: levels, finish: finish, in: root)
                casters.append(.init(footprint: points, height: height))
            }
        } else if let highway = tags["highway"] {
            let width: CGFloat = ["primary","secondary","trunk"].contains(highway) ? 13 : ["tertiary","residential"].contains(highway) ? 8 : 4
            for (a,b) in zip(points,points.dropFirst()) {
                let dx = b.x-a.x, dz = -(b.y-a.y), length = hypot(dx,dz)
                guard length > 0.1, abs(a.x)<700, abs(a.y)<700, abs(b.x)<700, abs(b.y)<700 else { continue }
                let n = cityBox(width,0.6,length,width >= 8 ? .init(red:0.50,green:0.53,blue:0.58,alpha:1) : .init(red:0.95,green:0.93,blue:0.88,alpha:1))
                n.position = cityVector((a.x+b.x)/2,0.5,-(a.y+b.y)/2)
                n.eulerAngles.y = Float(atan2(dx,dz)); root.addChildNode(n)
            }
        }
    }
    return casters
}
private func add101(to root: SCNNode) {
    let green = UIColor(red:0.19,green:0.47,blue:0.43,alpha:1)
    let pale = UIColor(red:0.49,green:0.70,blue:0.61,alpha:1)
    let podium = cityBox(125,25,95,.init(red:0.71,green:0.72,blue:0.64,alpha:1)); podium.position.y = 12.5; root.addChildNode(podium)
    let base = cityBox(65,65,65,green); base.position.y = 57.5; root.addChildNode(base)
    for i in 0..<8 {
        let bottom = CGFloat(90+i*42), top = bottom+38
        // Four-sided tapered volumes evoke the stacked bamboo silhouette, not a surveyed mesh.
        let cone = SCNCone(topRadius:40,bottomRadius:31,height:38); cone.radialSegmentCount = 4
        cone.materials = [cityMaterial(green)]
        let node = SCNNode(geometry:cone); node.position.y = Float(bottom+19); node.eulerAngles.y = .pi/4; root.addChildNode(node)
        let rim = cityBox(58,3,58,pale); rim.position.y = Float(top); root.addChildNode(rim)
        for j in 1..<6 {
            let strip = cityBox(54,0.7,54,pale)
            strip.name = "city-window"
            strip.position.y = Float(bottom+CGFloat(j)*6); root.addChildNode(strip)
        }
    }
    let cap = cityBox(27,42,27,green); cap.position.y = 447; root.addChildNode(cap)
    let spire = SCNCylinder(radius:2.3,height:40); spire.materials=[cityMaterial(pale)]
    let tip = SCNNode(geometry:spire); tip.position.y = 488; tip.name = "surface-landmark-101"; root.addChildNode(tip)
}
