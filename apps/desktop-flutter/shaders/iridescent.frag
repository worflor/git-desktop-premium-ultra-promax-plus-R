// Nacre / mother-of-pearl shimmer. Position-derived HSV hue shift
// across three stacked frequency bands, driven by uTime drift and
// uTilt parallax so dragging the window slides the gradient.

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

    // three stacked bands; h3 is time-animated so static surfaces
    // still shimmer
    float h1 = uv.x * 1.4 + uv.y * 0.6;
    float h2 = sin(uv.x * 6.28 + uv.y * 3.14) * 0.08;
    float h3 = sin(uv.x * 18.0 - uv.y * 12.0 + uTime * 0.3) * 0.04;

    // tilt weighted toward x — horizontal drag reads as viewing-angle change
    float drift = uTime * 0.06 + uTilt.x * 0.5 + uTilt.y * 0.3;
    float h = fract(h1 + h2 + h3 + uHueOffset + drift);

    // sat oscillates with hue so pearl + chromatic regions interleave
    float sat = 0.32 + 0.08 * sin(h * 6.28);
    vec3 shimmer = hsv2rgb(vec3(h, sat, 1.0));

    // wet-crest highlight near hue 0.65
    float specBand = exp(-pow((h - 0.65) * 8.0, 2.0)) * 0.25;
    shimmer += vec3(specBand);

    vec3 col = mix(uPearlBase.rgb, shimmer, uIntensity);

    fragColor = vec4(col, uPearlBase.a);
}
