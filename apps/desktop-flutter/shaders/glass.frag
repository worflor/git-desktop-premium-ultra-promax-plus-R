// iOS-26-style Liquid Glass, real optical transmission.
//
// This shader runs as an `ImageFilter.shader` on the BackdropFilter widget,
// so the engine auto-binds the live backdrop (everything painted behind
// the glass surface) to `uBackdrop` and writes the surface size into the
// first vec2 uniform `uSize`. That gives us a genuine forward-render of
// glass optics — not snapshot-based, not additive-only.
//
// Physical material parameters:
//   uIOR        — refractive index n. Drives Schlick F0, Cauchy dispersion,
//                 refractive displacement via Snell's law, and the
//                 lensmaker focal length that positions the internal caustic.
//   uRoughness  — GGX/Trowbridge-Reitz α. Drives microfacet specular
//                 lobe shape, Smith masking-shadowing, micro-grain.
//   uAbsorption — Beer-Lambert extinction per RGB channel. Applied along
//                 the optical path through the glass (interior SDF depth).
//
// Everything else derives from geometry (SDF), light direction, time, tilt.
//
// References:
//   Schlick (1994)          — Fresnel approximation
//   Walter et al. (2007)    — GGX microfacet BRDF
//   Cauchy (1836)           — n(λ) = A + B/λ²
//   Bouguer (1729)/Beer     — exponential attenuation
//   Snell (1621)            — refraction
//   Quilez                  — rounded-rect 2D SDF

#version 460 core
#include <flutter/runtime_effect.glsl>

// First uniform is vec2 by contract; Impeller's ImageFilter.shader writes
// the bound texture size into it automatically.
uniform vec2  uSize;

uniform vec4  uAbsorption;    // rgb: 1/px extinction; a: master strength
uniform vec4  uLightColor;    // light-source color (spec, rim, caustic)
uniform vec2  uLightDir;      // 2D direction TO the light (unit not required)
uniform vec2  uTilt;          // window-delta tilt, [-1..1]
uniform float uTime;
uniform float uIntensity;     // master output mix
uniform float uCornerRadius;  // SDF footprint radius (pixels)
uniform float uIOR;           // refractive index n
uniform float uRoughness;     // GGX α
uniform float uAnim;          // motion master (0..1)

// First sampler: Impeller binds the live backdrop here.
uniform sampler2D uBackdrop;

out vec4 fragColor;

const float PI       = 3.14159265358979;
const float TWO_PI   = 6.28318530717959;
const float TAP_STEP = 1.25663706;  // 2π / 5 — pentagonal angular step

// CIE standard-observer peak wavelengths (μm) — used by Cauchy dispersion.
const float LAMBDA_R = 0.611;
const float LAMBDA_G = 0.549;
const float LAMBDA_B = 0.464;
const float LAMBDA_D = 0.5876;  // Fraunhofer d-line reference

// Abbe number of BK7 crown glass. Anchors Cauchy B to n_d via
//     B ≈ (n_d − 1) · λ_d² / V_d
// so dispersion is a pure function of IOR.
const float ABBE_V = 64.17;

// ---- iq's rounded-rect SDF. ----
float sdRoundedRect(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// ---- Schlick Fresnel. ----
float fresnelSchlick(float cosTheta, float F0) {
    float m = clamp(1.0 - cosTheta, 0.0, 1.0);
    float m2 = m * m;
    return F0 + (1.0 - F0) * m2 * m2 * m;
}

// ---- GGX (Trowbridge-Reitz) normal distribution. ----
float ggxD(float NdotH, float alpha) {
    float a2 = alpha * alpha;
    float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / max(PI * d * d, 1e-8);
}

// ---- Schlick-GGX geometry term (k = α/2). ----
float smithG1(float NdotX, float alpha) {
    float k = alpha * 0.5;
    return NdotX / max(NdotX * (1.0 - k) + k, 1e-8);
}

// ---- Cauchy dispersion: δn per channel relative to green. ----
vec2 cauchyDeltaRB(float n) {
    float B       = (n - 1.0) * LAMBDA_D * LAMBDA_D / ABBE_V;
    float invLd2  = 1.0 / (LAMBDA_D * LAMBDA_D);
    float dR      = B * (1.0 / (LAMBDA_R * LAMBDA_R) - invLd2);
    float dG      = B * (1.0 / (LAMBDA_G * LAMBDA_G) - invLd2);
    float dB      = B * (1.0 / (LAMBDA_B * LAMBDA_B) - invLd2);
    return vec2(dR - dG, dB - dG);
}

// ---- Triangular-PDF hash noise. ----
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float triHash(vec2 p) {
    return hash21(p) + hash21(p + vec2(17.3, 9.7)) - 1.0;
}

void main() {
    vec2 p   = FlutterFragCoord();
    vec2 hsz = uSize * 0.5;
    vec2 cp  = p - hsz;
    vec2 uv  = p / uSize;

    // ---- SDF and interior depth. ----
    float rCorner = clamp(uCornerRadius, 0.0, min(hsz.x, hsz.y));
    float sd      = sdRoundedRect(cp, hsz, rCorner);
    if (sd > 0.5) { fragColor = vec4(0.0); return; }
    float dIn = max(-sd, 0.0);

    // ---- Normal from SDF gradient (central differences). ----
    // Unit-slope SDF ⇒ |grad| ≈ 1, direction points outward.
    float e = 1.0;
    vec2 grad = vec2(
        sdRoundedRect(cp + vec2(e, 0.0), hsz, rCorner)
            - sdRoundedRect(cp - vec2(e, 0.0), hsz, rCorner),
        sdRoundedRect(cp + vec2(0.0, e), hsz, rCorner)
            - sdRoundedRect(cp - vec2(0.0, e), hsz, rCorner)
    ) * 0.5;

    // ---- Hemispherical cap geometry. ----
    // R_dome = smallest footprint half-dim ⇒ sphere tangent at corners.
    // On the cap, |Nxy| = sin(θ_polar) = 1 − dIn/R_dome.
    float R_dome  = min(hsz.x, hsz.y);
    float rimFrac = 1.0 - clamp(dIn / R_dome, 0.0, 1.0);
    vec2  gradN   = grad / max(length(grad), 1e-4);
    vec2  nxy     = gradN * rimFrac;
    float nz      = sqrt(max(1.0 - dot(nxy, nxy), 0.0));
    vec3  N       = vec3(nxy, nz);

    // ---- Light vector (3D), drift + tilt. ----
    vec2  drift = vec2(sin(uTime * 0.618), cos(uTime * 0.382)) * 0.18 * uAnim;
    vec2  L2    = normalize(uLightDir + drift + uTilt * 0.4 * uAnim);
    vec3  L     = normalize(vec3(L2, 0.8));
    vec3  V     = vec3(0.0, 0.0, 1.0);
    vec3  H     = normalize(L + V);
    float NdotL = clamp(dot(N, L), 0.0, 1.0);
    float NdotV = clamp(dot(N, V), 0.0, 1.0);
    float NdotH = clamp(dot(N, H), 0.0, 1.0);
    float VdotH = clamp(dot(V, H), 0.0, 1.0);

    // ---- Material constants from IOR / roughness. ----
    float n     = max(uIOR, 1.0);
    float F0    = (n - 1.0) / (n + 1.0);
    F0          = F0 * F0;
    float alpha = max(uRoughness, 0.002);

    // ---- Refractive sampling of the live backdrop. ----
    // Thin-lens small-angle approximation: the lateral shift of a ray
    // refracting through glass of effective thickness d_eff is
    //     Δr = (n − 1) · tan(θ_i) · d_eff
    // tan(θ_i) = |Nxy| / Nz, direction = Nxy (outward-radial).
    // Dispersion: sample each channel at its own n(λ), using Cauchy δn.
    vec2  disp     = cauchyDeltaRB(n);
    float d_eff    = R_dome * 0.45;            // effective glass thickness (px)
    vec2  refrDir  = nxy / max(nz, 0.1);       // tan(θ_i) · direction
    vec2  baseUv   = uv - refrDir * (n - 1.0) * d_eff / uSize;
    vec2  uvR      = uv - refrDir * (n + disp.x - 1.0) * d_eff / uSize;
    vec2  uvB      = uv - refrDir * (n + disp.y - 1.0) * d_eff / uSize;

    // ---- Roughness-driven backdrop blur. ----
    // GGX roughness α controls not just the specular lobe but the
    // *transmission* lobe: polished glass passes sharp rays, rougher
    // glass scatters them into a cone. Implementation: 5-tap circular
    // kernel, per-pixel hash-rotated so neighbour averaging reads as
    // true blur. Each tap still uses its own channel's Cauchy UV so
    // dispersion and blur compose correctly. Polished glass (α→0) has
    // blurUV → 0 and all taps collapse to a single point.
    float rotAng = hash21(p) * TWO_PI;
    float blurPx = alpha * R_dome * 0.12;
    vec2  blurUV = vec2(blurPx) / uSize;

    vec3 refracted = vec3(0.0);
    for (int i = 0; i < 5; i++) {
        float a = rotAng + float(i) * TAP_STEP;
        vec2  o = vec2(cos(a), sin(a)) * blurUV;
        refracted.r += texture(uBackdrop, clamp(uvR    + o, vec2(0.0), vec2(1.0))).r;
        refracted.g += texture(uBackdrop, clamp(baseUv + o, vec2(0.0), vec2(1.0))).g;
        refracted.b += texture(uBackdrop, clamp(uvB    + o, vec2(0.0), vec2(1.0))).b;
    }
    refracted *= 0.2;  // ÷ 5

    // ---- Beer-Lambert with path-length correction. ----
    // Real optical path through the glass = geometric depth / cos(θ_t).
    // Approximate cos(θ_t) with Nz (clamped to avoid divergence at
    // grazing). Result: tinted glasses concentrate their tint toward the
    // rim where rays traverse the most material — the "thick-edge"
    // signature of real colored glass.
    vec3 transmission = exp(-uAbsorption.rgb * dIn * uAbsorption.a / max(nz, 0.1));
    vec3 transmitted  = refracted * transmission;

    // ---- GGX microfacet specular (reflective — no absorption). ----
    float D    = ggxD(NdotH, alpha);
    float G    = smithG1(NdotV, alpha) * smithG1(NdotL, alpha);
    float F_h  = fresnelSchlick(VdotH, F0);
    float spec = (D * G * F_h) / max(4.0 * NdotV * NdotL + 1e-4, 1e-4);
    vec3  specRGB = uLightColor.rgb * spec * NdotL;

    // ---- View-Fresnel rim (reflective — no absorption). ----
    float F_v = fresnelSchlick(NdotV, F0);
    vec3  rim = uLightColor.rgb * F_v;

    // ---- Focal caustic (transmitted — absorption applies). ----
    float f_focal    = R_dome / max(n - 1.0, 1e-3);
    vec2  focalPos   = -L2 * min(f_focal * 0.35, R_dome * 0.50);
    vec2  toFocal    = cp - focalPos;
    float focalSigma = R_dome * 0.28;
    float caustic    = exp(-dot(toFocal, toFocal) / (focalSigma * focalSigma))
                     * F0 * 4.0 * (1.0 - rimFrac);
    vec3  causticRGB = uLightColor.rgb * caustic * transmission;

    // ---- Micro-grain. ----
    float grain    = triHash(p);
    vec3  grainRGB = vec3(grain) * alpha * 0.12;

    // ---- Composite with asymmetric tonemap. ----
    // Base: transmitted backdrop, Fresnel-mixed with rim reflection. This
    // stays in [0,1] because both ends are bounded.
    vec3 base = mix(transmitted, rim, F_v);

    // HDR highlights (GGX D can spike >> 1 for small α). Pass through a
    // Reinhard soft-clip so spec never hard-clips to white while midtones
    // stay near-linear.
    vec3 hdr        = specRGB * 1.20 + causticRGB * 0.80;
    vec3 highlights = hdr / (vec3(1.0) + hdr);

    vec3 col = base + highlights + grainRGB;
    col = mix(transmitted, col, uIntensity);
    col = clamp(col, 0.0, 1.0);

    fragColor = vec4(col, 1.0);
}
