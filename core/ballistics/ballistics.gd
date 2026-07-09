class_name Ballistics
extends RefCounted
## 弾道計算ユーティリティ（static関数群）
## 弾丸本体と着弾予測（バレットカム発動判定）で同じ積分式を使う

const GRAVITY := Vector3(0.0, -9.8, 0.0)


## 1ステップ分のセミインプリシット・オイラー積分
## 戻り値: [次の位置, 次の速度]
static func step(pos: Vector3, vel: Vector3, wind_accel: Vector3, delta: float) -> Array:
	var new_vel := vel + (GRAVITY + wind_accel) * delta
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
		for tg in targets:
			var predicted: Vector3 = tg.position + tg.velocity * t
			# 頭部を先に判定（ヘッドショットのゾーン付き予測）
			var head_r: float = tg.get("head_radius", 0.0)
			if head_r > 0.0:
				var head_pos: Vector3 = predicted + tg.get("head_offset", Vector3.ZERO)
				var hclosest := Geometry3D.get_closest_point_to_segment(head_pos, pos, seg_end)
				if head_pos.distance_to(hclosest) <= head_r:
					return {"target": tg.node, "time": t, "point": hclosest, "zone": "head"}
			var closest := Geometry3D.get_closest_point_to_segment(predicted, pos, seg_end)
			if predicted.distance_to(closest) <= tg.radius:
				return {"target": tg.node, "time": t, "point": closest, "zone": "body"}
		if blocked:
			return {}
		pos = next
	return {}
