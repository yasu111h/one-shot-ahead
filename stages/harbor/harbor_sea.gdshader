shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// 夜の港の海（TABIJI isle_water の思想を夜用に軽量化）。
// 深度テクスチャは使わない（gl_compatibility・スマホで確実に動く不透明水面）。
// 3層ノイズの波で法線を揺らし、フレネルの空映り込み＋月光のきらめきで
// 「夜の海」を安く作る。本物の水シミュは禁止（§3）。

uniform vec3 deep_color : source_color = vec3(0.008, 0.020, 0.038);   // 夜の海の地色
uniform vec3 crest_color : source_color = vec3(0.030, 0.065, 0.105);  // 波頭のわずかな明るみ
uniform vec3 sky_tint : source_color = vec3(0.35, 0.48, 0.70);        // 映り込む夜空
uniform vec3 moon_tint : source_color = vec3(0.85, 0.92, 1.0);        // 月のきらめき
uniform float wave_speed = 0.8;
uniform float normal_strength = 1.8;

varying vec3 wpos;

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

// 波の高さ: 大うねり＋中波＋さざ波の3層
float wave_h(vec2 p, float t) {
	float h = vnoise(p * 0.10 + t * vec2(0.30, 0.12)) * 0.50;
	h += vnoise(p * 0.42 + t * vec2(-0.18, 0.26)) * 0.32;
	h += vnoise(p * 1.60 + t * vec2(0.48, -0.34)) * 0.18;
	return h;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = wpos.xz;

	// 波の法線（高さの傾きから）
	float e = 0.35;
	float h0 = wave_h(p, t);
	float hx = wave_h(p + vec2(e, 0.0), t);
	float hz = wave_h(p + vec2(0.0, e), t);
	NORMAL_MAP = normalize(vec3((h0 - hx) * normal_strength, (h0 - hz) * normal_strength, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// 地色: 波頭がわずかに明るい
	vec3 col = mix(deep_color, crest_color, smoothstep(0.55, 0.95, h0));

	// フレネル（浅い角度ほど夜空を映す）
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	ALBEDO = col;
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
	METALLIC = 0.0;

	// 空の映り込み ＋ まばらな月光のきらめき（波の頂だけが瞬く）
	float sp = hash12(floor(p * 2.6) + floor(vec2(t * 2.0)));
	float tw = step(0.972, sp) * smoothstep(0.62, 0.95, h0);
	EMISSION = sky_tint * fres * 0.10 + moon_tint * tw * 0.35;
}
