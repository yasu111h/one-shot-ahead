// 夜の埠頭の岸壁コンクリート。ワールドXZ座標で「目地・クレーンレール・車線・
// 縁の危険ストライプ・コンテナ区画線・作業灯の光だまり」を手続き描画する。
// 1枚の巨大プレーンで、左右どこまで見ても港の地表が続く（city_groundと同じ流儀）。
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.16, 0.17, 0.20);
uniform vec3 paint_color : source_color = vec3(0.55, 0.45, 0.12);   // 消えかけの黄ペンキ
uniform vec3 lamp_color : source_color = vec3(1.0, 0.78, 0.45);     // 作業灯
uniform float edge_z = -210.0;    // 岸壁の縁（これより手前が陸）

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
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x),
		mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(220.0, 750.0, dist);

	// コンクリ地＋大きなシミ・タイヤ痕
	vec3 col = base_color * (0.88 + 0.24 * vnoise(p * 0.13));
	col *= 1.0 - 0.18 * smoothstep(0.55, 0.85, vnoise(p * 0.045 + 7.0));
	// 8mピッチの目地
	vec2 j = abs(fract(p / 8.0) - 0.5) * 8.0;
	col *= 1.0 - (1.0 - smoothstep(0.04, 0.20, min(j.x, j.y))) * 0.22 * detail;

	// コンテナ区画線（縁から60〜140mの帯・白ペンキの区画割り）
	float band0 = edge_z + 60.0;   // -150
	float band1 = edge_z + 140.0;  // -70
	float bay = step(band0, wpos.z) * step(wpos.z, band1);
	vec2 bj = abs(fract(vec2(p.x / 7.0, wpos.z / 16.0)) - 0.5) * vec2(7.0, 16.0);
	float bline = 1.0 - smoothstep(0.05, 0.18, min(bj.x, bj.y));
	col += vec3(0.10) * bline * bay * detail * 0.6;

	// クレーンレール2本（縁と平行な鋼のライン）
	float rail = (1.0 - smoothstep(0.12, 0.30, abs(wpos.z - (edge_z + 14.0))))
		+ (1.0 - smoothstep(0.12, 0.30, abs(wpos.z - (edge_z + 6.0))));
	col = mix(col, vec3(0.050, 0.055, 0.065), clamp(rail, 0.0, 1.0) * 0.9);

	// 黄色の車線（連続線＋破線）。ペンキは剥げむらを掛ける
	float wear = 0.55 + 0.45 * vnoise(p * 0.7);
	float lane1 = 1.0 - smoothstep(0.10, 0.24, abs(wpos.z - (edge_z + 24.0)));
	float dash_on = step(fract(p.x / 10.0), 0.55);
	float lane2 = (1.0 - smoothstep(0.10, 0.24, abs(wpos.z - (edge_z + 60.0)))) * dash_on;
	col = mix(col, paint_color * wear, clamp(lane1 + lane2, 0.0, 1.0) * 0.85 * max(detail, 0.2));

	// 縁の危険ストライプ（黄黒の斜め縞・幅3m）
	float hz = step(edge_z + 1.0, wpos.z) * step(wpos.z, edge_z + 4.0);
	float stripe = step(0.5, fract((p.x + wpos.z) * 0.45));
	col = mix(col, mix(vec3(0.035), paint_color * wear * 1.3, stripe), hz * 0.85);

	// 作業灯の光だまり（岸壁沿いに2列・x方向へ周期的に続く＝遠くまで「稼働中の港」）
	vec3 emis = vec3(0.0);
	float pool = 0.0;
	// 列1: クレーンレール脇（縁から32m）55mピッチ
	{
		float t = floor(p.x / 55.0);
		float c = (t + 0.5) * 55.0;
		float d = length(vec2((p.x - c) * 0.75, (wpos.z - (edge_z + 32.0)) * 0.5));
		pool += (1.0 - smoothstep(2.0, 11.0, d)) * step(0.15, hash12(vec2(t, 1.0)));
	}
	// 列2: 倉庫前（縁から150m）70mピッチ
	{
		float t = floor(p.x / 70.0);
		float c = (t + 0.5) * 70.0;
		float d = length(vec2((p.x - c) * 0.75, (wpos.z - (edge_z + 150.0)) * 0.5));
		pool += (1.0 - smoothstep(2.0, 10.0, d)) * step(0.25, hash12(vec2(t, 9.0)));
	}
	pool = clamp(pool, 0.0, 1.0);
	vec3 warm = lamp_color;
	col += warm * pool * 0.28;
	emis = warm * pool * 0.34;

	ALBEDO = col;
	EMISSION = emis;
	// 基本はマットな夜のコンクリ（巨大平面だと低roughnessの月光スペキュラが
	// 面全体の白飛びになる）。「濡れた照り」は光だまりの中だけに出す
	ROUGHNESS = 0.62 - pool * 0.22;
	SPECULAR = 0.3;
}
