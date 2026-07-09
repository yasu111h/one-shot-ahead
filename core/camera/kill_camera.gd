class_name KillCamera
extends Camera3D
## キルカム用カメラ：弾丸の後方を追尾する

var _bullet: Node3D = null


func follow(bullet: Node3D) -> void:
	_bullet = bullet
	# 初期位置は弾のすぐ後ろへワープ
	var dir: Vector3 = bullet.velocity.normalized()
	global_position = bullet.global_position - dir * 0.8 + Vector3.UP * 0.2
	_look_along(dir, bullet.global_position)
	make_current()


func stop() -> void:
	_bullet = null


func _process(delta: float) -> void:
	if _bullet == null or not is_instance_valid(_bullet):
		return
	var dir: Vector3 = _bullet.velocity.normalized()
	var desired: Vector3 = _bullet.global_position - dir * 0.6 + Vector3.UP * 0.15
	# フレームレート非依存のlerp追従
	global_position = global_position.lerp(desired, 1.0 - pow(0.001, delta))
	_look_along(dir, _bullet.global_position)


func _look_along(dir: Vector3, bullet_pos: Vector3) -> void:
	var target := bullet_pos + dir * 5.0
	if global_position.distance_squared_to(target) < 0.0001:
		return
	if absf(dir.dot(Vector3.UP)) > 0.98:
		return  # ほぼ真上/真下はlook_at不可
	look_at(target)
