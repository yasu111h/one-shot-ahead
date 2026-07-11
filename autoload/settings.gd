extends Node
## 設定の永続化（オートロード）。user://settings.cfg に保存し、起動時に復元する。
## 将来の設定画面はこのシングルトンを読み書きするだけでよい。

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "gameplay"

## ミス弾（標的に当たらない弾）でもバレットカムを流すか
var miss_replay_enabled := true:
	set(v):
		miss_replay_enabled = v
		_save()

## 重力弾道（放物線）を使うか。Ballisticsのstatic varへ反映して全弾道計算に効かせる
var gravity_enabled := false:
	set(v):
		gravity_enabled = v
		Ballistics.gravity_enabled = v
		_save()

## 距離連動の手ブレを使うか（遠い標的ほど照準が揺れる。600mで窓1枚≒5mの振れ幅）
var sway_enabled := true:
	set(v):
		sway_enabled = v
		_save()


func _ready() -> void:
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return  # 初回起動などファイルなし＝デフォルトのまま
	miss_replay_enabled = bool(cfg.get_value(SECTION, "miss_replay", true))
	gravity_enabled = bool(cfg.get_value(SECTION, "gravity", false))
	sway_enabled = bool(cfg.get_value(SECTION, "sway", true))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 既存の設定を保持したまま上書き（無ければ新規作成）
	cfg.set_value(SECTION, "miss_replay", miss_replay_enabled)
	cfg.set_value(SECTION, "gravity", gravity_enabled)
	cfg.set_value(SECTION, "sway", sway_enabled)
	cfg.save(SETTINGS_PATH)
