package com.example.bemybench.gpu

/**
 * Fontes GLSL ES 1.00 (OpenGL ES 2.0) usadas pelo backend de GPU do Android.
 *
 * O mesmo conjunto de shaders alimenta o benchmark off-screen (EGL + Pbuffer)
 * e o overlay 3D ao vivo (GLSurfaceView), garantindo que a medição e o que o
 * usuário vê executem exatamente a mesma carga de trabalho.
 *
 * Observações de compatibilidade:
 *  - GLSL ES 1.00 exige limites de laço constantes; por isso as iterações de
 *    raymarching e de turbulência fractal são literais no código.
 *  - Nenhuma extensão é utilizada (sem half-float, sem MSAA, sem instancing),
 *    o que mantém o backend funcionando em praticamente qualquer aparelho.
 */
internal object GlslSources {

    /** Quad full-screen compartilhado por todos os passes. */
    const val VERTEX = """
attribute vec2 aPos;
varying vec2 vUv;
void main() {
    vUv = aPos * 0.5 + 0.5;
    gl_Position = vec4(aPos, 0.0, 1.0);
}
"""

    /**
     * Teste de compute emulando um compute shader: 48 iterações de
     * FMA + sin/cos + sqrt por pixel em 1920x1080.
     *
     * 48 iterações equiparam o teste ao do macOS (âncora da base de
     * referência), mantendo os scores comparáveis entre plataformas.
     */
    const val COMPUTE = """
precision highp float;
void main() {
    vec2 p = gl_FragCoord.xy;
    vec4 v = vec4(p.x * 0.000001, 1.0, 2.0, 3.0);
    vec4 acc = vec4(0.0);
    for (int i = 0; i < 48; i++) {
        v = v * 1.0000001 + vec4(0.000001);
        vec4 s = sin(v);
        vec4 c = cos(v.yzwx);
        v = s * c + sqrt(abs(v));
        acc += v;
    }
    gl_FragColor = vec4(fract(acc.x * 0.0001), fract(acc.y * 0.0001), fract(acc.z * 0.0001), 1.0);
}
"""

    /**
     * Cena volumétrica estilo FurMark: donut (toroide) com deslocamento por
     * ruído fractal, rotação contínua, iluminação difusa/especular, magma
     * procedural e atmosfera vulcânica.
     */
    const val SCENE = """
precision highp float;

varying vec2 vUv;
uniform float uTime;
uniform vec2 uResolution;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = p * 2.05 + vec2(97.0, 31.0);
        a *= 0.5;
    }
    return v;
}

float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

void main() {
    vec2 uv = (vUv - 0.5) * vec2(uResolution.x / uResolution.y, 1.0);
    vec3 ro = vec3(0.0, 3.2, -6.0);
    vec3 ta = vec3(0.0, 0.0, 0.0);
    vec3 ww = normalize(ta - ro);
    vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
    vec3 vv = normalize(cross(uu, ww));
    vec3 rd = normalize(uv.x * uu + uv.y * vv + 1.6 * ww);

    float t = 0.1;
    float d = 1000.0;
    vec3 p = ro;
    float ang = uTime * 0.9;
    float cosA = cos(ang);
    float sinA = sin(ang);

    for (int i = 0; i < 32; i++) {
        p = ro + rd * t;
        vec3 q = p;
        vec2 rotXZ = vec2(cosA * q.x - sinA * q.z, sinA * q.x + cosA * q.z);
        q.x = rotXZ.x;
        q.z = rotXZ.y;
        float disp = fbm(q.xy * 3.5 + vec2(uTime * 0.4, 0.0)) * 0.2;
        d = sdTorus(q, vec2(2.2, 0.85)) - disp;
        if (d < 0.001 || t > 25.0) {
            break;
        }
        t += d * 0.65;
    }

    vec3 col = vec3(0.045, 0.02, 0.018);
    if (d < 0.02) {
        vec3 eps = vec3(0.002, 0.0, 0.0);
        float nx = sdTorus(p + eps.xyz, vec2(2.2, 0.85)) - sdTorus(p - eps.xyz, vec2(2.2, 0.85));
        float ny = sdTorus(p + eps.zxy, vec2(2.2, 0.85)) - sdTorus(p - eps.zxy, vec2(2.2, 0.85));
        float nz = sdTorus(p + eps.yzx, vec2(2.2, 0.85)) - sdTorus(p - eps.yzx, vec2(2.2, 0.85));
        vec3 nor = normalize(vec3(nx, ny, nz));
        float dif = clamp(dot(nor, vec3(0.57, 0.70, -0.42)), 0.0, 1.0);
        float rim = pow(1.0 - clamp(dot(nor, -rd), 0.0, 1.0), 3.0);
        float glow = fbm(p.xy * 5.0 + vec2(uTime, uTime * 0.5));
        vec3 magma = mix(vec3(0.55, 0.04, 0.01), vec3(1.0, 0.42, 0.03), glow);
        col = magma * (0.22 + 0.95 * dif);
        col += vec3(1.0, 0.72, 0.22) * pow(dif, 6.0) * 0.32;
        col += vec3(1.0, 0.32, 0.04) * rim * 0.45;
    } else {
        float sky = fbm(vUv * 4.0 + vec2(uTime * 0.1, 0.0));
        col += vec3(0.18, 0.04, 0.01) * sky;
    }

    float vign = 1.0 - length(vUv - 0.5) * 0.7;
    col *= vign;
    gl_FragColor = vec4(col, 1.0);
}
"""

    /** Bright pass: isola as regiões claras para o bloom (meia resolução). */
    const val BRIGHT = """
precision mediump float;
varying vec2 vUv;
uniform sampler2D uTex;
uniform float uThreshold;
void main() {
    vec3 c = texture2D(uTex, vUv).rgb;
    float l = max(c.r, max(c.g, c.b));
    float w = smoothstep(uThreshold, uThreshold + 0.25, l);
    gl_FragColor = vec4(c * w, 1.0);
}
"""

    /** Gaussian blur separável de 5 taps (usado nas duas direções). */
    const val BLUR = """
precision mediump float;
varying vec2 vUv;
uniform sampler2D uTex;
uniform vec2 uTexel;
uniform vec2 uDir;
void main() {
    vec4 sum = texture2D(uTex, vUv) * 0.227027;
    sum += texture2D(uTex, vUv + uDir * uTexel * 1.3846) * 0.316216;
    sum += texture2D(uTex, vUv - uDir * uTexel * 1.3846) * 0.316216;
    sum += texture2D(uTex, vUv + uDir * uTexel * 3.2308) * 0.070270;
    sum += texture2D(uTex, vUv - uDir * uTexel * 3.2308) * 0.070270;
    gl_FragColor = sum;
}
"""

    /**
     * Composite final: bloom + vinheta + contraste.
     *
     * O alvo do Android é RGBA8 (LDR), então o composite NÃO aplica tonemap
     * ACES nem correção de gamma — isso estouraria as cores para bege/branco.
     * O macOS aplica ACES porque renderiza em HDR (rgba16Float).
     */
    const val COMPOSITE = """
precision highp float;
varying vec2 vUv;
uniform sampler2D uScene;
uniform sampler2D uBloom;
void main() {
    vec3 c = texture2D(uScene, vUv).rgb;
    vec3 b = texture2D(uBloom, vUv).rgb;
    c += b * 0.55;
    // Contraste suave em torno do ponto médio para preservar as sombras.
    c = (c - 0.5) * 1.12 + 0.5;
    // Leve realce de saturação para o magma ficar vivo.
    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(vec3(luma), c, 1.18);
    c = clamp(c, 0.0, 1.0);
    gl_FragColor = vec4(c, 1.0);
}
"""
}
