extends Node
## ステージのサムネイル自動キャプチャ（一時スクリプト・コミット前に削除）
## 起動引数 -- --stage=N のステージを読み込み、HUD・主人公を隠して撮影→保存→終了

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var idx := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			idx = int(a.trim_prefix("--stage="))
	GameManager.selected_mode = 0
	var entry: Dictionary = GameManager.STAGES[idx]
	var stage: SniperStage = load(entry.scene).instantiate()
	get_tree().root.add_child(stage)
	await get_tree().process_frame
	# 純粋な風景にする：HUDを消し、主人公は画面外へ（visibleは毎フレーム上書きされるため）
	stage.hud.visible = false
	stage.girl.position = Vector3(0, -999, 0)
	for f in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "res://ui/thumbs/%s.png" % String(entry.scene).get_file().get_basename()
	img.save_png(out)
	print("SAVED ", out)
	get_tree().quit(0)
