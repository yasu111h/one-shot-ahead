extends Object
## 画面中央の照準十字を描く共通ヘルパー（TABIJIのreticle.gdを移植）。
## 暗い背景でも明るい背景でも沈まないよう、明るい芯を濃い縁取りで囲む。
## 縁取りを芯より太く描くと、線の両側に黒フチが出て、どんな地の色でも輪郭が立つ。
## 使い方: const Reticle := preload("res://ui/reticle.gd")
##         Reticle.draw_cross(canvas_item, center, gap, tick, Color.WHITE)

const OUTLINE := Color(0.0, 0.0, 0.0, 0.9)   # 縁取り(濃い・不透明寄り)
const CORE_W := 2.4                          # 明るい芯の太さ
const OUTLINE_W := 5.2                        # 縁取りの太さ(芯より太く→両側に黒フチ)
const DOT_CORE := 1.8                         # 中心点の芯の半径
const DOT_OUTLINE := 3.6                      # 中心点の縁取り半径


## 中央の十字(4本のティック＋中心点)を、縁取り付きで描く。
##  ci   : 描画先(CanvasItem。draw中に呼ぶ)
##  c    : 画面中央
##  gap  : 中心から各ティックが始まるまでの空き
##  tick : ティックの長さ
##  core : 芯の色(通常は白、ロック時はオレンジ等)
static func draw_cross(ci: CanvasItem, c: Vector2, gap: float, tick: float, core: Color) -> void:
	var dirs := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	# 先に4本すべての縁取りを描く(隣の芯を縁取りが上書きしないよう順序を分ける)
	for d: Vector2 in dirs:
		ci.draw_line(c + d * gap, c + d * (gap + tick), OUTLINE, OUTLINE_W, true)
	# 中心点も縁取り→芯の順
	ci.draw_circle(c, DOT_OUTLINE, OUTLINE)
	for d: Vector2 in dirs:
		ci.draw_line(c + d * gap, c + d * (gap + tick), core, CORE_W, true)
	ci.draw_circle(c, DOT_CORE, core)


## 命中マーカー(斜め4本)。こちらも縁取り付きで背景に負けないようにする。
static func draw_hitmark(ci: CanvasItem, c: Vector2, core: Color) -> void:
	var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for d: Vector2 in dirs:
		var dn := d.normalized()
		ci.draw_line(c + dn * 6.0, c + dn * 16.0, OUTLINE, 4.2, true)
	for d: Vector2 in dirs:
		var dn := d.normalized()
		ci.draw_line(c + dn * 6.0, c + dn * 16.0, core, 2.2, true)
