extends SniperStage
## 「砂漠の検問所」ステージ（夜明け）。
## 武装勢力が幹線道路の検問所を占拠し、通行車両を止めて略奪している。
## プレイヤーは道路脇の監視塔から、悪人だけを撃ち抜く。
## 車を止められた民間人（白）がすぐそばにいる＝誤射は即ミッション失敗。
## 距離の構成：見張り約180m → 検問所約375m → 遠方の停車帯約650m（高倍率スコープの見せ場）。
## 見た目はTABIJI（beautiful-journey）の砂丘の考え方を流用（地形・砂・夜明けの空）。

var terrain: DesertTerrain


func _enter_tree() -> void:
	# シェーダ描きの窓ガラスは無い＝垂直面をガラス扱いさせない
	set_meta("facade_windows_enabled", false)


func _rig_position() -> Vector3:
	# 監視塔の上（丘 + 塔9.5m + 目線1.75m）
	var base_h := terrain.get_height(DesertTerrain.RIG_XZ.x, DesertTerrain.RIG_XZ.y)
	return Vector3(DesertTerrain.RIG_XZ.x, base_h + 9.62 + 1.75, DesertTerrain.RIG_XZ.y)


func _configure_rig() -> void:
	girl_offset.y = -1.75  # 塔の床板に足が着く高さ
	# 前方（-Z＝道路の彼方）を中心に左右へ70度。
	# 下は足元の道路まで・上は夜明けの空を少しだけ
	rig.set_view_limits(-70.0, 70.0, -35.0, 15.0)


func _mission_text() -> String:
	return "MISSION: ELIMINATE %d HOSTILES  /  DO NOT SHOOT CIVILIANS (WHITE)" % hostiles.size()


## 砂漠の朝風（±4m/s）
func _setup_wind() -> void:
	wind_speed = randf_range(-4.0, 4.0)
	wind_accel = Vector3(wind_speed, 0, 0) * WIND_FACTOR


## 夜明けの砂漠: 暖色の地平線と低い太陽。長距離狙撃なのでフォグは薄く
func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky_desert_dawn.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0

	# 距離フォグ（暖色・ごく薄く）。650m先の停車帯が読める濃さに抑える
	env.fog_enabled = true
	env.fog_light_color = Color(0.9, 0.6, 0.38)
	env.fog_density = 0.0005
	env.fog_sun_scatter = 0.3
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.12

	# 朝日と小屋の明かりをにじませる控えめなグロー
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.05

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 低い朝日。前方(-Z)のやや右＝逆光気味のドラマチックな絵。
	# 標的の視認性はambient(空)と赤い標的色で確保する
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.78, 0.55)
	sun.light_energy = 1.25
	sun.shadow_enabled = false  # リアルタイム影はオフ（モバイル負荷対策）
	sun.rotation_degrees = Vector3(-12.0, 160.0, 0.0)
	add_child(sun)


func _build_world() -> void:
	terrain = DesertTerrain.new()
	add_child(terrain)
	_build_road()
	_build_tower()
	_build_checkpoint()
	_build_far_stop()
	_build_poles()
	_build_rocks()
	_build_mesas()


# ---------------------------------------------------------------- 道路

## アスファルトの一本道。地形の道路コリドー（同じroad_height）に沿って
## 16m刻みの帯を敷く。見た目のみ（当たり判定は直下の地形が担う）
func _build_road() -> void:
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.17, 0.16, 0.16)
	asphalt.roughness = 1.0
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.85, 0.8, 0.7)
	var seg_len := 16.0
	var idx := 0
	var z := -40.0
	while z > -816.0:
		var z2 := z - seg_len
		var h1 := terrain.road_height(z)
		var h2 := terrain.road_height(z2)
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(7.4, 0.1, seg_len + 0.2)
		box.material = asphalt
		seg.mesh = box
		seg.position = Vector3(0, (h1 + h2) * 0.5 + 0.03, (z + z2) * 0.5)
		seg.rotation.x = asin(clampf((h2 - h1) / seg_len, -1.0, 1.0))
		add_child(seg)
		# センターラインの破線（1区間おき）
		if idx % 2 == 0:
			var dash := MeshInstance3D.new()
			var dbox := BoxMesh.new()
			dbox.size = Vector3(0.25, 0.02, 3.0)
			dbox.material = paint
			dash.mesh = dbox
			dash.position = Vector3(0, 0.07, 0)
			seg.add_child(dash)
		idx += 1
		z = z2


# ---------------------------------------------------------------- 監視塔（狙撃地点）

func _build_tower() -> void:
	var cx := DesertTerrain.RIG_XZ.x
	var cz := DesertTerrain.RIG_XZ.y
	var base_h := terrain.get_height(cx, cz)
	# 塔本体（鋼材色の柱）
	_static_box(Vector3(2.6, 9.4, 2.6), Vector3(cx, base_h + 4.7, cz), Color(0.38, 0.34, 0.3))
	# 床板
	_static_box(Vector3(3.6, 0.24, 3.6), Vector3(cx, base_h + 9.52, cz), Color(0.46, 0.4, 0.33))
	# 手すり（4辺・撃ち下ろしを遮らない低さ）
	var rail := Color(0.3, 0.27, 0.24)
	_static_box(Vector3(3.6, 0.08, 0.08), Vector3(cx, base_h + 10.4, cz - 1.76), rail, false)
	_static_box(Vector3(3.6, 0.08, 0.08), Vector3(cx, base_h + 10.4, cz + 1.76), rail, false)
	_static_box(Vector3(0.08, 0.08, 3.6), Vector3(cx - 1.76, base_h + 10.4, cz), rail, false)
	_static_box(Vector3(0.08, 0.08, 3.6), Vector3(cx + 1.76, base_h + 10.4, cz), rail, false)


# ---------------------------------------------------------------- 検問所（約375m）

func _build_checkpoint() -> void:
	var hh := terrain.get_height(-9.0, -384.0)
	# 検問小屋（漆喰壁＋陸屋根）
	_static_box(Vector3(4.6, 3.2, 3.8), Vector3(-9.0, hh + 1.6, -384.0), Color(0.78, 0.66, 0.5))
	_static_box(Vector3(5.2, 0.25, 4.4), Vector3(-9.0, hh + 3.32, -384.0), Color(0.5, 0.4, 0.32))
	# 窓明かり（夜明けでもまだ点いている＝標的エリアの目印）
	var win := MeshInstance3D.new()
	var wbox := BoxMesh.new()
	wbox.size = Vector3(0.06, 1.0, 1.6)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(1.0, 0.8, 0.45)
	wmat.emission_enabled = true
	wmat.emission = Color(1.0, 0.75, 0.4)
	wmat.emission_energy_multiplier = 2.0
	wbox.material = wmat
	win.mesh = wbox
	win.position = Vector3(-9.0 + 2.31, hh + 1.9, -385.0)
	add_child(win)
	# ドア（道路側の面）
	_static_box(Vector3(0.06, 2.2, 1.1), Vector3(-9.0 + 2.32, hh + 1.1, -382.8),
		Color(0.3, 0.22, 0.16), false)
	# 遮断バリア（紅白の棒。歩く見張りが低い棒の奥を横切る）
	var bh := terrain.road_height(-372.0)
	_static_box(Vector3(0.22, 1.3, 0.22), Vector3(-5.4, bh + 0.65, -372.0), Color(0.6, 0.58, 0.55))
	_static_box(Vector3(0.22, 1.3, 0.22), Vector3(5.4, bh + 0.65, -372.0), Color(0.6, 0.58, 0.55))
	for i in 6:
		var col := Color(0.85, 0.15, 0.12) if i % 2 == 0 else Color(0.92, 0.9, 0.86)
		_static_box(Vector3(1.8, 0.16, 0.16),
			Vector3(-4.5 + i * 1.8, bh + 1.05, -372.0), col)
	# 土のう（小屋の角と道路の反対側）
	_build_sandbags(Vector2(-6.2, -374.5))
	_build_sandbags(Vector2(5.8, -376.5))
	# ドラム缶
	_build_drum(Vector2(-6.8, -381.0), Color(0.55, 0.3, 0.15))
	_build_drum(Vector2(-6.0, -380.2), Color(0.25, 0.32, 0.22))
	# 止められた民間人の車（バリア手前）
	_build_car(Vector2(1.8, -366.0), Color(0.82, 0.78, 0.7))


## 土のうの小さな積み
func _build_sandbags(at: Vector2) -> void:
	var h := terrain.get_height(at.x, at.y)
	var col := Color(0.62, 0.52, 0.38)
	_static_box(Vector3(1.2, 0.32, 0.5), Vector3(at.x, h + 0.16, at.y), col)
	_static_box(Vector3(1.2, 0.32, 0.5), Vector3(at.x + 0.15, h + 0.48, at.y + 0.05), col)
	_static_box(Vector3(0.9, 0.32, 0.5), Vector3(at.x - 0.05, h + 0.8, at.y - 0.03), col)


func _build_drum(at: Vector2, color: Color) -> void:
	var h := terrain.get_height(at.x, at.y)
	var body := StaticBody3D.new()
	body.collision_layer = 0b0001
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 0.9
	cs.shape = cyl
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.35
	mesh.bottom_radius = 0.35
	mesh.height = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	mi.mesh = mesh
	body.add_child(mi)
	body.position = Vector3(at.x, h + 0.45, at.y)
	add_child(body)


# ---------------------------------------------------------------- 遠方の停車帯（約650m）

func _build_far_stop() -> void:
	# 止められた車（悪人がそばを歩き回る＝超遠距離の的）
	_build_car(Vector2(0.8, -652.0), Color(0.45, 0.12, 0.1))


## 停車中の車（プロップ・撃つ対象ではない）。長軸は道路(Z)方向
func _build_car(at: Vector2, color: Color) -> void:
	var h := terrain.get_height(at.x, at.y)
	var body := StaticBody3D.new()
	body.collision_layer = 0b0001
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.7, 4.4)
	cs.shape = shape
	cs.position = Vector3(0, 1.0, 0)
	body.add_child(cs)
	# 車体
	var mk := func(size: Vector3, pos: Vector3, col: Color) -> void:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		box.material = mat
		mi.mesh = box
		mi.position = pos
		body.add_child(mi)
	mk.call(Vector3(1.9, 0.35, 4.0), Vector3(0, 0.28, 0), Color(0.12, 0.12, 0.13))  # 足回り
	mk.call(Vector3(1.9, 0.9, 4.4), Vector3(0, 0.9, 0), color)                       # 車体
	mk.call(Vector3(1.7, 0.65, 2.2), Vector3(0, 1.65, -0.3), color.darkened(0.35))   # キャビン
	body.position = Vector3(at.x, h, at.y)
	add_child(body)


# ---------------------------------------------------------------- 沿道の小物・遠景

## 道路沿いの電柱（距離感のスケールを作る）
func _build_poles() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.22, 0.18)
	for i in 7:
		var z := -80.0 - i * 100.0
		var h := terrain.get_height(8.6, z)
		var body := StaticBody3D.new()
		body.collision_layer = 0b0001
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.4, 7.0, 0.4)
		cs.shape = shape
		cs.position = Vector3(0, 3.5, 0)
		body.add_child(cs)
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.12
		cyl.bottom_radius = 0.14
		cyl.height = 7.0
		cyl.material = mat
		pole.mesh = cyl
		pole.position = Vector3(0, 3.5, 0)
		body.add_child(pole)
		var arm := MeshInstance3D.new()
		var abox := BoxMesh.new()
		abox.size = Vector3(1.6, 0.12, 0.12)
		abox.material = mat
		arm.mesh = abox
		arm.position = Vector3(0, 6.6, 0)
		body.add_child(arm)
		body.position = Vector3(8.6, h, z)
		add_child(body)


## 道路脇の岩（見た目＋当たり判定）
func _build_rocks() -> void:
	var spots := [
		Vector3(-14.0, -140.0, 1.6), Vector3(18.0, -260.0, 2.2),
		Vector3(-20.0, -420.0, 1.8), Vector3(14.0, -520.0, 1.4),
		Vector3(-11.0, -590.0, 2.6),
	]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.37, 0.28)
	mat.roughness = 1.0
	for s in spots:
		var r: float = s.z
		var h := terrain.get_height(s.x, s.y)
		var body := StaticBody3D.new()
		body.collision_layer = 0b0001
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = r * 0.85
		cs.shape = sph
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = r
		mesh.height = r * 2.0
		mesh.material = mat
		mi.mesh = mesh
		mi.scale = Vector3(1.0, 0.62, 1.0)
		body.add_child(mi)
		body.position = Vector3(s.x, h + r * 0.25, s.y)
		add_child(body)


## 遠景の岩山。地平線のシルエット＝砂漠の空気感。
## 「見える物には当たり判定」の原則どおり衝突も持つ
func _build_mesas() -> void:
	# 幅広・低めの山型シルエットにして「浮いた箱」に見せない。
	# 基部は砂丘に深めに沈め、フォグの中で裾が地平線と溶けるようにする
	var spots := [
		[Vector2(-360.0, -1080.0), Vector3(360.0, 60.0, 160.0)],
		[Vector2(260.0, -1180.0), Vector3(420.0, 78.0, 180.0)],
		[Vector2(560.0, -980.0), Vector3(300.0, 48.0, 140.0)],
		[Vector2(-120.0, -1300.0), Vector3(380.0, 66.0, 170.0)],
	]
	for s in spots:
		var at: Vector2 = s[0]
		var size: Vector3 = s[1]
		var base := terrain.get_height(at.x, at.y) - 22.0
		var body := StaticBody3D.new()
		body.collision_layer = 0b0001
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, size.y, size.z)
		cs.shape = shape
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var prism := PrismMesh.new()  # 上がすぼまる台形＝メサの形
		prism.size = size
		prism.left_to_right = 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.34, 0.2, 0.17)
		mat.roughness = 1.0
		prism.material = mat
		mi.mesh = prism
		mi.scale = Vector3(1.0, 1.0, 1.0)
		body.add_child(mi)
		body.position = Vector3(at.x, base + size.y * 0.5, at.y)
		add_child(body)


## 箱プロップの共通生成（当たり判定つき既定）
func _static_box(size: Vector3, pos: Vector3, color: Color, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	mi.mesh = box
	if not collide:
		mi.position = pos
		add_child(mi)
		return
	var body := StaticBody3D.new()
	body.collision_layer = 0b0001
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.add_child(mi)
	body.position = pos
	add_child(body)


# ---------------------------------------------------------------- 標的

func _spawn_targets() -> void:
	# ① 尾根の見張り（約180m・最初に狙う的）。道路脇に立ち塔の方を睨む
	var h1 := terrain.get_height(-7.5, -180.0)
	var lookout := _add_standing(Vector3(-7.5, h1 + 0.76, -180.0), true)
	lookout.rotation.y = PI  # プレイヤー側を向く
	# ② 検問所の見張り（約370m）。バリアの手前＝止めた車の周りを歩き回り、
	#    車と民間人の陰に周期的に隠れる（撃てるのは開けた左半分にいる一瞬）
	var h2 := terrain.get_height(0.0, -369.0)
	_add_walker(Vector3(-5.0, h2 + 0.76, -369.0), Vector3(5.0, h2 + 0.76, -369.0), 1.4)
	# ③ 小屋の屋上の見張り（約375m・高所）
	var hh := terrain.get_height(-9.0, -384.0)
	var roof := _add_standing(Vector3(-9.0, hh + 3.45 + 0.76, -384.6), true)
	roof.rotation.y = PI
	# ④ 遠方の停車帯（約650m・超遠距離）。車から降ろした荷を漁って歩き回る
	var h4 := terrain.get_height(2.0, -650.0)
	_add_walker(Vector3(-0.5, h4 + 0.76, -650.0), Vector3(4.5, h4 + 0.76, -650.0), 1.0)

	# 民間人（撃てば即失敗）
	# 検問所: 車を止められ両手を上げて立ちすくむドライバー
	var c1 := terrain.get_height(3.6, -363.5)
	_add_standing(Vector3(3.6, c1 + 0.76, -363.5), false)
	# 遠方: 車のそばに残された同乗者
	var c2 := terrain.get_height(-1.2, -653.0)
	_add_standing(Vector3(-1.2, c2 + 0.76, -653.0), false)
