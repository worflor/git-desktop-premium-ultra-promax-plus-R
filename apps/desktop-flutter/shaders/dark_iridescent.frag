// Loverboy dark iridescence. Same uniform layout as iridescent.frag
// so it shares the loader. Differences:
//   hue cycle compressed to [0.72, 0.95] (pink/lavender/violet band)
//   saturation raised to 0.72..0.90, value raised to 0.85..1.0
//   spec crest at hue 0.82 with a pink tint rather than white
//   h3 time coefficient 0.4 (vs 0.3) for a faster underlayer

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2  uSize;
uniform float uIntensity;
uniform float uHueOffset;
uniform vec4  uPearlBase;    // dark bg base the shimmer mixes into
uniform vec2  uTilt;
uniform float uTime;

out vec4 fragColor;

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
    vec2 uv = FlutterFragCoord() / uSize;

    // Same three-band structure as iridescent.frag. h3 time coefficient
    // is 0.4 (vs 0.3 in iridescent.frag).
    float h1 = uv.x * 1.4 + uv.y * 0.6;
    float h2 = sin(uv.x * 6.28 + uv.y * 3.14) * 0.08;
    float h3 = sin(uv.x * 18.0 - uv.y * 12.0 + uTime * 0.4) * 0.04;

    float drift = uTime * 0.06 + uTilt.x * 0.5 + uTilt.y * 0.3;
    float h = fract(h1 + h2 + h3 + uHueOffset + drift);

    // Remap [0, 1] into [0.72, 0.95]. 0.72 = magenta-pink, 0.95 = blue-violet.
    float hOut = 0.72 + h * 0.23;

    // Wider saturation oscillation than nacre (0.18 vs 0.08).
    float sat = 0.72 + 0.18 * sin(hOut * 12.56);

    float val = 0.88 + 0.12 * sin(h * 6.28 + 1.0);

    vec3 shimmer = hsv2rgb(vec3(hOut, sat, val));

    // Pink-tinted spec crest at hOut ≈ 0.82, vs nacre's white crest.
    float spec = exp(-pow((hOut - 0.82) * 10.0, 2.0)) * 0.35;
    shimmer += vec3(spec * 0.9, spec * 0.15, spec * 0.55);

    vec3 col = mix(uPearlBase.rgb, shimmer, uIntensity);
    fragColor = vec4(col, uPearlBase.a);
}
