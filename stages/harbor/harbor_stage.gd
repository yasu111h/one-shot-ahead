extends SniperStage
## 「夜の埠頭」ステージ。
## プレイヤーは倉庫の屋上に陣取り、約180m先のコンテナ列の向こうを狙う。
## 悪人はコンテナの裏を歩いて回り、隙間（ギャップ）を横切る一瞬だけ姿が見える
## ＝都市ステージの「窓」をコンテナの隙間で作る。
## 隙間のいくつかには人質（民間人・白）が立たされており、誤射は即ミッション失敗。

const ROOF_Y := 16.0            # 倉庫の屋上の高さ
const ROW_Z := -148.0           # コンテナ前列（この裏を悪人が歩く）
const WALK_Z := -151.5          # 悪人の歩行ライン
const BACK_Z := -158.0          # 背景の倉庫壁（悪人のシルエットが立つ）

# コンテナ前列の構成。[中心x, 段数] を隙間を空けて並べる。
# 隙間は広い所2.4m・狭い所1.4mの2種類＝撃ちやすい窓と難しい窓ができる
const CONTAINERS := [
	[-27.0, 2], [-19.5, 1], [-11.0, 2], [-3.0, 1], [5.5, 1], [13.0, 2], [21.5, 1],
]
const CONT_W := 6.1   # コンテナ1個の幅(X)
const CONT_H := 2.6   # 高さ
const CONT_D := 2.44  # 奥行(Z)

## 人質の立ち位置（広い隙間の中・やや端）[x, z]
const HOSTAGES := [[-15.7, -149.3], [17.8, -149.3]]

var _rust: StandardMaterial3D
var _blue: StandardMaterial3D
var _green: StandardMaterial3D
var _metal: StandardMaterial3D
var _concrete: StandardMaterial3D


func _rig_position() -> Vector3:
	# 倉庫の屋上・前縁の左角
	return Vector3(-8.4, ROOF_Y + 2.0, 30.6)


func _configure_rig() -> void:
	# 角から埠頭を見渡せる扇形だけに視点を制限（上はクレーンや上層まで見上げられる）
	rig.set_view_limits(-38.0, 42.0, -32.0, 38.0)


func _mission_text() -> String:
	return "MISSION: ELIMINATE 4 HOSTILES  /  DO NOT SHOOT HOSTAGES (WHITE)"


## 夜の海辺：都市より暗く、雲は月光で青く照る。フォグはわずかな潮靄
func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky_city.gdshader")
	sky_mat.set_shader_parameter("top_color", Color(0.004, 0.008, 0.018))
	sky_mat.set_shader_parameter("horizon_color", Color(0.028, 0.050, 0.078))
	sky_mat.set_shader_parameter("cloud_dark", Color(0.022, 0.034, 0.055))
	sky_mat.set_shader_parameter("cloud_lit", Color(0.060, 0.080, 0.110))
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.40, 0.55)
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.035, 0.055, 0.075)
	env.fog_density = 0.0008
	env.fog_sun_scatter = 0.0
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 月明かり（海側から）
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.58, 0.70, 0.92)
	moon.light_energy = 0.45
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-34.0, 200.0, 0.0)
	add_child(moon)


## 海風は都市より強め（±4m/s。WIND_ENABLED=false の間は演出値のみ）
func _setup_wind() -> void:
	wind_speed = randf_range(-4.0, 4.0)
	wind_accel = Vector3(wind_speed, 0, 0) * WIND_FACTOR


func _build_world() -> void:
	var docks := StaticBody3D.new()
	docks.collision_layer = 0b0001   # 地形レイヤ（弾はここで止まる・LOSもこれで判定）
	docks.collision_mask = 0
	add_child(docks)
	_make_materials()
	_build_ground(docks)
	_build_warehouse(docks)
	_build_containers(docks)
	_build_backdrop(docks)
	_build_dressing(docks)


func _make_materials() -> void:
	_rust = StandardMaterial3D.new()
	_rust.albedo_color = Color(0.42, 0.16, 0.10)
	_rust.roughness = 0.9
	_blue = StandardMaterial3D.new()
	_blue.albedo_color = Color(0.10, 0.18, 0.32)
	_blue.roughness = 0.85
	_green = StandardMaterial3D.new()
	_green.albedo_color = Color(0.10, 0.24, 0.16)
	_green.roughness = 0.85
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.15, 0.17, 0.20)
	_metal.metallic = 0.7
	_metal.roughness = 0.45
	_concrete = StandardMaterial3D.new()
	_concrete.albedo_color = Color(0.13, 0.14, 0.16)
	_concrete.roughness = 0.95


func _box(parent: StaticBody3D, size: Vector3, pos: Vector3, mat: Material,
		coll := true) -> MeshInstance3D:
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


## 埠頭（濡れたアスファルト）と海面
func _build_ground(docks: StaticBody3D) -> void:
	var quay := PlaneMesh.new()
	quay.size = Vector2(700.0, 700.0)
	var qm := StandardMaterial3D.new()
	qm.albedo_color = Color(0.024, 0.028, 0.036)
	qm.roughness = 0.4
	var qmi := MeshInstance3D.new()
	qmi.mesh = quay
	qmi.material_override = qm
	docks.add_child(qmi)
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(700.0, 1.0, 700.0)
	shape.shape = bx
	shape.position = Vector3(0.0, -0.5, 0.0)
	docks.add_child(shape)

	# 海面（埠頭の向こう・わずかに低い。月光を鈍く映す）
	var sea := PlaneMesh.new()
	sea.size = Vector2(900.0, 500.0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.015, 0.035, 0.055)
	sm.metallic = 0.4
	sm.roughness = 0.12
	var smi := MeshInstance3D.new()
	smi.mesh = sea
	smi.material_override = sm
	smi.position = Vector3(0.0, -0.6, -450.0)
	docks.add_child(smi)


## プレイヤーの倉庫（屋上にパラペット）
func _build_warehouse(docks: StaticBody3D) -> void:
	_box(docks, Vector3(26.0, ROOF_Y, 22.0), Vector3(-6.0, ROOF_Y * 0.5, 42.0), _concrete)
	_box(docks, Vector3(26.0, 0.2, 22.0), Vector3(-6.0, ROOF_Y + 0.1, 42.0), _concrete)
	# パラペット（四辺）
	for e in [[Vector3(26.4, 0.9, 0.7), Vector3(-6.0, ROOF_Y + 0.65, 31.2)],
			[Vector3(26.4, 0.9, 0.7), Vector3(-6.0, ROOF_Y + 0.65, 52.8)],
			[Vector3(0.7, 0.9, 22.4), Vector3(-19.2, ROOF_Y + 0.65, 42.0)],
			[Vector3(0.7, 0.9, 22.4), Vector3(7.2, ROOF_Y + 0.65, 42.0)]]:
		_box(docks, e[0], e[1], _concrete)


## コンテナ前列（隙間が「命中の窓」になる）
func _build_containers(docks: StaticBody3D) -> void:
	var mats := [_rust, _blue, _green]
	for i in CONTAINERS.size():
		var cx: float = CONTAINERS[i][0]
		var stack: int = CONTAINERS[i][1]
		for lv in stack:
			_box(docks, Vector3(CONT_W, CONT_H, CONT_D),
				Vector3(cx, CONT_H * (0.5 + lv), ROW_Z),
				mats[(i + lv) % mats.size()])


## 背景の倉庫壁（悪人のシルエットの背）と数個の灯り窓
func _build_backdrop(docks: StaticBody3D) -> void:
	_box(docks, Vector3(90.0, 10.0, 1.0), Vector3(0.0, 5.0, BACK_Z), _concrete)
	# 壁の小窓（点在する灯り。狙撃の目印にもなる）
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(1.0, 0.75, 0.4)
	lit.emission_enabled = true
	lit.emission = Color(1.0, 0.72, 0.35)
	lit.emission_energy_multiplier = 1.6
	for wx in [-32.0, -12.0, 3.0, 21.0, 36.0]:
		_box(docks, Vector3(1.6, 1.1, 0.1), Vector3(wx, 6.4, BACK_Z + 0.56), lit, false)


## 書き割り：ガントリークレーン2基・貨物船・埠頭灯
func _build_dressing(docks: StaticBody3D) -> void:
	for cx in [-52.0, 55.0]:
		_build_crane(docks, cx)
	_build_ship(docks)
	for lx in [-38.0, -14.0, 12.0, 38.0]:
		_build_lamp(docks, Vector3(lx, 0.0, -138.0))


func _build_crane(docks: StaticBody3D, cx: float) -> void:
	# 脚2本＋水平ビーム（遠景シルエット・当たり判定あり）
	for dz in [-6.0, 6.0]:
		_box(docks, Vector3(2.2, 34.0, 2.2), Vector3(cx, 17.0, -185.0 + dz), _metal)
	_box(docks, Vector3(3.0, 3.0, 26.0), Vector3(cx, 35.0, -185.0), _metal)
	_box(docks, Vector3(30.0, 2.4, 2.6), Vector3(cx, 30.0, -185.0), _metal)


func _build_ship(docks: StaticBody3D) -> void:
	# 貨物船（船体＋ブリッジ＋舷窓の灯り列）
	_box(docks, Vector3(120.0, 9.0, 18.0), Vector3(20.0, 3.0, -262.0), _metal)
	_box(docks, Vector3(12.0, 14.0, 10.0), Vector3(64.0, 14.5, -262.0), _concrete)
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(0.95, 0.85, 0.6)
	lit.emission_enabled = true
	lit.emission = Color(0.95, 0.82, 0.55)
	lit.emission_energy_multiplier = 1.4
	_box(docks, Vector3(9.0, 0.7, 0.2), Vector3(64.0, 17.5, -256.8), lit, false)


func _build_lamp(docks: StaticBody3D, base: Vector3) -> void:
	# ポール＋発光ヘッド（ライトは置かない＝発光マテリアル+glowで安く見せる）
	var pole := CylinderMesh.new()
	pole.top_radius = 0.09
	pole.bottom_radius = 0.12
	pole.height = 7.0
	var pm := MeshInstance3D.new()
	pm.mesh = pole
	pm.material_override = _metal
	pm.position = base + Vector3(0, 3.5, 0)
	docks.add_child(pm)
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(1.0, 0.85, 0.55)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.8, 0.45)
	hm.emission_energy_multiplier = 2.2
	var hmi := MeshInstance3D.new()
	hmi.mesh = head
	hmi.material_override = hm
	hmi.position = base + Vector3(0, 7.1, 0)
	docks.add_child(hmi)


func _spawn_targets() -> void:
	# 悪人4人：コンテナ裏の歩行ライン。歩幅（往復範囲）と速度を変えて
	# 「どの隙間に・いつ現れるか」をずらす
	var y := 0.95
	_add_walker(Vector3(-29.0, y, WALK_Z), Vector3(-14.0, y, WALK_Z), 1.3)
	_add_walker(Vector3(-13.5, y, WALK_Z), Vector3(1.5, y, WALK_Z), 1.7)
	_add_walker(Vector3(3.0, y, WALK_Z), Vector3(16.0, y, WALK_Z), 1.1)
	_add_walker(Vector3(10.0, y, WALK_Z), Vector3(26.0, y, WALK_Z), 1.5)
	# 人質：隙間の中に立たされている（撃てば即失敗・悪人はその奥を横切る）
	for h in HOSTAGES:
		_add_standing(Vector3(h[0], y, h[1]), false)
