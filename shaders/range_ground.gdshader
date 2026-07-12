// 射撃場の草原。ワールドXZ座標で「草の色むら・土の禿げ・刈り込んだ射撃レーン・
// 轍の作業道」を手続き描画する（city_ground / harbor_quay と同じ流儀）。
// 1枚の巨大プレーンで、どこまで見ても草原が続く。
shader_type spatial;

uniform vec3 grass_a : source_color = vec3(0.33, 0.42, 0.29);   // 基本の草
uniform vec3 grass_b : source_color = vec3(0.42, 0.47, 0.27);   // 乾いた草（黄み）
uniform vec3 grass_dark : source_color = vec3(0.24, 0.33, 0.22); // 湿った濃い草
uniform vec3 dirt_color : source_color = vec3(0.42, 0.36, 0.26); // 土
uniform float lane_half = 45.0;   // 射撃レーン（刈り込み帯）の半幅

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

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(200.0, 900.0, dist);

	// 草の色むら（大きなうねり＋中スケールのまだら＋足元の細かい斑）
	float big = vnoise(p * 0.008);
	float mid = vnoise(p * 0.045 + 13.0);
	float fine = vnoise(p * 0.6 + 5.0) * detail;
	vec3 col = mix(grass_a, grass_b, smoothstep(0.30, 0.72, big));
	col = mix(col, grass_dark, smoothstep(0.45, 0.85, mid) * 0.85);
	col *= 0.88 + 0.24 * fine;

	// 土の禿げ（まばら。射撃場らしい踏み跡）
	float bare = smoothstep(0.62, 0.82, vnoise(p * 0.11 + 31.0));
	col = mix(col, dirt_color * (0.85 + 0.3 * fine), bare * 0.85);

	// 射撃レーン: 標的方向(-Z)へ延びる刈り込み帯。明るい黄緑で「整備された的場」
	float lane = 1.0 - smoothstep(lane_half - 6.0, lane_half + 10.0, abs(p.x));
	lane *= smoothstep(30.0, -10.0, wpos.z);   // やぐらの先から
	vec3 mowed = mix(grass_b, grass_a, 0.35) * 1.06;
	// 刈り込みの筋（レーン内に8mピッチの薄い縞＝芝刈りの跡）
	float strip = 0.5 + 0.5 * sin(p.x * 3.14159 / 8.0);
	mowed *= 0.97 + 0.05 * strip * detail;
	col = mix(col, mowed, lane * 0.85);

	// 作業道: レーンの両脇 x=±60m を走る轍の土道
	float road = (1.0 - smoothstep(1.6, 3.4, abs(abs(p.x) - 60.0)))
		* smoothstep(40.0, 0.0, wpos.z);
	// 轍2本（車輪の跡が濃い）
	float rut = 1.0 - smoothstep(0.25, 0.8, abs(abs(abs(p.x) - 60.0) - 0.9));
	vec3 road_col = mix(dirt_color, dirt_color * 0.72, rut * detail);
	col = mix(col, road_col, road * 0.9);

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
