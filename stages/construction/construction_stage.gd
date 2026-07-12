extends SniperStage
## 「高層ビル建設現場」ステージ（2026-07-12・新規）。
## プレイヤーは隣接する建設中タワーの足場（中層）に陣取り、通りを挟んだ
## 約130m先の鉄骨スケルトンのビルを狙う。
##   ・各フロアを敵スナイパーが巡回移動する（階層移動）。鉄骨の柱・梁・スラブが
##     フロア間の遮蔽になり、柱の陰に入った一瞬は撃てない
##   ・正面の一部フロアには鉄筋の格子（縦バー）が張られ、その隙間越しに撃つ
##     （格子越しの撃ち合い。バーに当たると弾は止まる）
##   ・タワークレーンの吊り荷（鉄筋束）が振り子で揺れ、特定フロアの射線を
##     周期的に塞ぐ（読めば当たる周期遮蔽・§6-2）
##   ・作業員（民間人・白）が数人取り残されており、誤射で即ミッション失敗
##
## 対応モード: A(精密)/B(応戦)。Bでは敵が格子・柱の陰から撃ち返してくる
## （EngageMode が hostiles を撃ち手にする。格子・柱の遮蔽がそのまま撃ち合いの窓になる）。
## 宣言は GameManager.STAGES の modes:[0,1]（台帳が正）。

# --- 標的のビル（鉄骨スケルトン） ---
## 約130m先。鉄骨は細いので近め＋大きめにして「格子越し」が読める大きさにする。
## 柱は前後2列だけ（遮蔽過多を避ける）。歩く敵は前面のすぐ裏を通る
const B_X := 21.0               # 建物の半幅(x: -21..21)
const B_FRONT_Z := -100.0       # 正面(プレイヤー側)の面z
const B_BACK_Z := -120.0        # 奥の面z
const FLOOR_YS := [11.0, 19.0, 27.0, 35.0]   # 各フロアのスラブ上面y
const COL_TOP := 44.0           # 柱の頂部y
const COL_XS := [-21.0, -10.5, 0.0, 10.5, 21.0]   # 柱の並ぶx（約10m grid）

# --- プレイヤーの足場タワー ---
const PLAT_Y := 23.0            # 足場の床の高さ（スケルトンの中層と目線が合う）
const PLAT_Z := 28.0

# --- タワークレーンの吊り荷（周期遮蔽） ---
const CRANE_X := 34.0
const CRANE_Z := -118.0
const CRANE_TOP := 56.0
const PIVOT := Vector3(4.0, 45.0, -110.0)   # 吊り荷ピボット（ジブ上・建物の上空）
const LOAD_DROP := 16.0                      # ピボットから吊り荷までのワイヤー長
const SWING_PERIOD := 5.0                     # 振り子の周期(s)
const SWING_AMP := 0.34                        # 振り角(rad)

var _steel: StandardMaterial3D
var _rebar: StandardMaterial3D
var _deck: StandardMaterial3D
var _tarp: StandardMaterial3D

var _pendulum: Node3D           # クレーン吊り荷のピボット（毎フレーム揺らす）
var _beacon_mat: StandardMaterial3D   # クレーン頂部の赤い障害灯（明滅）
var _t := 0.0


func _rig_position() -> Vector3:
	# 足場タワーの前縁（建物の方＝-Zを向く）。中層なのでフロア1〜4を見渡せる
	return Vector3(4.0, PLAT_Y + 2.0, PLAT_Z)


func _configure_rig() -> void:
	# 正面のスケルトンを中心に、右のタワークレーン〜左の資材ヤードまで。
	# 上はクレーン頂部・屋上、下は1階の作業帯まで見下ろせる
	rig.set_view_limits(-52.0, 58.0, -24.0, 30.0)


func _mission_text() -> String:
	return "MISSION: ELIMINATE %d HOSTILES  /  DO NOT SHOOT WORKERS (WHITE)" % hostiles.size()


# ---------------------------------------------------------------- 環境

func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky_city.gdshader")
	# 日没直後の群青（都市の夜より少し明るめ＝鉄骨のシルエットが読める）
	sky_mat.set_shader_parameter("top_color", Color(0.020, 0.030, 0.055))
	sky_mat.set_shader_parameter("horizon_color", Color(0.14, 0.11, 0.10))
	sky_mat.set_shader_parameter("cloud_dark", Color(0.045, 0.050, 0.065))
	sky_mat.set_shader_parameter("cloud_lit", Color(0.16, 0.13, 0.12))
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.45, 0.56)
	env.ambient_light_energy = 0.6   # 視認性優先（鉄骨は細いので暗いと消える）
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.09, 0.10)
	env.fog_density = 0.0007
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 残照（西日）＋弱い月光。鉄骨の縦横を起こす
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.72, 0.48)
	sun.light_energy = 0.6
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-14.0, 155.0, 0.0)
	add_child(sun)


## 高所なので風は強め（演出値。WIND_ENABLED=false の間は弾に影響しない）
func _setup_wind() -> void:
	wind_speed = randf_range(-5.0, 5.0)
	wind_accel = Vector3(wind_speed, 0, 0) * WIND_FACTOR


# ---------------------------------------------------------------- ワールド

func _build_world() -> void:
	set_meta("facade_windows_enabled", false)   # ガラス窓なし（ガラス割れ演出を無効化）
	var world := StaticBody3D.new()
	world.collision_layer = 0b0001   # 地形レイヤ（弾はここで止まる・LOSもこれで判定）
	world.collision_mask = 0
	add_child(world)
	_make_materials()
	_build_ground(world)
	_build_player_platform(world)
	_build_skeleton(world)
	_build_crane(world)
	_build_pendulum_load()
	_build_yard(world)
	_build_skyline(world)


func _make_materials() -> void:
	_steel = StandardMaterial3D.new()
	_steel.albedo_color = Color(0.42, 0.28, 0.16)   # 錆止めのオレンジ鉄骨（夜でも視認）
	_steel.metallic = 0.3
	_steel.roughness = 0.7
	_rebar = StandardMaterial3D.new()
	_rebar.albedo_color = Color(0.30, 0.30, 0.33)
	_rebar.metallic = 0.5
	_rebar.roughness = 0.6
	_deck = StandardMaterial3D.new()
	_deck.albedo_color = Color(0.34, 0.34, 0.36)     # コンクリートデッキ
	_deck.roughness = 0.95
	_tarp = StandardMaterial3D.new()
	_tarp.albedo_color = Color(0.16, 0.28, 0.40)     # 養生シート（青）
	_tarp.roughness = 0.9


func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material, coll := true) -> MeshInstance3D:
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
	return mi


## 発光マテリアル（作業灯。実ライトを置かず emission+glow で安く灯す）
func _glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## 建設現場の地面（造成地。舗装前の土＋鉄板＋水たまりの照り返し）と敷地灯
func _build_ground(world: StaticBody3D) -> void:
	var g := PlaneMesh.new()
	g.size = Vector2(2000.0, 2000.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.095, 0.10)   # 夜の造成地（暗い土）
	m.roughness = 0.8
	var mi := MeshInstance3D.new()
	mi.mesh = g
	mi.material_override = m
	world.add_child(mi)
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2000.0, 1.0, 2000.0)
	shape.shape = bx
	shape.position = Vector3(0.0, -0.5, 0.0)
	world.add_child(shape)
	# 敷地の投光器（プレイヤーと標的の間の通りを底から照らす＝鉄骨が浮かぶ）
	for lz in [-40.0, -110.0, -160.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.6)
		l.light_energy = 1.5
		l.omni_range = 40.0
		l.shadow_enabled = false
		l.position = Vector3(0.0, 6.0, lz)
		add_child(l)


## プレイヤーの足場タワー（隣接する建設中の躯体の1フロア）。前縁に手すりと足場板
func _build_player_platform(world: StaticBody3D) -> void:
	# 床スラブ
	_box(world, Vector3(20.0, 0.4, 16.0), Vector3(4.0, PLAT_Y - 0.2, PLAT_Z + 4.0), _deck)
	# 下層の躯体（地面まで柱で支える＝浮いて見えない）
	for cx in [-4.0, 4.0, 12.0]:
		for cz in [PLAT_Z - 2.0, PLAT_Z + 10.0]:
			_box(world, Vector3(0.6, PLAT_Y, 0.6), Vector3(cx, PLAT_Y * 0.5, cz), _steel)
	# 前縁の手すり（低い＝構えを邪魔しない。足元を隠す程度）
	_box(world, Vector3(20.0, 0.1, 0.1), Vector3(4.0, PLAT_Y + 0.95, PLAT_Z - 3.9), _rebar, false)
	for px in [-5.0, 0.0, 5.0, 10.0]:
		_box(world, Vector3(0.08, 1.0, 0.08), Vector3(px, PLAT_Y + 0.5, PLAT_Z - 3.9), _rebar, false)
	# 足場の資材（安全コーンと養生シートの束＝生活感）
	_box(world, Vector3(2.0, 1.2, 1.0), Vector3(-4.0, PLAT_Y + 0.6, PLAT_Z + 6.0), _tarp)
	# 足場灯（自分の手元を照らす）
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.9, 0.7)
	lamp.light_energy = 1.2
	lamp.omni_range = 10.0
	lamp.shadow_enabled = false
	lamp.position = Vector3(9.0, PLAT_Y + 3.0, PLAT_Z + 3.0)
	add_child(lamp)


## 標的の鉄骨スケルトン。柱＋各フロアの梁・部分スラブ＋正面の鉄筋格子。
## 柱・スラブがフロア間の遮蔽、格子が「格子越し」の窓になる（すべて地形レイヤ）
func _build_skeleton(world: StaticBody3D) -> void:
	# 柱（前後2列のみ。中列は置かず遮蔽過多を避ける）。地面〜頂部
	for cx in COL_XS:
		for cz in [B_FRONT_Z, B_BACK_Z]:
			_box(world, Vector3(0.6, COL_TOP, 0.6), Vector3(cx, COL_TOP * 0.5, cz), _steel)
	# 各フロア：外周梁＋部分スラブ（手前半分だけ床を張る＝フロアの陰を作る）
	for fy in FLOOR_YS:
		# 外周梁（前後・左右）
		_box(world, Vector3(B_X * 2.0, 0.5, 0.5), Vector3(0.0, fy, B_FRONT_Z), _steel)
		_box(world, Vector3(B_X * 2.0, 0.5, 0.5), Vector3(0.0, fy, B_BACK_Z), _steel)
		_box(world, Vector3(0.5, 0.5, B_BACK_Z - B_FRONT_Z), Vector3(-B_X, fy, (B_FRONT_Z + B_BACK_Z) * 0.5), _steel, false)
		_box(world, Vector3(0.5, 0.5, B_BACK_Z - B_FRONT_Z), Vector3(B_X, fy, (B_FRONT_Z + B_BACK_Z) * 0.5), _steel, false)
		# 部分スラブ（奥半分の床。歩く敵はこの上を移動し、床が下階への射線を切る）
		_box(world, Vector3(B_X * 2.0, 0.3, 8.0), Vector3(0.0, fy + 0.15, B_BACK_Z + 5.0), _deck)
		# 天井の梁（次の階の床レベルに1本＝横のシルエット）
		_box(world, Vector3(B_X * 2.0, 0.35, 0.35), Vector3(0.0, fy + 6.0, (B_FRONT_Z + B_BACK_Z) * 0.5), _steel, false)
	# 屋上（最上フロアの上に部分デッキ＝屋上の見張りの土台）
	_box(world, Vector3(B_X * 2.0, 0.4, B_BACK_Z * 0.0 + 10.0), Vector3(0.0, COL_TOP, B_BACK_Z + 5.0), _deck)

	# 正面の鉄筋格子（縦バー）。フロア2とフロア3の前面に張る＝この2階は格子越しに撃つ。
	# バー間隔1.3m・バー幅0.1m＝隙間が広く、歩く敵は大半見えるが時折バーが割る
	_build_rebar_grid(world, FLOOR_YS[1] + 0.5, FLOOR_YS[1] + 5.5)
	_build_rebar_grid(world, FLOOR_YS[2] + 0.5, FLOOR_YS[2] + 5.5)

	# 各フロアの作業灯（フロアを下から照らす＝敵のシルエットが浮く）
	for fy in FLOOR_YS:
		for lx in [-10.0, 8.0]:
			_box(world, Vector3(0.5, 0.3, 0.3), Vector3(lx, fy + 0.4, B_FRONT_Z + 0.3),
				_glow_mat(Color(1.0, 0.85, 0.55), 2.2), false)
			var wl := OmniLight3D.new()
			wl.light_color = Color(1.0, 0.86, 0.6)
			wl.light_energy = 1.0
			wl.omni_range = 12.0
			wl.shadow_enabled = false
			wl.position = Vector3(lx, fy + 1.6, B_FRONT_Z + 1.5)
			add_child(wl)


## 正面に縦の鉄筋バーを並べる（y0..y1の帯・x全幅）。1本ずつ地形レイヤの当たり判定つき
func _build_rebar_grid(world: StaticBody3D, y0: float, y1: float) -> void:
	var h := y1 - y0
	var cy := (y0 + y1) * 0.5
	var x := -B_X + 1.5
	while x <= B_X - 1.5:
		_box(world, Vector3(0.1, h, 0.1), Vector3(x, cy, B_FRONT_Z + 0.2), _rebar)
		x += 1.8   # 隙間は広め（歩く敵は大半見えるが時折バーが割る）
	# 帯の上下に水平の連結筋（横1本ずつ＝格子らしさ。射線はほぼ塞がない細さ）
	for yy in [y0 + 0.4, y1 - 0.4]:
		_box(world, Vector3(B_X * 2.0 - 2.0, 0.08, 0.08), Vector3(0.0, yy, B_FRONT_Z + 0.2), _rebar, false)


## タワークレーン（マスト＋ジブ＋カウンタージブ）。頂部に赤い障害灯。
## オペレータキャブは高所の見張りの立ち位置になる
func _build_crane(world: StaticBody3D) -> void:
	# マスト（格子状の塔＝4本柱＋筋交いを簡略化した1本の太い柱）
	_box(world, Vector3(1.6, CRANE_TOP, 1.6), Vector3(CRANE_X, CRANE_TOP * 0.5, CRANE_Z), _steel)
	# 旋回部（マスト頂部）
	_box(world, Vector3(2.6, 2.4, 2.6), Vector3(CRANE_X, CRANE_TOP + 0.5, CRANE_Z), _steel)
	# ジブ（建物の上空へ張り出す長い腕・-X方向）
	_box(world, Vector3(46.0, 0.7, 0.7), Vector3(CRANE_X - 22.0, CRANE_TOP + 2.0, CRANE_Z), _steel)
	# カウンタージブ（反対側・+X）とカウンターウェイト
	_box(world, Vector3(12.0, 0.7, 0.7), Vector3(CRANE_X + 6.0, CRANE_TOP + 2.0, CRANE_Z), _steel)
	_box(world, Vector3(3.0, 2.0, 2.6), Vector3(CRANE_X + 11.0, CRANE_TOP + 1.2, CRANE_Z), _steel)
	# オペレータキャブ（旋回部の下・見張りの立ち位置）
	_box(world, Vector3(2.2, 2.0, 2.4), Vector3(CRANE_X - 1.6, CRANE_TOP - 1.0, CRANE_Z), _tarp)
	# 頂部の赤い障害灯（明滅）
	_beacon_mat = _glow_mat(Color(1.0, 0.12, 0.08), 3.0)
	_box(world, Vector3(0.5, 0.5, 0.5), Vector3(CRANE_X, CRANE_TOP + 2.2, CRANE_Z), _beacon_mat, false)


## クレーンの吊り荷（鉄筋束）。ジブから吊られて振り子運動し、フロア3の射線を
## 周期的に塞ぐ（読めば当たる周期遮蔽）。吊り荷は地形レイヤ＝弾を止める
func _build_pendulum_load() -> void:
	_pendulum = Node3D.new()
	add_child(_pendulum)
	_pendulum.position = PIVOT
	# ワイヤー
	var wire := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.05
	wm.bottom_radius = 0.05
	wm.height = LOAD_DROP
	wire.mesh = wm
	wire.material_override = _rebar
	wire.position = Vector3(0, -LOAD_DROP * 0.5, 0)
	_pendulum.add_child(wire)
	# 吊り荷（鉄筋束＝横長の塊）。当たり判定つき
	var load := StaticBody3D.new()
	load.collision_layer = 0b0001
	load.collision_mask = 0
	_pendulum.add_child(load)
	_box(load, Vector3(6.0, 1.2, 1.6), Vector3(0, -LOAD_DROP - 0.6, 0), _rebar)
	# 吊り荷の警告灯（振り子の周期を目で読める）
	_box(load, Vector3(0.3, 0.3, 0.3), Vector3(0, -LOAD_DROP - 1.4, 1.0),
		_glow_mat(Color(1.0, 0.6, 0.12), 2.6), false)


## 資材ヤード（足元の生活感）。鉄骨の山・土管・仮設事務所・資材灯
func _build_yard(world: StaticBody3D) -> void:
	# 鉄骨の山（左手前）
	for i in 3:
		_box(world, Vector3(14.0, 0.5, 1.2), Vector3(-30.0, 0.6 + i * 0.6, -50.0 + i * 1.4), _steel)
	# 土管（右手前）
	for i in 3:
		_box(world, Vector3(2.2, 2.2, 6.0), Vector3(34.0 + i * 2.6, 1.1, -40.0), _deck)
	# 仮設事務所（灯りの点いたプレハブ）
	_box(world, Vector3(10.0, 3.2, 5.0), Vector3(-40.0, 1.6, -90.0), _tarp)
	_box(world, Vector3(0.1, 1.4, 3.6), Vector3(-35.0, 2.0, -90.0),
		_glow_mat(Color(1.0, 0.9, 0.65), 1.6), false)
	# 敷地を囲む仮囲い（低い塀＝敷地の輪郭）
	for zz in [-10.0, -170.0]:
		_box(world, Vector3(140.0, 2.4, 0.3), Vector3(0.0, 1.2, zz), _tarp)


## 背景の街のスカイライン（遠景のビル群。建設現場が「街の中」と分かる）。当たり判定つき
func _build_skyline(world: StaticBody3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 771012
	for i in 26:
		var ang := TAU * float(i) / 26.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(230.0, 340.0)
		var bx := cos(ang) * r
		var bz := sin(ang) * r - 80.0
		# プレイヤー⇄標的の射線帯は空ける
		if absf(bx) < 40.0 and bz > -220.0 and bz < 40.0:
			continue
		var w := rng.randf_range(20.0, 46.0)
		var h := rng.randf_range(30.0, 110.0)
		var mat := _win_city_mat(rng)
		_box(world, Vector3(w, h, rng.randf_range(20.0, 40.0)), Vector3(bx, h * 0.5, bz), mat)


## 遠景ビルの窓明かりマテリアル（都市ステージの窓シェーダを流用）
func _win_city_mat(rng: RandomNumberGenerator) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/building_windows.gdshader")
	m.set_shader_parameter("seed", rng.randf() * 100.0)
	m.set_shader_parameter("lit_ratio", rng.randf_range(0.2, 0.4))
	m.set_shader_parameter("warm_ratio", rng.randf_range(0.15, 0.35))
	return m


# ---------------------------------------------------------------- 標的

func _spawn_targets() -> void:
	var y := 0.95   # 胴体中心＝スラブ上面 + これ
	var wz := B_FRONT_Z - 1.3   # 歩行ライン（前面のすぐ裏＝大半は見える）
	# フロアを巡回するスナイパー（階層移動）。フロアごとに範囲・速度をずらす。
	# 柱(約10m grid)や鉄筋格子の陰を横切り、抜けた一瞬に撃ち合う
	_add_walker(Vector3(-14.0, FLOOR_YS[0] + y, wz), Vector3(14.0, FLOOR_YS[0] + y, wz), 1.6)  # 1階
	_add_walker(Vector3(12.0, FLOOR_YS[1] + y, wz), Vector3(-16.0, FLOOR_YS[1] + y, wz), 1.9)  # 2階（格子越し）
	_add_walker(Vector3(-10.0, FLOOR_YS[2] + y, wz), Vector3(16.0, FLOOR_YS[2] + y, wz), 1.3)  # 3階（格子＋吊り荷）
	# 外部ホイストを上下する敵（フロア1→フロア4を斜めに移動＝文字どおりの階層移動）
	_add_walker(Vector3(18.5, FLOOR_YS[0] + y, wz), Vector3(18.5, FLOOR_YS[3] + y, wz), 2.4)
	# 固定の狙撃手：Bモードでは自動でカバーから顔を出す（もぐら叩き）。
	#   4階の梁ぎわ／クレーンのオペレータキャブ（高所の見張り）
	_add_standing(Vector3(-15.0, FLOOR_YS[3] + y, wz), true)
	_add_standing(Vector3(CRANE_X - 1.6, CRANE_TOP + y, CRANE_Z + 1.4), true)

	# 作業員（民間人・白）。取り残されて身をすくめている。撃てば即失敗。
	# 悪人の巡回ラインに紛れる位置＝誤射の緊張（フロア1と3の奥寄り）
	_add_standing(Vector3(7.0, FLOOR_YS[0] + y, B_BACK_Z + 3.0), false)
	_add_standing(Vector3(-7.0, FLOOR_YS[2] + y, B_BACK_Z + 3.0), false)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_t += delta
	# クレーン吊り荷の振り子（等時性のある読める揺れ・フロア3の射線を周期的に塞ぐ）
	if _pendulum != null:
		_pendulum.rotation.z = sin(_t * TAU / SWING_PERIOD) * SWING_AMP
	# クレーン頂部の障害灯（ゆっくり明滅）
	if _beacon_mat != null:
		_beacon_mat.emission_energy_multiplier = 3.0 * (0.4 + 0.6 * pow(0.5 + 0.5 * sin(_t * 2.0), 3.0))
