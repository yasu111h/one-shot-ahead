// 砂漠ステージ「夜明け」の空。地平線の暖色→天頂の紫青のグラデーション、
// 低い太陽とハロ、天頂に消え残る星。太陽の位置はDirectionalLight3Dに追従する。
// TABIJI（beautiful-journey）の sky_dawn.gdshader を流用。
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.30, 0.28, 0.52);
uniform vec3 mid_color : source_color = vec3(0.87, 0.55, 0.42);
uniform vec3 horizon_color : source_color = vec3(1.00, 0.62, 0.30);
uniform vec3 ground_color : source_color = vec3(0.28, 0.16, 0.18);
uniform vec3 sun_color : source_color = vec3(1.00, 0.85, 0.60);

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	float y = EYEDIR.y;
	vec3 col;
	if (y >= 0.0) {
		col = mix(horizon_color, mid_color, smoothstep(0.0, 0.18, y));
		col = mix(col, zenith_color, smoothstep(0.12, 0.65, y));
	} else {
		col = mix(horizon_color, ground_color, clamp(-y * 6.0, 0.0, 1.0));
	}

	if (LIGHT0_ENABLED) {
		float sd = distance(EYEDIR, LIGHT0_DIRECTION);
		float disc = smoothstep(0.035, 0.028, sd);
		float halo = exp(-sd * 5.0) * 0.55;
		float glow = exp(-sd * 1.5) * 0.18;
		col += sun_color * (disc * 2.0 + halo + glow);
	}

	// 夜明けの空に消え残る星
	if (y > 0.25) {
		float s = hash13(floor(EYEDIR * 220.0));
		col += vec3(step(0.9985, s) * smoothstep(0.25, 0.6, y) * 0.5);
	}

	COLOR = col;
}
