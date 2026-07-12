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
	# 武器別の発砲音（WeaponDbのsndキャラクターで合成。装備で撃ち味の音が変わる）
	for w in WeaponDb.WEAPONS:
		var snd: Dictionary = w.snd
		_s["shot_" + w.id] = _wav(_gen_shot(
			snd.body_hi, snd.body_lo, snd.dur, snd.sub))
	_s["hit"] = _wav(_gen_hit())
	_s["headshot"] = _wav(_gen_headshot())
	_s["glass"] = _wav(_gen_glass())
	_s["impact"] = _wav(_gen_impact())
	_s["coin"] = _wav(_gen_coin())
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


## 発射音（毎発 音量-5〜-3dB・ピッチ0.96〜1.04ランダム＝TABIJI準拠）。
## weapon_id を渡すとその武器のキャラクターで鳴る（省略時は標準＝敵の発砲など）
func play_shot(weapon_id := "") -> void:
	var key := "shot_" + weapon_id if _s.has("shot_" + weapon_id) else "shot"
	_play(key, randf_range(-5.0, -3.0), randf_range(0.96, 1.04))


## 購入音（チャリン！＝ARMORYで武器を買った時）
func play_coin() -> void:
	_play("coin", -4.0, randf_range(0.98, 1.02))


## 命中音（胴体）
func play_hit() -> void:
	_play("hit", randf_range(-6.0, -4.0), randf_range(0.95, 1.05))


## 命中音（ヘッドショット・別種）
func play_headshot() -> void:
	_play("headshot", -3.0, randf_range(0.97, 1.03))


## ガラスの割れる音（パリンッ）
func play_glass() -> void:
	_play("glass", randf_range(-8.0, -6.0), randf_range(0.92, 1.08))


## 地形などガラス以外への着弾音（小さめの「ドスッ」＝土・壁の当たり）
func play_impact() -> void:
	_play("impact", randf_range(-15.0, -13.0), randf_range(0.9, 1.1))


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


## 発射: 野太いライフル砲。中低域の本体＋胸に来るサブベース＋立ち上がりのクラック。
## body_hi/body_lo=本体スイープHz・dur=長さ・sub_amt=低域の芯の量（武器ごとの音キャラ）
func _gen_shot(body_hi := 700.0, body_lo := 150.0, dur := 0.18,
		sub_amt := 0.9) -> PackedFloat32Array:
	var out := _blank(dur)
	var pbody := 0.0
	var psub := 0.0
	for i in out.size():
		var prog := float(i) / out.size()
		# 本体: body_hi→body_lo へ太く落とす(少しの矩形倍音でバイトを残す)
		pbody += TAU * lerpf(body_hi, body_lo, sqrt(prog)) / RATE
		var body := sin(pbody) * 0.6 + signf(sin(pbody)) * 0.2
		# サブベース: 95→55Hz の芯(発射のドスッ)
		psub += TAU * lerpf(95.0, 55.0, prog) / RATE
		var sub := sin(psub) * sub_amt * exp(-prog * 4.0)
		# 立ち上がりのクラック
		var noise := (randf() * 2.0 - 1.0) * 0.35 * exp(-prog * 22.0)
		var env := (1.0 - exp(-prog * 60.0)) * exp(-prog * 5.0)
		out[i] = (body * env + sub + noise) * 0.6
	return out


## 購入音: チャリン！＝レジベル（2打の明るいベル）＋こぼれるコインのきらめき
func _gen_coin() -> PackedFloat32Array:
	var dur := 0.5
	var out := _blank(dur)
	# ベル2打（2度目は少し高く・少し遅れて）＝「チャ・リン」
	var bells := [[2350.0, 0.0], [3520.0, 0.07]]
	for i in out.size():
		var t := float(i) / RATE
		var prog := float(i) / out.size()
		var v := 0.0
		for b in bells:
			var f: float = b[0]
			var t0: float = b[1]
			if t >= t0:
				var lt := t - t0
				# 基音＋明るい倍音のベル。速めに減衰
				v += (sin(TAU * f * lt) + 0.5 * sin(TAU * f * 2.76 * lt)) \
					* 0.42 * exp(-lt * 11.0)
		# 落ちたコインが転がるきらめき（後半・高域の粒）
		if t > 0.12:
			v += (randf() * 2.0 - 1.0) * 0.10 * exp(-(t - 0.12) * 9.0) \
				* (0.5 + 0.5 * sin(TAU * 160.0 * t))
		out[i] = v * (1.0 - prog * 0.2)
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


## ガラス割れ: 鋭いクラック＋高音の破片の鳴き（パリンッ）＋こぼれ落ちるきらめき
func _gen_glass() -> PackedFloat32Array:
	var dur := 0.45
	var out := _blank(dur)
	var freqs := [2350.0, 3150.0, 4200.0, 5300.0, 6100.0]
	for i in out.size():
		var prog := float(i) / out.size()
		var t := float(i) / RATE
		# 割れた瞬間の鋭いクラック
		var crack := (randf() * 2.0 - 1.0) * exp(-prog * 40.0) * 0.9
		# 破片の高い鳴き(複数の高音が別々に減衰＝ガラス特有のリン)
		var ring := 0.0
		for k in freqs.size():
			ring += sin(TAU * freqs[k] * t) * exp(-prog * (9.0 + float(k) * 3.0))
		ring *= 0.16
		# 破片がこぼれ落ちるきらめき(粗い明滅ノイズ)
		var sparkle := (randf() * 2.0 - 1.0) * exp(-prog * 7.0) * 0.18 \
			* (0.5 + 0.5 * sin(TAU * 90.0 * t))
		out[i] = (crack + ring + sparkle) * 0.55
	return out


## 地形着弾: 弱く鈍い「ドスッ」＋土埃のさらっとしたノイズ（壁・地面へのミス弾用・控えめ）
func _gen_impact() -> PackedFloat32Array:
	var dur := 0.14
	var out := _blank(dur)
	var pt := 0.0
	for i in out.size():
		var prog := float(i) / out.size()
		# 低い鈍い芯（150→70Hz を素早く減衰＝硬い面に当たった鈍い当たり）
		pt += TAU * lerpf(150.0, 70.0, prog) / RATE
		var thud := sin(pt) * exp(-prog * 14.0)
		# 土埃・破片のさらっとしたノイズ（高域を残さず速やかに消える）
		var noise := (randf() * 2.0 - 1.0) * 0.4 * exp(-prog * 24.0)
		out[i] = (thud * 0.7 + noise * 0.5) * 0.45
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
