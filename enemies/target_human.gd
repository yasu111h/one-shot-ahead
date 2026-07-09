class_name TargetHuman
extends RigidBody3D
## 人型プレースホルダ標的（カプセル胴体＋球の頭）
## 通常は freeze=true の静的ボディ。命中時に物理へ切替えて倒れる

signal died(target: TargetHuman)

var alive := true
var predict_radius := 0.8       # 着弾予測用の包含球半径
var velocity_estimate := Vector3.ZERO  # 偏差予測用の推定速度

var _prev_pos := Vector3.ZERO
var _body_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D


func _ready() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 0b0010  # レイヤ2: 敵ボディ
	collision_mask = 0b0001   # 地形とだけ衝突（倒れる用）
	set_meta("target_root", self)
	set_meta("zone", "body")
	_build_body()
	_prev_pos = global_position


func _build_body() -> void:
	# 胴体コリジョン（カプセル・中心が原点）
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.5
	col.shape = capsule
	add_child(col)
	# 胴体メッシュ
	var body_mesh := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.3
	body.height = 1.5
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.42, 0.47, 0.38)  # オリーブ色の人型
	body.material = _body_mat
	body_mesh.mesh = body
	add_child(body_mesh)
	# 頭メッシュ（球）
	var head_mesh := MeshInstance3D.new()
	var head := SphereMesh.new()
	head.radius = 0.16
	head.height = 0.32
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(0.8, 0.68, 0.56)
	head.material = _head_mat
	head_mesh.mesh = head
	head_mesh.position = Vector3(0, 0.93, 0)
	add_child(head_mesh)
	# 頭ヒットボックス（Area3D・レイヤ3）
	var head_area := Area3D.new()
	head_area.collision_layer = 0b0100
	head_area.collision_mask = 0
	head_area.monitoring = false
	head_area.monitorable = true
	head_area.set_meta("target_root", self)
	head_area.set_meta("zone", "head")
	var head_col := CollisionShape3D.new()
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.2
	head_col.shape = head_shape
	head_area.add_child(head_col)
	head_area.position = Vector3(0, 0.93, 0)
	add_child(head_area)


func _physics_process(delta: float) -> void:
	if alive and delta > 0.0:
		velocity_estimate = (global_position - _prev_pos) / delta
	_prev_pos = global_position


## 命中：物理ボディへ切替えて倒す（血の表現なし）
func die(hit_impulse: Vector3) -> void:
	if not alive:
		return
	alive = false
	velocity_estimate = Vector3.ZERO
	_body_mat.albedo_color = Color(0.3, 0.3, 0.3)
	_head_mat.albedo_color = Color(0.35, 0.33, 0.3)
	_fall.call_deferred(hit_impulse)
	died.emit(self)


func _fall(hit_impulse: Vector3) -> void:
	freeze = false
	# 上体寄りに撃力を与えて倒す
	apply_impulse(hit_impulse, Vector3(0, 0.5, 0))
