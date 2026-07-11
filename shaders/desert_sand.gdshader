// 砂漠ステージの砂。高さ・向きで色が変わり、砂粒がキラッと光る。
// TABIJI（beautiful-journey）の sand.gdshader を流用（ロジック持ち込みなし・見た目のみ）。
shader_type spatial;

uniform vec3 color_lit : source_color = vec3(0.93, 0.62, 0.38);
uniform vec3 color_shadow : source_color = vec3(0.48, 0.28, 0.32);
uniform vec3 color_crest : source_color = vec3(1.00, 0.80, 0.55);
uniform float glitter_density : hint_range(0.9, 1.0) = 0.985;
// 風紋(風が作る砂のさざ波)。wind_dir は風向き(xz)。畝は風に直交して並ぶ
uniform vec2 wind_dir = vec2(0.55, 0.84);
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.5;

varying vec3 wpos;
varying vec3 wnormal;
varying float glitter;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 面の向きと砂粒ノイズで色味を変化させる
	float grain = hash12(floor(wpos.xz * 24.0));
	float shade = clamp(wnormal.y * 0.6 + 0.4 + (grain - 0.5) * 0.08, 0.0, 1.0);
	vec3 base = mix(color_shadow, color_lit, shade);
	// 稜線ハイライトはほぼ真上を向いた面だけに弱く。
	// 閾値が低いと斜面の小凹凸に細い明色の筋が出るため狭く・弱くする
	float crest = smoothstep(0.965, 1.0, wnormal.y);
	base = mix(base, color_crest, crest * 0.15);
	ALBEDO = base;
	ROUGHNESS = 0.85;

	// --- 風紋: 足元〜中景だけに出る砂のさざ波(法線の凹凸+わずかな明暗) ---
	// 遠景では消してタイリング感・モアレを防ぐ。頂点は動かさないので当たり判定に影響なし
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float fade = (1.0 - smoothstep(9.0, 24.0, dist)) * ripple_strength;
	// 視線が斜面を掠める角度では消す(遠くの砂丘に等高線状の縞が出るのを防ぐ)
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - wpos);
	fade *= smoothstep(0.18, 0.55, dot(to_cam, wnormal));
	if (fade > 0.003) {
		vec2 wd = normalize(wind_dir);
		float along = dot(wpos.xz, wd);                  // 風下方向の距離
		float across = dot(wpos.xz, vec2(-wd.y, wd.x));  // 畝が並ぶ方向
		// 畝をゆるくうねらせて「まっすぐな縞」に見せない(強すぎると輪に見えるので控えめ)
		float wobble = sin(along * 0.23) * 0.8 + sin(along * 0.07 + 1.7) * 1.2;
		float ph = (across + wobble) * 12.0;             // 波長 ≈ 0.5m(細かい=質感として読める)
		// 風下側がなだらか・風上側が急な非対称の畝(実物の風紋の形)。
		// 朝日が低く陰影が付きすぎるため、法線の傾けはごく弱くする
		float slope = (cos(ph) + 0.55 * cos(ph * 2.0)) * fade;
		vec3 t = vec3(-wd.y, 0.0, wd.x);                 // 畝に直交する水平方向
		vec3 n = normalize(wnormal + t * slope * 0.22);
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		// 法線だけだと日陰で見えないので、明暗でも畝を描く(日向は法線が主役)。
		// 粗いノイズで縞の濃さをまだらにして「定規で引いた線」に見せない
		float rip_var = 0.55 + 0.9 * hash12(floor(wpos.xz * 5.0));
		ALBEDO *= 1.0 + (sin(ph) + 0.4 * sin(ph * 2.0 + 0.8)) * 0.055 * fade * rip_var;
	}

	// キラッと光る砂粒のマスク(light()で使う)
	float sp = hash12(floor(wpos.xz * 60.0));
	glitter = step(glitter_density, sp);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ndl * ATTENUATION;

	float nh = clamp(dot(NORMAL, normalize(VIEW + LIGHT)), 0.0, 1.0);
	// 広く柔らかい艶(指数低め・弱め)。斜面に沿った細い筋を出さない
	float sheen = pow(nh, 8.0) * 0.04;
	// 砂粒のきらめき: まばらな点にだけ鋭く出す(筋にならない)
	float sparkle = pow(nh, 220.0) * glitter * 1.2;
	SPECULAR_LIGHT += LIGHT_COLOR * (sheen + sparkle) * ndl * ATTENUATION;
}
