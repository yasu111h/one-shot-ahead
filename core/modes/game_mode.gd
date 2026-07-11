class_name GameMode
extends RefCounted
## ゲームモードの基底クラス（A精密/B応戦/C物量…の共通インターフェース）。
##
## ★フック名は凍結済み（2026-07-12・実装指示書§5）。他セッションは変更禁止。★
##   setup(stage) / on_fire() / on_hit(target, zone) / on_miss() / tick(delta)
##   / check_win() -> String / check_fail() -> String / hud_extra() -> Dictionary
##
## SniperStage が保持し、射撃イベント・毎フレーム・勝敗判定をこのフック経由で回す。
## 勝敗は check_win/check_fail のポーリング方式：
##   空文字 "" ＝継続。非空 ＝その文字列を結果表示（win→CLEAR画面 / fail→FAIL画面）にして終了。
##
## hud_extra() はモード固有のHUD要素を「データ」で返し、描画はHUD側の共通受け皿が行う
## （モード実装が hud.gd を直接改造しないための規約）:
##   {
##     "lines":  ["残り敵数 5", ...],                     # 左上ミッション文の下に小さく並ぶ
##     "gauges": [{"label": "ALERT", "value": 0.5,        # 画面下中央の横ゲージ(0..1)
##                 "color": Color(1, 0.4, 0.3)}, ...],
##   }
## どちらのキーも省略可。空Dictionaryなら何も出ない。

var stage: SniperStage


## ステージ構築完了後に1回呼ばれる（stageの標的・HUDは構築済み）
func setup(stage_ref: SniperStage) -> void:
	stage = stage_ref


## プレイヤーが1発撃った（弾道確定後・結果はまだ）
func on_fire() -> void:
	pass


## 標的に命中した（target=標的ノード、zone="head"/"body"。民間人への命中も来る）
func on_hit(_target: Node, _zone: String) -> void:
	pass


## 弾が何にも（標的に）当たらなかった（地形着弾・寿命切れ・ミスリプレイ着弾）
func on_miss() -> void:
	pass


## 毎物理フレーム呼ばれる（ゲーム終了後は呼ばれない）
func tick(_delta: float) -> void:
	pass


## 勝利判定。非空文字列を返すとその表示でCLEAR
func check_win() -> String:
	return ""


## 敗北判定。非空文字列を返すとその表示でFAIL（check_winより先に評価される）
func check_fail() -> String:
	return ""


## モード固有のHUD要素（上記の規約どおりのDictionary）。毎フレーム参照される
func hud_extra() -> Dictionary:
	return {}
