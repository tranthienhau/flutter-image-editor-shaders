#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uExposure;
uniform float uContrast;
uniform float uSaturation;
uniform float uTemperature;
uniform float uTint;
uniform float uShadows;
uniform float uHighlights;
uniform float uGrain;
uniform float uVignette;
uniform float uLutMix;
uniform float uTime;

uniform sampler2D uImage;
uniform sampler2D uLut;

out vec4 fragColor;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec3 applyTonecurve(vec3 c, float shadows, float highlights) {
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    float sMask = pow(1.0 - l, 2.0);
    float hMask = pow(l, 2.0);
    c += shadows * sMask;
    c += highlights * hMask;
    return c;
}

vec3 applyLut(vec3 color, sampler2D lut) {
    float blueIdx = color.b * 63.0;
    float bL = floor(blueIdx);
    float bH = ceil(blueIdx);
    float mixAmt = blueIdx - bL;

    vec2 quadL;
    quadL.y = floor(bL / 8.0);
    quadL.x = bL - quadL.y * 8.0;

    vec2 quadH;
    quadH.y = floor(bH / 8.0);
    quadH.x = bH - quadH.y * 8.0;

    vec2 tex1 = vec2(
        quadL.x * 0.125 + 0.5 / 512.0 + (0.125 - 1.0 / 512.0) * color.r,
        quadL.y * 0.125 + 0.5 / 512.0 + (0.125 - 1.0 / 512.0) * color.g
    );
    vec2 tex2 = vec2(
        quadH.x * 0.125 + 0.5 / 512.0 + (0.125 - 1.0 / 512.0) * color.r,
        quadH.y * 0.125 + 0.5 / 512.0 + (0.125 - 1.0 / 512.0) * color.g
    );

    vec3 c1 = texture(lut, tex1).rgb;
    vec3 c2 = texture(lut, tex2).rgb;
    return mix(c1, c2, mixAmt);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec3 color = texture(uImage, uv).rgb;

    color *= pow(2.0, uExposure);

    color = (color - 0.5) * (1.0 + uContrast) + 0.5;

    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, 1.0 + uSaturation);

    color.r += uTemperature * 0.1;
    color.b -= uTemperature * 0.1;
    color.g += uTint * 0.1;

    color = applyTonecurve(color, uShadows, uHighlights);

    color = clamp(color, 0.0, 1.0);

    if (uLutMix > 0.001) {
        vec3 lutColor = applyLut(color, uLut);
        color = mix(color, lutColor, uLutMix);
    }

    float n = hash(uv * uSize + uTime) - 0.5;
    color += n * uGrain;

    vec2 vUv = uv - 0.5;
    float vig = 1.0 - dot(vUv, vUv) * uVignette * 2.0;
    color *= clamp(vig, 0.0, 1.0);

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
