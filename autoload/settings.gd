extends Node
## 設定の永続化（オートロード）。user://settings.cfg に保存し、起動時に復元する。
## 将来の設定画面はこのシングルトンを読み書きするだけでよい。

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "gameplay"
const PROGRESS := "progress"   # 進行データ（所持金・武器）の保存セクション

## ★デバッグモード（開発者用の隠しスイッチ）。
## true にすると①プレイ画面に「DEBUG」ボタン（GRAVITY/SPREAD/弾道デバッグ）が出る、
## ②ホーム画面に「HORDE表示」トグルが出て、ONにすると隠しモードのHORDEが遊べるようになる。
## リリース状態は false。開発者がこの行を true に書き換えて使う（設定画面には出さない）。
const DEBUG_MODE := true

## HORDE（物量）モードをホーム画面に出すか。既定は非表示＝ホームは2モードだけ。
## DEBUG_MODE が true のときにホームの「HORDE表示」トグルで切り替えられる。
## （DEBUG_MODE が false の間は、この値に関わらずHORDEは出さない）
var horde_visible := false:
	set(v):
		horde_visible = v
		_save()

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


# --- 進行データ（お金・武器）。docs/武器・ショップ設計.md v1 ---

var money := 0                            # 所持金（契約報酬）
var owned_weapons: Array = ["ghost"]      # 購入済み武器id
var equipped_weapon := "ghost"            # 装備中の武器id


## 報酬の入金（キル即時・クリアボーナス）。負値は使わない
func add_money(amount: int) -> void:
	money += maxi(amount, 0)
	_save()


## 武器の購入。所持金が足りて未所持なら買って装備し true
func buy_weapon(id: String) -> bool:
	if id in owned_weapons:
		return false
	var w := WeaponDb.by_id(id)
	if w.id != id or money < w.price:
		return false
	money -= w.price
	owned_weapons.append(id)
	equipped_weapon = id  # 買ったらそのまま装備（ショップの手数を減らす）
	_save()
	return true


## 装備切り替え（所持している武器のみ）
func equip_weapon(id: String) -> bool:
	if id not in owned_weapons:
		return false
	equipped_weapon = id
	_save()
	return true


func _ready() -> void:
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return  # 初回起動などファイルなし＝デフォルトのまま
	horde_visible = bool(cfg.get_value(SECTION, "horde_visible", false))
	hit_replay_enabled = bool(cfg.get_value(SECTION, "hit_replay", true))
	miss_replay_enabled = bool(cfg.get_value(SECTION, "miss_replay", true))
	gravity_enabled = bool(cfg.get_value(SECTION, "gravity", false))
	spread_enabled = bool(cfg.get_value(SECTION, "spread", true))
	music_enabled = bool(cfg.get_value(SECTION, "music", true))
	music_volume = float(cfg.get_value(SECTION, "music_volume", 0.7))
	money = int(cfg.get_value(PROGRESS, "money", 0))
	owned_weapons = Array(cfg.get_value(PROGRESS, "owned_weapons", ["ghost"]))
	if "ghost" not in owned_weapons:
		owned_weapons.append("ghost")  # 初期武器は常に所持（セーブ破損の安全側）
	equipped_weapon = str(cfg.get_value(PROGRESS, "equipped_weapon", "ghost"))
	if equipped_weapon not in owned_weapons:
		equipped_weapon = "ghost"


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 既存の設定を保持したまま上書き（無ければ新規作成）
	cfg.set_value(SECTION, "horde_visible", horde_visible)
	cfg.set_value(SECTION, "hit_replay", hit_replay_enabled)
	cfg.set_value(SECTION, "miss_replay", miss_replay_enabled)
	cfg.set_value(SECTION, "gravity", gravity_enabled)
	cfg.set_value(SECTION, "spread", spread_enabled)
	cfg.set_value(SECTION, "music", music_enabled)
	cfg.set_value(SECTION, "music_volume", music_volume)
	cfg.set_value(PROGRESS, "money", money)
	cfg.set_value(PROGRESS, "owned_weapons", owned_weapons)
	cfg.set_value(PROGRESS, "equipped_weapon", equipped_weapon)
	cfg.save(SETTINGS_PATH)
