shader_type spatial;
// 山岳の地形材質。高さと斜度で草原・森の色むら・岩場・川岸を塗り分ける。
// テクスチャ不使用（ワールド座標ノイズのみ）＝gl_compatibilityで軽い。

uniform vec3 grass_low : source_color = vec3(0.22, 0.42, 0.16);   // 谷の瑞々しい草
uniform vec3 grass_high : source_color = vec3(0.38, 0.46, 0.22);  // 高所の乾いた草
uniform vec3 forest : source_color = vec3(0.10, 0.27, 0.11);      // 森の色むら
uniform vec3 rock : source_color = vec3(0.44, 0.42, 0.39);        // 岩場
uniform vec3 scree : source_color = vec3(0.56, 0.55, 0.52);       // 山頂近くのガレ場
uniform vec3 shore : source_color = vec3(0.50, 0.46, 0.34);       // 川岸の砂

varying vec3 wpos;
varying vec3 wnrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.13 + 17.3;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float h = wpos.y;
	float slope = 1.0 - wnrm.y;   // 0=平ら 〜 1=垂直

	// 草：谷の緑→高所の乾いた緑。大きなノイズで色むら
	float band = clamp(h / 130.0, 0.0, 1.0);
	vec3 grass = mix(grass_low, grass_high, band);
	float patch = fbm(wpos.xz * 0.015);
	grass = mix(grass, forest, smoothstep(0.55, 0.75, patch) * 0.85);
	grass *= 0.9 + 0.2 * fbm(wpos.xz * 0.12);   // 細かい草むら感

	// 岩：斜度が上がるほど岩肌。標高が高いほど早く岩化＋ガレ場の明るい石
	float rock_t = smoothstep(0.30, 0.52, slope + band * 0.10);
	vec3 rocks = mix(rock, scree, smoothstep(120.0, 165.0, h));
	rocks *= 0.85 + 0.3 * fbm(wpos.xz * 0.05 + 31.0);

	vec3 col = mix(grass, rocks, rock_t);
	// 川岸：水面(6.5m)近くは砂の色へ
	col = mix(shore, col, smoothstep(6.8, 10.5, h));

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}
