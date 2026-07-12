class_name Hud
extends CanvasLayer
## HUD：残弾・風・測距・操作ボタン・距離スタンプ・CLEAR/RETRY
## ＋動的レティクル（bloom開閉・照準減速ゾーンの中心点色変化・ヒットマーカー。
##   TABIJIのcombat_hud.gd方式）

const STAMP_HIT_COLOR := Color(0.95, 0.85, 0.5)   # 命中スタンプ（華やかな金色）
const STAMP_MISS_COLOR := Color(0.6, 0.62, 0.65)  # MISSスタンプ（グレー系で差別化）

var stage: SniperStage      # 親ステージ
var mission := ""           # ミッション文（左上に常時表示。空なら出さない）
var rig: SniperCamera
var range_distance := -1.0  # ステージが毎フレーム更新する測距値

var scope: ScopeOverlay

var _reticle: DynamicReticle
var _markers: TargetMarkers
var _enemies_label: Label         # 左上：残り敵数「▼ N」だけ
var _ammo_pips: AmmoPips          # 右下FIREの上：残弾を弾アイコンの列で表示
var _wind_label: Label
var _range_label: Label           # 測距（レティクル脇に小さく）
var _zoom_label: Label            # 倍率（SCOPEボタンの下に「1x」）
var _stamp: Label
var _intro_label: Label           # 開始時だけ中央に出すミッション文（数秒でフェード）
var _result_root: CenterContainer # リザルトカードを画面中央に置く容れ物
var _result_card: PanelContainer  # CLEAR/失敗のカード（タイトル＋ボタン）
var _result_title: Label
var _retry_btn: Button
var _select_btn: Button
var _hide_btn: Button             # CLEAR時のみ：カードを隠して射撃を続ける
var _show_result_chip: Button     # カードを隠している間に出す再表示チップ
var _result_is_clear := false     # 直近のリザルトがCLEAR（勝ち）か
var _menu_btn: Button             # 右上：メニュー「≡」
var _hit_chip: Button             # 右上：命中リプレイ ON/OFF チップ
var _miss_chip: Button            # 右上：ミスリプレイ ON/OFF チップ
var _mode_lines: Label            # モード固有のHUD行（hud_extra().lines の受け皿）
var _mode_gauges: ModeGauges      # モード固有のゲージ（hud_extra().gauges の受け皿）
var _fire_btn: TouchScreenButton
var _scope_btn: TouchScreenButton
# --- デバッグUI（OS.is_debug_build のときだけ生成。DEBUGボタンでパネル開閉） ---
var _debug_btn: Button
var _debug_panel: PanelContainer
var _gravity_toggle: Button
var _spread_toggle: Button
var _traj_toggle: Button
var _stamp_t := -1.0
var _intro_t := 0.0               # 開始からの経過（ミッション文フェード用）


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
	# 動的レティクル（スコープマスクより手前）
	# ※ set_anchors_preset は「現在のレクトを保持したままアンカーだけ変える」ため、
	#   生成直後のサイズ(0,0)のControlに使うと0サイズのまま＝中心(size/2)が左上になる。
	#   必ず set_anchors_and_offsets_preset でオフセットごとFULL_RECTにする。
	_reticle = DynamicReticle.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reticle)
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 左上：残り敵数「▼ N」だけ（長いミッション文・操作ヒントは常時表示しない）
	_enemies_label = _make_label("▼ 0", 20, Control.PRESET_TOP_LEFT, Vector2(14, 8))
	_enemies_label.modulate = Color(1.0, 0.35, 0.28, 0.95)
	_add_outline(_enemies_label, 5)
	# モード固有HUDの共通受け皿（GameMode.hud_extra() のデータを毎フレーム描く）
	_mode_lines = _make_label("", 13, Control.PRESET_TOP_LEFT, Vector2(14, 40))
	_mode_lines.modulate = Color(0.85, 0.92, 1.0, 0.95)
	_add_outline(_mode_lines, 4)
	_mode_lines.visible = false
	_mode_gauges = ModeGauges.new()
	_mode_gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mode_gauges)
	_mode_gauges.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wind_label = _make_center_label("WIND 0.0 m/s", 16, Control.PRESET_CENTER_TOP, Vector2(0, 8))
	_wind_label.visible = Ballistics.WIND_ENABLED
	# 測距：レティクルのすぐ右下に小さく（画面中央の渋滞を避ける）
	_range_label = _make_label("", 15, Control.PRESET_CENTER, Vector2(30, 26))
	_add_outline(_range_label, 4)
	# 倍率：SCOPEボタンの下に「1x」（位置は _layout_buttons で決める）
	_zoom_label = _make_label("1x", 15, Control.PRESET_BOTTOM_LEFT, Vector2.ZERO)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_outline(_zoom_label, 4)
	# 開始時だけ中央に出すミッション文（数秒でフェード。以降は残り敵数だけ）
	_intro_label = _make_center_label(mission, 22, Control.PRESET_CENTER, Vector2(0, -110))
	_intro_label.modulate = Color(1.0, 0.72, 0.45, 0.95)
	_add_outline(_intro_label, 5)
	_intro_label.visible = mission != ""
	_stamp = _make_center_label("", 44, Control.PRESET_CENTER, Vector2(0, 95))
	_stamp.modulate = STAMP_HIT_COLOR
	_stamp.visible = false
	# リザルト（CLEAR/失敗）の中央カード。整った縦積み＝タイトル→RETRY→STAGE SELECT
	_build_result_ui()
	# 右上：メニュー「≡」（コンパクト・半透明）
	_menu_btn = _make_chip("≡", Vector2(44, 34))
	_menu_btn.add_theme_font_size_override("font_size", 22)
	_menu_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_menu_btn.position += Vector2(-56, 10)
	_menu_btn.pressed.connect(func() -> void: GameManager.goto_select())
	# 右上：リプレイ切替チップ2つ（命中／ミス。プレイ中いつでも個別ON/OFF・値は永続化）
	_hit_chip = _make_chip("HIT", Vector2(66, 30))
	_hit_chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hit_chip.position += Vector2(-140, 52)
	_hit_chip.pressed.connect(func() -> void:
		Settings.hit_replay_enabled = not Settings.hit_replay_enabled
		_update_chips())
	_miss_chip = _make_chip("MISS", Vector2(66, 30))
	_miss_chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_miss_chip.position += Vector2(-70, 52)
	_miss_chip.pressed.connect(func() -> void:
		Settings.miss_replay_enabled = not Settings.miss_replay_enabled
		_update_chips())
	_update_chips()
	# 操作ボタン（マルチタッチ対応のTouchScreenButton）。FIREは大きく（狙いながら押しやすく）
	_fire_btn = _make_touch_button("FIRE", 76.0, Color(1.0, 0.4, 0.32, 0.92))
	_fire_btn.pressed.connect(func() -> void: stage.request_fire())
	_scope_btn = _make_touch_button("SCOPE", 46.0, Color(0.65, 0.85, 1.0, 0.9))
	_scope_btn.pressed.connect(func() -> void: rig.cycle_zoom())
	# 残弾ピップ（FIREの上）
	_ammo_pips = AmmoPips.new()
	_ammo_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ammo_pips)
	# デバッグUI（デバッグビルドのみ）：DEBUGボタンでGRAVITY/SPREAD/弾道の切替パネルを開く
	if OS.is_debug_build:
		_build_debug_ui()
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


## ラベルに黒縁取りを付ける（夜景の窓明かりに白文字が沈まないように）
func _add_outline(l: Label, size: int) -> void:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", size)


## 半透明の角丸チップ風ボタン（メニュー・リプレイ切替・デバッグ用）
func _make_chip(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.55)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = Color(0.16, 0.18, 0.22, 0.7)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_child(b)
	return b


## デバッグUIを構築（DEBUGボタン＋開閉パネル。GRAVITY/SPREAD/弾道デバッグをここに集約）。
## リリースビルドでは呼ばれない（プレイヤーには見えない）
func _build_debug_ui() -> void:
	_debug_btn = _make_chip("DEBUG", Vector2(66, 26))
	_debug_btn.modulate = Color(0.7, 1.0, 0.8, 0.85)
	_debug_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_debug_btn.position += Vector2(-140, 92)
	_debug_btn.pressed.connect(func() -> void:
		_debug_panel.visible = not _debug_panel.visible)
	# パネル本体（縦に3ボタン＋操作ヒント）
	_debug_panel = PanelContainer.new()
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.04, 0.05, 0.07, 0.82)
	pstyle.set_corner_radius_all(6)
	pstyle.set_content_margin_all(8)
	_debug_panel.add_theme_stylebox_override("panel", pstyle)
	_debug_panel.visible = false
	add_child(_debug_panel)
	_debug_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_debug_panel.position += Vector2(-206, 124)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_debug_panel.add_child(vb)
	_gravity_toggle = _make_debug_row(vb)
	_gravity_toggle.pressed.connect(func() -> void:
		Settings.gravity_enabled = not Settings.gravity_enabled
		_update_debug_toggles())
	_spread_toggle = _make_debug_row(vb)
	_spread_toggle.pressed.connect(func() -> void:
		Settings.spread_enabled = not Settings.spread_enabled
		_update_debug_toggles())
	_traj_toggle = _make_debug_row(vb)
	_traj_toggle.pressed.connect(func() -> void:
		stage.debug.toggle_enabled()
		_update_debug_toggles())
	var hint := Label.new()
	hint.text = "TRAJ: F3 / VIEW: TAB"
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(1, 1, 1, 0.5)
	vb.add_child(hint)
	_update_debug_toggles()


## デバッグパネル内の1行ボタン（幅そろえ・左寄せ）
func _make_debug_row(vb: VBoxContainer) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(180, 24)
	b.add_theme_font_size_override("font_size", 11)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(b)
	return b


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
	# self_modulate はこのノードのテクスチャだけを着色し、子ラベルには波及しない
	# （modulate だと FIRE 文字まで暗く染まって読めなくなる）
	btn.self_modulate = color
	var shape := CircleShape2D.new()
	shape.radius = radius
	btn.shape = shape
	btn.shape_centered = true
	btn.set_meta("radius", radius)
	add_child(btn)
	# ボタン内ラベル（白＋黒縁取りではっきり）
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20 if radius >= 70.0 else 14)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(radius * 2.0, radius * 2.0)
	l.position = Vector2.ZERO
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(l)
	return btn


func _layout_buttons() -> void:
	var vs := get_viewport().get_visible_rect().size
	var fire_c := Vector2(vs.x - 100.0, vs.y - 100.0)
	_place_button(_fire_btn, fire_c)
	var scope_c := Vector2(78.0, vs.y - 84.0)
	_place_button(_scope_btn, scope_c)
	# 倍率ラベルはSCOPEボタンの真下
	if _zoom_label != null:
		_zoom_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_zoom_label.position = scope_c + Vector2(-20, 52)
		_zoom_label.size = Vector2(40, 20)
	# 残弾ピップはFIREボタンの真上（受け皿トレイぶんの余白を見て少し上げる）
	if _ammo_pips != null:
		_ammo_pips.size = Vector2((AmmoPips.PIP_COUNT - 1) * AmmoPips.STEP + 9.0, 20)
		_ammo_pips.position = Vector2(fire_c.x - _ammo_pips.size.x * 0.5,
			fire_c.y - 76.0 - 34.0)
		_ammo_pips.queue_redraw()


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
	_enemies_label.visible = not replay
	_ammo_pips.visible = not replay
	_range_label.visible = not replay
	_menu_btn.visible = not replay
	_hit_chip.visible = not replay
	_miss_chip.visible = not replay
	# 自由射撃の再表示チップはリプレイ中だけ隠す（カードが隠れている間のみ出す）
	if _show_result_chip.visible or replay:
		_show_result_chip.visible = _result_root != null and not _result_root.visible \
			and stage.game_over and not replay
	if _debug_btn != null:
		_debug_btn.visible = not replay
		if replay:
			_debug_panel.visible = false
	# モード固有HUD（hud_extra）を反映
	var extra: Dictionary = stage.mode.hud_extra() if stage.mode != null else {}
	var lines: Array = extra.get("lines", [])
	_mode_lines.visible = not lines.is_empty() and not replay
	_mode_lines.text = "\n".join(PackedStringArray(lines))
	_mode_gauges.gauges = extra.get("gauges", [])
	_mode_gauges.visible = not _mode_gauges.gauges.is_empty() and not replay
	_mode_gauges.queue_redraw()
	# 倍率表示は連続値（ピンチズーム対応。「4.0x」→「4x」に整形）
	_zoom_label.text = String.num(rig.magnification, 1).trim_suffix(".0") + "x"
	# 残弾ピップ・残り敵数
	_ammo_pips.set_ammo(stage.ammo)
	var remaining: int = maxi(stage.hostiles.size() - stage.hits, 0)
	_enemies_label.text = "▼ %d" % remaining
	# 開始時のミッション文フェード（3秒表示→0.8秒でフェードアウト）
	if _intro_label.visible:
		_intro_t += delta
		_intro_label.modulate.a = 0.95 - clampf((_intro_t - 3.0) / 0.8, 0.0, 0.95)
		if _intro_t > 3.8:
			_intro_label.visible = false
	# 風表示（矢印の向きと本数で強さを表現）。風が弾に効く設定の時だけ
	if _wind_label.visible:
		var w: float = stage.wind_speed
		var arrows := ">".repeat(clampi(int(ceil(absf(w) / 1.5)), 1, 4)) if w >= 0.0 \
			else "<".repeat(clampi(int(ceil(absf(w) / 1.5)), 1, 4))
		_wind_label.text = "WIND %s %.1f m/s" % [arrows, absf(w)]
		_wind_label.modulate = Color(1.0, 0.75, 0.4) if absf(w) > 3.5 else Color(0.92, 0.9, 0.85)
	# 測距（レティクル脇。有効な時だけ）
	_range_label.text = ("%d m" % int(range_distance)) if range_distance > 0.0 else ""
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


## 照準減速ゾーンに入った/出た（レティクル中心点だけ控えめに色づく。
## 旧オートエイムの「オレンジ＝撃てば当たる」保証ではないため、十字は白のまま）
func set_sticky(active: bool) -> void:
	_reticle.sticky = active


## 距離スタンプ表示（例:「342m HIT」「512m HEADSHOT」）
func show_stamp(text: String, color := STAMP_HIT_COLOR) -> void:
	_stamp.text = text
	_stamp.reset_size()
	_stamp.modulate = color
	_stamp.modulate.a = 1.0
	_stamp.visible = true
	_stamp_t = 0.0


## ミスリプレイの余韻用「MISS」スタンプ（距離スタンプの代わり。グレー系で命中と差別化）
func show_miss_stamp() -> void:
	show_stamp("MISS", STAMP_MISS_COLOR)


## リプレイ切替チップ（HIT/MISS）の表記と色を現在の設定に合わせる。
## ●=ON（明るい）／○=OFF（暗い）で状態を一目で
func _update_chips() -> void:
	var on := Color(0.75, 0.95, 1.0, 0.95)
	var off := Color(1, 1, 1, 0.4)
	_hit_chip.text = "HIT %s" % ("●" if Settings.hit_replay_enabled else "○")
	_hit_chip.modulate = on if Settings.hit_replay_enabled else off
	_miss_chip.text = "MISS %s" % ("●" if Settings.miss_replay_enabled else "○")
	_miss_chip.modulate = on if Settings.miss_replay_enabled else off


## デバッグパネル内トグルの表記（GRAVITY/SPREAD/TRAJ）
func _update_debug_toggles() -> void:
	if _gravity_toggle == null:
		return
	_gravity_toggle.text = "GRAVITY: %s" % ("ON" if Settings.gravity_enabled else "OFF")
	_spread_toggle.text = "SPREAD: %s" % ("ON" if Settings.spread_enabled else "OFF")
	var traj_on: bool = stage.debug != null and stage.debug.enabled
	_traj_toggle.text = "TRAJECTORY: %s" % ("ON" if traj_on else "OFF")


## リザルトの中央カード（タイトル＋RETRY＋STAGE SELECT＋クリア時の「隠す」）。
## 縦に等間隔で積んだ角丸カード＝ボタンの並びがいびつにならない
func _build_result_ui() -> void:
	_result_root = CenterContainer.new()
	_result_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_result_root)
	_result_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_root.visible = false

	_result_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(22)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = Color(1, 1, 1, 0.10)
	_result_card.add_theme_stylebox_override("panel", sb)
	_result_root.add_child(_result_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_card.add_child(vb)

	_result_title = Label.new()
	_result_title.add_theme_font_size_override("font_size", 44)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_outline(_result_title, 5)
	vb.add_child(_result_title)

	_retry_btn = _make_result_button("RETRY", 22)
	_retry_btn.pressed.connect(func() -> void: stage.retry())
	vb.add_child(_retry_btn)

	_select_btn = _make_result_button("STAGE SELECT", 18)
	_select_btn.pressed.connect(func() -> void: GameManager.goto_select())
	vb.add_child(_select_btn)

	# クリア時のみ：カードを隠して射撃を続ける（隠しアイテム探し用）
	_hide_btn = _make_result_button("▽ 隠して射撃を続ける", 15)
	_hide_btn.pressed.connect(_hide_result)
	vb.add_child(_hide_btn)

	# 隠している間に出す再表示チップ（画面上中央）
	_show_result_chip = _make_chip("≡ 結果", Vector2(96, 34))
	_show_result_chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_show_result_chip.position += Vector2(-48, 14)
	_show_result_chip.pressed.connect(_show_result_again)
	_show_result_chip.visible = false


## リザルトカード内の統一ボタン（横幅そろえ・角丸）
func _make_result_button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 48)
	b.add_theme_font_size_override("font_size", font_size)
	return b


func show_clear() -> void:
	_result_is_clear = true
	_result_title.text = "CLEAR"
	_result_title.add_theme_color_override("font_color", Color(0.98, 0.88, 0.5))
	_hide_btn.visible = true
	_result_root.visible = true
	_show_result_chip.visible = false


## ミッション失敗（弾切れ・民間人の誤射など）
func show_fail(msg: String) -> void:
	_result_is_clear = false
	_result_title.text = msg
	_result_title.add_theme_color_override("font_color", Color(0.98, 0.5, 0.42))
	_hide_btn.visible = false   # 失敗時は「続ける」を出さない
	_result_root.visible = true
	_show_result_chip.visible = false


## カードを隠してステージ上の自由射撃へ（クリア後の隠しアイテム探し）
func _hide_result() -> void:
	_result_root.visible = false
	_show_result_chip.visible = true
	if stage != null:
		stage.set_free_roam(true)


## 隠したカードを再表示（自由射撃を終了してリザルトへ戻る）
func _show_result_again() -> void:
	_result_root.visible = true
	_show_result_chip.visible = false
	if stage != null:
		stage.set_free_roam(false)


## 残弾ピップ：弾アイコンの横一列で残弾を表す（数字の「AMMO 100/100」を廃止）。
## 表示は最大 PIP_COUNT 個。ammoがそれ以上なら全部満杯、終盤に減ると右から空になる。
## ※ 将来「弾切れで自動リロード」の弾倉制になっても、そのままの見た目で使える設計。
class AmmoPips:
	extends Control

	const PIP_COUNT := 8       # 表示する弾アイコンの数
	const STEP := 16.0         # アイコン間の横ピッチ(px)
	const PAD := 8.0           # 受け皿トレイの左右・上下パディング
	const COL_FULL := Color(1.0, 0.92, 0.72, 0.98)   # 実弾（真鍮＋弾頭）
	const COL_EMPTY := Color(1, 1, 1, 0.18)          # 撃った分（空スロット）
	const COL_TRAY := Color(0.0, 0.0, 0.0, 0.4)      # 受け皿（背景に負けないための暗い下地）

	var _ammo := 0

	func set_ammo(a: int) -> void:
		if a != _ammo:
			_ammo = a
			queue_redraw()

	func _draw() -> void:
		# 受け皿（暗い角丸トレイ）＝どんな背景でも弾が読める
		var tray := Rect2(Vector2(-PAD, -PAD), size + Vector2(PAD * 2.0, PAD * 2.0))
		draw_rect(tray, COL_TRAY, true)
		var full := clampi(_ammo, 0, PIP_COUNT)
		for i in PIP_COUNT:
			_draw_bullet(Vector2(i * STEP, 0), COL_FULL if i < full else COL_EMPTY)

	## 弾1発（下＝真鍮ケース、上＝尖った弾頭）を縦長で描く
	func _draw_bullet(o: Vector2, col: Color) -> void:
		var w := 9.0
		var case_h := 13.0
		var tip_h := 7.0
		draw_rect(Rect2(o + Vector2(0, tip_h), Vector2(w, case_h)), col)  # ケース
		draw_colored_polygon(PackedVector2Array([                          # 弾頭（三角）
			o + Vector2(0, tip_h), o + Vector2(w, tip_h), o + Vector2(w * 0.5, 0)]), col)


## モード固有ゲージの共通描画（hud_extra().gauges）。画面下中央に横バーを縦に並べる。
## 形式: [{"label": String, "value": 0..1, "color": Color}, ...]
class ModeGauges:
	extends Control

	const BAR_W := 240.0
	const BAR_H := 10.0
	const GAP := 22.0

	var gauges: Array = []

	func _draw() -> void:
		if gauges.is_empty():
			return
		var font := ThemeDB.fallback_font
		var cx := size.x * 0.5
		var y := size.y - 150.0 - GAP * float(gauges.size() - 1)
		for g in gauges:
			var label: String = g.get("label", "")
			var value: float = clampf(g.get("value", 0.0), 0.0, 1.0)
			var col: Color = g.get("color", Color(1, 1, 1))
			var rect := Rect2(cx - BAR_W * 0.5, y, BAR_W, BAR_H)
			draw_rect(rect, Color(1, 1, 1, 0.15))
			draw_rect(Rect2(rect.position, Vector2(BAR_W * value, BAR_H)), col)
			if label != "":
				draw_string(font, rect.position + Vector2(0, -4), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))
			y += GAP


## 動的レティクル（TABIJIのcombat_hud.gd:56-77を移植）
## 中心点常時＋十字ティック。ギャップ=(スコープ7:通常11)+bloom*12
## bloomは1発+0.45・4.0/s回復。照準減速ゾーン内は中心点だけ控えめにオレンジ。
## 命中で斜め4本のヒットマーカー
class DynamicReticle:
	extends Control

	const Reticle := preload("res://ui/reticle.gd")
	const COL_RETICLE := Color(1.0, 1.0, 1.0, 0.9)
	const COL_STICKY_DOT := Color(1.0, 0.62, 0.3, 0.95)  # 減速ゾーン内の中心点(控えめ)
	const HITMARK_TIME := 0.16
	# スコープ時の実銃風レティクル：細い黒芯＋うっすら白ハロー（明背景で黒く見え、
	# 暗背景でも沈まない）。中心は開けて標的・弾道を隠さない
	const SCOPE_CORE := Color(0.04, 0.04, 0.04, 0.95)    # ほぼ黒の細い芯
	const SCOPE_HALO := Color(1.0, 1.0, 1.0, 0.35)       # 芯を薄く縁取る白ハロー
	const SCOPE_CORE_W := 1.3
	const SCOPE_HALO_W := 2.7
	const SCOPE_GAP := 6.0                               # 中心の開き（塗りドットなし）
	const SCOPE_TICK := 34.0                             # 十字の腕の長さ（細く長い）

	var scoped := false
	var sticky := false          # 照準減速ゾーン内か(命中保証の意味はない)
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
		if scoped:
			# スコープ中：実銃風の細い十字。中心は開け（ドットなし）て標的・弾道を隠さない。
			# 減速ゾーン内だけ、中心に小さな色つき点をうっすら出す（控えめな合図）
			var gap := SCOPE_GAP + bloom * 12.0
			Reticle.draw_cross(self, c, gap, SCOPE_TICK, SCOPE_CORE,
				SCOPE_HALO, SCOPE_CORE_W, SCOPE_HALO_W, 0.0)
			if sticky:
				draw_circle(c, 2.0, COL_STICKY_DOT)
		else:
			# 腰だめ：はっきりした白十字＋中心点（戦闘用レティクル）
			var gap := 11.0 + bloom * 12.0
			var dot := COL_STICKY_DOT if sticky else COL_RETICLE
			Reticle.draw_cross(self, c, gap, 9.0, COL_RETICLE,
				Reticle.OUTLINE, Reticle.CORE_W, Reticle.OUTLINE_W, Reticle.DOT_CORE, dot)
		# ヒットマーカー(命中の一瞬、斜め4本)。ヘッドショットはオレンジ
		if hitmark_t > 0.0:
			var a := hitmark_t / HITMARK_TIME
			var hcol := Color(1.0, 0.62, 0.2, a) if hitmark_head else Color(1.0, 1.0, 1.0, a)
			Reticle.draw_hitmark(self, c, hcol)


## 標的マーカー：生存標的の頭上に▼を常時表示する2Dオーバーレイ。
## 「標的がどこにいるか」を一目で分かるようにする（背景に沈まないよう縁取り付き）。
## 距離のm表示は廃止（2026-07-10ユーザー決定。距離は画面中央の測距表示で足りる）
class TargetMarkers:
	extends Control

	const COL := Color(1.0, 0.30, 0.22, 0.95)
	const COL_OUTLINE := Color(0.0, 0.0, 0.0, 0.8)
	const MARKER_HEIGHT := 2.2   # 標的原点からマーカーまでの高さ(m)

	var stage: SniperStage
	var rig: SniperCamera

	func _process(_delta: float) -> void:
		queue_redraw()

	## 撃つべき標的（悪人）に▼を出す。位置は常に示す。
	## 壁の陰に入っている間は▼を消さず半透明にする（見えている時は不透明）＝
	## 「どこにいるか」は常に分かり、「今撃てるか」は濃さで分かる。
	const SEEN_ALPHA := 1.0        # 見えている時の濃さ
	const HIDDEN_ALPHA := 0.4      # 物陰に隠れている時の濃さ（半透明）

	func _draw() -> void:
		if stage == null or rig == null or rig.camera == null:
			return
		var cam: Camera3D = rig.camera
		for t in stage.hostiles:
			if not is_instance_valid(t) or not t.alive or not t.is_inside_tree():
				continue
			var wp: Vector3 = t.global_position + Vector3(0, MARKER_HEIGHT, 0)
			if cam.is_position_behind(wp):
				continue   # 画面の後ろ＝そもそも映せない標的だけスキップ
			# 遮蔽されている間は消さず半透明に
			var a := SEEN_ALPHA if stage.has_line_of_sight(t.global_position) else HIDDEN_ALPHA
			var sp := cam.unproject_position(wp)
			# ▼（下向き三角。縁取り→本体の順で背景に負けないように）
			var tri := PackedVector2Array([
				sp + Vector2(-8, -14), sp + Vector2(8, -14), sp + Vector2(0, -2)])
			var tri_o := PackedVector2Array([
				sp + Vector2(-10, -16), sp + Vector2(10, -16), sp + Vector2(0, 1)])
			draw_colored_polygon(tri_o, Color(COL_OUTLINE.r, COL_OUTLINE.g, COL_OUTLINE.b, COL_OUTLINE.a * a))
			draw_colored_polygon(tri, Color(COL.r, COL.g, COL.b, COL.a * a))
