extends Node
## 設定の永続化（オートロード）。user://settings.cfg に保存し、起動時に復元する。
## 将来の設定画面はこのシングルトンを読み書きするだけでよい。

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "gameplay"

## 命中弾（悪人へ当たる確定弾）でバレットカム（キルカム）を流すか
var hit_replay_enabled := true:
	set(v):
		hit_replay_enabled = v
		_save()

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

## 弾のばらつき（散布）を使うか。撃った瞬間に弾の方向が距離に応じてランダムにずれる
## （照準は静止のまま。600m先で窓1枚≒横5mまでずれうる）
var spread_enabled := true:
	set(v):
		spread_enabled = v
		_save()

## BGMを鳴らすか
var music_enabled := true:
	set(v):
		music_enabled = v
		if has_node("/root/Music"):
			Music.refresh()
		_save()

## BGM音量(0..1)。将来のスライダー用。既定は控えめ(0.7)
var music_volume := 0.7:
	set(v):
		music_volume = clampf(v, 0.0, 1.0)
		if has_node("/root/Music"):
			Music.refresh()
		_save()


func _ready() -> void:
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return  # 初回起動などファイルなし＝デフォルトのまま
	hit_replay_enabled = bool(cfg.get_value(SECTION, "hit_replay", true))
	miss_replay_enabled = bool(cfg.get_value(SECTION, "miss_replay", true))
	gravity_enabled = bool(cfg.get_value(SECTION, "gravity", false))
	spread_enabled = bool(cfg.get_value(SECTION, "spread", true))
	music_enabled = bool(cfg.get_value(SECTION, "music", true))
	music_volume = float(cfg.get_value(SECTION, "music_volume", 0.7))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 既存の設定を保持したまま上書き（無ければ新規作成）
	cfg.set_value(SECTION, "hit_replay", hit_replay_enabled)
	cfg.set_value(SECTION, "miss_replay", miss_replay_enabled)
	cfg.set_value(SECTION, "gravity", gravity_enabled)
	cfg.set_value(SECTION, "spread", spread_enabled)
	cfg.set_value(SECTION, "music", music_enabled)
	cfg.set_value(SECTION, "music_volume", music_volume)
	cfg.save(SETTINGS_PATH)
