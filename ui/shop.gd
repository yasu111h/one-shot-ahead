extends Control
## ショップ「ARMORY」（docs/武器・ショップ設計.md v1）。
## 契約報酬（お金）で武器を買う・装備を切り替える。メニューと同系のネイビー×金。
## 原則：売るのは「扱いやすさと手数」だけ（反動・ばらつき・装弾数・連射・リロード・弾速）。
## エイムの正確さは全武器同じ＝当てるのは腕（自動照準は商品にしない）。

const GOLD := Color(0.85, 0.72, 0.42)
const GOLD_BRIGHT := Color(1.0, 0.88, 0.55)
const TEXT_DIM := Color(1, 1, 1, 0.55)
const CARD_BG := Color(0.045, 0.06, 0.10, 0.90)
const NAVY := Color(0.015, 0.025, 0.05)

var _money_label: Label
var _rows: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = NAVY
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# タイトル・所持金・BACK
	var title := Label.new()
	title.text = "ARMORY"
	title.add_theme_font_size_override("font_size", 30)
	title.modulate = GOLD_BRIGHT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position += Vector2(0, 12)

	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 18)
	_money_label.modulate = GOLD_BRIGHT
	add_child(_money_label)
	_money_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_money_label.position += Vector2(-150, 16)

	var back := Button.new()
	back.text = "←  BACK"
	back.add_theme_font_size_override("font_size", 13)
	back.custom_minimum_size = Vector2(96, 32)
	_style_button(back)
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	back.position = Vector2(10, 8)
	back.pressed.connect(func() -> void: GameManager.goto_select())

	# 武器リスト
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	add_child(_rows)
	_rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rows.offset_top = 62
	_rows.offset_bottom = -12
	_rows.offset_left = 60
	_rows.offset_right = -60
	_refresh()


func _refresh() -> void:
	_money_label.text = "$ %d" % Settings.money
	for c in _rows.get_children():
		c.queue_free()
	for w in WeaponDb.WEAPONS:
		_rows.add_child(_make_row(w))


## 武器1行：名前・説明・性能・価格/装備ボタン
func _make_row(w: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	var owned: bool = w.id in Settings.owned_weapons
	var equipped: bool = Settings.equipped_weapon == w.id
	sb.border_color = GOLD_BRIGHT if equipped else Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
	sb.set_border_width_all(2 if equipped else 1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_l := Label.new()
	name_l.text = w.name + ("   [EQUIPPED]" if equipped else "")
	name_l.add_theme_font_size_override("font_size", 16)
	name_l.modulate = GOLD_BRIGHT if equipped else Color(0.9, 0.92, 0.97)
	info.add_child(name_l)
	var desc_l := Label.new()
	desc_l.text = w.desc
	desc_l.add_theme_font_size_override("font_size", 11)
	desc_l.modulate = TEXT_DIM
	info.add_child(desc_l)
	var stats_l := Label.new()
	stats_l.text = "MAG %d / AMMO %d / %s%.0fm/s / RELOAD %.1fs" % [
		w.mag, w.total, "FULL-AUTO / " if w.auto else "", w.speed, w.reload]
	stats_l.add_theme_font_size_override("font_size", 10)
	stats_l.modulate = Color(0.75, 0.82, 0.95, 0.8)
	info.add_child(stats_l)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(130, 40)
	btn.add_theme_font_size_override("font_size", 14)
	_style_button(btn)
	row.add_child(btn)
	if equipped:
		btn.text = "EQUIPPED"
		btn.disabled = true
	elif owned:
		btn.text = "EQUIP"
		btn.pressed.connect(func() -> void:
			Settings.equip_weapon(w.id)
			_refresh())
	else:
		btn.text = "BUY  $%d" % w.price
		btn.disabled = Settings.money < w.price   # 足りなければ押せない（金額は見せる）
		btn.pressed.connect(func() -> void:
			if Settings.buy_weapon(w.id):
				_refresh())
	return panel


func _style_button(btn: Button) -> void:
	for state in ["normal", "hover"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = CARD_BG
		sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		btn.add_theme_stylebox_override(state, sb)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		GameManager.goto_select()
