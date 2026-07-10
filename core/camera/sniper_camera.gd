class_name SniperCamera
extends Node3D
## 照準リグ：ドラッグ視点（キャプチャなし）・スコープFOVスムーズ遷移・リコイル
## スコープ遷移はTABIJIの _aim_blend 方式（move_toward 6.0/s）でFOVをなめらかに補間する。
## 手ブレ・息止めは廃止（2026-07-10ユーザー決定：照準は常に静止。ブレはリコイルのみ）

signal zoom_changed(stage: int)

const BASE_FOV := 75.0                          # 肉眼FOV
const SCOPE_FOVS: Array[float] = [18.75, 9.375] # 4x / 8x（75/倍率）
const AIM_BLEND_SPEED := 6.0 # スコープ遷移速度（TABIJI準拠 6.0/s）

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

var _pitch_node: Node3D
var _yaw := 0.0
var _pitch := 0.0
var _scope_fov: float = SCOPE_FOVS[0]  # スコープ側の現在FOV（4x⇄8x切替もなめらかに）
var _recoil := 0.0


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

	# リコイルの復帰（exp減衰・TABIJI準拠）。照準は常に静止＝ブレはリコイルのみ
	_recoil *= exp(-recoil_recover * delta)

	camera.rotation = Vector3(_recoil, 0.0, 0.0)
