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
    
    // --- TEXTURE GENERATION ---
    
    // 1. Base Grain (The main "spun" look)
    float baseGrain = shfl_noise(float2(radius * 400.0, angle * 2.0));
    
    // 2. Micro-scratches (Fine detail)
    float scratches = shfl_noise(float2(radius * 1200.0 + shfl_noise(float2(angle * 50.0)) * 20.0, angle * 20.0));
    
    // 3. Radial variation (Subtle rings)
    float rings = shfl_noise(float2(radius * 50.0, 0.0));
    
    // 4. Low-frequency waviness (New layer for "realism" and imperfections)
    // Helps avoid the perfect computer-generated look.
    float waviness = shfl_noise(float2(radius * 10.0, angle * 4.0));
    
    // Compose the height map (0.0 to 1.0)
    // Increased weight of scratches and waviness for more "bite"
    float height = (baseGrain * 0.4 + scratches * 0.4 + rings * 0.1 + waviness * 0.1);
    
    // --- LIGHTING ---
    
    // Calculate Normal from height map
    // Tangent follows the brush direction (angular)
    float2 tangent = float2(-sin(angle), cos(angle));
    // Bitangent points outwards (radial)
    float2 bitangent = float2(cos(angle), sin(angle));
    
    // Perturb normal - increased perturbation for more "crunchy" metal feel
    float normalPerturb = (height - 0.5) * 1.5; 
    float3 surfaceNormal = normalize(float3(bitangent * normalPerturb * 0.5, 1.0));
    
    // Light Source
    // Reduced tilt sensitivity slightly to keep glare more centered/controlled
    float3 lightDir = normalize(float3(highlightOffset.x * 0.005, highlightOffset.y * 0.005, 1.0));
    
    // Specular Reflection (Blinn-Phong)
    float3 viewDir = float3(0.0, 0.0, 1.0);
    float3 halfwayDir = normalize(lightDir + viewDir);
    float specAngle = max(dot(surfaceNormal, halfwayDir), 0.0);
    
    // Anisotropic highlight
    // BROADER falloff (lower exponent) for a softer, less "laser-like" glare.
    // This helps avoid the "cut off" feel by spreading the light more.
    float specular = pow(specAngle, 8.0); 
    
    // --- COMPOSITION ---
    
    // Deepen the ambient occlusion in grooves
    float occlusion = 0.7 + 0.3 * height;
    
    half3 baseColor = color.rgb * occlusion;
    
    // Warm, soft highlight
    half3 highlightColor = half3(1.0, 0.98, 0.95);
    
    // Final mix
    // Reduced intensity multiplier to fix "insane glare"
    half3 finalColor = baseColor + highlightColor * specular * intensity * 0.25;
    
    return half4(finalColor, color.a);
}
