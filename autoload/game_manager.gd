extends Node
## ゲーム全体管理（オートロード）。FPS上限・ステージ台帳・シーン切り替え

## ステージ台帳。ステージ選択画面はこれを並べるだけ＝追加はここに1行足す
const STAGES := [
	{
		"name": "CITY NIGHT",
		"desc": "ビル街の夜。窓に現れる悪人だけを撃ち抜け",
		"scene": "res://stages/city/city_stage.tscn",
	},
	{
		"name": "HARBOR",
		"desc": "夜の埠頭。コンテナの隙間を横切る一瞬を狙え",
		"scene": "res://stages/harbor/harbor_stage.tscn",
	},
	{
		"name": "TEST RANGE",
		"desc": "平原の射撃場。腕試しと感度チューニング",
		"scene": "res://stages/test_range/test_range.tscn",
	},
	{
		"name": "DESERT CHECKPOINT",
		"desc": "夜明けの砂漠。検問所を占拠した武装勢力だけを撃ち抜け",
		"scene": "res://stages/desert/desert_stage.tscn",
	},
]
const SELECT_SCENE := "res://ui/stage_select.tscn"


func _ready() -> void:
	Engine.max_fps = 60


## タイムスケール関連を初期状態へ戻す（リトライ時などに呼ぶ）
func reset_time() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


func goto_stage(scene_path: String) -> void:
	reset_time()
	get_tree().change_scene_to_file(scene_path)


func goto_select() -> void:
	reset_time()
	get_tree().change_scene_to_file(SELECT_SCENE)
