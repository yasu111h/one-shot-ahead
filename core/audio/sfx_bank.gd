class_name SfxBank
extends Node
## 戦闘サウンド ― すべてコードで波形を合成して鳴らす（外部音源ファイルなし・TABIJIのaudio.gd方式）。
## 起動時に短いSFXを AudioStreamWAV として生成し、プールした AudioStreamPlayer で再生する。
## 生成はデータ操作のみなので headless でも安全。

const RATE := 22050            # 生成サンプルレート
const POOL := 8                # 同時発音数

var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _s := {}                   # 名前 -> 合成AudioStreamWAV


func _ready() -> void:
	_s["shot"] = _wav(_gen_shot())
	_s["hit"] = _wav(_gen_hit())
	_s["headshot"] = _wav(_gen_headshot())
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


## 発射音（毎発 音量-5〜-3dB・ピッチ0.96〜1.04ランダム＝TABIJI準拠）
func play_shot() -> void:
	_play("shot", randf_range(-5.0, -3.0), randf_range(0.96, 1.04))


## 命中音（胴体）
func play_hit() -> void:
	_play("hit", randf_range(-6.0, -4.0), randf_range(0.95, 1.05))


## 命中音（ヘッドショット・別種）
func play_headshot() -> void:
	_play("headshot", -3.0, randf_range(0.97, 1.03))


func _play(sfx_name: String, vol_db: float, pitch: float) -> void:
	var stream: AudioStream = _s.get(sfx_name)
	if stream == null:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func _blank(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	return out


## float[-1,1] 列を 16bit PCM の AudioStreamWAV に変換する
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := clampf(samples[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(roundf(v * 32767.0)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


## 発射: 野太いライフル砲。中低域の本体＋胸に来るサブベース＋立ち上がりのクラック
func _gen_shot() -> PackedFloat32Array:
	var dur := 0.18
	var out := _blank(dur)
	var pbody := 0.0
	var psub := 0.0
	for i in out.size():
		var prog := float(i) / out.size()
		# 本体: 700→150Hz へ太く落とす(少しの矩形倍音でバイトを残す)
		pbody += TAU * lerpf(700.0, 150.0, sqrt(prog)) / RATE
		var body := sin(pbody) * 0.6 + signf(sin(pbody)) * 0.2
		# サブベース: 95→55Hz の芯(発射のドスッ)
		psub += TAU * lerpf(95.0, 55.0, prog) / RATE
		var sub := sin(psub) * 0.9 * exp(-prog * 4.0)
		# 立ち上がりのクラック
		var noise := (randf() * 2.0 - 1.0) * 0.35 * exp(-prog * 22.0)
		var env := (1.0 - exp(-prog * 60.0)) * exp(-prog * 5.0)
		out[i] = (body * env + sub + noise) * 0.6
	return out


## 命中(胴体): 低い芯のドッ（当たった手応え）
func _gen_hit() -> PackedFloat32Array:
	var dur := 0.2
	var out := _blank(dur)
	var pt := 0.0
	for i in out.size():
		var prog := float(i) / out.size()
		pt += TAU * lerpf(200.0, 130.0, prog) / RATE
		var thud := sin(pt) * exp(-prog * 7.0)
		var noise := (randf() * 2.0 - 1.0) * 0.25 * exp(-prog * 30.0)
		out[i] = (thud + noise) * 0.6
	return out


## 命中(ヘッドショット): 低い芯のドッ＋明るいピン（決定打の手応え・別種）
func _gen_headshot() -> PackedFloat32Array:
	var dur := 0.24
	var out := _blank(dur)
	var pt := 0.0
	var pp := 0.0
	for i in out.size():
		var prog := float(i) / out.size()
		pt += TAU * lerpf(200.0, 130.0, prog) / RATE
		pp += TAU * 920.0 / RATE
		var thud := sin(pt) * exp(-prog * 7.0)
		var ping := sin(pp) * 0.4 * exp(-prog * 16.0)
		var noise := (randf() * 2.0 - 1.0) * 0.25 * exp(-prog * 30.0)
		out[i] = (thud + ping + noise) * 0.6
	return out
