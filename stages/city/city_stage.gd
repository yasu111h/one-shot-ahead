extends SniperStage
## 「夜のビル街」ステージ（企画の柱）。
## プレイヤーは手前のビルの屋上に陣取り、約200m先の雑居ビルの灯った3部屋を狙う。
## 各部屋では悪人が動き回り、そばに民間人がいる。悪人だけを撃ち抜く＝誤射で即失敗。
## 窓の開口は部屋より狭いので、悪人が「窓に現れた一瞬」だけが撃てる窓（＝本作のコア）。

const CIVILIAN_ROOMS := [0, 1]   # 民間人がいる部屋（最上階の見張りは単独）

var city: CityBuildings


func _rig_position() -> Vector3:
	# 屋上の前縁・右角（パラペットの内側すぐ）。スナイパーは屋上の端に陣取る
	return Vector3(8.6, CityBuildings.ROOF_Y + 2.0, 35.4)


func _configure_rig() -> void:
	# 角から見渡せる範囲だけに視点を制限する。
	# 前方（-Z＝標的ビル）を中心に、左は通りの谷間まで(+50°)、
	# 右は大きく振り向けるように-110°まで(右側の街並み・標的ビル群を見渡せる)。
	# 真後ろ（自分の屋上側）だけは向けない
	rig.set_view_limits(-110.0, 50.0, -35.0, 12.0)


func _mission_text() -> String:
	return "MISSION: ELIMINATE 3 HOSTILES  /  DO NOT SHOOT CIVILIANS (WHITE)"


## 夜の街: 雲の流れる濃紺の空。地平線は街明かりの照り返しで青白い
func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky_city.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.44, 0.58)
	env.ambient_light_energy = 0.5

	# フォグは薄め（TABIJIより狙撃距離が長いので、濃いと200m先の部屋が見えない）
	env.fog_enabled = true
	env.fog_light_color = Color(0.045, 0.065, 0.10)
	env.fog_density = 0.0009
	env.fog_sun_scatter = 0.0
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.4

	# 窓明かり・障害灯・部屋の光をにじませる
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.08

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 月明かり(青白い弱い光)。屋上の小物と建物の形を静かに起こす
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 0.92)
	moon.light_energy = 0.42
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-38.0, 140.0, 0.0)
	add_child(moon)


func _build_world() -> void:
	city = CityBuildings.new()
	add_child(city)


## 夜の街なのでビル風は穏やか（±3m/s）
func _setup_wind() -> void:
	wind_speed = randf_range(-3.0, 3.0)
	wind_accel = Vector3(wind_speed, 0, 0) * WIND_FACTOR


func _spawn_targets() -> void:
	var speeds := [1.2, 1.6, 0.9]
	for i in CityBuildings.ROOMS.size():
		var cx: float = CityBuildings.ROOMS[i][0]
		var fy: float = CityBuildings.ROOMS[i][1]
		var y := fy + 0.95   # 床(fy+0.2)の上に立つ胴体中心
		# 悪人：部屋の中を左右に行き来する。窓の開口(幅5m)より広く歩くので、
		# 窓に現れる一瞬だけが撃てる
		_add_walker(
			Vector3(cx - 3.6, y, -163.0),
			Vector3(cx + 3.6, y, -163.0),
			speeds[i])
		# 民間人：窓際に立ちすくむ。撃てば即ミッション失敗
		if i in CIVILIAN_ROOMS:
			_add_standing(Vector3(cx + 1.9, y, -161.8), false)
