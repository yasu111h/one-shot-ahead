class_name CityTraffic
extends Node3D
## 夜の街の交通(都市ステージ改修 2026-07-12)。
##
## クロス通り(z=-120・X方向)を車が行き交う:
##   ①環境カー: 両車線を等速で流れる。弾は当たれば止まる(地形レイヤ)が標的ではない
##   ②VIP車(黒いバン): 交差点の信号で停車し、停まっている数秒だけプレイヤー側の
##     スモークガラスが下がって車内の標的の頭が覗く(走行中は防弾ガラスで撃てない)
## メイン通りには路肩の駐車車両を置く(視差と生活感)。
##
## 実装メモ:
## - 車はAnimatableBody3D(地形レイヤ1)。動いても弾・測距レイが正しく当たる
## - VIPのキャビンは1枚箱ではなくパネル分割。プレイヤー側後部だけが本当の
##   「開口」で、そこを可動のスモークガラス(コリジョン付き)が塞ぐ
## - 標的(TargetHuman)は物理ボディの入れ子を避けるため車の子にせず、
##   毎物理フレームで座席位置へ追従させる(倒れたら追従をやめてラグドール)
## - 信号機は車の状態と同期して赤/緑が切り替わる

const CROSS_Z := -120.0          # クロス通りの中心z
const LANE_HALF := 3.1           # 車線のオフセット(中心から)
const CAR_RANGE := 200.0         # 走行範囲 ±CAR_RANGE(遠景リングビルの内側)
const VIP_STOP_X := -6.0         # VIP車の停止位置(交差点の信号手前)
const VIP_SPEED := 13.0
const VIP_STOP_TIME := 7.0       # 停車時間(このうち中盤で窓が開く)
const WINDOW_SLIDE := 0.7        # 窓の開閉にかかる秒数
const WINDOW_OPEN_WAIT := 1.2    # 停車してから窓が開き始めるまで
const WINDOW_TRAVEL := 0.62      # 窓ガラスが下がる距離(m)
const BRAKE_DIST := 22.0         # 減速開始距離

# バンの寸法(VIP車)
const VAN_L := 5.0
const VAN_W := 2.0
const CHASSIS_TOP := 1.34        # 下半身(シャシー)の上端y
const CAB_H := 0.92              # キャビンの高さ
const CAB_TOP := CHASSIS_TOP + CAB_H

var vip_target: Node3D = null    # ステージが seat_vip() で渡す(座席追従とalive監視)

var _cars: Array = []            # 環境カー {body, dir, speed}
# 被弾リアクション対象の車の状態: body -> {state: "ok"/"spin"/"burn"/"wreck",
#   t: float, spin_rate: float, vel: Vector3, fire: Node3D, light: OmniLight3D}
var _car_states: Dictionary = {}
var _vip: AnimatableBody3D
var _vip_window: AnimatableBody3D
var _vip_window_y0 := 0.0        # 窓ガラスの閉位置y(ローカル)
var _vip_light: OmniLight3D
var _signal_red: StandardMaterial3D
var _signal_green: StandardMaterial3D
var _seat: Node3D                # 座席マーカー(標的が毎フレームここへ追従)

# VIP状態機械: cruise(進入)→brake(減速)→stop(停車・窓開閉)→go(加速して退場)→ループ
var _vip_state := "cruise"
var _vip_t := 0.0
var _vip_speed := VIP_SPEED
var _window_open := 0.0          # 0=閉(走行中)〜1=全開


func _ready() -> void:
	_build_road_dressing()
	_build_ambient_cars()
	_build_parked_cars()
	_build_vip_car()
	_build_signal()


## ステージが呼ぶ: VIP車の後部座席位置に標的を置く(以後、車に追従する)
func seat_vip(target: Node3D) -> void:
	vip_target = target
	_sync_vip_target()


# ---------------------------------------------------------------- 見た目の部品

func _car_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.6
	m.roughness = 0.35
	return m


## メッシュ＋(必要なら)同形のコリジョンを body に付ける
func _panel(body: PhysicsBody3D, size: Vector3, pos: Vector3, mat: Material, coll := true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	body.add_child(mi)
	if coll:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.position = pos
		body.add_child(col)


## 乗用車を組む(長手=X方向・+Xが前)。戻り値はAnimatableBody3D(地形レイヤ=弾が当たる)
func _make_car(color: Color) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 0b1000
	body.collision_mask = 0
	var mat := _car_mat(color)
	_panel(body, Vector3(4.4, 0.74, 1.85), Vector3(0.0, 0.72, 0.0), mat)          # シャシー
	_panel(body, Vector3(2.3, 0.68, 1.7), Vector3(-0.18, 1.43, 0.0), mat)          # キャビン
	_add_tires(body, 4.4, 1.85)
	_add_car_lights(body, 4.4, 1.85, 1.0)
	# 被弾リアクション対象（エンジン=前部/タイヤ/車体。VIP車は防弾のため対象外）
	body.set_meta("prop_owner", self)
	body.set_meta("car_len", 4.4)
	_car_states[body] = {"state": "ok", "t": 0.0, "spin_rate": 0.0,
		"vel": Vector3.ZERO, "fire": null, "light": null}
	add_child(body)
	return body


func _add_tires(body: PhysicsBody3D, l: float, w: float) -> void:
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.05, 0.05, 0.06)
	tire_mat.roughness = 0.9
	for tx in [-l * 0.32, l * 0.32]:
		for tz in [-w * 0.5 + 0.12, w * 0.5 - 0.12]:
			var t := BoxMesh.new()
			t.size = Vector3(0.62, 0.62, 0.24)
			var tmi := MeshInstance3D.new()
			tmi.mesh = t
			tmi.material_override = tire_mat
			tmi.position = Vector3(tx, 0.31, tz)
			body.add_child(tmi)


## ヘッドライト(白・+X端)とテールライト(赤・-X端)。夜の街で車の向きが読める
func _add_car_lights(body: PhysicsBody3D, l: float, w: float, y: float) -> void:
	for s: float in [-1.0, 1.0]:
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var is_head: bool = s > 0.0
		lm.albedo_color = Color(1.0, 0.95, 0.8) if is_head else Color(1.0, 0.1, 0.08)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.92, 0.7) if is_head else Color(1.0, 0.06, 0.04)
		lm.emission_energy_multiplier = 2.6 if is_head else 1.8
		for zz in [-w * 0.32, w * 0.32]:
			var lb := BoxMesh.new()
			lb.size = Vector3(0.06, 0.14, 0.3)
			var lmi := MeshInstance3D.new()
			lmi.mesh = lb
			lmi.material_override = lm
			lmi.position = Vector3(s * l * 0.5, y, zz)
			body.add_child(lmi)


# ---------------------------------------------------------------- 道路まわり

## クロス通りの舗装ハイライトと交差点の街灯(車と標的が夜でも視認できる明るさ)
func _build_road_dressing() -> void:
	# 通りの明かり(既存の街路グローと同じ流儀の加算プレーン)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.72, 0.42, 0.035)
	var p := PlaneMesh.new()
	p.size = Vector2(400.0, 13.0)
	var mi := MeshInstance3D.new()
	mi.mesh = p
	mi.material_override = m
	mi.position = Vector3(0.0, 0.15, CROSS_Z)
	add_child(mi)

	# 交差点の街灯2本(VIP車の停止位置を照らす=停車中の標的の視認性を確保)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.2, 0.21, 0.24)
	for lx in [-14.0, 6.0]:
		var pole := BoxMesh.new()
		pole.size = Vector3(0.18, 6.0, 0.18)
		var pmi := MeshInstance3D.new()
		pmi.mesh = pole
		pmi.material_override = pole_mat
		pmi.position = Vector3(lx, 3.0, CROSS_Z + 7.2)
		add_child(pmi)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.82, 0.55)
		lamp.light_energy = 1.4
		lamp.omni_range = 14.0
		lamp.shadow_enabled = false
		lamp.position = Vector3(lx, 5.8, CROSS_Z + 6.4)
		add_child(lamp)


## メイン通りの路肩に停まった車(静的な添え物。弾は当たる)
func _build_parked_cars() -> void:
	var colors := [Color(0.22, 0.24, 0.3), Color(0.45, 0.42, 0.4), Color(0.18, 0.3, 0.25)]
	var zs := [-52.0, -88.0, -30.0]
	var xs := [8.5, -8.5, -8.7]
	for i in 3:
		var car := _make_car(colors[i])
		car.position = Vector3(xs[i], 0.0, zs[i])
		car.rotation.y = PI * 0.5 + (0.06 if i == 1 else -0.04)   # 縦列駐車(Z向き)


func _build_ambient_cars() -> void:
	var colors := [
		Color(0.5, 0.5, 0.55), Color(0.6, 0.55, 0.3),
		Color(0.25, 0.3, 0.5), Color(0.5, 0.25, 0.22), Color(0.3, 0.42, 0.35),
	]
	# 東行き(+X・手前車線)3台 / 西行き(-X・奥車線)2台。位置とスピードをばらす
	var setups := [
		[1.0, -180.0, 11.0], [1.0, -60.0, 12.5], [1.0, 90.0, 10.5],
		[-1.0, 140.0, 12.0], [-1.0, -20.0, 13.5],
	]
	for i in setups.size():
		var s: Array = setups[i]
		var car := _make_car(colors[i])
		var dir: float = s[0]
		car.position = Vector3(s[1], 0.0, CROSS_Z + LANE_HALF * dir)
		car.rotation.y = 0.0 if dir > 0.0 else PI
		_cars.append({"body": car, "dir": dir, "speed": s[2]})


# ---------------------------------------------------------------- VIP車

## VIP車: 黒いバン。キャビンはパネル分割で、プレイヤー側(+Z)の後部だけが
## 本当の開口。可動のスモークガラスが塞ぎ、停車中だけ下がる。
## 開口x範囲: -1.55..-0.25 / 高さ: CHASSIS_TOP..CAB_TOP(屋根の下面まで)
func _build_vip_car() -> void:
	var mat := _car_mat(Color(0.07, 0.07, 0.09))
	_vip = AnimatableBody3D.new()
	_vip.sync_to_physics = false
	_vip.collision_layer = 0b1000
	_vip.collision_mask = 0
	add_child(_vip)

	# シャシー(バンは背が高め)
	_panel(_vip, Vector3(VAN_L, CHASSIS_TOP - 0.35, VAN_W), Vector3(0.0, (0.35 + CHASSIS_TOP) * 0.5, 0.0), mat)
	_add_tires(_vip, VAN_L, VAN_W)
	_add_car_lights(_vip, VAN_L, VAN_W, 0.95)

	# キャビン(x -2.0..+1.6): 屋根・前席部(密)・後端柱・反対側(-Z)面・
	# +Z面は前席側パネルと細い柱だけ=後部窓が開口として残る
	var cy := CHASSIS_TOP + CAB_H * 0.5
	_panel(_vip, Vector3(3.6, 0.08, VAN_W * 0.94), Vector3(-0.2, CAB_TOP - 0.04, 0.0), mat)        # 屋根
	_panel(_vip, Vector3(1.85, CAB_H, VAN_W * 0.94), Vector3(0.675, cy, 0.0), mat)                  # 前席部(密)
	_panel(_vip, Vector3(0.45, CAB_H, VAN_W * 0.94), Vector3(-1.775, cy, 0.0), mat)                 # 後端の柱
	_panel(_vip, Vector3(1.3, CAB_H, 0.07), Vector3(-0.9, cy, -VAN_W * 0.47 + 0.035), mat)          # 反対側の面
	# 窓開口の下の細いドア上端(サッシ)
	_panel(_vip, Vector3(1.3, 0.12, 0.07), Vector3(-0.9, CHASSIS_TOP + 0.06, VAN_W * 0.47 - 0.035), mat)

	# 後部座席(視覚)と座席マーカー。標的の頭(座高+0.93)が窓開口の中に入る高さ
	var seat_mat := StandardMaterial3D.new()
	seat_mat.albedo_color = Color(0.12, 0.11, 0.10)
	seat_mat.roughness = 0.9
	var seat_mesh := BoxMesh.new()
	seat_mesh.size = Vector3(1.1, 0.5, 1.5)
	var smi := MeshInstance3D.new()
	smi.mesh = seat_mesh
	smi.material_override = seat_mat
	smi.position = Vector3(-0.9, CHASSIS_TOP - 0.25, 0.0)
	_vip.add_child(smi)
	# 座高0.98: 頭(+0.93)が窓開口の中に収まり、屋上からの俯角(約11°)でも
	# 屋根の縁をかすめずに頭を撃ち抜ける高さ(幾何で確認済み)
	_seat = Node3D.new()
	_seat.position = Vector3(-0.9, 0.98, 0.0)
	_vip.add_child(_seat)

	# スモークガラス(可動・コリジョン付き=閉じている間は弾を止める)
	_vip_window = AnimatableBody3D.new()
	_vip_window.sync_to_physics = false
	_vip_window.collision_layer = 0b1000
	_vip_window.collision_mask = 0
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.04, 0.05, 0.07)
	gm.metallic = 0.9
	gm.roughness = 0.12
	_panel(_vip_window, Vector3(1.3, CAB_H - 0.04, 0.05), Vector3.ZERO, gm)
	_vip_window_y0 = cy
	_vip_window.position = Vector3(-0.9, _vip_window_y0, VAN_W * 0.47)
	_vip.add_child(_vip_window)

	# 車内灯(窓が開いている間だけ点く=夜でも標的がはっきり見える)
	_vip_light = OmniLight3D.new()
	_vip_light.light_color = Color(1.0, 0.8, 0.55)
	_vip_light.light_energy = 0.0
	_vip_light.omni_range = 2.8
	_vip_light.shadow_enabled = false
	_vip_light.position = Vector3(-0.9, CAB_TOP - 0.12, 0.0)
	_vip.add_child(_vip_light)

	_vip.position = Vector3(-CAR_RANGE, 0.0, CROSS_Z + LANE_HALF)  # 東行き車線から進入


## 交差点の信号機。VIP車の停車と同期して赤/緑が替わる
func _build_signal() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.15, 0.16, 0.18)
	var pole := BoxMesh.new()
	pole.size = Vector3(0.16, 5.2, 0.16)
	var pmi := MeshInstance3D.new()
	pmi.mesh = pole
	pmi.material_override = pole_mat
	pmi.position = Vector3(VIP_STOP_X + 3.2, 2.6, CROSS_Z - 6.4)
	add_child(pmi)

	_signal_red = StandardMaterial3D.new()
	_signal_red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_signal_red.emission_enabled = true
	_signal_green = _signal_red.duplicate()
	for i in 2:
		var ball := SphereMesh.new()
		ball.radius = 0.16
		ball.height = 0.32
		var bmi := MeshInstance3D.new()
		bmi.mesh = ball
		bmi.material_override = _signal_red if i == 0 else _signal_green
		bmi.position = Vector3(VIP_STOP_X + 3.2, 5.0 - float(i) * 0.42, CROSS_Z - 6.4)
		add_child(bmi)
	_set_signal(false)


func _set_signal(green: bool) -> void:
	_signal_red.emission = Color(0.9, 0.08, 0.05) * (0.4 if green else 3.0)
	_signal_red.albedo_color = Color(0.3, 0.05, 0.04)
	_signal_green.emission = Color(0.1, 0.9, 0.3) * (3.0 if green else 0.4)
	_signal_green.albedo_color = Color(0.05, 0.3, 0.1)


# ---------------------------------------------------------------- 動き

func _physics_process(delta: float) -> void:
	# 環境カー: 等速で流れ、端まで行ったら反対端へ(遠方の暗がりで折り返す)。
	# 撃たれた車（spin/burn/wreck）は通常走行から外れて事故処理へ
	for c in _cars:
		var b: AnimatableBody3D = c.body
		if _car_states.has(b) and _car_states[b].state != "ok":
			continue
		b.position.x += c.speed * c.dir * delta
		if c.dir > 0.0 and b.position.x > CAR_RANGE:
			b.position.x = -CAR_RANGE
		elif c.dir < 0.0 and b.position.x < -CAR_RANGE:
			b.position.x = CAR_RANGE
	_update_wrecks(delta)
	_update_vip(delta)
	_sync_vip_target()


func _update_vip(delta: float) -> void:
	# 標的が撃たれたら: 車はその場に停まり続ける(窓も開いたまま=戦果が見える)
	if vip_target != null and is_instance_valid(vip_target) and not vip_target.alive:
		if _vip_state != "done":
			_vip_state = "done"
			_set_signal(true)
		return

	match _vip_state:
		"cruise":
			_vip.position.x += VIP_SPEED * delta
			if _vip.position.x >= VIP_STOP_X - BRAKE_DIST:
				_vip_state = "brake"
				_vip_speed = VIP_SPEED
		"brake":
			# 等減速で停止位置へ収める
			_vip_speed = maxf(_vip_speed - (VIP_SPEED * VIP_SPEED / (2.0 * BRAKE_DIST)) * delta, 0.6)
			_vip.position.x += _vip_speed * delta
			if _vip.position.x >= VIP_STOP_X - 0.15:
				_vip.position.x = VIP_STOP_X
				_vip_state = "stop"
				_vip_t = 0.0
		"stop":
			_vip_t += delta
			# 停車のあいだ、窓が下がってしばらく開き、発進前に閉まる
			var open_target := 0.0
			if _vip_t > WINDOW_OPEN_WAIT and _vip_t < VIP_STOP_TIME - WINDOW_SLIDE - 0.4:
				open_target = 1.0
			_window_open = move_toward(_window_open, open_target, delta / WINDOW_SLIDE)
			_apply_window()
			if _vip_t >= VIP_STOP_TIME and _window_open <= 0.0:
				_vip_state = "go"
				_set_signal(true)
		"go":
			_vip_speed = minf(_vip_speed + 7.0 * delta, VIP_SPEED)
			_vip.position.x += _vip_speed * delta
			if _vip.position.x > CAR_RANGE:
				# 反対端から再進入(ループ)。信号は赤へ戻す
				_vip.position.x = -CAR_RANGE
				_vip_speed = VIP_SPEED
				_vip_state = "cruise"
				_set_signal(false)
		_:
			pass


## 標的を座席位置へ追従させる(物理ボディの入れ子を避けるための毎フレーム同期)。
## 倒れたら追従をやめてラグドールに任せる
func _sync_vip_target() -> void:
	if vip_target == null or not is_instance_valid(vip_target):
		return
	if "alive" in vip_target and not vip_target.alive:
		return
	vip_target.global_position = _seat.global_position
	vip_target.rotation.y = -PI * 0.5   # 進行方向(+X)を向いて座る


## 窓の開き具合を見た目(ガラス位置)と車内灯へ反映
func _apply_window() -> void:
	_vip_window.position.y = _vip_window_y0 - WINDOW_TRAVEL * _window_open
	_vip_light.light_energy = 1.5 * _window_open


# ---------------------------------------------------------------- 被弾リアクション

## 弾が車に当たった（ステージが呼ぶ）。部位で反応を変える:
##   エンジン(前部) → 炎上して停止（炎・煙・ちらつく灯り）
##   タイヤ         → バーストしてスピン→壁ぎわで停止（事故）
##   車体           → 反応なし（falseを返し、既定の着弾火花に任せる）
func on_prop_shot(body: Object, point: Vector3, dir: Vector3) -> bool:
	if not (body is Node3D) or not _car_states.has(body):
		return false
	var st: Dictionary = _car_states[body]
	if st.state == "burn":
		return true   # もう燃えている（追撃は吸うだけ）
	var l: float = body.get_meta("car_len", 4.4)
	var local: Vector3 = (body as Node3D).to_local(point)
	# タイヤ: 車軸付近の低い位置・車体の側面寄り
	# （前輪はエンジン域と重なるので、タイヤを先に判定する）
	if local.y < 0.55 and absf(absf(local.x) - l * 0.32) < 0.5 and absf(local.z) > 0.55:
		_blowout(body as Node3D, st, signf(local.z), dir)
		return true
	# エンジン: 前部(+X)のボンネット高さ
	if local.x > l * 0.24 and local.y > 0.3 and local.y < 1.2:
		_ignite(body as Node3D, st)
		return true
	return false


## エンジン命中: 炎上。走行中なら惰性で流れて停まる。炎・煙・オレンジの明滅
func _ignite(body: Node3D, st: Dictionary) -> void:
	# スピン中に撃たれた場合は回転を殺して燃えるだけにする
	st.state = "burn"
	st.t = 0.0
	if st.vel == Vector3.ZERO:
		st.vel = _cruise_velocity(body)   # 走行中の惰性（駐車車はゼロ）
	if st.fire == null:
		st.fire = _make_fire(body)
		var flick := OmniLight3D.new()
		flick.light_color = Color(1.0, 0.55, 0.2)
		flick.light_energy = 2.2
		flick.omni_range = 9.0
		flick.shadow_enabled = false
		flick.position = Vector3(body.get_meta("car_len", 4.4) * 0.34, 1.3, 0.0)
		body.add_child(flick)
		st.light = flick


## タイヤ命中: バースト。パンクした側へ切れ込みながらスピンして停まる
func _blowout(body: Node3D, st: Dictionary, side: float, dir: Vector3) -> void:
	if st.state != "ok":
		return
	st.state = "spin"
	st.t = 0.0
	st.vel = _cruise_velocity(body)
	_tire_smoke(body)
	if st.vel == Vector3.ZERO:
		return   # 駐車車のタイヤはバースト煙だけ（動いていないのでスピンなし）
	# パンク側＋弾の押しでヨー回転（1.6〜2.4 rad/s をランダムに）
	st.spin_rate = side * randf_range(1.6, 2.4) * signf(st.vel.x if absf(st.vel.x) > 0.1 else 1.0)


## 走行中の車の現在速度ベクトル（_carsから引く。いなければゼロ＝駐車車）
func _cruise_velocity(body: Node3D) -> Vector3:
	for c in _cars:
		if c.body == body:
			return Vector3(c.speed * c.dir, 0.0, 0.0)
	return Vector3.ZERO


## 事故処理: spin=回りながら減速して停止 / burn=惰性で停まり燃え続ける
func _update_wrecks(delta: float) -> void:
	for body in _car_states:
		var st: Dictionary = _car_states[body]
		if st.state == "ok" or st.state == "wreck" or not is_instance_valid(body):
			continue
		st.t += delta
		var b := body as Node3D
		match st.state:
			"spin":
				# 減速(2.2 m/s^2)しつつヨー回転も減衰。止まったらwreck
				var speed: float = st.vel.length()
				speed = maxf(speed - 5.5 * delta, 0.0)
				st.vel = st.vel.normalized() * speed if speed > 0.0 else Vector3.ZERO
				b.position += st.vel * delta
				b.rotation.y += st.spin_rate * clampf(1.0 - st.t / 2.6, 0.0, 1.0) * delta
				if speed <= 0.05:
					st.state = "wreck"
			"burn":
				# 惰性で流れて停まる（燃えたまま）。ハザード的に灯りを明滅させる
				var speed2: float = st.vel.length()
				speed2 = maxf(speed2 - 7.0 * delta, 0.0)
				st.vel = st.vel.normalized() * speed2 if speed2 > 0.0 else Vector3.ZERO
				b.position += st.vel * delta
				if st.light != null:
					st.light.light_energy = 1.8 + 1.0 * sin(st.t * 17.0) * randf_range(0.7, 1.0)


## 炎＋煙のパーティクル（ボンネットから。血なし・爆発なしの「燃える車」）
func _make_fire(body: Node3D) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(body.get_meta("car_len", 4.4) * 0.34, 1.05, 0.0)
	body.add_child(root)
	# 炎（橙→赤の上昇粒）
	var fire := CPUParticles3D.new()
	fire.amount = 26
	fire.lifetime = 0.55
	fire.direction = Vector3.UP
	fire.spread = 14.0
	fire.initial_velocity_min = 2.2
	fire.initial_velocity_max = 4.2
	fire.gravity = Vector3(0, 2.0, 0)
	fire.scale_amount_min = 0.5
	fire.scale_amount_max = 1.1
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fire.emission_box_extents = Vector3(0.55, 0.08, 0.5)
	var fm := SphereMesh.new()
	fm.radius = 0.16
	fm.height = 0.32
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.55, 0.12)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.45, 0.08)
	fmat.emission_energy_multiplier = 2.4
	fm.material = fmat
	fire.mesh = fm
	root.add_child(fire)
	# 黒煙（ゆっくり大きく立ちのぼる）
	var smoke := CPUParticles3D.new()
	smoke.amount = 14
	smoke.lifetime = 2.6
	smoke.direction = Vector3.UP
	smoke.spread = 10.0
	smoke.initial_velocity_min = 1.2
	smoke.initial_velocity_max = 2.2
	smoke.gravity = Vector3(0.4, 1.4, 0)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.4
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.08, 0.08, 0.09, 0.65)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = smat
	smoke.mesh = sm
	smoke.position.y = 0.5
	root.add_child(smoke)
	return root


## タイヤバーストの白煙（一瞬）
func _tire_smoke(body: Node3D) -> void:
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.9
	p.one_shot = true
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -1.5, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	var m := SphereMesh.new()
	m.radius = 0.18
	m.height = 0.36
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.73, 0.7, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	p.position = Vector3(0.0, 0.4, 0.0)
	body.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())
