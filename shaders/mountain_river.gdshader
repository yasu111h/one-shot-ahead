shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// 山あいの川の水面。深い青緑＋流れるさざ波のきらめき。
// 本物の水シミュは禁止（§3）なので、スクロールするノイズだけで水面感を作る。

uniform vec3 deep : source_color = vec3(0.05, 0.20, 0.26);
uniform vec3 shallow : source_color = vec3(0.16, 0.42, 0.46);
uniform float sparkle_strength = 0.55;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 川は概ね±X方向に流れる＝ノイズをX方向へスクロール
	vec2 uv = wpos.xz * 0.16;
	float w1 = vnoise(uv * 1.8 + vec2(TIME * 0.55, TIME * 0.07));
	float w2 = vnoise(uv * 3.7 - vec2(TIME * 0.34, TIME * 0.05) + 5.0);
	float ripple = w1 * 0.6 + w2 * 0.4;

	ALBEDO = mix(deep, shallow, ripple * 0.7);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	METALLIC = 0.0;
	// 波頭のきらめき（細かい明点がちらちら流れる）
	float glint = pow(vnoise(uv * 7.0 + vec2(TIME * 0.9, 0.0)), 7.0);
	EMISSION = vec3(0.85, 0.95, 1.0) * glint * sparkle_strength;
	ALPHA = 0.88;
}
