extends SniperStage
## 「風車群の丘」ステージ（夜明け）——ドローンの群れの撃墜ミッション。
## 発電施設を狙う赤い攻撃ドローンの群れが風車群の空域に侵入した。
## プレイヤーは高台の監視デッキから、赤いドローンだけを撃ち落とす。
## 空域には白い点検ドローン（民間）も飛んでいる＝撃てば即ミッション失敗。
## 「誤射禁止」の核を空に持ち込んだステージ。
##
## 命中の窓：回転する風車の羽根が周期的に射線を塞ぐ（読めば当たる・乱数なし）。
## ドローン自体も周回飛行＝飛行速度ぶんのリード（偏差撃ち）が必要。
## 距離構成：手前約200m → 中景350〜600m → 最奥約900m（高倍率スコープの見せ場）。

var terrain: WindfarmTerrain


func _enter_tree() -> void:
	# シェーダ描きの窓ガラスは無い＝垂直面をガラス扱いさせない
	set_meta("facade_windows_enabled", false)


func _rig_position() -> Vector3:
	# 監視デッキの上（丘 + デッキ2.4m + 目線1.75m）
	var base_h := terrain.get_height(WindfarmTerrain.RIG_XZ.x, WindfarmTerrain.RIG_XZ.y)
	return Vector3(WindfarmTerrain.RIG_XZ.x, base_h + 2.4 + 1.75, WindfarmTerrain.RIG_XZ.y)


func _configure_rig() -> void:
	girl_offset.y = -1.75  # デッキの床板に足が着く高さ
	# 前方（-Z＝風車群）を中心に左右75度。ドローンは空を飛ぶので上へ広く
	rig.set_view_limits(-75.0, 75.0, -25.0, 50.0)


func _mission_text() -> String:
	return "MISSION: SHOOT DOWN %d ATTACK DRONES (RED LIGHT)  /  WHITE = CIVILIAN" \
		% hostiles.size()


## 丘の朝風（±4m/s・演出値）
func _setup_wind() -> void:
	wind_speed = randf_range(-4.0, 4.0)
	wind_accel = Vector3(wind_speed, 0, 0) * WIND_FACTOR


## 夜明けの丘: 澄んだ朝の空気。砂漠の夜明け空シェーダを寒色寄りの色で使い回す
func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky_desert_dawn.gdshader")
	sky_mat.set_shader_parameter("zenith_color", Color(0.24, 0.32, 0.55))
	sky_mat.set_shader_parameter("mid_color", Color(0.62, 0.62, 0.72))
	sky_mat.set_shader_parameter("horizon_color", Color(1.0, 0.74, 0.45))
	sky_mat.set_shader_parameter("ground_color", Color(0.2, 0.22, 0.18))
	sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.9, 0.7))
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0

	# 朝もや（ごく薄く）。900m先の風車が読める濃さに抑える
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.72, 0.68)
	env.fog_density = 0.0004
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.1

	# ドローンのライトをにじませる控えめなグロー
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.06

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 低い朝日（横から風車と草をなでる光）
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.85, 0.62)
	sun.light_energy = 1.2
	sun.shadow_enabled = false  # リアルタイム影はオフ（モバイル負荷対策）
	sun.rotation_degrees = Vector3(-14.0, 118.0, 0.0)
	add_child(sun)


func _build_world() -> void:
	terrain = WindfarmTerrain.new()
	add_child(terrain)
	_build_turbines()
	_build_deck()
	_build_substation()


## 風車群（8基）。回転速度を基ごとに変えて「読める周期」をずらす
func _build_turbines() -> void:
	var speeds := [0.7, 0.55, 0.8, 0.62, 0.75, 0.5, 0.68, 0.58]
	for i in WindfarmTerrain.TURBINES.size():
		var at: Vector2 = WindfarmTerrain.TURBINES[i]
		var t := WindTurbine.new()
		t.spin_speed = speeds[i % speeds.size()]
		add_child(t)
		t.global_position = Vector3(at.x, terrain.get_height(at.x, at.y), at.y)
		# どの基もローター面がおおむね狙撃地点側を向く（羽根の円が正面に見える）
		t.rotation.y = atan2(WindfarmTerrain.RIG_XZ.x - at.x, WindfarmTerrain.RIG_XZ.y - at.y)


## 監視デッキ（狙撃地点の足場）
func _build_deck() -> void:
	var cx := WindfarmTerrain.RIG_XZ.x
	var cz := WindfarmTerrain.RIG_XZ.y
	var base_h := terrain.get_height(cx, cz)
	_static_box(Vector3(3.8, 0.24, 3.8), Vector3(cx, base_h + 2.28, cz), Color(0.5, 0.44, 0.36))
	# 脚4本
	for off in [Vector2(-1.5, -1.5), Vector2(1.5, -1.5), Vector2(-1.5, 1.5), Vector2(1.5, 1.5)]:
		_static_box(Vector3(0.22, 2.3, 0.22),
			Vector3(cx + off.x, base_h + 1.15, cz + off.y), Color(0.36, 0.32, 0.28), false)
	# 手すり（撃ち下ろしを遮らない低さ）
	var rail := Color(0.32, 0.29, 0.26)
	_static_box(Vector3(3.8, 0.08, 0.08), Vector3(cx, base_h + 3.2, cz - 1.86), rail, false)
	_static_box(Vector3(0.08, 0.08, 3.8), Vector3(cx - 1.86, base_h + 3.2, cz), rail, false)
	_static_box(Vector3(0.08, 0.08, 3.8), Vector3(cx + 1.86, base_h + 3.2, cz), rail, false)


## 変電小屋と柵（風車群の麓＝「発電施設を守っている」文脈を作る）
func _build_substation() -> void:
	var at := Vector2(-30.0, -150.0)
	var h := terrain.get_height(at.x, at.y)
	_static_box(Vector3(5.2, 2.8, 3.6), Vector3(at.x, h + 1.4, at.y), Color(0.62, 0.6, 0.58))
	_static_box(Vector3(5.8, 0.22, 4.2), Vector3(at.x, h + 2.9, at.y), Color(0.4, 0.38, 0.36))
	# 変圧器（箱＋碍子）
	_static_box(Vector3(1.6, 1.6, 1.6), Vector3(at.x + 4.6, h + 0.8, at.y + 0.4),
		Color(0.35, 0.37, 0.4))
	# 警告灯（小屋の角で赤く明滅している風＝発光のみ）
	var warn := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(0.18, 0.18, 0.18)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(1.0, 0.3, 0.2)
	wm.emission_enabled = true
	wm.emission = Color(1.0, 0.25, 0.15)
	wm.emission_energy_multiplier = 3.0
	wb.material = wm
	warn.mesh = wb
	warn.position = Vector3(at.x - 2.5, h + 3.1, at.y - 1.7)
	add_child(warn)


## 箱の静的オブジェクト（当たり判定つき既定。collide=falseで見た目のみ）
func _static_box(size: Vector3, pos: Vector3, color: Color, collide := true) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 0b0001
		body.collision_mask = 0
		add_child(body)
		body.global_position = pos
		body.add_child(mesh)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
	else:
		add_child(mesh)
		mesh.global_position = pos


## ドローンの配置。赤（hostile）9機＝風車の空域を周回する群れ。
## 白（民間・点検）3機＝風車のナセル近くをゆっくり周回。
func _spawn_targets() -> void:
	# [風車index, 高度オフセット, 周回半径, 角速度, 上下ゆらぎ]
	# 手前の基ほど速く（近距離の速いリード）、奥の基はゆっくり大きく（距離の挑戦）
	var reds := [
		[0, 30.0, 14.0, 0.65, 2.5],
		[0, 40.0, 20.0, -0.5, 3.0],
		[1, 32.0, 12.0, 0.55, 2.0],
		[2, 36.0, 16.0, -0.6, 2.5],
		[2, 46.0, 24.0, 0.4, 3.5],
		[3, 34.0, 14.0, 0.5, 2.0],
		[4, 38.0, 18.0, -0.45, 3.0],
		[5, 40.0, 16.0, 0.42, 2.5],
		[7, 44.0, 18.0, 0.35, 3.0],   # 最奥・約900m＝高倍率スコープの見せ場
	]
	for r in reds:
		_add_drone(r[0], r[1], r[2], r[3], r[4], true)
	# 白い点検ドローン（撃つと即FAIL）。ナセルの近くを小さくゆっくり
	var whites := [
		[1, 44.0, 6.0, 0.25, 1.0],
		[3, 45.0, 7.0, -0.22, 1.2],
		[5, 46.0, 6.5, 0.2, 1.0],
	]
	for w in whites:
		_add_drone(w[0], w[1], w[2], w[3], w[4], false)


func _add_drone(turbine_i: int, alt: float, radius: float, speed: float,
		bob: float, hostile_flag: bool) -> void:
	var at: Vector2 = WindfarmTerrain.TURBINES[turbine_i]
	var ground := terrain.get_height(at.x, at.y)
	var drone := TargetDrone.new()
	drone.hostile = hostile_flag
	drone.anchor = Vector3(at.x, ground + alt, at.y)
	drone.orbit_radius = radius
	drone.orbit_speed = speed
	drone.bob_amp = bob
	drone.phase = randf() * TAU
	add_child(drone)
	# 初期位置を軌道上に置く（1フレーム目の瞬間移動を避ける）
	drone.global_position = drone.anchor + Vector3(
		cos(drone.phase) * radius, 0, sin(drone.phase) * radius)
	_register(drone)
