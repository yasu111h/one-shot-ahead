class_name CityBuildings
extends StaticBody3D
## 夜の高層ビル街（TABIJIの city_buildings.gd を狙撃距離に合わせて作り直したもの）。
##
## プレイヤーは手前のビルの屋上(パラペット＋鉄パイプの手すり＋室外機)に伏せ、
## 通りの向こう約200m先の雑居ビルの、灯りの点いた3つの部屋を狙う。
## 部屋の開口は部屋そのものより狭い＝中で動く標的が「一瞬だけ窓に現れる」。
##
## 座標系: プレイヤーのビルが +Z 側(屋上 y=30)、標的のビルが -Z 側(正面 z=-160)。
## 当たり判定は全て地形レイヤ(1)。弾はここで止まる。

const WIN_SHADER := preload("res://shaders/building_windows.gdshader")

const ROOF_Y := 30.0             # プレイヤーの屋上の高さ

# --- 標的のビル ---
const X_MIN := -20.0
const X_MAX := 20.0
const Y_MIN := 0.0
const Y_MAX := 48.0
const FACADE_Z := -160.0         # 正面の壁(この面に窓の開口が空く)
const FACADE_T := 0.7            # 正面の壁の厚み
const BAND_Z0 := FACADE_Z - FACADE_T   # 部屋の帯(手前)
const BAND_Z1 := -167.4                # 部屋の帯(奥)
const MASS_Z1 := -190.0                # ビル本体の奥行き

const ROOM_W := 10.0             # 部屋の内寸(幅)
const ROOM_H := 4.0              # 部屋の内寸(高さ)
const OPEN_W := 5.0              # 窓の開口(幅)。部屋より狭い＝ここに現れた時だけ撃てる
const SILL := 0.35               # 窓の下端(床から)
const OPEN_H := 3.05             # 窓の開口(高さ)

## 標的の部屋 [中心x, 床の高さy]
const ROOMS := [
	[-11.0, 16.0],
	[2.0, 24.0],
	[12.0, 33.0],
]

var _metal: StandardMaterial3D
var _concrete: StandardMaterial3D
var _warm_wall: StandardMaterial3D
var _dark_wood: StandardMaterial3D


func _ready() -> void:
	collision_layer = 0b0001   # 地形レイヤ（弾はここで止まる）
	collision_mask = 0
	_make_materials()
	_build_ground()
	_build_player_building()
	_build_target_building()
	_build_towers()
	_build_street_glow()


## 部屋の中心（標的の配置と部屋の明かりに使う）
static func room_center(i: int) -> Vector3:
	return Vector3(ROOMS[i][0], ROOMS[i][1], (BAND_Z0 + BAND_Z1) * 0.5)


func _make_materials() -> void:
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.16, 0.18, 0.21)
	_metal.metallic = 0.7
	_metal.roughness = 0.45

	_concrete = StandardMaterial3D.new()
	_concrete.albedo_color = Color(0.14, 0.15, 0.17)
	_concrete.roughness = 0.95

	_warm_wall = StandardMaterial3D.new()
	_warm_wall.albedo_color = Color(0.52, 0.42, 0.30)
	_warm_wall.roughness = 0.9

	_dark_wood = StandardMaterial3D.new()
	_dark_wood.albedo_color = Color(0.22, 0.15, 0.10)
	_dark_wood.roughness = 0.8


func _box(size: Vector3, pos: Vector3, mat: Material, coll: bool) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if coll:
		var shape := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = size
		shape.shape = bx
		shape.position = pos
		add_child(shape)
	return mi


## ビル用の窓明かりマテリアル(ビルごとにseedと点灯率を変える)
func _win_mat(seed_v: float, lit: float, warm: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WIN_SHADER
	m.set_shader_parameter("seed", seed_v)
	m.set_shader_parameter("lit_ratio", lit)
	m.set_shader_parameter("warm_ratio", warm)
	return m


## 地面(通り)。夜露に濡れたアスファルト(街明かりをわずかに映す)
func _build_ground() -> void:
	var g := PlaneMesh.new()
	g.size = Vector2(700.0, 700.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.026, 0.030, 0.040)
	m.roughness = 0.45
	var mi := MeshInstance3D.new()
	mi.mesh = g
	mi.material_override = m
	add_child(mi)
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(700.0, 1.0, 700.0)
	shape.shape = bx
	shape.position = Vector3(0.0, -0.5, 0.0)
	add_child(shape)


## プレイヤーのビル。屋上にパラペット・鉄パイプの手すり・室外機・配管
func _build_player_building() -> void:
	_box(Vector3(20.0, ROOF_Y, 20.0), Vector3(0.0, ROOF_Y * 0.5, 44.0),
		_win_mat(11.0, 0.22, 0.3), true)
	_box(Vector3(20.0, 0.2, 20.0), Vector3(0.0, ROOF_Y + 0.1, 44.0), _concrete, true)

	# パラペット(四辺の低い立ち上がり)
	for e in [[Vector3(20.4, 1.0, 0.8), Vector3(0.0, ROOF_Y + 0.7, 33.8)],
			[Vector3(20.4, 1.0, 0.8), Vector3(0.0, ROOF_Y + 0.7, 54.2)],
			[Vector3(0.8, 1.0, 20.4), Vector3(-10.2, ROOF_Y + 0.7, 44.0)],
			[Vector3(0.8, 1.0, 20.4), Vector3(10.2, ROOF_Y + 0.7, 44.0)]]:
		_box(e[0], e[1], _concrete, true)

	# 前縁の鉄パイプ手すり(2段+支柱)。当たり判定なし＝弾は抜ける
	# パラペットの上に載る高さに留める（これより高いと構えた目線を横切って標的が隠れる）
	for h in [0.55, 1.15]:
		var pipe := CylinderMesh.new()
		pipe.top_radius = 0.05
		pipe.bottom_radius = 0.05
		pipe.height = 19.0
		var mi := MeshInstance3D.new()
		mi.mesh = pipe
		mi.material_override = _metal
		mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		mi.position = Vector3(0.0, ROOF_Y + 0.2 + h, 33.9)
		add_child(mi)
	for px in [-9.0, -4.5, 0.0, 4.5, 9.0]:
		_box(Vector3(0.09, 1.25, 0.09), Vector3(px, ROOF_Y + 0.78, 33.9), _metal, false)

	# 室外機・塔屋・配管
	_box(Vector3(3.4, 2.0, 1.6), Vector3(-6.5, ROOF_Y + 1.2, 40.0), _metal, true)
	_box(Vector3(1.2, 2.6, 1.2), Vector3(7.0, ROOF_Y + 1.5, 48.0), _concrete, true)
	_box(Vector3(0.14, 0.14, 12.0), Vector3(9.2, ROOF_Y + 0.3, 44.0), _metal, false)


# ---------------------------------------------------------------- 標的のビル

func _build_target_building() -> void:
	var mat := _win_mat(23.0, 0.30, 0.2)

	# 正面の壁：窓の開口だけを穴として残し、残りをグリッドで埋める
	var openings: Array[Rect2] = []
	for r in ROOMS:
		openings.append(Rect2(r[0] - OPEN_W * 0.5, r[1] + SILL, OPEN_W, OPEN_H))
	_grid_fill((FACADE_Z + BAND_Z0) * 0.5, FACADE_T, openings, mat)

	# 開口に窓ガラスをはめる（撃つと割れる。弾は止めない＝レイヤ5）
	for r in ROOMS:
		var pane := GlassPane.new(Vector2(OPEN_W, OPEN_H))
		add_child(pane)
		pane.position = Vector3(r[0], r[1] + SILL + OPEN_H * 0.5, (FACADE_Z + BAND_Z0) * 0.5)

	# 部屋の帯：部屋そのものを穴として残し、残りをグリッドで埋める
	var rooms: Array[Rect2] = []
	for r in ROOMS:
		rooms.append(Rect2(r[0] - ROOM_W * 0.5, r[1], ROOM_W, ROOM_H))
	var band_zc := (BAND_Z0 + BAND_Z1) * 0.5
	var band_d := BAND_Z0 - BAND_Z1
	_grid_fill(band_zc, band_d, rooms, mat)

	# ビル本体(部屋より奥の詰まった塊)
	_box(Vector3(X_MAX - X_MIN, Y_MAX - Y_MIN, BAND_Z1 - MASS_Z1),
		Vector3(0.0, (Y_MIN + Y_MAX) * 0.5, (BAND_Z1 + MASS_Z1) * 0.5), mat, true)

	for i in ROOMS.size():
		_build_room(ROOMS[i][0], ROOMS[i][1], band_zc, band_d)


## 壁面を格子に分割し、穴(holes)以外のセルを箱で埋める。
## 穴の縁が境界線になるので、窓まわりに窓台・まぐさ・方立が自然に出来る。
func _grid_fill(z_center: float, z_depth: float, holes: Array[Rect2], mat: Material) -> void:
	var xs: Array[float] = [X_MIN, X_MAX]
	var ys: Array[float] = [Y_MIN, Y_MAX]
	for h in holes:
		xs.append(h.position.x)
		xs.append(h.end.x)
		ys.append(h.position.y)
		ys.append(h.end.y)
	xs = _uniq_sorted(xs)
	ys = _uniq_sorted(ys)
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var w := xs[i + 1] - xs[i]
			var h := ys[j + 1] - ys[j]
			if w < 0.01 or h < 0.01:
				continue
			var c := Vector2(xs[i] + w * 0.5, ys[j] + h * 0.5)
			var inside := false
			for hole in holes:
				if hole.has_point(c):
					inside = true
					break
			if inside:
				continue
			_box(Vector3(w, h, z_depth), Vector3(c.x, c.y, z_center), mat, true)


func _uniq_sorted(v: Array[float]) -> Array[float]:
	v.sort()
	var out: Array[float] = []
	for x in v:
		if out.is_empty() or absf(out[-1] - x) > 0.005:
			out.append(x)
	return out


## 部屋の内装（暖色の壁・床・天井・家具・灯り）。この一室だけが夜景の中で暖かく灯る
func _build_room(cx: float, fy: float, zc: float, zd: float) -> void:
	_box(Vector3(ROOM_W, 0.2, zd), Vector3(cx, fy + 0.1, zc), _warm_wall, true)               # 床
	_box(Vector3(ROOM_W, 0.2, zd), Vector3(cx, fy + ROOM_H - 0.1, zc), _warm_wall, true)      # 天井
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.2, ROOM_H, zd), Vector3(cx + sx * (ROOM_W * 0.5 - 0.1), fy + ROOM_H * 0.5, zc),
			_warm_wall, true)                                                                # 左右の壁
	_box(Vector3(ROOM_W, ROOM_H, 0.2), Vector3(cx, fy + ROOM_H * 0.5, BAND_Z1 + 0.1),
		_warm_wall, true)                                                                    # 奥の壁

	# 家具（標的のシルエットが「部屋の中」に見える添え物）
	_box(Vector3(1.8, 0.8, 0.8), Vector3(cx + 3.0, fy + 0.5, BAND_Z1 + 1.2), _dark_wood, false)
	_box(Vector3(0.9, 2.2, 0.4), Vector3(cx - 3.6, fy + 1.3, BAND_Z1 + 0.6), _dark_wood, false)

	# 部屋の灯り
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.5)
	light.light_energy = 2.6
	light.omni_range = 8.5
	light.shadow_enabled = false
	light.position = Vector3(cx, fy + 3.4, zc)
	add_child(light)
	# 窓からこぼれる光(外壁をわずかに照らす)
	var spill := OmniLight3D.new()
	spill.light_color = Color(1.0, 0.75, 0.45)
	spill.light_energy = 0.8
	spill.omni_range = 6.0
	spill.shadow_enabled = false
	spill.position = Vector3(cx, fy + 2.0, FACADE_Z + 1.2)
	add_child(spill)


# ---------------------------------------------------------------- 周囲の街

## プレイヤーと標的を結ぶ射線の回廊は空ける（ここに建てると狙撃できない）
func _in_corridor(x: float, z: float, pad := 0.0) -> bool:
	return absf(x) < 34.0 + pad and z < 72.0 + pad and z > -200.0 - pad


## 周囲のタワー群。高さも点灯パターンもばらして「街」に見せる
func _build_towers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260710
	var placed := 0
	var guard := 0
	var tallest: Array = []   # 赤い航空障害灯を置く候補 [高さ, x, z]
	while placed < 44 and guard < 800:
		guard += 1
		var x := rng.randf_range(-220.0, 220.0)
		var z := rng.randf_range(-240.0, 150.0)
		if _in_corridor(x, z, 6.0):
			continue
		var w := rng.randf_range(12.0, 30.0)
		var dpt := rng.randf_range(12.0, 30.0)
		var h := rng.randf_range(16.0, 80.0)
		var mat := _win_mat(float(placed) * 7.3, rng.randf_range(0.18, 0.42), rng.randf_range(0.1, 0.35))
		# 当たり判定あり：弾・リプレイが最初に当たったビルで必ず止まる（貫通防止）
		_box(Vector3(w, h, dpt), Vector3(x, h * 0.5, z), mat, true)
		if h > 60.0:
			tallest.append([h, x, z])
		placed += 1

	# 遠景の低層ビル帯(隙間を埋めて「街が続いている」密度を出す)
	for i in 22:
		var ang := TAU * float(i) / 22.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(255.0, 300.0)
		var bx := cos(ang) * r
		var bz := sin(ang) * r
		var bw := rng.randf_range(34.0, 60.0)
		var bh := rng.randf_range(10.0, 30.0)
		var m := _win_mat(100.0 + float(i) * 3.7, 0.24, 0.25)
		# こちらも当たり判定あり（遠景でも撃てば手前の壁で止まる）
		_box(Vector3(bw, bh, rng.randf_range(20.0, 34.0)), Vector3(bx, bh * 0.5, bz), m, true)

	# 最も高い塔たちに赤い航空障害灯(ゆっくり明滅)
	var blink := Shader.new()
	blink.code = "shader_type spatial;\nrender_mode unshaded;\nuniform float seed = 0.0;\nvoid fragment() {\n\tfloat k = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(TIME * 2.2 + seed), 3.0);\n\tALBEDO = vec3(0.25, 0.0, 0.0);\n\tEMISSION = vec3(1.0, 0.08, 0.05) * k * 3.0;\n}\n"
	var i := 0
	for t in tallest:
		var m := ShaderMaterial.new()
		m.shader = blink
		m.set_shader_parameter("seed", float(i) * 2.1)
		var s := SphereMesh.new()
		s.radius = 0.45
		s.height = 0.9
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = m
		mi.position = Vector3(t[1], t[0] + 0.6, t[2])
		add_child(mi)
		i += 1


## 通りの明かり。ビルの谷間の底がぼんやり暖色に光る(遠景の街明かり)
func _build_street_glow() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.72, 0.42, 0.035)
	for s in [[Vector2(26.0, 240.0), Vector3(0.0, 0.15, -60.0)],
			[Vector2(240.0, 14.0), Vector3(0.0, 0.15, 70.0)],
			[Vector2(240.0, 14.0), Vector3(0.0, 0.15, -206.0)]]:
		var p := PlaneMesh.new()
		p.size = s[0]
		var mi := MeshInstance3D.new()
		mi.mesh = p
		mi.material_override = m
		mi.position = s[1]
		add_child(mi)
	# 通りを照らす低い街灯の光(ビルの下層をほんのり照らす)
	for lz in [10.0, -60.0, -140.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.45)
		l.light_energy = 0.6
		l.omni_range = 34.0
		l.shadow_enabled = false
		l.position = Vector3(0.0, 8.0, lz)
		add_child(l)
