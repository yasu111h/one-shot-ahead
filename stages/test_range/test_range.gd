extends Node3D
## テスト射撃場：平原＋遠距離標的（静止1・歩行2・車1）
## 射撃コアプロトタイプの統括（環境生成・入力・射撃・オートエイム・バレットカム・勝敗管理）
##
## 操作（TABIJIの操作感を移植・マウスキャプチャなし）:
##   視点   … 右ドラッグ（PC）/ 画面右側ドラッグ（タッチ・1本指追跡）
##   発射   … 左クリック / FIREボタン（Fキーは予備）
##   スコープ … Qキー / SCOPEボタンでトグル巡回（1x→4x→8x→1x）。ホイールで段階±1
##   息止め … スペース長押し / BREATHボタン（スコープ中のみ）

const WIND_FACTOR := 0.6  # 風速(m/s)→弾への加速度(m/s^2)係数
const MAX_AMMO := 5
const RANGE_MASK := 0b1111
const KILLCAM_COOLDOWN := 3.0  # バレットカムの再発動までの最短間隔(秒)

@export var muzzle_speed := 300.0  # 弾速 m/s（可変）

# --- オートエイム(吸い付き)。スナイパー用に狭め。TABIJIの_assist_dir方式 ---
@export var assist_deg_hip := 2.0      # 腰だめ時の吸い付き角(度)
@export var assist_deg_scope := 0.6    # スコープ中(狙いやすいので狭め)
@export var assist_touch_mult := 1.5   # タッチ端末は指で粗いので広めに
@export var assist_full_range := 600.0   # この距離までは吸い付き全開
@export var assist_fade_range := 1200.0  # ここで吸い付き0(これ以遠は補正なし)

var wind_speed := 0.0
var wind_accel := Vector3.ZERO
var ammo := MAX_AMMO
var hits := 0
var targets: Array = []
var bullets_in_flight := 0
var game_over := false

var rig: SniperCamera
var bullet_cam: BulletCam
var fx: ShotFx
var sfx: SfxBank
var hud: Hud

var _walkers: Array = []  # {follow: PathFollow3D, target: TargetHuman, speed: float, dir: float}
var _pending_fire := false
var _killcam_cd := 0.0
var _cam_touch_index := -1
var _is_touch := false


func _ready() -> void:
	GameManager.reset_time()
	_is_touch = DisplayServer.is_touchscreen_available()
	_build_environment()
	_build_range()
	_setup_wind()
	_spawn_targets()
	_build_cameras()
	_build_fx()
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
	bullet_cam = BulletCam.new()
	add_child(bullet_cam)
	bullet_cam.finished.connect(_check_end)


func _build_fx() -> void:
	fx = ShotFx.new()
	add_child(fx)
	sfx = SfxBank.new()
	add_child(sfx)


func _build_hud() -> void:
	hud = Hud.new()
	hud.stage = self
	hud.rig = rig
	add_child(hud)


## HUDが照準UIの表示/非表示に使う（バレットカム上映中か）
func is_replay_active() -> bool:
	return bullet_cam != null and bullet_cam.active


# ---------------------------------------------------------------- 入力

func _unhandled_input(event: InputEvent) -> void:
	# タッチ：画面右側(x>幅×0.45)の1本指を追跡し、そのドラッグで視点回転
	# （ボタン上のタッチはTouchScreenButtonが消費する）
	if event is InputEventScreenTouch:
		var w := get_viewport().get_visible_rect().size.x
		if event.pressed and _cam_touch_index == -1 and event.position.x > w * 0.45:
			_cam_touch_index = event.index
		elif not event.pressed and event.index == _cam_touch_index:
			_cam_touch_index = -1
		return
	if event is InputEventScreenDrag:
		if event.index == _cam_touch_index and not is_replay_active():
			rig.add_aim_delta(event.relative)
		return
	# マウス（Mac用。タッチ端末ではエミュレートマウスを無視）
	if _is_touch:
		if event is InputEventKey:
			pass  # 外付けキーボードは許可
		else:
			return
	if event is InputEventMouseMotion:
		# 右ドラッグ＝視点回転（押している間だけ・キャプチャなし）
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not is_replay_active():
			rig.add_aim_delta(event.relative)
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				request_fire()  # 左クリック＝発射
			MOUSE_BUTTON_WHEEL_UP:
				rig.step_zoom(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				rig.step_zoom(-1)
		return
	if event is InputEventKey and not event.echo:
		match event.keycode:
			KEY_Q:
				if event.pressed:
					rig.cycle_zoom()  # Q＝スコープトグル（1x→4x→8x→1x）
			KEY_SPACE:
				if event.pressed:
					rig.start_breath()  # スペース長押し＝息止め（スコープ中のみ）
				else:
					rig.stop_breath()
			KEY_F:
				if event.pressed:
					request_fire()  # 予備の発射キー


# ---------------------------------------------------------------- 射撃

func request_fire() -> void:
	if game_over or is_replay_active() or ammo <= 0 or _pending_fire:
		return
	_pending_fire = true  # 物理フレームで発射（空間クエリの安全のため）


func _physics_process(delta: float) -> void:
	_killcam_cd = maxf(_killcam_cd - delta, 0.0)
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
	# オートエイムのロック表示（捉えたらレティクルが白→オレンジ）
	var locked := false
	if not game_over and not is_replay_active():
		locked = _assist_dir(-rig.camera.global_transform.basis.z) != Vector3.ZERO
	hud.set_locked(locked)
	# 測距（照準先の距離をHUDへ）
	_update_rangefinder()


func _do_fire() -> void:
	if game_over or is_replay_active() or ammo <= 0:
		return
	ammo -= 1
	var cam := rig.camera
	var dir := -cam.global_transform.basis.z
	# オートエイム（吸い付き）：捉えていれば弾道を標的へ曲げる
	var assisted := _assist_dir(dir)
	if assisted != Vector3.ZERO:
		dir = assisted
	var start := cam.global_position + dir * 0.6
	# 撃ち味（反動・マズルフラッシュ・レティクル開き・発射音）
	rig.kick()
	fx.muzzle_flash(start)
	hud.on_shot()
	sfx.play_shot()
	# 弾道を事前予測し、命中確定弾のみバレットカム発動
	var velocity := dir * muzzle_speed
	var infos: Array = []
	for t in targets:
		if t.alive:
			infos.append({
				"node": t,
				"position": t.global_position,
				"velocity": t.velocity_estimate,
				"radius": t.predict_radius,
				"head_offset": t.head_offset,
				"head_radius": t.head_radius,
			})
	var predicted := Ballistics.predict_hit(
		get_world_3d().direct_space_state, start, velocity, wind_accel, infos)
	if not predicted.is_empty() and _killcam_cd <= 0.0:
		_killcam_cd = KILLCAM_COOLDOWN
		_start_replay(start, predicted, dir)
		return
	# 通常弾：実弾（重力・風の毎フレーム積分）を飛ばし、トレーサーを追従させる
	var bullet := Bullet.new()
	add_child(bullet)
	bullet.global_position = start
	bullet.velocity = velocity
	bullet.wind_accel = wind_accel
	bullet.hit.connect(_on_bullet_hit.bind(bullet))
	bullet.vanished.connect(_on_bullet_vanished)
	bullets_in_flight += 1
	fx.attach_tracer(bullet)


## 命中確定弾のバレットカム開始。実弾は飛ばさず、確定弾道をスロー再生し、
## ダメージ適用は「リプレイの着弾の瞬間」（on_impact）に行う。
func _start_replay(start: Vector3, predicted: Dictionary, dir: Vector3) -> void:
	var target: Node = predicted.target
	var zone: String = predicted.get("zone", "body")
	var point: Vector3 = predicted.point
	# 動く標的の補正：予測着弾点は「実飛翔時間ぶん未来」の位置なので、
	# リプレイ中に実際へ進む世界時間（SLOWMO×FLIGHT_TIME≒0.12s）の位置へ引き戻す。
	# これでリプレイの弾は「その瞬間に標的がいる場所」へ命中して見える。
	var tvel: Vector3 = target.velocity_estimate if is_instance_valid(target) else Vector3.ZERO
	var replay_world_dt: float = BulletCam.SLOWMO * BulletCam.FLIGHT_TIME
	var to: Vector3 = point - tvel * (predicted.time - replay_world_dt)
	bullet_cam.play(start, to, func() -> void:
		_on_replay_impact(target, to, zone, dir))


## リプレイの着弾の瞬間：ここで初めてダメージ・スタンプ・ヒットマーカー・命中音を出す
## （倒れる様子はバレットカムの余韻＝HOLD_SLOWMO 0.7秒の中で見える）
func _on_replay_impact(target: Node, point: Vector3, zone: String, dir: Vector3) -> void:
	if not is_instance_valid(target) or not target.alive:
		return
	var dist := int(round(rig.camera.global_position.distance_to(point)))
	target.die(dir * 3.0)
	hits += 1
	hud.show_stamp("%dm %s" % [dist, "HEADSHOT" if zone == "head" else "HIT"])
	hud.show_hitmark(zone)
	if zone == "head":
		sfx.play_headshot()
	else:
		sfx.play_hit()
	# 勝敗判定はバレットカム終了時（finishedシグナル→_check_end）に行う


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


# ---------------------------------------------------------------- オートエイム(TABIJI移植)

## オートエイム: 狙い(base)の近くにいる標的部位("target_part"グループ)を探し、
## 吸い付き角の内なら「その部位に実際に命中する発射方向（重力・風の弾道解）」を返す。
## いなければ Vector3.ZERO。部位がカプセルなら中心でなく「芯線上で狙いに最も近い点」へ。
## ※ TABIJIはヒットスキャンなので部位への直線方向でよいが、本作は実弾道（重力落下・
##    風流され）のため、直線に吸い付くと必ず下に外れる。吸い付き先を弾道補正済みの
##    照準解にすることで「ロック＝当たる」が成立する。
func _assist_dir(base: Vector3) -> Vector3:
	var deg := lerpf(assist_deg_hip, assist_deg_scope, rig.aim_blend)
	if _is_touch:
		deg *= assist_touch_mult
	var best_ang := deg_to_rad(deg)
	var best := Vector3.ZERO
	var eye := rig.camera.global_position
	for n in get_tree().get_nodes_in_group("target_part"):
		if not (n is Node3D) or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var root = n.get_meta("target_root") if n.has_meta("target_root") else null
		if root == null or not is_instance_valid(root) or not root.alive:
			continue
		var point := _aim_point(n, eye, base)
		var d := (point - eye).length()
		# 距離が遠いほど吸い付き角を細くする。assist_fade_range 以遠は補正なし
		var range_k := clampf(
			1.0 - (d - assist_full_range) / (assist_fade_range - assist_full_range), 0.0, 1.0)
		if range_k <= 0.0:
			continue
		# 弾道補正：飛翔時間ぶんの重力・風ドロップを見込んだ照準点（上・風上へずらす）
		var tf := d / muzzle_speed
		var solution := point - (Ballistics.GRAVITY + wind_accel) * (0.5 * tf * tf)
		var to := solution - eye
		var eff_ang := deg_to_rad(deg) * range_k
		var ang := base.angle_to(to.normalized())
		if ang < eff_ang and ang < best_ang:
			best_ang = ang
			best = to.normalized()
	return best


## 部位の狙い点。カプセル(胴体)なら芯線のうちレイに最も近い点、それ以外は中心。
func _aim_point(n: Node3D, eye: Vector3, base: Vector3) -> Vector3:
	for c in n.get_children():
		if c is CollisionShape3D and c.shape is CapsuleShape3D:
			var cap: CapsuleShape3D = c.shape
			var half := maxf(cap.height * 0.5 - cap.radius, 0.0)
			var up: Vector3 = (c as CollisionShape3D).global_transform.basis.y
			var center: Vector3 = (c as CollisionShape3D).global_position
			return _closest_on_segment_to_ray(center - up * half, center + up * half, eye, base)
	return n.global_position


## 線分AB上で、レイ(origin O・方向D)に最も近い点を返す
func _closest_on_segment_to_ray(a: Vector3, b: Vector3, o: Vector3, d: Vector3) -> Vector3:
	var u := b - a
	var w := a - o
	var uu := u.dot(u)
	var ud := u.dot(d)
	var dd := d.dot(d)
	var uw := u.dot(w)
	var dw := d.dot(w)
	var den := uu * dd - ud * ud
	var s := 0.0
	if den > 0.0001:
		s = clampf((ud * dw - dd * uw) / den, 0.0, 1.0)
	return a + u * s


# ---------------------------------------------------------------- 命中処理（通常弾）

func _on_bullet_hit(result: Dictionary, bullet: Bullet) -> void:
	bullets_in_flight -= 1
	var collider: Object = result.collider
	var normal: Vector3 = result.get("normal", Vector3.UP)
	if collider and collider.has_meta("target_root"):
		_handle_target_hit(result, bullet)
	else:
		# 地形に着弾：フレア＋土煙
		fx.impact_burst(result.position, normal)
		_spawn_impact_dust(result.position)
		_check_end()


func _on_bullet_vanished() -> void:
	bullets_in_flight -= 1
	_check_end()


func _handle_target_hit(result: Dictionary, bullet: Bullet) -> void:
	var collider: Object = result.collider
	var target: Node = collider.get_meta("target_root")
	var part: String = collider.get_meta("part", "body")
	var normal: Vector3 = result.get("normal", Vector3.UP)
	if not target.alive:
		# 既に倒れた標的への命中は不算入
		_check_end()
		return
	var dist := int(round(rig.camera.global_position.distance_to(result.position)))
	target.die(bullet.velocity.normalized() * 3.0)
	hits += 1
	fx.impact_burst(result.position, normal)
	hud.show_stamp("%dm %s" % [dist, "HEADSHOT" if part == "head" else "HIT"])
	hud.show_hitmark(part)
	if part == "head":
		sfx.play_headshot()
	else:
		sfx.play_hit()
	_check_end()


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
		hud.show_clear()
	elif ammo <= 0 and bullets_in_flight <= 0 and not is_replay_active():
		game_over = true
		hud.show_retry()


func retry() -> void:
	bullet_cam.abort()
	GameManager.reset_time()
	get_tree().reload_current_scene()
