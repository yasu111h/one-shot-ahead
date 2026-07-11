class_name HordeMode
extends GameMode
## Cモード「物量」。大量の敵を速く捌く。2つの勝ち筋を1プレイに直列で持つ：
##   第1部・防衛型 … 傭兵のウェーブ（3波）が奥400〜600mから防衛ラインへ接近。
##                    ライン到達でFAIL。波を全滅させると次の波
##   第2部・掃討型 … 複数標的が同時に出現。制限時間内に全消しでCLEAR。
##                    コンボ・ペナルティなし（ユーザー指示）。クリアタイムで星評価
##
## リプレイ方針（実装指示書）：要所のみ＝「最終波の最後の1体」と「掃討の最後の1体」。
## ミスリプレイは強制OFF。stage.replay_enabled / miss_replay_allowed で制御する。
##
## 敵はゾンビ禁止→傭兵（HordeRunner）。オブジェクトプールで死体を再利用して
## 同時多数でもノード数を増やし続けない。
## 舞台は当面 test_range（-Z方向へ開けた平原）を前提とした座標系。

const LINE_Z := -80.0        # 防衛ライン（生存敵がこのzより手前に来たらFAIL）
const GROUND_Y := 0.76       # 敵の立ち高さ（test_rangeの地面上）
const DANGER_RANGE := 400.0  # 防衛ラインゲージが振れ始めるライン手前距離(m)
const WAVE_BREAK := 3.0      # 波間のインターバル(秒)
const SWEEP_COUNT := 8       # 掃討の同時出現数
const SWEEP_LIMIT := 45.0    # 掃討の制限時間(秒)
const STAR3_TIME := 100.0    # 総経過がこれ未満で★3
const STAR2_TIME := 150.0    # これ未満で★2（以上は★1）

## 防衛ウェーブ定義 [体数, スポーン距離(m), 基本速度(m/s)]
const WAVES := [
	{"count": 5, "dist": 420.0, "speed": 4.5},
	{"count": 7, "dist": 500.0, "speed": 5.5},
	{"count": 9, "dist": 580.0, "speed": 6.5},
]

enum Phase { WAVE, BREAK, SWEEP, DONE }

var phase := Phase.WAVE
var wave_idx := 0

var _pool: Array = []      # 生成済みの全HordeRunner（死体をreviveで再利用）
var _active: Array = []    # 現在の波/掃討の管理対象
var _break_t := 0.0
var _sweep_t := 0.0
var _elapsed := 0.0        # モード全体の経過時間（星評価用）
var _fail_msg := ""
var _stars_shown := false


func setup(stage_ref: SniperStage) -> void:
	super(stage_ref)
	# リプレイは要所のみ：普段は命中リプレイもミスリプレイも出さない
	stage.replay_enabled = false
	stage.miss_replay_allowed = false
	_spawn_wave(0)


func tick(delta: float) -> void:
	_elapsed += delta
	match phase:
		Phase.WAVE:
			var alive := _alive_count()
			# 要所リプレイ：最終波の最後の1体だけバレットカムを許可
			stage.replay_enabled = (wave_idx == WAVES.size() - 1 and alive == 1)
			_check_line_breach()
			if alive == 0 and _fail_msg == "":
				stage.replay_enabled = false
				phase = Phase.BREAK
				_break_t = WAVE_BREAK
		Phase.BREAK:
			_break_t -= delta
			if _break_t <= 0.0:
				wave_idx += 1
				if wave_idx < WAVES.size():
					_spawn_wave(wave_idx)
					phase = Phase.WAVE
				else:
					_spawn_sweep()
					_sweep_t = 0.0
					phase = Phase.SWEEP
		Phase.SWEEP:
			_sweep_t += delta
			var alive := _alive_count()
			# 要所リプレイ：掃討の最後の1体（＝この試合の最後の敵）
			stage.replay_enabled = (alive == 1)
			if alive == 0:
				phase = Phase.DONE
				_show_stars()
		Phase.DONE:
			pass


func check_fail() -> String:
	if _fail_msg != "":
		return _fail_msg
	if phase == Phase.SWEEP and _sweep_t >= SWEEP_LIMIT and _alive_count() > 0:
		return "TIME UP"
	if phase != Phase.DONE and stage.ammo <= 0 and stage.bullets_in_flight <= 0 \
			and not stage.is_replay_active() and _alive_count() > 0:
		return "AMMO OUT"
	return ""


func check_win() -> String:
	if phase == Phase.DONE:
		return "CLEAR"
	return ""


func hud_extra() -> Dictionary:
	match phase:
		Phase.WAVE:
			return {
				"lines": ["WAVE %d/%d" % [wave_idx + 1, WAVES.size()],
					"HOSTILES LEFT %d" % _alive_count()],
				"gauges": [{"label": "DEFENSE LINE", "value": _danger(),
					"color": Color(1.0, 0.35, 0.25)}],
			}
		Phase.BREAK:
			return {"lines": ["WAVE %d CLEARED" % (wave_idx + 1), "STAND BY..."]}
		Phase.SWEEP:
			return {
				"lines": ["SWEEP — ELIMINATE ALL", "LEFT %d" % _alive_count()],
				"gauges": [{"label": "TIME",
					"value": clampf(1.0 - _sweep_t / SWEEP_LIMIT, 0.0, 1.0),
					"color": Color(0.55, 0.8, 1.0)}],
			}
	return {}


# ---------------------------------------------------------------- 波の生成

## 防衛ウェーブ：奥からジグザグで防衛ラインへ駆けてくる
func _spawn_wave(i: int) -> void:
	_active.clear()
	var w: Dictionary = WAVES[i]
	var count: int = w.count
	for k in count:
		# 横に散らばって湧く（奥行きにも少し幅を持たせて縦列にならないように）
		var fx := (float(k) / maxf(float(count - 1), 1.0)) * 2.0 - 1.0  # -1..1
		var x := fx * 90.0 + randf_range(-8.0, 8.0)
		var z: float = -w.dist + randf_range(-25.0, 25.0)
		var r := _acquire(Vector3(x, GROUND_Y, z))
		r.run_speed = w.speed + randf_range(-0.5, 1.0)
		r.weave_amp = 2.0
		r.goal = Vector3(x * 0.2, GROUND_Y, LINE_Z + 4.0)  # ラインの少し先＝必ず踏み越える
		r.advancing = true
		_active.append(r)


## 掃討：複数標的が同時に立ち現れる（動かない。数と時間で圧をかける）
func _spawn_sweep() -> void:
	_active.clear()
	for k in SWEEP_COUNT:
		var fx := (float(k) / float(SWEEP_COUNT - 1)) * 2.0 - 1.0
		var x := fx * 75.0 + randf_range(-6.0, 6.0)
		var z := randf_range(-380.0, -150.0)
		var r := _acquire(Vector3(x, GROUND_Y, z))
		r.advancing = false
		_active.append(r)


## プールから死体を再利用。無ければ新規生成してステージに登録する
func _acquire(pos: Vector3) -> HordeRunner:
	for r in _pool:
		if not r.alive:
			r.revive(pos)
			return r
	var r := HordeRunner.new()
	stage.add_child(r)
	r.global_position = pos
	stage._register(r)  # targets/hostilesへ＝照準減速・▼マーカー・着弾予測が効く
	_pool.append(r)
	return r


# ---------------------------------------------------------------- 判定・表示

func _alive_count() -> int:
	var n := 0
	for r in _active:
		if is_instance_valid(r) and r.alive:
			n += 1
	return n


## 生存敵が防衛ラインを踏み越えたらFAIL
func _check_line_breach() -> void:
	if _fail_msg != "":
		return
	for r in _active:
		if is_instance_valid(r) and r.alive and r.global_position.z > LINE_Z:
			_fail_msg = "LINE BREACHED"
			return


## 防衛ラインゲージ（0=安全 → 1=ライン到達寸前）。最も近い生存敵で振れる
func _danger() -> float:
	var worst := 0.0
	for r in _active:
		if not is_instance_valid(r) or not r.alive:
			continue
		var dist: float = LINE_Z - r.global_position.z  # ラインまでの残り距離(m)
		worst = maxf(worst, clampf(1.0 - dist / DANGER_RANGE, 0.0, 1.0))
	return worst


## クリア時の星評価（総経過時間。速いほど星が多い）
func _show_stars() -> void:
	if _stars_shown:
		return
	_stars_shown = true
	var stars := 1
	if _elapsed < STAR3_TIME:
		stars = 3
	elif _elapsed < STAR2_TIME:
		stars = 2
	stage.hud.show_stamp("%s  %d s" % ["★".repeat(stars), int(_elapsed)])
