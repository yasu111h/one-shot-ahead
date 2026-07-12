class_name SniperStage
extends Node3D
## 狙撃ステージの共通基底。環境・入力・射撃・照準減速・バレットカムを持つ。
## 勝敗ルールは GameMode（core/modes/）に委譲：mode が未指定なら選択中のモード
## （既定はA精密＝PrecisionMode・従来挙動）が入る。射撃イベントは
## on_fire/on_hit/on_miss、毎フレームは tick、勝敗は check_win/check_fail で回す。
## ステージ固有（見た目・地形・標的配置・狙撃地点）はサブクラスが下記を上書きする:
##   _build_environment() … 空・光・フォグ
##   _build_world()       … 地形/建物
##   _spawn_targets()     … 標的の配置（_register / _add_walker を使う）
##   _rig_position()      … 狙撃地点
##   _setup_wind()        … 風（既定はランダム横風。Ballistics.WIND_ENABLED=false の間は
##                            弾に影響せずHUDにも出ない。風を復活させたら自動で有効化）
##
## 操作（TABIJIの操作感・マウスキャプチャなし）:
##   視点   … 右ドラッグ（PC）/ 画面のどこでもドラッグ（タッチ・最初の1本指を追跡）
##   発射   … 左クリック / FIREボタン（Fキーは予備）
##   スコープ … Qキー / SCOPEボタンでトグル巡回（1x→4x→8x→1x）。ホイールで段階±1
## ※ 息止めは廃止（照準は常に静止・2026-07-10ユーザー決定）
## ※ オートエイム（発射方向の吸い付き）は廃止（2026-07-10ユーザー決定）。
##    弾は常に照準レイどおりに飛ぶ＝当てるのはプレイヤー自身。
##    代わりに「照準減速（スティッキーエイム・CoD方式）」で標的付近の微調整だけを楽にする

const WIND_FACTOR := 0.6  # 風速(m/s)→弾への加速度(m/s^2)係数
const RANGE_MASK := 0b1111
const TERRAIN_MASK := 0b0001
const GLASS_MASK := 0b10000  # 窓ガラス(レイヤ5)。割れるだけで弾は逸れない・止まらない
# バレットカムのクールダウンは廃止（2026-07-10ユーザー決定：対象弾は毎回リプレイする）

@export var muzzle_speed := 850.0  # 弾速 m/s（装備武器の値で_readyに上書きされる）
@export var max_ammo := 30         # 総弾数（同上。マガジン込み・尽きたらAMMO OUT対象）

# --- 照準減速(スティッキーエイム・CoD方式)。弾は曲げず、敵標的の近くでだけ感度を落とす ---
@export var stick_angle := 2.5       # 減速ゾーンのしきい角(度)。照準レイと標的の最接近角がこの内側で減速
@export var stick_slow := 0.35       # 標的中心での感度倍率。ゾーン外縁1.0→中心でこの値へ角度補間
@export var stick_touch_mult := 1.5  # タッチ端末は指で粗いのでゾーンを広めに

var wind_speed := 0.0
var wind_accel := Vector3.ZERO
var ammo := 0               # 総残弾（マガジン込み）。モードのAMMO OUT判定はこれを見る
var hits := 0

# --- 武器（マガジン制・docs/武器・ショップ設計.md）---
var weapon: Dictionary = {}  # 装備中の武器データ（WeaponDb。テストは_ready前に注入可）
var mag := 0                # マガジン残弾。0になると自動リロード
var mag_size := 6
var reloading := false      # リロード中（撃てない・HUDがRELOADING表示に使う）
var _reload_t := 0.0
var _fire_cd := 0.0         # 発射間隔の残り(秒)
var _fire_held := false     # FIRE押しっぱなし（フルオート武器の連射用）
var targets: Array = []    # 弾道予測の対象（悪人＋民間人。民間人も「弾を止める者」として要る）
var hostiles: Array = []   # 撃つべき標的（勝敗判定はこの数で行う）
var bullets_in_flight := 0
var game_over := false

var mode: GameMode          # ゲームモード（A精密/B応戦/C物量…）。未指定なら選択中or精密が入る
# モードが制御するリプレイ方針（C物量は要所以外を抑制する。既定は従来どおり毎回リプレイ）
var replay_enabled := true        # falseの間は命中確定弾もリプレイせず実弾で見せる
var miss_replay_allowed := true   # falseの間はミスリプレイを出さない（ユーザー設定より優先）
var rig: SniperCamera
var girl: SniperGirl        # 主人公アバター（非スコープ時のみ表示）
var bullet_cam: BulletCam
var fx: ShotFx
var sfx: SfxBank
var hud: Hud
var debug: TrajectoryDebug  # 弾道検証デバッグ（F3でON/OFF・デバッグビルド専用）

## カメラから見た主人公の立ち位置（リグローカル）。ステージが足場の高さに合わせて上書きする
var girl_offset := Vector3(-0.55, -1.8, -1.0)

var _walkers: Array = []  # {follow: PathFollow3D, target: Node, speed: float, dir: float}
var _pending_fire := false
var _cam_touch_index := -1
var _touch_pts := {}      # 押下中の全タッチ index -> 現在位置（ピンチ判定用）
var _pinch_dist := -1.0   # ピンチ中の指の間隔(px)。-1=ピンチしていない
var _is_touch := false
var _stick_factor := 1.0  # 照準減速の現在値(物理フレームごとに更新。1.0=減速なし)


func _ready() -> void:
	GameManager.reset_time()
	_is_touch = DisplayServer.is_touchscreen_available()
	# 装備武器の数値を射撃コアへ反映（テストが weapon を注入済みならそれを使う）
	if weapon.is_empty():
		weapon = WeaponDb.equipped()
	muzzle_speed = weapon.speed
	max_ammo = weapon.total
	mag_size = weapon.mag
	mag = mag_size
	ammo = max_ammo
	_build_environment()
	_build_world()
	_setup_wind()
	_spawn_targets()
	_build_cameras()
	_build_fx()
	_build_hud()
	_build_debug()
	# ゲームモード（ステージ・テストが事前に注入していなければ、選択中のモードを生成）
	if mode == null:
		mode = GameManager.create_selected_mode()
	mode.setup(self)
	if has_node("/root/Music"):
		Music.play_game()   # プレイBGMへ（リトライでは鳴り直さない）


# ---------------------------------------------------------------- サブクラスの差し替え点

func _build_environment() -> void:
	pass


func _build_world() -> void:
	pass


func _spawn_targets() -> void:
	pass


## 狙撃地点（カメラリグの位置）
func _rig_position() -> Vector3:
	return Vector3.ZERO


## リグの追加設定（視点の可動範囲など）。サブクラスが上書きする
func _configure_rig() -> void:
	pass


## ステージ開始時のランダムな横風（X軸方向）
func _setup_wind() -> void:
	wind_speed = randf_range(-5.0, 5.0)
	wind_accel = Vector3(wind_speed, 0, 0) * WIND_FACTOR


# ---------------------------------------------------------------- 標的の登録

## 標的をステージに登録する（add_childは呼び出し側で済ませておく）
func _register(t: Node) -> void:
	targets.append(t)
	if t.hostile:
		hostiles.append(t)


## 2点間を往復する歩行標的を作る。from/to は「胴体中心」のワールド座標
func _add_walker(from: Vector3, to: Vector3, speed: float, hostile := true) -> TargetHuman:
	var path := Path3D.new()
	var curve := Curve3D.new()
	curve.add_point(from)
	curve.add_point(to)
	path.curve = curve
	add_child(path)
	var follow := PathFollow3D.new()
	follow.loop = false
	follow.rotation_mode = PathFollow3D.ROTATION_Y
	path.add_child(follow)
	var man := TargetHuman.new()
	man.hostile = hostile
	follow.add_child(man)
	_register(man)
	_walkers.append({"follow": follow, "target": man, "speed": speed, "dir": 1.0})
	return man


## その場に立つ標的を作る（民間人はこれ）
func _add_standing(pos: Vector3, hostile := true) -> TargetHuman:
	var man := TargetHuman.new()
	man.hostile = hostile
	add_child(man)
	man.global_position = pos
	_register(man)
	return man


# ---------------------------------------------------------------- 組み立て

func _build_cameras() -> void:
	rig = SniperCamera.new()
	add_child(rig)
	rig.recoil_kick *= weapon.recoil  # 武器の反動倍率（正確さは全武器同じ・扱いやすさだけの差）
	rig.position = _rig_position()
	_configure_rig()
	# 主人公アバター：リグ（ヨー回転ノード）の子にして視点の左右に体ごと追従させる。
	# カメラの少し前・左下に立つ＝肩越しの三人称。スコープ中は非表示（一人称へ）
	girl = SniperGirl.new()
	rig.add_child(girl)
	girl.position = girl_offset
	# 起動時は最も近い標的がほぼ画面中央に見える向きにする
	var nearest := _nearest_hostile()
	if nearest != null:
		rig.aim_at(nearest.global_position)
	bullet_cam = BulletCam.new()
	add_child(bullet_cam)
	bullet_cam.finished.connect(_check_end)


func _nearest_hostile() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for t in hostiles:
		if not (t is Node3D) or not is_instance_valid(t) or not t.is_inside_tree():
			continue
		var d: float = rig.global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


func _build_fx() -> void:
	fx = ShotFx.new()
	add_child(fx)
	sfx = SfxBank.new()
	add_child(sfx)


func _build_hud() -> void:
	hud = Hud.new()
	hud.stage = self
	hud.rig = rig
	hud.mission = _mission_text()
	add_child(hud)


func _build_debug() -> void:
	debug = TrajectoryDebug.new()
	debug.stage = self
	add_child(debug)


## HUD左上に出すミッション文（サブクラスが上書き。空なら非表示）
func _mission_text() -> String:
	return ""


## HUDが照準UIの表示/非表示に使う（バレットカム上映中か）
func is_replay_active() -> bool:
	return bullet_cam != null and bullet_cam.active


# ---------------------------------------------------------------- 入力

func _unhandled_input(event: InputEvent) -> void:
	# タッチ：1本指ドラッグ＝画面のどこでも視点回転／2本指ピンチ＝スコープ倍率の連続変更。
	# ボタン（FIRE/SCOPE等のTouchScreenButton・右上のButton群）上のタッチは
	# そちらが消費して_unhandled_inputまで届かないので、ここに来た指は視点・ピンチ用でよい
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_pts[event.index] = event.position
			if _cam_touch_index == -1:
				_cam_touch_index = event.index
		else:
			_touch_pts.erase(event.index)
			if event.index == _cam_touch_index:
				# 視点用の指が離れたら、残っている指へ引き継ぐ（持ち替えが自然になる）
				_cam_touch_index = _touch_pts.keys()[0] if not _touch_pts.is_empty() else -1
		if _touch_pts.size() < 2:
			_pinch_dist = -1.0  # ピンチ終了
		return
	if event is InputEventScreenDrag:
		_touch_pts[event.index] = event.position
		if _touch_pts.size() >= 2:
			# ピンチ：最初の2本の指の間隔の変化率でズーム（ピンチ中は視点を回さない）。
			# 指同士が近すぎる間(40px未満)は距離比が暴れるのでズームしない
			var ks := _touch_pts.keys()
			var d: float = (_touch_pts[ks[0]] as Vector2).distance_to(_touch_pts[ks[1]])
			if _pinch_dist > 40.0 and d > 40.0 and not is_replay_active():
				rig.pinch_zoom(d / _pinch_dist)
			_pinch_dist = d
		elif event.index == _cam_touch_index and not is_replay_active():
			rig.add_aim_delta(event.relative * _stick_factor)  # 照準減速を掛ける
		return
	# マウス（Mac用）。タッチ端末で実タッチから合成されるエミュレートマウスだけを
	# 無視し、実マウスは端末判定に関わらず常に受け付ける
	# （※旧実装の「タッチ端末なら全マウス無視」は、端末誤判定時にMacの
	#   クリック・右ドラッグが全滅するため device 判定に変更）
	if event.device == InputEvent.DEVICE_ID_EMULATION and not (event is InputEventKey):
		return
	if event is InputEventMouseMotion:
		# 右ドラッグ＝視点回転（押している間だけ・キャプチャなし）
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not is_replay_active():
			rig.add_aim_delta(event.relative * _stick_factor)  # 照準減速を掛ける
		return
	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					set_fire_held(true)   # フルオート武器は押している間連射
					request_fire()        # 左クリック＝発射
				MOUSE_BUTTON_WHEEL_UP:
					rig.step_zoom(1)
				MOUSE_BUTTON_WHEEL_DOWN:
					rig.step_zoom(-1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			set_fire_held(false)
		return
	if event is InputEventKey and not event.echo:
		match event.keycode:
			KEY_Q:
				if event.pressed:
					rig.cycle_zoom()  # Q＝スコープトグル（1x→4x→8x→1x）
			KEY_F:
				if event.pressed:
					request_fire()  # 予備の発射キー
			KEY_F3:
				if event.pressed and OS.is_debug_build:
					debug.toggle_enabled()  # F3＝弾道デバッグ表示ON/OFF
			KEY_TAB:
				if event.pressed and OS.is_debug_build:
					debug.cycle_view()  # Tab＝デバッグ視点切替（通常→真横→着弾点）
			KEY_ESCAPE:
				if event.pressed:
					GameManager.goto_select()  # ステージ選択へ戻る


# ---------------------------------------------------------------- 射撃

func request_fire() -> void:
	if game_over or is_replay_active() or ammo <= 0 or _pending_fire:
		return
	if reloading or mag <= 0 or _fire_cd > 0.0:
		return  # リロード中・マガジン切れ・発射間隔内は撃てない
	_pending_fire = true  # 物理フレームで発射（空間クエリの安全のため）


## FIREボタン/左クリックの押しっぱなし状態（フルオート武器の連射用。HUDと入力が更新する）
func set_fire_held(held: bool) -> void:
	_fire_held = held


## マガジンが空になったら自動でリロード（docs/武器・ショップ設計.md）
func _start_reload() -> void:
	if reloading or ammo <= 0:
		return
	reloading = true
	_reload_t = weapon.reload


func _physics_process(delta: float) -> void:
	# 歩行標的のPath3D追従（往復）
	for w in _walkers:
		if not w.target.alive:
			continue
		var f: PathFollow3D = w.follow
		f.progress += w.speed * w.dir * delta
		var length: float = (f.get_parent() as Path3D).curve.get_baked_length()
		if f.progress >= length:
			w.dir = -1.0
		elif f.progress <= 0.0:
			w.dir = 1.0
	# 武器の時間管理：発射間隔・リロード進行・フルオート連射
	_fire_cd = maxf(_fire_cd - delta, 0.0)
	if reloading:
		_reload_t -= delta
		if _reload_t <= 0.0:
			reloading = false
			mag = mini(mag_size, ammo)  # 残りの総弾数ぶんだけ込める
	elif weapon.get("auto", false) and _fire_held:
		request_fire()  # フルオート：押しっぱなしで発射間隔ごとに連射
	# 発射処理
	if _pending_fire:
		_pending_fire = false
		_do_fire()
	# 主人公アバターはスコープを覗き込むまで見える（覗いたら一人称＝非表示）。
	# バレットカム上映中は「角で構える姿」が画に入るので表示したままにする
	if girl != null:
		girl.visible = rig.aim_blend < 0.5 or is_replay_active()
		# 上下の狙いに合わせて上半身と銃口を向ける（左右はリグの回転で追従済み）
		girl.set_aim_pitch(rig.get_aim_pitch())
	# 照準減速(スティッキーエイム)の更新。空間クエリを使うので物理フレームで計算し、
	# 入力イベント側はこのキャッシュ値を使う。減速ゾーン内はレティクル中心点が控えめに色づく
	# （旧オートエイムの「オレンジ＝撃てば当たる」保証ではない。当てるのはプレイヤー自身）
	_stick_factor = 1.0
	if not game_over and not is_replay_active():
		_stick_factor = _stick_speed_scale()
	hud.set_sticky(_stick_factor < 1.0)
	# 測距（照準先の距離をHUDへ）
	_update_rangefinder()
	# モードの毎フレーム処理と時間経過系の勝敗（接近・被弾などはモードが判定する）
	if not game_over and mode != null:
		mode.tick(delta)
		_check_end()


func _do_fire() -> void:
	if game_over or is_replay_active() or ammo <= 0 or reloading or mag <= 0:
		return
	ammo -= 1
	mag -= 1
	_fire_cd = weapon.cooldown
	if mag <= 0 and ammo > 0:
		_start_reload()  # マガジンが空＝自動リロード
	var cam := rig.camera
	# 照準レイ（画面中央）そのまま。発射方向の「補正」は一切ない＝当てるのはプレイヤー自身
	var dir := -cam.global_transform.basis.z
	# 弾のばらつき（散布）：撃った瞬間に、標的が遠いほど大きくランダムにずれる。
	# 予測より前に掛けるので、バレットカム・デバッグ・実弾のすべてが同じずれで一致する
	dir = _apply_spread(dir)
	var start := cam.global_position + dir * 0.6
	# 弾道予測には民間人も混ぜる。手前に立たれていたら悪人への命中は「確定」しない
	var infos := _target_infos()
	var predicted := _predict(start, dir, infos)
	# 弾道デバッグ（F3）：この1発の「レティクルが指していた点」と、実弾と同一の
	# 積分・当たり判定で一括シミュレートした実弾道（赤線）をその場で記録
	debug.on_fire(cam.global_position, dir, false)
	debug.simulate_real(start, dir * muzzle_speed, wind_accel)
	# 撃ち味（反動・マズルフラッシュ・レティクル開き・発射音）
	rig.kick()
	fx.muzzle_flash(start)
	hud.on_shot()
	sfx.play_shot()
	mode.on_fire()
	# 悪人への命中確定弾は毎回バレットカムになる（民間人への誤射は演出せず実弾で見せる）
	# ※ モードが replay_enabled=false の間、またはユーザーがHITリプレイをOFFにした間は抑制。
	#   OFF時は実弾が飛んで着弾で倒す（キルカムなしの即時撃破）
	if not predicted.is_empty() and predicted.target.hostile and replay_enabled \
			and Settings.hit_replay_enabled:
		_start_replay(start, predicted, dir)
		return
	# ミス弾（何にも当たらない弾）も、設定ONならバレットカムで見送る
	# （誤射＝民間人命中の予測弾は従来どおり実弾で見せる）
	if predicted.is_empty() and Settings.miss_replay_enabled and miss_replay_allowed \
			and not _prop_on_line(start, dir):
		_start_miss_replay(start, dir)
		return
	# 通常弾：実弾（Ballisticsの毎フレーム積分。既定は直線・等速）を飛ばし、
	# トレーサーを追従させる
	var bullet := Bullet.new()
	add_child(bullet)
	bullet.global_position = start
	bullet.velocity = dir * muzzle_speed
	bullet.wind_accel = wind_accel
	bullet.hit.connect(_on_bullet_hit.bind(bullet))
	bullet.vanished.connect(_on_bullet_vanished)
	bullet.glass_hit.connect(_on_bullet_glass)
	bullets_in_flight += 1
	fx.attach_tracer(bullet)


## 生きている標的の弾道予測用スナップショット
func _target_infos() -> Array:
	var infos: Array = []
	for t in targets:
		if t.alive:
			infos.append({
				"node": t,
				"position": t.global_position,
				"velocity": t.velocity_estimate,
				"radius": t.predict_radius,
				"head_offset": t.head_offset,
				"head_radius": t.head_radius,
			})
	return infos


func _predict(start: Vector3, dir: Vector3, infos: Array) -> Dictionary:
	return Ballistics.predict_hit(
		get_world_3d().direct_space_state, start, dir * muzzle_speed, wind_accel, infos)


## 命中確定弾のバレットカム開始。実弾は飛ばさず、確定弾道をスロー再生し、
## ダメージ適用は「リプレイの着弾の瞬間」（on_impact）に行う。
func _start_replay(start: Vector3, predicted: Dictionary, dir: Vector3) -> void:
	var target: Node = predicted.target
	var zone: String = predicted.get("zone", "body")
	var point: Vector3 = predicted.point
	# 動く標的の補正：予測着弾点は「実飛翔時間ぶん未来」の位置なので、
	# リプレイ中に実際へ進む世界時間（SLOWMO×再生時間）の位置へ引き戻す。
	# これでリプレイの弾は「その瞬間に標的がいる場所」へ命中して見える。
	# 再生時間は飛行距離で決まるため、ここでも同じ式（flight_time_for）を使う
	var tvel: Vector3 = target.velocity_estimate if is_instance_valid(target) else Vector3.ZERO
	var replay_world_dt: float = BulletCam.SLOWMO \
		* BulletCam.flight_time_for(start.distance_to(point))
	var to: Vector3 = point - tvel * (predicted.time - replay_world_dt)
	debug.on_replay(start, to)  # 弾道デバッグ：リプレイ弾道（黄線）の始点・終点を記録
	_schedule_replay_glass(start, to)
	# 加速度と実飛行時間を渡す＝重力ONならリプレイ弾も実弾と同じ放物線を描く
	bullet_cam.play(start, to, func() -> void:
		_on_replay_impact(target, to, zone, dir),
		Ballistics.effective_accel(wind_accel), predicted.time)


## ミス弾のバレットカム開始。地面への着弾予測点（最大射程まで何にも当たらなければ
## 最大射程点）までスロー再生する。ダメージはなく、余韻突入時に「MISS」表示と、
## 地面着弾なら土煙FX（着弾フレア＋火花）を出す。
func _start_miss_replay(start: Vector3, dir: Vector3) -> void:
	var impact := Ballistics.predict_miss_point(
		get_world_3d().direct_space_state, start, dir * muzzle_speed, wind_accel)
	var point: Vector3 = impact.point
	var normal: Vector3 = impact.normal
	var grounded: bool = impact.grounded
	debug.on_replay(start, point)  # 弾道デバッグ：ミスリプレイ弾道も黄線で記録
	_schedule_replay_glass(start, point)
	# 加速度と実飛行時間を渡す＝重力ONならリプレイ弾も実弾と同じ放物線を描く
	bullet_cam.play(start, point, func() -> void:
		if grounded:
			# ビルの窓(シェーダ描き)ならガラス割れ演出。それ以外は地形着弾の演出
			if WindowBreak.try_break(self, point, normal, dir):
				sfx.play_glass()
			else:
				_impact_effect(point, normal)
		hud.show_miss_stamp()
		mode.on_miss(),
		Ballistics.effective_accel(wind_accel), impact.time)


## リプレイの着弾の瞬間：ここで初めてダメージ・スタンプ・ヒットマーカー・命中音を出す
## （倒れる様子はバレットカムの余韻＝HOLD_SLOWMO 0.7秒の中で見える）
func _on_replay_impact(target: Node, point: Vector3, zone: String, dir: Vector3) -> void:
	if not is_instance_valid(target) or not target.alive:
		return
	var dist := int(round(rig.camera.global_position.distance_to(point)))
	target.die(dir * 3.0)
	hits += 1
	var reward := _award_kill(dist, zone)
	hud.show_stamp("%dm %s  +$%d" % [dist, "HEADSHOT" if zone == "head" else "HIT", reward])
	hud.show_hitmark(zone)
	if zone == "head":
		sfx.play_headshot()
	else:
		sfx.play_hit()
	mode.on_hit(target, zone)
	# 勝敗判定はバレットカム終了時（finishedシグナル→_check_end）に行う


func _update_rangefinder() -> void:
	var from := rig.camera.global_position
	var dir := -rig.camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 1500.0, RANGE_MASK)
	query.collide_with_areas = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		hud.range_distance = from.distance_to(result.position)
	else:
		hud.range_distance = -1.0


# ---------------------------------------------------------------- 弾のばらつき（散布）

## 距離連動の散布角の上限(rad)。基準＝600m先で窓1枚（横幅5m）ぶんずれうる。
## 角度上限が距離に比例して育つため、着弾のずれは距離の二乗で効く
## （例: 200mで±0.56m・400mで±2.2m・600mで±5m）。
const SPREAD_REF_DIST := 600.0   # 基準距離(m)
const SPREAD_REF_DEV := 5.0      # 基準距離での最大ずれ幅(m)＝都市ステージの窓の横幅

## 発射方向にランダムな散布を掛ける（照準は静止のまま・弾だけがずれる）。
## HUDのSPREADトグルでOFFにすると素通し
func _apply_spread(dir: Vector3) -> Vector3:
	if not Settings.spread_enabled:
		return dir
	var d: float = hud.range_distance
	if d <= 0.0:
		return dir  # 測距なし（空など）＝ずらす意味がない
	# 武器のばらつき倍率（高精度ライフルは小さく・LMGは大きい）
	var max_ang := (SPREAD_REF_DEV / SPREAD_REF_DIST) * (d / SPREAD_REF_DIST) \
		* float(weapon.get("spread", 1.0))
	# 円盤内で一様にばらす（sqrtで中心偏重を打ち消す）＋方位はランダム
	var ang := max_ang * sqrt(randf())
	var azim := randf() * TAU
	var side := dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var offset_dir := (side * cos(azim) + up * sin(azim)).normalized()
	return (dir + offset_dir * tan(ang)).normalized()


## 射線上にプロップ（乗り物レイヤのうちprop_owner持ち＝反応する車）がいるか。
## いる場合はミスリプレイにせず実弾を飛ばす＝命中の瞬間に部位リアクションが出る。
## （ミスリプレイの着弾予測は地形しか見ないため、車を素通りする映像になるのを防ぐ）
func _prop_on_line(start: Vector3, dir: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(start, start + dir * 1500.0, 0b1000)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider != null and hit.collider.has_meta("prop_owner")


# ---------------------------------------------------------------- 照準減速(スティッキーエイム)

## 照準減速: 照準レイの近くに「見えている敵標的」がいる間だけドラッグ感度を落とし、
## 標的付近の微調整をやりやすくする（CoD方式）。戻り値はドラッグ入力に掛ける倍率。
## 照準を勝手に動かす・発射方向を曲げることは一切しない＝入力の効きを弱めるだけ。
## 判定は「照準レイと標的部位の最接近角」。しきい角 stick_angle の外なら1.0（減速なし）、
## 外縁で1.0→標的中心（角度0）で stick_slow へ角度に応じて線形補間する。
## ※ 民間人では減速しない。減速は弾を曲げないので誤射は作らないが、
##    民間人に照準が「粘る」感触自体が誤誘導になるため（減速＝敵の合図に統一）。
## ※ 壁・床の陰で見えていない標的も対象外（旧オートエイムの可視判定を流用）。
func _stick_speed_scale() -> float:
	var deg := stick_angle
	if _is_touch:
		deg *= stick_touch_mult
	var limit := deg_to_rad(deg)
	var best := limit
	var eye := rig.camera.global_position
	var base := -rig.camera.global_transform.basis.z
	for n in get_tree().get_nodes_in_group("target_part"):
		if not (n is Node3D) or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var root = n.get_meta("target_root") if n.has_meta("target_root") else null
		if root == null or not is_instance_valid(root) or not root.alive or not root.hostile:
			continue
		var point := _aim_point(n, eye, base)
		var ang := base.angle_to(point - eye)
		if ang >= best:
			continue
		if _blocked_by_terrain(eye, point):
			continue  # 壁・床の陰。見えていない標的では減速しない
		best = ang
	if best >= limit:
		return 1.0
	return lerpf(stick_slow, 1.0, best / limit)


## 視線が地形（レイヤ1）で遮られているか
func _blocked_by_terrain(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, TERRAIN_MASK)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## 狙撃地点からその点が見えているか（HUDの標的マーカーが使う）
func has_line_of_sight(point: Vector3) -> bool:
	if rig == null or rig.camera == null:
		return false
	return not _blocked_by_terrain(rig.camera.global_position, point)


## 部位の狙い点。カプセル(胴体)なら芯線のうちレイに最も近い点、それ以外は中心。
func _aim_point(n: Node3D, eye: Vector3, base: Vector3) -> Vector3:
	for c in n.get_children():
		if c is CollisionShape3D and c.shape is CapsuleShape3D:
			var cap: CapsuleShape3D = c.shape
			var half := maxf(cap.height * 0.5 - cap.radius, 0.0)
			var up: Vector3 = (c as CollisionShape3D).global_transform.basis.y
			var center: Vector3 = (c as CollisionShape3D).global_position
			return _closest_on_segment_to_ray(center - up * half, center + up * half, eye, base)
	return n.global_position


## 線分AB上で、レイ(origin O・方向D)に最も近い点を返す
func _closest_on_segment_to_ray(a: Vector3, b: Vector3, o: Vector3, d: Vector3) -> Vector3:
	var u := b - a
	var w := a - o
	var uu := u.dot(u)
	var ud := u.dot(d)
	var dd := d.dot(d)
	var uw := u.dot(w)
	var dw := d.dot(w)
	var den := uu * dd - ud * ud
	var s := 0.0
	if den > 0.0001:
		s = clampf((ud * dw - dd * uw) / den, 0.0, 1.0)
	return a + u * s


# ---------------------------------------------------------------- ガラス

## 実弾がガラスを通過した（弾は止まらず、割るだけ）
func _on_bullet_glass(result: Dictionary, dir: Vector3) -> void:
	var pane: Object = result.collider
	if pane != null and pane.has_method("shatter"):
		# 音が先・破片が後: shatter()は破片ノードの大量生成で処理落ちすることがあり、
		# 音を後に置くとそのぶん遅れて聞こえる(命中音との順番が逆転する一因)
		sfx.play_glass()
		pane.shatter(result.position, dir)


## リプレイ弾道(from→to)上のガラスを「リプレイの弾が通過する瞬間」に割る。
## バレットカムはスロー(time_scale)で進むので、タイマーは実時間
## (ignore_time_scale)で刻む＝等速再生のリプレイ弾の位置と正確に同期する。
func _schedule_replay_glass(from: Vector3, to: Vector3) -> void:
	var total := from.distance_to(to)
	if total < 0.5:
		return
	var dir := (to - from) / total
	var pos := from
	for i in 3:
		var query := PhysicsRayQueryParameters3D.create(pos, to, GLASS_MASK)
		query.collide_with_areas = true
		var g := get_world_3d().direct_space_state.intersect_ray(query)
		if g.is_empty():
			return
		var pane: Object = g.collider
		var point: Vector3 = g.position
		# ガラスが割れる時刻＝リプレイ弾がそこを通過する瞬間（再生時間は飛行距離で決まる）。
		# ただし標的の直前のガラス（窓越しの狙撃）は通過が命中とほぼ同時刻になり、
		# 「命中音→ガラス音」と逆順に聞こえてしまう。
		# 割れは必ず命中の0.35秒以上前に先行させ、耳ではっきり
		# 「パリン(ガラス)→ドッ(命中)」の順になるようにする
		var t_total := BulletCam.flight_time_for(total)
		var delay: float = minf(
			from.distance_to(point) / total * t_total,
			t_total - 0.35)
		delay = maxf(delay, 0.0)
		# タイマーはシーンよりも長生きするので、リトライ等で破棄済みなら何もしない
		get_tree().create_timer(delay, true, false, true).timeout.connect(func() -> void:
			if not is_instance_valid(self) or not is_instance_valid(pane):
				return
			if pane.has_method("shatter"):
				# 音が先・破片が後(生成の処理落ちで音が遅れないように)
				sfx.play_glass()
				pane.shatter(point, dir))
		pos = point + dir * 0.1  # 同じ板を二重検知しないよう少し先へ進めて再走査


# ---------------------------------------------------------------- 命中処理（通常弾）

func _on_bullet_hit(result: Dictionary, bullet: Bullet) -> void:
	bullets_in_flight -= 1
	var collider: Object = result.collider
	var normal: Vector3 = result.get("normal", Vector3.UP)
	if collider and collider.has_meta("target_root"):
		_handle_target_hit(result, bullet)
	elif collider and collider.has_meta("prop_owner"):
		# 汎用プロップ（走る車など）: 持ち主に部位リアクションを任せる
		# （エンジン炎上・タイヤパンク等。標的ではないのでミス扱いは変わらない）
		var owner: Object = collider.get_meta("prop_owner")
		var handled := false
		if owner != null and is_instance_valid(owner) and owner.has_method("on_prop_shot"):
			handled = owner.on_prop_shot(collider, result.position, bullet.velocity.normalized())
		if not handled:
			fx.impact_burst(result.position, normal)
		mode.on_miss()
		_check_end()
	else:
		# ビルの窓(シェーダ描き)ならガラス割れ演出。それ以外は地形着弾の演出
		if WindowBreak.try_break(self, result.position, normal, bullet.velocity.normalized()):
			sfx.play_glass()
		else:
			_impact_effect(result.position, normal)
		mode.on_miss()
		_check_end()


func _on_bullet_vanished() -> void:
	bullets_in_flight -= 1
	mode.on_miss()
	_check_end()


func _handle_target_hit(result: Dictionary, bullet: Bullet) -> void:
	var collider: Object = result.collider
	var target: Node = collider.get_meta("target_root")
	var part: String = collider.get_meta("part", "body")
	var normal: Vector3 = result.get("normal", Vector3.UP)
	if not target.alive:
		# 既に倒れた標的への命中は不算入
		_check_end()
		return
	var dist := int(round(rig.camera.global_position.distance_to(result.position)))
	target.die(bullet.velocity.normalized() * 3.0)
	fx.impact_burst(result.position, normal)
	# 民間人の誤射＝勝敗はモードが決める（精密モードでは即FAIL）。演出は出さない
	if not target.hostile:
		sfx.play_hit()
		mode.on_hit(target, part)
		_check_end()
		return
	hits += 1
	var reward := _award_kill(dist, part)
	hud.show_stamp("%dm %s  +$%d" % [dist, "HEADSHOT" if part == "head" else "HIT", reward])
	hud.show_hitmark(part)
	if part == "head":
		sfx.play_headshot()
	else:
		sfx.play_hit()
	mode.on_hit(target, part)
	_check_end()


## 地形着弾の演出（フレア＋土煙＋小さな音）。
## 水面など特殊な着弾を持つステージはこれを上書きする（例: 山岳の川＝水しぶき）
func _impact_effect(point: Vector3, normal: Vector3) -> void:
	fx.impact_burst(point, normal)
	_spawn_impact_dust(point)
	sfx.play_impact()


func _spawn_impact_dust(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	add_child(p)
	p.global_position = pos + Vector3(0, 0.1, 0)
	p.amount = 14
	p.lifetime = 0.8
	p.one_shot = true
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.5
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.4)
	sphere.material = mat
	p.mesh = sphere
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- 報酬（お金）

const KILL_BASE_REWARD := 40      # キル1体の基礎報酬($)
const KILL_DIST_RATE := 0.5       # 距離ボーナス($/m)
const CLEAR_BONUS := 150          # クリアボーナス($)

## 悪人を倒した報酬。距離が遠いほど・ヘッドショットなら高い。即時入金し金額を返す
func _award_kill(dist: int, zone: String) -> int:
	var reward := KILL_BASE_REWARD + int(float(dist) * KILL_DIST_RATE)
	if zone == "head":
		reward *= 2
	Settings.add_money(reward)
	return reward


# ---------------------------------------------------------------- 勝敗

func _fail(msg: String) -> void:
	if game_over:
		return
	game_over = true
	hud.show_fail(msg)


## 勝敗判定（モードに委譲）。fail優先→win。どちらも空文字なら継続
func _check_end() -> void:
	if game_over or mode == null:
		return
	var fail := mode.check_fail()
	if fail != "":
		_fail(fail)
		return
	var win := mode.check_win()
	if win != "":
		game_over = true
		Settings.add_money(CLEAR_BONUS)
		hud.show_stamp("CLEAR BONUS  +$%d" % CLEAR_BONUS)
		hud.show_clear()


func retry() -> void:
	bullet_cam.abort()
	GameManager.reset_time()
	get_tree().reload_current_scene()
