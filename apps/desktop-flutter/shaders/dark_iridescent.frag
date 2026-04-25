// Loverboy dark iridescence — same thin-film interference physics as
// iridescent.frag, but the resulting spectral pattern is remapped onto
// the pink → lavender → violet band loverboy's identity lives in.
//
// The thin-film PATTERN is fully physics-driven: path difference, Snell's
// law, wavelength-dependent amplitude — all real. What's stylized is the
// mapping from interference amplitude to displayed color. Instead of
// outputting the CIE-correct spectrum, we drive a three-stop palette
// (pink/lavender/violet) using the blue-channel amplitude as the position
// along that palette. The PATTERN therefore shifts the same way real
// iridescence does (with view angle, with thickness, with time) — only
// the palette is constrained.
//
// See iridescent.frag for the underlying physics.

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2  uSize;
uniform float uIntensity;
uniform float uHueOffset;     // biases thickness (was static hue)
uniform vec4  uPearlBase;
uniform vec2  uTilt;
uniform float uTime;

out vec4 fragColor;

const float PI     = 3.14159265358979;
const float TWO_PI = 6.28318530717959;

const float N_FILM = 1.56;

const float LAMBDA_R = 611.0;
const float LAMBDA_G = 549.0;
const float LAMBDA_B = 464.0;

// Narrower / cooler thickness range than iridescent.frag so the bare
// physics already leans toward shorter wavelengths before the palette
// remap. Keeps temporal/positional variation authentic to thin-film.
const float D_MIN = 220.0;
const float D_MAX = 620.0;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void main() {
    vec2 uv = FlutterFragCoord() / uSize;

    // ---- Thin-film interference (same physics as iridescent.frag). ----
    // Slow temporal drift (10× gentler than iridescent.frag). Fast
    // hue shifts here were showing THROUGH loverboy's partial-alpha
    // cell edges and crossfade pixels, reading as per-frame flicker
    // at those intermediate-alpha pixels. Slower drift keeps the
    // "alive" shimmer feel but pushes per-frame changes below
    // visible perception under the partial-alpha compositing.
    float n1 = valueNoise(uv * 5.0  + vec2(uTime * 0.005, uTime * 0.004));
    float n2 = valueNoise(uv * 13.0 + vec2(-uTime * 0.003, uTime * 0.006));
    float nm = n1 * 0.65 + n2 * 0.35;
    float d  = mix(D_MIN, D_MAX, fract(nm + uHueOffset));

    vec2  viewTilt    = uTilt * 0.55 + (uv - 0.5) * 0.20;
    float sinSqTheta  = min(dot(viewTilt, viewTilt), 0.25);
    float sinSqThetaT = sinSqTheta / (N_FILM * N_FILM);
    float cosThetaT   = sqrt(1.0 - sinSqThetaT);

    float delta = 2.0 * N_FILM * d * cosThetaT;

    float phiR = TWO_PI * delta / LAMBDA_R + PI;
    float phiG = TWO_PI * delta / LAMBDA_G + PI;
    float phiB = TWO_PI * delta / LAMBDA_B + PI;

    vec3 amp = vec3(
        (1.0 + cos(phiR)) * 0.5,
        (1.0 + cos(phiG)) * 0.5,
        (1.0 + cos(phiB)) * 0.5
    );

    // ---- Palette remap onto the loverboy band. ----
    // The blue-channel amplitude makes a naturally good palette cursor
    // for the cool band. Use it as a position in [0, 1] over the
    // pink → lavender → violet gradient.
    float t     = amp.b;
    float tPink = 1.0 - smoothstep(0.0, 0.5, t);
    float tVio  = smoothstep(0.5, 1.0, t);
    float tLav  = max(0.0, 1.0 - tPink - tVio);

    vec3 pink     = vec3(1.00, 0.43, 0.71);
    vec3 lavender = vec3(0.82, 0.57, 0.93);
    vec3 violet   = vec3(0.52, 0.30, 0.90);

    vec3 tinted = pink * tPink + lavender * tLav + violet * tVio;

    // ---- Brightness modulation from total interference amplitude. ----
    // Peaks (constructive across channels) brighten the palette; valleys
    // darken it. Gives the surface a lively, iridescent shimmer WITHIN
    // the constrained palette.
    float bright = (amp.r + amp.g + amp.b) * 0.333;
    tinted *= 0.55 + 0.65 * bright;

    // ---- Pink-tinted specular crest at the constructive sweet spot. ----
    // Where the green channel peaks (bright ≈ 1), add a warm highlight.
    float crest = smoothstep(0.75, 1.0, amp.g);
    tinted += vec3(crest * 0.55, crest * 0.15, crest * 0.35);

    vec3 col = mix(uPearlBase.rgb, tinted, uIntensity);
    fragColor = vec4(col, uPearlBase.a);
}
