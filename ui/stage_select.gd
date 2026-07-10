extends Control
## ステージ選択画面（メインシーン）。GameManager.STAGES を並べて選ばせるだけ。
## マウス/タッチのボタンのほか、数字キー(1〜)でも選べる。

const BG_COLOR := Color(0.03, 0.045, 0.07)
const ACCENT := Color(0.95, 0.85, 0.5)   # 命中スタンプと同じ金色


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var title := Label.new()
	title.text = "ONE SHOT AHEAD"
	title.add_theme_font_size_override("font_size", 44)
	title.modulate = ACCENT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var sub := Label.new()
	sub.text = "SELECT STAGE"
	sub.add_theme_font_size_override("font_size", 14)
	sub.modulate = Color(1, 1, 1, 0.55)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	root.add_child(spacer)

	for i in GameManager.STAGES.size():
		var st: Dictionary = GameManager.STAGES[i]
		var btn := Button.new()
		btn.text = "%d.  %s\n%s" % [i + 1, st.name, st.desc]
		btn.custom_minimum_size = Vector2(460, 58)
		btn.add_theme_font_size_override("font_size", 16)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.pressed.connect(GameManager.goto_stage.bind(st.scene))
		# 中央寄せ（VBox内で幅いっぱいに伸びないように）
		var wrap := CenterContainer.new()
		wrap.add_child(btn)
		root.add_child(wrap)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var idx: int = event.keycode - KEY_1
		if idx >= 0 and idx < GameManager.STAGES.size():
			GameManager.goto_stage(GameManager.STAGES[idx].scene)
