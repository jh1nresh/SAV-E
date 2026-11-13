#if SAVVY_CITY_MVP
import SceneKit
import UIKit

/// Four independently mipmapped textures, selected by a constant UV1 per wall.
/// Keep these properties visible to resource accounting; this is not an atlas.
@MainActor
enum CityRetailFacadeMaterial {
    static let texturePropertyNames = (0..<4).flatMap { ["cityRetailDay\($0)", "cityRetailNight\($0)"] }

    static func textureProperties(in material: SCNMaterial) -> [SCNMaterialProperty] {
        guard material.shaderModifiers?[.surface]?.contains("texture2d<float> cityRetailDay0;") == true else { return [] }
        return texturePropertyNames.compactMap { material.value(forKey: $0) as? SCNMaterialProperty }
    }

    static func make() -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "city-lit-facade"
        material.lightingModel = .lambert
        material.diffuse.contents = UIColor.white
        material.emission.contents = UIColor.white
        material.emission.intensity = 0
        let scale = CityStreetDetail.facadeLightScale
        material.emission.contentsTransform = SCNMatrix4MakeScale(scale, scale, 1)
        // A real texture is required for SceneKit to publish UV1. Reuse an
        // existing opaque image and read only its alpha, which is always one.
        material.transparent.contents = CityStreetDetail.repeatedFacade(finish: .retail, variant: 0).0
        material.transparent.mappingChannel = 1
        material.transparencyMode = .aOne
        for variant in 0..<4 {
            let pair = CityStreetDetail.repeatedFacade(finish: .retail, variant: variant)
            for (name, image) in [("cityRetailDay\(variant)", pair.0), ("cityRetailNight\(variant)", pair.1)] {
                let property = SCNMaterialProperty(contents: image)
                property.wrapS = .repeat; property.wrapT = .repeat
                property.minificationFilter = .linear; property.magnificationFilter = .linear
                property.mipFilter = .linear
                material.setValue(property, forKey: name)
            }
        }
        material.shaderModifiers = [.surface: surface]
        return material
    }

    private static let surface = """
    #pragma arguments
    texture2d<float> cityRetailDay0;
    texture2d<float> cityRetailNight0;
    texture2d<float> cityRetailDay1;
    texture2d<float> cityRetailNight1;
    texture2d<float> cityRetailDay2;
    texture2d<float> cityRetailNight2;
    texture2d<float> cityRetailDay3;
    texture2d<float> cityRetailNight3;
    #pragma body
    constexpr sampler cityRetailSampler(coord::normalized, address::repeat,
                                        filter::linear, mip_filter::linear);
    int cityVariant = int(floor(_surface.transparentTexcoord.x + 0.5));
    float2 cityDayUV = _surface.diffuseTexcoord;
    // A color-only emission slot does not apply SceneKit's texture transform.
    float2 cityNightUV = _surface.diffuseTexcoord * \(CityStreetDetail.facadeLightScale);
    float4 cityDay;
    float4 cityNight;
    if (cityVariant == 0) {
        cityDay = cityRetailDay0.sample(cityRetailSampler, cityDayUV);
        cityNight = cityRetailNight0.sample(cityRetailSampler, cityNightUV);
    } else if (cityVariant == 1) {
        cityDay = cityRetailDay1.sample(cityRetailSampler, cityDayUV);
        cityNight = cityRetailNight1.sample(cityRetailSampler, cityNightUV);
    } else if (cityVariant == 2) {
        cityDay = cityRetailDay2.sample(cityRetailSampler, cityDayUV);
        cityNight = cityRetailNight2.sample(cityRetailSampler, cityNightUV);
    } else {
        cityDay = cityRetailDay3.sample(cityRetailSampler, cityDayUV);
        cityNight = cityRetailNight3.sample(cityRetailSampler, cityNightUV);
    }
    _surface.diffuse *= cityDay;
    _surface.ambient *= cityDay;
    // SceneKit's white emission already contains the existing 0 / .75 intensity.
    _surface.emission.rgb *= cityNight.rgb;
    """
}
#endif
