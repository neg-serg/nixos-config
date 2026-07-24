#version 440 core
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform qt_ubuf {
    vec4 iPhase;
    vec4 iColor;
    vec4 iRadius;
    vec4 cx;
    vec4 cy;
};

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
float fbm(vec2 p) { float v=0.0,a=0.5; for(int i=0;i<5;i++){v+=a*noise(p);p*=2.0;a*=0.5;} return v; }

void main() {
    vec2 center = vec2(cx.x, cy.x);
    vec2 pos = qt_TexCoord0 - center;
    float dist = length(pos);
    float phase = iPhase.x;
    float r = iRadius.x;

    if (dist > r) { fragColor = vec4(0.0); return; }

    float crater = 0.0, craterDepth = 0.0;
    for (int i = 0; i < 18; i++) {
        float ci = float(i);
        vec2 cp = vec2(hash(vec2(ci,0)), hash(vec2(ci,1))) * 2.0 - 1.0;
        cp *= r * 0.85;
        float cr = r * (0.03 + hash(vec2(ci,2)) * 0.09);
        float cd = length(pos - cp);
        if (cd < cr) { float rim = smoothstep(cr, cr*0.85, cd); float depth = (1.0 - cd/cr) * 0.5; crater += rim*0.15; craterDepth += depth*0.3; }
        else if (cd < cr*1.5) { float rd = abs(cd-cr); float rim = exp(-rd*12.0/cr)*0.2; crater += rim; craterDepth -= rim*0.15; }
        float la = atan(pos.y - cp.y, pos.x - cp.x);
        if (cd < cr*1.5 && cd > cr*0.7) crater += max(0.0, cos(la-0.8))*0.08;
    }

    float maria = fbm(pos*4.0/r)*0.12 + fbm(pos*8.0/r)*0.06;
    float micro = noise(pos*30.0/r)*0.03;
    float sa = phase*6.28318;
    float sg = smoothstep(r*0.9, r*1.1, pos.x*cos(sa) + pos.y*sin(sa));
    float ps = (1.0 - sg)*0.75;

    float surf = 0.55 - maria - crater + craterDepth + micro - ps;
    surf = clamp(surf, 0.0, 1.0);

    vec3 col = mix(vec3(0.82,0.80,0.78), vec3(0.76,0.74,0.72), maria*3.0);
    col = mix(col, vec3(0.55,0.53,0.50), ps);
    col = mix(col, iColor.rgb*0.3, crater*2.0);
    col += smoothstep(r, r*0.92, dist)*0.1;
    fragColor = vec4(col, 1.0);
}
