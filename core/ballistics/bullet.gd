class_name Bullet
extends Node3D
## 弾丸：Node3D＋毎フレーム自前積分。
## 前フレーム→現フレームのセグメントRayCastで当たり判定（すり抜け防止）

signal hit(result: Dictionary)  # 何かに命中（intersect_rayの結果を渡す）
signal vanished                 # 何にも当たらず寿命切れ

const HIT_MASK := 0b1111  # 地形1 + ボディ2 + ヘッド4 + 乗り物8
const LIFETIME := 5.0

var velocity := Vector3.ZERO
var wind_accel := Vector3.ZERO

var _age := 0.0
var _done := false
# 見た目は持たない（トレーサー＝ShotFxが実弾位置に追従して光の筋を描く）


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	var prev := global_position
	var r := Ballistics.step(prev, velocity, wind_accel, delta)
	var next: Vector3 = r[0]
	velocity = r[1]
	# 移動区間をレイで判定（高速弾のトンネリング防止）
	var query := PhysicsRayQueryParameters3D.create(prev, next, HIT_MASK)
	query.collide_with_areas = true  # ヘッドショット判定のArea3Dも拾う
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		_done = true
		global_position = result.position
		hit.emit(result)
		queue_free()
		return
	global_position = next
	if _age > LIFETIME or global_position.y < -10.0:
		_done = true
		vanished.emit()
		queue_free()
