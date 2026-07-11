extends SniperStage
## 「夜の埠頭」ステージ（2026-07-12 完全作り直し）。
## プレイヤーは倉庫の屋上から夜の港を見渡す。
##   ・約180m先：コンテナ列の隙間を悪人が横切る（隙間＝命中の窓。人質の誤射禁止）
##   ・約220m先：ガントリークレーンの点検台に見張り
##   ・約330m先：停泊した貨物船。波で上下し、舷壁裏の見張りは「波の頂の一瞬」だけ撃てる
##   ・吊り荷クレーンの振り子が一部の隙間の射線を周期的に塞ぐ（読めば当たる周期遮蔽）
##   ・灯台の回転ビームが港を周期的に舐める（一瞬の光・演出）
## 旧実装の失敗（暗すぎる・地面がない）への対策として、明るさとコントラストを最優先：
## 地面を明るいコンクリートにし、月光＋作業灯の光だまり＋発光マテリアルで視認性を確保する。
##
## 対応モード: A(精密)/B(応戦)。モード基盤のmainマージ後、台帳の宣言に反映する
const SUPPORTED_MODES := ["precision", "engage"]

const ROOF_Y := 14.0            # 倉庫の屋上の高さ
const ROW_Z := -150.0           # コンテナ前列（この裏を悪人が歩く）
const WALK_Z := -153.8          # 悪人の歩行ライン
const QUAY_EDGE_Z := -210.0     # 岸壁の縁（ここから先は海）
const SEA_Y := -1.6             # 海面の高さ

# コンテナ前列の構成 [中心x, 段数]。隙間（窓）を空けて並べる
const CONTAINERS := [
	[-30.0, 2], [-21.5, 1], [-13.0, 2], [-4.5, 1], [4.0, 2], [12.5, 1], [21.0, 2],
]
const CONT_W := 6.1
const CONT_H := 2.6
const CONT_D := 2.44

## 人質の立ち位置（隙間の中・やや端）[x, z]
const HOSTAGES := [[-17.2, -151.8], [8.4, -151.8]]

# --- 貨物船（波で上下・見張りの周期遮蔽） ---
const SHIP_POS := Vector3(35.0, 0.0, -300.0)  # 船体基準（波アニメの中心）
const SHIP_DECK := 7.0                        # 甲板の高さ（船ローカル）
const HEAVE_AMP := 0.85                       # 波の上下量(m)
const HEAVE_PERIOD := 5.2                     # 波の周期(s)

# --- 吊り荷の振り子（周期遮蔽） ---
const PEND_X := -4.5            # 振り子が守る隙間のx（CONTAINERSの4番目の隙間）
const PEND_Z := -138.0          # コンテナ列より手前＝射線上
const PEND_PERIOD := 4.6        # 振り子の周期(s)
const PEND_AMP := 0.42          # 振り角(rad)

# --- 灯台の回転ビーム（一瞬の光） ---
const BEACON_POS := Vector3(92.0, 0.0, -204.0)
const BEACON_H := 17.0
const BEACON_PERIOD := 6.5      # 1回転の周期(s)

var _rust: StandardMaterial3D
var _blue: StandardMaterial3D
var _green: StandardMaterial3D
var _metal: StandardMaterial3D
var _concrete: StandardMaterial3D
var _hull: StandardMaterial3D

var _ship: Node3D               # 波で上下する船（毎フレーム動かす）
var _pendulum: Node3D           # 吊り荷の振り子ピボット
var _beacon: Node3D             # 灯台の回転ヘッド
var _buoys: Array = []          # 点滅ブイ [{mat, phase}]
var _boats: Array = []          # 係留小型船 [{node, base_y, phase}]
var _t := 0.0


func _rig_position() -> Vector3:
	# 倉庫の屋上・前縁の左寄り
	return Vector3(-8.0, ROOF_Y + 2.0, 30.6)


func _configure_rig() -> void:
	# 埠頭全景（左のヤード〜正面のコンテナ列〜右の船・灯台）を見渡せる扇形。
	# 上はクレーンの点検台・灯台の頭まで見上げられる
	rig.set_view_limits(-75.0, 75.0, -30.0, 36.0)


func _mission_text() -> String:
	return "MISSION: ELIMINATE %d HOSTILES  /  DO NOT SHOOT HOSTAGES (WHITE)" % hostiles.size()


## 夜の海辺。旧版より地平線・環境光を明るくし「暗くて見えない」を根絶する
func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky_city.gdshader")
	sky_mat.set_shader_parameter("top_color", Color(0.008, 0.014, 0.030))
	sky_mat.set_shader_parameter("horizon_color", Color(0.055, 0.085, 0.130))
	sky_mat.set_shader_parameter("cloud_dark", Color(0.030, 0.045, 0.070))
	sky_mat.set_shader_parameter("cloud_lit", Color(0.085, 0.105, 0.140))
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.47, 0.62)
	env.ambient_light_energy = 0.55   # 視認性は保ちつつ「夜」の暗さを残す
	env.fog_enabled = true
	env.fog_light_color = Color(0.040, 0.060, 0.085)
	env.fog_density = 0.0007
	env.fog_sun_scatter = 0.0
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 月明かり（海側から。旧版より強めて形を起こす）
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.60, 0.72, 0.94)
	moon.light_energy = 0.55
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-36.0, 195.0, 0.0)
	add_child(moon)


## 海風は都市より強め（±4m/s。WIND_ENABLED=false の間は演出値のみ）
func _setup_wind() -> void:
	wind_speed = randf_range(-4.0, 4.0)
	wind_accel = Vector3(wind_speed, 0, 0) * WIND_FACTOR


func _build_world() -> void:
	# このステージにシェーダ描きのファサード窓はない（コンテナ・船体の鉄壁で
	# ガラス割れ演出が誤発動しないよう明示的に無効化する）
	set_meta("facade_windows_enabled", false)
	var docks := StaticBody3D.new()
	docks.collision_layer = 0b0001   # 地形レイヤ（弾はここで止まる・LOSもこれで判定）
	docks.collision_mask = 0
	add_child(docks)
	_make_materials()
	_build_ground(docks)
	_build_warehouse(docks)
	_build_container_yard(docks)
	_build_backdrop(docks)
	_build_cranes(docks)
	_build_pendulum()
	_build_ship()
	_build_beacon(docks)
	_build_dressing(docks)
	_build_skyline(docks)


func _make_materials() -> void:
	_rust = StandardMaterial3D.new()
	_rust.albedo_color = Color(0.55, 0.22, 0.14)
	_rust.roughness = 0.9
	_blue = StandardMaterial3D.new()
	_blue.albedo_color = Color(0.16, 0.28, 0.48)
	_blue.roughness = 0.85
	_green = StandardMaterial3D.new()
	_green.albedo_color = Color(0.16, 0.36, 0.24)
	_green.roughness = 0.85
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.30, 0.33, 0.38)
	_metal.metallic = 0.6
	_metal.roughness = 0.45
	_concrete = StandardMaterial3D.new()
	_concrete.albedo_color = Color(0.32, 0.33, 0.36)
	_concrete.roughness = 0.9
	_hull = StandardMaterial3D.new()
	_hull.albedo_color = Color(0.20, 0.10, 0.10)
	_hull.roughness = 0.7


func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material,
		coll := true) -> MeshInstance3D:
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


## 発光マテリアル（灯り。実ライトは置かず emission+glow で安く見せる）
func _glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## 岸壁（明るいコンクリート）・岸壁の縁・海面
func _build_ground(docks: StaticBody3D) -> void:
	# 埠頭の床。§3「まず地面」。夜でも読める明るめのコンクリート
	var quay := PlaneMesh.new()
	quay.size = Vector2(360.0, 320.0)
	var qm := StandardMaterial3D.new()
	qm.albedo_color = Color(0.16, 0.17, 0.20)   # 濡れた夜のアスファルト。
	qm.roughness = 0.45   # 光だまり・月光の照り返しでコントラストを作る
	var qmi := MeshInstance3D.new()
	qmi.mesh = quay
	qmi.material_override = qm
	qmi.position = Vector3(0.0, 0.0, QUAY_EDGE_Z * 0.5 + 40.0)
	docks.add_child(qmi)
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(360.0, 1.0, 320.0)
	shape.shape = bx
	shape.position = Vector3(0.0, -0.5, QUAY_EDGE_Z * 0.5 + 40.0)
	docks.add_child(shape)

	# 岸壁の縁（海へ落ちる壁）と縁石ライン
	_box(docks, Vector3(360.0, 3.0, 1.6), Vector3(0.0, -1.5, QUAY_EDGE_Z), _concrete)
	var curb := _glow_mat(Color(0.85, 0.75, 0.35), 0.5)
	_box(docks, Vector3(360.0, 0.12, 0.4), Vector3(0.0, 0.06, QUAY_EDGE_Z + 1.0), curb, false)

	# 海面（専用の夜シェーダ。波・フレネル・月のきらめき）
	var sea := PlaneMesh.new()
	sea.size = Vector2(1400.0, 900.0)
	var sea_mat := ShaderMaterial.new()
	sea_mat.shader = preload("res://stages/harbor/harbor_sea.gdshader")
	var smi := MeshInstance3D.new()
	smi.mesh = sea
	smi.material_override = sea_mat
	smi.position = Vector3(0.0, SEA_Y, QUAY_EDGE_Z - 440.0)
	docks.add_child(smi)
	# 海にも弾を止める床を敷く（着弾の水柱は出さないが弾は消える高さ）
	var sea_shape := CollisionShape3D.new()
	var sbx := BoxShape3D.new()
	sbx.size = Vector3(1400.0, 1.0, 900.0)
	sea_shape.shape = sbx
	sea_shape.position = Vector3(0.0, SEA_Y - 0.5, QUAY_EDGE_Z - 440.0)
	docks.add_child(sea_shape)


## プレイヤーの倉庫（屋上にパラペット・空調・アンテナ）
func _build_warehouse(docks: StaticBody3D) -> void:
	_box(docks, Vector3(26.0, ROOF_Y, 22.0), Vector3(-6.0, ROOF_Y * 0.5, 42.0), _concrete)
	_box(docks, Vector3(26.4, 0.2, 22.4), Vector3(-6.0, ROOF_Y + 0.1, 42.0), _concrete)
	for e in [[Vector3(26.4, 0.9, 0.7), Vector3(-6.0, ROOF_Y + 0.65, 31.2)],
			[Vector3(26.4, 0.9, 0.7), Vector3(-6.0, ROOF_Y + 0.65, 52.8)],
			[Vector3(0.7, 0.9, 22.4), Vector3(-19.2, ROOF_Y + 0.65, 42.0)],
			[Vector3(0.7, 0.9, 22.4), Vector3(7.2, ROOF_Y + 0.65, 42.0)]]:
		_box(docks, e[0], e[1], _concrete)
	# 屋上の空調ボックスと赤い航空障害灯
	_box(docks, Vector3(3.2, 1.6, 2.2), Vector3(0.5, ROOF_Y + 1.0, 46.0), _metal)
	_box(docks, Vector3(0.3, 0.3, 0.3), Vector3(0.5, ROOF_Y + 2.0, 46.0),
		_glow_mat(Color(0.9, 0.15, 0.1), 2.0), false)


## コンテナ前列（隙間が「命中の窓」）＋ヤードの積みコンテナ
func _build_container_yard(docks: StaticBody3D) -> void:
	var mats := [_rust, _blue, _green]
	for i in CONTAINERS.size():
		var cx: float = CONTAINERS[i][0]
		var stack: int = CONTAINERS[i][1]
		for lv in stack:
			_box(docks, Vector3(CONT_W, CONT_H, CONT_D),
				Vector3(cx, CONT_H * (0.5 + lv), ROW_Z),
				mats[(i + lv) % mats.size()])
	# ヤードの積みコンテナ群（左右の奥行き・遮蔽の壁）
	for c in [[-52.0, -128.0, 3], [-44.0, -140.0, 2], [46.0, -132.0, 2],
			[38.0, -118.0, 1], [58.0, -146.0, 3], [-66.0, -150.0, 2]]:
		for lv in int(c[2]):
			_box(docks, Vector3(CONT_W, CONT_H, CONT_D * 2.0),
				Vector3(c[0], CONT_H * (0.5 + lv), c[1]),
				mats[(int(c[0]) + lv) % mats.size()])
	# 岸壁の縁の4段積み（波の周期遮蔽の要）：
	# 甲板の見張りへの射線がこの山の頂すれすれを通るよう置いてあり、
	# 船が波の頂へ持ち上がった数秒だけ見張りの上半身が山の上に現れる
	for lv in 4:
		_box(docks, Vector3(CONT_W, CONT_H, CONT_D * 2.0),
			Vector3(33.5, CONT_H * (0.5 + lv), -200.0), mats[lv % mats.size()])


## 背景の大倉庫2棟（灯り窓・シャッター）。悪人のシルエットが立つ背にもなる
func _build_backdrop(docks: StaticBody3D) -> void:
	var lit := _glow_mat(Color(1.0, 0.72, 0.35), 1.8)
	# 右の倉庫は x38〜66 に寄せ、船の見張りへの射線の通り道（x22〜38付近）を空けてある
	for w in [[-38.0, -184.0, 56.0], [52.0, -184.0, 28.0]]:
		var cx: float = w[0]
		var cz: float = w[1]
		var width: float = w[2]
		_box(docks, Vector3(width, 12.0, 16.0), Vector3(cx, 6.0, cz), _concrete)
		_box(docks, Vector3(width + 0.4, 1.2, 16.4), Vector3(cx, 12.6, cz), _metal)
		# 壁の灯り窓（等間隔）とシャッター
		var n := int(width / 12.0)
		for k in n:
			var wx: float = cx - width * 0.5 + 6.0 + 12.0 * k
			_box(docks, Vector3(1.6, 1.1, 0.1), Vector3(wx, 8.4, cz + 8.1), lit, false)
			_box(docks, Vector3(4.0, 4.5, 0.2), Vector3(wx, 2.25, cz + 8.1), _metal, false)


## ガントリークレーン2基（岸壁の縁・片方の脚上に見張りの点検台）
func _build_cranes(docks: StaticBody3D) -> void:
	for cx in [-58.0, 58.0]:
		# 門型の脚4本＋横梁＋海側へ突き出すブーム
		for off in [Vector3(-9.0, 0, -4.5), Vector3(9.0, 0, -4.5),
				Vector3(-9.0, 0, 4.5), Vector3(9.0, 0, 4.5)]:
			_box(docks, Vector3(2.0, 32.0, 2.0),
				Vector3(cx + off.x, 16.0, -196.0 + off.z), _metal)
		_box(docks, Vector3(22.0, 2.6, 3.0), Vector3(cx, 30.0, -196.0), _metal)
		_box(docks, Vector3(3.0, 2.2, 40.0), Vector3(cx, 31.5, -206.0), _metal)
		# 稼働灯（緑）とブーム先端の赤灯
		_box(docks, Vector3(0.4, 0.4, 0.4), Vector3(cx, 32.9, -196.0),
			_glow_mat(Color(0.2, 0.95, 0.4), 2.2), false)
		_box(docks, Vector3(0.35, 0.35, 0.35), Vector3(cx, 31.5, -225.5),
			_glow_mat(Color(0.95, 0.2, 0.12), 2.2), false)
	# 左クレーンの梁の上に点検台＋見張り（_spawn_targetsで配置。
	# 右クレーン側は船への射線が混むため左に置く）
	_box(docks, Vector3(4.0, 0.3, 3.4), Vector3(-52.0, 31.4, -196.0), _metal)
	for rz in [-197.6, -194.4]:
		_box(docks, Vector3(4.0, 0.12, 0.12), Vector3(-52.0, 32.4, rz), _metal, false)


## 吊り荷の振り子（射線を周期的に塞ぐ・§6-2採用の周期遮蔽）
## 小型の門型ローダーがコンテナ列の手前に立ち、吊ったコンテナが左右に揺れる
func _build_pendulum() -> void:
	var docks := StaticBody3D.new()
	docks.collision_layer = 0b0001
	docks.collision_mask = 0
	add_child(docks)
	# 門型ローダー（脚2本＋梁）
	for lx in [PEND_X - 11.0, PEND_X + 11.0]:
		_box(docks, Vector3(1.6, 14.0, 1.6), Vector3(lx, 7.0, PEND_Z), _metal)
	_box(docks, Vector3(24.0, 1.8, 2.0), Vector3(PEND_X, 14.4, PEND_Z), _metal)
	# 振り子ピボット（梁の中央）。ワイヤー＋吊りコンテナが子で揺れる
	_pendulum = Node3D.new()
	add_child(_pendulum)
	_pendulum.position = Vector3(PEND_X, 13.5, PEND_Z)
	var wire := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.05
	wm.bottom_radius = 0.05
	wm.height = 9.0
	wire.mesh = wm
	wire.material_override = _metal
	wire.position = Vector3(0, -4.5, 0)
	_pendulum.add_child(wire)
	var load := StaticBody3D.new()
	load.collision_layer = 0b0001   # 吊り荷は弾を止める＝周期遮蔽
	load.collision_mask = 0
	_pendulum.add_child(load)
	_box(load, Vector3(CONT_W, CONT_H, CONT_D), Vector3(0, -10.3, 0), _rust)
	# 吊り荷の警告灯（振り子の周期を目で読める）
	_box(load, Vector3(0.3, 0.3, 0.3), Vector3(0, -8.9, 1.4),
		_glow_mat(Color(1.0, 0.65, 0.15), 2.4), false)


## 停泊中の貨物船。波で上下し、舷壁裏の見張りは波の頂の一瞬だけ見える
func _build_ship() -> void:
	_ship = Node3D.new()
	add_child(_ship)
	_ship.position = SHIP_POS
	var body := StaticBody3D.new()
	body.collision_layer = 0b0001
	body.collision_mask = 0
	_ship.add_child(body)
	# 船体（喫水下〜甲板）とハッチ・デッキコンテナ
	_box(body, Vector3(130.0, 10.0, 20.0), Vector3(0.0, SHIP_DECK - 5.0, 0.0), _hull)
	_box(body, Vector3(126.0, 0.4, 18.0), Vector3(0.0, SHIP_DECK + 0.2, 0.0), _metal)
	var mats := [_blue, _green, _rust]
	for i in 4:
		_box(body, Vector3(10.0, CONT_H, 5.0),
			Vector3(-44.0 + i * 22.0, SHIP_DECK + CONT_H * 0.5, 2.5), mats[i % 3])
	# 手前側（プレイヤー側＝ローカル+Z）の低い手すり。脚元だけを隠す
	_box(body, Vector3(130.0, 0.6, 0.4), Vector3(0.0, SHIP_DECK + 0.3, 9.7), _hull)
	# ブリッジ（船尾・窓明かり）＋マスト灯
	_box(body, Vector3(14.0, 12.0, 12.0), Vector3(50.0, SHIP_DECK + 6.0, 0.0), _concrete)
	_box(body, Vector3(11.0, 0.9, 0.2), Vector3(50.0, SHIP_DECK + 9.6, 6.1),
		_glow_mat(Color(0.95, 0.85, 0.6), 1.6), false)
	_box(body, Vector3(0.3, 4.0, 0.3), Vector3(50.0, SHIP_DECK + 14.0, 0.0), _metal, false)
	_box(body, Vector3(0.35, 0.35, 0.35), Vector3(50.0, SHIP_DECK + 16.2, 0.0),
		_glow_mat(Color(1.0, 0.95, 0.8), 2.2), false)
	# 舷側の作業灯列（船の存在を夜景に立たせる。プレイヤー側の舷）
	for i in 5:
		_box(body, Vector3(0.5, 0.25, 0.2), Vector3(-50.0 + i * 25.0, SHIP_DECK + 2.3, 9.8),
			_glow_mat(Color(1.0, 0.8, 0.45), 1.8), false)


## 灯台（回転ビーム＝一瞬の光）。頭のスポットライトが港をゆっくり舐める
func _build_beacon(docks: StaticBody3D) -> void:
	# 塔（紅白の帯）
	var band_r := StandardMaterial3D.new()
	band_r.albedo_color = Color(0.7, 0.16, 0.12)
	band_r.roughness = 0.8
	for i in 4:
		var mat: Material = band_r if i % 2 == 0 else _concrete
		var seg := CylinderMesh.new()
		seg.top_radius = 1.4 - i * 0.08
		seg.bottom_radius = 1.48 - i * 0.08
		seg.height = BEACON_H / 4.0
		var mi := MeshInstance3D.new()
		mi.mesh = seg
		mi.material_override = mat
		mi.position = BEACON_POS + Vector3(0, BEACON_H / 8.0 + BEACON_H / 4.0 * i, 0)
		docks.add_child(mi)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.5
	cyl.height = BEACON_H
	shape.shape = cyl
	shape.position = BEACON_POS + Vector3(0, BEACON_H * 0.5, 0)
	docks.add_child(shape)
	# ランプ室
	_box(docks, Vector3(2.2, 1.8, 2.2), BEACON_POS + Vector3(0, BEACON_H + 0.9, 0),
		_glow_mat(Color(1.0, 0.9, 0.6), 2.5), false)
	# 回転ヘッド：実スポットライト＋見える光条（反対向きの2本）
	_beacon = Node3D.new()
	add_child(_beacon)
	_beacon.position = BEACON_POS + Vector3(0, BEACON_H + 0.9, 0)
	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.92, 0.7)
	spot.light_energy = 8.0
	spot.spot_range = 280.0
	spot.spot_angle = 6.5
	spot.shadow_enabled = false
	spot.rotation_degrees = Vector3(0, 180.0, 0)   # -Z向き（SpotLightは-Zへ照射）
	_beacon.add_child(spot)
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(1.0, 0.9, 0.6, 0.10)
	shaft_mat.emission_enabled = true
	shaft_mat.emission = Color(1.0, 0.9, 0.65)
	shaft_mat.emission_energy_multiplier = 2.2
	shaft_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shaft_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shaft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shaft_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for dir in [1.0, -1.0]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.3
		cone.bottom_radius = 5.0
		cone.height = 120.0
		cone.radial_segments = 12
		var beam := MeshInstance3D.new()
		beam.mesh = cone
		beam.material_override = shaft_mat
		beam.rotation_degrees = Vector3(-90.0 * dir, 0, 0)
		beam.position = Vector3(0, 0, -60.0 * dir)
		_beacon.add_child(beam)


## 小物：街灯と光だまり・係留小型船・ブイ・ボラード・パレット
func _build_dressing(docks: StaticBody3D) -> void:
	# 街灯（発光ヘッド＋足元の光だまり。実ライトなし）
	for lp in [[-70.0, -80.0], [-30.0, -100.0], [15.0, -80.0], [55.0, -100.0],
			[-50.0, -170.0], [70.0, -170.0], [0.0, -30.0]]:
		_build_lamp(docks, Vector3(lp[0], 0.0, lp[1]))
	# ボラード（岸壁の縁の係船柱）
	for bx in range(-80, 100, 24):
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.28
		cm.bottom_radius = 0.34
		cm.height = 0.8
		mi.mesh = cm
		mi.material_override = _metal
		mi.position = Vector3(float(bx), 0.4, QUAY_EDGE_Z + 1.8)
		docks.add_child(mi)
	# パレット・木箱の山（ヤードの生活感）
	for pk in [[-20.0, -120.0], [26.0, -136.0], [-38.0, -112.0]]:
		_box(docks, Vector3(2.4, 1.0, 2.4), Vector3(pk[0], 0.5, pk[1]), _rust)
		_box(docks, Vector3(1.8, 0.8, 1.8), Vector3(pk[0] + 0.4, 1.9, pk[1] - 0.2), _green)
	# 係留された小型船2隻（波でゆっくり揺れる）
	for i in 2:
		var boat := Node3D.new()
		add_child(boat)
		var bx := -78.0 + i * 22.0
		boat.position = Vector3(bx, SEA_Y + 0.4, QUAY_EDGE_Z - 12.0)
		var bb := StaticBody3D.new()
		bb.collision_layer = 0b0001
		bb.collision_mask = 0
		boat.add_child(bb)
		_box(bb, Vector3(8.0, 1.6, 3.2), Vector3.ZERO, _hull)
		_box(bb, Vector3(2.6, 1.4, 2.2), Vector3(-1.2, 1.5, 0.0), _concrete)
		_box(bb, Vector3(0.25, 0.25, 0.25), Vector3(-1.2, 2.5, 0.0),
			_glow_mat(Color(1.0, 0.85, 0.55), 1.8), false)
		_boats.append({"node": boat, "base_y": boat.position.y, "phase": i * 2.1})
	# 点滅ブイ（赤・海上）
	for bp in [[-30.0, -255.0], [8.0, -340.0], [110.0, -280.0]]:
		var buoy := Node3D.new()
		add_child(buoy)
		buoy.position = Vector3(bp[0], SEA_Y + 0.5, bp[1])
		var body := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.4
		cm2.bottom_radius = 0.7
		cm2.height = 1.6
		body.mesh = cm2
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.6, 0.14, 0.10)
		body.material_override = bm
		buoy.add_child(body)
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		lamp.mesh = sm
		var lm := _glow_mat(Color(0.95, 0.18, 0.12), 2.5)
		lamp.material_override = lm
		lamp.position = Vector3(0, 1.1, 0)
		buoy.add_child(lamp)
		_buoys.append({"mat": lm, "phase": randf() * TAU, "node": buoy,
			"base_y": buoy.position.y})


func _build_lamp(docks: StaticBody3D, base: Vector3) -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.09
	pole.bottom_radius = 0.13
	pole.height = 7.5
	var pm := MeshInstance3D.new()
	pm.mesh = pole
	pm.material_override = _metal
	pm.position = base + Vector3(0, 3.75, 0)
	docks.add_child(pm)
	var head := SphereMesh.new()
	head.radius = 0.3
	head.height = 0.6
	var hmi := MeshInstance3D.new()
	hmi.mesh = head
	hmi.material_override = _glow_mat(Color(1.0, 0.83, 0.5), 2.4)
	hmi.position = base + Vector3(0, 7.6, 0)
	docks.add_child(hmi)
	# 足元の光だまり（発光の薄い円盤＝実ライトなしで「照らされた地面」を作る）
	var pool := CylinderMesh.new()
	pool.top_radius = 4.2
	pool.bottom_radius = 4.2
	pool.height = 0.02
	var pool_mat := StandardMaterial3D.new()
	pool_mat.albedo_color = Color(0.9, 0.75, 0.45, 0.28)
	pool_mat.emission_enabled = true
	pool_mat.emission = Color(0.9, 0.72, 0.4)
	pool_mat.emission_energy_multiplier = 0.85
	pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pmi := MeshInstance3D.new()
	pmi.mesh = pool
	pmi.material_override = pool_mat
	pmi.position = base + Vector3(0, 0.06, 0)
	docks.add_child(pmi)


## 対岸の夜景スカイライン（遠景。§3「遠景まで置いて場所として成立」）
func _build_skyline(docks: StaticBody3D) -> void:
	var win := _glow_mat(Color(0.95, 0.85, 0.6), 1.2)
	var win_b := _glow_mat(Color(0.6, 0.8, 1.0), 1.0)
	var heights := [38.0, 62.0, 46.0, 82.0, 54.0, 70.0, 42.0, 58.0, 90.0, 50.0]
	for i in heights.size():
		var h: float = heights[i]
		var bx := -420.0 + i * 92.0
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.05, 0.06, 0.09)
		bm.roughness = 0.9
		# 遠景ビルにも当たり判定（「見えるビルを弾が貫通」させない）
		_box(docks, Vector3(46.0, h, 30.0), Vector3(bx, h * 0.5 - 2.0, -800.0), bm)
		# 窓明かりの帯（数本・色を混ぜる）
		for k in 3:
			var wy: float = h * (0.25 + 0.25 * k)
			_box(docks, Vector3(38.0, 1.4, 0.5),
				Vector3(bx, wy, -784.5), win if (i + k) % 3 != 0 else win_b, false)


func _spawn_targets() -> void:
	var y := 0.95
	# 悪人3人：コンテナ裏の歩行ライン。歩幅と速度を変えて出現の周期をずらす。
	# 2人目の歩行範囲は吊り荷の振り子が塞ぐ隙間を含む＝周期の重なりを読む
	_add_walker(Vector3(-32.0, y, WALK_Z), Vector3(-16.0, y, WALK_Z), 1.4)
	_add_walker(Vector3(-15.0, y, WALK_Z), Vector3(1.0, y, WALK_Z), 1.7)
	_add_walker(Vector3(2.0, y, WALK_Z), Vector3(18.0, y, WALK_Z), 1.1)
	# 人質：広い隙間の中に立たされている（撃てば即失敗）
	for h in HOSTAGES:
		_add_standing(Vector3(h[0], y, h[1]), false)
	# クレーン点検台の見張り（約220m・高所）
	_add_standing(Vector3(-52.0, 31.55 + y, -196.0), true)
	# 貨物船の見張り2人（船と一緒に波で上下する＝縦のリード撃ち）
	# 1人目：甲板・手すりの内側。岸壁の4段コンテナ山が射線を遮っており、
	# 船が波の頂に持ち上がった一瞬だけ上半身が山の上に現れる（周期遮蔽・§6-2の波）
	_spawn_on_ship(Vector3(15.0, SHIP_DECK + y, 8.6))
	# 2人目：ブリッジの屋上。常に見えるが距離330m＋波の上下＝縦のリード撃ち
	_spawn_on_ship(Vector3(44.0, SHIP_DECK + 12.0 + y, 3.5))


## 船の子として立ち見張りを置く（船の揺れに追従して動く標的になる）
func _spawn_on_ship(local_pos: Vector3) -> void:
	var man := TargetHuman.new()
	man.hostile = true
	_ship.add_child(man)
	man.position = local_pos
	man.rotation.y = PI   # 舷側の外（プレイヤー側）を向く
	_register(man)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_t += delta
	# 貨物船：波でゆっくり上下＋わずかなロール（周期遮蔽。読めば当たる）
	if _ship != null:
		var ph := _t * TAU / HEAVE_PERIOD
		_ship.position.y = SHIP_POS.y + sin(ph) * HEAVE_AMP
		_ship.rotation.x = sin(ph * 0.5 + 0.8) * 0.018
		_ship.rotation.z = sin(ph * 0.35) * 0.008
	# 吊り荷の振り子（等時性のある読める揺れ）
	if _pendulum != null:
		_pendulum.rotation.z = sin(_t * TAU / PEND_PERIOD) * PEND_AMP
	# 灯台の回転ビーム
	if _beacon != null:
		_beacon.rotation.y = _t * TAU / BEACON_PERIOD
	# 係留小型船の揺れ
	for b in _boats:
		b.node.position.y = b.base_y + sin(_t * 1.1 + b.phase) * 0.12
		b.node.rotation.z = sin(_t * 0.9 + b.phase) * 0.02
	# ブイの点滅と揺れ
	for u in _buoys:
		u.mat.emission_energy_multiplier = 2.5 * maxf(0.0, sin(_t * 2.2 + u.phase))
		u.node.position.y = u.base_y + sin(_t * 1.3 + u.phase) * 0.18
