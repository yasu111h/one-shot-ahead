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
var _spinners: Array = []       # 回転中の武器3Dモデル（毎フレームぐるぐる）
var _sfx: SfxBank               # 購入音（チャリン）
var _confirm: Control           # 購入確認ポップアップ（開いている間だけ存在）


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = NAVY
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sfx = SfxBank.new()
	add_child(_sfx)

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
	_spinners.clear()
	for c in _rows.get_children():
		c.queue_free()
	for w in WeaponDb.WEAPONS:
		_rows.add_child(_make_row(w))


func _process(delta: float) -> void:
	# 武器プレビューの自動回転（ぐるぐる）
	for s in _spinners:
		if is_instance_valid(s):
			s.rotate_y(delta * 1.4)


## 武器の3D回転プレビュー（行の左端）。SubViewportに武器モデル＋ライト＋カメラを置く
func _make_preview(w: Dictionary) -> Control:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(150, 78)
	var vp := SubViewport.new()
	vp.transparent_bg = true   # カードの下地が透ける＝画面に馴染む
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)
	# 武器（バレル+Z。少し見下ろす構図の中心でY回転）
	var model := WeaponModel.build(w.id)
	model.position = Vector3(0.0, 0.0, 0.0)
	vp.add_child(model)
	_spinners.append(model)
	# ライト（キー＋アクセント色の逆光）
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	key.light_energy = 1.4
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10.0, 150.0, 0.0)
	rim.light_color = w.color
	rim.light_energy = 0.8
	vp.add_child(rim)
	# カメラ（銃全体が収まる距離・わずかに上から）
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.22, 0.85)
	cam.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
	cam.fov = 40.0
	vp.add_child(cam)
	cam.make_current()
	return holder


## 武器1行：3Dプレビュー・名前・説明・性能・価格/装備ボタン
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

	# 左端：ぐるぐる回る武器の3Dプレビュー
	row.add_child(_make_preview(w))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_l := Label.new()
	name_l.text = w.name + ("   [EQUIPPED]" if equipped else "")
	name_l.add_theme_font_size_override("font_size", 16)
	name_l.modulate = GOLD_BRIGHT if equipped else w.color.lightened(0.4)
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
		btn.pressed.connect(func() -> void: _open_confirm(w))
	return panel


## 購入確認ポップアップ：「本当に買う？」を挟み、BUYでチャリン＋購入＋装備
func _open_confirm(w: Dictionary) -> void:
	if _confirm != null:
		return
	_confirm = Control.new()
	add_child(_confirm)
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 背後を暗くする幕（タップしてもキャンセルにはしない＝誤爆防止）
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	_confirm.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 中央カード
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = GOLD_BRIGHT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", sb)
	_confirm.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var q := Label.new()
	q.text = "%s を購入しますか？" % w.name
	q.add_theme_font_size_override("font_size", 17)
	q.modulate = w.color.lightened(0.4)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(q)
	var price_l := Label.new()
	price_l.text = "$%d   （残高 $%d → $%d）" % [w.price, Settings.money, Settings.money - w.price]
	price_l.add_theme_font_size_override("font_size", 13)
	price_l.modulate = GOLD_BRIGHT
	price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(price_l)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_row)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(120, 42)
	cancel.add_theme_font_size_override("font_size", 14)
	_style_button(cancel)
	cancel.pressed.connect(_close_confirm)
	btn_row.add_child(cancel)
	var buy := Button.new()
	buy.text = "BUY  $%d" % w.price
	buy.custom_minimum_size = Vector2(140, 42)
	buy.add_theme_font_size_override("font_size", 14)
	_style_button(buy)
	buy.modulate = GOLD_BRIGHT
	buy.pressed.connect(func() -> void:
		if Settings.buy_weapon(w.id):
			_sfx.play_coin()   # チャリン！
		_close_confirm()
		_refresh())
	btn_row.add_child(buy)


func _close_confirm() -> void:
	if _confirm != null:
		_confirm.queue_free()
		_confirm = null


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
		if _confirm != null:
			_close_confirm()   # ポップアップ中のESCはキャンセル
		else:
			GameManager.goto_select()
