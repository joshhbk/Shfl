#include <metal_stdlib>
using namespace metal;

// Hash function for noise
float random(float2 st) {
    return fract(sin(dot(st.xy, float2(12.9898, 78.233))) * 43758.5453123);
}

// 2D Noise
float noise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);

    float a = random(i);
    float b = random(i + float2(1.0, 0.0));
    float c = random(i + float2(0.0, 1.0));
    float d = random(i + float2(1.0, 1.0));

    float2 u = f * f * (3.0 - 2.0 * f);

    return mix(a, b, u.x) +
            (c - a)* u.y * (1.0 - u.x) +
            (d - b) * u.x * u.y;
}

[[ stitchable ]] half4 brushedMetal(
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
    
    // Create radial brushing effect
    // We use the radius heavily to create rings, mixed with some angular noise
    // to make it look like spun aluminum
    
    // Base frequency for the rings
    float ringFreq = 1.5;
    
    // Add noise to the radius to create "imperfections" in the brushing
    float noiseVal = noise(float2(radius * ringFreq, angle * 2.0));
    
    // Main brushing texture - high frequency radial noise
    float brushing = noise(float2(radius * 100.0, angle));
    
    // Combine for base metal texture
    float metalTexture = 0.8 + 0.2 * brushing;
    
    // Specular highlight calculation
    // Simulate a light source reflection that moves with highlightOffset
    // We simulate a "cone" of anisotropic reflection typical of brushed metal
    
    // Highlight vector based on offset (tilt)
    float2 highlightDir = normalize(highlightOffset + float2(0.001, 0.001)); // Avoid divide by zero
    float highlightStrength = length(highlightOffset) / 100.0; // Normzlize strength
    
    // Anisotropic highlight: perpendicular to the brushing direction (radial)
    // The brushing is circular, so the normal is radial.
    // The tangent is perpendicular to radius.
    
    // Simple radial gradient highlight logic for "conic" feel
    float2 normalizedDelta = normalize(delta);
    
    // Calculate alignment with the highlight direction
    // For brushed metal, the highlight forms a "pie wedge" or cone shape perpendicular to light
    // specific implementation for "spun" look:
    float diffuse = dot(normalizedDelta, highlightDir);
    
    // Sharpen the highlight
    float specular = pow(max(diffuse, 0.0), 4.0) * highlightStrength * 2.0;
    
    // Mix it all together
    half3 baseColor = color.rgb;
    
    // Apply texture
    half3 finalColor = baseColor * metalTexture;
    
    // Apply highlight (additive)
    finalColor += half3(1.0, 1.0, 1.0) * specular * intensity * 0.5;
    
    return half4(finalColor, color.a);
}
