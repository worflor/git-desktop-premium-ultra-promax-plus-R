// Petrichor fog: layered value noise at different scales drifting
// slowly in different directions. Tilt shifts the fog as a parallax
// layer. Output is a soft luminance wash composited over the
// app gradient at very low opacity from Dart.

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2  uSize;
uniform float uTime;
uniform vec2  uTilt;
uniform float uIntensity;

out vec4 fragColor;

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

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec2 tilt = uTilt * 0.04;

    float t = uTime * 0.012;

    float f1 = fbm(uv * 2.8 + tilt * 1.0 + vec2(t, t * 0.7));
    float f2 = fbm(uv * 1.4 + tilt * 1.8 + vec2(-t * 0.5, t * 0.3) + 40.0);
    float f3 = fbm(uv * 4.5 + tilt * 0.6 + vec2(t * 0.3, -t * 0.2) + 80.0);

    float fog = f1 * 0.5 + f2 * 0.35 + f3 * 0.15;
    fog = smoothstep(0.28, 0.72, fog);

    // Soft vignette — fog thins at edges.
    vec2 vig = uv - 0.5;
    float v = 1.0 - dot(vig, vig) * 0.8;

    float alpha = fog * v * uIntensity;

    vec3 col = vec3(0.70, 0.76, 0.82);
    fragColor = vec4(col * alpha, alpha);
}
