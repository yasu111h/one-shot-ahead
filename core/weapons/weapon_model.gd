class_name WeaponModel
extends RefCounted
## 武器の3Dモデルを箱の組み合わせで作る共用ビルダー（外部アセットなし）。
## 使う場所：①主人公アバターの手元（sniper_girl）②ARMORYの回転プレビュー（shop）。
## 座標系は sniper_girl の旧 _make_rifle と同じ＝バレルはローカル+Z方向・原点は受け付近。
## 各武器は形とアクセント色（WeaponDb.color）で見分けが付くように作り分ける。

static func build(id: String) -> Node3D:
	var w := WeaponDb.by_id(id)
	var root := Node3D.new()
	root.name = "Rifle"
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.11, 0.11, 0.13)
	metal.metallic = 0.8
	metal.roughness = 0.4
	var accent := StandardMaterial3D.new()
	accent.albedo_color = w.color * 0.55  # アクセント色（暗めに落として銃らしく）
	accent.metallic = 0.4
	accent.roughness = 0.55
	match w.id:
		"hawkeye":
			_build_hawkeye(root, metal, accent)
		"raptor":
			_build_raptor(root, metal, accent)
		"tempest":
			_build_tempest(root, metal, accent)
		_:
			_build_ghost(root, metal, accent)
	return root


## GHOST M24: 標準ボルトアクション（旧 sniper_girl._make_rifle と同形）
static func _build_ghost(root: Node3D, metal: Material, accent: Material) -> void:
	_box(root, Vector3(0.05, 0.075, 0.30), Vector3(0.0, 0.0, 0.05), metal)       # 受け
	_box(root, Vector3(0.026, 0.026, 0.46), Vector3(0.0, 0.014, 0.42), metal)    # 銃身
	_box(root, Vector3(0.036, 0.036, 0.07), Vector3(0.0, 0.014, 0.66), accent)   # マズル
	_box(root, Vector3(0.032, 0.032, 0.16), Vector3(0.0, 0.075, 0.06), metal)    # スコープ
	_box(root, Vector3(0.045, 0.065, 0.16), Vector3(0.0, -0.01, -0.17), accent)  # ストック
	var grip := _box(root, Vector3(0.04, 0.10, 0.05), Vector3(0.0, -0.08, -0.05), accent)
	grip.rotation_degrees = Vector3(18.0, 0.0, 0.0)
	var mag := _box(root, Vector3(0.03, 0.10, 0.055), Vector3(0.0, -0.085, 0.09), metal)
	mag.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	_bipod(root, metal, 0.52)


## HAWKEYE X: 超遠距離向き＝さらに長い銃身＋大型スコープ＋頬当て付きストック
static func _build_hawkeye(root: Node3D, metal: Material, accent: Material) -> void:
	_box(root, Vector3(0.05, 0.075, 0.32), Vector3(0.0, 0.0, 0.05), metal)
	_box(root, Vector3(0.024, 0.024, 0.60), Vector3(0.0, 0.014, 0.50), metal)    # 長銃身
	_box(root, Vector3(0.04, 0.04, 0.10), Vector3(0.0, 0.014, 0.83), accent)     # 大型マズル
	_box(root, Vector3(0.042, 0.042, 0.24), Vector3(0.0, 0.085, 0.05), accent)   # 大型スコープ
	_box(root, Vector3(0.05, 0.014, 0.05), Vector3(0.0, 0.055, 0.05), metal)     # マウント
	_box(root, Vector3(0.045, 0.07, 0.20), Vector3(0.0, -0.005, -0.19), accent)  # ストック
	_box(root, Vector3(0.03, 0.03, 0.10), Vector3(0.0, 0.045, -0.20), accent)    # 頬当て
	var grip := _box(root, Vector3(0.04, 0.10, 0.05), Vector3(0.0, -0.08, -0.05), accent)
	grip.rotation_degrees = Vector3(18.0, 0.0, 0.0)
	var mag := _box(root, Vector3(0.03, 0.09, 0.05), Vector3(0.0, -0.08, 0.10), metal)
	mag.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	_bipod(root, metal, 0.66)


## RAPTOR SEMI: 速射＝短めの箱型ボディ＋長い弾倉＋短スコープ（カービン風）
static func _build_raptor(root: Node3D, metal: Material, accent: Material) -> void:
	_box(root, Vector3(0.052, 0.085, 0.36), Vector3(0.0, 0.0, 0.08), accent)     # 箱型ボディ
	_box(root, Vector3(0.028, 0.028, 0.30), Vector3(0.0, 0.014, 0.40), metal)    # 短め銃身
	_box(root, Vector3(0.034, 0.034, 0.05), Vector3(0.0, 0.014, 0.56), metal)    # マズル
	_box(root, Vector3(0.03, 0.03, 0.10), Vector3(0.0, 0.07, 0.08), metal)       # 短スコープ
	_box(root, Vector3(0.02, 0.05, 0.02), Vector3(0.0, 0.065, 0.28), metal)      # フロントサイト
	_box(root, Vector3(0.045, 0.055, 0.13), Vector3(0.0, 0.0, -0.15), metal)     # 短ストック
	var grip := _box(root, Vector3(0.04, 0.09, 0.05), Vector3(0.0, -0.075, -0.04), metal)
	grip.rotation_degrees = Vector3(18.0, 0.0, 0.0)
	var mag := _box(root, Vector3(0.032, 0.15, 0.06), Vector3(0.0, -0.10, 0.12), accent)
	mag.rotation_degrees = Vector3(-16.0, 0.0, 0.0)   # 長い弾倉（前傾）


## TEMPEST LMG: 物量戦＝太い銃身＋ドラムマガジン＋ハンドル＋二脚
static func _build_tempest(root: Node3D, metal: Material, accent: Material) -> void:
	_box(root, Vector3(0.06, 0.09, 0.34), Vector3(0.0, 0.0, 0.06), metal)        # 太いボディ
	_box(root, Vector3(0.036, 0.036, 0.40), Vector3(0.0, 0.014, 0.44), metal)    # 太い銃身
	_box(root, Vector3(0.05, 0.05, 0.06), Vector3(0.0, 0.014, 0.65), accent)     # マズル
	_box(root, Vector3(0.028, 0.05, 0.14), Vector3(0.0, 0.085, 0.02), metal)     # キャリングハンドル
	_box(root, Vector3(0.02, 0.035, 0.02), Vector3(0.0, 0.06, 0.30), metal)      # フロントサイト
	_box(root, Vector3(0.05, 0.07, 0.14), Vector3(0.0, -0.005, -0.16), accent)   # ストック
	var grip := _box(root, Vector3(0.04, 0.09, 0.05), Vector3(0.0, -0.075, -0.04), metal)
	grip.rotation_degrees = Vector3(18.0, 0.0, 0.0)
	# ドラムマガジン（円筒・ボディ下）
	var drum := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.055
	cyl.bottom_radius = 0.055
	cyl.height = 0.05
	drum.mesh = cyl
	drum.material_override = accent
	drum.rotation_degrees = Vector3(0.0, 0.0, 90.0)   # 横倒し＝弾倉らしく
	drum.position = Vector3(0.0, -0.075, 0.10)
	drum.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(drum)
	_bipod(root, metal, 0.50)


## 二脚（前方下・左右）
static func _bipod(root: Node3D, metal: Material, z: float) -> void:
	for sx in [-1.0, 1.0]:
		var leg := _box(root, Vector3(0.012, 0.14, 0.012), Vector3(sx * 0.03, -0.08, z), metal)
		leg.rotation_degrees = Vector3(0.0, 0.0, sx * -14.0)


static func _box(root: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi
