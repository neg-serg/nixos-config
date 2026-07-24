// Solar corona + granulation + sparkle particles
uniform float iTime;
uniform vec3 iColor;
uniform float iRadius;
uniform float cx;
uniform float cy;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 center = vec2(cx, cy);
    vec2 pos = uv - center;
    float dist = length(pos);
    float angle = atan(pos.y, pos.x);

    float corona = exp(-dist * 3.0 / iRadius) * 0.6;
    corona += noise(pos * 8.0 + iTime * 0.3) * 0.15 * exp(-dist * 2.0 / iRadius);

    float rays = 0.0;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398 + sin(float(i) * 3.7 + iTime * 0.5) * 0.3;
        float adiff = abs(angle - a);
        adiff = min(adiff, 6.28318 - adiff);
        rays += exp(-adiff * 12.0) * 0.4 * exp(-dist * 1.5 / iRadius) * (1.0 + sin(iTime * 2.0 + float(i)) * 0.3);
    }

    float gran = noise(pos * 40.0 + iTime * 0.1) * 0.08 * smoothstep(iRadius, iRadius * 0.3, dist);
    gran += noise(pos * 80.0 + iTime * 0.2) * 0.04 * smoothstep(iRadius * 0.8, 0.0, dist);

    float sparkle = 0.0;
    for (int j = 0; j < 30; j++) {
        float sj = float(j);
        vec2 sp = vec2(hash(vec2(sj, 0.0)), hash(vec2(sj, 1.0))) * 2.0 - 1.0;
        sp *= iRadius * 1.6;
        sp += vec2(sin(iTime * 2.0 + sj), cos(iTime * 1.7 + sj)) * iRadius * 0.15;
        float sd = length(pos - sp);
        sparkle += exp(-sd * 60.0 / iRadius) * 0.5 * (0.5 + 0.5 * sin(iTime * 5.0 + sj * 7.3));
    }

    float alpha = (corona + rays + gran + sparkle) * 0.8;
    alpha = clamp(alpha, 0.0, 1.0);
    vec3 col = mix(iColor, vec3(1.0, 0.95, 0.8), smoothstep(iRadius * 0.2, 0.0, dist));
    gl_FragColor = vec4(col, alpha);
}
