// Nacre iridescence via actual thin-film interference physics.
//
// Real mother-of-pearl iridescence comes from light reflecting off the
// top AND bottom surfaces of a microscopic aragonite layer. The two
// reflected waves interfere — constructive where path difference matches
// an integer wavelength, destructive where it matches half-wavelengths.
// Because different wavelengths satisfy the condition at different
// thicknesses (and different viewing angles), the perceived color shifts
// with both surface geometry AND view direction.
//
// Path difference for reflection off a thin film:
//     Δ = 2·n·d·cos(θ_t) + λ/2
// where n is the film's refractive index, d is thickness, θ_t is the
// refracted angle (by Snell's law), and the +λ/2 is the phase flip from
// the first reflection off a denser medium.
//
// Constructive peaks occur at Δ = m·λ for integer m. This shader samples
// the interference amplitude at the CIE standard-observer RGB peaks and
// blends into the base pearl color. The `uTilt` uniform drives the
// incidence angle — drag the window and the color bands slide through
// the spectrum the way actual nacre shifts as you move past it.
//
// References:
//   Thomas Young (1802)       — thin-film interference
//   Snell (1621)              — refraction at an interface
//   Schott / CIE (1931)       — peak wavelengths
//   Aragonite index ≈ 1.56    — nacre's actual mineral

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2  uSize;
uniform float uIntensity;
uniform float uHueOffset;     // biases local thickness (was static hue shift)
uniform vec4  uPearlBase;
uniform vec2  uTilt;
uniform float uTime;

out vec4 fragColor;

const float PI     = 3.14159265358979;
const float TWO_PI = 6.28318530717959;

// Film refractive index. Aragonite — the calcium-carbonate crystal
// that forms nacre layers in real shells.
const float N_FILM = 1.56;

// Wavelengths in nm for R/G/B peaks of the CIE standard observer.
const float LAMBDA_R = 611.0;
const float LAMBDA_G = 549.0;
const float LAMBDA_B = 464.0;

// Thickness range (nm) spanning several interference orders so the
// surface cycles through the full visible spectrum as d varies.
const float D_MIN = 280.0;
const float D_MAX = 820.0;

// ---- 2D value noise for organic thickness variation. ----
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);  // Hermite smoothstep
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void main() {
    vec2 uv = FlutterFragCoord() / uSize;

    // ---- Local film thickness (nm). ----
    // Two-octave value noise drifts slowly with time, giving the pearl
    // its organic, "breathing" texture. uHueOffset biases the thickness
    // so themes can dial the dominant spectral region.
    float n1 = valueNoise(uv * 5.0  + vec2(uTime * 0.04, uTime * 0.03));
    float n2 = valueNoise(uv * 13.0 + vec2(-uTime * 0.02, uTime * 0.05));
    float nm = n1 * 0.65 + n2 * 0.35;
    float d  = mix(D_MIN, D_MAX, fract(nm + uHueOffset));

    // ---- Incidence angle from tilt + mild position parallax. ----
    // The tilt vector becomes sin(θ_i) — no tilt means looking straight
    // down the normal, full tilt gives ~30° grazing angle. Position adds
    // a mild per-pixel offset so curved surfaces (a glass pane seen from
    // the side) get a natural angular gradient across the face.
    vec2  viewTilt    = uTilt * 0.5 + (uv - 0.5) * 0.18;
    float sinSqTheta  = min(dot(viewTilt, viewTilt), 0.25);

    // ---- Snell's law ⇒ cos(θ_t). ----
    float sinSqThetaT = sinSqTheta / (N_FILM * N_FILM);
    float cosThetaT   = sqrt(1.0 - sinSqThetaT);

    // ---- Path difference through the film. ----
    float delta = 2.0 * N_FILM * d * cosThetaT;  // nm

    // ---- Wavelength-dependent interference amplitudes. ----
    // Amplitude = (1 + cos(φ))/2 ∈ [0,1]. The +π comes from the
    // half-wave phase flip at the film's upper surface (reflection off
    // a denser medium). Without it, constructive/destructive order flips
    // and the colors land in the wrong place.
    float phiR = TWO_PI * delta / LAMBDA_R + PI;
    float phiG = TWO_PI * delta / LAMBDA_G + PI;
    float phiB = TWO_PI * delta / LAMBDA_B + PI;

    vec3 iridescence = vec3(
        (1.0 + cos(phiR)) * 0.5,
        (1.0 + cos(phiG)) * 0.5,
        (1.0 + cos(phiB)) * 0.5
    );

    // ---- Saturation lift. ----
    // Raw thin-film output has a neutral-gray DC component (all three
    // channels contribute some amplitude at any thickness). Subtracting
    // the minimum strips it, leaving the chromatic peak. 0.88 keeps a
    // hint of base luminance so the darker side of the spectrum doesn't
    // read as black.
    float minC = min(iridescence.r, min(iridescence.g, iridescence.b));
    iridescence = iridescence - vec3(minC * 0.88);

    // Boost so after the subtraction the peak still reads as ~1.
    iridescence *= 1.7;

    // ---- Mix into pearl base. ----
    vec3 col = mix(uPearlBase.rgb, uPearlBase.rgb + iridescence, uIntensity);

    fragColor = vec4(col, uPearlBase.a);
}
