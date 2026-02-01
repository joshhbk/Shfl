#include <metal_stdlib>
using namespace metal;

// Hash function for noise
static float shfl_random(float2 st) {
    return fract(sin(dot(st.xy, float2(12.9898, 78.233))) * 43758.5453123);
}

// 2D Noise
static float shfl_noise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);

    float a = shfl_random(i);
    float b = shfl_random(i + float2(1.0, 0.0));
    float c = shfl_random(i + float2(0.0, 1.0));
    float d = shfl_random(i + float2(1.0, 1.0));

    float2 u = f * f * (3.0 - 2.0 * f);

    return mix(a, b, u.x) +
            (c - a)* u.y * (1.0 - u.x) +
            (d - b) * u.x * u.y;
}

[[ stitchable ]] half4 shfl_brushedMetal(
    float2 position,
    half4 color,
    float2 center,
    float2 highlightOffset,
    float intensity
) {
    // Subtle grain texture - no directional pattern

    // Fine grain at different scales for natural look
    float fineGrain = shfl_noise(position * 2.0);
    float mediumGrain = shfl_noise(position * 0.5);

    // Combine grains - mostly fine detail with subtle low-frequency variation
    float grain = fineGrain * 0.7 + mediumGrain * 0.3;

    // Very subtle variation: 0.95 to 1.05 range (±5%)
    float variation = 0.95 + grain * 0.1 * intensity;

    // Apply subtle grain to color
    half3 finalColor = color.rgb * variation;

    return half4(finalColor, color.a);
}
