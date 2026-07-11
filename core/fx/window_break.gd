class_name WindowBreak
extends Object
## 装飾ビルの「シェーダ描きの窓」を撃った時に、その窓だけ割れたように見せる。
##
## ビル群の窓は building_windows.gdshader がワールド座標グリッドで描く模様であり、
## 1枚ずつの実体は存在しない。そこで着弾点と壁の法線から「どの窓セルのどちらのペインか」を
## シェーダと同じ格子計算で逆算し、その位置に GlassPane を動的に生成して即 shatter()
## ＝既存の破片・閃光・破れ残りの演出をそのまま流用する。
## さらに割れ跡デカール(ギザギザの暗い穴＋放射ヒビ)を残す。同じペインは二度割れない。
##
## 格子定数は building_windows.gdshader の値と一致させること(変えたら両方直す)。

const GlassPaneScript := preload("res://core/props/glass_pane.gd")

const WIN_W := 1.7        # 窓ピッチ(横)
const FLOOR_H := 3.2      # 階高
const X0 := 0.20          # セル内の窓の範囲(シェーダのwx/wyと同値)
const X1 := 0.86
const Y0 := 0.24
const Y1 := 0.80
const MULL := 0.53        # 中桟(ここで左右ペインに分かれる)
const MULL_HALF := 0.022

const META_KEY := "broken_facade_windows"   # 割れ済みペインの記録(ステージのmeta)


## 着弾が窓なら割って true を返す(火花・土煙は出さない側で分岐する)。
## 窓以外(壁の桟・コンクリ・屋上など)なら false。
static func try_break(stage: Node3D, point: Vector3, normal: Vector3, dir: Vector3) -> bool:
	# シェーダ窓のないステージは対象外(コンテナや船体の鉄壁でガラスが割れないように。
	# ステージ側が meta "facade_windows_enabled"=false を立てて明示的に無効化する)
	if not stage.get_meta("facade_windows_enabled", true):
		return false
	# 垂直な壁面のみ(屋上・地面は窓ではない)
	if absf(normal.y) > 0.5:
		return false

	# シェーダと同じ平面座標を選ぶ(X面はZY、Z面はXY)
	var axis_x := absf(normal.x) > absf(normal.z)
	var u := point.z if axis_x else point.x
	var v := point.y
	var fu := fposmod(u / WIN_W, 1.0)
	var fv := fposmod(v / FLOOR_H, 1.0)

	# 窓の帯の外(壁の桟・スパンドレル)は通常の着弾
	if fu < X0 or fu > X1 or fv < Y0 or fv > Y1:
		return false

	# どちらのペインか(中桟の左右)
	var left := fu < MULL
	var u0 := X0 if left else MULL + MULL_HALF
	var u1 := MULL - MULL_HALF if left else X1

	# 割れ済みチェック(壁面の位置も含めてペインを一意にする)
	var cell_u := floorf(u / WIN_W)
	var cell_v := floorf(v / FLOOR_H)
	var wall_coord := point.x if axis_x else point.z
	var key := "%s_%d_%d_%d_%s" % [
		"x" if axis_x else "z", roundi(wall_coord * 10.0), cell_u, cell_v, "L" if left else "R"]
	var registry: Dictionary = stage.get_meta(META_KEY, {})
	if registry.has(key):
		return true   # 既に割れた窓: 何も出さない(弾は穴を抜けた体)
	registry[key] = true
	stage.set_meta(META_KEY, registry)

	# ペインのワールド中心とサイズ
	var pane_w := (u1 - u0) * WIN_W
	var pane_h := (Y1 - Y0) * FLOOR_H
	var cu := (cell_u + (u0 + u1) * 0.5) * WIN_W
	var cv := (cell_v + (Y0 + Y1) * 0.5) * FLOOR_H
	var center: Vector3
	if axis_x:
		center = Vector3(point.x, cv, cu)
	else:
		center = Vector3(cu, cv, point.z)
	center += normal * 0.05   # 壁面から浮かせてZファイティングを防ぐ

	# 既存のGlassPaneをその場に生成して即割る(破片・閃光・破れ残りを流用)
	var pane := GlassPaneScript.new(Vector2(pane_w, pane_h))
	stage.add_child(pane)
	pane.global_position = center
	pane.look_at(center - normal, Vector3.UP)   # QuadMeshの表(+Z)を法線側へ
	pane.shatter(point + normal * 0.05, dir)

	# 割れ跡デカール(暗い穴＋放射ヒビ)。着弾点をペイン内UVに変換して渡す
	var iu := clampf((fu - u0) / maxf(u1 - u0, 0.001), 0.05, 0.95)
	var iv := clampf((fv - Y0) / (Y1 - Y0), 0.05, 0.95)
	_spawn_decal(stage, center, normal, Vector2(pane_w, pane_h), Vector2(iu, iv), key.hash() % 100)
	return true


## 割れ跡デカール: 窓ペインに重ねる1枚クワッド。
## ギザギザの暗い穴(ガラスが抜けた闇)＋放射状のヒビ＋同心のヒビ輪。
static func _spawn_decal(stage: Node3D, center: Vector3, normal: Vector3,
		size: Vector2, impact_uv: Vector2, seed_v: int) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec2 impact = vec2(0.5, 0.5);
uniform float seed = 0.0;

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
	vec2 p = UV - impact;
	float r = length(p);
	float a = atan(p.y, p.x);

	// ギザギザの暗い穴(ガラスの抜けた闇)
	float jag = vnoise(vec2(a * 2.2 + seed, seed));
	float hole = 1.0 - smoothstep(0.08, 0.15 + 0.10 * jag, r);

	// 放射状のヒビ(着弾点から走る細い線)
	float rays = pow(max(0.0, sin(a * 11.0 + seed * 6.0)), 70.0) * smoothstep(0.7, 0.08, r);
	// 同心のヒビ輪
	float rings = smoothstep(0.015, 0.0, abs(fract(r * 8.0 + seed) - 0.5) - 0.42)
		* smoothstep(0.55, 0.15, r) * 0.6;

	ALBEDO = vec3(0.008, 0.010, 0.018);
	EMISSION = vec3(0.45, 0.55, 0.72) * (rays + rings) * 0.7;
	ALPHA = clamp(hole * 0.95 + (rays + rings) * 0.55, 0.0, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("impact", impact_uv)
	mat.set_shader_parameter("seed", float(seed_v))

	var quad := QuadMesh.new()
	quad.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(mi)
	mi.global_position = center + normal * 0.01
	mi.look_at(mi.global_position - normal, Vector3.UP)
