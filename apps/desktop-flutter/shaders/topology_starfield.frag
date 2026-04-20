// topology_starfield.frag
//
// Replaces _paintStarfield's ~158 per-frame drawCircle calls with one
// fragment-shaded quad. Each pixel iterates the golden-angle spiral
// twice (base + dense counts) and accumulates brightness from the
// closest stars. Output is a translucent overlay — the same visual as
// the CPU version but rendered in ~1ms on integrated GPUs and
// substantially less on discrete.
//
// Star positions are parameterised by uMaxRadius only, so the same
// program handles every canvas size. Base + dense counts / fade
// envelopes come in as scalar uniforms; no per-entity data texture
// needed at this scale.

#version 460 core
#include <flutter/runtime_effect.glsl>

// Must be a vec2 (Flutter packs consecutive setFloats into vecs).
uniform vec2 uSize;         // canvas size in px (2 floats)
uniform vec2 uCenter;       // starfield center (2 floats)
uniform float uMaxRadius;   // outermost spiral radius
uniform float uBaseCount;   // base spiral star count (~48)
uniform float uExtraCount;  // extra spiral star count (0..110)
uniform float uBaseEnv;     // base fade envelope, [0, 1]
uniform float uDenseEnv;    // dense fade envelope, [0, 1]
uniform vec4 uColor;        // chrome color (premultiplied rgba)

out vec4 fragColor;

const float GOLDEN_ANGLE = 2.3998;

// Soft-edged dot at `center` with half-size `size`. Matches Flutter's
// default 1px antialias on drawCircle.
float dot_intensity(vec2 frag, vec2 center, float size) {
    float d = distance(frag, center);
    return 1.0 - smoothstep(size - 0.5, size + 0.5, d);
}

void main() {
    vec2 p = FlutterFragCoord().xy;

    // Reject pixels outside the canvas rect (Flutter occasionally
    // runs the shader on a slightly-larger raster pass; this ensures
    // we don't splatter stars past the declared size).
    if (p.x < 0.0 || p.y < 0.0 || p.x > uSize.x || p.y > uSize.y) {
        fragColor = vec4(0.0);
        return;
    }

    float baseIntensity = 0.0;
    float denseIntensity = 0.0;

    // Base layer: fixed 48-star count, capped via const for unroll.
    if (uBaseEnv > 0.0) {
        int baseN = int(uBaseCount + 0.5);
        for (int i = 0; i < 48; i++) {
            if (i >= baseN) break;
            float fi = float(i);
            float t = fi / uBaseCount;
            float r = uMaxRadius * (0.18 + 0.95 * sqrt(t));
            float theta = fi * GOLDEN_ANGLE;
            vec2 starPos = uCenter + r * vec2(cos(theta), sin(theta));
            float size = 0.9 + 0.5 * sin(fi * 1.7);
            baseIntensity += dot_intensity(p, starPos, size);
        }
    }

    // Dense layer: up to 110 stars, bounded by caller's cap.
    if (uDenseEnv > 0.0 && uExtraCount > 0.0) {
        int extraN = int(uExtraCount + 0.5);
        float total = uBaseCount + uExtraCount;
        for (int i = 0; i < 110; i++) {
            if (i >= extraN) break;
            float fi = float(i);
            float t = (fi + uBaseCount) / total;
            float r = uMaxRadius * (0.22 + 0.92 * sqrt(t));
            float theta = (fi + uBaseCount) * GOLDEN_ANGLE;
            vec2 starPos = uCenter + r * vec2(cos(theta), sin(theta));
            float size = 0.9 + 0.4 * sin(fi * 2.1);
            denseIntensity += dot_intensity(p, starPos, size);
        }
    }

    // Compose. Each base star contributes baseAlpha = 0.24 * baseEnv
    // at its center; dense contributes 0.28 * denseEnv. Sum and
    // clamp to avoid over-bright overlap in high-density regions.
    float alpha = clamp(
        baseIntensity * 0.24 * uBaseEnv +
            denseIntensity * 0.28 * uDenseEnv,
        0.0,
        1.0);
    // Premultiplied output matches Flutter's compositor expectations.
    fragColor = vec4(uColor.rgb * alpha, alpha) * uColor.a;
}
