extends Node
## BGM管理（オートロード）。メニューBGMとプレイBGMをループ再生し、
## 画面切り替え時にクロスフェードでつなぐ。専用の"Music"音声バスで鳴らすので、
## SFXと独立に音量調整できる（Settings.music_enabled / music_volume）。
##
## 呼び出し側:
##   ui/stage_select.gd  … Music.play_menu()
##   stages/sniper_stage.gd … Music.play_game()
## 同じ曲が既に鳴っていれば何もしない（リトライでの再スタートを防ぐ）。

const MENU_TRACK := "res://assets/music/nocturnal_perimeter.mp3"
const GAME_TRACK := "res://assets/music/held_breath.mp3"
const BUS_NAME := "Music"
const FADE_TIME := 1.2   # クロスフェード秒数

var _players: Array[AudioStreamPlayer] = []   # 2枚使ってクロスフェード
var _active := 0                              # 現在鳴っている側(0/1)
var _current_path := ""                       # 再生中トラックのパス（重複再生の抑止）
var _tween: Tween


func _ready() -> void:
	# シーン切り替えで止まらないよう、ツリーのポーズにも影響されない
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_NAME
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_apply_bus_volume()


## 終了時（アプリ終了・シーンツリー破棄）にTweenを確実に片付ける。
## クロスフェード中に強制終了されるとTweenが宙に浮いてリーク警告になるため。
func _exit_tree() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	# 再生中のストリーム参照を解放（強制終了時の "resource still in use" 回避）
	for p in _players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null


## "Music"バスを（無ければ）作る。以後この名前でボリュームをまとめて操作する
func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, BUS_NAME)
	AudioServer.set_bus_send(idx, "Master")


func play_menu() -> void:
	_play(MENU_TRACK)


func play_game() -> void:
	_play(GAME_TRACK)


## 設定変更（Settings）からの通知。ミュート切替・音量反映
func refresh() -> void:
	_apply_bus_volume()


# ---------------------------------------------------------------- 内部

func _play(path: String) -> void:
	if path == _current_path and _players[_active].playing:
		return  # 既に同じ曲が鳴っている（リトライ・同一画面の再入）
	_current_path = path
	# CACHE_MODE_IGNORE: ResourceLoaderのキャッシュに残さない＝参照はこのプレイヤーだけ。
	# 終了時に stream=null すれば確実に解放される（"resource still in use" を出さない）
	var stream := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if stream == null:
		return
	# MP3をループ再生に（Sunoの書き出しは末尾に余韻があるので loop_offset は付けない）
	if stream is AudioStreamMP3:
		stream.loop = true
	var next := 1 - _active
	var incoming := _players[next]
	var outgoing := _players[_active]
	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	_active = next

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	# 目標音量（ミュート中は無音のまま＝フェードしても鳴らない）
	var target := 0.0 if _music_on() else -80.0
	_tween.tween_property(incoming, "volume_db", target, FADE_TIME)
	_tween.tween_property(outgoing, "volume_db", -80.0, FADE_TIME)
	_tween.chain().tween_callback(outgoing.stop)


func _music_on() -> bool:
	# プレイヤーの音量は常に0dBまで上げ、ON/OFFはバスのミュートで制御する
	# （ここでフェード先を絞ると復帰時に鳴らないため）
	return true


## バス全体の音量（ミュート/音量スライダー用）。Settingsがあれば従う
func _apply_bus_volume() -> void:
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx == -1:
		return
	var on := true
	var vol := 1.0
	if _has_settings():
		on = Settings.music_enabled
		vol = Settings.music_volume
	AudioServer.set_bus_mute(idx, not on)
	# 0..1 を dB へ（0.0で-24dB相当まで絞り、1.0で0dB）
	AudioServer.set_bus_volume_db(idx, lerpf(-24.0, 0.0, clampf(vol, 0.0, 1.0)))


func _has_settings() -> bool:
	return get_node_or_null("/root/Settings") != null
