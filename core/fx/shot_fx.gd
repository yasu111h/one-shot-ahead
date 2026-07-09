class_name ShotFx
extends Node3D
## 撃ち味エフェクト一式（TABIJIの値を移植）。すべて起動時にプール生成し、
## 実行中のノード生成ゼロで軽い（スマホ対策）。
##   ・マズルフラッシュ：加算合成ビルボードのソフト円（0.10-0.16スケール・0.06秒フェード）
##   ・トレーサー：BoxMesh伸縮の光の筋。実弾（重力・風の積分弾）の現在位置に追従
##   ・着弾：フレア0.6→1.9拡大0.18秒フェード＋GPUParticles3D火花

const TRACER_POOL := 6
const IMPACT_POOL := 4
const SPARK_POOL := 4
const TRACER_LEN := 2.4        # 光の筋の長さ(m)
const MUZZLE_LIFE := 0.06      # マズルフラッシュの寿命(秒)
const IMPACT_LIFE := 0.18      # 着弾フレアの寿命(秒)

var _muzzle: MeshInstance3D
var _muzzle_t := 0.0
var _tracers: Array = []       # [{mesh, bullet, start, active}]
var _impacts: Array = []       # [{mesh, t, active}]
var _sparks: Array = []        # GPUParticles3D(one_shot)
var _spark_i := 0


func _ready() -> void:
	# マズルフラッシュ（加算合成のソフト円。眩しすぎない抑えた色＝TABIJI準拠）
	_muzzle = _make_flare(0.55, Color(0.45, 0.43, 0.37, 1.0))
	add_child(_muzzle)

	# トレーサープール（細長い光の筋。scale.zで伸縮）
	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tracer_mat.albedo_color = Color(0.6, 0.9, 1.0)
	tracer_mat.emission_enabled = true
	tracer_mat.emission = Color(0.6, 0.9, 1.0)
	tracer_mat.emission_energy_multiplier = 10.0
	for i in TRACER_POOL:
		var mi := MeshInstance3D.new()
		mi.top_level = true
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.07, 1.0)   # 長さはscale.zで伸ばす
		mi.mesh = bm
		mi.material_override = tracer_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracers.append({"mesh": mi, "bullet": null, "start": Vector3.ZERO, "active": false})

	# 着弾フレアプール（広がりながら消える発光ビルボード・熱い白）
	for i in IMPACT_POOL:
		var f := _make_flare(1.0, Color(1.0, 0.93, 0.80, 1.0))
		add_child(f)
		_impacts.append({"mesh": f, "t": 0.0, "active": false})

	# 着弾火花プール（白熱→橙→赤に冷えながら速度方向へ伸びる筋）
	for i in SPARK_POOL:
		_sparks.append(_make_spark())


## 発射の瞬間に呼ぶ。posはマズル位置（弾の発射点）
func muzzle_flash(pos: Vector3) -> void:
	_muzzle.visible = true
	_muzzle.transparency = 0.0
	_muzzle.global_position = pos
	var ms := randf_range(0.10, 0.16)
	_muzzle.scale = Vector3(ms, ms, ms)
	_muzzle_t = MUZZLE_LIFE


## 飛翔中の実弾にトレーサーを付ける（毎フレーム弾の現在位置に追従する）
func attach_tracer(bullet: Node3D) -> void:
	var e: Dictionary = {}
	for t in _tracers:
		if not t.active:
			e = t
			break
	if e.is_empty():
		e = _tracers[0]  # 足りなければ最古を再利用
	e.bullet = bullet
	e.start = bullet.global_position
	e.active = true
	var mi: MeshInstance3D = e.mesh
	mi.global_position = bullet.global_position
	mi.scale = Vector3(1.0, 1.0, 0.1)
	mi.visible = true


## 着弾FX（フレア＋火花）。normalは着弾面の法線
func impact_burst(pos: Vector3, normal := Vector3.UP) -> void:
	for imp in _impacts:
		if imp.active:
			continue
		imp.active = true
		imp.t = 0.0
		var mi: MeshInstance3D = imp.mesh
		mi.visible = true
		mi.transparency = 0.0
		mi.global_position = pos
		mi.scale = Vector3.ONE * 0.6
		break
	var p: GPUParticles3D = _sparks[_spark_i]
	_spark_i = (_spark_i + 1) % _sparks.size()
	(p.process_material as ParticleProcessMaterial).direction = normal
	p.global_position = pos + normal * 0.05
	p.restart()


func _process(delta: float) -> void:
	# マズルフラッシュの減衰（0.06秒フェード）
	if _muzzle_t > 0.0:
		_muzzle_t = maxf(_muzzle_t - delta, 0.0)
		_muzzle.transparency = 1.0 - _muzzle_t / MUZZLE_LIFE
		if _muzzle_t <= 0.0:
			_muzzle.visible = false

	# トレーサー：実弾の現在位置に頭を合わせ、後方TRACER_LENの光の筋を描く
	for e in _tracers:
		if not e.active:
			continue
		var b = e.bullet
		if b == null or not is_instance_valid(b):
			e.active = false
			e.bullet = null
			e.mesh.visible = false
			continue
		var head: Vector3 = b.global_position
		var vel: Vector3 = b.velocity
		if vel.length() < 0.01:
			continue
		var dir := vel.normalized()
		var travelled: float = e.start.distance_to(head)
		var len := minf(TRACER_LEN, maxf(travelled, 0.1))
		var mi: MeshInstance3D = e.mesh
		mi.global_position = head - dir * (len * 0.5)
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		mi.look_at(mi.global_position + dir, up)
		mi.scale = Vector3(1.0, 1.0, len)

	# 着弾フレア：0.6→1.9へ広がりながら0.18秒でフェード
	for imp in _impacts:
		if not imp.active:
			continue
		imp.t += delta
		var k: float = imp.t / IMPACT_LIFE
		if k >= 1.0:
			imp.active = false
			imp.mesh.visible = false
			continue
		var s: float = lerpf(0.6, 1.9, k)
		imp.mesh.scale = Vector3(s, s, s)
		imp.mesh.transparency = k


## カメラを向く発光ビルボード（マズル・着弾フレアに使う）
func _make_flare(size: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.top_level = true
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _make_soft_dot()
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


## 着弾の火花（one-shot・移植仕様: amount=10, lifetime=0.35, spread180°, 速度5-11, gravity-9）
func _make_spark() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	pm.direction = Vector3(0.0, 1.0, 0.0)   # 着弾ごとに面の法線へ差し替える
	pm.spread = 180.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0.0, -9.0, 0.0)
	pm.damping_min = 2.0
	pm.damping_max = 6.0
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.98, 0.90, 1.0))
	grad.add_point(0.25, Color(1.0, 0.72, 0.28, 1.0))
	grad.add_point(0.7, Color(0.85, 0.30, 0.08, 0.8))
	grad.set_color(grad.get_point_count() - 1, Color(0.4, 0.08, 0.02, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _make_soft_dot()

	var quad := QuadMesh.new()
	quad.size = Vector2(0.022, 0.16)   # 細長い筋。向きは速度方向へ
	quad.material = mat

	var p := GPUParticles3D.new()
	p.top_level = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 10
	p.lifetime = 0.35
	p.local_coords = false
	p.emitting = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.process_material = pm
	p.draw_pass_1 = quad
	add_child(p)
	return p


## 中心が白く外へ透ける丸いテクスチャ（フレア・火花に使う）
func _make_soft_dot() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex
