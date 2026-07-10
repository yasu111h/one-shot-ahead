class_name SniperGirl
extends Node3D
## 主人公の女の子（TABIJIのVRoidモデルを流用）。
## 屋上の角でスナイパーライフルを構えて立つ「見た目専用」のアバター。
## Mixamoの構えモーション(Idle_Aiming)をVRM骨格へリターゲットしてループ再生し、
## 右手ボーンにライフルを装着する（TABIJIのplayer.gd方式の簡略版）。
##
## SniperCamera(ヨー回転ノード)の子として置くと、視点の左右に合わせて体ごと旋回する。
## スコープを覗いている間はステージ側が visible=false にする（一人称に切り替え）。

const VRM_CHAR := "res://characters/AvatarSample.vrm"
const IDLE_AIM_FBX := "res://characters/Idle_Aiming.fbx"
const TGT_SKEL_PATH := "GeneralSkeleton"   # VRM内スケルトンへの相対パス

## Idle_Aimingの構えは体の正面から28°右へ銃を向ける姿勢（両手ボーンの実測から算出）。
## 体をこの分だけ左へ回し、銃線＝リグの正面(-Z)に一致させる
const BODY_ANGLE_DEG := 28.0

## ライフルの取り付け（girlローカル・体基準で固定）。
## 手ボーン装着だと構えモーションとの相性で向きが暴れるため、
## 「右手の実測位置に置き、常に正面を向ける」方式にする（三人称の見た目専用）
const GUN_POS := Vector3(0.15, 1.20, -0.15)

## 上下の狙いで体を折る支点（girlローカル・みぞおち付近）。
## 銃はここを中心に回すので、上半身の骨を同じ支点で曲げれば手と銃がずれない
const TORSO_PIVOT := Vector3(0.05, 1.12, -0.05)

var _skel: Skeleton3D
var _torso: Node3D          # 銃をぶら下げる支点（ピッチで回す）
var _bend: TorsoBend        # 上半身の骨を曲げるモディファイア


func _ready() -> void:
	var character := (load(VRM_CHAR) as PackedScene).instantiate()
	# VRMは+Z向きで出てくるので、リグの前方(-Z)へ向ける＋構えの銃線を正面に合わせる
	character.rotation.y = PI + deg_to_rad(BODY_ANGLE_DEG)
	add_child(character)

	var ap := _find_anim_player(character)
	_skel = _find_skel(character)
	if ap == null or _skel == null:
		push_warning("VRMのAnimationPlayer/Skeletonが見つからないため素立ちのまま")
		return
	var lib := ap.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		ap.add_animation_library("", lib)
	var aim := _bake_from_fbx(IDLE_AIM_FBX, _skel)
	if aim != null:
		aim.loop_mode = Animation.LOOP_LINEAR
		if lib.has_animation("IdleAim"):
			lib.remove_animation("IdleAim")
		lib.add_animation("IdleAim", aim)
		ap.play("IdleAim")
	_build_gun()
	# 上半身を曲げるモディファイア（アニメの後に適用される）
	_bend = TorsoBend.new()
	_bend.body_ref = self
	_skel.add_child(_bend)


## FBXを一時的に実体化し、そのMixamoアニメをVRM骨格用にベイクして返す（TABIJI方式）
func _bake_from_fbx(path: String, tgt_skel: Skeleton3D) -> Animation:
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate()
	inst.visible = false
	add_child(inst)
	var src_skel := _find_skel(inst)
	var src_ap := _find_anim_player(inst)
	var baked: Animation = null
	if src_skel and src_ap and src_ap.has_animation("mixamo_com"):
		baked = VrmRetarget.bake(src_skel, src_ap, "mixamo_com", tgt_skel, TGT_SKEL_PATH)
	inst.queue_free()
	return baked


# ---------------------------------------------------------------- 銃（スナイパーライフル）

## ライフルを「みぞおちの支点」にぶら下げる。支点をピッチで回すと、銃口が
## 狙っている方向（＝視線）へ一緒に向く（バレルは支点が水平なとき正面-Z）
func _build_gun() -> void:
	_torso = Node3D.new()
	_torso.name = "TorsoPivot"
	_torso.position = TORSO_PIVOT
	add_child(_torso)
	var gun := _make_rifle()
	gun.position = GUN_POS - TORSO_PIVOT
	gun.rotation.y = PI   # モデルのバレルは+Z向きなので正面(-Z)へ回す
	_torso.add_child(gun)


## 上下の狙い(rad・上が正)を受け取り、銃と上半身をそこへ向ける。
## ステージが毎フレーム rig.get_aim_pitch() を渡す
func set_aim_pitch(pitch: float) -> void:
	# girlローカルの前方は-Z。+XまわりにpitchだけまわすとFORWARDが上を向く
	if _torso != null:
		_torso.rotation.x = pitch
	if _bend != null:
		_bend.pitch = pitch


## スナイパーライフルの仮モデル（箱の組み合わせ・バレルはローカル+Z方向）
## TABIJIのSMG風 _make_gun を長銃身＋スコープ付きに伸ばしたもの
func _make_rifle() -> Node3D:
	var root := Node3D.new()
	root.name = "Rifle"
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.11, 0.11, 0.13)
	metal.metallic = 0.8
	metal.roughness = 0.4
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.18, 0.16, 0.14)
	accent.metallic = 0.3
	accent.roughness = 0.6

	# 受け(本体)
	root.add_child(_gun_box(Vector3(0.05, 0.075, 0.30), Vector3(0.0, 0.0, 0.05), metal))
	# 長い銃身
	root.add_child(_gun_box(Vector3(0.026, 0.026, 0.46), Vector3(0.0, 0.014, 0.42), metal))
	# マズル(先端の太み)
	root.add_child(_gun_box(Vector3(0.036, 0.036, 0.07), Vector3(0.0, 0.014, 0.66), accent))
	# スコープ(本体上)
	root.add_child(_gun_box(Vector3(0.032, 0.032, 0.16), Vector3(0.0, 0.075, 0.06), metal))
	# ストック(後ろ)
	root.add_child(_gun_box(Vector3(0.045, 0.065, 0.16), Vector3(0.0, -0.01, -0.17), accent))
	# グリップ(下)
	var grip := _gun_box(Vector3(0.04, 0.10, 0.05), Vector3(0.0, -0.08, -0.05), accent)
	grip.rotation_degrees = Vector3(18.0, 0.0, 0.0)
	root.add_child(grip)
	# マガジン(下・前寄り)
	var mag := _gun_box(Vector3(0.03, 0.10, 0.055), Vector3(0.0, -0.085, 0.09), metal)
	mag.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	root.add_child(mag)
	# 二脚(前方下・左右)
	for sx in [-1.0, 1.0]:
		var leg := _gun_box(Vector3(0.012, 0.14, 0.012), Vector3(sx * 0.03, -0.08, 0.52), metal)
		leg.rotation_degrees = Vector3(0.0, 0.0, sx * -14.0)
		root.add_child(leg)
	return root


func _gun_box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- 探索ユーティリティ

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r:
			return r
	return null
