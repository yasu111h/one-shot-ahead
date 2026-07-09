shader_type spatial;
render_mode cull_back;
// 夜のビルの窓明かり v2。実写の夜景ビルの要素を再現する:
//  - 窓は小さく密(実物の窓は意外と細かい)
//  - 消えている窓も「ガラス」として空をうっすら青く映す(真っ黒にしない)
//  - 点灯窓には中桟(縦の枠線)・天井照明の上下グラデ・カーテン半閉じの部分点灯
//  - 外壁はコンクリートの汚れむら(単色ののっぺりを消す)

uniform vec3 wall_color : source_color = vec3(0.050, 0.058, 0.075);
uniform vec3 lit_warm : source_color = vec3(1.0, 0.78, 0.50);   // 暖色の窓(生活の光)
uniform vec3 lit_cool : source_color = vec3(0.72, 0.84, 1.0);   // 青白い窓(オフィス)
uniform float win_w = 1.7;       // 窓ピッチ(横)
uniform float floor_h = 3.2;     // 階高
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.30;   // 灯っている窓の割合
uniform float warm_ratio : hint_range(0.0, 1.0) = 0.25;  // 灯りのうち暖色の割合
uniform float seed = 0.0;        // ビルごとに変える(点灯パターンが揃わないように)

varying vec3 wpos;
varying vec3 wnrm;

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
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.1 + 13.7;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 屋上・底面には窓を出さない
	float side = step(abs(wnrm.y), 0.5);
	// 面の向きで窓グリッドに使う平面座標を選ぶ(X面はZY、Z面はXY)
	vec2 pc = abs(wnrm.x) > abs(wnrm.z) ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);

	vec2 g = pc / vec2(win_w, floor_h);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	// セルの中央部だけが窓(まわりは壁の桟・スパンドレル)
	float wx = step(0.20, f.x) * step(f.x, 0.86);
	float wy = step(0.24, f.y) * step(f.y, 0.80);
	float win = wx * wy * side;

	// 窓ごとの点灯・色・明るさむら
	float lit = step(1.0 - lit_ratio, hash12(cell + vec2(seed, seed * 1.7)));
	float warm = step(1.0 - warm_ratio, hash12(cell * 2.3 + vec2(seed)));
	float br = 0.5 + 0.9 * hash12(cell * 3.1 + vec2(seed * 0.7));
	vec3 litcol = mix(lit_cool, lit_warm, warm);

	// 中桟(窓中央の縦の枠)で1枚窓を2枚に割る
	float mull = 1.0 - step(abs(f.x - 0.53), 0.022);
	// 天井照明のグラデ(窓の上のほうが明るい)
	float ceil_grad = 0.55 + 0.45 * smoothstep(0.24, 0.72, f.y);
	// カーテン半閉じ: 一部の窓は下半分が暗い
	float curtained = step(hash12(cell * 4.7 + vec2(seed * 1.3)), 0.35);
	float curtain = mix(1.0, smoothstep(0.30, 0.58, f.y), curtained);

	// 消えている窓も空をうっすら映すガラス(上端ほど空色。真っ黒にしない)
	vec3 glass = mix(vec3(0.016, 0.024, 0.038), vec3(0.055, 0.080, 0.125), f.y * 0.8);

	// 外壁の汚れむら(大きなノイズで濃淡)
	float dirt = 0.72 + 0.55 * fbm(pc * 0.13 + vec2(seed));

	ALBEDO = mix(wall_color * dirt, glass, win);
	ROUGHNESS = mix(0.92, 0.18, win);
	SPECULAR = 0.5;
	EMISSION = litcol * win * lit * br * ceil_grad * curtain * mull;
}
