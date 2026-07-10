class_name Bullet
extends Node3D
## 弾丸：Node3D＋毎フレーム自前積分。
## 前フレーム→現フレームのセグメントRayCastで当たり判定（すり抜け防止）

signal hit(result: Dictionary)  # 何かに命中（intersect_rayの結果を渡す）
signal vanished                 # 何にも当たらず寿命切れ
signal glass_hit(result: Dictionary, dir: Vector3)  # ガラス通過（弾は止まらず割るだけ）

const HIT_MASK := 0b1111    # 地形1 + ボディ2 + ヘッド4 + 乗り物8
const GLASS_MASK := 0b10000  # ガラス5（HIT_MASK外＝弾を止めない。通過検知だけする）
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
	# 停止点(命中点 or 区間の終端)までに通過したガラスを割る(弾は止まらない)
	_check_glass(prev, result.position if result else next)
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


## 区間内のガラス(レイヤ5)を検知して通知する。1フレームで複数枚を貫くこともある
func _check_glass(from: Vector3, to: Vector3) -> void:
	var vdir := velocity.normalized()
	var pos := from
	for i in 3:
		var query := PhysicsRayQueryParameters3D.create(pos, to, GLASS_MASK)
		query.collide_with_areas = true
		var g := get_world_3d().direct_space_state.intersect_ray(query)
		if g.is_empty():
			return
		glass_hit.emit(g, vdir)
		pos = g.position + vdir * 0.1  # 同じ板を二重検知しないよう少し先へ進めて再走査
