class_name CrouchPose
extends SkeletonModifier3D
## 主人公の「伏せ（しゃがみ）」ポーズ。構えアニメ(IdleAim)の後段で走り、
## blend(0..1)に応じて脚を折り・腰を落とし・上体を丸めて遮蔽に隠れる姿勢を作る。
## Mixamoのしゃがみアニメに頼らず、TorsoBend と同じ「骨のグローバル回転合成」方式で
## コード生成する（アニメと喧嘩しない・全ステージで同じに動く）。
##
## 回転軸は「体の右方向」（body_ref の +X をスケルトン空間へ変換）。
## 符号は target_human._build_shot_anim（崩れ落ちアニメ）と同じ規約:
##   UpperLeg 負=腿を持ち上げる / LowerLeg 正=膝を折る / Spine・Chest 正=前屈

## ボーンごとの伏せ角(rad・blend=1のときの値)。親→子の順に適用する
const KEYS := {
	"Hips": 0.30,            # 腰を前へ倒す（尻が落ちる）
	"Spine": 0.35,           # 背を丸める
	"Chest": 0.25,
	"Head": -0.35,           # 顔だけは前（標的の方）を見続ける
	"LeftUpperLeg": -1.05,   # 腿を深く畳む
	"RightUpperLeg": -0.90,
	"LeftLowerLeg": 1.35,    # 膝を折る
	"RightLowerLeg": 1.20,
}

var body_ref: Node3D    # 体の向きの基準（SniperGirl本体）
var blend := 0.0        # 0=立ち 1=伏せ


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or body_ref == null or blend < 0.001:
		return
	# 体の右方向をスケルトン空間で求める（モデルのY回転を打ち消す）。
	# ※ モデルはY軸へ約208°回して立っているため、girlの+Xはモデルから見ると
	#   ほぼ-X＝回転の向きが逆になる。軸を反転して「正の角度＝前に畳む」に揃える
	var axis := -(skel.global_transform.basis.inverse() * body_ref.global_transform.basis.x)
	if axis.length_squared() < 0.000001:
		return
	axis = axis.normalized()
	for bone_name in KEYS:
		var i := skel.find_bone(bone_name)
		if i == -1:
			continue
		# 親から順に処理するので、子の骨はこの時点で親の回転を織り込んだ姿勢になっている
		var gp := skel.get_bone_global_pose(i)
		skel.set_bone_global_pose(i,
			Transform3D(Basis(axis, KEYS[bone_name] * blend) * gp.basis, gp.origin))
