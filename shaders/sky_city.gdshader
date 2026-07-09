shader_type sky;
// 夜の都市の空。実写の夜景写真の要素:
//  - 濃紺の空に低い雲が流れ、雲の底が街明かりでほんのり照る
//  - 地平線近くは街の光の照り返しで青白く明るい
//  - 高い空にわずかな星

uniform vec3 top_color : source_color = vec3(0.006, 0.010, 0.020);
uniform vec3 horizon_color : source_color = vec3(0.045, 0.065, 0.105);
uniform vec3 cloud_dark : source_color = vec3(0.030, 0.042, 0.065);
uniform vec3 cloud_lit : source_color = vec3(0.075, 0.085, 0.115);   // 街明かりに照る雲の底

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
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.1 + 13.7;
		a *= 0.5;
	}
	return v;
}

void sky() {
	float h = EYEDIR.y;

	// 基本グラデ: 地平線の照り返し→濃紺
	vec3 col = mix(horizon_color, top_color, clamp(pow(max(h, 0.0) * 2.0, 0.55), 0.0, 1.0));

	// 低い雲(平面投影)。ゆっくり流れる
	if (h > 0.015) {
		vec2 uv = EYEDIR.xz / (h + 0.18) * 0.55;
		float c = fbm(uv + vec2(TIME * 0.006, TIME * 0.002));
		float cl = smoothstep(0.42, 0.78, c);
		vec3 cloud = mix(cloud_dark, cloud_lit, smoothstep(0.35, 0.0, h));   // 低い雲ほど街の光で照る
		col = mix(col, cloud, cl * 0.85);

		// 雲の切れ間の星(高い空だけ・ごく淡く)
		float star = step(0.9985, hash12(floor(EYEDIR.xz / max(h, 0.2) * 220.0)));
		col += vec3(0.6, 0.7, 0.9) * star * (1.0 - cl) * smoothstep(0.25, 0.6, h) * 0.5;
	}

	// 地平線のグロー(街の光が空ににじむ)
	col += vec3(0.030, 0.045, 0.080) * smoothstep(0.18, 0.0, abs(h));

	COLOR = col;
}
