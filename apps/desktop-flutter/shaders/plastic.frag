// Plastic gloss for Bibble. Mono-hue surface + moving specular band +
// bottom inner shadow + magenta fresnel rim. Unlike iridescent (hue
// cycles across position/time), this keeps the color constant and
// walks the light across it.

#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uIntensity;
uniform vec4 uBase;
uniform vec4 uHighlight;
uniform vec4 uShadow;
uniform vec2 uTilt;
uniform float uTime;
uniform float uEdgePx;

out vec4 fragColor;

void main() {
    vec2 frag = FlutterFragCoord();
    vec2 uv = frag / uSize;

    // diagonal highlight band, slow time drift + window tilt
    float drift = uTime * 0.015 + uTilt.x * 0.28 + uTilt.y * 0.12;
    vec2 dir = normalize(vec2(1.0, 0.9));
    float d = dot(uv, dir) - 0.45 - drift;
    float band = exp(-pow(d * 4.4, 2.0));

    // bottom-right inner shadow — colored, not black
    float shadeX = smoothstep(0.35, 1.05, uv.x);
    float shadeY = smoothstep(0.40, 1.10, uv.y);
    float shade = shadeX * shadeY * 0.65;

    // fresnel rim. squared falloff so it reads as a molded lip rather
    // than an atmospheric halo.
    vec2 edgeDistPx = min(frag, uSize - frag);
    float edgePx = min(edgeDistPx.x, edgeDistPx.y);
    float rim = 1.0 - smoothstep(0.0, uEdgePx, edgePx);
    rim = rim * rim;

    vec3 col = uBase.rgb;
    col = mix(col, uShadow.rgb, shade * uShadow.a * uIntensity);
    col += uHighlight.rgb * band * uIntensity * 0.42;
    col = mix(col, uHighlight.rgb, rim * uHighlight.a * uIntensity * 0.75);

    fragColor = vec4(col, uBase.a);
}
