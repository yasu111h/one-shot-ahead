class_name HordeRunner
extends TargetHuman
## C物量モード（HordeMode）の接近兵。スポーン点から防衛ラインの目標点へ
## ジグザグに駆けてくる傭兵。倒れた個体は revive() で立たせ直して再利用する
## （オブジェクトプール＝同時多数でもノードを増やし続けない）。
##
## 移動は freeze=true のまま global_position を直接進める方式（Path3D歩行標的と同じ思想）。
## TargetHuman._physics_process が移動後の位置から velocity_estimate を出すので、
## 着弾予測（リード撃ち）はそのまま効く。

var run_speed := 5.0      # 前進速度(m/s)
var weave_amp := 2.0      # ジグザグの横振れ速度成分(m/s)。0で直進
var weave_freq := 0.55    # ジグザグの周期(Hz)
var goal := Vector3.ZERO  # 防衛ライン上の目標点
var advancing := false    # trueの間だけ前進する

var _weave_phase := 0.0


func _init() -> void:
	_weave_phase = randf() * TAU


func _physics_process(delta: float) -> void:
	if advancing and alive and freeze:
		var flat := goal - global_position
		flat.y = 0.0
		if flat.length() > 0.5:
			var dir := flat.normalized()
			var side := dir.cross(Vector3.UP)
			_weave_phase += TAU * weave_freq * delta
			var vel := dir * run_speed + side * (sin(_weave_phase) * weave_amp)
			global_position += vel * delta
	super(delta)


## プール再利用：倒れた個体を指定位置に立たせ直す。
## ラグドール状態の解除（freeze復帰）は物理ステップ外で行う必要があるため遅延実行
func revive(pos: Vector3) -> void:
	alive = true
	advancing = false
	velocity_estimate = Vector3.ZERO
	_weave_phase = randf() * TAU
	# 死亡でグレーに沈めた全身マテリアルを敵の赤へ戻す。
	# ※ TargetHumanがVRM化され旧 _body_mat/_head_mat は廃止され _mats 配列に統一された。
	#   これを参照したままだったためHordeRunnerがコンパイルできず、C物量モードで
	#   敵が1体も湧かない＝敵0体として即CLEARになるバグの原因だった（2026-07-12修正）。
	for m in _mats:
		m.albedo_color = Color(0.62, 0.10, 0.09)
	# 死亡アニメ(Shot/停止)を待機へ戻す（前進を始めれば基底が自動でWalkへ切り替える）
	if _ap != null and _ap.has_animation("Idle"):
		_ap.play("Idle", 0.1)
	can_sleep = true
	_stand_at.call_deferred(pos)


func _stand_at(pos: Vector3) -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis.IDENTITY, pos)
	_prev_pos = pos
