class_name WindTurbine
extends Node3D
## 風力発電の風車1基。塔＋ナセル＋回転する3枚羽根。
## 羽根は AnimatableBody3D（地形レイヤ1）＝弾を止め・視線も遮る。
## 回転は物理フレームで回す＝「羽根の周期を読んで隙間に撃ち込む」が成立する
## （乱数でなく物理の周期で"読めば当たる"実力ゲーにする・実装指示書§6-2）。
##
## ドローン（TargetDrone）はこの風車の周りを周回する＝羽根が周期的に
## ドローンへの射線を塞ぐのが本ステージの「命中の窓」。

const TOWER_H := 42.0        # 塔の高さ(m)
const BLADE_LEN := 17.0      # 羽根1枚の長さ(m)

@export var spin_speed := 0.7   # 回転速度(rad/s)。基ごとに変えて周期をずらす

var _rotor: Node3D


func _ready() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.88, 0.9, 0.92)
	steel.roughness = 0.55
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.92, 0.94, 0.96)
	blade_mat.roughness = 0.5

	# 塔（下が太いテーパー円柱）。弾を止める＝StaticBody
	var tower_body := StaticBody3D.new()
	tower_body.collision_layer = 0b0001
	tower_body.collision_mask = 0
	add_child(tower_body)
	var tower := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 1.1
	tc.bottom_radius = 2.0
	tc.height = TOWER_H
	tc.material = steel
	tower.mesh = tc
	tower.position = Vector3(0, TOWER_H * 0.5, 0)
	tower_body.add_child(tower)
	var tcol := CollisionShape3D.new()
	var tshape := CylinderShape3D.new()
	tshape.radius = 1.5
	tshape.height = TOWER_H
	tcol.shape = tshape
	tcol.position = Vector3(0, TOWER_H * 0.5, 0)
	tower_body.add_child(tcol)

	# ナセル（発電機の箱）。ローターは -Z（狙撃地点側）を向く
	var nacelle := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(2.2, 2.4, 5.4)
	nb.material = steel
	nacelle.mesh = nb
	nacelle.position = Vector3(0, TOWER_H + 1.0, 0.6)
	add_child(nacelle)

	# ローター（回転軸）＝StaticBody3D 1個に羽根3枚のメッシュと当たり判定をぶら下げ、
	# ローターごと回す。弾の当たり判定はセグメントRayCastなので、回転をローターの
	# transformで表現すればレイは常に現在の羽根の位置に当たる。
	# ※ AnimatableBody3D(sync_to_physics)は「親の回転に追従しない」罠があり、
	#   羽根がワールド原点に置き去りになる不具合を起こしたため使わない
	_rotor = StaticBody3D.new()
	_rotor.collision_layer = 0b0001  # 地形扱い＝弾を止め・▼マーカーの視線も遮る
	_rotor.collision_mask = 0
	_rotor.position = Vector3(0, TOWER_H + 1.0, -2.6)
	add_child(_rotor)
	var hub := MeshInstance3D.new()
	var hb := SphereMesh.new()
	hb.radius = 0.9
	hb.height = 1.8
	hb.material = steel
	hub.mesh = hb
	_rotor.add_child(hub)
	for i in 3:
		var ang := TAU * float(i) / 3.0
		var blade := Node3D.new()
		blade.rotation.z = ang
		_rotor.add_child(blade)
		var bm := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(1.1, BLADE_LEN, 0.18)
		bb.material = blade_mat
		bm.mesh = bb
		bm.position = Vector3(0, BLADE_LEN * 0.5 + 0.8, 0)
		blade.add_child(bm)
		var bcol := CollisionShape3D.new()
		var bshape := BoxShape3D.new()
		bshape.size = Vector3(1.1, BLADE_LEN, 0.18)
		bcol.shape = bshape
		bcol.position = Vector3(0, BLADE_LEN * 0.5 + 0.8, 0)
		blade.add_child(bcol)
	# 位相を基ごとにずらす（全基が同時に開かないように）
	_rotor.rotation.z = randf() * TAU


func _physics_process(delta: float) -> void:
	# 物理フレームで回す＝AnimatableBodyの当たり判定が羽根に正しく追従する
	_rotor.rotation.z += spin_speed * delta
