extends Node
## ゲーム全体管理（オートロード）。FPS上限・モード/ステージ台帳・シーン切り替え

## モード台帳。選択画面の1段目はこれを並べる。
## ready=false は「準備中」（枠だけ。中身は担当セッションが実装したら true にする）。
## script はそのモードの GameMode 継承クラス（core/modes/）。
const MODES := [
	{
		"id": "precision",
		"name": "PRECISION",
		"desc": "精密狙撃。冷静に、正確に、悪人だけを撃ち抜け",
		"script": "res://core/modes/precision_mode.gd",
		"ready": true,
	},
	{
		"id": "engage",
		"name": "ENGAGE",
		"desc": "応戦。敵は撃ち返してくる",
		"script": "res://core/modes/engage_mode.gd",  # repo_02 実装済み
		"ready": true,
	},
	{
		"id": "horde",
		"name": "HORDE",
		"desc": "物量。押し寄せる敵を撃ち捌け",
		"script": "res://core/modes/horde_mode.gd",
		"ready": true,
	},
]

## ステージ台帳。選択画面の2段目は「選んだモードに対応するステージ」だけを並べる。
## modes = 対応モードのインデックス配列（MODESの並び順。0=A精密 1=B応戦 2=C物量）。
## ステージ追加はここに1行足す＋対応モードを宣言する。
const STAGES := [
	{
		"name": "CITY NIGHT",
		"desc": "ビル街の夜。窓に現れる悪人だけを撃ち抜け",
		"scene": "res://stages/city/city_stage.tscn",
		"modes": [0, 1, 2],
	},
	{
		"name": "HARBOR",
		"desc": "夜の埠頭。コンテナの隙間を横切る一瞬を狙え",
		"scene": "res://stages/harbor/harbor_stage.tscn",
		"modes": [0, 1],
	},
	{
		"name": "TEST RANGE",
		"desc": "平原の射撃場。腕試しと感度チューニング",
		"scene": "res://stages/test_range/test_range.tscn",
		"modes": [0, 2],   # C物量の当面の舞台（砂漠完成後に移設予定）
	},
	{
		"name": "DESERT CHECKPOINT",
		"desc": "夜明けの砂漠。検問所を占拠した武装勢力だけを撃ち抜け",
		"scene": "res://stages/desert/desert_stage.tscn",
		"modes": [0, 2],
	},
]
const SELECT_SCENE := "res://ui/stage_select.tscn"

## 現在選択中のモード/ステージ（台帳インデックス）。リトライのシーン再読込でも保持される
var selected_mode := 0
var selected_stage := 0


func _ready() -> void:
	Engine.max_fps = 60


## タイムスケール関連を初期状態へ戻す（リトライ時などに呼ぶ）
func reset_time() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


## ステージ開始（台帳インデックス指定）。mode_idx省略時は現在の選択を維持
func goto_stage(stage_idx: int, mode_idx := -1) -> void:
	if mode_idx >= 0:
		selected_mode = mode_idx
	selected_stage = stage_idx
	reset_time()
	get_tree().change_scene_to_file(STAGES[stage_idx].scene)


func goto_select() -> void:
	reset_time()
	get_tree().change_scene_to_file(SELECT_SCENE)


## 選択中モードの GameMode インスタンスを生成する（SniperStage._ready が呼ぶ）。
## 未実装モード（script空）の場合は精密モードで動かす（安全側フォールバック）
func create_selected_mode() -> GameMode:
	var entry: Dictionary = MODES[selected_mode]
	if entry.script != "":
		var cls = load(entry.script)
		if cls != null:
			return cls.new()
	return PrecisionMode.new()
