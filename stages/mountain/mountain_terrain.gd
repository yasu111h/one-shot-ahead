class_name MountainTerrain
extends StaticBody3D
## 山岳ステージの地形。
## desert_terrain.gd と同じ原則：get_height() を唯一の高さの真実とし、
## 見た目のメッシュと当たり判定（HeightMapShape3D）を同じ関数から生成する。
## 尾根（リッジ）ノイズの山並みに、①プレイヤーの主峰 ②蛇行する川の谷
## ③標的の立ち場（平場パッド）を彫り込む。針葉樹はMultiMeshで散布する。

const X_HALF := 700.0        # プレイエリアの横幅 ±700m（詳細メッシュ＋当たり判定）
const Z_MIN := -1500.0       # 奥行き（-Z が標的方向）
const Z_MAX := 260.0
const MESH_STEP := 10.0      # 見た目メッシュの分割ピッチ(m)
const COL_STEP := 3.0        # 当たり判定のサンプルピッチ(m)

# --- 遠景の山地（プレイエリアの外周。同じノイズから生成＝地平線まで山が続く） ---
# 当たり判定も同じ64mグリッドで張る＝きわどく峰をかすめた弾も遠景の山肌で止まり、
# ミスリプレイのカメラが山の中へ入って裏側が見えることがない
const FAR_EXTENT := 4200.0   # 遠景の広がり ±4.2km
const FAR_STEP := 64.0       # 遠景メッシュの分割ピッチ(m)

const WATER_Y := 6.5         # 川の水面の高さ
const RIVER_BED := 2.2       # 川底の高さ

## プレイヤーの主峰（この山頂に立つ）。周囲より必ず高い「決め打ちの円錐」でつくる
const PEAK_XZ := Vector2(0.0, 60.0)
const PEAK_TOP := 165.0      # 山頂の標高
const PEAK_SLOPE := 0.9      # 円錐の斜度（急峻な岩峰＝裾が近距離の射線を遮らない）
const PEAK_R := 150.0        # 円錐がなじむ半径

## 立ち場パッド [x, z, 半径, かさ上げ]。0番はリグ(山頂)、以降は標的の立ち場。
## 2番（川辺）以外の標的パッドは「段丘ランプ上のノール（小山）」として地形に盛る
## ＝奥の標的ほど高い位置に立ち、山頂から必ず射線が通る（KNOLL_PADS参照）
const PADS := [
	[0.0, 60.0, 9.0, 0.0],        # リグ（山頂）
	[-52.0, -150.0, 10.0, 0.6],   # 約215m: 手前の尾根の肩
	[78.0, -185.0, 12.0, 0.6],    # 約260m: 川辺の草地（歩行）
	[-125.0, -430.0, 10.0, 0.6],  # 約510m: 対岸の中腹
	[160.0, -570.0, 12.0, 0.6],   # 約650m: 右手の尾根道（歩行）
	[-70.0, -760.0, 10.0, 0.6],   # 約830m: 奥の尾根の肩
	[25.0, -960.0, 10.0, 1.0],    # 約1020m: 最奥の頂（超遠距離の見せ場）
]
const KNOLL_PADS := [1, 3, 4, 5, 6]  # ノール化するパッド（2=川辺は谷のまま）
const KNOLL_R := 50.0                # ノールの裾野半径

var _ridge := FastNoiseLite.new()    # 山並みの尾根
var _broad := FastNoiseLite.new()    # 大きなうねり
var _mid := FastNoiseLite.new()      # 中くらいの起伏
var _detail := FastNoiseLite.new()   # 細かい起伏
var _pad_floor: Array[float] = []    # 各パッドの床高さ（素の地形から算出）


func _init() -> void:
	_ridge.seed = 41
	_ridge.frequency = 0.0016
	_ridge.fractal_octaves = 3
	_broad.seed = 7
	_broad.frequency = 0.0009
	_broad.fractal_octaves = 2
	_mid.seed = 19
	_mid.frequency = 0.008
	_mid.fractal_octaves = 2
	_detail.seed = 33
	_detail.frequency = 0.05
	_detail.fractal_octaves = 1
	# パッドの床高さは「パッド彫り込み前」の素の地形から決める（自己参照を避ける）
	for p in PADS:
		_pad_floor.append(_raw_height(p[0], p[1]) + p[3])


func _ready() -> void:
	collision_layer = 0b0001  # レイヤ1: 地形（弾はここで止まる）
	collision_mask = 0
	_build_mesh()
	_build_far_mesh()
	_build_collision()
	_build_river()
	_build_trees()


## 川のセンターライン（xを入れると川のz位置が返る。全幅を蛇行しながら横切る）
func river_z(x: float) -> float:
	return -285.0 + sin(x * 0.005) * 55.0 + sin(x * 0.0013 + 1.7) * 42.0


## 素の地形（パッド彫り込み前）。
## 尾根の山並み → 視界の回廊（段丘） → 主峰の円錐 → 川の谷、の順に彫る。
## 回廊：中央(|x|<約300)は「奥へ行くほど高くなる」段丘状に高さを制限し、
## 山頂(165m)からすべての標的パッドへ射線が通ることを地形で保証する。
## 両脇(|x|>380)は素の高い山並みのまま＝視界の額縁になる
func _raw_height(x: float, z: float) -> float:
	# 尾根状の山並み（absを滑らかにして刃を丸める）
	var r := _ridge.get_noise_2d(x, z)
	var ridge := 1.0 - sqrt(r * r + 0.010)
	var h := pow(maxf(ridge, 0.0), 2.2) * 125.0
	h += _broad.get_noise_2d(x, z) * 42.0
	h += _mid.get_noise_2d(x, z) * 9.0
	h += _detail.get_noise_2d(x, z) * 1.1
	# 視界の回廊（前方の段丘）
	var az := -z
	if az > 0.0:
		var k := (1.0 - smoothstep(240.0, 380.0, absf(x))) * smoothstep(20.0, 90.0, az)
		if k > 0.0:
			h = lerpf(h, minf(h, _corridor_cap(az)), k)
	# プレイヤーの主峰（円錐へブレンド＋近傍は円錐面を上限にする＝目の前の壁を作らない）
	var pd := Vector2(x - PEAK_XZ.x, z - PEAK_XZ.y).length()
	var w := 1.0 - smoothstep(30.0, PEAK_R, pd)
	if w > 0.0:
		h = lerpf(h, PEAK_TOP - pd * PEAK_SLOPE, w)
	if pd < PEAK_R:
		h = minf(h, PEAK_TOP + 7.0 - pd * 0.85)
	# 川の谷: センターラインに近いほど川底へ均す（谷幅は約±95m）
	var rd := absf(z - river_z(x))
	var t := 1.0 - smoothstep(16.0, 95.0, rd)
	if t > 0.0:
		h = lerpf(h, RIVER_BED, t)
	# 標的ノール: 段丘ランプの上限高さに立つ小山を盛る（低い窪地に落ちて
	# 手前の段丘に隠れることを防ぐ＝奥の標的ほど高く、必ず見える）
	for i in KNOLL_PADS:
		var p: Array = PADS[i]
		var dist := Vector2(x - p[0], z - p[1]).length()
		if dist < KNOLL_R:
			var top: float = _corridor_cap(-p[1]) + p[3]
			h = maxf(h, top - dist * 0.6)
	return h


## 段丘ランプの上限高さ（前方距離azにおける回廊の天井）
func _corridor_cap(az: float) -> float:
	return 12.0 + az * 0.16


## 地形の高さ（メッシュ・当たり判定・配置がすべてこれを使う）
func get_height(x: float, z: float) -> float:
	var h := _raw_height(x, z)
	# 立ち場パッド: 標的・リグの足場を平らに均す
	for i in PADS.size():
		var p: Array = PADS[i]
		var dist := Vector2(x - p[0], z - p[1]).length()
		var t := 1.0 - smoothstep(p[2] * 0.5, p[2], dist)
		if t > 0.0:
			h = lerpf(h, _pad_floor[i], t)
	return h


func _build_mesh() -> void:
	var nx := int(X_HALF * 2.0 / MESH_STEP) + 1
	var nz := int((Z_MAX - Z_MIN) / MESH_STEP) + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var x := ix * MESH_STEP - X_HALF
			var z := Z_MIN + iz * MESH_STEP
			var idx := iz * nx + ix
			verts[idx] = Vector3(x, get_height(x, z), z)
			# 法線は広め(2セル分)の差分で均す（陰影の筋を防ぐ）
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
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/mountain_terrain.gdshader")
	mi.material_override = mat
	add_child(mi)


## 遠景の山地メッシュ。同じ get_height を粗いピッチでサンプルして±4.2kmまで敷く
## ＝空へ撃ったミス弾のバレットカムでも「どこまでも山が続く」世界に見える。
## プレイエリア内は詳細メッシュが上に載るので、重なる部分は0.5m沈めて隠す
func _build_far_mesh() -> void:
	var n := int(FAR_EXTENT * 2.0 / FAR_STEP) + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(n * n)
	normals.resize(n * n)
	for iz in n:
		for ix in n:
			var x := ix * FAR_STEP - FAR_EXTENT
			var z := iz * FAR_STEP - FAR_EXTENT
			var idx := iz * n + ix
			var y := get_height(x, z)
			if _inside_play_area(x, z):
				y -= 0.5  # 詳細メッシュの下へ沈めてZファイトを防ぐ
			verts[idx] = Vector3(x, y, z)
			var e := FAR_STEP
			var dnx := get_height(x - e, z) - get_height(x + e, z)
			var dnz := get_height(x, z - e) - get_height(x, z + e)
			normals[idx] = Vector3(dnx, 2.0 * e, dnz).normalized()

	var indices := PackedInt32Array()
	for iz in n - 1:
		for ix in n - 1:
			# プレイエリアの完全に内側のセルは張らない（詳細メッシュに任せる）
			var cx := (float(ix) + 0.5) * FAR_STEP - FAR_EXTENT
			var cz := (float(iz) + 0.5) * FAR_STEP - FAR_EXTENT
			if _inside_play_area(cx - FAR_STEP, cz - FAR_STEP) \
					and _inside_play_area(cx + FAR_STEP, cz + FAR_STEP):
				continue
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var dd := c + 1
			indices.append(a)
			indices.append(b)
			indices.append(c)
			indices.append(b)
			indices.append(dd)
			indices.append(c)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/mountain_terrain.gdshader")
	mi.material_override = mat
	add_child(mi)
	_build_far_collision()


## 遠景の当たり判定（見た目と同じ64mグリッド＝面が一致する）。
## プレイエリア内は詳細判定(3m)に任せるため、大きく沈めて干渉させない
func _build_far_collision() -> void:
	var n := int(FAR_EXTENT * 2.0 / FAR_STEP) + 1
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var data := PackedFloat32Array()
	data.resize(n * n)
	for iz in n:
		for ix in n:
			var x := ix * FAR_STEP - FAR_EXTENT
			var z := iz * FAR_STEP - FAR_EXTENT
			var y := get_height(x, z)
			if _inside_play_area(x, z):
				y = -200.0  # 詳細判定の下へ沈める
			data[iz * n + ix] = y / FAR_STEP
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(FAR_STEP, FAR_STEP, FAR_STEP)
	add_child(cs)


func _inside_play_area(x: float, z: float) -> bool:
	return absf(x) < X_HALF and z > Z_MIN and z < Z_MAX


func _build_collision() -> void:
	# COL_STEPピッチでサンプルし、均一scaleで実寸へ（desert_terrainと同方式）
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


## 川の水面。谷の蛇行コリドーを覆う帯状の面（地形が水面より高い所では隠れる）。
## 弾は水面を抜けて川底（地形）で止まる＝当たり判定なし
func _build_river() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/mountain_river.gdshader")
	# 蛇行(±97m)を覆う幅240mの帯を、x方向に分割して川筋に追従させる。
	# 遠景の山地まで川が続いて見えるよう、プレイエリア外は粗い分割で±4.2kmまで延長
	var x := -FAR_EXTENT
	while x < FAR_EXTENT:
		var seg_w := 100.0 if absf(x) < X_HALF else 400.0
		var band := 240.0 if absf(x) < X_HALF else 340.0  # 外周は蛇行ずれぶん広く
		var mid := x + seg_w * 0.5
		var plane := PlaneMesh.new()
		plane.size = Vector2(seg_w + 2.0, band)
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = mat
		mi.position = Vector3(mid, WATER_Y, river_z(mid))
		add_child(mi)
		# 水面の当たり判定（薄い箱・上面＝水面）。弾は水中へ進まず水面で止まる。
		# 川岸(水面より高い地形)では地形の判定が先に当たるので誤爆しない
		var wbody := StaticBody3D.new()
		wbody.collision_layer = 0b0001
		wbody.collision_mask = 0
		wbody.set_meta("water_surface", true)
		var wcs := CollisionShape3D.new()
		var wbox := BoxShape3D.new()
		wbox.size = Vector3(seg_w + 2.0, 0.3, band)
		wcs.shape = wbox
		wbody.add_child(wcs)
		wbody.position = Vector3(mid, WATER_Y - 0.15, river_z(mid))
		add_child(wbody)
		x += seg_w


## 針葉樹の散布（MultiMesh・当たり判定なし）。
## 草の生える緩斜面だけに植え、川・パッド・山頂〜標的の射線コリドーは避ける
func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260712
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.3
	cone.height = 7.0
	cone.radial_segments = 6
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	cone.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cone
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var guard := 0
	var eye := Vector3(PEAK_XZ.x, get_height(PEAK_XZ.x, PEAK_XZ.y) + 1.75, PEAK_XZ.y)
	while transforms.size() < 560 and guard < 9000:
		guard += 1
		var x := rng.randf_range(-X_HALF + 30.0, X_HALF - 30.0)
		var z := rng.randf_range(Z_MIN + 60.0, Z_MAX - 30.0)
		var h := get_height(x, z)
		if h < WATER_Y + 2.0 or h > 120.0:
			continue  # 川の中・高すぎる岩場には生えない
		# 斜度チェック（急斜面は岩＝木は生えない）
		var e := 6.0
		var grad := Vector2(get_height(x - e, z) - get_height(x + e, z),
			get_height(x, z - e) - get_height(x, z + e)).length() / (2.0 * e)
		if grad > 0.55:
			continue
		if not _clear_of_pads_and_sightlines(x, z, eye):
			continue
		var s := rng.randf_range(0.7, 1.6)
		var t := Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), Vector3(x, h + 3.2 * s, z))
		transforms.append(t)
		var g := rng.randf_range(0.0, 1.0)
		colors.append(Color(0.09 + 0.05 * g, 0.26 + 0.10 * g, 0.10 + 0.05 * g))
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


## パッドの上・山頂→各パッドの射線コリドー（半径14m）には木を植えない
func _clear_of_pads_and_sightlines(x: float, z: float, eye: Vector3) -> bool:
	var p3 := Vector3(x, get_height(x, z) + 3.5, z)
	for i in PADS.size():
		var p: Array = PADS[i]
		if Vector2(x - p[0], z - p[1]).length() < p[2] + 8.0:
			return false
		if i == 0:
			continue
		# 射線: eye→パッド上空1m の線分との距離
		var goal := Vector3(p[0], _pad_floor[i] + 1.0, p[1])
		var seg := goal - eye
		var t := clampf((p3 - eye).dot(seg) / seg.length_squared(), 0.0, 1.0)
		if p3.distance_to(eye + seg * t) < 14.0:
			return false
	return true
