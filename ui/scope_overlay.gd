class_name ScopeOverlay
extends Control
## 2Dスコープマスク：円形ケラレ（黒マスク・シェーダ）＋ミルドット付きレティクル

const SHADER_CODE := "
shader_type canvas_item;
uniform vec2 rect_size = vec2(854.0, 480.0);
uniform float radius = 210.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * rect_size;
	float d = length(p);
	// 円の外側を黒でマスク（縁は2段のぼかし）
	float vignette = smoothstep(radius - 2.0, radius + 20.0, d);
	// スコープ筒の縁リング
	float ring = (1.0 - smoothstep(0.0, 5.0, abs(d - radius))) * 0.65;
	float a = max(vignette, ring);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"

var scope_radius := 210.0

var _mask: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask = ColorRect.new()
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mask.material = _mat
	add_child(_mask)
	_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_update_params)
	_update_params()


func _update_params() -> void:
	scope_radius = minf(size.x, size.y) * 0.44
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("radius", scope_radius)
	queue_redraw()


func _draw() -> void:
	# ミルドットのみ描く（中央の十字は動的レティクル＝HUD側が担当する）
	var c := size * 0.5
	var col := Color(0.05, 0.05, 0.05, 0.85)
	var r := scope_radius
	# ミルドット（重力落下・風の保持照準用）
	for i in range(1, 7):
		var d := i * 24.0
		if d < r - 12.0:
			draw_circle(c + Vector2(0, d), 2.2, col)   # 下（ドロップ補正）
			if i <= 4:
				draw_circle(c + Vector2(d, 0), 2.2, col)   # 右（風補正）
				draw_circle(c - Vector2(d, 0), 2.2, col)   # 左
