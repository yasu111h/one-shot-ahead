extends SniperStage
## 「対向すれ違い列車」ステージ(実装指示書§5-D 併走狙撃)。
## プレイヤーは走る列車の屋根の上(-Z方向へ90km/h)。標的は隣の線路を"対向"で
## 走る列車の中(+Z方向へ80km/h)。相対速度≒170km/h(47m/s)で猛烈にすれ違うため、
## 標的の窓が一瞬だけ照準を横切る=その刹那に撃ち込む。
## 標的列車が後方へ抜けたら前方遠くへループ=「別の列車」が何度も来る
## (このときガラスは全て修復＝無傷の車両として来る)。全悪人を倒すまで繰り返す。
## 貨車の荷台や屋根の上にも見張りが立つ(車両の外の標的)。
##
## 実装: 両列車とリグは本当に走り続ける。地面・枕木・架線柱・茂みは
## 「リグ基準で周期リサイクル」して無限の車窓を作る(座標は数kmまでfloatで安全)。

const TrainLineScript := preload("res://stages/train/train_line.gd")

const PLAYER_SPEED := 25.0     # 自分の列車(m/s ≒ 90km/h・-Z方向)
const ENEMY_SPEED := -22.0     # 標的の列車(m/s ≒ 80km/h・対向=+Z方向)。相対47m/s=170km/h
const ENEMY_START_Z := -150.0  # 標的列車の初期位置(前方)。ここから対向で近づいてくる
const LOOP_BACK := 130.0       # 標的がこれだけ後方へ抜けたら次の周回へ
const LOOP_AHEAD := 270.0      # 次の周回の出現位置(リグの前方この距離)
const PLAYER_TRACK_X := 6.0    # 自分の線路の中心x
const ENEMY_TRACK_X := -6.0    # 標的の線路の中心x
var rig_y: float = TrainLineScript.ROOF_Y + 1.9   # 屋根の上に立つ目線

const ENEMY_COMP := ["pass", "pass", "flat", "pass", "tank", "pass", "pass", "pass"]
const CIVIL_CARS := [5, 6]     # 民間人が乗る客車(通し番号)
const WALK_CARS := [0, 1, 3, 7]  # 悪人が通路を歩く客車
const ROOF_CARS := [1, 5]      # 屋根に見張りが立つ客車

var ptrain          # 自分の列車
var etrain          # 標的の列車
var _enemy_len := 0.0
var _sway_t := 0.0
var _followers: Array = []     # リグに完全追従する景観 [Node3D]
var _cyclers: Array = []       # 周期リサイクルする景観 [{node, period}]


func _rig_position() -> Vector3:
	return Vector3(PLAYER_TRACK_X, rig_y, 0.0)


func _configure_rig() -> void:
	# 標的の列車は左(-X)側。対向で猛速なので前方から来るのを早く捉えられるよう広めに
	# (真左を中心に前方ほぼ正面〜後方まで。自分の車内側=真後ろだけ不可)
	rig.set_view_limits(8.0, 172.0, -32.0, 14.0)


func _mission_text() -> String:
	return "MISSION: ELIMINATE %d HOSTILES  /  DO NOT SHOOT CIVILIANS (WHITE)" % hostiles.size()


## 夕暮れの平原: 低い夕日・暖色の霞。列車の窓明かりが映える時間帯
func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky_sunset.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.44, 0.40)
	env.ambient_light_energy = 0.65

	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.28, 0.18)
	env.fog_density = 0.0016
	env.fog_sun_scatter = 0.3
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.1

	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.06

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 夕日(西=標的列車の側から低く差す。車体と標的が逆光気味に照る)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.72, 0.45)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-9.0, 70.0, 0.0)
	add_child(sun)


func _build_world() -> void:
	set_meta("facade_windows_enabled", false)   # ビル窓の格子判定は列車には使わない
	_build_ground_and_track()
	_build_trains()


## 地面・線路・枕木・架線柱・茂み。リグ基準の追従とリサイクルで無限に流れる
func _build_ground_and_track() -> void:
	# 平原(リグに追従する一枚板。均一色+霞で「流れ」は枕木・柱・茂みが伝える)
	var ground := StaticBody3D.new()
	ground.collision_layer = 0b0001
	ground.collision_mask = 0
	add_child(ground)
	var g := PlaneMesh.new()
	g.size = Vector2(900.0, 900.0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.14, 0.115, 0.085)   # 夕日に照る乾いた草原
	gm.roughness = 1.0
	var gmi := MeshInstance3D.new()
	gmi.mesh = g
	gmi.material_override = gm
	ground.add_child(gmi)
	var gshape := CollisionShape3D.new()
	var gbx := BoxShape3D.new()
	gbx.size = Vector3(900.0, 1.0, 900.0)
	gshape.shape = gbx
	gshape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(gshape)
	_followers.append(ground)

	# 線路2本(バラスト+レール。均一なので追従でよい)
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.35, 0.30, 0.28)
	rail_mat.metallic = 0.8
	rail_mat.roughness = 0.35
	var ballast_mat := StandardMaterial3D.new()
	ballast_mat.albedo_color = Color(0.21, 0.19, 0.17)
	ballast_mat.roughness = 1.0
	for tx in [PLAYER_TRACK_X, ENEMY_TRACK_X]:
		var bed := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.2, 0.5, 800.0)
		bed.mesh = bm
		bed.material_override = ballast_mat
		bed.position = Vector3(tx, 0.25, 0.0)
		add_child(bed)
		_followers.append(bed)
		for rx in [-0.75, 0.75]:
			var rail := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(0.12, 0.16, 800.0)
			rail.mesh = rm
			rail.material_override = rail_mat
			rail.position = Vector3(tx + rx, 0.58, 0.0)
			add_child(rail)
			_followers.append(rail)

	# 枕木(スピード感の主役)。ピッチ3.5mの帯をMultiMeshで作り、ピッチ周期でリサイクル
	var tie_mat := StandardMaterial3D.new()
	tie_mat.albedo_color = Color(0.16, 0.12, 0.09)
	tie_mat.roughness = 1.0
	for tx in [PLAYER_TRACK_X, ENEMY_TRACK_X]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var tie := BoxMesh.new()
		tie.size = Vector3(2.4, 0.14, 0.5)
		tie.material = tie_mat
		mm.mesh = tie
		mm.instance_count = 120
		for i in 120:
			mm.set_instance_transform(i,
				Transform3D(Basis(), Vector3(0.0, 0.52, float(i - 60) * 3.5)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = Vector3(tx, 0.0, 0.0)
		add_child(mmi)
		_cyclers.append({"node": mmi, "period": 3.5})

	# 架線柱(40mおき)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.22, 0.22, 0.24)
	pole_mat.roughness = 0.7
	pole_mat.metallic = 0.4
	for i in 22:
		var pole := Node3D.new()
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.12
		pm.bottom_radius = 0.16
		pm.height = 7.5
		post.mesh = pm
		post.material_override = pole_mat
		post.position = Vector3(0.0, 3.75, 0.0)
		pole.add_child(post)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(3.4, 0.12, 0.12)
		arm.mesh = am
		arm.material_override = pole_mat
		arm.position = Vector3(-1.5, 7.0, 0.0)
		pole.add_child(arm)
		pole.position = Vector3(PLAYER_TRACK_X + 3.4, 0.0, float(i - 11) * 40.0)
		add_child(pole)
		_cyclers.append({"node": pole, "period": 880.0})

	# 茂み・岩(左右の平原にまばらに。流れる景色の添え物)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var bush_mat := StandardMaterial3D.new()
	bush_mat.albedo_color = Color(0.17, 0.14, 0.08)
	bush_mat.roughness = 1.0
	for i in 42:
		var b := MeshInstance3D.new()
		var s := SphereMesh.new()
		var r := rng.randf_range(0.5, 1.6)
		s.radius = r
		s.height = r * 1.3
		b.mesh = s
		b.material_override = bush_mat
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		b.position = Vector3(side * rng.randf_range(14.0, 120.0), r * 0.4,
			rng.randf_range(-450.0, 450.0))
		add_child(b)
		_cyclers.append({"node": b, "period": 900.0})

	# 遠景の山並み(線路と平行の長い稜線。追従=常に窓の外にある)
	var hill_mat := StandardMaterial3D.new()
	hill_mat.albedo_color = Color(0.16, 0.10, 0.11)
	hill_mat.roughness = 1.0
	for h in [[-380.0, 60.0], [420.0, 45.0]]:
		var hill := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(140.0, h[1], 1400.0)
		hill.mesh = hm
		hill.material_override = hill_mat
		hill.position = Vector3(h[0], h[1] * 0.5 - 14.0, 0.0)
		hill.rotation_degrees = Vector3(0.0, 0.0, 4.0 * signf(h[0]))
		add_child(hill)
		_followers.append(hill)


func _build_trains() -> void:
	# 自分の列車(3両。リグは中央車両の屋根の上)
	ptrain = TrainLineScript.new()
	ptrain.speed = PLAYER_SPEED
	ptrain.glass_side = -1.0   # 自分の車両のガラスは標的側(-X)に(見た目用)
	ptrain.lit_windows = false
	add_child(ptrain)
	ptrain.build(["pass", "pass", "pass"], Color(0.16, 0.22, 0.30))
	ptrain.position = Vector3(PLAYER_TRACK_X, 0.0, -(TrainLineScript.CAR_L + TrainLineScript.GAP) - TrainLineScript.CAR_L * 0.5)

	# 標的の列車(8両。+X側=プレイヤー側に割れるガラス)
	etrain = TrainLineScript.new()
	etrain.speed = ENEMY_SPEED
	etrain.glass_side = 1.0
	etrain.lit_windows = true
	add_child(etrain)
	etrain.build(ENEMY_COMP, Color(0.34, 0.14, 0.10))
	_enemy_len = etrain.total_length(ENEMY_COMP.size())
	etrain.position = Vector3(ENEMY_TRACK_X, 0.0, ENEMY_START_Z)


func _spawn_targets() -> void:
	# 客車の通路を歩く悪人(窓の前を通る一瞬だけ撃てる)
	var speeds := [1.2, 0.9, 1.5, 1.1]
	var wi := 0
	for i in WALK_CARS:
		var p: Dictionary = etrain.aisle_paths[_pass_index(i)]
		_train_walker(etrain, p.from, p.to, speeds[wi % speeds.size()], true)
		wi += 1
	# 民間人(客車の窓際に立ちすくむ。誤射で即失敗)
	for i in CIVIL_CARS:
		_train_standing(etrain, etrain.civil_points[_pass_index(i)], false)
	# 車両の外の標的: 屋根の見張り+貨車の荷台の見張り
	for i in ROOF_CARS:
		_train_standing(etrain, etrain.roof_points[_pass_index(i)], true)
	for p in etrain.flat_points:
		_train_standing(etrain, p, true)


## 通し車両番号 → 客車だけ数えた添字(aisle_paths等は客車のみ積まれる)
func _pass_index(car_idx: int) -> int:
	var n := 0
	for i in car_idx:
		if ENEMY_COMP[i] == "pass":
			n += 1
	return n


## 列車の子として立ち標的を置く(列車と一緒に動く)
func _train_standing(train, local_pos: Vector3, hostile_v: bool) -> TargetHuman:
	var man := TargetHuman.new()
	man.hostile = hostile_v
	train.add_child(man)
	man.position = local_pos
	# 窓の外(ガラスを張った側=プレイヤーの側)を向いて立つ
	man.rotation.y = -PI * 0.5 * signf(train.glass_side)
	_register(man)
	man.died.connect(_on_train_target_died)
	return man


## 列車の子として通路を往復する悪人を置く(ローカルのPath3D=列車と一緒に動く)
func _train_walker(train, from: Vector3, to: Vector3, speed: float, hostile_v: bool) -> void:
	var path := Path3D.new()
	var curve := Curve3D.new()
	curve.add_point(from)
	curve.add_point(to)
	path.curve = curve
	train.add_child(path)
	var follow := PathFollow3D.new()
	follow.loop = false
	follow.rotation_mode = PathFollow3D.ROTATION_Y
	path.add_child(follow)
	var man := TargetHuman.new()
	man.hostile = hostile_v
	follow.add_child(man)
	_register(man)
	man.died.connect(_on_train_target_died)
	_walkers.append({"follow": follow, "target": man, "speed": speed, "dir": 1.0})


## 列車上の標的が倒れたら: 列車の慣性を与えて世界側へ切り離す
## (走る列車から崩れ落ち、車両が先へ走り去っていく)
func _on_train_target_died(t: TargetHuman) -> void:
	t.call_deferred("reparent", self)
	# 列車の走行速度ぶんの慣性(die()の転倒撃力に加算される)
	var kick := func() -> void:
		if is_instance_valid(t):
			t.apply_impulse(Vector3(0.0, 0.2, -ENEMY_SPEED * 0.9))
	kick.call_deferred()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if rig == null:
		return
	# リグ(=自分)は列車と同じ速度で走り続ける+車体の揺れ
	_sway_t += delta
	rig.position.z -= PLAYER_SPEED * delta
	rig.position.x = PLAYER_TRACK_X + sin(_sway_t * 3.1) * 0.035
	rig.position.y = rig_y + sin(_sway_t * 7.3) * 0.022

	# 景観: 追従(均一なもの)とリサイクル(模様のあるもの)
	var rz := rig.position.z
	for f in _followers:
		f.position.z = rz
	for c in _cyclers:
		var n: Node3D = c.node
		n.position.z = rz + wrapf(n.position.z - rz, -c.period * 0.5, c.period * 0.5)

	# 標的列車が後方へ抜けたら「別の列車」として前方遠くへループ。
	# このときガラスを全修復＝無傷の車両として来る(リプレイ・飛翔弾のない隙に)
	var rel: float = etrain.position.z - rz
	if rel > LOOP_BACK and not is_replay_active() and bullets_in_flight == 0:
		etrain.position.z = rz - LOOP_AHEAD - _enemy_len
		etrain.reset_all_glass()
