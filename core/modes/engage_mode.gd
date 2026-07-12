class_name EngageMode
extends GameMode
## Bモード「応戦」。敵が撃ち返してくる。被弾でFAIL。
##   勝ち: 悪人全滅 → CLEAR
##   負け: 被弾3発 → DOWNED ／ 民間人を撃つ → CIVILIAN DOWN ／ 撃ち漏らし弾切れ → AMMO OUT
##
## 2本の緊張の柱：
##  ① 反撃タイマー（位置特定ゲージ）：こちらが撃つたびゲージ上昇→満タンで敵の射撃が正確に。
##    撃たずに待てば下がる＝「撃つほど自分が危険」のジレンマ。
##  ② カバー撃ち：敵は遮蔽から周期的に顔を出して撃つ（EnemyShooter）。
##    出た一瞬に撃ち返す＝もぐら叩き×狙撃。
##
## HUDは hud_extra() 経由（位置特定ゲージ・被弾数・被弾警告）。hud.gd は改造しない。

const MAX_HITS := 3              # 被弾がこの数に達したらFAIL
const DETECT_PER_SHOT := 0.34    # 1発撃つと位置特定ゲージがこれだけ上昇
const DETECT_DECAY := 0.14       # 撃たなければ毎秒これだけ減衰
const ENEMY_ACC_MIN := 0.14      # ゲージ0での敵1発の命中率
const ENEMY_ACC_MAX := 0.80      # ゲージ満タンでの敵1発の命中率
const UNDER_FIRE_HOLD := 1.2     # 被弾直後に「UNDER FIRE」を出す時間(秒)

var _shooters: Array = []
var _hits_taken := 0
var _detection := 0.0
var _civilian_down := false
var _under_fire_t := 0.0
var _damage_flash: DamageFlash


func setup(stage_ref: SniperStage) -> void:
	super.setup(stage_ref)
	# 伏せ（カバー）を有効化：伏せ中は敵弾が当たらない代わりに撃てない。
	# 「撃つ→狙われる→伏せて凌ぐ→起きて撃ち返す」が応戦モードの基本リズムになる
	stage.crouch_enabled = true
	# 被弾フィードバック（赤ビネット＋全画面フラッシュ）を画面へ
	_damage_flash = DamageFlash.new()
	stage.add_child(_damage_flash)
	# 悪人1体ごとに撃ち返し行動を付与する。既に動く敵（歩行）は遮蔽を作らず、
	# 静止している敵にはカバー壁＋顔出しサイクルを与える
	for t in stage.hostiles:
		if not (t is TargetHuman):
			continue
		var sh := EnemyShooter.new()
		sh.stage = stage
		sh.target = t
		sh.use_cover = not _is_walker(t)
		sh.on_player_hit = _on_player_hit
		stage.add_child(sh)
		sh.begin()
		_shooters.append(sh)


## ステージの歩行標的（PathFollow3Dで動く敵）かどうか
func _is_walker(t: Node) -> bool:
	for w in stage._walkers:
		if w.target == t:
			return true
	return false


func on_fire() -> void:
	# 撃つと自分の位置がバレる＝ゲージ上昇
	_detection = clampf(_detection + DETECT_PER_SHOT, 0.0, 1.0)


func on_hit(target: Node, _zone: String) -> void:
	if not target.hostile:
		_civilian_down = true


func tick(delta: float) -> void:
	# 撃たなければゲージ減衰。ゲージが高いほど敵の命中率が上がる
	_detection = maxf(_detection - DETECT_DECAY * delta, 0.0)
	_under_fire_t = maxf(_under_fire_t - delta, 0.0)
	var acc := lerpf(ENEMY_ACC_MIN, ENEMY_ACC_MAX, _detection)
	for sh in _shooters:
		if is_instance_valid(sh):
			sh.accuracy = acc


## 敵の射撃がプレイヤーに当たった（EnemyShooter から呼ばれる）
func _on_player_hit() -> void:
	_hits_taken += 1
	_under_fire_t = UNDER_FIRE_HOLD
	if _damage_flash != null:
		_damage_flash.flash(_hits_taken, MAX_HITS)  # 赤フラッシュ＋蓄積ビネット


func check_fail() -> String:
	if _civilian_down:
		return "CIVILIAN DOWN"
	if _hits_taken >= MAX_HITS:
		return "DOWNED"
	if stage.ammo <= 0 and stage.bullets_in_flight <= 0 and not stage.is_replay_active():
		return "AMMO OUT"
	return ""


func check_win() -> String:
	if stage.hits >= stage.hostiles.size():
		return "CLEAR"
	return ""


func hud_extra() -> Dictionary:
	var lines := ["HITS TAKEN %d/%d" % [_hits_taken, MAX_HITS]]
	if _under_fire_t > 0.0:
		lines.append("!! UNDER FIRE !!")
	# ゲージ色：低い=青(安全)→高い=赤(危険)
	var col := Color(0.45, 0.8, 1.0).lerp(Color(1.0, 0.32, 0.28), _detection)
	return {
		"lines": lines,
		"gauges": [{"label": "DETECTION", "value": _detection, "color": col}],
	}
