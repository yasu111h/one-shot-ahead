class_name DamageFlash
extends CanvasLayer
## 被弾フィードバック（Bモード応戦などで使う画面演出）。
## FPSの定番＝「赤いビネット（画面端の赤いにじみ）＋被弾の瞬間の全画面フラッシュ」。
##   ・撃たれた瞬間：全画面が一瞬赤く光り、画面端の赤が強く出てフェードする
##   ・蓄積：被弾が増えるほど画面端の赤みが常時残る（残りHPが少ないほど画面が赤い＝危険）
## モードが setup で stage に add_child し、被弾のたび flash(被弾数, 最大被弾数) を呼ぶだけ。
## hud.gd を一切触らずにモード固有の演出を足すための独立ノード。

const FLASH_DUR := 0.5        # 被弾フラッシュのフェード時間(実時間・秒)
const FULL_PEAK := 0.42       # 全画面フラッシュのピーク不透明度
const VIGNETTE_FLASH := 0.7   # 被弾時にビネットへ上乗せする不透明度
const VIGNETTE_ACCUM := 0.5   # 被弾MAX直前での常時ビネット不透明度

var _vignette: TextureRect
var _full: ColorRect
var _flash_t := 0.0
var _hits := 0
var _max_hits := 3


func _ready() -> void:
	layer = 20  # HUD(10)より前・バレットカムのレターボックス(95)より後ろ
	# 画面端の赤いビネット（中心透明→端が赤の放射グラデ）
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 0.82, 1.0])
	grad.colors = PackedColorArray([
		Color(0.8, 0.0, 0.0, 0.0), Color(0.8, 0.0, 0.0, 0.0),
		Color(0.75, 0.02, 0.02, 0.55), Color(0.65, 0.0, 0.0, 0.95),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.modulate.a = 0.0
	# 被弾の瞬間だけ光る全画面の赤
	_full = ColorRect.new()
	_full.color = Color(0.85, 0.05, 0.05, 0.0)
	_full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_full)
	_full.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 被弾した。hits=現在の累計被弾数・max_hits=FAILになる被弾数
func flash(hits: int, max_hits: int) -> void:
	_hits = hits
	_max_hits = maxi(max_hits, 1)
	_flash_t = FLASH_DUR


func _process(delta: float) -> void:
	# バレットカム中(time_scale低下)でもフェードは実時間で進める
	var rdt := delta / maxf(Engine.time_scale, 0.0001)
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - rdt, 0.0)
	var flash_a := _flash_t / FLASH_DUR    # 1→0
	# 全画面フラッシュ（被弾直後だけ）
	_full.color.a = flash_a * FULL_PEAK
	# ビネット＝蓄積ぶん（HPが減るほど濃く残る）＋被弾フラッシュぶん
	var accum := float(_hits) / float(_max_hits) * VIGNETTE_ACCUM
	_vignette.modulate.a = clampf(accum + flash_a * VIGNETTE_FLASH, 0.0, 1.0)
