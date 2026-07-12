extends SniperStage
## 「山岳の尾根」ステージ（昼の高原）。
## 山賊団が登山ルートの峰々に見張りを立てて占拠している。
## プレイヤーは主峰の山頂から、点在する見張りだけを撃ち抜く。
## ルート上にはハイカー（民間人・白）が居合わせる＝誤射は即ミッション失敗。
## 距離の構成：約190m → 300m(歩行) → 510m → 650m(歩行) → 830m → 1020m(最奥の頂)。
## 見た目：緑の山並みと青空・流れる積雲・谷を蛇行する川（地形はget_height一元管理）。

var terrain: MountainTerrain


func _enter_tree() -> void:
	# シェーダ描きの窓ガラスは無い＝垂直面をガラス扱いさせない
	set_meta("facade_windows_enabled", false)


func _rig_position() -> Vector3:
	# 主峰の山頂（パッド0）＋目線1.75m
	var p: Array = MountainTerrain.PADS[0]
	return Vector3(p[0], terrain.get_height(p[0], p[1]) + 1.75, p[1])


func _configure_rig() -> void:
	girl_offset.y = -1.75  # 山頂の地面に足が着く高さ
	# 前方(-Z＝谷と対岸の峰々)を中心に左右85度。下は眼下の川まで・上は空を少し
	rig.set_view_limits(-85.0, 85.0, -45.0, 12.0)


func _mission_text() -> String:
	return "MISSION: ELIMINATE %d HOSTILES  /  DO NOT SHOOT HIKERS (WHITE)" % hostiles.size()


## 山の風（±5m/s。稜線の風は強め）
func _setup_wind() -> void:
	wind_speed = randf_range(-5.0, 5.0)
	wind_accel = Vector3(wind_speed, 0, 0) * WIND_FACTOR


## 昼の高原: 青空と積雲・澄んだ空気。超遠距離が見えるようフォグはごく薄く
func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky_alpine.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0

	# 距離フォグ（青みの大気遠近。1000m先の頂が読める薄さ）
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.80, 0.92)
	env.fog_density = 0.00042
	env.fog_sun_scatter = 0.1
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 昼の太陽（空シェーダの sun_dir と同じ向きから照らす）
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.light_energy = 1.25
	sun.shadow_enabled = false  # リアルタイム影はオフ（モバイル負荷対策）
	sun.rotation_degrees = Vector3(-34.0, 25.0, 0.0)
	add_child(sun)


func _build_world() -> void:
	terrain = MountainTerrain.new()
	add_child(terrain)
	_build_summit_props()
	_build_boulders()


## 山頂の小物（ケルン=石積みと道標）。狙撃地点の「場所」感を出す
func _build_summit_props() -> void:
	var p: Array = MountainTerrain.PADS[0]
	var base := terrain.get_height(p[0], p[1])
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.5, 0.48, 0.45)
	rock_mat.roughness = 1.0
	# ケルン（積み石。上ほど小さい球）。視線の後方に小さく置く
	for k in 4:
		var s := 0.34 - float(k) * 0.06
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = s
		sph.height = s * 1.2
		sph.material = rock_mat
		mi.mesh = sph
		mi.position = Vector3(p[0] - 4.2, base + 0.18 + float(k) * 0.34, p[1] + 4.5)
		add_child(mi)
	# 道標（木の柱＋板）
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.26, 0.16)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.07
	cyl.height = 1.8
	cyl.material = wood
	pole.mesh = cyl
	pole.position = Vector3(p[0] + 3.0, base + 0.9, p[1] + 1.5)
	add_child(pole)
	var sign := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.9, 0.24, 0.05)
	sb.material = wood
	sign.mesh = sb
	sign.position = Vector3(p[0] + 3.0, base + 1.55, p[1] + 1.5)
	sign.rotation_degrees.y = 24.0
	add_child(sign)


## 斜面の大岩（当たり判定つき。§3「見える物には当たり判定」）
func _build_boulders() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.47, 0.45, 0.42)
	mat.roughness = 1.0
	for spec in [
		[Vector2(-90.0, -180.0), 3.2], [Vector2(120.0, -320.0), 4.0],
		[Vector2(-40.0, -520.0), 3.5], [Vector2(60.0, -680.0), 4.5],
		[Vector2(-170.0, -300.0), 3.0], [Vector2(210.0, -460.0), 3.8],
	]:
		var at: Vector2 = spec[0]
		var r: float = spec[1]
		var body := StaticBody3D.new()
		body.collision_layer = 0b0001
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = r * 0.92
		cs.shape = shape
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = r
		sph.height = r * 1.5
		sph.material = mat
		mi.mesh = sph
		body.add_child(mi)
		body.position = Vector3(at.x, terrain.get_height(at.x, at.y) + r * 0.3, at.y)
		add_child(body)


func _spawn_targets() -> void:
	# パッド1〜6（mountain_terrain.PADS）に沿って山賊の見張りを点在させる。
	# 2・4番は尾根道を往復する歩行標的＝リード（偏差撃ち）の見せ場
	var pads: Array = MountainTerrain.PADS
	_standing_on_pad(pads[1])                    # 約190m
	_walker_on_pad(pads[2], 6.0, 1.3)            # 約300m（歩行）
	_standing_on_pad(pads[3])                    # 約510m
	_walker_on_pad(pads[4], 7.0, 1.6)            # 約650m（歩行）
	_standing_on_pad(pads[5])                    # 約830m
	_standing_on_pad(pads[6])                    # 約1020m（最奥の頂・高倍率の見せ場）
	# ハイカー（民間人・白）。見張りのそばに居合わせる＝誤射禁止の緊張
	_add_standing(_pad_pos(pads[2]) + Vector3(-4.5, 0, 1.5), false)
	_add_standing(_pad_pos(pads[5]) + Vector3(3.8, 0, -1.2), false)


## パッド中心の「胴体中心」ワールド座標
func _pad_pos(p: Array) -> Vector3:
	return Vector3(p[0], terrain.get_height(p[0], p[1]) + 0.78, p[1])


func _standing_on_pad(p: Array) -> void:
	_add_standing(_pad_pos(p))


func _walker_on_pad(p: Array, half: float, speed: float) -> void:
	var c := _pad_pos(p)
	_add_walker(c + Vector3(-half, 0, 0), c + Vector3(half, 0, 0), speed)
