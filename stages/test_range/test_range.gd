extends Node3D
## テスト射撃場：平原＋遠距離標的（静止1・歩行2・車1）
## 射撃コアプロトタイプの統括（環境生成・入力・射撃・キルカム・勝敗管理）

const WIND_FACTOR := 0.6  # 風速(m/s)→弾への加速度(m/s^2)係数
const MAX_AMMO := 5
const RANGE_MASK := 0b1111

@export var muzzle_speed := 300.0  # 弾速 m/s（可変）

var wind_speed := 0.0
var wind_accel := Vector3.ZERO
var ammo := MAX_AMMO
var hits := 0
var targets: Array = []
var bullets_in_flight := 0
var game_over := false

var rig: SniperCamera
var kill_camera: KillCamera
var slowmo: SlowMotionDirector
var hud: Hud

var _walkers: Array = []  # {follow: PathFollow3D, target: TargetHuman, speed: float, dir: float}
var _pending_fire := false


func _ready() -> void:
	GameManager.reset_time()
	_build_environment()
	_build_range()
	_setup_wind()
	_spawn_targets()
	_build_cameras()
	_build_hud()


# ---------------------------------------------------------------- 環境構築

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


func _build_range() -> void:
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


func _setup_wind() -> void:
	# ステージ開始時にランダムな横風（-5〜+5 m/s、X軸方向）
	wind_speed = randf_range(-5.0, 5.0)
	wind_accel = Vector3(wind_speed, 0, 0) * WIND_FACTOR


func _spawn_targets() -> void:
	# 静止標的（150m）
	var still := TargetHuman.new()
	add_child(still)
	still.global_position = Vector3(6, 0.76, -150)
	targets.append(still)
	# 歩行標的（300m / 450m・Path3D追従）
	_add_walker(-300.0, 15.0, 1.5)
	_add_walker(-450.0, 20.0, 2.0)
	# 走る車（550m・等速で横切る）
	var car := TargetVehicle.new()
	add_child(car)
	car.global_position = Vector3(-40, 0.85, -550)
	car.speed = 10.0
	car.range_x = 60.0
	targets.append(car)


func _add_walker(z: float, half_range: float, speed: float) -> void:
	var path := Path3D.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(-half_range, 0, z))
	curve.add_point(Vector3(half_range, 0, z))
	path.curve = curve
	add_child(path)
	var follow := PathFollow3D.new()
	follow.loop = false
	follow.rotation_mode = PathFollow3D.ROTATION_Y
	path.add_child(follow)
	var man := TargetHuman.new()
	follow.add_child(man)
	man.position = Vector3(0, 0.76, 0)
	targets.append(man)
	_walkers.append({"follow": follow, "target": man, "speed": speed, "dir": 1.0})


func _build_cameras() -> void:
	rig = SniperCamera.new()
	add_child(rig)
	rig.position = Vector3(0, 6.3, 1.5)  # やぐらの上
	kill_camera = KillCamera.new()
	add_child(kill_camera)
	slowmo = SlowMotionDirector.new()
	add_child(slowmo)
	slowmo.kill_camera = kill_camera
	slowmo.main_camera = rig.camera


func _build_hud() -> void:
	hud = Hud.new()
	hud.stage = self
	hud.rig = rig
	add_child(hud)


# ---------------------------------------------------------------- 入力

func _unhandled_input(event: InputEvent) -> void:
	# タッチ：ドラッグで視点回転（ボタン上のタッチはTouchScreenButtonが消費する）
	if event is InputEventScreenDrag:
		if not slowmo.active:
			rig.add_aim_delta(event.relative)
		return
	# マウス（Macテスト用）：キャプチャ中のみ視点回転
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not slowmo.active:
			rig.add_aim_delta(event.relative)
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					if not game_over:
						Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # クリックでキャプチャ開始
				else:
					request_fire()  # 左クリック＝発射
			MOUSE_BUTTON_RIGHT:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					rig.cycle_zoom()  # 右クリック＝スコープ切替（1x→4x→8x→1x）
			MOUSE_BUTTON_WHEEL_UP:
				rig.step_zoom(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				rig.step_zoom(-1)
		return
	if event is InputEventKey and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if event.pressed:
					rig.start_breath()  # スペース長押し＝息止め（スコープ中のみ）
				else:
					rig.stop_breath()
			KEY_ESCAPE:
				if event.pressed:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # Escでマウス解放
			KEY_F:
				if event.pressed:
					request_fire()  # 予備の発射キー


# ---------------------------------------------------------------- 射撃

func request_fire() -> void:
	if game_over or slowmo.active or ammo <= 0 or _pending_fire:
		return
	_pending_fire = true  # 物理フレームで発射（空間クエリの安全のため）


func _physics_process(delta: float) -> void:
	# 歩行標的のPath3D追従（往復）
	for w in _walkers:
		if not w.target.alive:
			continue
		var f: PathFollow3D = w.follow
		f.progress += w.speed * w.dir * delta
		var length: float = (f.get_parent() as Path3D).curve.get_baked_length()
		if f.progress >= length:
			w.dir = -1.0
		elif f.progress <= 0.0:
			w.dir = 1.0
	# 発射処理
	if _pending_fire:
		_pending_fire = false
		_do_fire()
	# 測距（照準先の距離をHUDへ）
	_update_rangefinder()


func _do_fire() -> void:
	if game_over or slowmo.active or ammo <= 0:
		return
	ammo -= 1
	var cam := rig.camera
	var dir := -cam.global_transform.basis.z
	var start := cam.global_position + dir * 0.6
	var bullet := Bullet.new()
	add_child(bullet)
	bullet.global_position = start
	bullet.velocity = dir * muzzle_speed
	bullet.wind_accel = wind_accel
	bullet.hit.connect(_on_bullet_hit.bind(bullet))
	bullet.vanished.connect(_on_bullet_vanished)
	bullets_in_flight += 1
	rig.kick()
	# 弾道を事前予測し、命中確定弾のみキルカム発動
	var infos: Array = []
	for t in targets:
		if t.alive:
			infos.append({
				"node": t,
				"position": t.global_position,
				"velocity": t.velocity_estimate,
				"radius": t.predict_radius,
			})
	var predicted := Ballistics.predict_hit(
		get_world_3d().direct_space_state, start, bullet.velocity, wind_accel, infos)
	if not predicted.is_empty():
		slowmo.start_killcam(bullet)


func _update_rangefinder() -> void:
	var from := rig.camera.global_position
	var dir := -rig.camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 1500.0, RANGE_MASK)
	query.collide_with_areas = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		hud.range_distance = from.distance_to(result.position)
	else:
		hud.range_distance = -1.0


# ---------------------------------------------------------------- 命中処理

func _on_bullet_hit(result: Dictionary, bullet: Bullet) -> void:
	bullets_in_flight -= 1
	var collider: Object = result.collider
	if collider and collider.has_meta("target_root"):
		_handle_target_hit(result, bullet)
	else:
		# 地形に着弾：土煙のみ（キルカム中なら即復帰＝予測外れ）
		_spawn_impact_dust(result.position)
		if slowmo.active:
			slowmo.end_killcam()
		_check_end()


func _on_bullet_vanished() -> void:
	bullets_in_flight -= 1
	if slowmo.active:
		slowmo.end_killcam()
	_check_end()


func _handle_target_hit(result: Dictionary, bullet: Bullet) -> void:
	var collider: Object = result.collider
	var target: Node = collider.get_meta("target_root")
	var zone: String = collider.get_meta("zone", "body")
	if not target.alive:
		# 既に倒れた標的への命中は不算入
		if slowmo.active:
			slowmo.end_killcam()
		_check_end()
		return
	var dist := int(round(rig.camera.global_position.distance_to(result.position)))
	target.die(bullet.velocity.normalized() * 3.0)
	hits += 1
	var text := "%dm %s" % [dist, "HEADSHOT" if zone == "head" else "HIT"]
	if slowmo.active:
		_killcam_impact(text)
	else:
		hud.show_stamp(text)
	_check_end()


## キルカム着弾演出：一拍止め→倒れを見せてから通常復帰
func _killcam_impact(text: String) -> void:
	Engine.time_scale = 0.05
	hud.show_stamp(text)
	await get_tree().create_timer(0.45, true, false, true).timeout
	if not is_instance_valid(self) or not slowmo.active:
		return
	Engine.time_scale = 0.35  # 倒れる様子を少し見せる
	await get_tree().create_timer(1.4, true, false, true).timeout
	if not is_instance_valid(self) or not slowmo.active:
		return
	slowmo.end_killcam()


func _spawn_impact_dust(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	add_child(p)
	p.global_position = pos + Vector3(0, 0.1, 0)
	p.amount = 14
	p.lifetime = 0.8
	p.one_shot = true
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.5
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.4)
	sphere.material = mat
	p.mesh = sphere
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- 勝敗

func _check_end() -> void:
	if game_over:
		return
	if hits >= targets.size():
		game_over = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.show_clear()
	elif ammo <= 0 and bullets_in_flight <= 0:
		game_over = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.show_retry()


func retry() -> void:
	GameManager.reset_time()
	get_tree().reload_current_scene()
