// Nacre / mother-of-pearl shimmer.
//
// Position-derived HSV hue shift: the bg color literally changes with
// fragment coordinate, mimicking how light splits into different
// wavelengths through a thin film (soap bubble, oil slick, nacre).
//
// Three frequency bands stack for layered "depth shift":
//   - h1: slow diagonal gradient across the whole surface
//   - h2: tighter sin ripple, breaks up the linear hue ramp
//   - h3: high-frequency oil-slick vibration, time-animated
//
// Two animation sources nudge the hue continuously:
//   - uTime: slow continuous drift (~1 cycle per 100s) so static
//     surfaces still shimmer
//   - uTilt: window-position delta from `LiquidGlassProvider`, so as
//     the user drags the window the iridescent gradient slides like
//     real mother-of-pearl catching a different angle of light
//
// A subtle spec highlight pops where the hue lands in a target band,
// reading as the bright "wet" spot you see on actual nacre. Saturation
// itself oscillates with hue so different regions feel pearl vs
// chromatic — adds depth without raising the global saturation.
//
// All math is per-pixel, ~20 ALU ops, no texture fetches, no branches.

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uIntensity;     // 0..1 shimmer strength
uniform float uHueOffset;     // global hue rotation (legacy hook)
uniform vec4 uPearlBase;      // pearl-cream base the shimmer mixes into
uniform vec2 uTilt;           // window-delta tilt vector, [-1..1]
uniform float uTime;          // seconds, monotonic

out vec4 fragColor;

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
    vec2 uv = FlutterFragCoord() / uSize;

    // Three stacked frequency bands. h3 animates over time so the
    // surface always has a slow vibration even when the window is
    // still — never reads as a frozen gradient.
    float h1 = uv.x * 1.4 + uv.y * 0.6;
    float h2 = sin(uv.x * 6.28 + uv.y * 3.14) * 0.08;
    float h3 = sin(uv.x * 18.0 - uv.y * 12.0 + uTime * 0.3) * 0.04;

    // Drift: continuous time creep + window-tilt parallax. Tilt has
    // larger weight on x because horizontal window drags read more
    // strongly as a "viewing angle change" for iridescent surfaces.
    float drift = uTime * 0.06 + uTilt.x * 0.5 + uTilt.y * 0.3;
    float h = fract(h1 + h2 + h3 + uHueOffset + drift);

    // Saturation oscillates with hue — pearl regions (low sat) and
    // chromatic regions (high sat) interleave for visual depth instead
    // of one uniform pastel wash.
    float sat = 0.32 + 0.08 * sin(h * 6.28);
    vec3 shimmer = hsv2rgb(vec3(h, sat, 1.0));

    // Spec highlight: where hue lands near a target band, add a soft
    // bright pop. Mimics the "wet" iridescent crest on real nacre.
    // The exp falls off quickly so the highlight is a localized glow,
    // not a flat brightening.
    float specBand = exp(-pow((h - 0.65) * 8.0, 2.0)) * 0.25;
    shimmer += vec3(specBand);

    // Mix into the pearl base — at intensity=0 we get pure base, at
    // intensity=1 we get pure shimmer.
    vec3 col = mix(uPearlBase.rgb, shimmer, uIntensity);

    fragColor = vec4(col, uPearlBase.a);
}
