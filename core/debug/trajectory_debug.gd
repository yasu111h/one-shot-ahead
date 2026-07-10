class_name TrajectoryDebug
extends Node3D
## 弾道検証デバッグ表示（F3でON/OFF・デバッグビルド専用。リリースには出ない）
##
## 目で確認できること：
##   ① 発射の瞬間にレティクルが指していた点 … 緑の線＋AIMマーカー
##   ② 実弾が実際に通った軌跡と着弾点       … 赤い線＋REALマーカー
##      （狙点レイからの落下量DROP・横ズレSIDEを数値表示。直線弾道なら0のはず）
##   ③ リプレイ(バレットカム)の弾の軌跡     … 黄の線＋REPLAYマーカー
##      （実弾道との最大乖離を数値表示。重なっていれば「同じ弾道」）
##
## 赤線は「実弾と同一の積分・当たり判定」で発射の瞬間に一括シミュレートするため、
## 命中確定弾（実弾を飛ばさない）でも長距離でも、撃った直後に全長が表示される。
##
## Tab：視点切替（0=通常 → 1=弾道を真横から → 2=着弾点アップ → 0…）
## ※ 弾道は視線方向と重なるため、通常視点では線の重なり・落差はほぼ見えない。
##    Tabの「真横」視点で赤・黄・緑の線の一致/ズレを見る。精密な差は数値パネルで。

const COL_AIM := Color(0.25, 1.0, 0.35)     # 緑：レティクルの狙点
const COL_REAL := Color(1.0, 0.25, 0.2)     # 赤：実弾（発射時に一括シミュレート）
const COL_REPLAY := Color(1.0, 0.9, 0.2)    # 黄：リプレイ弾
const RAY_MASK := 0b1111                    # 地形1+ボディ2+ヘッド4+乗り物8
const VIEW_NAMES := ["normal", "side", "impact"]
const DASH_LEN := 2.0                       # 破線のダッシュ長(m)。赤と黄は位相をずらして交互に見せる
const MATCH_TOL := 0.1                      # 「一致」と判定する許容誤差(m)
const MARKER_LIFETIME := 3.0                # マーカー（球＋名前）の表示時間(実秒)。線とパネルは残る

var stage  # SniperStage（型を書くと相互参照になるため未型付け）
var enabled := false

var _mesh: ImmediateMesh
var _markers: Array[Dictionary] = []        # {node, age}。寿命つき（視界を塞がない）
var _panel: CanvasLayer
var _label: Label
var _view := 0
var _cam: Camera3D

# --- 直近1発の記録（新しい発射でクリア） ---
var _has_shot := false
var _aim_start := Vector3.ZERO
var _aim_dir := Vector3.FORWARD
var _aim_point := Vector3.ZERO
var _assisted := false                      # この1発にオートエイム補正が入ったか
var _real_pts := PackedVector3Array()       # 実弾が通った点列
var _real_impact := Vector3.ZERO
var _has_real_impact := false
var _replay_pts := PackedVector3Array()     # リプレイ弾が通った点列
var _replay_from := Vector3.ZERO
var _replay_to := Vector3.ZERO
var _has_replay := false


func _ready() -> void:
	# 3本の線（緑・赤・黄）。壁越しでも見えるよう深度テストなしで最前面に描く
	_mesh = ImmediateMesh.new()
	var inst := MeshInstance3D.new()
	inst.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 20
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	# 検証用カメラ（Tabの真横視点・着弾点アップ）
	_cam = Camera3D.new()
	_cam.far = 2000.0
	add_child(_cam)
	# 数値パネル（左上・HUDより手前、リプレイのレターボックスより奥）
	_panel = CanvasLayer.new()
	_panel.layer = 90
	_panel.visible = false
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.75))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.position = Vector2(12, 66)
	_panel.add_child(_label)


## F3：デバッグ表示のON/OFF
func toggle_enabled() -> void:
	enabled = not enabled
	_panel.visible = enabled
	if not enabled:
		_clear_shot()
		_set_view(0)


## Tab：視点切替（通常→真横→着弾点アップ→通常…）
func cycle_view() -> void:
	if not enabled or not _has_shot:
		return
	_set_view((_view + 1) % 3)


# ---------------------------------------------------------------- 記録の受け口（SniperStageが呼ぶ）

## 発射の瞬間：レティクル（素の視線）が指していた点をレイキャストで確定して緑マーカーを置く
func on_fire(eye: Vector3, raw_dir: Vector3, assisted: bool) -> void:
	if not enabled:
		return
	_clear_shot()
	_has_shot = true
	_assisted = assisted
	_aim_start = eye
	_aim_dir = raw_dir.normalized()
	var query := PhysicsRayQueryParameters3D.create(eye, eye + raw_dir * 1500.0, RAY_MASK)
	query.collide_with_areas = true
	var res := get_world_3d().direct_space_state.intersect_ray(query)
	_aim_point = res.position if res else eye + raw_dir * 1500.0
	_add_marker(_aim_point, "AIM", COL_AIM, 0.6)
	if _view != 0:
		_set_view(0)  # 新しい1発は通常視点から（前の弾の視点位置が残らないように）


## 実弾の弾道を発射の瞬間に一括シミュレートして赤線として記録する。
## bullet.gd とまったく同じ計算（Ballistics.step・dt=1/60・移動区間のセグメントレイ・
## 同じ判定マスク）なので、結果は実際に飛ぶ実弾と同一。
## ※ 以前は「ゴースト実弾」を実時間で飛ばして記録していたが、長距離＋リプレイの
##   スローモーション中は赤線が伸びきるまで10秒以上かかり「赤が見えない」状態に
##   なったため、待ち時間ゼロのその場シミュレートに変更（2026-07-10）
func simulate_real(start: Vector3, velocity: Vector3, wind_accel: Vector3) -> void:
	if not enabled:
		return
	const DT := 1.0 / 60.0      # bullet.gd の物理フレームと同じ刻み
	const LIFETIME := 5.0       # bullet.gd と同じ寿命
	var space := get_world_3d().direct_space_state
	var pos := start
	var vel := velocity
	var t := 0.0
	_real_pts.append(pos)
	while t < LIFETIME:
		var r := Ballistics.step(pos, vel, wind_accel, DT)
		var next: Vector3 = r[0]
		vel = r[1]
		var query := PhysicsRayQueryParameters3D.create(pos, next, RAY_MASK)
		query.collide_with_areas = true
		var result := space.intersect_ray(query)
		if result:
			_real_impact = result.position
			_real_pts.append(result.position)
			_has_real_impact = true
			_add_marker(result.position, "REAL", COL_REAL, 1.2)
			return
		pos = next
		_real_pts.append(pos)
		if pos.y < -10.0:
			return  # 何にも当たらず落下限界（bullet.gdの消滅条件と同じ）
		t += DT


## リプレイ（バレットカム）開始：確定弾道の始点・終点を記録して黄マーカーを置く
func on_replay(from: Vector3, to: Vector3) -> void:
	if not enabled:
		return
	_has_replay = true
	_replay_from = from
	_replay_to = to
	_replay_pts.append(from)
	_add_marker(to, "REPLAY", COL_REPLAY, 1.8)


# ---------------------------------------------------------------- 毎フレーム処理

func _process(delta: float) -> void:
	if not enabled:
		return
	# マーカー（球＋名前ラベル）は数秒で自動消去（AIM/REAL/REPLAYの文字が
	# 視界を塞ぎ続けないように）。線と数値パネルは次の発射まで残る
	var real_dt := delta / maxf(Engine.time_scale, 0.001)
	for i in range(_markers.size() - 1, -1, -1):
		_markers[i].age += real_dt
		if _markers[i].age > MARKER_LIFETIME:
			if is_instance_valid(_markers[i].node):
				_markers[i].node.queue_free()
			_markers.remove_at(i)
	# リプレイ弾の位置サンプリング（bullet_camの弾丸モデルの実座標）
	var bc = stage.bullet_cam
	if _has_replay and bc != null and bc.bolt_flying():
		var p: Vector3 = bc.bolt_position()
		if _replay_pts.is_empty() or _replay_pts[_replay_pts.size() - 1].distance_to(p) > 0.05:
			_replay_pts.append(p)
	_rebuild_lines()
	_update_panel()


func _rebuild_lines() -> void:
	_mesh.clear_surfaces()
	if not _has_shot:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# 緑：狙点レイ（実線）
	_mesh.surface_set_color(COL_AIM)
	_mesh.surface_add_vertex(_aim_start)
	_mesh.surface_add_vertex(_aim_point)
	# 赤：実弾の軌跡（破線・位相0）／黄：リプレイ弾の軌跡（破線・位相ずらし）。
	# 3本が完全に重なっている場合でも「緑の実線の上に赤・黄のダッシュが交互に乗る」
	# ので、1本にしか見えず区別できない問題を解消する（重なり＝一致の証拠が見える）
	_add_dashed(_real_pts, COL_REAL, 0.0)
	_add_dashed(_replay_pts, COL_REPLAY, DASH_LEN)
	_mesh.surface_end()


## 破線ポリライン。DASH_LEN描いてDASH_LEN休むを繰り返す。phase＝パターンの開始オフセット(m)
func _add_dashed(pts: PackedVector3Array, col: Color, phase: float) -> void:
	_mesh.surface_set_color(col)
	var period := DASH_LEN * 2.0
	var pos_along := phase
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len < 0.0001:
			continue
		var dirv := (b - a) / seg_len
		var t := 0.0
		while t < seg_len:
			var local := fmod(pos_along, period)
			if local < DASH_LEN:
				var run := minf(DASH_LEN - local, seg_len - t)
				_mesh.surface_add_vertex(a + dirv * t)
				_mesh.surface_add_vertex(a + dirv * (t + run))
				t += run
				pos_along += run
			else:
				var skip := minf(period - local, seg_len - t)
				t += skip
				pos_along += skip


# ---------------------------------------------------------------- 数値パネル

func _update_panel() -> void:
	var lines: Array[String] = []
	lines.append("[TRAJ DEBUG] F3:off  TAB:view=%d(%s)" % [_view, VIEW_NAMES[_view]])
	if not _has_shot:
		lines.append("fire to record...")
		_label.text = "\n".join(lines)
		return
	lines.append("GRAVITY: %s / WIND: %s" % [
		"ON" if Ballistics.gravity_enabled else "OFF",
		"ON" if Ballistics.WIND_ENABLED else "OFF"])
	lines.append("AIM    d=%.1fm  %s" % [_aim_start.distance_to(_aim_point), _fmt(_aim_point)])
	var drop := 0.0
	if _has_real_impact:
		var off := _ray_offset(_real_impact)
		var side := Vector2(off.x, off.z).length()
		drop = -off.y
		lines.append("REAL   DROP:%+.2fm SIDE:%.2fm  %s" % [drop, side, _fmt(_real_impact)])
	else:
		lines.append("REAL   -")
	var gap := -1.0
	var dev := -1.0
	if _has_replay:
		gap = _real_impact.distance_to(_replay_to) if _has_real_impact else -1.0
		var gap_s := ("%.2fm" % gap) if gap >= 0.0 else "-"
		lines.append("REPLAY end %s  GAP(real-replay):%s" % [_fmt(_replay_to), gap_s])
		dev = _max_dev()
		lines.append("PATH DEV(real vs replay) max:%s" % (("%.2fm" % dev) if dev >= 0.0 else "-"))
	else:
		lines.append("REPLAY -")
	# 結論の1行：数値を読まなくても分かる判定。緑線・赤線・黄線が重なって
	# 1本に見える時は、これがMATCHなら「一致している証拠」
	if _has_real_impact and _has_replay and gap >= 0.0 and dev >= 0.0:
		# 重力ON時はDROP（狙点より下への落下）があるのが正しい挙動なので判定から外し、
		# 「実弾とリプレイが同じ弾道か」（GAP・PATH DEV）だけを見る
		var ok := gap < MATCH_TOL and dev < MATCH_TOL \
			and (Ballistics.gravity_enabled or absf(drop) < MATCH_TOL)
		var msg := "MATCH - aim/real/replay match (lines overlap)"
		if Ballistics.gravity_enabled:
			msg = "MATCH - real/replay match (DROP is expected w/ gravity)"
		lines.insert(1, "RESULT: %s" % (msg if ok else "MISMATCH!! check DROP/GAP/DEV below"))
		_label.add_theme_color_override(
			"font_color", Color(0.7, 1.0, 0.75) if ok else Color(1.0, 0.45, 0.4))
	_label.text = "\n".join(lines)


func _fmt(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


## 点pの「狙点レイからのズレ」ベクトル（レイ上の最近点→p）
func _ray_offset(p: Vector3) -> Vector3:
	var d := (p - _aim_start).dot(_aim_dir)
	return p - (_aim_start + _aim_dir * d)


## 実弾の軌跡とリプレイ弾道（from→to直線）の最大乖離。
## リプレイ区間より先へ飛び続けた尾（標的が動いた場合など）は比較対象から外す
func _max_dev() -> float:
	if _real_pts.size() < 2 or not _has_replay:
		return -1.0
	var seg := _replay_to - _replay_from
	var len2 := seg.length_squared()
	if len2 < 0.0001:
		return -1.0
	var m := -1.0
	for p in _real_pts:
		var t := (p - _replay_from).dot(seg) / len2
		if t > 1.02:
			continue
		var q := _replay_from + seg * clampf(t, 0.0, 1.0)
		m = maxf(m, p.distance_to(q))
	return m


# ---------------------------------------------------------------- 視点切替

func _set_view(v: int) -> void:
	_view = v
	if v == 0:
		if stage.rig != null and stage.rig.camera != null and not stage.is_replay_active():
			stage.rig.camera.current = true
		return
	var end := _end_point()
	var side := _aim_dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	if v == 1:
		# 真横：弾道全体が入る距離まで引いて、横から線の重なりを見る
		var mid := (_aim_start + end) * 0.5
		var length := _aim_start.distance_to(end)
		var dist := clampf(length * 0.62, 8.0, 260.0)
		_cam.global_position = mid + side * dist + Vector3.UP * (length * 0.05)
		_cam.look_at(mid, Vector3.UP)
	else:
		# 着弾点アップ：3本の線の終点が一致しているかを間近で見る
		_cam.global_position = end + side * 3.5 + Vector3.UP * 1.2 - _aim_dir * 1.5
		_cam.look_at(end, Vector3.UP)
	_cam.current = true


func _end_point() -> Vector3:
	if _has_real_impact:
		return _real_impact
	if _has_replay:
		return _replay_to
	return _aim_point


# ---------------------------------------------------------------- マーカー・クリア

## マーカー（球＋名前ラベル）。label_h＝ラベルの高さ(m)。
## AIM/REAL/REPLAYで高さを変え、3点が同じ場所でもラベルが縦に並んで読めるようにする
func _add_marker(pos: Vector3, text: String, col: Color, label_h := 0.9) -> void:
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.no_depth_test = true
	mat.render_priority = 21
	sphere.material = mat
	m.mesh = sphere
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos
	var l := Label3D.new()
	l.text = text
	l.modulate = col
	l.font_size = 14
	l.outline_size = 5
	l.pixel_size = 0.002         # fixed_sizeでの画面上の大きさ（既定0.005は巨大すぎた）
	l.fixed_size = true          # 距離によらず画面上で同じ大きさ（200m先でも読める）
	l.no_depth_test = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, label_h, 0)
	m.add_child(l)
	_markers.append({"node": m, "age": 0.0})


func _clear_shot() -> void:
	for e in _markers:
		if is_instance_valid(e.node):
			e.node.queue_free()
	_markers.clear()
	_has_shot = false
	_assisted = false
	_real_pts = PackedVector3Array()
	_has_real_impact = false
	_replay_pts = PackedVector3Array()
	_has_replay = false
	_mesh.clear_surfaces()
