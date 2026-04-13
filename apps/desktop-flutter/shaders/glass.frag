// Real-time liquid glass shading.
//
// "Liquid glass" UI aesthetic: gloopy meniscus rim, crispy specular core,
// chromatic dispersion at the edge, subtle internal flow that reads as
// alive. All without backdrop sampling — Flutter's FragmentProgram can't
// efficiently sample the destination buffer, so we approximate the
// optical phenomena that actually carry "this is glass" perception:
//
//   1. Rim fresnel via rounded-rect SDF — distance-to-edge is computed
//      against a configurable corner radius so the rim wraps the
//      corners with curvature instead of jagging at right angles.
//      uCornerRadius=0 gives sharp box rim; large radius gives gloopy
//      meniscus.
//
//   2. Three-channel chromatic dispersion — R/G/B sample the SDF at
//      slightly offset positions along the light direction, modulated
//      by uTilt (window-position delta). Produces prismatic edge fringe
//      that ALSO subtly shifts as the window moves, like a real lens
//      catching a different angle of room light.
//
//   3. Two-term specular — soft satin band (low exponent) plus a
//      crispy hot core (high exponent). Surface normal is a faux dome
//      (radial vector from center), so the spec wraps as if the pane
//      bulges slightly instead of sliding flat.
//
//   4. Center darkening — light *transmits* through thick glass; only
//      the rim reflects. A multiplicative inverse of fresnel produces
//      depth illusion without actual refraction.
//
//   5. Time + tilt drift — slow sin/cos on the effective light vector
//      makes spec breathe; window tilt shifts spec like a real
//      reflection following the room. Either source can be zeroed via
//      uAnim.
//
//   6. Hash-noise micro-grain at the rim — perfectly smooth glass reads
//      CG. A few cents of value-noise scaled by inverse interior makes
//      the rim feel tactile without pebbling the body.
//
// ~50 ALU per fragment, no branches. Runs at native fps on integrated
// GPUs even with all features at max.

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

// Signed distance to a rounded rectangle. Negative inside, positive
// outside. Standard inigo quilez form — three vector ops + length.
float sdRoundedRect(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

float fresnelAt(float dIn, float falloff) {
    return 1.0 - smoothstep(0.0, falloff, dIn);
}

// Cheap value-noise hash. Single sin + dot; ~3 ALU on modern GPUs.
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec2 p = FlutterFragCoord();
    vec2 hsz = uSize * 0.5;
    vec2 cp = p - hsz;
    vec2 ld = normalize(uLightDir);

    // Drift sources. Time gives continuous slow breathing so glass is
    // alive even when the window is still; tilt nudges chromatic
    // dispersion and the effective light vector when the window moves.
    // Both gated by uAnim so themes can opt out of motion entirely.
    vec2 timeDrift = vec2(sin(uTime * 0.7), cos(uTime * 0.5)) * 0.18 * uAnim;
    vec2 chBase = ld * uChromatic + uTilt * uChromatic * 0.5 * uAnim;

    // Three SDF samples for chromatic dispersion. R inward, G center,
    // B outward → prismatic rim. Offset doubles as a hand-of-god lens
    // shift when the window tilts.
    float r = clamp(uCornerRadius, 0.0, min(hsz.x, hsz.y));
    float sdR = sdRoundedRect(cp - chBase, hsz, r);
    float sdG = sdRoundedRect(cp,          hsz, r);
    float sdB = sdRoundedRect(cp + chBase, hsz, r);
    float fR = fresnelAt(max(-sdR, 0.0), uFresnelPx);
    float fG = fresnelAt(max(-sdG, 0.0), uFresnelPx);
    float fB = fresnelAt(max(-sdB, 0.0), uFresnelPx);

    // Faux dome normal — radial vector from center, scaled to roughly
    // unit magnitude. Surface acts like a slightly bulged lens so the
    // spec streak wraps over a curve instead of sliding across a flat.
    vec2 nrm = cp / max(length(hsz), 1.0);

    // Effective light direction = base + breathing drift + tilt push.
    vec2 effLight = normalize(ld + timeDrift + uTilt * 0.4 * uAnim);

    // Two-term spec: soft body band (sells "light caught in the pane")
    // + crispy hot core (sells "single bright reflection point"). Mix
    // ratio favors the band slightly to avoid harsh chromy hot spots.
    float ndl = clamp(dot(nrm, effLight) + 0.5, 0.0, 1.0);
    float sharp = max(uSpecSharp, 1.0);
    float specSoft = pow(ndl, sharp);
    float specHot  = pow(ndl, sharp * max(uSpecCore, 1.5));
    float spec = specSoft * 0.6 + specHot * 0.4;

    // Center darkening — fakes optical thickness. Real glass transmits
    // light through its body and reflects at the surface; multiplying
    // the tint by an inverse-fresnel mask creates the illusion of depth
    // without actual refraction. Capped so we never push to black.
    float dInG = max(-sdG, 0.0);
    float interior = smoothstep(0.0, uFresnelPx * 4.0, dInG);
    float thickness = 1.0 - interior * uThickness * 0.25;

    // Rim noise mask — grain reads at the edge (where light catches
    // surface imperfections) and smooths out across the body.
    float n = hash(p) - 0.5;
    float rimMask = 1.0 - interior * 0.85;

    // Composite. Tint × thickness is the substrate; everything else
    // adds light to it.
    vec3 col = uTint.rgb * thickness;

    // Per-channel chromatic rim glow.
    col.r += uHighlight.r * fR * uIntensity * 0.55;
    col.g += uHighlight.g * fG * uIntensity * 0.55;
    col.b += uHighlight.b * fB * uIntensity * 0.55;

    // Cool dichroic wash painted only at the rim, biased to the side
    // OPPOSITE the primary light. Two-source illumination feel — like
    // a warm lamp from one side and a cool sky tint from the other.
    float coolMask = 1.0 - clamp(dot(nrm, ld) + 0.4, 0.0, 1.0);
    col += uHighlightCool.rgb * fG * coolMask * uIntensity * 0.25;

    // Specular — uses the warm primary highlight color.
    col += uHighlight.rgb * spec * uIntensity * 0.32;

    // Rim micro-grain.
    col += vec3(n * uNoise * 0.08 * rimMask);

    fragColor = vec4(col, uTint.a);
}
