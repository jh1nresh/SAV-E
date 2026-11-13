#include <metal_stdlib>
using namespace metal;
#include <SceneKit/scn_metal>

struct CityCompositeInput {
    float4 position [[attribute(SCNVertexSemanticPosition)]];
    float2 uv [[attribute(SCNVertexSemanticTexcoord0)]];
};
struct CityCompositeVertex {
    float4 position [[position]];
    float2 uv;
};
vertex CityCompositeVertex cityCompositeVertex(CityCompositeInput in [[stage_in]]) {
    return {in.position, float2(in.uv.x, 1.0f - in.uv.y)};
}
float3 cityEncodeSRGB(float3 color) {
    return select(12.92f * color, 1.055f * pow(color, float3(1.0f / 2.4f)) - 0.055f,
                  color > 0.0031308f);
}
float3 cityDecodeSRGB(float3 color) {
    return select(color / 12.92f, pow((color + 0.055f) / 1.055f, float3(2.4f)),
                  color > 0.04045f);
}
fragment float4 cityCompositeFragment(CityCompositeVertex in [[stage_in]],
                                      texture2d<float> linearColor [[texture(0)]]) {
    constexpr sampler sampleColor(coord::normalized, address::clamp_to_edge, filter::nearest);
    float4 color = linearColor.sample(sampleColor, in.uv);
    float alpha = clamp(color.a, 0.0f, 1.0f);
    if (alpha <= 0.000001f) return float4(0);
    if (alpha >= 0.999999f) return color;
    // The final sRGB attachment encodes RGB after this function. Associate
    // RGB in display space before that conversion, rather than encoding an
    // already-premultiplied linear value (which can make RGB exceed alpha).
    float3 straight = clamp(color.rgb / alpha, 0.0f, 1.0f);
    float3 associatedDisplay = cityEncodeSRGB(straight) * alpha;
    return float4(cityDecodeSRGB(associatedDisplay), alpha);
}
