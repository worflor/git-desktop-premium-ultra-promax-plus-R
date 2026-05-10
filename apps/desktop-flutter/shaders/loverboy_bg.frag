// Loverboy background — Conway's Game of Life, crossfaded.
//
// Binary B3/S23 rules (Conway 1970), sampled from the previous frame
// via `uPrevious`. Generations advance at 3Hz (333ms/gen) — slow
// enough to read as ambient, fast enough to feel alive. Between
// generations the shader CROSSFADES from the captured snapshot to
// the newly-computed state using `genProgress ∈ [0, 1]`, so the
// visual transitions are continuous without the hard pop of a naive
// redraw-on-tick renderer.
//
// Logos-y touches:
//   • Slow sine drift of the ambient spontaneous-birth rate so the
//     board has "seasons" — periods of dense perturbation interleaved
//     with quieter stretches (history-aware rhythm).
//   • Pixel-accurate crossfade: each pixel fades from its previous-
//     snapshot value to its new-render value, preserving the tile
//     geometry through the transition.
//   • The usual tiled visual language: adaptive cells, inner glow,
//     rim/ink lighting rotating with tilt, pink/violet tint, grid
//     lines, and the regional blacked-out cascade.
//
// Rules: B3/S23. Gardner, "Mathematical Games" (Sci. Am., Oct 1970).

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2  uSize;
uniform float uIntensity;
uniform float uTime;
uniform vec2  uTilt;

// Seconds since the last snapshot was captured (same clock as uTime).
// Drives the crossfade interpolation across the generation interval.
// Negative means "no snapshot yet" — triggers initial seeding.
uniform float uSnapshotTime;

uniform sampler2D uPrevious;

out vec4 fragColor;

const float ALIVE_THRESH = 0.30;
const float GEN_INTERVAL = 0.333;  // 3Hz — keep in sync with Dart throttle

float h21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    return fract((p.x + 19.19) * p.y * 127.1);
}

void main() {
    vec2 fc       = FlutterFragCoord() + uTilt * 6.0;
    float cellPx  = clamp(min(uSize.x, uSize.y) / 22.0, 10.0, 38.0);
    float invCell = 1.0 / cellPx;

    vec2 gridF = fc * invCell;
    vec2 g     = floor(gridF);
    vec2 lcl   = gridF - g;

    vec2 cellCenterUV = (g + 0.5) * cellPx / uSize;
    vec2 cellStepUV   = vec2(cellPx) / uSize;

    // ---- Conway step from previous snapshot. ----
    vec4  prevSelf = texture(uPrevious, cellCenterUV);
    float self     = step(ALIVE_THRESH, prevSelf.a);

    float n = 0.0;
    n += step(ALIVE_THRESH, texture(uPrevious, cellCenterUV + vec2(-cellStepUV.x, -cellStepUV.y)).a);
    n += step(ALIVE_THRESH, texture(uPrevious, cellCenterUV + vec2( 0.0,          -cellStepUV.y)).a);
    n += step(ALIVE_THRESH, texture(uPrevious, cellCenterUV + vec2( cellStepUV.x, -cellStepUV.y)).a);
    n += step(ALIVE_THRESH, texture(uPrevious, cellCenterUV + vec2(-cellStepUV.x,  0.0)).a);
    n += step(ALIVE_THRESH, texture(uPrevious, cellCenterUV + vec2( cellStepUV.x,  0.0)).a);
    n += step(ALIVE_THRESH, texture(uPrevious, cellCenterUV + vec2(-cellStepUV.x,  cellStepUV.y)).a);
    n += step(ALIVE_THRESH, texture(uPrevious, cellCenterUV + vec2( 0.0,           cellStepUV.y)).a);
    n += step(ALIVE_THRESH, texture(uPrevious, cellCenterUV + vec2( cellStepUV.x,  cellStepUV.y)).a);

    float survive = step(1.5, n) * (1.0 - step(3.5, n));  // 2 ≤ n ≤ 3
    float birth   = step(2.5, n) * (1.0 - step(3.5, n));  // n == 3
    float alive   = mix(birth, survive, self);

    // First-gen seeding only (sentinel uSnapshotTime < 0).
    float firstGen = 1.0 - step(0.0, uSnapshotTime);
    float seedHash = h21(g * 1.37 + 7.1);
    float seeded   = step(0.60, seedHash) * firstGen;
    alive = max(alive, seeded);

    // Ambient spontaneous birth as 2×2 BLOCKS, not single cells.
    // A 2×2 block is Conway's smallest still-life — each cell has
    // exactly 3 neighbours (the other 3 in the block) so B3/S23
    // keeps it alive indefinitely. Single-cell births, by contrast,
    // have 0 neighbours and die in one gen — producing exactly the
    // flashing-in-and-out we want to eliminate.
    //
    // Implementation: hash each coarse 2×2 region (g / 2). When that
    // block "fires", every cell in that region is set alive — the
    // four cells form a stable block that persists until another
    // pattern collides with it.
    //
    // Rate modulated by a slow sine so perturbation density breathes
    // over ~78s cycles — Logos-flavoured rhythm.
    float genClock     = floor(uSnapshotTime / GEN_INTERVAL);
    float seasonPhase  = sin(uSnapshotTime * 0.08) * 0.006;
    float blockThresh  = 0.988 - seasonPhase;
    vec2  coarse       = floor(g * 0.5);
    float blockSeed    = h21(coarse + vec2(genClock * 0.31, genClock * 0.59));
    float blockFires   = step(blockThresh, blockSeed);
    alive = max(alive, blockFires * (1.0 - self));

    // ---- Tiled visual language. ----
    vec2  inside = step(vec2(0.08), lcl) * step(lcl, vec2(0.92));
    float inner  = inside.x * inside.y;

    vec2  d    = lcl - 0.5;
    float t    = max(0.0, 1.0 - dot(d, d) * 5.0);
    float glow = t * t * 0.55;

    float combined = alive * (inner * 0.85 + glow);

    vec2  L         = normalize(uTilt * 1.5 + vec2(-0.7, -0.7));
    float litTop    = step(L.y, 0.0);
    float litLeft   = step(L.x, 0.0);
    float litBottom = 1.0 - litTop;
    float litRight  = 1.0 - litLeft;

    const float RIM_T = 0.03;
    const float INK_T = 0.06;
    float eTopR    = step(lcl.y, 0.08 + RIM_T) * inner;
    float eLeftR   = step(lcl.x, 0.08 + RIM_T) * inner;
    float eBottomR = step(0.92 - RIM_T, lcl.y) * inner;
    float eRightR  = step(0.92 - RIM_T, lcl.x) * inner;
    float eTopI    = step(lcl.y, 0.08 + INK_T) * inner;
    float eLeftI   = step(lcl.x, 0.08 + INK_T) * inner;
    float eBottomI = step(0.92 - INK_T, lcl.y) * inner;
    float eRightI  = step(0.92 - INK_T, lcl.x) * inner;

    float rim = max(max(eTopR    * litTop,    eLeftR    * litLeft),
                    max(eBottomR * litBottom, eRightR   * litRight));
    float ink = max(max(eTopI    * (1.0 - litTop),    eLeftI    * (1.0 - litLeft)),
                    max(eBottomI * (1.0 - litBottom), eRightI   * (1.0 - litRight)));

    vec3  pink    = vec3(1.000, 0.431, 0.706);
    vec3  violet  = vec3(0.714, 0.384, 0.902);
    float tint    = fract(cellCenterUV.x * 0.5 + cellCenterUV.y * 0.2 + uTime * 0.03);
    vec3  cellCol = mix(pink, violet, tint);

    vec3 rimCol = mix(cellCol, vec3(1.0), 0.45);
    vec3 inkCol = cellCol * 0.12;

    float gLine = step(0.96, max(lcl.x, lcl.y)) * 0.10;

    vec3 newCol = cellCol * combined;
    newCol = mix(newCol, rimCol, alive * rim * 0.85);
    newCol = mix(newCol, inkCol, alive * ink * 0.92);
    newCol += vec3(gLine * 0.7, gLine * 0.05, gLine * 0.4);

    float newAlpha = clamp(combined + gLine, 0.0, 1.0);

    // ---- Blacked-out cascade (visual overlay; alpha preserved). ----
    vec2  clusterG      = floor(g * 0.25);
    float regionalPhase = h21(clusterG + vec2(31.7, 47.3));
    float localPhase    = h21(g        + vec2(71.3, 89.1));
    float cellThresh    = mix(regionalPhase, localPhase, 0.3) * 1.6 - 0.3;

    float regionAngle = h21(clusterG + vec2(11.1, 13.7)) * 6.2831853;
    vec2  flowDir     = vec2(cos(regionAngle), sin(regionAngle));

    float tiltSignal = dot(uTilt * 1.8, flowDir)
                     + dot(cellCenterUV - 0.5, flowDir) * 1.2;
    float blackedOut = step(cellThresh, tiltSignal) * inner * alive;

    newCol   = mix(newCol,   vec3(0.0), blackedOut);
    newAlpha = mix(newAlpha, 1.0,       blackedOut);

    // ---- Pixel-accurate crossfade to new state. ----
    // Sample the previous snapshot at THIS pixel's UV. Previous snapshot
    // is stored PREMULTIPLIED (see output below), so prevPixel.rgb is
    // already col*alpha from last gen. newCol is non-premul here, so
    // we premultiply it (by newAlpha) before mixing — keeps the crossfade
    // in a single colour space (premul) end-to-end.
    vec2  uvPixel   = FlutterFragCoord() / uSize;
    vec4  prevPixel = texture(uPrevious, uvPixel);

    float genProgress = clamp((uTime - uSnapshotTime) / GEN_INTERVAL, 0.0, 1.0);
    float gp          = smoothstep(0.0, 1.0, genProgress);

    float finalAlpha    = mix(prevPixel.a, newAlpha * uIntensity, gp);
    vec3  newColPremul  = newCol * uIntensity * newAlpha;
    vec3  finalColPremul = mix(prevPixel.rgb, newColPremul, gp);

    // ---- Ambient motion layer (no CA impact, visual polish only). ----
    // Slow diagonal "light wave" sweeping across the board. Direction
    // tilts subtly with window position. Added in premul space, so the
    // contribution is proportional to alpha — dead regions stay clean.
    vec2  waveDir  = normalize(vec2(0.707, 0.707) + uTilt * 0.35);
    vec2  uvN      = FlutterFragCoord() / uSize;
    float waveAxis = dot(uvN, waveDir);
    float wavePos  = fract(uTime * 0.09 - waveAxis);
    float waveAmp  = exp(-pow(wavePos - 0.5, 2.0) * 16.0);
    finalColPremul += cellCol * waveAmp * finalAlpha * 0.28;

    // ---- Global breath. ----
    // Multiplies the premultiplied colour only — alpha is untouched so
    // compositing stays correct.
    finalColPremul *= 1.0 + sin(uTime * 0.40) * 0.07;

    fragColor = vec4(finalColPremul, finalAlpha);
}
