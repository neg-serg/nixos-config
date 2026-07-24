// Lunar surface — procedural craters with parallax depth, maria noise, phase shadow
uniform float iPhase;
uniform vec3 iColor;
uniform float cx;
uniform float cy;
uniform float iRadius;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
float fbm(vec2 p) { float v=0.0,a=0.5; for(int i=0;i<5;i++){v+=a*noise(p);p*=2.0;a*=0.5;} return v; }

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 center = vec2(cx, cy);
    vec2 pos = uv - center;
    float dist = length(pos);

    if (dist > iRadius) { gl_FragColor = vec4(0.0); return; }

    // Craters with parallax depth
    float crater = 0.0;
    float craterDepth = 0.0;
    for (int i = 0; i < 18; i++) {
        float ci = float(i);
        vec2 cp = vec2(hash(vec2(ci, 0.0)), hash(vec2(ci, 1.0))) * 2.0 - 1.0;
        cp *= iRadius * 0.85;
        float cr = iRadius * (0.03 + hash(vec2(ci, 2.0)) * 0.09);
        vec2 lp = cp + vec2(0.2, 0.15) * iRadius * 0.1;
        float cd = length(pos - cp);
        if (cd < cr) {
            float rim = smoothstep(cr, cr * 0.85, cd);
            float depth = (1.0 - cd / cr) * 0.5;
            crater += rim * 0.15;
            craterDepth += depth * 0.3;
        } else if (cd < cr * 1.5) {
            float rimDist = abs(cd - cr);
            float rim = exp(-rimDist * 12.0 / cr) * 0.2;
            crater += rim;
            craterDepth -= rim * 0.15;
        }
        float lightAngle = atan(pos.y - cp.y, pos.x - cp.x);
        float lightDiff = cos(lightAngle - 0.8);
        if (cd < cr * 1.5 && cd > cr * 0.7) crater += max(0.0, lightDiff) * 0.08;
    }

    // Lunar maria
    float maria = fbm(pos * 4.0 / iRadius) * 0.12;
    maria += fbm(pos * 8.0 / iRadius) * 0.06;
    float micro = noise(pos * 30.0 / iRadius) * 0.03;

    // Phase shadow
    float shadowAngle = iPhase * 6.28318;
    float shadowGrad = smoothstep(iRadius * 0.9, iRadius * 1.1, pos.x * cos(shadowAngle) + pos.y * sin(shadowAngle));
    float phaseShadow = (1.0 - shadowGrad) * 0.75;

    float surf = 0.55 - maria - crater + craterDepth + micro - phaseShadow;
    surf = clamp(surf, 0.0, 1.0);

    vec3 col = mix(vec3(0.82, 0.80, 0.78), vec3(0.76, 0.74, 0.72), maria * 3.0);
    col = mix(col, vec3(0.55, 0.53, 0.50), phaseShadow);
    col = mix(col, iColor * 0.3, crater * 2.0);
    col += smoothstep(iRadius, iRadius * 0.92, dist) * 0.1;
    gl_FragColor = vec4(col, 1.0);
}
