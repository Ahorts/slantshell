#version 440
// Frosted glass for SkewPanel: samples the wallpaper (aligned to the screen, "cover" fit), blurs it with a
// spiral of taps, and cuts the result to the panel's slanted outline. One pass, no extra layers.
// Rebuild after editing:   /usr/lib/qt6/bin/qsb --qt6 glass.frag -o glass.frag.qsb

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // panel size in px
    vec4 edges;         // top-left x, bottom-left x, top-right x, bottom-right x
    vec2 yRange;        // top y, bottom y
    vec2 origin;        // panel top-left on the screen, px
    vec2 screenSize;    // screen size, px
    vec2 imageSize;     // wallpaper image size, px
    float rb;           // radius of the rounded bottom corners, px (0 = square)
};

const float RADIUS = 22.0;      // blur radius, screen px
const float BRIGHTNESS = 0.9;
const float SATURATION = 1.1;

layout(binding = 1) uniform sampler2D src;

vec2 toUv(vec2 screenPx) {
    float s = max(screenSize.x / imageSize.x, screenSize.y / imageSize.y);
    vec2 off = (screenSize - imageSize * s) * 0.5;
    return (screenPx - off) / (imageSize * s);
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    float t = clamp((p.y - yRange.x) / max(yRange.y - yRange.x, 1.0), 0.0, 1.0);
    float xl = mix(edges.x, edges.y, t);
    float xr = mix(edges.z, edges.w, t);
    // rounded bottom corners: pull both sides in along a circle of radius rb
    float yy = p.y - (yRange.y - rb);
    if (rb > 0.5 && yy > 0.0) {
        float inset = rb - sqrt(max(rb * rb - yy * yy, 0.0));
        xl += inset;
        xr -= inset;
    }
    float a = clamp(p.x - xl + 0.5, 0.0, 1.0) * clamp(xr - p.x + 0.5, 0.0, 1.0);
    a *= step(yRange.x - 0.5, p.y) * step(p.y, yRange.y + 0.5);
    if (a <= 0.0) { fragColor = vec4(0.0); return; }

    vec2 sp = origin + p;
    const int TAPS = 16;
    vec3 acc = vec3(0.0);
    for (int i = 0; i < TAPS; i++) {
        float fi = float(i) + 0.5;
        float r = RADIUS * sqrt(fi / float(TAPS));
        float ang = fi * 2.39996323;
        acc += textureLod(src, toUv(sp + r * vec2(cos(ang), sin(ang))), 0.0).rgb;
    }
    vec3 c = acc / float(TAPS);
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(vec3(l), c, SATURATION) * BRIGHTNESS;
    // The wallpaper texture is decoded to linear on sampling; encode back so it matches what is on screen.
    c = pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
    fragColor = vec4(c, 1.0) * a * qt_Opacity;
}
