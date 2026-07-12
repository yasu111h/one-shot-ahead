// 風車群の丘の草地。面の向き・高さ・パッチノイズで色が変わる素朴な草原。
// 頂点は動かさない＝当たり判定（HeightMapShape3D）と常に一致する。
shader_type spatial;

uniform vec3 color_sun : source_color = vec3(0.46, 0.52, 0.26);    // 日の当たる草
uniform vec3 color_shade : source_color = vec3(0.22, 0.30, 0.18);  // 陰の草
uniform vec3 color_dry : source_color = vec3(0.62, 0.55, 0.32);    // 乾いた草のパッチ
uniform vec3 color_dirt : source_color = vec3(0.42, 0.34, 0.24);   // 土（急斜面に出る）

varying vec3 wpos;
varying vec3 wnormal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 2値ノイズの双線形補間（パッチの境界をなだらかに）
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
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 面の向きで日向⇄陰。細かい草むらノイズを少し混ぜる
	float grain = hash12(floor(wpos.xz * 18.0));
	float shade = clamp(wnormal.y * 0.7 + 0.3 + (grain - 0.5) * 0.10, 0.0, 1.0);
	vec3 base = mix(color_shade, color_sun, shade);
	// 乾いた草のパッチ（大きめのまだら）
	float patch = vnoise(wpos.xz * 0.035);
	base = mix(base, color_dry, smoothstep(0.58, 0.78, patch) * 0.55);
	// 急斜面は土が覗く
	float steep = 1.0 - smoothstep(0.55, 0.8, wnormal.y);
	base = mix(base, color_dirt, steep * 0.7);
	ALBEDO = base;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
