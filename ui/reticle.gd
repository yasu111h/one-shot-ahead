extends Object
## 画面中央の照準十字を描く共通ヘルパー（TABIJIのreticle.gdを移植・スナイパー向けに調整）。
## 暗い背景でも明るい背景でも沈まないよう、芯を細い縁取りで囲む（芯より太い縁取り＝
## 線の両側にフチが出て、どんな地の色でも輪郭が立つ）。
## スコープ時は実銃スコープ風の「細い十字＋中心は開ける（塗りドットなし）」にして、
## 標的や弾道が中心で隠れないようにする。
## 使い方: const Reticle := preload("res://ui/reticle.gd")
##         Reticle.draw_cross(ci, center, gap, tick, core, outline)

# 腰だめ（非スコープ）用の既定スタイル：白芯＋黒フチのはっきりした十字
const OUTLINE := Color(0.0, 0.0, 0.0, 0.9)   # 縁取り(濃い)
const CORE_W := 2.0                          # 芯の太さ
const OUTLINE_W := 4.4                        # 縁取りの太さ(芯より太く→両側にフチ)
const DOT_CORE := 1.6                         # 中心点の芯の半径


## 中央の十字を縁取り付きで描く。線の太さ・色・中心ドット半径を指定できる。
##  ci          : 描画先(CanvasItem。draw中に呼ぶ)
##  c           : 画面中央
##  gap         : 中心から各ティックが始まるまでの空き（中心はここで開く）
##  tick        : ティックの長さ
##  core        : 芯の色
##  outline     : 縁取りの色（省略時は既定の黒フチ）
##  core_w      : 芯の太さ（省略時 CORE_W）
##  outline_w   : 縁取りの太さ（省略時 OUTLINE_W）
##  dot_radius  : 中心点の芯半径（0＝中心ドットを描かない＝スコープはこれで中心を開ける）
##  dot_core    : 中心点だけ別色にしたい時に指定（減速ゾーンの控えめな合図など）
static func draw_cross(ci: CanvasItem, c: Vector2, gap: float, tick: float, core: Color,
		outline := OUTLINE, core_w := CORE_W, outline_w := OUTLINE_W,
		dot_radius := DOT_CORE, dot_core := Color(0, 0, 0, 0)) -> void:
	var dirs := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	# 先に4本すべての縁取りを描く(隣の芯を縁取りが上書きしないよう順序を分ける)
	for d: Vector2 in dirs:
		ci.draw_line(c + d * gap, c + d * (gap + tick), outline, outline_w, true)
	# 中心ドット（dot_radius>0の時だけ）。縁取り→芯の順
	if dot_radius > 0.0:
		var dot := dot_core if dot_core.a > 0.0 else core
		ci.draw_circle(c, dot_radius + (outline_w - core_w) * 0.5, outline)
		for d: Vector2 in dirs:
			ci.draw_line(c + d * gap, c + d * (gap + tick), core, core_w, true)
		ci.draw_circle(c, dot_radius, dot)
	else:
		for d: Vector2 in dirs:
			ci.draw_line(c + d * gap, c + d * (gap + tick), core, core_w, true)


## 命中マーカー(斜め4本)。こちらも縁取り付きで背景に負けないようにする。
static func draw_hitmark(ci: CanvasItem, c: Vector2, core: Color) -> void:
	var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for d: Vector2 in dirs:
		var dn := d.normalized()
		ci.draw_line(c + dn * 6.0, c + dn * 16.0, OUTLINE, 4.2, true)
	for d: Vector2 in dirs:
		var dn := d.normalized()
		ci.draw_line(c + dn * 6.0, c + dn * 16.0, core, 2.2, true)
