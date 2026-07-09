class_name Hud
extends CanvasLayer
## HUD：残弾・風・測距・息止め円弧ゲージ・操作ボタン・距離スタンプ・CLEAR/RETRY

const AMMO_MAX := 5

var stage: Node3D           # test_range（親ステージ）
var rig: SniperCamera
var range_distance := -1.0  # ステージが毎フレーム更新する測距値

var scope: ScopeOverlay

var _ammo_label: Label
var _wind_label: Label
var _targets_label: Label
var _hint_label: Label
var _range_label: Label
var _zoom_label: Label
var _crosshair: Label
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
	# 息止め円弧ゲージ
	_breath_arc = BreathArc.new()
	_breath_arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_breath_arc)
	_breath_arc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_breath_arc.visible = false
	# ラベル類
	_targets_label = _make_label("TARGETS 0/0", 15, Control.PRESET_TOP_LEFT, Vector2(12, 8))
	_hint_label = _make_label(
		"CLICK: CAPTURE MOUSE / AIM: MOUSE / R-CLICK or WHEEL: SCOPE / L-CLICK: FIRE / SPACE: BREATH / ESC: RELEASE",
		10, Control.PRESET_TOP_LEFT, Vector2(12, 30))
	_hint_label.modulate = Color(1, 1, 1, 0.55)
	_wind_label = _make_center_label("WIND 0.0 m/s", 16, Control.PRESET_CENTER_TOP, Vector2(0, 8))
	_ammo_label = _make_label("AMMO 5/5", 16, Control.PRESET_TOP_RIGHT, Vector2(-110, 8))
	_range_label = _make_center_label("--- m", 15, Control.PRESET_CENTER, Vector2(0, 46))
	_zoom_label = _make_center_label("4x", 18, Control.PRESET_CENTER, Vector2(120, -140))
	_zoom_label.visible = false
	_crosshair = _make_center_label("+", 20, Control.PRESET_CENTER, Vector2.ZERO)
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
	var scoped := rig.zoom_stage > 0
	scope.visible = scoped
	_crosshair.visible = not scoped
	_zoom_label.visible = scoped
	_zoom_label.text = ["1x", "4x", "8x"][rig.zoom_stage]
	_ammo_label.text = "AMMO %d/%d" % [stage.ammo, AMMO_MAX]
	_targets_label.text = "TARGETS %d/%d" % [stage.hits, stage.targets.size()]
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
	_breath_arc.visible = scoped
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


func show_retry() -> void:
	_center_msg.text = "AMMO OUT"
	_center_msg.modulate = Color(0.95, 0.45, 0.4)
	_center_msg.visible = true
	_retry_btn.visible = true


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
