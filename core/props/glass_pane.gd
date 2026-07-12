class_name GlassPane
extends Area3D
## 窓ガラス。弾を止めない専用レイヤ(5)に置く。
## 弾丸(bullet.gd)・リプレイ弾道(sniper_stage.gd)が通過した瞬間に shatter() で割れる。
## 当たり判定・弾道・オートエイム・着弾予測には一切影響しない＝「割れるだけで弾は逸れない」。
## 割れると: 板が消え、破片が飛び散り、窓枠の縁にギザギザの破れ残りが残る。

const LAYER := 0b10000  # レイヤ5: ガラス専用(弾のHIT_MASK外＝弾はすり抜ける)

# --- スロー(バレットカム)中の見え方 ---
# time_scale=0.08のスロー中、破片が素の速度だとほぼ静止して見えて地味。
# speed_scaleを毎フレーム補償し「実時間の約15%」でゆっくり舞い散らせる
# ＝映画のガラス爆発の見え方（速すぎるとスローの中で浮くため控えめに・2026-07-10調整）
const SLOWMO_DRIFT := 0.15

var broken := false

var _size: Vector2
var _pane: MeshInstance3D
var _col: CollisionShape3D
var _live_fx: Array = []          # 舞っている破片パーティクル(スロー補償の対象)
var _flash: OmniLight3D = null    # 割れた瞬間の閃光(実時間で減衰)
var _flash_decay := 0.0


func _init(size := Vector2(5.0, 3.0)) -> void:
	_size = size


func _ready() -> void:
	set_process(false)  # 割れた後だけ動かす(スロー補償・閃光減衰)
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true

	_col = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_size.x, _size.y, 0.06)
	_col.shape = box
	add_child(_col)

	# 板ガラス(夜はうっすら青白い照り。部屋の明かりは透ける)
	_pane = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = _size
	_pane.mesh = quad
	_pane.material_override = _glass_mat(0.13)
	add_child(_pane)


func _glass_mat(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.62, 0.74, 0.92, alpha)
	m.roughness = 0.05
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## 割る。hit_pos=弾の通過点(ワールド)、dir=弾の進行方向(破片を押し出す向き)
func shatter(hit_pos: Vector3, dir: Vector3) -> void:
	if broken:
		return
	broken = true
	if _pane == null:
		_ready()   # ツリー追加直後(_ready前)に割られても安全に(動的スポーン対応)
	_pane.visible = false
	_col.set_deferred("disabled", true)
	set_deferred("monitorable", false)
	_spawn_shards(hit_pos, dir)
	_spawn_flash(hit_pos)
	_spawn_remnants()
	set_process(true)


## 割れたガラスを無傷に戻す（列車ステージのループで「別の車両＝新品の窓」にする）。
## 破片・閃光・破れ残りはすべてこのノードの子なので一括で片付け、板と当たり判定を復活。
func reset() -> void:
	if not broken:
		return
	broken = false
	set_process(false)
	_flash = null
	_live_fx.clear()
	for c in get_children():
		if c != _pane and c != _col:
			c.queue_free()   # 破片パーティクル・閃光ライト・破れ残り
	if _pane != null:
		_pane.visible = true
	collision_layer = LAYER
	if _col != null:
		_col.set_deferred("disabled", false)
	set_deferred("monitorable", true)


## 割れた後の毎フレーム処理：スロー補償と閃光の実時間減衰
func _process(delta: float) -> void:
	var ts := maxf(Engine.time_scale, 0.0001)
	# スロー中は破片の速度を補償して「舞い散り」を見せる(通常時は1.0=補償なし)
	var k := maxf(1.0, SLOWMO_DRIFT / ts)
	# 解放済みインスタンスは型付き引数(Object)へ変換できず filter がエラーを吐くため、
	# 引数は無型で受けて is_instance_valid だけで判定する
	_live_fx = _live_fx.filter(func(p) -> bool: return is_instance_valid(p))
	for p in _live_fx:
		p.speed_scale = k
	# 閃光はスローに巻き込まず実時間で減衰(スロー中でも「パッと光ってすっと消える」)
	if _flash != null:
		_flash.light_energy -= _flash_decay * (delta / ts)
		if _flash.light_energy <= 0.0:
			_flash.queue_free()
			_flash = null
	if _flash == null and _live_fx.is_empty():
		set_process(false)


## 割れた瞬間の閃光。夜の街で「どの窓が割れたか」がひと目で分かる
func _spawn_flash(pos: Vector3) -> void:
	_flash = OmniLight3D.new()
	add_child(_flash)
	_flash.global_position = pos
	_flash.light_color = Color(0.75, 0.86, 1.0)
	_flash.light_energy = 8.0
	_flash.omni_range = 10.0
	_flash.shadow_enabled = false
	_flash_decay = 18.0  # 実時間 約0.45秒で消える


## 破片の飛散。大きな板ガラス片(板全体)＋着弾点の吹き飛び＋キラキラ光る細片の3層
func _spawn_shards(hit_pos: Vector3, dir: Vector3) -> void:
	# 大きな板ガラス片(回転しながら落ちる。スロー中の主役)
	var shard := QuadMesh.new()
	shard.size = Vector2(0.16, 0.22)
	var m := _glass_mat(0.65)
	m.emission_enabled = true
	m.emission = Color(0.55, 0.70, 0.95)
	m.emission_energy_multiplier = 1.2
	shard.material = m

	# キラキラ光る細片(空中で瞬く粉ガラス。夜に映える)
	var glitter := QuadMesh.new()
	glitter.size = Vector2(0.05, 0.06)
	var gm := _glass_mat(0.9)
	gm.emission_enabled = true
	gm.emission = Color(0.75, 0.86, 1.0)
	gm.emission_energy_multiplier = 3.0
	glitter.material = gm

	# 板全体からの割れ落ち(重力でバラバラ落ちる)
	var whole := _make_particles(shard)
	whole.position = Vector3.ZERO
	whole.amount = 64
	whole.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	whole.emission_box_extents = Vector3(_size.x * 0.5, _size.y * 0.5, 0.02)
	whole.direction = dir
	whole.spread = 35.0
	whole.initial_velocity_min = 0.5
	whole.initial_velocity_max = 3.0
	whole.scale_amount_min = 0.6
	whole.scale_amount_max = 2.0
	whole.emitting = true

	# 着弾点の吹き飛び(弾が突き抜けた勢い。バレットカムの目の前で弾ける)
	var burst := _make_particles(shard)
	burst.global_position = hit_pos
	burst.amount = 26
	burst.direction = dir
	burst.spread = 22.0
	burst.initial_velocity_min = 4.0
	burst.initial_velocity_max = 9.0
	burst.emitting = true

	# きらめき(板全体からふわっと広がって瞬く)
	var sparkle := _make_particles(glitter)
	sparkle.position = Vector3.ZERO
	sparkle.amount = 40
	sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparkle.emission_box_extents = Vector3(_size.x * 0.5, _size.y * 0.5, 0.02)
	sparkle.direction = dir
	sparkle.spread = 60.0
	sparkle.initial_velocity_min = 0.8
	sparkle.initial_velocity_max = 4.0
	sparkle.lifetime = 1.2
	sparkle.emitting = true


func _make_particles(mesh: Mesh) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	add_child(p)
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 1.5
	p.gravity = Vector3(0, -9.8, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.mesh = mesh
	_live_fx.append(p)  # スロー中は_processが速度を補償する
	# スロー(バレットカム)中に生まれても、実時間で必ず片付ける
	get_tree().create_timer(6.0, true, false, true).timeout.connect(p.queue_free)
	return p


## 窓枠の縁に残るギザギザの破れ残り(ガラスが「割れた」ことがひと目で分かる)
func _spawn_remnants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var hw := _size.x * 0.5
	var hh := _size.y * 0.5
	# [辺の起点, 辺に沿う向き, 内側への向き, 辺の長さ]
	var edges := [
		[Vector3(-hw, -hh, 0), Vector3.RIGHT, Vector3.UP, _size.x],
		[Vector3(-hw, hh, 0), Vector3.RIGHT, Vector3.DOWN, _size.x],
		[Vector3(-hw, -hh, 0), Vector3.UP, Vector3.RIGHT, _size.y],
		[Vector3(hw, -hh, 0), Vector3.UP, Vector3.LEFT, _size.y],
	]
	var verts := PackedVector3Array()
	for e in edges:
		var origin: Vector3 = e[0]
		var along: Vector3 = e[1]
		var inward: Vector3 = e[2]
		var length: float = e[3]
		var t := rng.randf_range(0.05, 0.35)
		while t < length - 0.3:
			var w := rng.randf_range(0.12, 0.45)   # 歯の幅
			var depth := rng.randf_range(0.08, 0.38)  # 内側への食い込み
			var a := origin + along * t
			var b := origin + along * (t + w)
			var c := origin + along * (t + w * rng.randf_range(0.3, 0.7)) + inward * depth
			verts.append(a)
			verts.append(b)
			verts.append(c)
			t += w + rng.randf_range(0.1, 0.55)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3(0, 0, 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _glass_mat(0.30)
	add_child(mi)
