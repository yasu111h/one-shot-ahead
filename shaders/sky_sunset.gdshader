shader_type sky;
// 夕暮れの平原の空。低い夕日・地平線の橙のグラデーション・夕焼けに照る薄い雲。
// 列車ステージ用(夜の都市・埠頭と差別化した暖色の時間帯)。

uniform vec3 zenith_color : source_color = vec3(0.13, 0.16, 0.28);
uniform vec3 horizon_color : source_color = vec3(0.88, 0.46, 0.20);
uniform vec3 sun_color : source_color = vec3(1.0, 0.78, 0.5);
uniform vec3 sun_dir = vec3(-0.85, 0.10, -0.35);   // 夕日の方向(標的列車の側=西)

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x),
		mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
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
	vec3 sdir = normalize(sun_dir);

	// 基本グラデ: 地平線の橙 → 上空の群青
	vec3 col = mix(horizon_color, zenith_color, clamp(pow(max(h, 0.0) * 1.7, 0.65), 0.0, 1.0));

	// 夕日(低い位置の大きな柔らかい光)
	float sun_amt = pow(max(dot(EYEDIR, sdir), 0.0), 220.0);
	float sun_glow = pow(max(dot(EYEDIR, sdir), 0.0), 8.0);
	col += sun_color * (sun_amt * 4.0 + sun_glow * 0.55);

	// 夕焼けに照る筋雲
	if (h > 0.02) {
		vec2 uv = EYEDIR.xz / (h + 0.22) * 0.4;
		float c = fbm(uv * vec2(1.0, 2.6) + vec2(TIME * 0.004, 0.0));
		float cl = smoothstep(0.48, 0.8, c);
		vec3 cloud = mix(vec3(0.30, 0.22, 0.28), vec3(1.0, 0.62, 0.38),
			smoothstep(0.4, 0.0, h) * 0.8 + sun_glow * 0.5);
		col = mix(col, cloud, cl * 0.6 * smoothstep(0.0, 0.1, h));
	}

	// 地平線のもや
	col += vec3(0.30, 0.16, 0.08) * smoothstep(0.16, 0.0, abs(h));

	COLOR = col;
}
