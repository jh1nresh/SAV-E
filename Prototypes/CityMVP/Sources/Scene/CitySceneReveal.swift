#if SAVVY_CITY_MVP
import SceneKit
import SpriteKit

/// Experimental solid-surface handoff. One coverage field drives geometry and
/// cloud masses; neither changes the projected pin position.
@MainActor
final class CitySceneReveal {
    enum Mode: Equatable { case cloudCut, materialTone }
    /// Preparation may finish before appearance. Reach zero continuously at
    /// the existing projection cutoff; keep the entire near district solid.
    static func arrivalOpacity(distance: Double) -> CGFloat {
        guard distance.isFinite, distance > 0 else { return 0 }
        let progress = min(1, max(0, (5_200 - distance) / 400))
        return CGFloat(progress * progress * (3 - 2 * progress))
    }
    private let mode: Mode
    struct Field {
        let uniform: SIMD4<Float>
        let aspect: Float
        let phase: Double

        init(phase: Double, center: CGPoint, viewport: CGSize) {
            let width = max(1, viewport.width), height = max(1, viewport.height)
            let progress = min(1, max(0, phase.isFinite ? phase : 0))
            uniform = SIMD4(Float(center.x / width), Float(center.y / height),
                            Float(progress), 0.08)
            aspect = Float(width / height)
            self.phase = progress
        }
    }

    private var materials: [SCNMaterial] = []
    let cloud = SKSpriteNode(color: .white, size: .zero)
    private let fieldUniform = SKUniform(name: "u_reveal", vectorFloat4: .zero)
    private let aspectUniform = SKUniform(name: "u_aspect", float: 1)
    private let nightUniform = SKUniform(name: "u_night", float: 0)

    init(mode: Mode = .cloudCut) {
        self.mode = mode
        cloud.name = "city-solid-reveal-cloud"
        cloud.anchorPoint = .zero
        cloud.zPosition = -10
        cloud.shader = SKShader(source: Self.cloudShader,
                                uniforms: [fieldUniform, aspectUniform, nightUniform])
    }

    /// Called once after geometry installation; sharing a material must not
    /// append the modifier twice. Existing fragment/lighting behavior is kept.
    func install(in root: SCNNode, excluding excluded: SCNNode?) {
        materials.removeAll()
        var copies: [ObjectIdentifier: SCNMaterial] = [:]
        var geometries: [ObjectIdentifier: SCNGeometry] = [:]
        root.enumerateChildNodes { node, _ in
            guard node !== excluded, let original = node.geometry else { return }
            let geometryID = ObjectIdentifier(original)
            if let existing = geometries[geometryID] {
                node.geometry = existing
                return
            }
            // Several scene builders cache materials. Isolate this candidate
            // while retaining material sharing and the original texture objects.
            let geometry = original.copy() as! SCNGeometry
            geometry.materials = original.materials.map { source in
                if let existing = copies[ObjectIdentifier(source)] { return existing }
                let material = source.copy() as! SCNMaterial
                var modifiers = material.shaderModifiers ?? [:]
                let prior = modifiers[.surface] ?? ""
                let declaration = "\n#pragma arguments\nfloat4 cityReveal;\n#pragma declaration\n"
                    + Self.fieldFunctions.replacingOccurrences(of: "CITY_VEC2", with: "float2")
                    + "\n#pragma body\n"
                if let body = prior.range(of: "#pragma body") {
                    // Establish the original texture first; applying its body
                    // afterward would overwrite the reveal's albedo tone.
                    modifiers[.surface] = String(prior[..<body.lowerBound]) + declaration
                        + String(prior[body.upperBound...]) + "\n" + Self.geometryBody
                } else {
                    modifiers[.surface] = declaration + prior + "\n" + Self.geometryBody
                }
                material.shaderModifiers = modifiers
                materials.append(material)
                copies[ObjectIdentifier(source)] = material
                return material
            }
            geometries[geometryID] = geometry
            node.geometry = geometry
        }
    }

    func update(_ field: Field, viewport: CGSize, night: Bool) {
        var v = field.uniform
        if mode == .materialTone { v.w = -1 }
        let value = NSValue(scnVector4: SCNVector4(v.x, v.y, v.z, v.w))
        for material in materials { material.setValue(value, forKey: "cityReveal") }
        cloud.size = viewport
        cloud.position = .zero
        cloud.isHidden = field.phase <= 0 || field.phase >= 1
        fieldUniform.vectorFloat4Value = v
        aspectUniform.floatValue = field.aspect
        nightUniform.floatValue = night ? 1 : 0
    }

    // One function body for Metal and SpriteKit's GLSL dialect. Noise is fixed
    // relative to the reveal center, with no time input or changing random seed.
    // The convex weights keep coverage in [0.15, 0.85], leaving safe endpoint
    // intervals for clouds to enter before any cut and exit after all cuts.
    private static let fieldFunctions = """
    float cityHash(CITY_VEC2 p) {
        p = fract(p * CITY_VEC2(123.34, 345.45));
        p += dot(p, p + 34.345);
        return fract(p.x * p.y);
    }
    float cityNoise(CITY_VEC2 p) {
        CITY_VEC2 cell = floor(p);
        CITY_VEC2 f = fract(p);
        CITY_VEC2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(cityHash(cell), cityHash(cell + CITY_VEC2(1.0, 0.0)), u.x),
                   mix(cityHash(cell + CITY_VEC2(0.0, 1.0)), cityHash(cell + CITY_VEC2(1.0, 1.0)), u.x), u.y);
    }
    float cityCoverage(CITY_VEC2 relative) {
        float noise = 0.60 * cityNoise(relative * 5.5)
                    + 0.28 * cityNoise(relative * 11.1 + CITY_VEC2(7.0, 11.0))
                    + 0.12 * cityNoise(relative * 22.3 + CITY_VEC2(2.0, 3.0));
        float reach = clamp(length(relative), 0.0, 1.0);
        float banks = noise * smoothstep(0.0, 0.35, reach);
        return 0.15 + 0.70 * (0.55 * reach + 0.45 * banks);
    }
    """

    // _surface.position is in view space. Convert to normalized top-left
    // viewport coordinates using the public SceneKit projection uniform.
    private static let geometryBody = """
    float4 cityClip = scn_frame.projectionTransform * float4(_surface.position, 1.0);
    float2 cityUV = float2(cityClip.x / cityClip.w * 0.5 + 0.5,
                          0.5 - cityClip.y / cityClip.w * 0.5);
    float cityAspect = scn_frame.inverseResolution.y / scn_frame.inverseResolution.x;
    float2 cityP = float2(cityUV.x * cityAspect, cityUV.y);
    float2 cityC = float2(cityReveal.x * cityAspect, cityReveal.y);
    if (cityReveal.w < 0.0) {
        float4 cityWorld = scn_frame.inverseViewTransform * float4(_surface.position, 1.0);
        float cityHeight = cityWorld.y / cityWorld.w;
        float cityAmount = (1.0 - cityReveal.z) * smoothstep(1.5, 4.0, cityHeight);
        float cityLuma = dot(_surface.diffuse.rgb, float3(0.2126, 0.7152, 0.0722));
        float3 cityNeutral = mix(float3(0.70, 0.73, 0.76), float3(cityLuma), 0.18);
        _surface.diffuse.rgb = mix(_surface.diffuse.rgb, cityNeutral, cityAmount);
    } else {
        float cityEdge = cityCoverage(cityP - cityC) - cityReveal.z;
        if (cityEdge > 0.0) { discard_fragment(); }
    }
    """

    // SpriteKit's texture y-axis points up. This uses the same normalized
    // field as SceneKit. Broad coverage on the unrevealed side replaces the
    // closed white outline; every actual cut remains covered at full opacity.
    private static let cloudShader = fieldFunctions.replacingOccurrences(of: "CITY_VEC2", with: "vec2") + """
    void main() {
        vec2 uv = vec2(v_tex_coord.x, 1.0 - v_tex_coord.y);
        vec2 p = vec2(uv.x * u_aspect, uv.y);
        vec2 c = vec2(u_reveal.x * u_aspect, u_reveal.y);
        vec2 relative = p - c;
        float alpha;
        if (u_reveal.w < 0.0) {
            float weather = 0.65 * cityNoise(relative * 3.0)
                          + 0.35 * cityNoise(relative * 7.0 + vec2(4.0, 9.0));
            float wisps = smoothstep(0.42, 0.72, weather);
            alpha = 0.18 * smoothstep(0.0, 0.12, u_reveal.z) * (1.0 - u_reveal.z) * wisps;
        } else {
            float edge = cityCoverage(relative) - u_reveal.z;
            float approach = smoothstep(0.0, 0.15, u_reveal.z);
            float clear = 1.0 - smoothstep(0.85, 1.0, u_reveal.z);
            alpha = smoothstep(-u_reveal.w * 0.5, 0.0, edge)
                  * (1.0 - smoothstep(0.12, 0.42, edge)) * approach * clear;
        }
        float light = cityNoise(relative * 14.0 + vec2(9.0, 17.0));
        vec3 day = mix(vec3(0.84, 0.89, 0.95), vec3(1.0, 1.0, 1.0), light);
        vec3 night = mix(vec3(0.20, 0.25, 0.36), vec3(0.42, 0.48, 0.62), light);
        vec3 color = mix(day, night, u_night);
        gl_FragColor = vec4(color * alpha, alpha);
    }
    """
}
#endif
