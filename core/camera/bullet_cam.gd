class_name BulletCam
extends Node
## 弾道リプレイ(バレットカム)。発射→着弾までスローモーションで
## 弾を追いかけるシネマ映像として見せる（TABIJIのbullet_cam.gdを移植）。
## 弾道は発射時の事前予測で確定済みなので「録画」は不要で、
## 確定した弾道(発射点→着弾点)をスロー演出で再生し直す方式。
## 命中確定弾のほか、ミス弾（設定ON時）の地面着弾点までの見送りにも使う。
##
## 使い方: play(発射点, 着弾点, 着弾時に呼ぶCallable)
##   ・着弾時Callableの中でダメージ適用と距離スタンプ表示を行う(=リプレイの瞬間に効果が出る)
##   ・スロー中の着弾FXは出さない(速度違和感になる)
##   ・再生中は active が true。終了で finished シグナル。

signal finished

const SLOWMO := 0.08           # リプレイ中の世界の時間倍率(スロー度合い)
const HOLD_SLOWMO := 0.20      # 着弾後の余韻中は少しだけ時間を進める(標的が倒れるのが見える)
const FLIGHT_TIME := 1.5       # 発射→着弾の体感時間(実時間・秒)。等速再生・減速演出なし
const IMPACT_HOLD := 0.7       # 着弾後の余韻(実時間・秒)
const CAM_BACK := 1.3          # 弾の後方距離(実弾は小さいので近めに寄る)
const CAM_SIDE := 0.5          # 弾の横オフセット
const CAM_UP := 0.28           # 弾の上オフセット
const SWEEP_RAD := 0.9         # 飛翔中にカメラが弾の周りを回り込む角度(rad)
const SPIN_RATE := 24.0        # 弾のライフリング回転(rad/s・実時間)
const BAR_RATIO := 0.11        # レターボックス黒帯1本の高さ(画面比)

var active := false

var _cam: Camera3D
var _prev_cam: Camera3D = null
var _bolt: Node3D
var _bars: CanvasLayer
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _dir := Vector3.FORWARD
var _t := 0.0                  # 飛翔の進行(0..1)
var _spin := 0.0               # ライフリング回転の累積角(rad)
var _hold := 0.0
var _phase := 0                # 0=待機 1=飛翔 2=着弾余韻
var _on_impact := Callable()


func _ready() -> void:
	# シネマ用カメラ(通常は非アクティブ)。長距離狙撃なので遠くまで描く
	_cam = Camera3D.new()
	_cam.top_level = true
	_cam.far = 2000.0
	add_child(_cam)

	# リプレイ用の実弾(黒い金属の弾丸。胴体+先端の尖り。-Z方向が進行方向)
	_bolt = Node3D.new()
	_bolt.top_level = true
	_bolt.visible = false
	add_child(_bolt)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.07, 0.07, 0.08)   # ほぼ黒のガンメタル
	metal.metallic = 0.9
	metal.roughness = 0.35
	# 胴体(円筒)。シネマ用に実弾よりやや大きめに作って視認できるようにする
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.021
	bm.bottom_radius = 0.021
	bm.height = 0.085
	body.mesh = bm
	body.material_override = metal
	body.rotation_degrees.x = -90.0   # Y軸円筒を-Z(進行方向)へ向ける
	body.position.z = 0.045
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.add_child(body)
	# 先端(細くなる弾頭)
	var nose := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.002
	nm.bottom_radius = 0.021
	nm.height = 0.075
	nose.mesh = nm
	nose.material_override = metal
	nose.rotation_degrees.x = -90.0
	nose.position.z = -0.035
	nose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.add_child(nose)

	# レターボックス(上下の黒帯。映画的な区切り)
	_bars = CanvasLayer.new()
	_bars.layer = 95
	_bars.visible = false
	add_child(_bars)
	for top in [true, false]:
		var r := ColorRect.new()
		r.color = Color(0, 0, 0, 0.92)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if top:
			r.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			r.anchor_bottom = BAR_RATIO
		else:
			r.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			r.anchor_top = 1.0 - BAR_RATIO
		_bars.add_child(r)


## リプレイ開始。from→to の弾道をスローで再生し、着弾の瞬間に on_impact を呼ぶ。
func play(from: Vector3, to: Vector3, on_impact: Callable = Callable()) -> void:
	if active:
		return
	var seg := to - from
	if seg.length() < 1.0:
		if on_impact.is_valid():
			on_impact.call()
		return
	active = true
	_from = from
	_to = to
	_dir = seg.normalized()
	_on_impact = on_impact
	_t = 0.0
	_spin = 0.0
	_phase = 1

	_prev_cam = get_viewport().get_camera_3d()
	Engine.time_scale = SLOWMO
	_bars.visible = true
	_bolt.visible = true
	_place(0.0)
	_cam.current = true


func _process(delta: float) -> void:
	if not active:
		return
	# Engine.time_scaleの影響を打ち消して「実時間」で演出を進める
	var real_dt := delta / maxf(Engine.time_scale, 0.0001)

	if _phase == 1:
		_t += real_dt / FLIGHT_TIME
		if _t >= 1.0:
			# 着弾: この瞬間にダメージが入る(着弾FXはスロー中の速度違和感になるので出さない)
			_bolt.visible = false
			if _on_impact.is_valid():
				_on_impact.call()
			Engine.time_scale = HOLD_SLOWMO   # 余韻: 標的が倒れるのが少し動いて見える
			_phase = 2
			_hold = IMPACT_HOLD
		else:
			# 現実の弾道をスロー再生した見え方=等速。減速演出はしない
			_spin += SPIN_RATE * real_dt   # ライフリング回転(累積)
			_place(clampf(_t, 0.0, 1.0))
	elif _phase == 2:
		_hold -= real_dt
		# 着弾点をゆっくり見つめたままわずかに引く
		_cam.global_position += -_dir * real_dt * 0.6
		_look_impact()
		if _hold <= 0.0:
			_finish()


## 進行度(0..1)に応じて弾とカメラを配置する。弾道は直線(from.lerp(to,t))
func _place(te: float) -> void:
	var pos := _from.lerp(_to, te)
	_bolt.global_position = pos
	var up := Vector3.UP if absf(_dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	_bolt.look_at(pos + _dir, up)
	_bolt.rotate_object_local(Vector3.FORWARD, _spin)   # look_at後に累積回転を乗せる

	# カメラ: 弾の斜め後ろから追走し、飛翔中に弾の周りをゆっくり回り込む
	var side := _dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var base := -_dir * CAM_BACK + side * CAM_SIDE + Vector3.UP * CAM_UP
	var offset := base.rotated(_dir, lerpf(-SWEEP_RAD * 0.3, SWEEP_RAD, te))
	_cam.global_position = pos + offset
	_cam.look_at(pos + _dir * 2.0, Vector3.UP)


func _look_impact() -> void:
	var up := Vector3.UP if absf(_dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	_cam.look_at(_to, up)


func _finish() -> void:
	Engine.time_scale = 1.0
	_bars.visible = false
	_bolt.visible = false
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.current = true
	_prev_cam = null
	_phase = 0
	active = false
	finished.emit()


## 中断(リトライ・シーン切替など)。時間とカメラを必ず正常へ戻す
func abort() -> void:
	if not active:
		return
	_finish()


func _exit_tree() -> void:
	# シーン切替でノードごと消える場合も時間倍率だけは必ず戻す
	if active:
		Engine.time_scale = 1.0
