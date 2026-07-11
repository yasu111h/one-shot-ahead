class_name SniperCamera
extends Node3D
## 照準リグ：ドラッグ視点（キャプチャなし）・スコープFOVスムーズ遷移・リコイル
## スコープ遷移はTABIJIの _aim_blend 方式（move_toward 6.0/s）でFOVをなめらかに補間する。
## 息止めは廃止（2026-07-10ユーザー決定）。
## 手ブレは「距離連動」で復活（2026-07-10ユーザー指示）：狙っている標的が遠いほど
## 角度ブレが大きくなる。基準は600m先で窓1枚（横幅5m）ぶん照準がずれうる振れ幅。
## Settings.sway_enabled でON/OFF（HUD右上のSWAYボタン）。

signal zoom_changed(stage: int)

const BASE_FOV := 75.0                          # 肉眼FOV
const SCOPE_FOVS: Array[float] = [18.75, 9.375] # 4x / 8x（75/倍率）
const AIM_BLEND_SPEED := 6.0 # スコープ遷移速度（TABIJI準拠 6.0/s）

# --- 距離連動の手ブレ ---
const SWAY_REF_DIST := 600.0   # 基準距離(m)
const SWAY_REF_DEV := 5.0      # 基準距離での最大ずれ幅(m)＝都市ステージの窓の横幅
const SWAY_FADE_SPEED := 3.0   # ON/OFF・距離変化時の振幅のなじみ速さ(1/s)

@export var base_sens := 0.005          # 視点感度(rad/px)。FOV比例で自動微調整
@export var scope_sens_mult := 0.55     # スコープ中の感度倍率（TABIJI準拠）
@export var recoil_kick := 0.011        # 1発ごとのピッチ跳ね上がり(rad・TABIJI準拠)
@export var recoil_max := 0.055         # リコイルの上限(rad)
@export var recoil_recover := 9.0       # リコイルの戻り速さ(1/s・exp減衰)
@export var recoil_scoped_mult := 0.55  # スコープ中のリコイル倍率

var camera: Camera3D
var zoom_stage := 0          # 0=肉眼 1=4x 2=8x
var aim_blend := 0.0         # 肉眼0⇄スコープ1のなめらかな遷移値

# 視点の可動範囲（rad）。ステージが set_view_limits で狙撃地点に合わせて絞る。
# 例：屋上の角に陣取るステージでは「角から見渡せる扇形」だけに制限する
var yaw_min := deg_to_rad(-80.0)
var yaw_max := deg_to_rad(80.0)
var pitch_min := deg_to_rad(-25.0)
var pitch_max := deg_to_rad(25.0)

var sway_distance := -1.0    # 手ブレの基準にする標的距離(m)。ステージが毎フレーム更新（-1=無効）

var _pitch_node: Node3D
var _yaw := 0.0
var _pitch := 0.0
var _scope_fov: float = SCOPE_FOVS[0]  # スコープ側の現在FOV（4x⇄8x切替もなめらかに）
var _recoil := 0.0
var _sway_amp := 0.0         # 現在の手ブレ振幅(rad・なめらかに追従)
var _sway_phase := 0.0
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


## 視点の可動範囲を度で設定する（ステージの狙撃地点から見渡せる範囲に絞る）
func set_view_limits(yaw_min_deg: float, yaw_max_deg: float,
		pitch_min_deg: float, pitch_max_deg: float) -> void:
	yaw_min = deg_to_rad(yaw_min_deg)
	yaw_max = deg_to_rad(yaw_max_deg)
	pitch_min = deg_to_rad(pitch_min_deg)
	pitch_max = deg_to_rad(pitch_max_deg)
	# 現在の向きが新しい範囲の外なら中へ引き戻す
	_yaw = clampf(_yaw, yaw_min, yaw_max)
	_pitch = clampf(_pitch, pitch_min, pitch_max)
	rotation.y = _yaw
	_pitch_node.rotation.x = _pitch


## 現在の上下角(rad・上が正)。主人公アバターが上半身と銃をこれに追従させる
func get_aim_pitch() -> float:
	return _pitch


## ドラッグによる視点回転。感度はFOVに比例＋スコープ中は×0.55（TABIJI準拠）
func add_aim_delta(rel: Vector2) -> void:
	var sens := base_sens * lerpf(1.0, scope_sens_mult, aim_blend) * (camera.fov / BASE_FOV)
	_yaw = clampf(_yaw - rel.x * sens, yaw_min, yaw_max)
	_pitch = clampf(_pitch - rel.y * sens, pitch_min, pitch_max)
	rotation.y = _yaw
	_pitch_node.rotation.x = _pitch


## 指定ワールド座標がほぼ画面中央に来る向きへ即座に合わせる（起動時の初期照準など）
func aim_at(point: Vector3) -> void:
	var to := point - global_position
	var horiz := Vector2(to.x, to.z).length()
	_yaw = clampf(atan2(-to.x, -to.z), yaw_min, yaw_max)
	_pitch = clampf(atan2(to.y, horiz), pitch_min, pitch_max)
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
	zoom_changed.emit(stage)


## 発射時の反動キック（TABIJI準拠：ピッチ跳ね＋左右微ぶれ）
func kick() -> void:
	_recoil = minf(_recoil + recoil_kick * lerpf(1.0, recoil_scoped_mult, aim_blend), recoil_max)
	_yaw = clampf(_yaw + randf_range(-0.0018, 0.0018), yaw_min, yaw_max)
	rotation.y = _yaw


func _process(delta: float) -> void:
	# スコープ遷移（_aim_blend方式）。FOVは肉眼⇄スコープをなめらかに補間
	aim_blend = move_toward(aim_blend, 1.0 if zoom_stage > 0 else 0.0, AIM_BLEND_SPEED * delta)
	var target_scope_fov: float = SCOPE_FOVS[maxi(zoom_stage, 1) - 1]
	_scope_fov = lerpf(_scope_fov, target_scope_fov, 1.0 - exp(-AIM_BLEND_SPEED * delta))
	camera.fov = lerpf(BASE_FOV, _scope_fov, aim_blend)

	# リコイルの復帰（exp減衰・TABIJI準拠）
	_recoil *= exp(-recoil_recover * delta)

	# 距離連動の手ブレ：角度の振れ幅が標的距離に比例して育つ。
	# 600m先で「窓1枚(5m)ぶんずれうる」＝振れ幅 5/600 rad を基準に、距離比で線形スケール。
	# （近距離では着弾のずれ＝距離×角度も小さくなるので、体感は距離の二乗で効く）
	var target_amp := 0.0
	if Settings.sway_enabled and sway_distance > 0.0:
		target_amp = (SWAY_REF_DEV / SWAY_REF_DIST) * (sway_distance / SWAY_REF_DIST)
	# ON/OFFや測距値の切り替わりで照準が跳ねないよう、振幅はなめらかに追従させる
	_sway_amp = lerpf(_sway_amp, target_amp, 1.0 - exp(-SWAY_FADE_SPEED * delta))
	var sway_x := 0.0
	var sway_y := 0.0
	if _sway_amp > 0.00001:
		# ゆったりした8の字＋Perlinノイズ（縦は横の2倍周波数・息づかいの揺れ）
		_sway_phase += delta * 0.8
		var nx := _noise_x.get_noise_1d(_sway_phase * 40.0)
		var ny := _noise_y.get_noise_1d(_sway_phase * 40.0)
		sway_x = (sin(_sway_phase * TAU * 0.35) + nx * 0.8) * _sway_amp * 0.55
		sway_y = (sin(_sway_phase * TAU * 0.7) * 0.5 + ny * 0.8) * _sway_amp * 0.55

	camera.rotation = Vector3(sway_y + _recoil, sway_x, 0.0)
