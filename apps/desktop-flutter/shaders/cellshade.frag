// Kirby comic-book overlay. One program with a uMode switch:
//   0 → halftone dots
//   1 → cross-hatch (two diagonal stripe sets ANDed)

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;          // surface size in px
uniform float uMode;         // 0 = halftone, 1 = hatch
uniform float uDotSize;      // pixel pitch of dots / hatch lines
uniform float uIntensity;    // 0..1 dot/line opacity
uniform vec4 uInkColor;      // dot/line colour
uniform vec4 uPaperColor;    // base background
uniform float uOutline;      // px of inset ink stripe (0 = none)
uniform float uHatchAngle;   // radians for cross-hatch rotation

out vec4 fragColor;

float halftoneMask(vec2 p, float pitch, float density) {
    // dot radius scales with density (not count) — matches real
    // comic-book halftones where darker tone = bigger dot
    vec2 cell = floor(p / pitch);
    vec2 uv = (p / pitch) - cell - 0.5;
    float d = length(uv);
    float r = density * 0.55;
    return 1.0 - smoothstep(r - 0.04, r + 0.04, d);
}

float hatchMask(vec2 p, float pitch, float ang) {
    // Two rotated stripe sets — a diamond/cross pattern emerges
    // where they overlap. Sin gives a smooth on/off curve so the
    // lines feather at the edges instead of aliasing.
    float c = cos(ang), s = sin(ang);
    vec2 r1 = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
    vec2 r2 = vec2(p.x * c + p.y * s, -p.x * s + p.y * c);
    float a = sin(r1.x * 6.2831853 / pitch);
    float b = sin(r2.y * 6.2831853 / pitch);
    return clamp(max(a, b) * 0.5 + 0.5, 0.0, 1.0);
}

float insetEdge(vec2 p, vec2 size, float w) {
    // Distance to nearest edge of the surface, clamped to [0, w].
    // Returns 1 inside the ink stripe, 0 outside.
    if (w < 0.5) return 0.0;
    float dx = min(p.x, size.x - p.x);
    float dy = min(p.y, size.y - p.y);
    float d = min(dx, dy);
    return 1.0 - smoothstep(w - 1.0, w + 1.0, d);
}

void main() {
    vec2 p = FlutterFragCoord();

    float mask;
    if (uMode < 0.5) {
        mask = halftoneMask(p, uDotSize, uIntensity);
    } else {
        mask = hatchMask(p, uDotSize, uHatchAngle) * uIntensity;
    }

    vec4 col = mix(uPaperColor, uInkColor, mask);

    // inset ink stripe = comic-panel border baked in
    float edge = insetEdge(p, uSize, uOutline);
    col = mix(col, uInkColor, edge);

    fragColor = col;
}
