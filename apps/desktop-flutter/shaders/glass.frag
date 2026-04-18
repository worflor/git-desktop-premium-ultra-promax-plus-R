// Liquid-glass shading. Approximates glass optics without backdrop
// sampling (Flutter's FragmentProgram can't read the dest buffer):
// rounded-rect SDF for fresnel rim, three-channel chromatic dispersion
// along light direction, two-term specular (satin + hot core) over a
// faux dome normal, fresnel-inverse center darkening for depth,
// time+tilt drift on the light vector, and hash-noise micro-grain at
// the rim so it doesn't read as CG-smooth.

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uTint;            // base glass color (theme)
uniform vec4 uHighlight;       // primary rim/spec color (warm)
uniform vec4 uHighlightCool;   // dichroic counterpart (cool side wash)
uniform vec2 uLightDir;        // 2D direction TO the implicit light
uniform vec2 uTilt;            // window-delta tilt vector, normalized [-1..1]
uniform float uTime;           // seconds, monotonic; loops via sin/cos
uniform float uIntensity;      // master strength (0..1)
uniform float uFresnelPx;      // edge falloff distance in px
uniform float uChromatic;      // chromatic edge offset in px
uniform float uSpecSharp;      // spec exponent (4..32) — higher = crispier
uniform float uSpecCore;       // hot-core exponent multiplier (1.5..6)
uniform float uThickness;      // center darken amount (0..1)
uniform float uCornerRadius;   // SDF rim radius — bigger = gloopier meniscus
uniform float uNoise;          // micro-grain amount at rim (0..1)
uniform float uAnim;           // animation strength multiplier (0..1)

out vec4 fragColor;

// iq's rounded-rect SDF. negative inside, positive outside.
float sdRoundedRect(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

float fresnelAt(float dIn, float falloff) {
    return 1.0 - smoothstep(0.0, falloff, dIn);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec2 p = FlutterFragCoord();
    vec2 hsz = uSize * 0.5;
    vec2 cp = p - hsz;
    vec2 ld = normalize(uLightDir);

    // time breathes, tilt pushes; uAnim gates both
    vec2 timeDrift = vec2(sin(uTime * 0.7), cos(uTime * 0.5)) * 0.18 * uAnim;
    vec2 chBase = ld * uChromatic + uTilt * uChromatic * 0.5 * uAnim;

    // three SDF samples → R inward, G center, B outward = prismatic rim
    float r = clamp(uCornerRadius, 0.0, min(hsz.x, hsz.y));
    float sdR = sdRoundedRect(cp - chBase, hsz, r);
    float sdG = sdRoundedRect(cp,          hsz, r);
    float sdB = sdRoundedRect(cp + chBase, hsz, r);
    float fR = fresnelAt(max(-sdR, 0.0), uFresnelPx);
    float fG = fresnelAt(max(-sdG, 0.0), uFresnelPx);
    float fB = fresnelAt(max(-sdB, 0.0), uFresnelPx);

    // faux dome normal so spec wraps over a curve, not a flat
    vec2 nrm = cp / max(length(hsz), 1.0);

    vec2 effLight = normalize(ld + timeDrift + uTilt * 0.4 * uAnim);

    // two-term spec: soft body band + crispy hot core
    float ndl = clamp(dot(nrm, effLight) + 0.5, 0.0, 1.0);
    float sharp = max(uSpecSharp, 1.0);
    float specSoft = pow(ndl, sharp);
    float specHot  = pow(ndl, sharp * max(uSpecCore, 1.5));
    float spec = specSoft * 0.6 + specHot * 0.4;

    // center darken = fake optical thickness
    float dInG = max(-sdG, 0.0);
    float interior = smoothstep(0.0, uFresnelPx * 4.0, dInG);
    float thickness = 1.0 - interior * uThickness * 0.25;

    float n = hash(p) - 0.5;
    float rimMask = 1.0 - interior * 0.85;

    vec3 col = uTint.rgb * thickness;

    col.r += uHighlight.r * fR * uIntensity * 0.55;
    col.g += uHighlight.g * fG * uIntensity * 0.55;
    col.b += uHighlight.b * fB * uIntensity * 0.55;

    // cool dichroic wash on the side opposite the light
    float coolMask = 1.0 - clamp(dot(nrm, ld) + 0.4, 0.0, 1.0);
    col += uHighlightCool.rgb * fG * coolMask * uIntensity * 0.25;

    col += uHighlight.rgb * spec * uIntensity * 0.32;

    col += vec3(n * uNoise * 0.08 * rimMask);

    fragColor = vec4(col, uTint.a);
}
