class_name SniperStage
extends Node3D
## 狙撃ステージの共通基底。環境・入力・射撃・オートエイム・バレットカム・勝敗を持つ。
## ステージ固有（見た目・地形・標的配置・狙撃地点）はサブクラスが下記を上書きする:
##   _build_environment() … 空・光・フォグ
##   _build_world()       … 地形/建物
##   _spawn_targets()     … 標的の配置（_register / _add_walker を使う）
##   _rig_position()      … 狙撃地点
##   _setup_wind()        … 風（既定はランダム横風。Ballistics.WIND_ENABLED=false の間は
##                            弾に影響せずHUDにも出ない。風を復活させたら自動で有効化）
##
## 操作（TABIJIの操作感・マウスキャプチャなし）:
##   視点   … 右ドラッグ（PC）/ 画面右側ドラッグ（タッチ・1本指追跡）
##   発射   … 左クリック / FIREボタン（Fキーは予備）
##   スコープ … Qキー / SCOPEボタンでトグル巡回（1x→4x→8x→1x）。ホイールで段階±1
##   息止め … スペース長押し / BREATHボタン（スコープ中のみ）

const WIND_FACTOR := 0.6  # 風速(m/s)→弾への加速度(m/s^2)係数
const RANGE_MASK := 0b1111
const TERRAIN_MASK := 0b0001
const KILLCAM_COOLDOWN := 3.0  # バレットカムの再発動までの最短間隔(秒)

@export var muzzle_speed := 300.0  # 弾速 m/s（可変）
@export var max_ammo := 100

# --- オートエイム(吸い付き)。スナイパー用に狭め。TABIJIの_assist_dir方式 ---
@export var assist_deg_hip := 2.0      # 腰だめ時の吸い付き角(度)
@export var assist_deg_scope := 0.6    # スコープ中(狙いやすいので狭め)
@export var assist_touch_mult := 1.5   # タッチ端末は指で粗いので広めに
@export var assist_full_range := 600.0   # この距離までは吸い付き全開
@export var assist_fade_range := 1200.0  # ここで吸い付き0(これ以遠は補正なし)

var wind_speed := 0.0
var wind_accel := Vector3.ZERO
var ammo := 0
var hits := 0
var targets: Array = []    # 弾道予測の対象（悪人＋民間人。民間人も「弾を止める者」として要る）
var hostiles: Array = []   # 撃つべき標的（勝敗判定はこの数で行う）
var bullets_in_flight := 0
var game_over := false

var rig: SniperCamera
var bullet_cam: BulletCam
var fx: ShotFx
var sfx: SfxBank
var hud: Hud

var _walkers: Array = []  # {follow: PathFollow3D, target: Node, speed: float, dir: float}
var _pending_fire := false
var _killcam_cd := 0.0
var _cam_touch_index := -1
var _is_touch := false


func _ready() -> void:
	GameManager.reset_time()
	_is_touch = DisplayServer.is_touchscreen_available()
	ammo = max_ammo
	_build_environment()
	_build_world()
	_setup_wind()
	_spawn_targets()
	_build_cameras()
	_build_fx()
	_build_hud()


# ---------------------------------------------------------------- サブクラスの差し替え点

func _build_environment() -> void:
	pass


func _build_world() -> void:
	pass


func _spawn_targets() -> void:
	pass


## 狙撃地点（カメラリグの位置）
func _rig_position() -> Vector3:
	return Vector3.ZERO


## ステージ開始時のランダムな横風（X軸方向）
func _setup_wind() -> void:
	wind_speed = randf_range(-5.0, 5.0)
	wind_accel = Vector3(wind_speed, 0, 0) * WIND_FACTOR


# ---------------------------------------------------------------- 標的の登録

## 標的をステージに登録する（add_childは呼び出し側で済ませておく）
func _register(t: Node) -> void:
	targets.append(t)
	if t.hostile:
		hostiles.append(t)


## 2点間を往復する歩行標的を作る。from/to は「胴体中心」のワールド座標
func _add_walker(from: Vector3, to: Vector3, speed: float, hostile := true) -> TargetHuman:
	var path := Path3D.new()
	var curve := Curve3D.new()
	curve.add_point(from)
	curve.add_point(to)
	path.curve = curve
	add_child(path)
	var follow := PathFollow3D.new()
	follow.loop = false
	follow.rotation_mode = PathFollow3D.ROTATION_Y
	path.add_child(follow)
	var man := TargetHuman.new()
	man.hostile = hostile
	follow.add_child(man)
	_register(man)
	_walkers.append({"follow": follow, "target": man, "speed": speed, "dir": 1.0})
	return man


## その場に立つ標的を作る（民間人はこれ）
func _add_standing(pos: Vector3, hostile := true) -> TargetHuman:
	var man := TargetHuman.new()
	man.hostile = hostile
	add_child(man)
	man.global_position = pos
	_register(man)
	return man


# ---------------------------------------------------------------- 組み立て

func _build_cameras() -> void:
	rig = SniperCamera.new()
	add_child(rig)
	rig.position = _rig_position()
	# 起動時は最も近い標的がほぼ画面中央に見える向きにする
	var nearest := _nearest_hostile()
	if nearest != null:
		rig.aim_at(nearest.global_position)
	bullet_cam = BulletCam.new()
	add_child(bullet_cam)
	bullet_cam.finished.connect(_check_end)


func _nearest_hostile() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for t in hostiles:
		if not (t is Node3D) or not is_instance_valid(t) or not t.is_inside_tree():
			continue
		var d: float = rig.global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


func _build_fx() -> void:
	fx = ShotFx.new()
	add_child(fx)
	sfx = SfxBank.new()
	add_child(sfx)


func _build_hud() -> void:
	hud = Hud.new()
	hud.stage = self
	hud.rig = rig
	hud.mission = _mission_text()
	add_child(hud)


## HUD左上に出すミッション文（サブクラスが上書き。空なら非表示）
func _mission_text() -> String:
	return ""


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
	# マウス（Mac用）。タッチ端末で実タッチから合成されるエミュレートマウスだけを
	# 無視し、実マウスは端末判定に関わらず常に受け付ける
	# （※旧実装の「タッチ端末なら全マウス無視」は、端末誤判定時にMacの
	#   クリック・右ドラッグが全滅するため device 判定に変更）
	if event.device == InputEvent.DEVICE_ID_EMULATION and not (event is InputEventKey):
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
	var raw := -cam.global_transform.basis.z
	# 弾道予測には民間人も混ぜる。手前に立たれていたら悪人への命中は「確定」しない
	var infos := _target_infos()
	# オートエイム（吸い付き）：捉えていれば弾道を標的へ曲げる
	var dir := raw
	var assisted := _assist_dir(raw)
	if assisted != Vector3.ZERO:
		dir = assisted
	var start := cam.global_position + dir * 0.6
	var predicted := _predict(start, dir, infos)
	# 吸い付きが弾を民間人へ寄せてしまった場合は補正を捨て、素の狙いで撃つ
	# （プレイヤーが狙っていない誤射を、こちらの補正で作らない）
	if assisted != Vector3.ZERO and not predicted.is_empty() and not predicted.target.hostile:
		dir = raw
		start = cam.global_position + dir * 0.6
		predicted = _predict(start, dir, infos)
	# 撃ち味（反動・マズルフラッシュ・レティクル開き・発射音）
	rig.kick()
	fx.muzzle_flash(start)
	hud.on_shot()
	sfx.play_shot()
	# 悪人への命中確定弾だけがバレットカムになる（民間人への誤射は演出せず実弾で見せる）
	if not predicted.is_empty() and predicted.target.hostile and _killcam_cd <= 0.0:
		_killcam_cd = KILLCAM_COOLDOWN
		_start_replay(start, predicted, dir)
		return
	# ミス弾（何にも当たらない弾）も、設定ONならバレットカムで見送る
	# （クールダウンは命中と共通。誤射＝民間人命中の予測弾は従来どおり実弾で見せる）
	if predicted.is_empty() and Settings.miss_replay_enabled and _killcam_cd <= 0.0:
		_killcam_cd = KILLCAM_COOLDOWN
		_start_miss_replay(start, dir)
		return
	# 通常弾：実弾（Ballisticsの毎フレーム積分。既定は直線・等速）を飛ばし、
	# トレーサーを追従させる
	var bullet := Bullet.new()
	add_child(bullet)
	bullet.global_position = start
	bullet.velocity = dir * muzzle_speed
	bullet.wind_accel = wind_accel
	bullet.hit.connect(_on_bullet_hit.bind(bullet))
	bullet.vanished.connect(_on_bullet_vanished)
	bullets_in_flight += 1
	fx.attach_tracer(bullet)


## 生きている標的の弾道予測用スナップショット
func _target_infos() -> Array:
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
	return infos


func _predict(start: Vector3, dir: Vector3, infos: Array) -> Dictionary:
	return Ballistics.predict_hit(
		get_world_3d().direct_space_state, start, dir * muzzle_speed, wind_accel, infos)


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


## ミス弾のバレットカム開始。地面への着弾予測点（最大射程まで何にも当たらなければ
## 最大射程点）までスロー再生する。ダメージはなく、余韻突入時に「MISS」表示と、
## 地面着弾なら土煙FX（着弾フレア＋火花）を出す。
func _start_miss_replay(start: Vector3, dir: Vector3) -> void:
	var impact := Ballistics.predict_miss_point(
		get_world_3d().direct_space_state, start, dir * muzzle_speed, wind_accel)
	var point: Vector3 = impact.point
	var normal: Vector3 = impact.normal
	var grounded: bool = impact.grounded
	bullet_cam.play(start, point, func() -> void:
		if grounded:
			fx.impact_burst(point, normal)
			_spawn_impact_dust(point)
		hud.show_miss_stamp())


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
## 吸い付き角の内なら「その部位に実際に命中する発射方向（弾道解）」を返す。
## いなければ Vector3.ZERO。部位がカプセルなら中心でなく「芯線上で狙いに最も近い点」へ。
## ※ 弾道解は Ballistics のフラグに従う。現行の直線弾道では部位への直線方向そのもの。
##    重力・風（GRAVITY_ENABLED / WIND_ENABLED）を復活させた場合は、飛翔時間ぶんの
##    ドロップを見込んだ照準解に自動で切り替わり「ロック＝当たる」が維持される。
## ※ 民間人と、壁の陰にいる標的には吸い付かない（ロック＝当たる、を壊さないため）。
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
		if root == null or not is_instance_valid(root) or not root.alive or not root.hostile:
			continue
		var point := _aim_point(n, eye, base)
		var d := (point - eye).length()
		# 距離が遠いほど吸い付き角を細くする。assist_fade_range 以遠は補正なし
		var range_k := clampf(
			1.0 - (d - assist_full_range) / (assist_fade_range - assist_full_range), 0.0, 1.0)
		if range_k <= 0.0:
			continue
		var eff_ang := deg_to_rad(deg) * range_k
		# 弾道補正：飛翔時間ぶんのドロップを見込んだ照準点。
		# Ballistics のフラグに従う（直線弾道＝実効加速度ゼロなら補正なし＝部位そのもの）
		var tf := d / muzzle_speed
		var solution := point - Ballistics.effective_accel(wind_accel) * (0.5 * tf * tf)
		var to := solution - eye
		var ang := base.angle_to(to.normalized())
		if ang >= eff_ang or ang >= best_ang:
			continue
		if _blocked_by_terrain(eye, point):
			continue  # 壁・床の陰。見えていない標的には吸い付かせない
		best_ang = ang
		best = to.normalized()
	return best


## 視線が地形（レイヤ1）で遮られているか
func _blocked_by_terrain(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, TERRAIN_MASK)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## 狙撃地点からその点が見えているか（HUDの標的マーカーが使う）
func has_line_of_sight(point: Vector3) -> bool:
	if rig == null or rig.camera == null:
		return false
	return not _blocked_by_terrain(rig.camera.global_position, point)


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
	fx.impact_burst(result.position, normal)
	# 民間人の誤射＝即ミッション失敗
	if not target.hostile:
		sfx.play_hit()
		_fail("CIVILIAN DOWN")
		return
	hits += 1
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

func _fail(msg: String) -> void:
	if game_over:
		return
	game_over = true
	hud.show_fail(msg)


func _check_end() -> void:
	if game_over:
		return
	if hits >= hostiles.size():
		game_over = true
		hud.show_clear()
	elif ammo <= 0 and bullets_in_flight <= 0 and not is_replay_active():
		game_over = true
		hud.show_fail("AMMO OUT")


func retry() -> void:
	bullet_cam.abort()
	GameManager.reset_time()
	get_tree().reload_current_scene()
