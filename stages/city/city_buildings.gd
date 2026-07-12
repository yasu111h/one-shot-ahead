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

# --- 小窓の部屋(装飾窓グリッドの1マスぶんの開口。ガラスは小さいまま) ---
# 窓グリッド定数は building_windows.gdshader / window_break.gd と一致させること
const WIN_W := 1.7
const FLOOR_H := 3.2
const CELL_X0 := 0.20
const CELL_X1 := 0.86
const CELL_Y0 := 0.24
const CELL_Y1 := 0.80

## 標的ビル正面の小窓部屋(窓グリッドのセル座標 [cu, cv])。大部屋と重ならない位置。
## 改修(2026-07-12): 標的の1棟集中をやめ4棟へ分散したため、このビルの小窓は1つに減量
const SMALL_ROOM_CELLS := [
	[4, 12],    # 右上(x≈8, y≈40)
]

## 遠距離の狙撃塔 [中心x, 手前面z, 高さ, 部屋のセルv]。数百m先の小窓に標的が立つ。
## xは標的ビル(±20m)の脇を射線が抜けられる位置に置く(レイキャストで検証済み)。
## 3本目は約880m先の超高層ペンシルタワー(超遠距離の見せ場)。
## メインビルの屋上(y=48)越しに最上部の部屋(y≈113)を狙う
const FAR_TOWERS := [
	[-75.0, -430.0, 70.0, 11],   # 約480m先・左手(標的ビルの左脇を抜く)
	[60.0, -620.0, 90.0, 17],    # 約660m先・右手(標的ビルの右脇を抜く)
	[-8.0, -840.0, 125.0, 35],   # 約880m先・正面奥(標的ビルの屋上越し)
]

# --- 中距離ビル(棟2・約370m先の左手) ---
const MID_X := -48.0             # 中心x
const MID_HW := 10.0             # 半幅
const MID_FACADE_Z := -330.0     # 正面の壁の外面z
const MID_H := 46.0              # 高さ
const MID_BAND_D := 3.0          # 部屋の帯の奥行き
const MID_DEPTH := 16.0          # ビル全体の奥行き

var small_rooms: Array[Vector3] = []   # 小窓部屋の標的スポーン点(ワールド。ステージが読む)
var civil_rooms: Array[Vector3] = []   # 民間人が立つ部屋のスポーン点(撃てば即FAIL)
var mid_walk_from := Vector3.ZERO      # 中距離ビルの広間を歩く悪人の往復点
var mid_walk_to := Vector3.ZERO
var side_walks: Array = []             # サイドビル広間の往復点 [{from, to}]（ワールド）
var side_stands: Array[Vector3] = []   # サイドビルの小窓の立ち見張り
var roof_stands: Array[Vector3] = []   # ★屋上の見張り（B応戦で撃ち返してくる敵）

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
	_build_mid_building()
	_build_far_towers()
	_build_side_buildings()
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


## 地面。ワールド座標シェーダで「街区・道路・歩道・街灯の光だまり」を描く
## （ビル窓と同じ流儀）。4km四方＝どこまで見ても街の地表が続く
func _build_ground() -> void:
	var g := PlaneMesh.new()
	g.size = Vector2(4000.0, 4000.0)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/city_ground.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = g
	mi.material_override = m
	add_child(mi)
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4000.0, 1.0, 4000.0)
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

## 部屋の「空洞」Rect。開口(窓)より狭い空間に人型(横倒し1.5m)が収まらないと、
## 倒れた死体が周囲の詰まった箱にめり込み、押し出されて空中に静止する
## （「死体が宙に浮く」バグの原因）。開口はそのまま、裏の空洞だけ横へ広げる
static func room_cavity(rect: Rect2, min_w := 2.2) -> Rect2:
	if rect.size.x >= min_w:
		return rect
	var grow := (min_w - rect.size.x) * 0.5
	return Rect2(rect.position.x - grow, rect.position.y, min_w, rect.size.y)


## 窓グリッドのセル[cu, cv]の「窓ガラス部分」のRect(シェーダの描く窓と正確に一致する)
static func cell_rect(cu: int, cv: int) -> Rect2:
	return Rect2(
		(float(cu) + CELL_X0) * WIN_W, (float(cv) + CELL_Y0) * FLOOR_H,
		(CELL_X1 - CELL_X0) * WIN_W, (CELL_Y1 - CELL_Y0) * FLOOR_H)


func _build_target_building() -> void:
	var mat := _win_mat(23.0, 0.30, 0.2)

	# 小窓部屋の開口(装飾窓の1マスと同じ位置・同じ大きさ。ガラスは小さいまま)
	var small_rects: Array[Rect2] = []
	for c in SMALL_ROOM_CELLS:
		small_rects.append(cell_rect(c[0], c[1]))

	# 正面の壁：窓の開口だけを穴として残し、残りをグリッドで埋める
	var openings: Array[Rect2] = []
	for r in ROOMS:
		openings.append(Rect2(r[0] - OPEN_W * 0.5, r[1] + SILL, OPEN_W, OPEN_H))
	openings.append_array(small_rects)
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
	for r in small_rects:
		rooms.append(room_cavity(r))   # 小窓部屋の空洞（開口より広い）も帯に空ける
	var band_zc := (BAND_Z0 + BAND_Z1) * 0.5
	var band_d := BAND_Z0 - BAND_Z1
	_grid_fill(band_zc, band_d, rooms, mat)

	# 小窓部屋の内装・灯り・ガラス・スポーン点
	for rect in small_rects:
		_build_small_room(rect, FACADE_Z, BAND_Z0, BAND_Z1)

	# ビル本体(部屋より奥の詰まった塊)
	_box(Vector3(X_MAX - X_MIN, Y_MAX - Y_MIN, BAND_Z1 - MASS_Z1),
		Vector3(0.0, (Y_MIN + Y_MAX) * 0.5, (BAND_Z1 + MASS_Z1) * 0.5), mat, true)

	# 屋上のパラペット（見張りの土台・シルエットが夜空に浮く）＋屋上の見張り2体。
	# 正面のZは本体の手前面(FACADE_Z)に合わせ、遮蔽なしで撃ち合える
	_box(Vector3(X_MAX - X_MIN, 0.9, 1.0), Vector3(0.0, Y_MAX + 0.45, FACADE_Z - 0.5), _concrete, true)
	roof_stands.append(Vector3(-8.0, Y_MAX + 0.95, FACADE_Z - 1.6))
	roof_stands.append(Vector3(9.0, Y_MAX + 0.95, FACADE_Z - 1.6))

	for i in ROOMS.size():
		_build_room(ROOMS[i][0], ROOMS[i][1], band_zc, band_d)


## 壁面を格子に分割し、穴(holes)以外のセルを箱で埋める。
## 穴の縁が境界線になるので、窓まわりに窓台・まぐさ・方立が自然に出来る。
## x0..x1/y0..y1で壁面の範囲を指定できる(既定は標的ビルの正面)
func _grid_fill(z_center: float, z_depth: float, holes: Array[Rect2], mat: Material,
		x_min := X_MIN, x_max := X_MAX, y_min := Y_MIN, y_max := Y_MAX) -> void:
	var xs: Array[float] = [x_min, x_max]
	var ys: Array[float] = [y_min, y_max]
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


## 小窓部屋: 装飾窓1マスぶんの開口の裏にある小さな空間。
## 内装(暖色)・灯り・小さなガラス・立ち標的のスポーン点を作る。
## rect=開口(壁面座標)、facade_z=正面壁の外面z、band_z0/band_z1=空洞の手前/奥
## spawn_kind: "hostile"=悪人スポーン点 / "civilian"=民間人 / "none"=スポーンなし(呼び出し側が置く)
func _build_small_room(rect: Rect2, facade_z: float, band_z0: float, band_z1: float,
		spawn_kind := "hostile") -> void:
	var cx := rect.position.x + rect.size.x * 0.5
	var fy := rect.position.y            # 開口の下端=部屋の床
	var w := rect.size.x
	var h := rect.size.y
	var zc := (band_z0 + band_z1) * 0.5
	var zd := band_z0 - band_z1
	# 内装は「空洞」サイズで作る（開口より広い＝倒れた死体が横たわれる）
	var cav := room_cavity(rect)
	var cav_cx := cav.position.x + cav.size.x * 0.5
	var cw := cav.size.x

	# 内装(床・天井・左右・奥)。薄い暖色パネル
	_box(Vector3(cw, 0.1, zd), Vector3(cav_cx, fy + 0.05, zc), _warm_wall, true)
	_box(Vector3(cw, 0.1, zd), Vector3(cav_cx, fy + h - 0.05, zc), _warm_wall, false)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.1, h, zd), Vector3(cav_cx + sx * (cw * 0.5 - 0.05), fy + h * 0.5, zc), _warm_wall, false)
	_box(Vector3(cw, h, 0.1), Vector3(cav_cx, fy + h * 0.5, band_z1 + 0.05), _warm_wall, true)

	# 灯り(小さい部屋なので控えめ。夜景の中で「そこに誰かいる」と分かる)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.5)
	light.light_energy = 1.6
	light.omni_range = 4.0
	light.shadow_enabled = false
	light.position = Vector3(cx, fy + h - 0.3, zc)
	add_child(light)

	# 開口に小さなガラス(撃つと割れる。弾は止めない=レイヤ5)
	var pane := GlassPane.new(Vector2(w, h))
	add_child(pane)
	pane.position = Vector3(cx, fy + h * 0.5, (facade_z + band_z0) * 0.5)

	# 立ち標的のスポーン点(胴体中心)。部屋の中央やや窓寄り
	match spawn_kind:
		"hostile":
			small_rooms.append(Vector3(cx, fy + 0.95, zc + 0.3))
		"civilian":
			civil_rooms.append(Vector3(cx, fy + 0.95, zc + 0.3))
		_:
			pass


## 中距離ビル(棟2・約370m先の左手)。灯った部屋が3つ:
##   広間(y18): 悪人が歩き回り、窓際に民間人が立つ＝誤射禁止の緊張
##   小部屋(y30): 見張りの悪人が窓辺に立つ
##   小部屋(y38): 民間人だけが灯りの中にいる「はずれ部屋」(撃てば即FAIL)
func _build_mid_building() -> void:
	var mat := _win_mat(57.0, 0.28, 0.22)
	var facade_t := 0.7
	var band_z0 := MID_FACADE_Z - facade_t
	var band_z1 := band_z0 - MID_BAND_D
	var x0 := MID_X - MID_HW
	var x1 := MID_X + MID_HW

	# 部屋の開口。広間は横長(窓幅2.6m)＝部屋(4.8m)より狭い。歩く悪人が現れる一瞬を作る
	var hall := Rect2(MID_X - 1.3, 18.0 + 0.35, 2.6, 2.45)
	var watch := Rect2(MID_X + 3.4, 30.0 + 0.3, 1.3, 1.9)
	var decoy := Rect2(MID_X - 5.2, 38.0 + 0.3, 1.3, 1.9)
	var holes: Array[Rect2] = [hall, watch, decoy]

	# 正面の壁は「開口」だけ穴。帯は「部屋の空洞」で穴を空ける
	# （開口幅のまま帯を掘ると、部屋を歩く悪人が詰まった箱の中を歩き、
	#   倒れた死体が壁に押し出されて宙に浮く）
	var hall_cav := Rect2(MID_X - 2.4, 18.0 + 0.35, 4.8, 2.45)
	var band_holes: Array[Rect2] = [hall_cav, room_cavity(watch), room_cavity(decoy)]
	_grid_fill(MID_FACADE_Z - facade_t * 0.5, facade_t, holes, mat, x0, x1, 0.0, MID_H)
	_grid_fill((band_z0 + band_z1) * 0.5, MID_BAND_D, band_holes, mat, x0, x1, 0.0, MID_H)
	_box(Vector3(MID_HW * 2.0, MID_H, MID_DEPTH - facade_t - MID_BAND_D),
		Vector3(MID_X, MID_H * 0.5, band_z1 - (MID_DEPTH - facade_t - MID_BAND_D) * 0.5), mat, true)

	# 広間: 部屋そのものは開口より広い(内寸4.8m)。悪人はこの中を往復し、
	# 窓(2.6m)に現れた一瞬だけ撃てる。民間人は窓の右端に立ちすくむ
	var hall_room := Rect2(MID_X - 2.4, 18.0 + 0.35, 4.8, 2.45)
	_build_small_room(hall_room, MID_FACADE_Z, band_z0, band_z1, "none")
	var hall_y := 18.0 + 0.35 + 0.95
	var hall_z := (band_z0 + band_z1) * 0.5
	mid_walk_from = Vector3(MID_X - 1.9, hall_y, hall_z)
	mid_walk_to = Vector3(MID_X + 1.9, hall_y, hall_z)
	civil_rooms.append(Vector3(MID_X + 1.15, hall_y, hall_z + 0.55))

	# 見張りの小部屋(悪人)と、民間人だけの「はずれ部屋」
	_build_small_room(watch, MID_FACADE_Z, band_z0, band_z1, "hostile")
	_build_small_room(decoy, MID_FACADE_Z, band_z0, band_z1, "civilian")

	# 屋上の赤い航空障害灯(遠目にもビルの存在が読める)
	var beacon := OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.2, 0.15)
	beacon.light_energy = 0.7
	beacon.omni_range = 8.0
	beacon.shadow_enabled = false
	beacon.position = Vector3(MID_X, MID_H + 1.2, MID_FACADE_Z - 6.0)
	add_child(beacon)


## 遠距離の狙撃塔。正面(+Z側)に小窓部屋が1つだけ灯る高層タワー
func _build_far_towers() -> void:
	var i := 0
	for t in FAR_TOWERS:
		var cx: float = t[0]
		var fz: float = t[1]          # 手前面のz
		var h: float = t[2]
		var cv: int = t[3]
		var hw := 8.0                 # 半幅
		var facade_t := 0.7
		var band_d := 2.6
		var depth := 14.0
		var mat := _win_mat(300.0 + float(i) * 11.3, 0.26, 0.25)

		# 開口セル: 塔の中心に最も近い窓セル
		var cu := roundi(cx / WIN_W - 0.5)
		var rect := cell_rect(cu, cv)

		# 正面の壁(開口だけ穴)→空洞の帯(部屋の空洞＝開口より広く掘る)→本体
		_grid_fill(fz - facade_t * 0.5, facade_t, [rect] as Array[Rect2], mat, cx - hw, cx + hw, 0.0, h)
		_grid_fill(fz - facade_t - band_d * 0.5, band_d, [room_cavity(rect)] as Array[Rect2],
			mat, cx - hw, cx + hw, 0.0, h)
		_box(Vector3(hw * 2.0, h, depth - facade_t - band_d),
			Vector3(cx, h * 0.5, fz - facade_t - band_d - (depth - facade_t - band_d) * 0.5), mat, true)

		# 小窓部屋(内装・灯り・ガラス・スポーン点)
		_build_small_room(rect, fz, fz - facade_t, fz - facade_t - band_d)
		i += 1


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

## プレイヤーと標的を結ぶ射線・道路の回廊は空ける（ここに建てると狙撃/走行できない）。
## [x_min, x_max, z_min, z_max]
## ランダムビルはz≧-240にしか湧かないが、超遠距離タワーの射線も念のため深くまで守る
const CLEAR_LANES := [
	[-34.0, 34.0, -900.0, 72.0],     # メイン通り＋中央射線(超遠距離タワーまで)
	[-80.0, -20.0, -440.0, -180.0],  # 左手の射線(中距離ビル370m・狙撃塔480m)
	[20.0, 70.0, -250.0, -180.0],    # 右手の射線(狙撃塔660mへの抜け)
	[-210.0, 210.0, -129.0, -111.0], # クロス通り(信号待ちのVIP車が走る)
	[34.0, 130.0, -55.0, 40.0],      # 右手サイドビル(棟6)の敷地＋射線
	[-125.0, -34.0, -80.0, 40.0],    # 左手サイドビル(棟7)の敷地＋射線
]

func _in_corridor(x: float, z: float, pad := 0.0) -> bool:
	for l in CLEAR_LANES:
		if x > l[0] - pad and x < l[1] + pad and z > l[2] - pad and z < l[3] + pad:
			return true
	return false


# ---------------------------------------------------------------- サイドビル(棟6・棟7)

## 視点を左右へ振った先の標的ビル（2026-07-12ユーザー指示：中央集中の解消）。
## 回転したコンテナの中にローカル座標で組む＝正面(ローカル+Z)がプレイヤーを向く。
##   広間: 開口(2.8m)より広い部屋(5.6m)を悪人が往復＝窓に現れた一瞬だけ撃てる
##   小窓: 見張りの悪人が立つ／広間の窓際に民間人（誤射禁止の緊張は維持）
##   屋上: 見張りが立つ（遮蔽なしのご褒美標的。夜空を背にシルエットが浮かぶ）
func _build_side_buildings() -> void:
	# 右手（プレイヤーから約115m・yaw≈-54°）／左手（約135m・yaw≈+49°）。
	# どちらも屋上に見張り（B応戦で撃ち返してくる敵になる）
	_build_side_building(Vector3(100.0, 0.0, -30.0), 71.0)
	_build_side_building(Vector3(-95.0, 0.0, -55.0), 83.0)


func _build_side_building(origin: Vector3, seed_v: float) -> void:
	var hw := 9.0        # 半幅
	var h := 34.0        # 高さ
	var depth := 16.0
	var ft := 0.7        # 正面壁の厚み
	var bd := 2.8        # 部屋の帯の奥行き
	var player := Vector3(8.6, 0.0, 35.4)   # 狙撃地点（水平投影）

	# コンテナ：ローカル+Z面（正面）がプレイヤーを向く回転
	var to_player := player - origin
	var root := StaticBody3D.new()
	root.collision_layer = 0b0001
	root.collision_mask = 0
	root.position = origin
	root.rotation.y = atan2(to_player.x, to_player.z)
	add_child(root)
	var mat := _win_mat(seed_v, 0.30, 0.25)

	# 開口（正面壁ローカルXY・下端y）。広間=横長／小窓=見張り
	var hall := Rect2(-1.4, 20.35, 2.8, 2.3)
	var watch := Rect2(3.6, 26.3, 1.2, 1.8)
	var holes: Array[Rect2] = [hall, watch]   # 正面壁の穴＝開口
	# 帯の穴＝部屋の空洞（開口より広く掘る。狭いと死体が壁に載って宙に浮く）
	var hall_room := Rect2(-2.8, hall.position.y, 5.6, hall.size.y)
	var band_holes: Array[Rect2] = [hall_room, room_cavity(watch)]

	# 正面の壁（開口だけ穴）→部屋の帯→本体
	var fz := depth * 0.5                 # 正面の外面（ローカル+Z）
	var band_z0 := fz - ft                # 部屋の帯（手前/奥）
	var band_z1 := band_z0 - bd
	_grid_fill_in(root, fz - ft * 0.5, ft, holes, mat, -hw, hw, 0.0, h)
	_grid_fill_in(root, (band_z0 + band_z1) * 0.5, bd, band_holes, mat, -hw, hw, 0.0, h)
	# 本体（部屋の帯より奥〜背面までの詰まった塊）
	_box_in(root, Vector3(hw * 2.0, h, band_z1 + depth * 0.5),
		Vector3(0.0, h * 0.5, (band_z1 - depth * 0.5) * 0.5), mat, true)

	# 広間（内寸5.6m＝開口2.8mより広い）：内装・灯り・ガラス・往復点
	var zc := (band_z0 + band_z1) * 0.5
	_side_room_in(root, hall_room, fz, band_z0, band_z1)
	var wy := hall.position.y + 0.95
	side_walks.append({
		"from": root.to_global(Vector3(-2.3, wy, zc)),
		"to": root.to_global(Vector3(2.3, wy, zc)),
	})
	# 民間人：広間の窓際・右端（撃てば即FAIL）
	civil_rooms.append(root.to_global(Vector3(1.25, wy, zc + 0.5)))

	# 小窓の見張り
	_side_room_in(root, watch, fz, band_z0, band_z1)
	side_stands.append(root.to_global(
		Vector3(watch.position.x + watch.size.x * 0.5, watch.position.y + 0.95, zc + 0.3)))

	# 屋上の見張り（正面寄り・遮蔽なし）＋屋上の縁と塔屋（シルエットの土台）
	_box_in(root, Vector3(hw * 2.0 + 0.4, 0.9, 0.7), Vector3(0.0, h + 0.45, fz - 0.35), _concrete, true)
	_box_in(root, Vector3(2.2, 2.2, 2.2), Vector3(-hw + 2.6, h + 1.1, -2.0), _concrete, true)
	roof_stands.append(root.to_global(Vector3(2.0, h + 0.95, fz - 1.6)))

	# 屋上の赤い航空障害灯（遠目でもビルの存在が読める）
	var beacon := OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.2, 0.15)
	beacon.light_energy = 0.7
	beacon.omni_range = 8.0
	beacon.shadow_enabled = false
	beacon.position = Vector3(0.0, h + 1.4, -2.0)
	root.add_child(beacon)


## _box のローカル版（親ノード指定）。コリジョンも親に付く
func _box_in(parent: Node, size: Vector3, pos: Vector3, mat: Material, coll: bool) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if coll:
		var shape := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = size
		shape.shape = bx
		shape.position = pos
		parent.add_child(shape)
	return mi


## _grid_fill のローカル版（親ノード指定・親のローカル座標で組む）
func _grid_fill_in(parent: Node, z_center: float, z_depth: float, holes: Array[Rect2],
		mat: Material, x_min: float, x_max: float, y_min: float, y_max: float) -> void:
	var xs: Array[float] = [x_min, x_max]
	var ys: Array[float] = [y_min, y_max]
	for hole in holes:
		xs.append(hole.position.x)
		xs.append(hole.end.x)
		ys.append(hole.position.y)
		ys.append(hole.end.y)
	xs = _uniq_sorted(xs)
	ys = _uniq_sorted(ys)
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var w := xs[i + 1] - xs[i]
			var hh := ys[j + 1] - ys[j]
			if w < 0.01 or hh < 0.01:
				continue
			var c := Vector2(xs[i] + w * 0.5, ys[j] + hh * 0.5)
			var inside := false
			for hole in holes:
				if hole.has_point(c):
					inside = true
					break
			if inside:
				continue
			_box_in(parent, Vector3(w, hh, z_depth), Vector3(c.x, c.y, z_center), mat, true)


## _build_small_room のローカル版（rootの中に内装・灯り・ガラスを組む）
func _side_room_in(root: Node3D, rect: Rect2, fz: float, band_z0: float, band_z1: float) -> void:
	# 内装は「空洞」サイズで作る（開口より広い＝倒れた死体が横たわれる）
	var cav := room_cavity(rect)
	var cx := cav.position.x + cav.size.x * 0.5
	var fy := cav.position.y
	var w := cav.size.x
	var h := cav.size.y
	var zc := (band_z0 + band_z1) * 0.5
	var zd := band_z0 - band_z1
	_box_in(root, Vector3(w, 0.1, zd), Vector3(cx, fy + 0.05, zc), _warm_wall, true)
	_box_in(root, Vector3(w, 0.1, zd), Vector3(cx, fy + h - 0.05, zc), _warm_wall, false)
	for sx in [-1.0, 1.0]:
		_box_in(root, Vector3(0.1, h, zd),
			Vector3(cx + sx * (w * 0.5 - 0.05), fy + h * 0.5, zc), _warm_wall, false)
	_box_in(root, Vector3(w, h, 0.1), Vector3(cx, fy + h * 0.5, band_z1 + 0.05), _warm_wall, true)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.5)
	light.light_energy = 1.8
	light.omni_range = 4.5
	light.shadow_enabled = false
	light.position = Vector3(cx, fy + h - 0.3, zc)
	root.add_child(light)
	var pane := GlassPane.new(Vector2(w, h))
	root.add_child(pane)
	pane.position = Vector3(cx, fy + h * 0.5, (fz + band_z0) * 0.5)


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
		var dpt := rng.randf_range(20.0, 34.0)
		# 射線・道路の保護レーンに掛かる遠景ビルは建てない
		# (中距離ビル370m・狙撃塔480/660m・超遠距離880mへの射線を確実に通す)
		if _in_corridor(bx, bz, bw * 0.5):
			continue
		var m := _win_mat(100.0 + float(i) * 3.7, 0.24, 0.25)
		# こちらも当たり判定あり（遠景でも撃てば手前の壁で止まる）
		_box(Vector3(bw, bh, dpt), Vector3(bx, bh * 0.5, bz), m, true)

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
