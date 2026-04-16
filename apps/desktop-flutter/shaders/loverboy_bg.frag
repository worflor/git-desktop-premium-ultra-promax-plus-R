// Loverboy background. Game-of-Life-ish cellular grid with a parallax
// lighting trick on each cell's edges and a set of dead cells that
// shift as you drag the window.

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2  uSize;
uniform float uIntensity;
uniform float uTime;
uniform vec2  uTilt;

out vec4 fragColor;

float h21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    return fract((p.x + 19.19) * p.y * 127.1);
}

void main() {
    vec2 fc = FlutterFragCoord() + uTilt * 6.0;
    vec2 uv = fc / uSize;

    float cellPx  = clamp(min(uSize.x, uSize.y) / 22.0, 10.0, 38.0);
    float invCell = 1.0 / cellPx;

    // fract(gridF) reuses the floor above as gridF - g.
    vec2 gridF = fc * invCell;
    vec2 g     = floor(gridF);
    vec2 lcl   = gridF - g;

    float tStep = floor(uTime * 0.5555556);

    // Regional + local hash gate. The regional hash is 3x coarser, so
    // alive cells cluster in blobs instead of salt-and-pepper noise.
    float regional = h21(floor(g * 0.333333) + tStep * vec2(7.13, 3.97));
    float local    = h21(g                   + tStep * vec2(13.71, 7.31));
    float alive    = step(0.45, regional) * step(0.55, local);

    vec2 inside = step(vec2(0.08), lcl) * step(lcl, vec2(0.92));
    float inner = inside.x * inside.y;

    // Polynomial approximation of exp(-|d|²·k), squared falloff.
    vec2  d    = lcl - 0.5;
    float t    = max(0.0, 1.0 - dot(d, d) * 5.0);
    float glow = t * t * 0.55;

    float combined = alive * (inner * 0.85 + glow);

    // Light direction. Base is top-left; tilt rotates it. Each edge
    // tests step(L.y, 0) / step(L.x, 0) to decide rim vs ink.
    vec2 L = normalize(uTilt * 1.5 + vec2(-0.7, -0.7));
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

    float rim = max(max(eTopR * litTop,    eLeftR * litLeft),
                    max(eBottomR * litBottom, eRightR * litRight));
    float ink = max(max(eTopI * (1.0 - litTop),    eLeftI * (1.0 - litLeft)),
                    max(eBottomI * (1.0 - litBottom), eRightI * (1.0 - litRight)));

    // Cell-centre sampled tint so every pixel in a cell gets the same
    // colour, no gradient across the square.
    vec2  cellCenterUV = (g + 0.5) * cellPx / uSize;
    vec3  pink    = vec3(1.000, 0.431, 0.706);
    vec3  violet  = vec3(0.714, 0.384, 0.902);
    float tint    = fract(cellCenterUV.x * 0.5 + cellCenterUV.y * 0.2 + uTime * 0.03);
    vec3  cellCol = mix(pink, violet, tint);

    vec3 rimCol = mix(cellCol, vec3(1.0), 0.45);
    vec3 inkCol = cellCol * 0.12;

    float gLine = step(0.96, max(lcl.x, lcl.y)) * 0.10;

    vec3  base = cellCol * combined;
    float rimA = alive * rim * 0.85;
    float inkA = alive * ink * 0.92;
    vec3  col  = mix(base, rimCol, rimA);
    col        = mix(col,  inkCol, inkA);
    col       += vec3(gLine * 0.7, gLine * 0.05, gLine * 0.4);

    float alpha = clamp(combined + gLine, 0.0, 1.0) * uIntensity;

    // Dead cells. Each cell has a tilt threshold (hash of its position);
    // a per-region flow direction projects the tilt onto a signal; dead
    // when signal > threshold. Regional hash dominates so dead cells
    // cluster, and each region has its own flow direction so the cascade
    // snakes rather than sweeping uniformly.
    vec2  clusterG      = floor(g * 0.25);
    float regionalPhase = h21(clusterG + vec2(31.7, 47.3));
    float localPhase    = h21(g        + vec2(71.3, 89.1));
    float cellThresh    = mix(regionalPhase, localPhase, 0.3) * 1.6 - 0.3;

    float regionAngle = h21(clusterG + vec2(11.1, 13.7)) * 6.2831853;
    vec2  flowDir     = vec2(cos(regionAngle), sin(regionAngle));

    // Signal sampled at cell centre so step() flips the whole square,
    // never mid-cell.
    float tiltSignal = dot(uTilt * 1.8, flowDir)
                     + dot(cellCenterUV - 0.5, flowDir) * 1.2;

    float dead = step(cellThresh, tiltSignal) * inner;

    col   = mix(col,   vec3(0.0), dead);
    alpha = mix(alpha, uIntensity, dead);

    fragColor = vec4(col * uIntensity, alpha);
}
