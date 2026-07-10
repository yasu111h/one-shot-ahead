class_name Ballistics
extends RefCounted
## 弾道計算ユーティリティ（static関数群）
## 弾丸本体と着弾予測（バレットカム発動判定）で同じ積分式を使う

const GRAVITY := Vector3(0.0, -9.8, 0.0)

## 弾道の偏向フラグ（2026-07-10ユーザー決定：狙った点にそのまま当たる直線弾道）
## 両方 false ＝直線・等速。「照準の命中点」「実弾の着弾点」「予測（predict_*）」
## 「リプレイの終点」が原理的に同一直線上に乗り、ズレが消える。
## 弾速300m/sの飛行時間はそのまま＝動く標的へのリード（偏差撃ち）は生きる。
## 将来リアル弾道（重力落下・風流され）を復活させる場合は true に戻すだけでよい。
## 実弾(bullet.gd)・着弾予測がともに effective_accel() を参照するため、
## 切り替えても両者の整合は保たれる。
const GRAVITY_ENABLED := false
const WIND_ENABLED := false


## 弾に働く実効加速度（フラグに従う）。直線弾道時は Vector3.ZERO
static func effective_accel(wind_accel: Vector3) -> Vector3:
	var a := Vector3.ZERO
	if GRAVITY_ENABLED:
		a += GRAVITY
	if WIND_ENABLED:
		a += wind_accel
	return a


## 1ステップ分のセミインプリシット・オイラー積分
## 戻り値: [次の位置, 次の速度]
static func step(pos: Vector3, vel: Vector3, wind_accel: Vector3, delta: float) -> Array:
	var new_vel := vel + effective_accel(wind_accel) * delta
	var new_pos := pos + new_vel * delta
	return [new_pos, new_vel]


## 発射時の命中事前予測（粗いステップ積分）
## targets: [{node, position, velocity, radius, head_offset, head_radius}]
##          … 標的は等速直線移動と仮定。head_radius>0なら頭部を先に判定してゾーンを返す
## 命中が予測されれば {target, time, point, zone}、外れなら {} を返す
## point は弾道セグメント上の最接近点（=着弾点の近似。バレットカムの終点に使う）
static func predict_hit(
	space_state: PhysicsDirectSpaceState3D,
	start: Vector3,
	velocity: Vector3,
	wind_accel: Vector3,
	targets: Array,
	max_time := 4.0,
	dt := 0.02
) -> Dictionary:
	var pos := start
	var vel := velocity
	var t := 0.0
	while t < max_time:
		var r := step(pos, vel, wind_accel, dt)
		var next: Vector3 = r[0]
		vel = r[1]
		# 地形（レイヤ1）に当たる場合はセグメントを着弾点まで縮める
		var seg_end := next
		var blocked := false
		var query := PhysicsRayQueryParameters3D.create(pos, next, 1)
		var terrain_hit := space_state.intersect_ray(query)
		if terrain_hit:
			seg_end = terrain_hit.position
			blocked = true
		t += dt
		# 各標的の予測位置と弾道セグメントの距離をチェック（地形より手前なら命中）
		# 1ステップ内に複数の標的が重なりうる（部屋の中で悪人の手前に民間人が立つ等）ので、
		# 弾の進行方向で最も手前の1体を選ぶ。配列順で決めると奥の標的に当たってしまう。
		var best := {}
		var best_d := INF
		for tg in targets:
			var predicted: Vector3 = tg.position + tg.velocity * t
			var head_r: float = tg.get("head_radius", 0.0)
			if head_r > 0.0:
				var head_pos: Vector3 = predicted + tg.get("head_offset", Vector3.ZERO)
				var hclosest := Geometry3D.get_closest_point_to_segment(head_pos, pos, seg_end)
				if head_pos.distance_to(hclosest) <= head_r:
					var hd := pos.distance_to(hclosest)
					if hd < best_d:
						best_d = hd
						best = {"target": tg.node, "time": t, "point": hclosest, "zone": "head"}
			var closest := Geometry3D.get_closest_point_to_segment(predicted, pos, seg_end)
			if predicted.distance_to(closest) <= tg.radius:
				var bd := pos.distance_to(closest)
				if bd < best_d:
					best_d = bd
					best = {"target": tg.node, "time": t, "point": closest, "zone": "body"}
		if not best.is_empty():
			return best
		if blocked:
			return {}
		pos = next
	return {}


## ミス弾の着弾点予測（ミスリプレイのカメラ終点に使う）
## 地形（レイヤ1）に当たればその着弾点と法線を {point, normal, grounded=true} で返す。
## 最大射程まで何にも当たらなければ、その時点の弾の位置を grounded=false で返す。
static func predict_miss_point(
	space_state: PhysicsDirectSpaceState3D,
	start: Vector3,
	velocity: Vector3,
	wind_accel: Vector3,
	max_time := 4.0,
	dt := 0.02
) -> Dictionary:
	var pos := start
	var vel := velocity
	var t := 0.0
	while t < max_time:
		var r := step(pos, vel, wind_accel, dt)
		var next: Vector3 = r[0]
		vel = r[1]
		var query := PhysicsRayQueryParameters3D.create(pos, next, 1)
		var hit := space_state.intersect_ray(query)
		if hit:
			return {"point": hit.position, "normal": hit.get("normal", Vector3.UP), "grounded": true}
		pos = next
		t += dt
	return {"point": pos, "normal": Vector3.UP, "grounded": false}
