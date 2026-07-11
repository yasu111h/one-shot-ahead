extends Control
## 選択画面（メインシーン）。2段構成：①モードを選ぶ → ②対応ステージを選ぶ。
## GameManager.MODES / STAGES 台帳を並べるだけ。全ステージ最初から開放。
## マウス/タッチのボタンのほか、数字キー(1〜)でも選べる。ステージ画面のESC/BACKで戻る。

const BG_COLOR := Color(0.03, 0.045, 0.07)
const ACCENT := Color(0.95, 0.85, 0.5)   # 命中スタンプと同じ金色

var _root: VBoxContainer
var _sub: Label
var _list: VBoxContainer          # ボタン群（画面切替のたびに作り直す）
var _mode_idx := -1               # -1=モード選択画面 / 0..=そのモードのステージ選択画面
var _visible_stages: Array = []   # 現在表示中のステージ台帳インデックス列
var _notice: Label                # 「準備中」表示


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_root = VBoxContainer.new()
	_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_theme_constant_override("separation", 10)
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var title := Label.new()
	title.text = "ONE SHOT AHEAD"
	title.add_theme_font_size_override("font_size", 44)
	title.modulate = ACCENT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)

	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 14)
	_sub.modulate = Color(1, 1, 1, 0.55)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	_root.add_child(spacer)

	_list = VBoxContainer.new()
	_list.alignment = BoxContainer.ALIGNMENT_CENTER
	_list.add_theme_constant_override("separation", 10)
	_root.add_child(_list)

	_notice = Label.new()
	_notice.add_theme_font_size_override("font_size", 13)
	_notice.modulate = Color(1.0, 0.72, 0.45, 0.95)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.text = " "
	_root.add_child(_notice)

	_show_modes()


# ---------------------------------------------------------------- 画面の組み立て

func _clear_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	_notice.text = " "


## 1段目：モード選択
func _show_modes() -> void:
	_mode_idx = -1
	_clear_list()
	_sub.text = "SELECT MODE"
	for i in GameManager.MODES.size():
		var m: Dictionary = GameManager.MODES[i]
		var label := "%d.  %s\n%s" % [i + 1, m.name, m.desc]
		if not m.ready:
			label += "（準備中）"
		var btn := _make_button(label)
		btn.modulate = Color(1, 1, 1, 1.0 if m.ready else 0.45)
		btn.pressed.connect(_on_mode_pressed.bind(i))


## 2段目：選んだモードに対応するステージ選択
func _show_stages(mode_idx: int) -> void:
	_mode_idx = mode_idx
	_clear_list()
	_sub.text = "SELECT STAGE — %s" % GameManager.MODES[mode_idx].name
	_visible_stages.clear()
	for i in GameManager.STAGES.size():
		var st: Dictionary = GameManager.STAGES[i]
		if not (mode_idx in st.modes):
			continue  # このモードに対応しないステージは出さない
		_visible_stages.append(i)
		var btn := _make_button("%d.  %s\n%s" % [_visible_stages.size(), st.name, st.desc])
		btn.pressed.connect(_on_stage_pressed.bind(i))
	var back := _make_button("BACK")
	back.custom_minimum_size = Vector2(200, 40)
	back.pressed.connect(_show_modes)


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(460, 58)
	btn.add_theme_font_size_override("font_size", 16)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 中央寄せ（VBox内で幅いっぱいに伸びないように）
	var wrap := CenterContainer.new()
	wrap.add_child(btn)
	_list.add_child(wrap)
	return btn


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
