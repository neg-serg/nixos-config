#version 440 core
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform qt_ubuf {
    vec4 params0; // x=iTime, y=iRadius, z=cx, w=cy
    vec4 iColor;
};

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }

void main() {
    float t = params0.x;
    float r = params0.y;
    vec2 center = vec2(params0.z, params0.w);
    vec2 pos = qt_TexCoord0 - center;
    float dist = length(pos);
    float angle = atan(pos.y + 1e-6, pos.x + 1e-6);

    float corona = exp(-dist * 3.0 / r) * 0.6;
    corona += noise(pos * 8.0 + t * 0.3) * 0.15 * exp(-dist * 2.0 / r);

    float rays = 0.0;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398 + sin(float(i) * 3.7 + t * 0.5) * 0.3;
        float adiff = abs(angle - a);
        adiff = min(adiff, 6.28318 - adiff);
        rays += exp(-adiff * 12.0) * 0.4 * exp(-dist * 1.5 / r) * (1.0 + sin(t * 2.0 + float(i)) * 0.3);
    }

    float gran = noise(pos * 40.0 + t * 0.1) * 0.08 * smoothstep(r * 0.3, r, dist);
    gran += noise(pos * 80.0 + t * 0.2) * 0.04 * smoothstep(0.0, r * 0.8, dist);

    float sparkle = 0.0;
    for (int j = 0; j < 30; j++) {
        float sj = float(j);
        vec2 sp = vec2(hash(vec2(sj, 0.0)), hash(vec2(sj, 1.0))) * 2.0 - 1.0;
        sp *= r * 1.6;
        sp += vec2(sin(t * 2.0 + sj), cos(t * 1.7 + sj)) * r * 0.15;
        float sd = length(pos - sp);
        sparkle += exp(-sd * 60.0 / r) * 0.5 * (0.5 + 0.5 * sin(t * 5.0 + sj * 7.3));
    }

    float alpha = (corona + rays + gran + sparkle) * 0.8;
    alpha = clamp(alpha, 0.0, 1.0);
    vec3 col = mix(iColor.rgb, vec3(1.0, 0.95, 0.8), smoothstep(0.0, r * 0.2, dist));
    fragColor = vec4(col, alpha);
}
