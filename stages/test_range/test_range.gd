extends SniperStage
## テスト射撃場：平原＋遠距離標的（静止1・歩行2・車1）
## 射撃コアの手触りを確かめるための素の練習場。共通の射撃ロジックは SniperStage が持つ。


func _rig_position() -> Vector3:
	return Vector3(0, 6.3, 1.5)  # やぐらの上


func _configure_rig() -> void:
	girl_offset.y = -1.7  # やぐら上面(y=4.6)に足が着く高さ


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.42, 0.65)
	sky_mat.sky_horizon_color = Color(0.68, 0.72, 0.75)
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.2)
	sky_mat.ground_horizon_color = Color(0.6, 0.64, 0.62)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.76, 0.8)
	env.fog_density = 0.0004  # 距離フォグのみ（volumetric禁止）
	world_env.environment = env
	add_child(world_env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.1
	light.shadow_enabled = false  # リアルタイム影はオフ（負荷対策）
	add_child(light)


func _build_world() -> void:
	# 地面（3km四方の平原）
	var ground := StaticBody3D.new()
	ground.collision_layer = 0b0001
	ground.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3000, 1, 3000)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.33, 0.42, 0.29)  # 草原色
	plane.material = mat
	mesh.mesh = plane
	ground.add_child(mesh)
	add_child(ground)
	# 狙撃やぐら（見晴らし確保用の高台）
	var tower := StaticBody3D.new()
	tower.collision_layer = 0b0001
	var tcol := CollisionShape3D.new()
	var tbox := BoxShape3D.new()
	tbox.size = Vector3(2.4, 4.6, 2.4)
	tcol.shape = tbox
	tower.add_child(tcol)
	var tmesh := MeshInstance3D.new()
	var tboxmesh := BoxMesh.new()
	tboxmesh.size = Vector3(2.4, 4.6, 2.4)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.4, 0.36, 0.3)
	tboxmesh.material = tmat
	tmesh.mesh = tboxmesh
	tower.add_child(tmesh)
	tower.position = Vector3(0, 2.3, 1.5)
	add_child(tower)
	# 距離マーカー（100mごとに白線＋距離表示）
	for d in [100, 200, 300, 400, 500, 600]:
		var line := MeshInstance3D.new()
		var lbox := BoxMesh.new()
		lbox.size = Vector3(80, 0.06, 0.35)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.9, 0.9, 0.85)
		lbox.material = lmat
		line.mesh = lbox
		line.position = Vector3(0, 0.03, -d)
		add_child(line)
		var label := Label3D.new()
		label.text = "%dm" % d
		label.font_size = 640
		label.pixel_size = 0.01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.95, 0.95, 0.9)
		label.position = Vector3(-42, 3.5, -d)
		add_child(label)


func _spawn_targets() -> void:
	# C物量モードでは練習標的を置かない（敵はHordeModeが波で湧かせる）
	if GameManager.MODES[GameManager.selected_mode].id == "horde":
		return
	# 静止標的（80m・最初に狙う練習用に近め）
	_add_standing(Vector3(6, 0.76, -80))
	# 歩行標的（300m / 450m・Path3D追従）
	_add_walker(Vector3(-15, 0.76, -300), Vector3(15, 0.76, -300), 1.5)
	_add_walker(Vector3(-20, 0.76, -450), Vector3(20, 0.76, -450), 2.0)
	# 走る車（550m・等速で横切る）
	var car := TargetVehicle.new()
	add_child(car)
	car.global_position = Vector3(-40, 0.85, -550)
	car.speed = 10.0
	car.range_x = 60.0
	_register(car)
