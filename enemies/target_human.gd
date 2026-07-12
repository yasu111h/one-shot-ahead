class_name TargetHuman
extends RigidBody3D
## 人型標的。見た目はVRMの3Dモデル(主人公と同じ仕組み)＋Mixamoアニメのリターゲット。
## 通常は freeze=true の静的ボディ。命中時に物理へ切替えて人形のように倒れる。
##
## ゲーム性の契約(従来のカプセル版と完全に同一):
##   - 胴体カプセル(レイヤ2)＋頭Area3D(レイヤ3)・meta target_root/part・group target_part
##   - hostile / alive / predict_radius / head_offset / head_radius / velocity_estimate
##   - die(hit_impulse) で物理転倒＋died シグナル
## 視認性の色分けも維持: 悪人=濃い赤 / 民間人=白 のマネキン風tint
## (実写テクスチャだと数百m先で敵味方が読めないため。シルエットだけリアルにする)
##
## hostile=false は民間人。撃つべきでない相手なので、照準減速（スティッキーエイム）は
## 反応せず、バレットカムも発動しない。撃ってしまうとミッション失敗（SniperStage._fail）。

signal died(target: TargetHuman)

const VRM_CHAR := "res://characters/AvatarSample.vrm"
const IDLE_FBX := "res://characters/Idle.fbx"
const WALK_FBX := "res://characters/Walking.fbx"
const TGT_SKEL_PATH := "GeneralSkeleton"   # VRM内スケルトンへの相対パス

const TOTAL_HEIGHT := 1.68     # 足元→頭中心の高さ(頭Area 0.93 + 足元 -0.75 に合わせる)
const FEET_Y := -0.75          # 胴体中心(原点)から見た足元

## Mixamoアニメのベイクは重いので、初回の1回だけ行い全標的で共有する(標的は10体以上いる)
static var _anim_cache: Dictionary = {}

var hostile := true   # false＝民間人（誤射禁止）
var alive := true
var use_model := true           # falseで従来のカプセル見た目に(特殊な置き場所用)
var predict_radius := 0.8       # 着弾予測用の包含球半径
var velocity_estimate := Vector3.ZERO  # 偏差予測用の推定速度
var head_offset := Vector3(0, 0.93, 0)  # 中心→頭中心のオフセット（着弾予測のゾーン判定用）
var head_radius := 0.2                  # 頭部ヒットボックス半径（同上）

var _prev_pos := Vector3.ZERO
var _mats: Array[StandardMaterial3D] = []   # 全身のtintマテリアル(死亡でグレー化)
var _ap: AnimationPlayer = null             # VRMのアニメ(死亡で停止)
var _walking := false


func _ready() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 0b0010  # レイヤ2: 敵ボディ
	collision_mask = 0b0001   # 地形とだけ衝突（倒れる用）
	set_meta("target_root", self)
	set_meta("part", "body")
	add_to_group("target_part")  # 照準減速の対象（グループ＋meta "part" 契約）
	_build_hitboxes()
	if use_model:
		_build_model()
	if _mats.is_empty():
		_build_capsule_visual()   # モデルが読めない環境でも従来の見た目で動く
	_prev_pos = global_position


## 当たり判定(従来と同一の寸法・レイヤ・meta)
func _build_hitboxes() -> void:
	# 胴体コリジョン（カプセル・中心が原点）
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.5
	col.shape = capsule
	add_child(col)
	# 頭ヒットボックス（Area3D・レイヤ3）
	var head_area := Area3D.new()
	head_area.collision_layer = 0b0100
	head_area.collision_mask = 0
	head_area.monitoring = false
	head_area.monitorable = true
	head_area.set_meta("target_root", self)
	head_area.set_meta("part", "head")
	head_area.add_to_group("target_part")  # 照準減速はヘッド付近でも効く
	var head_col := CollisionShape3D.new()
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.2
	head_col.shape = head_shape
	head_area.add_child(head_col)
	head_area.position = Vector3(0, 0.93, 0)
	add_child(head_area)


## VRM人型モデルの見た目。頭ヒットボックス(y=0.93)に頭が重なるようスケールを合わせる
func _build_model() -> void:
	var scene := load(VRM_CHAR) as PackedScene
	if scene == null:
		return
	var character := scene.instantiate()
	character.rotation.y = PI   # VRMは+Z向き→標的の正面(-Z)へ
	add_child(character)

	var skel := _find_skel(character)
	_ap = _find_anim_player(character)
	if skel == null:
		character.queue_free()
		return

	# 実測の頭の高さから全体スケールを決め、足元を胴体カプセルの下端に合わせる
	var head_idx := skel.find_bone("Head")
	var head_h := 1.5
	if head_idx >= 0:
		head_h = (skel.global_transform * skel.get_bone_global_rest(head_idx)).origin.y \
			- character.global_position.y
	var s := TOTAL_HEIGHT / maxf(head_h + 0.09, 0.5)   # +0.09=頭骨→頭中心のぶん
	character.scale = Vector3.ONE * s
	character.position.y = FEET_Y

	# 視認性のtint: 悪人=濃い赤 / 民間人=白(従来の色分けを踏襲)。全メッシュを差し替え
	var tint := Color(0.62, 0.10, 0.09) if hostile else Color(0.88, 0.88, 0.92)
	for mi in _all_meshes(character):
		var m := StandardMaterial3D.new()
		m.albedo_color = tint
		m.roughness = 0.85
		mi.material_override = m
		_mats.append(m)

	# アニメ: 待機/歩き(Mixamo→VRMへベイク。結果は全標的で共有)
	if _ap != null:
		var lib := _ap.get_animation_library("")
		if lib == null:
			lib = AnimationLibrary.new()
			_ap.add_animation_library("", lib)
		var idle := _shared_anim(IDLE_FBX, skel)
		var walk := _shared_anim(WALK_FBX, skel)
		if idle != null:
			lib.add_animation("Idle", idle)
		if walk != null:
			lib.add_animation("Walk", walk)
		if idle != null:
			_ap.play("Idle")
			# 個体ごとに再生位置をずらす(全員が同じ拍で揺れる「量産感」を消す)
			_ap.seek(randf() * idle.length, true)


## ベイク済みアニメの共有キャッシュ。初回だけFBXを実体化してベイクする
func _shared_anim(path: String, skel: Skeleton3D) -> Animation:
	if _anim_cache.has(path):
		return _anim_cache[path]
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
		baked = VrmRetarget.bake(src_skel, src_ap, "mixamo_com", skel, TGT_SKEL_PATH)
	inst.queue_free()
	if baked != null:
		baked.loop_mode = Animation.LOOP_LINEAR
		_anim_cache[path] = baked
	return baked


## 従来のカプセル見た目(VRMが読めない時のフォールバック)
func _build_capsule_visual() -> void:
	var body_mesh := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.3
	body.height = 1.5
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.75, 0.10, 0.08) if hostile else Color(0.86, 0.86, 0.90)
	body.material = body_mat
	body_mesh.mesh = body
	add_child(body_mesh)
	_mats.append(body_mat)
	var head_mesh := MeshInstance3D.new()
	var head := SphereMesh.new()
	head.radius = 0.16
	head.height = 0.32
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.95, 0.32, 0.22) if hostile else Color(0.95, 0.93, 0.90)
	head.material = head_mat
	head_mesh.mesh = head
	head_mesh.position = Vector3(0, 0.93, 0)
	add_child(head_mesh)
	_mats.append(head_mat)


func _physics_process(delta: float) -> void:
	if alive and delta > 0.0:
		velocity_estimate = (global_position - _prev_pos) / delta
	_prev_pos = global_position
	# 動いていれば歩き、止まっていれば待機(往復ウォーカーが折り返しでも自然に切替わる)
	if alive and _ap != null:
		var moving := velocity_estimate.length() > 0.2
		if moving != _walking:
			_walking = moving
			var next := "Walk" if moving else "Idle"
			if _ap.has_animation(next):
				_ap.play(next)


## 命中：物理ボディへ切替えて人形のように倒す（血の表現なし）
func die(hit_impulse: Vector3) -> void:
	if not alive:
		return
	alive = false
	velocity_estimate = Vector3.ZERO
	# 全身をグレーに沈めてアニメを止める(こと切れた表現)
	for m in _mats:
		m.albedo_color = Color(0.32, 0.31, 0.30)
	if _ap != null:
		_ap.pause()
	_fall.call_deferred(hit_impulse)
	died.emit(self)


func _fall(hit_impulse: Vector3) -> void:
	freeze = false
	# 上体寄りに撃力を与えて倒す
	apply_impulse(hit_impulse, Vector3(0, 0.5, 0))


# ---------------------------------------------------------------- VRMユーティリティ

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


func _all_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_meshes(c))
	return out
