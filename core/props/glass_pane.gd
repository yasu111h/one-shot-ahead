class_name GlassPane
extends Area3D
## 窓ガラス。弾を止めない専用レイヤ(5)に置く。
## 弾丸(bullet.gd)・リプレイ弾道(sniper_stage.gd)が通過した瞬間に shatter() で割れる。
## 当たり判定・弾道・オートエイム・着弾予測には一切影響しない＝「割れるだけで弾は逸れない」。
## 割れると: 板が消え、破片が飛び散り、窓枠の縁にギザギザの破れ残りが残る。

const LAYER := 0b10000  # レイヤ5: ガラス専用(弾のHIT_MASK外＝弾はすり抜ける)

var broken := false

var _size: Vector2
var _pane: MeshInstance3D
var _col: CollisionShape3D


func _init(size := Vector2(5.0, 3.0)) -> void:
	_size = size


func _ready() -> void:
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
	_pane.visible = false
	_col.set_deferred("disabled", true)
	set_deferred("monitorable", false)
	_spawn_shards(hit_pos, dir)
	_spawn_remnants()


## 破片の飛散。板全体がバラバラ落ちる＋着弾点まわりは弾の方向へ強く飛ぶ
func _spawn_shards(hit_pos: Vector3, dir: Vector3) -> void:
	var shard := QuadMesh.new()
	shard.size = Vector2(0.14, 0.18)
	var m := _glass_mat(0.6)
	m.emission_enabled = true
	m.emission = Color(0.55, 0.70, 0.95)
	m.emission_energy_multiplier = 0.35
	shard.material = m

	# 板全体からの割れ落ち(重力でパラパラ落ちる)
	var whole := _make_particles(shard)
	whole.position = Vector3.ZERO
	whole.amount = 44
	whole.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	whole.emission_box_extents = Vector3(_size.x * 0.5, _size.y * 0.5, 0.02)
	whole.direction = dir
	whole.spread = 35.0
	whole.initial_velocity_min = 0.4
	whole.initial_velocity_max = 2.2
	whole.emitting = true

	# 着弾点の吹き飛び(弾が突き抜けた勢い)
	var burst := _make_particles(shard)
	burst.global_position = hit_pos
	burst.amount = 14
	burst.direction = dir
	burst.spread = 18.0
	burst.initial_velocity_min = 3.0
	burst.initial_velocity_max = 7.0
	burst.emitting = true


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
