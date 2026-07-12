extends Control
## 選択画面（メインシーン）v2 —「TACTICAL OPS」デザイン（2026-07-12ユーザー承認モック準拠）。
## 2段構成：①モードを選ぶ → ②対応ステージを選ぶ。フロー・数字キー・ESC/BACKは従来どおり。
##
## デザインの作り：外部画像素材は使わず、
##   ・背景/カードのアート＝実ゲーム画面のキャプチャ（ui/thumbs/。tools/capture_thumbs で再生成可）
##   ・金の枠・コーナーブラケット・レティクルロゴ・六角アイコン等＝すべてControlのコード描画
## 新ステージを足すときは STAGES 台帳に1行＋ tools/capture_thumbs 再実行でサムネイルが揃う。

const GOLD := Color(0.85, 0.72, 0.42)
const GOLD_BRIGHT := Color(1.0, 0.88, 0.55)
const SILVER := Color(0.86, 0.88, 0.92)
const TEXT_DIM := Color(1, 1, 1, 0.55)
const CARD_BG := Color(0.045, 0.06, 0.10, 0.90)
const NAVY := Color(0.015, 0.025, 0.05)

## モードカードの背景アート（モードid → ステージキャプチャ名）
const MODE_ART := {"precision": "city_stage", "engage": "harbor_stage", "horde": "desert_stage"}

var _mode_idx := -1               # -1=モード選択画面 / 0..=そのモードのステージ選択画面
var _visible_stages: Array = []   # 現在表示中のステージ台帳インデックス列
var _content: Control             # カード群（画面切替のたびに作り直す）
var _sub: BracketText             # 「SELECT MODE / SELECT STAGE — X」
var _notice: Label                # 「準備中」表示
var _back_btn: Button             # 左上の戻る（ステージ画面のみ）
var _bottom: BottomBar            # 下中央のバー（TAP TO SELECT / BACK）
var _side_deco: Array[Control] = []  # ステージ画面だけの飾り（座標・STATUS等）


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_chrome()
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_notice = Label.new()
	_notice.add_theme_font_size_override("font_size", 12)
	_notice.modulate = Color(1.0, 0.72, 0.45, 0.95)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_notice)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_notice.position += Vector2(0, -76)
	_show_modes()


# ---------------------------------------------------------------- 背景・共通装飾

func _thumb(base_name: String) -> Texture2D:
	var path := "res://ui/thumbs/%s.png" % base_name
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = NAVY
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 背景＝夜の都市の実キャプチャ（青く沈めて文字を立てる）
	var art := TextureRect.new()
	art.texture = _thumb("city_stage")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(0.55, 0.62, 0.80, 1.0)
	add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.045, 0.66)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ビネット（周辺減光）
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.6)])
	var vt := GradientTexture2D.new()
	vt.gradient = grad
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(0.5, -0.15)
	vt.width = 256
	vt.height = 256
	var vig := TextureRect.new()
	vig.texture = vt
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_chrome() -> void:
	# タイトルロゴ（レティクルの「O」＋銀の欧文＋金の下線）
	var logo := TitleLogo.new()
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	logo.offset_top = 14
	logo.offset_bottom = 66
	# サブタイトル（コーナーブラケット付き）
	_sub = BracketText.new()
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub)
	_sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_sub.offset_top = 70
	_sub.offset_bottom = 96
	# 右上の飾り（TACTICAL OPS // 01-A ＋ 金バー）
	var ops := OpsBadge.new()
	ops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ops)
	ops.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	ops.offset_left = -320
	ops.offset_right = -10
	ops.offset_top = 8
	ops.offset_bottom = 40
	# 左上のBACK（ステージ画面のみ表示）
	_back_btn = Button.new()
	_back_btn.text = "←  BACK"
	_back_btn.add_theme_font_size_override("font_size", 13)
	_back_btn.add_theme_stylebox_override("normal", _panel_style(1))
	_back_btn.add_theme_stylebox_override("hover", _panel_style(1))
	_back_btn.add_theme_stylebox_override("pressed", _panel_style(2, GOLD_BRIGHT))
	_back_btn.custom_minimum_size = Vector2(96, 32)
	add_child(_back_btn)
	_back_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_back_btn.position = Vector2(10, 8)
	_back_btn.pressed.connect(_show_modes)
	# 下中央のバー
	_bottom = BottomBar.new()
	add_child(_bottom)
	_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom.offset_top = -52
	_bottom.offset_bottom = -10
	_bottom.pressed.connect(func() -> void:
		if _mode_idx >= 0:
			_show_modes())
	# ステージ画面だけの飾りテキスト（座標・STATUS・SIGNAL）
	for spec in [
		["COORDINATE\n35.6895° N\n139.6917° E", Control.PRESET_TOP_LEFT, Vector2(12, 120)],
		["STATUS\nSTANDBY", Control.PRESET_BOTTOM_LEFT, Vector2(12, -54)],
		["SIGNAL\nSTRONG ▮▮▮▮", Control.PRESET_BOTTOM_RIGHT, Vector2(-118, -54)],
	]:
		var l := Label.new()
		l.text = spec[0]
		l.add_theme_font_size_override("font_size", 9)
		l.modulate = Color(0.75, 0.8, 0.9, 0.45)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		l.set_anchors_and_offsets_preset(spec[1])
		l.position += spec[2]
		_side_deco.append(l)


## カード・ボタン共通の枠スタイル（暗い半透明＋金の縁）
func _panel_style(border: int, border_col := Color(GOLD.r, GOLD.g, GOLD.b, 0.45)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = border_col
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	return sb


# ---------------------------------------------------------------- 画面の組み立て

func _clear_content() -> void:
	for c in _content.get_children():
		c.queue_free()
	_notice.text = " "


## 1段目：モード選択（3枚のカード）
func _show_modes() -> void:
	_mode_idx = -1
	_clear_content()
	_sub.text = "SELECT MODE"
	_sub.queue_redraw()
	_back_btn.visible = false
	_bottom.text = "TAP TO SELECT"
	_bottom.queue_redraw()
	for l in _side_deco:
		l.visible = false

	var center := CenterContainer.new()
	_content.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 100
	center.offset_bottom = -56
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	center.add_child(row)

	for i in GameManager.MODES.size():
		var m: Dictionary = GameManager.MODES[i]
		var card := _make_card(Vector2(236, 300))
		card.modulate = Color(1, 1, 1, 1.0 if m.ready else 0.45)
		card.pressed.connect(_on_mode_pressed.bind(i))
		row.add_child(card)
		# カードの中身（アート・六角アイコン・名前・説明）
		var art := TextureRect.new()
		var art_name: String = MODE_ART.get(m.id, "city_stage")
		art.texture = _thumb(art_name)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(0.78, 0.84, 0.98, 0.9)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.offset_top = 6
		art.offset_bottom = -114
		art.offset_left = 6
		art.offset_right = -6
		var fade := ColorRect.new()
		fade.color = Color(0.02, 0.035, 0.07, 0.42)
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(fade)
		fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fade.offset_top = 6
		fade.offset_bottom = -114
		fade.offset_left = 6
		fade.offset_right = -6
		var hex := HexIcon.new()
		hex.kind = i
		hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hex)
		hex.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		hex.offset_left = -34
		hex.offset_right = 34
		hex.offset_top = 22
		hex.offset_bottom = 90
		var name_l := Label.new()
		name_l.text = "%d. %s" % [i + 1, m.name]
		name_l.add_theme_font_size_override("font_size", 21)
		name_l.modulate = GOLD_BRIGHT
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_l)
		name_l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		name_l.offset_top = -106
		name_l.offset_bottom = -78
		var desc := Label.new()
		desc.text = m.desc + ("\n（準備中）" if not m.ready else "")
		desc.add_theme_font_size_override("font_size", 12)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(desc)
		desc.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		desc.offset_top = -74
		desc.offset_bottom = -14
		desc.offset_left = 12
		desc.offset_right = -12
		var frame := CornerFrame.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(frame)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 2段目：選んだモードに対応するステージ選択（ミッションファイル風カードの2列グリッド）
func _show_stages(mode_idx: int) -> void:
	_mode_idx = mode_idx
	_clear_content()
	_sub.text = "SELECT STAGE — %s" % GameManager.MODES[mode_idx].name
	_sub.queue_redraw()
	_back_btn.visible = true
	_bottom.text = "BACK"
	_bottom.queue_redraw()
	for l in _side_deco:
		l.visible = true

	_visible_stages.clear()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 102
	scroll.offset_bottom = -58
	scroll.offset_left = 92
	scroll.offset_right = -92
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	for i in GameManager.STAGES.size():
		var st: Dictionary = GameManager.STAGES[i]
		if not (mode_idx in st.modes):
			continue  # このモードに対応しないステージは出さない
		_visible_stages.append(i)
		var n := _visible_stages.size()
		var card := _make_card(Vector2(329, 148))
		card.pressed.connect(_on_stage_pressed.bind(i))
		grid.add_child(card)
		# 偵察写真（左）
		var shot := TextureRect.new()
		shot.texture = _thumb(String(st.scene).get_file().get_basename())
		shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(shot)
		shot.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		shot.offset_left = 6
		shot.offset_right = 128
		shot.offset_top = 6
		shot.offset_bottom = -6
		# ファイル見出し（右）
		var file_l := Label.new()
		file_l.text = "MISSION FILE                // %02d" % n
		file_l.add_theme_font_size_override("font_size", 9)
		file_l.modulate = TEXT_DIM
		file_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(file_l)
		file_l.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		file_l.position = Vector2(140, 12)
		var name_l := Label.new()
		name_l.text = "%d. %s" % [n, st.name]
		name_l.add_theme_font_size_override("font_size", 15)
		name_l.modulate = GOLD_BRIGHT
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_l)
		name_l.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		name_l.position = Vector2(140, 28)
		var recon := Label.new()
		recon.text = "◈ RECON"
		recon.add_theme_font_size_override("font_size", 9)
		recon.modulate = Color(GOLD.r, GOLD.g, GOLD.b, 0.75)
		recon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(recon)
		recon.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		recon.position = Vector2(140, 50)
		var desc := Label.new()
		desc.text = st.desc
		desc.add_theme_font_size_override("font_size", 11)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(desc)
		desc.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		desc.position = Vector2(140, 68)
		desc.size = Vector2(180, 68)
		var frame := CornerFrame.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(frame)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## カードの土台（枠スタイル付きButton。中身は呼び出し側が重ねる）
func _make_card(min_size: Vector2) -> Button:
	var card := Button.new()
	card.custom_minimum_size = min_size
	card.add_theme_stylebox_override("normal", _panel_style(1))
	card.add_theme_stylebox_override("hover", _panel_style(1, Color(GOLD.r, GOLD.g, GOLD.b, 0.8)))
	card.add_theme_stylebox_override("pressed", _panel_style(2, GOLD_BRIGHT))
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return card


# ---------------------------------------------------------------- 入力

func _on_mode_pressed(i: int) -> void:
	if not GameManager.MODES[i].ready:
		_notice.text = "このモードは準備中です"
		return
	_show_stages(i)


func _on_stage_pressed(stage_idx: int) -> void:
	GameManager.goto_stage(stage_idx, _mode_idx)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE and _mode_idx >= 0:
		_show_modes()
		return
	var n: int = event.keycode - KEY_1
	if _mode_idx < 0:
		if n >= 0 and n < GameManager.MODES.size():
			_on_mode_pressed(n)
	else:
		if n >= 0 and n < _visible_stages.size():
			_on_stage_pressed(_visible_stages[n])


# ---------------------------------------------------------------- 装飾パーツ（コード描画）

## タイトルロゴ：「O」を金のレティクルに置き換えた銀の欧文＋金の下線とダイヤ
class TitleLogo:
	extends Control
	const TXT := "NE SHOT AHEAD"

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var fs := 36
		var tw := font.get_string_size(TXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := 16.0
		var gap := 7.0
		var total := r * 2.0 + gap + tw
		var x0 := (size.x - total) * 0.5
		var cy := size.y * 0.5
		var c := Vector2(x0 + r, cy)
		# レティクルの「O」（外輪・内輪・十字ティック）
		draw_arc(c, r, 0, TAU, 48, Color(0.85, 0.72, 0.42), 1.8, true)
		draw_arc(c, r * 0.52, 0, TAU, 40, Color(1.0, 0.88, 0.55), 4.0, true)
		for k in 4:
			var a := float(k) * PI * 0.5
			var dv := Vector2(cos(a), sin(a))
			draw_line(c + dv * (r * 0.66), c + dv * (r + 4.0), Color(0.85, 0.72, 0.42), 1.4, true)
		# 銀の欧文（わずかに沈む影で金属感）
		var pen := Vector2(x0 + r * 2.0 + gap, cy + fs * 0.36)
		draw_string(font, pen + Vector2(0, 1.5), TXT,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.55))
		draw_string(font, pen, TXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.86, 0.88, 0.92))
		# 下線＋中央のダイヤ
		var ly := cy + fs * 0.58
		var half := total * 0.62
		draw_line(Vector2(size.x * 0.5 - half, ly), Vector2(size.x * 0.5 + half, ly),
			Color(0.85, 0.72, 0.42, 0.45), 1.0, true)
		var dc := Vector2(size.x * 0.5, ly)
		draw_colored_polygon(PackedVector2Array([
			dc + Vector2(0, -3.5), dc + Vector2(5, 0), dc + Vector2(0, 3.5), dc + Vector2(-5, 0)]),
			Color(1.0, 0.88, 0.55))


## コーナーブラケット付きの見出しテキスト（[ SELECT MODE ] 風）
class BracketText:
	extends Control
	var text := ""

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var fs := 14
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		draw_string(font, Vector2(cx - tw * 0.5, cy + fs * 0.36), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.72, 0.42))
		var gold := Color(0.85, 0.72, 0.42, 0.8)
		var hw := tw * 0.5 + 16.0
		var hh := 9.0
		var arm := 6.0
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := Vector2(cx + sx * hw, cy + sy * hh)
				draw_line(corner, corner + Vector2(-sx * arm, 0), gold, 1.2, true)
				draw_line(corner, corner + Vector2(0, -sy * arm), gold, 1.2, true)


## 右上の「◎ TACTICAL OPS | // 01-A ＋金バー」飾り
class OpsBadge:
	extends Control

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var dim := Color(0.75, 0.8, 0.9, 0.6)
		var gold := Color(0.85, 0.72, 0.42)
		var cy := size.y * 0.5
		# 小さなレティクル
		var c := Vector2(size.x - 300, cy)
		draw_arc(c, 6.0, 0, TAU, 24, dim, 1.2, true)
		draw_circle(c, 1.6, dim)
		draw_string(font, Vector2(size.x - 286, cy + 4), "TACTICAL OPS",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)
		draw_line(Vector2(size.x - 172, cy - 8), Vector2(size.x - 172, cy + 8),
			Color(1, 1, 1, 0.25), 1.0)
		draw_string(font, Vector2(size.x - 160, cy + 4), "// 01-A",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)
		# 金の斜めバー3本
		for k in 3:
			var x: float = size.x - 88.0 + float(k) * 26.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(x + 5, cy - 6), Vector2(x + 22, cy - 6),
				Vector2(x + 17, cy + 6), Vector2(x, cy + 6)]), gold)


## モードの六角アイコン（0=精密:弾丸レティクル 1=応戦:盾 2=物量:三連レティクル）
class HexIcon:
	extends Control
	var kind := 0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		var gold := Color(0.85, 0.72, 0.42)
		var bright := Color(1.0, 0.88, 0.55)
		# 六角形（暗い面＋金の縁）
		var pts := PackedVector2Array()
		for k in 6:
			var a := -PI * 0.5 + float(k) * TAU / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(0.03, 0.045, 0.08, 0.92))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, gold, 1.6, true)
		match kind:
			0:
				# 精密：円形レティクル＋中央に弾丸（縦のカプセル）
				draw_arc(c, r * 0.52, 0, TAU, 40, gold, 1.4, true)
				for k in 4:
					var a := float(k) * PI * 0.5
					var dv := Vector2(cos(a), sin(a))
					draw_line(c + dv * (r * 0.38), c + dv * (r * 0.62), gold, 1.2, true)
				draw_line(c + Vector2(0, r * 0.2), c + Vector2(0, -r * 0.18), bright, 4.5, true)
				draw_circle(c + Vector2(0, -r * 0.22), 2.4, bright)
			1:
				# 応戦：盾の輪郭＋中央のレティクル点
				var s := r * 0.55
				var shield := PackedVector2Array([
					c + Vector2(-s, -s * 0.7), c + Vector2(0, -s), c + Vector2(s, -s * 0.7),
					c + Vector2(s, s * 0.15), c + Vector2(0, s), c + Vector2(-s, s * 0.15),
					c + Vector2(-s, -s * 0.7)])
				draw_polyline(shield, gold, 1.6, true)
				draw_arc(c, s * 0.42, 0, TAU, 30, bright, 1.2, true)
				draw_circle(c, 1.8, bright)
			2:
				# 物量：三連の小レティクル
				for off in [Vector2(0, -r * 0.34), Vector2(-r * 0.36, r * 0.22),
						Vector2(r * 0.36, r * 0.22)]:
					var p: Vector2 = c + off
					draw_arc(p, r * 0.2, 0, TAU, 24, gold, 1.3, true)
					draw_line(p + Vector2(-r * 0.28, 0), p + Vector2(r * 0.28, 0),
						gold, 0.9, true)
					draw_line(p + Vector2(0, -r * 0.28), p + Vector2(0, r * 0.28),
						gold, 0.9, true)
					draw_circle(p, 1.5, bright)


## カード四隅のブラケット＋下辺のハッチ（斜線）飾り
class CornerFrame:
	extends Control

	func _draw() -> void:
		var gold := Color(1.0, 0.88, 0.55, 0.9)
		var arm := 14.0
		var inset := 3.0
		for sx in [0.0, 1.0]:
			for sy in [0.0, 1.0]:
				var corner := Vector2(
					lerpf(inset, size.x - inset, sx), lerpf(inset, size.y - inset, sy))
				var dx := 1.0 if sx == 0.0 else -1.0
				var dy := 1.0 if sy == 0.0 else -1.0
				draw_line(corner, corner + Vector2(dx * arm, 0), gold, 1.6, true)
				draw_line(corner, corner + Vector2(0, dy * arm), gold, 1.6, true)
		# 下辺中央のハッチ（//////）
		var cx := size.x * 0.5
		var y0 := size.y - 9.0
		for k in 6:
			var x: float = cx - 21.0 + float(k) * 7.0
			draw_line(Vector2(x, y0 + 5.0), Vector2(x + 4.0, y0),
				Color(0.85, 0.72, 0.42, 0.55), 1.2, true)


## 下中央のバー（レティクル＋テキスト。押すと戻る。左右に点線の飾り）
class BottomBar:
	extends Control
	signal pressed
	var text := "TAP TO SELECT"

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var gold := Color(0.85, 0.72, 0.42)
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		var w := 250.0
		var h := 36.0
		var rect := Rect2(cx - w * 0.5, cy - h * 0.5, w, h)
		draw_rect(rect, Color(0.03, 0.045, 0.08, 0.85))
		draw_rect(rect, Color(gold.r, gold.g, gold.b, 0.55), false, 1.2)
		# 中のレティクル＋テキスト
		var fs := 13
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var icon_c := Vector2(cx - tw * 0.5 - 16.0, cy)
		draw_arc(icon_c, 6.0, 0, TAU, 24, gold, 1.2, true)
		draw_circle(icon_c, 1.5, gold)
		draw_string(font, Vector2(cx - tw * 0.5 + 2.0, cy + fs * 0.36), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, gold)
		# 左右の点線
		for sx in [-1.0, 1.0]:
			for k in 8:
				var x: float = cx + sx * (w * 0.5 + 24.0 + float(k) * 14.0)
				draw_circle(Vector2(x, cy), 1.1, Color(1, 1, 1, 0.22))
