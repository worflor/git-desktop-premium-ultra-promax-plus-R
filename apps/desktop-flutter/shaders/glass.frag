// Liquid Glass — thick, dense optical surface.
//
// ImageFilter.shader on BackdropFilter. Impeller binds the live
// backdrop to uBackdrop and writes surface size into uSize.
//
// Uniforms:
//   uIOR        — refractive index. Fresnel, Cauchy, Snell, caustic.
//   uRoughness  — GGX α. Specular lobe + transmission blur.
//   uAbsorption — Beer-Lambert per-channel extinction along SDF depth.
//
// v2 over glass_v1_clear:
//   parabolic thickness, center lensing, env reflection at rim,
//   forward scatter, per-pixel Abbe from backdrop luminance,
//   double refraction (front + back surface approx).

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2  uSize;

uniform vec4  uAbsorption;
uniform vec4  uLightColor;
uniform vec2  uLightDir;
uniform vec2  uTilt;
uniform float uTime;
uniform float uIntensity;
uniform float uCornerRadius;
uniform float uIOR;
uniform float uRoughness;
uniform float uAnim;

uniform sampler2D uBackdrop;

out vec4 fragColor;

const float PI       = 3.14159265358979;
const float TWO_PI   = 6.28318530717959;
const float TAP_STEP = 1.25663706;

const float LAMBDA_R = 0.611;
const float LAMBDA_G = 0.549;
const float LAMBDA_B = 0.464;
const float LAMBDA_D = 0.5876;

// Per-pixel Abbe. Dark backdrop → low (rainbow fringe has contrast).
// Bright backdrop → high (fringe vanishes). Wrong physics, right feel.
const float ABBE_LO = 20.0;
const float ABBE_HI = 72.0;

float sdRoundedRect(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

float fresnelSchlick(float cosTheta, float F0) {
    float m = clamp(1.0 - cosTheta, 0.0, 1.0);
    float m2 = m * m;
    return F0 + (1.0 - F0) * m2 * m2 * m;
}

float ggxD(float NdotH, float alpha) {
    float a2 = alpha * alpha;
    float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / max(PI * d * d, 1e-8);
}

float smithG1(float NdotX, float alpha) {
    float k = alpha * 0.5;
    return NdotX / max(NdotX * (1.0 - k) + k, 1e-8);
}

vec2 cauchyDeltaRB(float n, float abbeV) {
    float B      = (n - 1.0) * LAMBDA_D * LAMBDA_D / max(abbeV, 1.0);
    float invLd2 = 1.0 / (LAMBDA_D * LAMBDA_D);
    float dR     = B * (1.0 / (LAMBDA_R * LAMBDA_R) - invLd2);
    float dG     = B * (1.0 / (LAMBDA_G * LAMBDA_G) - invLd2);
    float dB     = B * (1.0 / (LAMBDA_B * LAMBDA_B) - invLd2);
    return vec2(dR - dG, dB - dG);
}

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

    // SDF + depth.
    float rCorner = clamp(uCornerRadius, 0.0, min(hsz.x, hsz.y));
    float sd      = sdRoundedRect(cp, hsz, rCorner);
    if (sd > 0.5) { fragColor = vec4(0.0); return; }
    float dIn = max(-sd, 0.0);

    // Normal from SDF gradient.
    float e = 1.0;
    vec2 grad = vec2(
        sdRoundedRect(cp + vec2(e, 0.0), hsz, rCorner)
            - sdRoundedRect(cp - vec2(e, 0.0), hsz, rCorner),
        sdRoundedRect(cp + vec2(0.0, e), hsz, rCorner)
            - sdRoundedRect(cp - vec2(0.0, e), hsz, rCorner)
    ) * 0.5;

    // Hemisphere cap.
    float R_dome  = min(hsz.x, hsz.y);
    float rimFrac = 1.0 - clamp(dIn / R_dome, 0.0, 1.0);
    vec2  gradN   = grad / max(length(grad), 1e-4);
    vec2  nxy     = gradN * rimFrac;
    float nz      = sqrt(max(1.0 - dot(nxy, nxy), 0.0));
    vec3  N       = vec3(nxy, nz);

    // Parabolic lens cross-section. exp < 1 = fat center, steep rim.
    float t_norm = clamp(dIn / R_dome, 1e-4, 1.0);
    float d_eff  = R_dome * 1.8 * pow(t_norm, 0.42);

    // Light.
    vec2  drift = vec2(sin(uTime * 0.618), cos(uTime * 0.382)) * 0.18 * uAnim;
    vec2  L2    = normalize(uLightDir + drift + uTilt * 0.4 * uAnim);
    vec3  L     = normalize(vec3(L2, 0.8));
    vec3  V     = vec3(0.0, 0.0, 1.0);
    vec3  H     = normalize(L + V);
    float NdotL = clamp(dot(N, L), 0.0, 1.0);
    float NdotV = clamp(dot(N, V), 0.0, 1.0);
    float NdotH = clamp(dot(N, H), 0.0, 1.0);
    float VdotH = clamp(dot(V, H), 0.0, 1.0);

    float n     = max(uIOR, 1.0);
    float F0    = (n - 1.0) / (n + 1.0);
    F0          = F0 * F0;
    float alpha = max(uRoughness, 0.002);

    // Lensing — thick convex glass magnifies at center.
    float lensing = 0.08 * (n - 1.0) * t_norm;
    vec2  lensUV  = uv + (vec2(0.5) - uv) * lensing;

    // Per-pixel Abbe from backdrop luminance.
    vec3  bgSample  = texture(uBackdrop, lensUV).rgb;
    float bgLum     = dot(bgSample, vec3(0.2126, 0.7152, 0.0722));
    float localAbbe = mix(ABBE_LO, ABBE_HI, bgLum);

    // Double refraction (front + back surface approx).
    vec2  disp    = cauchyDeltaRB(n, localAbbe);
    vec2  refrDir = nxy / max(nz, 0.1);

    vec2 frontOff = refrDir * (n - 1.0) * d_eff / uSize;
    vec2 backOff  = -refrDir * (n - 1.0) * d_eff * 0.30 / uSize;
    vec2 totalOff = frontOff + backOff;

    vec2 baseUv = lensUV - totalOff;
    vec2 uvR    = lensUV - (refrDir * (n + disp.x - 1.0) * d_eff / uSize)
                         - backOff;
    vec2 uvB    = lensUV - (refrDir * (n + disp.y - 1.0) * d_eff / uSize)
                         - backOff;

    // 5-tap blur scaled by roughness.
    float rotAng = hash21(p) * TWO_PI;
    float blurPx = alpha * R_dome * 0.08;
    vec2  blurUV = vec2(blurPx) / uSize;

    vec3 refracted = vec3(0.0);
    for (int i = 0; i < 5; i++) {
        float a = rotAng + float(i) * TAP_STEP;
        vec2  o = vec2(cos(a), sin(a)) * blurUV;
        refracted.r += texture(uBackdrop, clamp(uvR    + o, vec2(0.0), vec2(1.0))).r;
        refracted.g += texture(uBackdrop, clamp(baseUv + o, vec2(0.0), vec2(1.0))).g;
        refracted.b += texture(uBackdrop, clamp(uvB    + o, vec2(0.0), vec2(1.0))).b;
    }
    refracted *= 0.2;

    // Beer-Lambert. 1.4× boost + low nz clamp = dark thick edges.
    vec3 transmission = exp(-uAbsorption.rgb * dIn * uAbsorption.a * 1.4 / max(nz, 0.08));
    vec3 transmitted  = refracted * transmission;

    // Forward scatter — internal glow from the volume.
    float scatterDepth = 1.0 - exp(-dIn * uAbsorption.a * 0.6);
    vec3  scatterTint  = vec3(1.0) - uAbsorption.rgb * 0.4;
    vec3  scatter      = scatterTint * scatterDepth * 0.12 * uLightColor.rgb;

    // GGX specular.
    float D    = ggxD(NdotH, alpha);
    float G    = smithG1(NdotV, alpha) * smithG1(NdotL, alpha);
    float F_h  = fresnelSchlick(VdotH, F0);
    float spec = (D * G * F_h) / max(4.0 * NdotV * NdotL + 1e-4, 1e-4);
    vec3  specRGB = uLightColor.rgb * spec * NdotL;

    // Rim — sample backdrop at reflected offset, not a flat color.
    float F_v    = fresnelSchlick(NdotV, F0);
    vec2  reflUV = uv + nxy * 0.20;
    vec3  envRef = texture(uBackdrop, clamp(reflUV, vec2(0.0), vec2(1.0))).rgb;
    vec3  rim    = envRef * uLightColor.rgb * 1.15;

    // Top-edge sheen (y-down screen space: N.y > 0 = top rim).
    float topSheen = clamp(N.y * 0.5 + 0.5, 0.0, 1.0);
    topSheen *= rimFrac * rimFrac;
    vec3  sheenRGB = uLightColor.rgb * topSheen * 0.25;

    // Caustic.
    float f_focal    = R_dome / max(n - 1.0, 1e-3);
    vec2  focalPos   = -L2 * min(f_focal * 0.35, R_dome * 0.45);
    vec2  toFocal    = cp - focalPos;
    float focalSigma = R_dome * 0.20;
    float caustic    = exp(-dot(toFocal, toFocal) / (focalSigma * focalSigma))
                     * F0 * 6.0 * (1.0 - rimFrac);
    vec3  causticRGB = uLightColor.rgb * caustic * transmission;

    // Grain.
    float grain    = triHash(p);
    vec3  grainRGB = vec3(grain) * alpha * 0.08;

    // Composite.
    vec3 base = mix(transmitted, rim, F_v * 0.75) + scatter + sheenRGB;

    vec3 hdr        = specRGB * 1.40 + causticRGB * 1.0;
    vec3 highlights = hdr / (vec3(1.0) + hdr);

    vec3 col = base + highlights + grainRGB;
    col = mix(transmitted, col, uIntensity);
    col = clamp(col, 0.0, 1.0);

    fragColor = vec4(col, 1.0);
}
