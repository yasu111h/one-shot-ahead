class_name TorsoBend
extends SkeletonModifier3D
## 構えアニメを再生したあとに、上半身の骨だけを上下の狙いへ折り曲げる。
## SkeletonModifier3D はアニメーションの後段で走るので、アニメと喧嘩しない。
##
## 折り曲げの軸は「体の右方向」。VRMの骨格はモデルの向き（PI+28°）ぶん回っているので、
## body_ref の +X軸をスケルトン空間へ変換して使う。BONES を親から順に等分で回すと、
## その子である腕・頭には合計でピッチ全量が乗り、銃を持つ手が銃と一緒に上下する。

const BONES: Array[String] = ["Spine", "Chest"]  # 親→子の順であること

var body_ref: Node3D    # 体の向きの基準（SniperGirl本体）
var pitch := 0.0        # 上下の狙い(rad・上が正)


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or body_ref == null or is_zero_approx(pitch):
		return
	# 体の右方向をスケルトン空間で求める（モデルのY回転を打ち消す）
	var axis := skel.global_transform.basis.inverse() * body_ref.global_transform.basis.x
	if axis.length_squared() < 0.000001:
		return
	axis = axis.normalized()
	var each := pitch / float(BONES.size())
	for bone_name in BONES:
		var i := skel.find_bone(bone_name)
		if i == -1:
			continue
		# 親から順に処理するので、子の骨はこの時点で親の回転を織り込んだ姿勢になっている
		var gp := skel.get_bone_global_pose(i)
		skel.set_bone_global_pose(i, Transform3D(Basis(axis, each) * gp.basis, gp.origin))
