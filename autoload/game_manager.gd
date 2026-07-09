extends Node
## ゲーム全体管理（オートロード）。プロトタイプではFPS上限設定のみ

func _ready() -> void:
	Engine.max_fps = 60


## タイムスケール関連を初期状態へ戻す（リトライ時などに呼ぶ）
func reset_time() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
