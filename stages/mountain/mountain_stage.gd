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
	# 山頂の小物（ケルン・道標）は廃止（2026-07-12ユーザーFB: 視界の端で浮いて見える）
	_build_boulders()


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


## 着弾演出の差し替え：川の水面なら土煙ではなく水しぶき
func _impact_effect(point: Vector3, normal: Vector3) -> void:
	if point.y < MountainTerrain.WATER_Y + 0.5 \
			and absf(point.z - terrain.river_z(point.x)) < 175.0:
		_splash(point)
		sfx.play_impact()
	else:
		super(point, normal)


## 水しぶき：噴き上がる水柱＋飛び散る飛沫＋広がる波紋（遠距離でも読める大きさ）
func _splash(pos: Vector3) -> void:
	var top := Vector3(pos.x, MountainTerrain.WATER_Y + 0.05, pos.z)
	# 水柱（白い柱がシュッと立って萎む。遠くからでも一目で分かる主役）
	var plume := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.55
	cyl.height = 1.0
	var pm := StandardMaterial3D.new()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = Color(0.92, 0.97, 1.0, 0.9)
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = pm
	plume.mesh = cyl
	add_child(plume)
	plume.global_position = top + Vector3(0, 0.5, 0)
	plume.scale = Vector3(0.6, 0.3, 0.6)
	var ptw := create_tween()
	ptw.tween_property(plume, "scale", Vector3(1.0, 3.4, 1.0), 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ptw.parallel().tween_property(plume, "global_position",
		top + Vector3(0, 1.9, 0), 0.22)
	ptw.tween_property(pm, "albedo_color:a", 0.0, 0.55)
	ptw.parallel().tween_property(plume, "scale", Vector3(1.6, 2.2, 1.6), 0.55)
	ptw.chain().tween_callback(plume.queue_free)
	# 飛沫（白い雫が高く上がって落ちる）
	var p := CPUParticles3D.new()
	add_child(p)
	p.global_position = top
	p.amount = 60
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 26.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 13.0
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.8
	var drop := SphereMesh.new()
	drop.radius = 0.15
	drop.height = 0.34
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.93, 1.0, 0.85)
	m.emission_enabled = true
	m.emission = Color(0.7, 0.85, 1.0)
	m.emission_energy_multiplier = 0.5
	drop.material = m
	p.mesh = drop
	p.emitting = true
	get_tree().create_timer(2.5, true, false, true).timeout.connect(p.queue_free)
	# 波紋（水面に広がる輪。スケールを広げつつ薄くなる板）
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.7
	var rm := StandardMaterial3D.new()
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.9, 0.96, 1.0, 0.7)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = rm
	ring.mesh = torus
	add_child(ring)
	ring.global_position = top
	ring.scale = Vector3(0.4, 0.12, 0.4)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(5.0, 0.12, 5.0), 1.1)
	tw.tween_property(rm, "albedo_color:a", 0.0, 1.1)
	tw.chain().tween_callback(ring.queue_free)


## パッド中心の「胴体中心」ワールド座標
func _pad_pos(p: Array) -> Vector3:
	return Vector3(p[0], terrain.get_height(p[0], p[1]) + 0.78, p[1])


func _standing_on_pad(p: Array) -> void:
	_add_standing(_pad_pos(p))


func _walker_on_pad(p: Array, half: float, speed: float) -> void:
	var c := _pad_pos(p)
	_add_walker(c + Vector3(-half, 0, 0), c + Vector3(half, 0, 0), speed)
