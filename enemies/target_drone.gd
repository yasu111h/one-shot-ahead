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
var _light_mat: StandardMaterial3D


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


## 命中：ライト消灯・ローター停止・物理落下（きりもみ）。血なし
func die(hit_impulse: Vector3) -> void:
	if not alive:
		return
	alive = false
	velocity_estimate = Vector3.ZERO
	_light_mat.emission_enabled = false
	_light_mat.albedo_color = Color(0.2, 0.2, 0.22)
	freeze = false
	gravity_scale = 1.0
	apply_central_impulse(hit_impulse)
	apply_torque_impulse(Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3)))
	died.emit(self)
