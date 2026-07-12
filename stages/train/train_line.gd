class_name TrainLine
extends Node3D
## 1編成の列車。-Z方向へ speed(m/s) で走り続ける。
## 車両はノードローカルで z=0(先頭) から +Z(後方)へ連結して組む。
## 標的の配置点(通路・屋根・貨車)はローカル座標で公開し、ステージが子として標的を置く
## =列車が動けば標的も一緒に動く(弾道予測は velocity_estimate が自動で追従する)。
##
## 種別: "pass"=客車(窓・室内灯・通路) / "flat"=貨車(木箱) / "tank"=タンク車

const CAR_L := 20.0       # 車両長
const CAR_W := 3.0        # 車両幅
const GAP := 1.4          # 連結間隔
const FLOOR_Y := 1.1      # 床の高さ(レール面から)
const BODY_TOP := 3.55    # 側壁の上端
const ROOF_Y := 3.75      # 屋根の上面
const WIN_Y0 := 1.95      # 窓の下端
const WIN_Y1 := 3.05      # 窓の上端
const WIN_W := 1.8        # 窓幅
const WIN_PITCH := 3.2    # 窓ピッチ

var speed := 14.0          # 走行速度(m/s・-Z方向)
var glass_side := 1.0      # ガラス(割れる板)を張る側(+1=+X側)。反対側は開口のみ
var lit_windows := true    # 室内灯を灯すか

# 標的の配置点(ローカル)。build()後にステージが読む
var aisle_paths: Array = []        # 客車の通路 [{from: Vector3, to: Vector3}]
var roof_points: Array = []        # 屋根の上の見張り位置 [Vector3]
var flat_points: Array = []        # 貨車の荷台の見張り位置 [Vector3]
var civil_points: Array = []       # 民間人の立ち位置 [Vector3]

var glass_panes: Array = []        # 全客車のガラス(ループで一括修復する)

var _body_mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D
var _inner_mat: StandardMaterial3D
var _seat_mat: StandardMaterial3D


## 割れた全ガラスを無傷に戻す(次の周回=別の車両として来るため)
func reset_all_glass() -> void:
	for p in glass_panes:
		if is_instance_valid(p):
			p.reset()


func _physics_process(delta: float) -> void:
	position.z -= speed * delta


## composition: 種別の配列(先頭から)。lit_carsの客車(通し番号)に通路/民間人点を割り振る
func build(composition: Array, body_color: Color) -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = body_color
	_body_mat.roughness = 0.55
	_body_mat.metallic = 0.25
	_dark_mat = StandardMaterial3D.new()
	_dark_mat.albedo_color = Color(0.09, 0.09, 0.10)
	_dark_mat.roughness = 0.8
	_dark_mat.metallic = 0.3
	_inner_mat = StandardMaterial3D.new()
	_inner_mat.albedo_color = Color(0.55, 0.48, 0.38)
	_inner_mat.roughness = 0.9
	_seat_mat = StandardMaterial3D.new()
	_seat_mat.albedo_color = Color(0.30, 0.16, 0.12)
	_seat_mat.roughness = 0.9

	for i in composition.size():
		var z0 := float(i) * (CAR_L + GAP)
		match composition[i]:
			"pass":
				_build_passenger(z0)
			"flat":
				_build_flat(z0)
			"tank":
				_build_tank(z0)


## 全長(先頭から最後尾まで)
func total_length(n_cars: int) -> float:
	return float(n_cars) * (CAR_L + GAP)


func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material, coll := true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if coll:
		var shape := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = size
		shape.shape = bx
		shape.position = pos
		parent.add_child(shape)


## 台枠+台車(全車種共通の足回り)
func _underframe(body: StaticBody3D, z0: float) -> void:
	_box(body, Vector3(CAR_W - 0.4, 0.5, CAR_L - 1.0), Vector3(0.0, 0.85, z0 + CAR_L * 0.5), _dark_mat)
	for bz in [z0 + 3.0, z0 + CAR_L - 3.0]:
		for wx in [-1.0, 1.0]:
			for wz in [-0.9, 0.9]:
				var wheel := CylinderMesh.new()
				wheel.top_radius = 0.45
				wheel.bottom_radius = 0.45
				wheel.height = 0.2
				var mi := MeshInstance3D.new()
				mi.mesh = wheel
				mi.material_override = _dark_mat
				mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
				mi.position = Vector3(wx * 1.1, 0.45, bz + wz)
				body.add_child(mi)


## 客車: 窓の開口が並ぶ車体+室内(床・座席・灯り)+屋根。片側に割れるガラス
func _build_passenger(z0: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 0b0001
	body.collision_mask = 0
	add_child(body)
	_underframe(body, z0)

	var zc := z0 + CAR_L * 0.5
	# 床・天井(屋根)
	_box(body, Vector3(CAR_W, 0.12, CAR_L), Vector3(0.0, FLOOR_Y + 0.06, zc), _inner_mat)
	_box(body, Vector3(CAR_W, 0.2, CAR_L), Vector3(0.0, ROOF_Y - 0.1, zc), _body_mat)
	# 妻面(前後の壁)
	for ez in [z0 + 0.1, z0 + CAR_L - 0.1]:
		_box(body, Vector3(CAR_W, BODY_TOP - FLOOR_Y, 0.2),
			Vector3(0.0, (FLOOR_Y + BODY_TOP) * 0.5, ez), _body_mat)

	# 側壁: 窓下の腰板・窓上の幕板・窓柱(両側)。窓は本当の開口
	var n_win := 5
	var first := zc - float(n_win - 1) * WIN_PITCH * 0.5
	for sx in [-1.0, 1.0]:
		var wall_x: float = sx * (CAR_W * 0.5 - 0.07)
		_box(body, Vector3(0.14, WIN_Y0 - FLOOR_Y, CAR_L), Vector3(wall_x, (FLOOR_Y + WIN_Y0) * 0.5, zc), _body_mat)
		_box(body, Vector3(0.14, BODY_TOP - WIN_Y1, CAR_L), Vector3(wall_x, (WIN_Y1 + BODY_TOP) * 0.5, zc), _body_mat)
		# 窓柱(窓と窓の間+両端)
		for k in n_win + 1:
			var pz := first - WIN_PITCH * 0.5 + float(k) * WIN_PITCH
			pz = clampf(pz, z0 + 0.5, z0 + CAR_L - 0.5)
			var pw := WIN_PITCH - WIN_W
			_box(body, Vector3(0.14, WIN_Y1 - WIN_Y0, pw), Vector3(wall_x, (WIN_Y0 + WIN_Y1) * 0.5, pz), _body_mat)
		# 割れるガラス(プレイヤー側のみ。弾は止めない=レイヤ5)
		if signf(sx) == signf(glass_side):
			for k in n_win:
				var gz := first + float(k) * WIN_PITCH
				var pane := GlassPane.new(Vector2(WIN_W, WIN_Y1 - WIN_Y0))
				add_child(pane)
				pane.position = Vector3(wall_x, (WIN_Y0 + WIN_Y1) * 0.5, gz)
				pane.rotation.y = PI * 0.5   # 板の面を±X向きに
				glass_panes.append(pane)

	# 座席(窓下の低いベンチを両側に)
	for sx in [-1.0, 1.0]:
		_box(body, Vector3(0.55, 0.45, CAR_L - 2.0),
			Vector3(sx * (CAR_W * 0.5 - 0.45), FLOOR_Y + 0.35, zc), _seat_mat, false)

	# 室内灯(暖色。夕暮れの中で車内が読める)
	if lit_windows:
		for lz in [zc - 5.0, zc + 5.0]:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.82, 0.58)
			l.light_energy = 1.1
			l.omni_range = 5.5
			l.shadow_enabled = false
			l.position = Vector3(0.0, BODY_TOP - 0.25, lz)
			add_child(l)

	# 通路(中央)を歩ける区間として公開
	aisle_paths.append({
		"from": Vector3(0.0, FLOOR_Y + 1.07, z0 + 2.2),
		"to": Vector3(0.0, FLOOR_Y + 1.07, z0 + CAR_L - 2.2),
	})
	civil_points.append(Vector3(-0.7, FLOOR_Y + 1.07, zc))
	roof_points.append(Vector3(0.0, ROOF_Y + 0.95, zc))


## 貨車: 低い荷台+木箱。箱の間に立てる
func _build_flat(z0: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 0b0001
	body.collision_mask = 0
	add_child(body)
	_underframe(body, z0)
	var zc := z0 + CAR_L * 0.5
	_box(body, Vector3(CAR_W, 0.25, CAR_L), Vector3(0.0, FLOOR_Y + 0.12, zc), _inner_mat)
	# 木箱(不規則に積む)
	var crate := StandardMaterial3D.new()
	crate.albedo_color = Color(0.42, 0.30, 0.18)
	crate.roughness = 0.95
	_box(body, Vector3(1.6, 1.5, 2.2), Vector3(-0.5, FLOOR_Y + 1.0, z0 + 4.5), crate)
	_box(body, Vector3(1.3, 1.1, 1.6), Vector3(0.6, FLOOR_Y + 0.8, z0 + 8.5), crate)
	_box(body, Vector3(1.8, 1.9, 2.6), Vector3(0.2, FLOOR_Y + 1.2, z0 + 15.0), crate)
	# 箱の間の見張り位置
	flat_points.append(Vector3(0.0, FLOOR_Y + 1.2, z0 + 11.6))


## タンク車: 荷台+横倒しの円筒
func _build_tank(z0: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 0b0001
	body.collision_mask = 0
	add_child(body)
	_underframe(body, z0)
	var zc := z0 + CAR_L * 0.5
	_box(body, Vector3(CAR_W, 0.25, CAR_L), Vector3(0.0, FLOOR_Y + 0.12, zc), _dark_mat)
	var tank := CylinderMesh.new()
	tank.top_radius = 1.25
	tank.bottom_radius = 1.25
	tank.height = CAR_L - 3.0
	var mi := MeshInstance3D.new()
	mi.mesh = tank
	mi.material_override = _dark_mat
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	mi.position = Vector3(0.0, FLOOR_Y + 1.5, zc)
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.25
	cyl.height = CAR_L - 3.0
	shape.shape = cyl
	shape.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	shape.position = Vector3(0.0, FLOOR_Y + 1.5, zc)
	body.add_child(shape)
