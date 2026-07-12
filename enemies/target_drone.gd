class_name TargetDrone
extends RigidBody3D
## 飛行ドローン標的（クアッドコプター）。TargetHumanと同じ「標的の契約」を満たす：
##   hostile / alive / predict_radius / head_offset / head_radius / velocity_estimate
##   / die(impulse) / meta "target_root"・"part" / グループ "target_part"
## なので、着弾予測（リード撃ち）・照準減速・▼マーカー・バレットカムがそのまま効く。
##
## hostile=true …… 赤い攻撃ドローン（撃つべき標的。赤いライトが目印）
## hostile=false …… 白い点検ドローン（民間。撃てば即ミッション失敗）
##
## 移動は freeze=true のまま anchor（周回中心）の周りを楕円軌道＋上下ゆらぎで飛ぶ。
## 直前フレームとの差分から velocity_estimate を出す＝偏差予測はそのまま効く。
## 命中すると freeze を解いて物理落下（ローター停止・ライト消灯・きりもみ）。血なし。

signal died(drone: TargetDrone)

var hostile := true
var alive := true
var predict_radius := 0.8        # 着弾予測用の包含球半径（機体全幅~1.6m）
var velocity_estimate := Vector3.ZERO
var head_offset := Vector3.ZERO  # 頭部なし
var head_radius := 0.0

# --- 飛行パターン（ステージが配置時に設定する） ---
var anchor := Vector3.ZERO       # 周回の中心（ワールド座標・高度込み）
var orbit_radius := 12.0         # 周回半径(m)
var orbit_speed := 0.5           # 周回の角速度(rad/s)。負で逆回り
var bob_amp := 2.0               # 上下ゆらぎの振幅(m)
var phase := 0.0                 # 周回位相（配置時にランダムを入れると散らばる）

var _prev_pos := Vector3.ZERO
var _rotor_hubs: Array[Node3D] = []
var _arms: Array[Node3D] = []          # 4本アーム（撃墜時に折れて破片になる）
var _light_mat: StandardMaterial3D
var _body_color := Color(0.16, 0.17, 0.2)  # 機体色（破片の色に流用）


func _ready() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 0b0010  # レイヤ2: 敵ボディ（弾・測距レイが当たる）
	collision_mask = 0b0001   # 地形とだけ衝突（撃墜されて落ちる用）
	set_meta("target_root", self)
	set_meta("part", "body")
	add_to_group("target_part")  # 照準減速の対象（グループ＋meta "part" 契約）
	_build_body()
	_prev_pos = global_position


func _build_body() -> void:
	# 当たり判定（機体中心の球）
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	col.shape = sphere
	add_child(col)

	var body_col := Color(0.16, 0.17, 0.2) if hostile else Color(0.88, 0.9, 0.92)
	_body_color = body_col
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body_col
	body_mat.roughness = 0.6

	# 中央ボディ
	var core := MeshInstance3D.new()
	var core_box := BoxMesh.new()
	core_box.size = Vector3(0.55, 0.22, 0.55)
	core_box.material = body_mat
	core.mesh = core_box
	add_child(core)

	# ライト（機体下面の発光体。赤=攻撃ドローン／白=点検ドローン。
	# 遠距離での視認はこの光と▼マーカーが担う）
	_light_mat = StandardMaterial3D.new()
	var lc := Color(1.0, 0.16, 0.1) if hostile else Color(1.0, 1.0, 0.95)
	_light_mat.albedo_color = lc
	_light_mat.emission_enabled = true
	_light_mat.emission = lc
	_light_mat.emission_energy_multiplier = 6.0
	var light := MeshInstance3D.new()
	var light_box := BoxMesh.new()
	light_box.size = Vector3(0.3, 0.12, 0.3)
	light_box.material = _light_mat
	light.mesh = light_box
	light.position = Vector3(0, -0.16, 0)
	add_child(light)

	# 4本アーム＋ローター（薄い円盤＝回転ブレの表現）
	var arm_mat := StandardMaterial3D.new()
	arm_mat.albedo_color = body_col.darkened(0.2)
	var rotor_mat := StandardMaterial3D.new()
	rotor_mat.albedo_color = Color(0.1, 0.1, 0.12, 0.55)
	rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 4:
		var ang := TAU * (float(i) + 0.5) / 4.0
		var dir := Vector3(cos(ang), 0, sin(ang))
		var arm := MeshInstance3D.new()
		var arm_box := BoxMesh.new()
		arm_box.size = Vector3(0.62, 0.06, 0.09)
		arm_box.material = arm_mat
		arm.mesh = arm_box
		arm.position = dir * 0.45
		arm.rotation.y = -ang
		add_child(arm)
		_arms.append(arm)
		# ローター円盤（見た目のみ）。hubを回してブレードの明滅感を出す
		var hub := Node3D.new()
		hub.position = dir * 0.72 + Vector3(0, 0.08, 0)
		add_child(hub)
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 0.02
		cyl.material = rotor_mat
		disc.mesh = cyl
		hub.add_child(disc)
		var blade := MeshInstance3D.new()
		var blade_box := BoxMesh.new()
		blade_box.size = Vector3(0.58, 0.03, 0.07)
		blade_box.material = arm_mat
		blade.mesh = blade_box
		hub.add_child(blade)
		_rotor_hubs.append(hub)


func _physics_process(delta: float) -> void:
	if alive and freeze:
		# 周回＋上下ゆらぎ。速度は orbit_speed×orbit_radius ＝リードの手応えを作る
		phase += orbit_speed * delta
		var p := anchor + Vector3(
			cos(phase) * orbit_radius,
			sin(phase * 2.3) * bob_amp,
			sin(phase) * orbit_radius)
		# 進行方向へ機首を向ける（見た目のみ）
		var vel := p - global_position
		global_position = p
		if vel.length() > 0.001:
			rotation.y = atan2(-vel.x, -vel.z)
	if delta > 0.0:
		velocity_estimate = (global_position - _prev_pos) / delta
	_prev_pos = global_position


func _process(delta: float) -> void:
	# ローター回転（見た目のみ・毎フレーム）
	if alive:
		for hub in _rotor_hubs:
			hub.rotate_y(38.0 * delta)


## 命中：機体が割れる。①4本アームが折れて破片になり飛散、②本体チャンク（コア）が
## きりもみ落下、③着弾フラッシュ＋火花。破片・本体とも物理で落下する（血なし）。
## ドローンは撃墜時リプレイのスロー中に死ぬので、割れて散る様子がよく見える。
func die(hit_impulse: Vector3) -> void:
	if not alive:
		return
	alive = false
	velocity_estimate = Vector3.ZERO
	_light_mat.emission_enabled = false
	_light_mat.albedo_color = Color(0.2, 0.2, 0.22)
	var center := global_position
	var parent := get_parent()
	# 着弾フラッシュ＋火花（機体色の破片が飛ぶ手前で一瞬光る）
	if parent != null:
		_spawn_flash(parent, center)
		_spawn_sparks(parent, center)
	# ①アームを破片として切り離す（見た目のアームは隠し、独立した物理片を飛ばす）
	if parent != null:
		for a in _arms:
			var wpos: Vector3 = a.global_position
			var out := (wpos - center)
			out.y = 0.0
			out = (out.normalized() + Vector3(0, 0.7, 0)).normalized()
			a.visible = false
			_spawn_fragment(parent, wpos, out * randf_range(3.0, 5.5) + hit_impulse * 0.25)
	for h in _rotor_hubs:
		h.visible = false
	# ②本体チャンク（コア＋ライト）はきりもみ落下
	freeze = false
	gravity_scale = 1.0
	apply_central_impulse(hit_impulse * 0.6 + Vector3(0, 1.5, 0))
	apply_torque_impulse(Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)))
	died.emit(self)


## アーム破片（小箱＋ローター円盤の1片）。独立したRigidBodyとして飛散・落下する
func _spawn_fragment(parent: Node, wpos: Vector3, impulse: Vector3) -> void:
	var frag := RigidBody3D.new()
	frag.collision_layer = 0
	frag.collision_mask = 0b0001  # 地形にだけ当たって落ちる（弾・他の破片とは干渉しない）
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _body_color.darkened(0.15)
	mat.roughness = 0.7
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.06, 0.09)
	box.material = mat
	mesh.mesh = box
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frag.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.1, 0.14)
	col.shape = shape
	frag.add_child(col)
	parent.add_child(frag)
	frag.global_position = wpos
	frag.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	frag.apply_central_impulse(impulse)
	frag.apply_torque_impulse(Vector3(
		randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8)))
	# 後片付け（実時間で確実に消す＝スロー再生に引きずられない）
	frag.get_tree().create_timer(6.0, true, false, true).timeout.connect(frag.queue_free)


## 着弾フラッシュ（一瞬の発光球。すぐ縮んで消える）
func _spawn_flash(parent: Node, wpos: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.45)
	mat.emission_energy_multiplier = 8.0
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.2
	sphere.material = mat
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = wpos
	# スロー再生でも実時間で縮めて消す（Tweenをタイムスケール無視で回す）
	var tw := mesh.create_tween().set_ignore_time_scale(true)
	tw.tween_property(mesh, "scale", Vector3(0.3, 0.3, 0.3), 0.14)
	tw.tween_callback(mesh.queue_free)


## 撃墜の火花（オレンジの粒が四方へ・one-shot）
func _spawn_sparks(parent: Node, wpos: Vector3) -> void:
	var p := CPUParticles3D.new()
	parent.add_child(p)
	p.global_position = wpos
	p.emitting = true
	p.one_shot = true
	p.amount = 20
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 11.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.7, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.25)
	mat.emission_energy_multiplier = 4.0
	mesh.material = mat
	p.mesh = mesh
	p.get_tree().create_timer(2.0, true, false, true).timeout.connect(p.queue_free)
