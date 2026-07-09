class_name Hud
extends CanvasLayer
## HUD：残弾・風・測距・息止め円弧ゲージ・操作ボタン・距離スタンプ・CLEAR/RETRY
## ＋動的レティクル（bloom開閉・ロック色変化・ヒットマーカー。TABIJIのcombat_hud.gd方式）

var stage: SniperStage      # 親ステージ
var mission := ""           # ミッション文（左上に常時表示。空なら出さない）
var rig: SniperCamera
var range_distance := -1.0  # ステージが毎フレーム更新する測距値

var scope: ScopeOverlay

var _reticle: DynamicReticle
var _markers: TargetMarkers
var _ammo_label: Label
var _wind_label: Label
var _targets_label: Label
var _hint_label: Label
var _mission_label: Label
var _range_label: Label
var _zoom_label: Label
var _stamp: Label
var _center_msg: Label
var _retry_btn: Button
var _breath_arc: BreathArc
var _fire_btn: TouchScreenButton
var _scope_btn: TouchScreenButton
var _breath_btn: TouchScreenButton
var _stamp_t := -1.0


func _ready() -> void:
	layer = 10
	# スコープマスク（最背面）
	scope = ScopeOverlay.new()
	add_child(scope)
	scope.visible = false
	# 標的マーカー（▼＋距離。スコープマスクより奥＝円の外はマスクで隠れる）
	_markers = TargetMarkers.new()
	_markers.stage = stage
	_markers.rig = rig
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_markers)
	move_child(_markers, 0)
	_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 息止め円弧ゲージ
	# ※ set_anchors_preset は「現在のレクトを保持したままアンカーだけ変える」ため、
	#   生成直後のサイズ(0,0)のControlに使うと0サイズのまま＝中心(size/2)が左上になる。
	#   必ず set_anchors_and_offsets_preset でオフセットごとFULL_RECTにする。
	_breath_arc = BreathArc.new()
	_breath_arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_breath_arc)
	_breath_arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_breath_arc.visible = false
	# 動的レティクル（スコープマスクより手前）
	_reticle = DynamicReticle.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reticle)
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ラベル類
	_targets_label = _make_label("TARGETS 0/0", 15, Control.PRESET_TOP_LEFT, Vector2(12, 8))
	_hint_label = _make_label(
		"AIM: R-DRAG / FIRE: L-CLICK / SCOPE: Q or WHEEL / BREATH: HOLD SPACE (SCOPED)",
		10, Control.PRESET_TOP_LEFT, Vector2(12, 30))
	_hint_label.modulate = Color(1, 1, 1, 0.55)
	_mission_label = _make_label(mission, 13, Control.PRESET_TOP_LEFT, Vector2(12, 48))
	_mission_label.modulate = Color(1.0, 0.72, 0.45, 0.95)
	_mission_label.visible = mission != ""
	_wind_label = _make_center_label("WIND 0.0 m/s", 16, Control.PRESET_CENTER_TOP, Vector2(0, 8))
	_ammo_label = _make_label("AMMO 5/5", 16, Control.PRESET_TOP_RIGHT, Vector2(-110, 8))
	_range_label = _make_center_label("--- m", 15, Control.PRESET_CENTER, Vector2(0, 46))
	_zoom_label = _make_center_label("4x", 18, Control.PRESET_CENTER, Vector2(120, -140))
	_zoom_label.visible = false
	_stamp = _make_center_label("", 44, Control.PRESET_CENTER, Vector2(0, 95))
	_stamp.modulate = Color(0.95, 0.85, 0.5)
	_stamp.visible = false
	_center_msg = _make_center_label("", 52, Control.PRESET_CENTER, Vector2(0, -70))
	_center_msg.visible = false
	# RETRYボタン
	_retry_btn = Button.new()
	_retry_btn.text = "RETRY"
	_retry_btn.custom_minimum_size = Vector2(180, 52)
	_retry_btn.add_theme_font_size_override("font_size", 22)
	add_child(_retry_btn)
	_retry_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_retry_btn.position += Vector2(0, 10)
	_retry_btn.visible = false
	_retry_btn.pressed.connect(func() -> void: stage.retry())
	# 操作ボタン（マルチタッチ対応のTouchScreenButton）
	_fire_btn = _make_touch_button("FIRE", 52.0, Color(1.0, 0.55, 0.45, 0.9))
	_fire_btn.pressed.connect(func() -> void: stage.request_fire())
	_scope_btn = _make_touch_button("SCOPE", 44.0, Color(0.65, 0.85, 1.0, 0.9))
	_scope_btn.pressed.connect(func() -> void: rig.cycle_zoom())
	_breath_btn = _make_touch_button("BREATH", 40.0, Color(0.75, 1.0, 0.7, 0.9))
	_breath_btn.pressed.connect(func() -> void: rig.start_breath())
	_breath_btn.released.connect(func() -> void: rig.stop_breath())
	_layout_buttons()
	get_viewport().size_changed.connect(_layout_buttons)


func _make_label(text: String, font_size: int, preset: int, offset: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.set_anchors_and_offsets_preset(preset)
	l.position += offset
	return l


func _make_center_label(text: String, font_size: int, preset: int, offset: Vector2) -> Label:
	var l := _make_label(text, font_size, preset, offset)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	return l


func _make_touch_button(text: String, radius: float, color: Color) -> TouchScreenButton:
	var btn := TouchScreenButton.new()
	# 円形グラデーションテクスチャを生成（半透明の丸ボタン）
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.72, 0.82, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.16),
		Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = int(radius * 2.0)
	tex.height = int(radius * 2.0)
	btn.texture_normal = tex
	btn.modulate = color
	var shape := CircleShape2D.new()
	shape.radius = radius
	btn.shape = shape
	btn.shape_centered = true
	btn.set_meta("radius", radius)
	add_child(btn)
	# ボタン内ラベル
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(radius * 2.0, radius * 2.0)
	l.position = Vector2.ZERO
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(l)
	return btn


func _layout_buttons() -> void:
	var vs := get_viewport().get_visible_rect().size
	_place_button(_fire_btn, Vector2(vs.x - 74.0, vs.y - 74.0))
	_place_button(_scope_btn, Vector2(74.0, vs.y - 66.0))
	_place_button(_breath_btn, Vector2(178.0, vs.y - 96.0))


func _place_button(btn: TouchScreenButton, center: Vector2) -> void:
	var r: float = btn.get_meta("radius")
	btn.position = center - Vector2(r, r)


func _process(delta: float) -> void:
	var replay: bool = stage.is_replay_active()
	var scoped := rig.zoom_stage > 0
	# リプレイ中はシネマ映像の邪魔になる照準UIを消す
	scope.visible = scoped and not replay
	_reticle.visible = not replay
	_markers.visible = not replay
	_reticle.scoped = scoped
	_zoom_label.visible = scoped and not replay
	_zoom_label.text = ["1x", "4x", "8x"][rig.zoom_stage]
	_ammo_label.text = "AMMO %d/%d" % [stage.ammo, stage.max_ammo]
	_targets_label.text = "TARGETS %d/%d" % [stage.hits, stage.hostiles.size()]
	# 風表示（矢印の向きと本数で強さを表現）
	var w: float = stage.wind_speed
	var arrows := ">".repeat(clampi(int(ceil(absf(w) / 1.5)), 1, 4)) if w >= 0.0 \
		else "<".repeat(clampi(int(ceil(absf(w) / 1.5)), 1, 4))
	_wind_label.text = "WIND %s %.1f m/s" % [arrows, absf(w)]
	_wind_label.modulate = Color(1.0, 0.75, 0.4) if absf(w) > 3.5 else Color(0.92, 0.9, 0.85)
	# 測距
	_range_label.text = ("%d m" % int(range_distance)) if range_distance > 0.0 else "--- m"
	# 息止めゲージ
	var frac: float = rig.breath_gauge / SniperCamera.BREATH_MAX
	_breath_arc.visible = scoped and not replay
	_breath_arc.fraction = frac
	_breath_arc.pulse += delta / maxf(Engine.time_scale, 0.001)
	_breath_arc.queue_redraw()
	# 距離スタンプのアニメーション（time_scaleの影響を受けない実時間で動かす）
	if _stamp.visible:
		var rdt := delta / maxf(Engine.time_scale, 0.001)
		_stamp_t += rdt
		var punch := clampf(1.0 - _stamp_t / 0.18, 0.0, 1.0)
		var s := 1.0 + 1.6 * punch
		_stamp.pivot_offset = _stamp.size * 0.5
		_stamp.scale = Vector2(s, s)
		_stamp.modulate.a = 1.0 - clampf((_stamp_t - 2.0) / 0.5, 0.0, 1.0)
		if _stamp_t > 2.5:
			_stamp.visible = false


# --- 射撃フィードバック（ステージから呼ばれる受け口） ---

## 1発撃った：レティクルが開く（bloom）
func on_shot() -> void:
	_reticle.bloom = minf(_reticle.bloom + 0.45, 1.0)


## 命中：ヒットマーカー（HEADSHOTはオレンジ）
func show_hitmark(part: String) -> void:
	_reticle.hitmark_t = DynamicReticle.HITMARK_TIME
	_reticle.hitmark_head = (part == "head")


## オートエイムが標的を捉えた/外した（レティクル色 白⇄オレンジ）
func set_locked(locked: bool) -> void:
	_reticle.locked = locked


## 距離スタンプ表示（例:「342m HIT」「512m HEADSHOT」）
func show_stamp(text: String) -> void:
	_stamp.text = text
	_stamp.reset_size()
	_stamp.modulate.a = 1.0
	_stamp.visible = true
	_stamp_t = 0.0


func show_clear() -> void:
	_center_msg.text = "CLEAR"
	_center_msg.modulate = Color(0.95, 0.85, 0.5)
	_center_msg.visible = true
	_retry_btn.visible = true


## ミッション失敗（弾切れ・民間人の誤射など）
func show_fail(msg: String) -> void:
	_center_msg.text = msg
	_center_msg.modulate = Color(0.95, 0.45, 0.4)
	_center_msg.visible = true
	_retry_btn.visible = true


## 動的レティクル（TABIJIのcombat_hud.gd:56-77を移植）
## 中心点常時＋十字ティック。ギャップ=(スコープ7:通常11)+bloom*12
## bloomは1発+0.45・4.0/s回復。ロックでオレンジ。命中で斜め4本のヒットマーカー
class DynamicReticle:
	extends Control

	const Reticle := preload("res://ui/reticle.gd")
	const COL_RETICLE := Color(1.0, 1.0, 1.0, 0.9)
	const COL_LOCKED := Color(1.0, 0.42, 0.28, 0.95)   # オートエイムが標的を捉えた時
	const HITMARK_TIME := 0.16

	var scoped := false
	var locked := false
	var bloom := 0.0             # 連射でレティクルが開く量(0〜1)
	var hitmark_t := 0.0         # ヒットマーカーの残り表示時間
	var hitmark_head := false    # ヘッドショットか(色を変える)

	func _process(delta: float) -> void:
		if bloom > 0.0:
			bloom = maxf(bloom - 4.0 * delta, 0.0)
		if hitmark_t > 0.0:
			hitmark_t = maxf(hitmark_t - delta, 0.0)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var col := COL_LOCKED if locked else COL_RETICLE
		var gap := (7.0 if scoped else 11.0) + bloom * 12.0
		Reticle.draw_cross(self, c, gap, 9.0, col)
		# ヒットマーカー(命中の一瞬、斜め4本)。ヘッドショットはオレンジ
		if hitmark_t > 0.0:
			var a := hitmark_t / HITMARK_TIME
			var hcol := Color(1.0, 0.62, 0.2, a) if hitmark_head else Color(1.0, 1.0, 1.0, a)
			Reticle.draw_hitmark(self, c, hcol)


## 標的マーカー：生存標的の頭上に▼＋距離ラベルを常時表示する2Dオーバーレイ。
## 「標的がどこにいるか」を一目で分かるようにする（背景に沈まないよう縁取り付き）
class TargetMarkers:
	extends Control

	const COL := Color(1.0, 0.30, 0.22, 0.95)
	const COL_OUTLINE := Color(0.0, 0.0, 0.0, 0.8)
	const FONT_SIZE := 13
	const MARKER_HEIGHT := 2.2   # 標的原点からマーカーまでの高さ(m)

	var stage: SniperStage
	var rig: SniperCamera

	func _process(_delta: float) -> void:
		queue_redraw()

	## 撃つべき標的（悪人）だけに▼を出す。しかも「今その姿が見えている」時だけ。
	## 壁の陰に入ると▼が消えるので、窓に現れた一瞬がそのまま撃つ合図になる。
	func _draw() -> void:
		if stage == null or rig == null or rig.camera == null:
			return
		var cam: Camera3D = rig.camera
		var font := ThemeDB.fallback_font
		for t in stage.hostiles:
			if not is_instance_valid(t) or not t.alive or not t.is_inside_tree():
				continue
			if not stage.has_line_of_sight(t.global_position):
				continue
			var wp: Vector3 = t.global_position + Vector3(0, MARKER_HEIGHT, 0)
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp)
			# ▼（下向き三角。縁取り→本体の順で背景に負けないように）
			var tri := PackedVector2Array([
				sp + Vector2(-8, -14), sp + Vector2(8, -14), sp + Vector2(0, -2)])
			var tri_o := PackedVector2Array([
				sp + Vector2(-10, -16), sp + Vector2(10, -16), sp + Vector2(0, 1)])
			draw_colored_polygon(tri_o, COL_OUTLINE)
			draw_colored_polygon(tri, COL)
			# 距離ラベル（▼の上・中央寄せ）
			var dist := int(round(cam.global_position.distance_to(t.global_position)))
			var text := "%dm" % dist
			var ts := font.get_string_size(
				text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
			var tp := sp + Vector2(-ts.x * 0.5, -20)
			draw_string_outline(font, tp, text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, COL_OUTLINE)
			draw_string(font, tp, text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL)


## 息止め円弧ゲージ（スコープ円の左弧に沿って描画）
class BreathArc:
	extends Control

	var fraction := 1.0
	var pulse := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.44 - 16.0
		var a0 := PI * 0.72
		var a1 := PI * 1.28
		draw_arc(c, r, a0, a1, 40, Color(1, 1, 1, 0.18), 5.0, true)
		if fraction > 0.0:
			var col := Color(0.91, 0.89, 0.85, 0.9)
			if fraction < 0.2:
				col = Color(0.91, 0.3, 0.25, 0.7 + 0.3 * sin(pulse * 12.0))
			draw_arc(c, r, a0, a0 + (a1 - a0) * fraction, 40, col, 5.0, true)
