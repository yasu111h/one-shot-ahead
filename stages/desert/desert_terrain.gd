class_name DesertTerrain
extends StaticBody3D
## 砂漠の検問所の地形。
## TABIJI（beautiful-journey）の dune_terrain.gd の考え方を流用：
## get_height() を唯一の高さの真実とし、見た目のメッシュと
## 当たり判定（HeightMapShape3D）を同じ関数から生成する。
## 起伏はこのゲーム用：狙撃塔から遠方へ延びる一本道（道路）と、
## 検問所・遠方停車帯の平場を砂丘に彫り込む。

const X_HALF := 500.0        # 横幅 ±500m
const Z_MIN := -1600.0       # 奥行き（-Z が標的方向）
const Z_MAX := 200.0
const MESH_STEP := 8.0       # 見た目メッシュの分割ピッチ(m)
const COL_STEP := 2.0        # 当たり判定のサンプルピッチ(m)

# --- 道路（x=0 を通る一本道。-Z へ延びる） ---
const ROAD_HALF := 5.0       # 道路の平坦部の半幅(m)
const ROAD_BLEND := 26.0     # 道路脇→素の砂丘へのなじみ幅(m)
const ROAD_NEAR := 6.0       # 道路が現れ始める前方距離(-z)
const ROAD_FULL := 46.0      # ここから完全な道路
const ROAD_FAR_FULL := 812.0 # ここまで完全な道路
const ROAD_FAR_END := 864.0  # ここで砂丘へ消える

# --- 平場（検問所・遠方停車帯・狙撃塔の丘） ---
const CHECKPOINT_XZ := Vector2(0.0, -378.0)
const CHECKPOINT_R := 34.0
const FAR_STOP_XZ := Vector2(0.0, -650.0)
const FAR_STOP_R := 22.0
const RIG_XZ := Vector2(12.0, -16.0)
const RIG_R := 11.0
const RIG_RAISE := 4.0       # 狙撃塔の丘は道路より一段高くする

var _base := FastNoiseLite.new()     # 大きなうねり
var _dune := FastNoiseLite.new()     # 砂丘の畝(うね)
var _detail := FastNoiseLite.new()   # 細かい起伏
var _road_wave := FastNoiseLite.new()  # 道路の長いうねり


func _init() -> void:
	_base.seed = 11
	_base.frequency = 0.004
	_base.fractal_octaves = 3
	_dune.seed = 27
	_dune.frequency = 0.018
	_dune.fractal_octaves = 2
	_detail.seed = 5
	_detail.frequency = 0.05
	_detail.fractal_octaves = 2
	_road_wave.seed = 3
	_road_wave.frequency = 0.004
	_road_wave.fractal_octaves = 1


func _ready() -> void:
	collision_layer = 0b0001  # レイヤ1: 地形
	collision_mask = 0
	_build_mesh()
	_build_collision()


## 道路のセンターラインの高さ。遠方へ緩やかに下る＋長いうねり。
## うねりは狙撃塔からの見下ろし角（約2度）より緩くし、遠方の路面が
## 手前の路面の陰に隠れないようにする
func road_height(z: float) -> float:
	return z * 0.018 + _road_wave.get_noise_1d(z) * 1.2


## 地形の高さ。素の砂丘ノイズに、道路コリドーと平場を彫り込む。
func get_height(x: float, z: float) -> float:
	var h := _base.get_noise_2d(x, z) * 13.0
	var d := _dune.get_noise_2d(x * 0.35, z)
	# 尾根(リッジ)状の砂丘。absを滑らかにして刃のような尾根を丸める
	var ridge := 1.0 - sqrt(d * d + 0.012)
	h += pow(ridge, 2.0) * 7.5
	h += _detail.get_noise_2d(x, z) * 0.3
	# 道路コリドー: 中心線に近く・道路区間内なら road_height へ均す
	var az := -z  # 前方距離
	var lat := 1.0 - smoothstep(ROAD_HALF, ROAD_HALF + ROAD_BLEND, absf(x))
	var along := smoothstep(ROAD_NEAR, ROAD_FULL, az) \
		* (1.0 - smoothstep(ROAD_FAR_FULL, ROAD_FAR_END, az))
	if lat * along > 0.0:
		h = lerpf(h, road_height(z), lat * along)
	# 平場: 検問所・遠方停車帯は道路の高さへ、狙撃塔の丘は一段高く
	h = _flatten(h, x, z, CHECKPOINT_XZ, CHECKPOINT_R, road_height(CHECKPOINT_XZ.y))
	h = _flatten(h, x, z, FAR_STOP_XZ, FAR_STOP_R, road_height(FAR_STOP_XZ.y))
	h = _flatten(h, x, z, RIG_XZ, RIG_R, road_height(RIG_XZ.y) + RIG_RAISE)
	return h


## 中心 c・半径 r の円内を floor_h へなだらかに均す
func _flatten(h: float, x: float, z: float, c: Vector2, r: float, floor_h: float) -> float:
	var dist := Vector2(x - c.x, z - c.y).length()
	var t := 1.0 - smoothstep(r * 0.45, r, dist)
	if t <= 0.0:
		return h
	return lerpf(h, floor_h, t)


func _build_mesh() -> void:
	var nx := int(X_HALF * 2.0 / MESH_STEP) + 1
	var nz := int((Z_MAX - Z_MIN) / MESH_STEP) + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	uvs.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var x := ix * MESH_STEP - X_HALF
			var z := Z_MIN + iz * MESH_STEP
			var idx := iz * nx + ix
			verts[idx] = Vector3(x, get_height(x, z), z)
			uvs[idx] = Vector2(ix / float(nx - 1), iz / float(nz - 1))
			# 法線は広め(メッシュ2セル分)に差分を取って均す（陰影の筋を防ぐ）
			var e := MESH_STEP * 2.0
			var dnx := get_height(x - e, z) - get_height(x + e, z)
			var dnz := get_height(x, z - e) - get_height(x, z + e)
			normals[idx] = Vector3(dnx, 2.0 * e, dnz).normalized()

	var indices := PackedInt32Array()
	indices.resize((nx - 1) * (nz - 1) * 6)
	var k := 0
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			var b := a + 1
			var c := a + nx
			var dd := c + 1
			# Godotの表面は「時計回り」巻き。逆巻きだと地面が裏向きになる
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = dd
			indices[k + 5] = c
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/desert_sand.gdshader")
	mi.material_override = mat
	add_child(mi)


func _build_collision() -> void:
	# COL_STEPピッチでサンプルし、CollisionShape3Dの均一scaleで実寸に広げる。
	# （非均一スケールの衝突形状は非対応のため、高さも1/COL_STEPで格納して
	#   Yスケールで実寸に戻す）
	var sx := int(X_HALF * 2.0 / COL_STEP) + 1
	var sz := int((Z_MAX - Z_MIN) / COL_STEP) + 1
	var shape := HeightMapShape3D.new()
	shape.map_width = sx
	shape.map_depth = sz
	var data := PackedFloat32Array()
	data.resize(sx * sz)
	for iz in sz:
		for ix in sx:
			data[iz * sx + ix] = get_height(
				ix * COL_STEP - X_HALF, Z_MIN + iz * COL_STEP) / COL_STEP
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(COL_STEP, COL_STEP, COL_STEP)
	cs.position = Vector3(0.0, 0.0, (Z_MIN + Z_MAX) * 0.5)
	add_child(cs)
