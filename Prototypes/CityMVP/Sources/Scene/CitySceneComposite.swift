#if SAVVY_CITY_MVP
import SceneKit
import Metal

/// Render into linear float color first, then associate display-encoded RGB
/// with alpha for Core Animation's transparent source-over composition.
/// Opaque scene pixels retain their original linear color.
enum CitySceneComposite {
    static func makeTechnique() -> SCNTechnique? {
        guard let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary(),
              library.makeFunction(name: "cityCompositeVertex") != nil,
              library.makeFunction(name: "cityCompositeFragment") != nil else { return nil }
        return SCNTechnique(dictionary: [
            "sequence": ["linearScene", "displayAlpha"],
            "metalLibraryName": "default",
            "targets": ["linearColor": ["type": "color", "format": "rgba16f"]],
            "passes": [
                "linearScene": [
                    "draw": "DRAW_SCENE", "outputs": ["color": "linearColor"],
                    "colorStates": ["clear": true, "clearColor": "sceneBackground"],
                ],
                "displayAlpha": [
                    "draw": "DRAW_QUAD", "inputs": ["linearColor": "linearColor"],
                    "outputs": ["color": "COLOR"],
                    "metalVertexShader": "cityCompositeVertex",
                    "metalFragmentShader": "cityCompositeFragment",
                    "blendStates": ["enable": false],
                ],
            ],
        ])
    }
}
#endif
