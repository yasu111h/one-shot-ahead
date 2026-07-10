class_name VrmRetarget
extends RefCounted
## Mixamoのアニメを VRM(標準人型骨格) へリターゲット（流し込み）する。
## 各ボーンの「グローバル回転の rest からの差分」を計算して target に適用するため、
## 骨格の基本姿勢（ボーンの向き）が違っても破綻しない。

# Mixamo(mixamorig_X) → VRM 人型名。指は省略（走り/歩きに不要）。Spine2は対応先なしで省略。
const BONE_MAP := {
	"mixamorig_Hips": "Hips",
	"mixamorig_Spine": "Spine",
	"mixamorig_Spine1": "Chest",
	"mixamorig_Neck": "Neck",
	"mixamorig_Head": "Head",
	"mixamorig_LeftShoulder": "LeftShoulder",
	"mixamorig_LeftArm": "LeftUpperArm",
	"mixamorig_LeftForeArm": "LeftLowerArm",
	"mixamorig_LeftHand": "LeftHand",
	"mixamorig_RightShoulder": "RightShoulder",
	"mixamorig_RightArm": "RightUpperArm",
	"mixamorig_RightForeArm": "RightLowerArm",
	"mixamorig_RightHand": "RightHand",
	"mixamorig_LeftUpLeg": "LeftUpperLeg",
	"mixamorig_LeftLeg": "LeftLowerLeg",
	"mixamorig_LeftFoot": "LeftFoot",
	"mixamorig_LeftToeBase": "LeftToes",
	"mixamorig_RightUpLeg": "RightUpperLeg",
	"mixamorig_RightLeg": "RightLowerLeg",
	"mixamorig_RightFoot": "RightFoot",
	"mixamorig_RightToeBase": "RightToes",
}


# ボーンのグローバル rest 回転（rootから合成）
static func _global_rest_basis(skel: Skeleton3D, idx: int) -> Basis:
	var t: Transform3D = skel.get_bone_rest(idx)
	var p: int = skel.get_bone_parent(idx)
	while p != -1:
		t = skel.get_bone_rest(p) * t
		p = skel.get_bone_parent(p)
	return t.basis.orthonormalized()


## src_ap で anim_name を再生・サンプリングし、tgt_skel 用の Animation を生成して返す。
## tgt_skel_path: AnimationPlayerのrootから見た tgt スケルトンの相対パス（例 "GeneralSkeleton"）
static func bake(src_skel: Skeleton3D, src_ap: AnimationPlayer, anim_name: String,
		tgt_skel: Skeleton3D, tgt_skel_path: String) -> Animation:
	var src_anim := src_ap.get_animation(anim_name)
	var length: float = src_anim.length

	var out := Animation.new()
	out.length = length
	out.loop_mode = Animation.LOOP_LINEAR

	# マッピング表を作る
	var pairs: Array = []
	var src_rest: Dictionary = {}
	var tgt_rest: Dictionary = {}
	for src_name in BONE_MAP:
		var si: int = src_skel.find_bone(src_name)
		var ti: int = tgt_skel.find_bone(BONE_MAP[src_name])
		if si == -1 or ti == -1:
			continue
		var tr: int = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, tgt_skel_path + ":" + BONE_MAP[src_name])
		pairs.append({"si": si, "ti": ti, "tr": tr})
		src_rest[si] = _global_rest_basis(src_skel, si)
		tgt_rest[ti] = _global_rest_basis(tgt_skel, ti)

	# サンプリング（30fps）
	src_ap.play(anim_name)
	var fps := 30.0
	var frames: int = max(1, int(round(length * fps)))
	for f in range(frames + 1):
		var t: float = min(float(f) / fps, length)
		src_ap.seek(t, true)
		src_skel.force_update_all_bone_transforms()

		# 各 target ボーンのグローバル回転を求める
		var tgt_global: Dictionary = {}
		for pair in pairs:
			var src_g: Basis = src_skel.get_bone_global_pose(pair.si).basis.orthonormalized()
			var delta: Basis = src_g * src_rest[pair.si].inverse()
			tgt_global[pair.ti] = delta * tgt_rest[pair.ti]

		# 親のグローバルでローカル回転に変換してキー挿入
		for pair in pairs:
			var ti: int = pair.ti
			var pidx: int = tgt_skel.get_bone_parent(ti)
			var parent_g: Basis
			if tgt_global.has(pidx):
				parent_g = tgt_global[pidx]
			elif pidx != -1:
				parent_g = _global_rest_basis(tgt_skel, pidx)
			else:
				parent_g = Basis()
			var local_b: Basis = parent_g.inverse() * tgt_global[ti]
			out.rotation_track_insert_key(pair.tr, t, local_b.get_rotation_quaternion())

	src_ap.stop()
	return out
