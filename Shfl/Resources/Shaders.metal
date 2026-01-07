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
    // Convert to polar coordinates relative to the view center
    float2 delta = position - center;
    float radius = length(delta);
    float angle = atan2(delta.y, delta.x);
    
    // --- TEXTURE GENERATION (Sparkling Anodized) ---
    // Target: Visible, metallic grain that sparkles.
    
    float2 uv = position;
    
    // 1. Visible Grain (Medium frequency)
    // Larger scale so individual "grains" are visible on screen.
    float grainHigh = shfl_noise(uv * 3.0);
    float grainLow = shfl_noise(uv * 0.5);
    
    // 2. Mix for natural variation
    // The "grain" is the surface texture.
    float grain = grainHigh * 0.7 + grainLow * 0.3;
    
    // 3. Directional Bias (Linear Vertical - very subtle)
    // Keeps it feeling like a manufactured casing
    float directional = shfl_noise(float2(uv.x * 4.0, uv.y * 0.1));
    
    // Height map
    // Sharper contrast for "rough" metal look
    float height = grain * 0.8 + directional * 0.2;
    
    // --- LIGHTING ---
    
    // Tangent/Bitangent (Standard UV space)
    float2 bitangent = float2(1.0, 0.0); // Horizontal
    
    // Perturb normal - SIGNFICANTLY INCREASED for metallic "bite"
    // Was 0.15 (too smooth), now 1.2
    float normalPerturb = (height - 0.5) * 1.2;
    
    // Anisotropic Normal (Brushed-ish bias)
    float3 anisotropicNormal = normalize(float3(bitangent * normalPerturb, 1.0));
    // Isotropic Normal (General surface)
    float3 isotropicNormal = normalize(float3(bitangent * normalPerturb * 0.5, 1.0));
    
    // Light Source
    float3 lightDir = normalize(float3(highlightOffset.x * 0.015, highlightOffset.y * 0.015, 1.0));
    
    // Specular Reflection
    float3 viewDir = float3(0.0, 0.0, 1.0);
    float3 halfwayDir = normalize(lightDir + viewDir);
    
    // 1. Broad Sheen (Satin finish)
    float isoAngle = max(dot(isotropicNormal, halfwayDir), 0.0);
    float baseSheen = pow(isoAngle, 2.0);
    
    // 2. Metallic Sparkle (High freq interaction)
    // We actively start creating "hot spots" based on the noise grain
    float sparkleAngle = max(dot(anisotropicNormal, halfwayDir), 0.0);
    // High exponent for sharp sparkles
    float sparkleSpec = pow(sparkleAngle, 12.0);
    // Modulate sparkle by the grain height - high points sparkle more
    float sparkle = sparkleSpec * (height * 1.5); 
    
    // Combine Specular
    // Base sheen for shape + Sparkle for texture "pop"
    float specular = baseSheen * 0.4 + sparkle * 0.6;
    
    // --- COMPOSITION ---
    
    // Ambient Occlusion
    // Restoring some contrast so the texture exists in the darks too
    float occlusion = 0.8 + 0.2 * height;
    
    half3 baseColor = color.rgb * occlusion;
    
    // Highlight Overlay
    half3 highlightColor = half3(1.0, 1.0, 1.0);
    
    // Final mix
    // Intensity bump (0.12 -> 0.22) to make the sparkle visible
    half3 finalColor = baseColor + (highlightColor * specular * intensity * 0.22 * color.a);
    
    return half4(finalColor, color.a);
}
