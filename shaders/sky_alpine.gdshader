shader_type sky;
// 高原の昼の空。濃い青の天頂→白っぽい地平線、ゆっくり流れる積雲、太陽とハロ。

uniform vec3 zenith : source_color = vec3(0.16, 0.40, 0.78);
uniform vec3 horizon : source_color = vec3(0.74, 0.84, 0.94);
uniform vec3 sun_dir = vec3(-0.35, 0.55, -0.75);   // 太陽の方向（ステージの光と合わせる）
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.45;

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
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.1 + 13.7;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, 0.0, 1.0);
	// 青のグラデーション（地平線ほど白く霞む）
	vec3 col = mix(horizon, zenith, pow(up, 0.55));
	// 地平線の下はうっすら大気色（地形で隠れるが念のため）
	if (dir.y < 0.0) {
		col = mix(horizon, vec3(0.42, 0.48, 0.52), clamp(-dir.y * 3.0, 0.0, 1.0));
	}

	// 地平線際の遠山シルエット（3層・ごく控えめ）。地形メッシュ(±4.2km)の縁と
	// 真の地平線の間のわずかな隙間を、霞んだ山並みの層で埋めて
	// 「どこまでも山が続く」ように見せる。視点(山頂165m)からは水平よりやや下に見えるため、
	// 帯は dir.y≈0 のすぐ下に沈めて実地形の陰から頭だけ覗かせる
	if (dir.y < 0.02) {
		float ang = atan(dir.x, dir.z);
		// 遠い層から手前の層の順に重ねる（i=0が最遠＝淡い、i=2が最手前＝やや濃い）
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float top = 0.002 - fi * 0.011
				+ (fbm(vec2(ang * (2.0 + fi * 0.9), fi * 7.3)) - 0.5) * 0.016;
			if (dir.y < top) {
				vec3 ridge_col = mix(vec3(0.44, 0.55, 0.52), horizon, 0.72 - fi * 0.14);
				col = mix(col, ridge_col, 0.5);
			}
		}
	}

	vec3 s = normalize(sun_dir);
	float sd = clamp(dot(dir, s), 0.0, 1.0);
	// 太陽の円盤＋広いハロ
	col += vec3(1.0, 0.98, 0.90) * smoothstep(0.9993, 0.9998, sd) * 6.0;
	col += vec3(0.9, 0.9, 0.8) * pow(sd, 220.0) * 0.7;
	col += vec3(0.55, 0.62, 0.72) * pow(sd, 8.0) * 0.14;

	// 積雲：空を平面に投影してfbm。ゆっくり流れる
	if (dir.y > 0.015) {
		vec2 uv = dir.xz / (dir.y + 0.18) * 0.55;
		uv += vec2(TIME * 0.004, TIME * 0.0016);
		float n = fbm(uv * 1.6);
		float cov = smoothstep(1.0 - cloud_amount * 0.62, 1.02 - cloud_amount * 0.3, n);
		// 遠く(地平線近く)ほど雲を薄く＝奥行き
		cov *= smoothstep(0.015, 0.16, dir.y);
		// 雲の陰影（下面をわずかに暗く）
		float shade = 0.82 + 0.18 * fbm(uv * 3.1 + 7.0);
		vec3 cloud = vec3(1.0, 1.0, 1.0) * shade;
		// 太陽に近い雲は縁が光る
		cloud += vec3(0.25, 0.22, 0.16) * pow(sd, 5.0);
		col = mix(col, cloud, cov * 0.92);
	}

	COLOR = col;
}
