// Eigenmanifold — per-glyph thermal presence.
//
// Applied via ShaderMask + srcATop: the shader tints each text glyph
// individually. Cool pole at idle, warming as spectral flux accumulates.
// Per-glyph variation from noise at character-width frequency. The
// effect is always on — the text quietly breathes.

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2  uSize;
uniform float uTime;
uniform float uTemperature;   // [0, 1]: 0 = cold/idle, 1 = hot/active
uniform float uGap;           // spectral gap → flow coherence
uniform float uSpectralDim;   // spectral dimension → noise complexity
uniform float uBerryPhase;    // accumulated radians, grows monotonically
uniform float uIntensity;     // master fade [0, 1]
uniform vec4  uCoolColor;     // theme's cool chromatic pole
uniform vec4  uWarmColor;     // theme's warm chromatic pole

out vec4 fragColor;

// --- noise ---

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    for (int i = 0; i < octaves; i++) {
        v += a * noise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    float temp = clamp(uTemperature, 0.0, 1.0);

    // --- Macro flow ---
    // Berry phase slowly rotates the gradient direction. Over a session
    // the warm/cool zones drift from left-right to diagonal to vertical.
    float angle = uBerryPhase * 0.03;
    vec2 flowDir = vec2(cos(angle), sin(angle));
    float flow = dot(uv - 0.5, flowDir) + 0.5;

    // --- Per-glyph variation ---
    // Noise at character-width frequency (~14 features across the text).
    // Each letter gets a slightly different warmth.
    float glyphVar = noise(vec2(
        uv.x * 14.0 + uBerryPhase * 0.3,
        uv.y * 3.0 + uTime * 0.008
    ));

    // Blend macro + glyph. Temperature increases individuality:
    // cold → mostly uniform wash, hot → each letter finds its own warmth.
    float detail = 0.25 + temp * 0.35;
    float field = mix(flow, glyphVar, detail);

    // --- k₀ breathing ---
    const float k0 = 0.27;
    float spring = sin(uTime * sqrt(k0) * 0.4) * 0.5 + 0.5;
    spring = mix(0.5, spring, 0.3);
    field = field * (0.85 + 0.15 * spring);

    // --- Spectral texture ---
    // Dimension controls complexity; gap controls coherence.
    int octaves = clamp(int(uSpectralDim), 1, 4);
    float grain = fbm(
        uv * (6.0 + uSpectralDim * 2.0) + uTime * 0.01,
        octaves
    );
    float coherence = clamp(uGap * 2.0, 0.1, 1.0);
    field = mix(field, field * (0.8 + 0.4 * grain), (1.0 - coherence) * 0.5);

    // --- Color ---
    // Temperature shifts the palette center; field adds local variation.
    // Cold: narrow range near cool pole → monochromatic shimmer.
    // Hot: broad sweep across both poles → rich chromatic flow.
    float range = 0.12 + temp * 0.58;
    float center = temp;
    float colorMix = clamp(center + (field - 0.5) * range, 0.0, 1.0);
    vec4 color = mix(uCoolColor, uWarmColor, colorMix);

    // --- Alpha (tint strength) ---
    // Always visible. Rises with temperature.
    float baseAlpha = 0.10 + temp * 0.32;
    baseAlpha *= (0.8 + 0.2 * field);
    baseAlpha *= (0.92 + 0.08 * spring);
    float alpha = baseAlpha * uIntensity;

    fragColor = vec4(color.rgb, alpha);
}
