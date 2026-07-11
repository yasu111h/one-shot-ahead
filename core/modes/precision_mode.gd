class_name PrecisionMode
extends GameMode
## Aモード「精密」（既定）。従来の勝敗ロジックをそのまま移設したもの。
## 相手は撃ってこない・襲ってこない。冷静に正確に。
##   勝ち: 悪人全滅 → CLEAR
##   負け: 民間人を撃つ → CIVILIAN DOWN ／ 弾切れで撃ち漏らし → AMMO OUT

var _civilian_down := false


func on_hit(target: Node, _zone: String) -> void:
	if not target.hostile:
		_civilian_down = true


func check_fail() -> String:
	if _civilian_down:
		return "CIVILIAN DOWN"
	if stage.ammo <= 0 and stage.bullets_in_flight <= 0 and not stage.is_replay_active():
		return "AMMO OUT"
	return ""


func check_win() -> String:
	if stage.hits >= stage.hostiles.size():
		return "CLEAR"
	return ""
