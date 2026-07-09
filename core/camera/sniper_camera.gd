class_name SniperCamera
extends Node3D
## 照準リグ：ドラッグ/マウス視点・FOVズーム（スコープトグル）・息止め・手ブレ
## スコープと息止めは分離型（スコープ＝トグル、息止め＝スコープ中のみ長押し）

signal zoom_changed(stage: int)

const BASE_FOV := 70.0
const ZOOM_FOVS: Array[float] = [70.0, 17.5, 8.75]  # 通常 / 4x / 8x
const BREATH_MAX := 4.0      # 息止めゲージ（秒）
const REBOUND_TIME := 2.0    # 息切れ/解除後の手ブレ増時間（秒）

var camera: Camera3D
var zoom_stage := 0          # 0=肉眼 1=4x 2=8x
var breath_gauge := BREATH_MAX
var breath_holding := false

var _pitch_node: Node3D
var _yaw := 0.0
var _pitch := 0.0
var _rebound := 0.0
var _recoil := 0.0
var _phase := 0.0
var _noise_x := FastNoiseLite.new()
var _noise_y := FastNoiseLite.new()
var _fov_tween: Tween


func _ready() -> void:
	_pitch_node = Node3D.new()
	_pitch_node.name = "Pitch"
	add_child(_pitch_node)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = BASE_FOV
	camera.near = 0.05
	camera.far = 2000.0
	_pitch_node.add_child(camera)
	camera.make_current()
	_noise_x.seed = 1
	_noise_y.seed = 99


## ドラッグ/マウス移動による視点回転。感度はFOVに比例（ズーム中は自動で微調整化）
func add_aim_delta(rel: Vector2) -> void:
	var sens := 0.0028 * (camera.fov / BASE_FOV)
	_yaw = clampf(_yaw - rel.x * sens, deg_to_rad(-80.0), deg_to_rad(80.0))
	_pitch = clampf(_pitch - rel.y * sens, deg_to_rad(-25.0), deg_to_rad(25.0))
	rotation.y = _yaw
	_pitch_node.rotation.x = _pitch


## スコープボタン/右クリック：通常→4x→8x→通常 の巡回
func cycle_zoom() -> void:
	set_zoom_stage((zoom_stage + 1) % ZOOM_FOVS.size())


## マウスホイール用：段階を±1
func step_zoom(dir: int) -> void:
	set_zoom_stage(clampi(zoom_stage + dir, 0, ZOOM_FOVS.size() - 1))


func set_zoom_stage(stage: int) -> void:
	if stage == zoom_stage:
		return
	zoom_stage = stage
	if zoom_stage == 0 and breath_holding:
		stop_breath()  # スコープ解除で息止めも解除
	if _fov_tween:
		_fov_tween.kill()
	_fov_tween = create_tween()
	_fov_tween.tween_property(camera, "fov", ZOOM_FOVS[stage], 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	zoom_changed.emit(stage)


## 息止め開始（スコープ中のみ有効）
func start_breath() -> void:
	if breath_holding or zoom_stage == 0:
		return
	breath_holding = true


## 息止め解除。ゲージを消費していたらリバウンド（手ブレ増）
func stop_breath() -> void:
	if not breath_holding:
		return
	breath_holding = false
	if breath_gauge < BREATH_MAX * 0.95:
		_rebound = REBOUND_TIME


## 発射時の反動キック
func kick() -> void:
	_recoil += deg_to_rad(0.5)


func _process(delta: float) -> void:
	# 息止めゲージ管理
	if breath_holding:
		if breath_gauge > 0.0:
			breath_gauge = maxf(0.0, breath_gauge - delta)
			if breath_gauge == 0.0:
				_rebound = REBOUND_TIME  # 息切れ：手ブレ増リバウンド
	else:
		breath_gauge = minf(BREATH_MAX, breath_gauge + delta * 1.5)
	if _rebound > 0.0:
		_rebound = maxf(0.0, _rebound - delta)

	# 手ブレ：Perlinノイズ＋8の字ドリフト（縦は横の2倍周波数）
	var sway_scale := 1.0
	if breath_holding and breath_gauge > 0.0:
		sway_scale = 0.05  # 息止め中はほぼ停止
	elif _rebound > 0.0:
		sway_scale = 1.0 + 1.0 * (_rebound / REBOUND_TIME)
	_phase += delta * 0.8
	var amp := deg_to_rad(0.30)
	var nx := _noise_x.get_noise_1d(_phase * 40.0)
	var ny := _noise_y.get_noise_1d(_phase * 40.0)
	var sway_x := (sin(_phase * TAU * 0.35) + nx * 0.8) * amp * sway_scale
	var sway_y := (sin(_phase * TAU * 0.7) * 0.5 + ny * 0.8) * amp * sway_scale

	# 反動の減衰
	_recoil = maxf(0.0, _recoil - delta * deg_to_rad(2.0))

	camera.rotation = Vector3(sway_y + _recoil, sway_x, 0.0)
