class_name SlowMotionDirector
extends Node
## キルカムのスローモーション制御（time_scale＋弾丸追尾カメラの切替/復帰）

signal killcam_finished

const SLOW_SCALE := 0.15

var kill_camera: KillCamera
var main_camera: Camera3D
var active := false


## 命中確定弾の発射直後に呼ぶ
func start_killcam(bullet: Node3D) -> void:
	if active:
		return
	active = true
	Engine.time_scale = SLOW_SCALE
	Engine.physics_ticks_per_second = 240  # スロー中も物理の粒度を維持
	kill_camera.follow(bullet)


## キルカム終了：通常速度・通常カメラへ復帰
func end_killcam() -> void:
	if not active:
		return
	active = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	kill_camera.stop()
	if main_camera:
		main_camera.make_current()
	killcam_finished.emit()
