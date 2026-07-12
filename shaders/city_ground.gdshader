// 夜の都市の地面。ワールドXZ座標で「街区・道路・歩道・車線・街灯の光だまり」を
// 手続き的に描く（ビルの窓 building_windows.gdshader と同じ流儀）。
// 1枚の巨大プレーンに貼るだけで、どこまで遠くへ行っても街の地表が続く。
shader_type spatial;

uniform float road_pitch = 120.0;        // 街区の一辺（道路中心線の間隔）
uniform float road_half = 6.5;           // 道路の半幅
uniform float walk_w = 3.2;              // 歩道の幅
uniform vec2 grid_offset = vec2(4.0, 0.0);  // 道路網の位相（既存のクロス通りz=-120に合わせる）
uniform float lamp_pitch = 42.0;         // 街灯の光だまりの間隔
uniform vec3 lot_color : source_color = vec3(0.034, 0.038, 0.050);
uniform vec3 road_color : source_color = vec3(0.056, 0.061, 0.074);
uniform vec3 walk_color : source_color = vec3(0.070, 0.075, 0.086);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.72, 0.42);

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
	vec2 p = wpos.xz + grid_offset;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	// 細部（ノイズ・車線・目地）は遠景でフェードしてモアレを防ぐ
	float detail = 1.0 - smoothstep(250.0, 800.0, dist);

	// 道路中心線（x軸沿い・z軸沿いの2系統）までの距離
	vec2 cell = floor(p / road_pitch);
	vec2 local = p - cell * road_pitch;           // 0..pitch
	float dx = min(local.x, road_pitch - local.x); // z沿い道路への距離
	float dz = min(local.y, road_pitch - local.y); // x沿い道路への距離
	float droad = min(dx, dz);

	float is_road = 1.0 - smoothstep(road_half - 0.4, road_half + 0.6, droad);
	float is_walk = (1.0 - smoothstep(road_half + walk_w, road_half + walk_w + 1.0, droad))
		* (1.0 - is_road);

	// 街区（ロット）: 区画ごとに明るさをわずかに変え、粗いノイズでむらを足す
	float lot_var = 0.75 + 0.5 * hash12(cell + 7.0);
	float stain = 0.85 + 0.3 * vnoise(p * 0.11);
	vec3 col = lot_color * lot_var * stain;
	// 街区内の細かい目地（駐車場・敷地の割り）: 12mピッチの薄い線
	vec2 sub = abs(fract(p / 12.0) - 0.5) * 12.0;
	float seam = 1.0 - smoothstep(0.06, 0.25, min(sub.x, sub.y));
	col *= 1.0 - seam * 0.25 * detail;

	// 歩道: わずかに明るいコンクリ＋縁石の明線
	col = mix(col, walk_color * stain, is_walk);
	float curb = (1.0 - smoothstep(0.0, 0.5, abs(droad - road_half - 0.2))) * (1.0 - is_road);
	col += vec3(0.012) * curb * detail;

	// 道路: 夜露のアスファルト＋車線の破線（道路方向に沿わせる）
	vec3 rcol = road_color * (0.9 + 0.2 * vnoise(p * 0.23));
	float lane_axis = (dx < dz) ? p.y : p.x;        // 道路の走行方向の座標
	float center = (dx < dz) ? dx : dz;             // 中心線までの距離
	float dash_on = step(fract(lane_axis / 9.0), 0.45);
	float lane = (1.0 - smoothstep(0.10, 0.28, center)) * dash_on;
	rcol += vec3(0.10, 0.095, 0.08) * lane * detail;
	col = mix(col, rcol, is_road);

	// 街灯の光だまり: 道路沿いに周期的な暖色の楕円。遠景では「点々と続く街の灯」になる
	float lamp_t = floor(lane_axis / lamp_pitch);
	float lamp_center = (lamp_t + 0.5) * lamp_pitch;
	vec2 road_dir = (dx < dz) ? vec2(0.0, 1.0) : vec2(1.0, 0.0);
	float along_d = abs(lane_axis - lamp_center);
	float pool_d = length(vec2(along_d * 0.7, center * 0.5));
	float lamp_on = step(0.22, hash12(vec2(lamp_t, cell.x * 3.1 + cell.y * 7.7) + road_dir));
	float pool = (1.0 - smoothstep(2.0, 11.0, pool_d)) * lamp_on * is_road;
	// 交差点は四方の街灯が重なって少し明るい
	vec3 warm = lamp_color * (0.55 + 0.45 * hash12(vec2(lamp_t * 1.7, cell.y)));
	col += warm * pool * 0.30;
	vec3 emis = warm * pool * 0.40;

	// 街区側にも「敷地の常夜灯・看板の照り返し」を粗くまばらに（遠景の街の面の灯）
	vec2 gcell = floor(p / 30.0);
	float gl = hash12(gcell + 3.3);
	float glot = step(0.86, gl) * (1.0 - is_road) *
		(1.0 - smoothstep(4.0, 11.0, length(fract(p / 30.0) * 30.0 - 15.0)));
	vec3 lot_warm = mix(lamp_color, vec3(0.7, 0.8, 1.0), step(0.93, gl));
	col += lot_warm * glot * 0.18;
	emis += lot_warm * glot * 0.22;
	EMISSION = emis;

	ALBEDO = col;
	// 濡れた路面は反射が強め（街明かりをわずかに映す既存の意図を踏襲）
	ROUGHNESS = mix(0.6, 0.32, is_road);
	SPECULAR = 0.5;
}
