class_name SniperCamera
extends Node3D
## 照準リグ：ドラッグ視点（キャプチャなし）・スコープFOVスムーズ遷移・息止め・手ブレ・リコイル
## スコープ遷移はTABIJIの _aim_blend 方式（move_toward 6.0/s）でFOVをなめらかに補間する。
## スコープと息止めは分離型（スコープ＝トグル、息止め＝スコープ中のみ長押し）

signal zoom_changed(stage: int)

const BASE_FOV := 75.0                          # 肉眼FOV
const SCOPE_FOVS: Array[float] = [18.75, 9.375] # 4x / 8x（75/倍率）
const BREATH_MAX := 4.0      # 息止めゲージ（秒）
const REBOUND_TIME := 2.0    # 息切れ/解除後の手ブレ増時間（秒）
const AIM_BLEND_SPEED := 6.0 # スコープ遷移速度（TABIJI準拠 6.0/s）

@export var base_sens := 0.005          # 視点感度(rad/px)。FOV比例で自動微調整
@export var scope_sens_mult := 0.55     # スコープ中の感度倍率（TABIJI準拠）
@export var recoil_kick := 0.011        # 1発ごとのピッチ跳ね上がり(rad・TABIJI準拠)
@export var recoil_max := 0.055         # リコイルの上限(rad)
@export var recoil_recover := 9.0       # リコイルの戻り速さ(1/s・exp減衰)
@export var recoil_scoped_mult := 0.55  # スコープ中のリコイル倍率

var camera: Camera3D
var zoom_stage := 0          # 0=肉眼 1=4x 2=8x
var breath_gauge := BREATH_MAX
var breath_holding := false
var aim_blend := 0.0         # 肉眼0⇄スコープ1のなめらかな遷移値

var _pitch_node: Node3D
var _yaw := 0.0
var _pitch := 0.0
var _scope_fov: float = SCOPE_FOVS[0]  # スコープ側の現在FOV（4x⇄8x切替もなめらかに）
var _rebound := 0.0
var _recoil := 0.0
var _phase := 0.0
var _noise_x := FastNoiseLite.new()
var _noise_y := FastNoiseLite.new()


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


## ドラッグによる視点回転。感度はFOVに比例＋スコープ中は×0.55（TABIJI準拠）
func add_aim_delta(rel: Vector2) -> void:
	var sens := base_sens * lerpf(1.0, scope_sens_mult, aim_blend) * (camera.fov / BASE_FOV)
	_yaw = clampf(_yaw - rel.x * sens, deg_to_rad(-80.0), deg_to_rad(80.0))
	_pitch = clampf(_pitch - rel.y * sens, deg_to_rad(-25.0), deg_to_rad(25.0))
	rotation.y = _yaw
	_pitch_node.rotation.x = _pitch


## スコープボタン/Qキー：肉眼→4x→8x→肉眼 の巡回（スコープ中の再タップで段階切替）
func cycle_zoom() -> void:
	set_zoom_stage((zoom_stage + 1) % 3)


## マウスホイール用：段階を±1
func step_zoom(dir: int) -> void:
	set_zoom_stage(clampi(zoom_stage + dir, 0, 2))


func set_zoom_stage(stage: int) -> void:
	if stage == zoom_stage:
		return
	zoom_stage = stage
	if zoom_stage == 0 and breath_holding:
		stop_breath()  # スコープ解除で息止めも解除
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


## 発射時の反動キック（TABIJI準拠：ピッチ跳ね＋左右微ぶれ）
func kick() -> void:
	_recoil = minf(_recoil + recoil_kick * lerpf(1.0, recoil_scoped_mult, aim_blend), recoil_max)
	_yaw += randf_range(-0.0018, 0.0018)
	rotation.y = _yaw


func _process(delta: float) -> void:
	# スコープ遷移（_aim_blend方式）。FOVは肉眼⇄スコープをなめらかに補間
	aim_blend = move_toward(aim_blend, 1.0 if zoom_stage > 0 else 0.0, AIM_BLEND_SPEED * delta)
	var target_scope_fov: float = SCOPE_FOVS[maxi(zoom_stage, 1) - 1]
	_scope_fov = lerpf(_scope_fov, target_scope_fov, 1.0 - exp(-AIM_BLEND_SPEED * delta))
	camera.fov = lerpf(BASE_FOV, _scope_fov, aim_blend)

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

	# リコイルの復帰（exp減衰・TABIJI準拠）
	_recoil *= exp(-recoil_recover * delta)

	camera.rotation = Vector3(sway_y + _recoil, sway_x, 0.0)
