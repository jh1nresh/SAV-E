#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Quantize spatial sampling only; retain source colors and premultiplied alpha.
[[ stitchable ]] half4 savePixelate(float2 position, SwiftUI::Layer layer,
                                    float4 bounds, float cellSize) {
    float cell = max(cellSize, 1.0f);
    float2 local = position - bounds.xy;
    float2 sample = floor(local / cell) * cell + cell * 0.5f;
    sample = clamp(sample, float2(0.0f), max(bounds.zw - 0.5f, float2(0.0f)));
    return layer.sample(bounds.xy + sample);
}
