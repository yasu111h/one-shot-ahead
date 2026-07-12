class_name WindfarmTerrain
extends StaticBody3D
## 風車群の丘の地形（なだらかな草の丘陵）。
## desert_terrain.gd と同じ原則：get_height() を唯一の高さの真実とし、
## 見た目のメッシュと当たり判定（HeightMapShape3D）を同じ関数から生成する。
## 風車の建つ場所と狙撃地点の丘は平場に均す。

const X_HALF := 500.0        # 横幅 ±500m
const Z_MIN := -1100.0       # 奥行き（-Z が風車群の方向）
const Z_MAX := 140.0
const MESH_STEP := 8.0       # 見た目メッシュの分割ピッチ(m)
const COL_STEP := 2.0        # 当たり判定のサンプルピッチ(m)

## 風車の建設位置（x, z）。ステージはこの並びに沿って風車・ドローンを配置する。
## 手前約180m〜最奥約900m（超遠距離の見せ場）まで散らす
const TURBINES := [
	Vector2(-62.0, -180.0),
	Vector2(74.0, -250.0),
	Vector2(-18.0, -340.0),
	Vector2(150.0, -430.0),
	Vector2(-136.0, -470.0),
	Vector2(46.0, -580.0),
	Vector2(-80.0, -700.0),
	Vector2(20.0, -900.0),
]
const PAD_R := 14.0          # 風車の基礎の平場半径

const RIG_XZ := Vector2(14.0, 22.0)   # 狙撃地点の丘（+Z側の高台）
const RIG_R := 13.0
const RIG_RAISE := 7.0       # 周囲より一段高くして風車群を見渡す

var _base := FastNoiseLite.new()     # 大きなうねり（丘陵）
var _roll := FastNoiseLite.new()     # 中くらいの起伏
var _detail := FastNoiseLite.new()   # 細かい草地の凹凸


func _init() -> void:
	_base.seed = 41
	_base.frequency = 0.0028
	_base.fractal_octaves = 3
	_roll.seed = 8
	_roll.frequency = 0.012
	_roll.fractal_octaves = 2
	_detail.seed = 19
	_detail.frequency = 0.06
	_detail.fractal_octaves = 2


func _ready() -> void:
	collision_layer = 0b0001  # レイヤ1: 地形
	collision_mask = 0
	_build_mesh()
	_build_collision()


## 地形の高さ。なだらかな丘陵に、風車の基礎と狙撃の丘を均す
func get_height(x: float, z: float) -> float:
	var h := _base.get_noise_2d(x, z) * 16.0
	h += _roll.get_noise_2d(x, z) * 4.5
	h += _detail.get_noise_2d(x, z) * 0.4
	# 奥へ行くほど緩やかに下る谷筋（風車が奥まで見渡せる）
	h += z * 0.012
	# 風車の基礎平場
	for t in TURBINES:
		h = _flatten(h, x, z, t, PAD_R, _pad_height(t))
	# 狙撃地点の丘（一段高く）
	h = _flatten(h, x, z, RIG_XZ, RIG_R, _pad_height(RIG_XZ) + RIG_RAISE)
	return h


## 平場の基準高さ（ノイズの大きなうねりだけで決める＝平場内で一定）
func _pad_height(at: Vector2) -> float:
	return _base.get_noise_2d(at.x, at.y) * 16.0 + at.y * 0.012


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
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var x := -X_HALF + ix * MESH_STEP
			var z := Z_MIN + iz * MESH_STEP
			var idx := iz * nx + ix
			verts[idx] = Vector3(x, get_height(x, z), z)
			var e := 1.5
			var dnx := get_height(x - e, z) - get_height(x + e, z)
			var dnz := get_height(x, z - e) - get_height(x, z + e)
			normals[idx] = Vector3(dnx, 2.0 * e, dnz).normalized()
	var indices := PackedInt32Array()
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			var b := a + 1
			var c := a + nx
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/hill_grass.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)


func _build_collision() -> void:
	var sx := int(X_HALF * 2.0 / COL_STEP) + 1
	var sz := int((Z_MAX - Z_MIN) / COL_STEP) + 1
	var data := PackedFloat32Array()
	data.resize(sx * sz)
	for iz in sz:
		for ix in sx:
			data[iz * sx + ix] = get_height(
				-X_HALF + ix * COL_STEP, Z_MIN + iz * COL_STEP)
	var shape := HeightMapShape3D.new()
	shape.map_width = sx
	shape.map_depth = sz
	shape.map_data = data
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	# HeightMapShapeは中心原点なので、地形の中心へオフセット
	col.position = Vector3(0.0, 0.0, (Z_MIN + Z_MAX) * 0.5)
	col.scale = Vector3(COL_STEP, 1.0, COL_STEP)
