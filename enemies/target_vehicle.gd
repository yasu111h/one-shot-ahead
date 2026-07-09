class_name TargetVehicle
extends RigidBody3D
## 走る車のプレースホルダ標的（箱）。X方向に等速で往復する

signal died(target: TargetVehicle)

var alive := true
var predict_radius := 1.8
var velocity_estimate := Vector3.ZERO
var head_offset := Vector3.ZERO  # 乗り物に頭部はない
var head_radius := 0.0
var speed := 10.0        # 走行速度 m/s
var range_x := 60.0      # 往復範囲 ±range_x

var _dir := 1.0
var _mat: StandardMaterial3D


func _ready() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 0b1000  # レイヤ4: 乗り物
	collision_mask = 0b0001
	set_meta("target_root", self)
	set_meta("part", "body")
	add_to_group("target_part")  # オートエイム対象（グループ＋meta "part" 契約）
	# コリジョン（箱）
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.5, 1.6, 2.0)
	col.shape = shape
	add_child(col)
	# メッシュ（箱）
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.5, 1.6, 2.0)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.35, 0.5, 0.7)  # スチールブルー
	box.material = _mat
	mesh.mesh = box
	add_child(mesh)


func _physics_process(delta: float) -> void:
	if not alive:
		velocity_estimate = Vector3.ZERO
		return
	velocity_estimate = Vector3(speed * _dir, 0, 0)
	global_position.x += speed * _dir * delta
	if global_position.x > range_x:
		_dir = -1.0
	elif global_position.x < -range_x:
		_dir = 1.0


## 命中：停止して物理で少し傾く
func die(hit_impulse: Vector3) -> void:
	if not alive:
		return
	alive = false
	velocity_estimate = Vector3.ZERO
	_mat.albedo_color = Color(0.25, 0.25, 0.28)
	_fall.call_deferred(hit_impulse)
	died.emit(self)


func _fall(hit_impulse: Vector3) -> void:
	freeze = false
	mass = 20.0
	apply_impulse(hit_impulse * 10.0, Vector3(0, 0.8, 0))
