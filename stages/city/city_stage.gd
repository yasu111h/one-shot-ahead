extends SniperStage
## 「夜のビル街」ステージ（企画の柱・2026-07-12改修）。
## プレイヤーは手前のビルの屋上に陣取り、悪人が潜む5つの棟＋走る車を狙い分ける:
##   棟1(約200m) 雑居ビル: 灯った3部屋の歩く悪人＋小窓の見張り。民間人が隣にいる
##   棟2(約370m) 中距離ビル: 広間の悪人(隣に民間人)＋見張り＋民間人だけの部屋
##   棟3(約480m)・棟4(約660m) 狙撃塔: 小窓の見張り
##   棟5(約880m) 超高層タワー最上部: 超遠距離の見せ場(高倍率スコープ+▼マーカー+測距)
##   クロス通りのVIP車: 信号待ちで停車した数秒だけスモークガラスが下がり頭が覗く
## 悪人だけを撃ち抜く＝民間人の誤射で即失敗。
## 窓の開口は部屋より狭いので、悪人が「窓に現れた一瞬」だけが撃てる窓（＝本作のコア）。

const CIVILIAN_ROOMS := [0, 1]   # 民間人がいる部屋（最上階の見張りは単独）

var city: CityBuildings
var traffic: CityTraffic

# 時間帯（夜/夕方）。デバッグビルドのDEBUGパネル「TIME」ボタンで切り替えて見比べられる
var dusk := false
var _we: WorldEnvironment
var _sky_mat: ShaderMaterial
var _moon: DirectionalLight3D
var _sun: DirectionalLight3D


func _rig_position() -> Vector3:
	# 屋上の前縁・右角のすぐ内側（角から約30cm＝壁に寄りかかって狙撃する距離感）。
	# 主人公はカメラ前方1.14mに立ち体の半径が約0.3mなので、壁面から1.5mの
	# この位置なら視点をどこへ振っても体がパラペットに届かない（ギリギリの設計値）
	return Vector3(8.3, CityBuildings.ROOF_Y + 2.0, 35.7)


func _configure_rig() -> void:
	# 角から見渡せる範囲だけに視点を制限する。
	# 前方（-Z＝標的ビル）を中心に、左はクロス通りを進入してくるVIP車を
	# 追えるところまで(+62°)、右は大きく振り向けるように-110°まで。
	# 真後ろ（自分の屋上側）だけは向けない
	# 上は屋上より高い階の窓・超高層タワーの最上部まで見上げられるように+38°
	rig.set_view_limits(-110.0, 62.0, -35.0, 38.0)


func _mission_text() -> String:
	# 小窓の標的が増えたので数は動的に(HUD構築は標的スポーン後に走る)
	return "MISSION: ELIMINATE %d HOSTILES  /  DO NOT SHOOT CIVILIANS (WHITE)" % hostiles.size()


## 街の空と光。夜（既定）と夕方の2プリセットを持ち、_apply_time_of_day で切り替える
func _build_environment() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://shaders/sky_city.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

	# フォグは薄め（TABIJIより狙撃距離が長いので、濃いと200m先の部屋が見えない）
	env.fog_enabled = true
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

	_we = WorldEnvironment.new()
	_we.environment = env
	add_child(_we)

	# 月明かり(青白い弱い光)。屋上の小物と建物の形を静かに起こす
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.62, 0.72, 0.92)
	_moon.light_energy = 0.42
	_moon.shadow_enabled = false
	_moon.rotation_degrees = Vector3(-38.0, 140.0, 0.0)
	add_child(_moon)

	# 夕日(低い暖色の光)。夕方プリセットでだけ点く。
	# プレイヤーの左後ろから＝標的ビルの正面が夕日に染まる向き
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.62, 0.36)
	_sun.light_energy = 1.0
	_sun.shadow_enabled = false
	_sun.rotation_degrees = Vector3(-12.0, 30.0, 0.0)
	_sun.visible = false
	add_child(_sun)

	_apply_time_of_day(dusk)


## 時間帯プリセットの適用。false=夜（従来どおり） / true=夕方
func _apply_time_of_day(to_dusk: bool) -> void:
	dusk = to_dusk
	var env := _we.environment
	if to_dusk:
		# 夕方: 地平線が燃える暖色・雲の底が夕日に照る。空気も薄く暖色に
		_sky_mat.set_shader_parameter("top_color", Color(0.055, 0.055, 0.13))
		_sky_mat.set_shader_parameter("horizon_color", Color(0.78, 0.34, 0.11))
		_sky_mat.set_shader_parameter("cloud_dark", Color(0.20, 0.11, 0.13))
		_sky_mat.set_shader_parameter("cloud_lit", Color(0.85, 0.42, 0.20))
		env.ambient_light_color = Color(0.55, 0.44, 0.42)
		env.ambient_light_energy = 0.62
		env.fog_light_color = Color(0.34, 0.18, 0.11)
		_moon.visible = false
		_sun.visible = true
	else:
		# 夜: 濃紺の空・街明かりの照り返し（従来の値そのまま）
		_sky_mat.set_shader_parameter("top_color", Color(0.006, 0.010, 0.020))
		_sky_mat.set_shader_parameter("horizon_color", Color(0.045, 0.065, 0.105))
		_sky_mat.set_shader_parameter("cloud_dark", Color(0.030, 0.042, 0.065))
		_sky_mat.set_shader_parameter("cloud_lit", Color(0.075, 0.085, 0.115))
		env.ambient_light_color = Color(0.36, 0.44, 0.58)
		env.ambient_light_energy = 0.5
		env.fog_light_color = Color(0.045, 0.065, 0.10)
		_moon.visible = true
		_sun.visible = false


## DEBUGパネルの「TIME」ボタンから呼ばれる：夜⇔夕方の切り替え
func toggle_time_of_day() -> void:
	_apply_time_of_day(not dusk)


## HUDが「TIME: NIGHT/DUSK」表示に使う
func is_dusk() -> bool:
	return dusk


func _build_world() -> void:
	city = CityBuildings.new()
	add_child(city)
	traffic = CityTraffic.new()
	add_child(traffic)


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

	# 小窓の部屋(棟1の小窓＋棟2の見張り＋狙撃塔480/660m＋超高層880m)：
	# 悪人が窓辺に立って外を見張っている。ガラスは小さいまま=見えるのは上半身だけ
	for p in city.small_rooms:
		var man := _add_standing(p, true)
		man.rotation.y = PI   # 窓の外(プレイヤー側)を向く

	# 棟2(中距離ビル)の広間: 悪人が往復し、窓の右端に民間人が立ちすくむ
	_add_walker(city.mid_walk_from, city.mid_walk_to, 1.1)

	# サイドビル(棟6右手・棟7左手): 広間を往復する悪人＋小窓/屋上の見張り。
	# 視点を左右へ大きく振った先にも標的がいる(2026-07-12ユーザー指示の分散)
	for w in city.side_walks:
		_add_walker(w.from, w.to, 1.3)
	for p in city.side_stands:
		var guard := _add_standing(p, true)
		# プレイヤーの方を向いて見張る
		guard.rotation.y = atan2(rig.position.x - p.x, rig.position.z - p.z) if rig != null \
			else atan2(8.6 - p.x, 35.4 - p.z)

	# 民間人だけの部屋(棟2の広間の窓際＋上階の「はずれ部屋」＋サイドビル広間)。撃てば即失敗
	for p in city.civil_rooms:
		_add_standing(p, false)

	# VIP車の標的: 信号待ちで停車し窓が開いた数秒だけ頭が覗く
	var vip := TargetHuman.new()
	vip.hostile = true
	add_child(vip)
	traffic.seat_vip(vip)
	_register(vip)
