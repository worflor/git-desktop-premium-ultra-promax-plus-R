// CRT phosphor shader, applied as an `ImageFilter.shader` so the live
// scene is auto-bound to `uBackdrop` and we can transform it through
// real CRT optics:
//
//   1. Barrel distortion — the tube's faceplate is convex; edges bow
//      outward. Radial warp: uv' = uv + k·r²·(uv − 0.5).
//   2. Beam Gaussian — the electron beam is Gaussian-shaped and spreads
//      horizontally as it paints each scanline. Approximated here with
//      a symmetric 3-tap horizontal sample.
//   3. Aperture grille — subpixel RGB stripes every `uMaskPitch` px.
//      Trinitron/GDM-style vertical stripes attenuate each channel in
//      its own sub-stripe.
//   4. Scanlines — smooth darkening between integer pixel rows; the
//      classic "horizontal dim-band between lines" look.
//   5. Phosphor tint + glow — a slight emissive boost in the material's
//      phosphor color (P22 green by default, P3 amber for legacy feel).
//
// No temporal persistence in this pass (would need a per-surface
// feedback buffer). The shadow-mask + beam + scanlines give the CRT
// identity; persistence is an obvious v2 add using the same
// previous-frame snapshot pattern we used for Conway's Life.
//
// References:
//   Sony Trinitron aperture grille (1968)
//   P22 phosphor chromaticity (EIA standard, ~1953)
//   Lottes, "CRT Shader" (2013) — seminal public-domain implementation
//     that informed the general structure here

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2  uSize;
uniform float uIntensity;
uniform float uTime;
uniform vec4  uPhosphorTint;    // light-emissive color, rgba
uniform float uMaskPitch;        // px per RGB triplet, 3.0 = native subpixels
uniform float uBeamSigma;        // horizontal Gaussian spread in px
uniform float uScanlineDepth;    // 0..1 — darkening between scanlines
uniform float uBarrelAmount;     // 0..0.2 — faceplate curvature

uniform sampler2D uBackdrop;

out vec4 fragColor;

const float PI = 3.14159265358979;

void main() {
    vec2 p  = FlutterFragCoord();
    vec2 uv = p / uSize;

    // ---- (1) Barrel distortion. ----
    // Classic radial warp around the centre. Larger r² → more bow.
    // Sampling beyond [0,1] gets clamped by the caller to black, which
    // gives a natural vignette at the tube's corners.
    vec2  cp   = uv - 0.5;
    float r2   = dot(cp, cp);
    vec2  warp = cp * (1.0 + uBarrelAmount * r2);
    vec2  suv  = 0.5 + warp;

    // ---- (2) Beam Gaussian (3-tap horizontal). ----
    // Electron beam has a Gaussian profile. Three symmetric taps on the
    // horizontal axis approximate it: 0.5 centre + 0.25 each wing.
    vec2  stepPx = vec2(1.0, 0.0) / uSize;
    vec3  scene  = texture(uBackdrop, clamp(suv,                    vec2(0.0), vec2(1.0))).rgb * 0.50
                 + texture(uBackdrop, clamp(suv + stepPx * uBeamSigma, vec2(0.0), vec2(1.0))).rgb * 0.25
                 + texture(uBackdrop, clamp(suv - stepPx * uBeamSigma, vec2(0.0), vec2(1.0))).rgb * 0.25;

    // ---- (3) Aperture grille. ----
    // Each triplet of `uMaskPitch` pixels cycles R/G/B. Within a stripe
    // the matching channel is boosted (0.4 + 0.6 × stripe), others are
    // attenuated to 0.4. Baseline 0.4 prevents the mask from reading as
    // pure colored bars at rest — real grilles aren't that saturated.
    float phase  = mod(p.x, uMaskPitch) / uMaskPitch;
    float third  = 1.0 / 3.0;
    float twoThirds = 2.0 / 3.0;
    vec3  mask   = vec3(0.4);
    mask.r += 0.6 * (1.0 - step(third, phase));
    mask.g += 0.6 * step(third, phase) * (1.0 - step(twoThirds, phase));
    mask.b += 0.6 * step(twoThirds, phase);

    // ---- (4) Scanlines. ----
    // Smooth |sin(π·y)| falls off to 0 between integer rows. Multiplied
    // by uScanlineDepth so the inter-line band darkens that much.
    float scanWave = abs(sin(p.y * PI));
    float scanline = 1.0 - uScanlineDepth * scanWave;

    // ---- (5) Composite. ----
    vec3 col = scene * mask * scanline;

    // ---- Phosphor tint glow. ----
    // A tiny emissive lift in the phosphor's own color — the faint
    // warmth a real CRT has even with black input.
    col += uPhosphorTint.rgb * uPhosphorTint.a * 0.04;

    // ---- Vignette at tube corners. ----
    // Falls in past the rectangular framebuffer edges, simulating the
    // CRT mask cutoff. Uses the same r² we computed for barrel.
    float vignette = 1.0 - smoothstep(0.55, 1.0, sqrt(r2));
    col *= vignette;

    col *= uIntensity;
    col = clamp(col, 0.0, 1.0);

    fragColor = vec4(col, 1.0);
}
