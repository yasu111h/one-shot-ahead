class_name EnemyShooter
extends Node3D
## Bモード「応戦」の敵の行動。既存の TargetHuman を1体参照し、
## 「カバー撃ち（遮蔽から周期的に顔を出して撃つ）」を与える。
## モード（EngageMode）が悪人1体につき1つ生成し、ステージに add_child する。
##
## 撃てる窓の作り方は2通り：
##  - use_cover=true（静止標的）：この敵の手前に低い遮蔽ブロックを立て、周期で標的を
##    その裏に沈める／出す。出ている一瞬だけプレイヤーは撃てる＝もぐら叩き狙撃。
##  - use_cover=false（歩行標的など既に動く敵）：遮蔽は作らず、ステージ既存のギミック
##    （都市の窓・埠頭のコンテナ隙間）が撃てる窓になる。見えている間だけ撃ってくる。
##
## 射撃は実弾を飛ばさず、露出中盤にマズルフラッシュ＋確率ロールで「プレイヤーに当たったか」を
## 決める（accuracy はモードが位置特定ゲージに応じて毎フレーム更新する）。命中したら
## on_player_hit を呼ぶ。プレイヤーは露出中に敵を撃てば発砲前に黙らせられる。

var stage: SniperStage
var target: TargetHuman
var on_player_hit := Callable()
var use_cover := false
var accuracy := 0.2          # 0..1。EngageMode が位置特定ゲージから毎フレーム更新

const HIDE_DEPTH := 1.7      # 遮蔽の裏へ沈める深さ(m)
const EXPOSED_FRAC := 0.42   # 1サイクルのうち顔を出している割合
const MOVE_FRAC := 0.14      # 沈む／せり上がるのにかける割合(残りは静止)
const AIM_FRAC := 0.55       # 露出時間のどこで発砲するか(0=出た瞬間 1=引っ込む直前)

var _base_pos := Vector3.ZERO
var _period := 3.0
var _phase := 0.0            # 0..1 のサイクル位相
var _cover: StaticBody3D
var _fired_this_window := false


## モードが標的配置後に呼ぶ。位相と周期を敵ごとにばらして単調さを避ける
func begin() -> void:
	if not is_instance_valid(target):
		return
	_base_pos = target.global_position
	_period = randf_range(2.6, 4.0)
	_phase = randf()  # 出るタイミングを敵ごとにずらす
	if use_cover:
		_build_cover()


## 標的の手前(プレイヤー方向)に低い遮蔽ブロックを立てる。地形レイヤ＝弾はここで止まる
func _build_cover() -> void:
	if stage == null or stage.rig == null:
		return
	var to_rig := stage.rig.global_position - _base_pos
	to_rig.y = 0.0
	if to_rig.length() < 0.01:
		to_rig = Vector3.FORWARD
	to_rig = to_rig.normalized()
	_cover = StaticBody3D.new()
	_cover.collision_layer = 0b0001  # 地形レイヤ
	_cover.collision_mask = 0
	stage.add_child(_cover)
	# 壁は標的と同じ高さ中心・低め。露出時は頭(base+0.93)が壁上端(base+0.7)より上に
	# 出て撃ち合える／沈むと頭が壁下へ隠れる。高すぎると露出時も敵自身の射線を塞ぐ
	_cover.global_position = _base_pos + to_rig * 1.1
	var size := Vector3(2.4, 1.4, 0.4)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.19, 0.22)
	mat.roughness = 0.9
	mi.material_override = mat
	_cover.add_child(mi)
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	col.shape = bx
	_cover.add_child(col)
	# 壁の-Zを標的方向へ＝幅(X)が射線に対して横に張る（同じ高さなので水平に向く）
	_cover.look_at(_base_pos, Vector3.UP)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	if not target.alive:
		# 倒したら射撃も上下動も止める（ラグドールは自由落下）
		return
	if use_cover:
		_update_cover_motion(delta)
	else:
		# 動く敵：露出＝プレイヤーから視線が通ること。周期で発砲権をリセット
		_phase += delta / _period
		if _phase >= 1.0:
			_phase -= 1.0
			_fired_this_window = false
	_try_fire()


## 遮蔽の裏へ沈める／せり上がらせる。位相で「隠れ→出現→露出→退避→隠れ」を作る
func _update_cover_motion(delta: float) -> void:
	_phase += delta / _period
	if _phase >= 1.0:
		_phase -= 1.0
		_fired_this_window = false
	# 露出プロファイル e(0..1)：0=完全に隠れ 1=完全露出
	var e := 0.0
	if _phase < MOVE_FRAC:
		e = _phase / MOVE_FRAC                       # せり上がる
	elif _phase < MOVE_FRAC + EXPOSED_FRAC:
		e = 1.0                                       # 露出キープ
	elif _phase < 2.0 * MOVE_FRAC + EXPOSED_FRAC:
		e = 1.0 - (_phase - MOVE_FRAC - EXPOSED_FRAC) / MOVE_FRAC  # 沈む
	else:
		e = 0.0                                       # 隠れキープ
	target.global_position = _base_pos - Vector3(0, HIDE_DEPTH * (1.0 - e), 0)


## いま露出しており視線が通るなら、露出中盤で1回だけ発砲する
func _try_fire() -> void:
	if _fired_this_window or not is_instance_valid(stage):
		return
	# 露出しているか：カバー敵は位相で、動く敵は「顔を出す時間帯か」で判定
	var window_open := false
	if use_cover:
		var win_start := MOVE_FRAC * AIM_FRAC
		window_open = _phase >= MOVE_FRAC + EXPOSED_FRAC * AIM_FRAC and \
			_phase < MOVE_FRAC + EXPOSED_FRAC
		# 実際に頭が壁の上に出ているかも確認（沈みきりでは撃たない）
		if window_open and target.global_position.y < _base_pos.y - HIDE_DEPTH * 0.4:
			window_open = false
	else:
		window_open = _phase >= AIM_FRAC and _phase < AIM_FRAC + 0.12
	if not window_open:
		return
	# プレイヤーへの視線が通らなければ撃てない（壁・建物の陰なら見送り）
	var muzzle := target.global_position + Vector3(0, 0.93, 0)
	if not stage.has_line_of_sight(muzzle):
		return
	_fired_this_window = true
	_fire_at_player(muzzle)


## 発砲：マズルフラッシュ＋発射音に加え、プレイヤー方向へ「白いトレーサー付きの実弾」を
## 飛ばす（プレイヤーの弾と同じ ShotFx.attach_tracer＝敵の弾道が目で見える）。
## 命中は accuracy ロールで先に決め、外れ弾は照準点をカメラの脇へ逸らす＝
## 「白い筋が掠めて抜けていく」のが見える。被弾の適用は弾がこちらへ届く瞬間に合わせる
func _fire_at_player(muzzle: Vector3) -> void:
	if stage.fx != null:
		stage.fx.muzzle_flash(muzzle)
	if stage.sfx != null:
		stage.sfx.play_shot()
	var will_hit := randf() < accuracy
	var aim: Vector3 = stage.rig.camera.global_position
	if not will_hit:
		# 外れ弾：カメラの横・上下へランダムに逸らす（近くを通るほど緊張感が出る）
		var side := (aim - muzzle).cross(Vector3.UP).normalized()
		aim += side * randf_range(1.2, 2.8) * (1.0 if randf() < 0.5 else -1.0) \
			+ Vector3(0.0, randf_range(-0.6, 1.5), 0.0)
	var dir := (aim - muzzle).normalized()
	# 演出弾：勝敗カウンタ（bullets_in_flight等）には一切触れない。
	# プレイヤーに当たり判定はないので弾はカメラ脇を抜け、背後の壁で火花が散る。
	# 弾速はプレイヤーの弾（stage.muzzle_speed）に合わせる＝トレーサーの見え方が揃う
	var speed: float = stage.muzzle_speed
	var bullet := Bullet.new()
	stage.add_child(bullet)
	bullet.global_position = muzzle + dir * 0.8
	bullet.velocity = dir * speed
	bullet.hit.connect(func(result: Dictionary) -> void:
		if is_instance_valid(stage) and stage.fx != null:
			stage.fx.impact_burst(result.position, result.get("normal", Vector3.UP)))
	if stage.fx != null:
		stage.fx.attach_tracer(bullet)
	# 被弾判定は「弾がこちらへ届く瞬間」に遅らせる（弾速連動・time_scale連動タイマー）
	if will_hit and on_player_hit.is_valid():
		var flight := muzzle.distance_to(aim) / speed
		stage.get_tree().create_timer(flight).timeout.connect(func() -> void:
			if is_instance_valid(stage) and not stage.game_over and on_player_hit.is_valid():
				on_player_hit.call())
