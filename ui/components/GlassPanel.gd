## Frosted-glass container: soft shadow, blurred backdrop, translucent tint and a thin light rim.
## Behaves like a PanelContainer (children are fitted inside `padding`), the decoration layers
## are internal children so they never show up in get_children().
@tool
extends Container
class_name GlassPanel

const GLASS_SHADER = preload("res://shaders/ui_glass.gdshader")

@export var padding: int = 24:
	set(value):
		padding = value
		queue_sort()
		update_minimum_size()
@export var corner_radius: int = 22:
	set(value):
		corner_radius = value
		_apply_styles()
@export var tint: Color = Color(0.04, 0.055, 0.10, 0.62):
	set(value):
		tint = value
		_apply_styles()
@export var blur: float = 3.2:
	set(value):
		blur = value
		_apply_styles()
@export var rim_color: Color = Color(1, 1, 1, 0.16):
	set(value):
		rim_color = value
		_apply_styles()
@export var show_shadow: bool = true:
	set(value):
		show_shadow = value
		_apply_styles()

var _shadow: Panel
var _backdrop: Panel
var _frame: Panel
var _material: ShaderMaterial

func _init():
	if _frame:
		return  # Subclasses may call super._init() explicitly
	mouse_filter = Control.MOUSE_FILTER_STOP

	_shadow = _make_layer("Shadow")
	_backdrop = _make_layer("Backdrop")
	_frame = _make_layer("Frame")

	_material = ShaderMaterial.new()
	_material.shader = GLASS_SHADER
	_backdrop.material = _material

	_apply_styles()

func _make_layer(layer_name: String) -> Panel:
	var layer = Panel.new()
	layer.name = layer_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer, false, Node.INTERNAL_MODE_FRONT)
	return layer

func _apply_styles():
	if not _frame:
		return

	var shadow_box = StyleBoxFlat.new()
	shadow_box.bg_color = Color(0, 0, 0, 0)
	shadow_box.set_corner_radius_all(corner_radius)
	shadow_box.shadow_color = Color(0, 0, 0, 0.35 if show_shadow else 0.0)
	shadow_box.shadow_size = 28
	shadow_box.shadow_offset = Vector2(0, 10)
	_shadow.add_theme_stylebox_override("panel", shadow_box)

	# Opaque white is only a mask for the blur shader (rounded, antialiased)
	var mask_box = StyleBoxFlat.new()
	mask_box.bg_color = Color.WHITE
	mask_box.set_corner_radius_all(corner_radius)
	mask_box.anti_aliasing = true
	_backdrop.add_theme_stylebox_override("panel", mask_box)

	var frame_box = StyleBoxFlat.new()
	frame_box.bg_color = Color(1, 1, 1, 0.045)
	frame_box.set_corner_radius_all(corner_radius)
	frame_box.set_border_width_all(1)
	frame_box.border_color = rim_color
	frame_box.border_blend = false
	_frame.add_theme_stylebox_override("panel", frame_box)

	_material.set_shader_parameter("tint_color", tint)
	_update_blur()

## The blur is a mip level in physical pixels: add log2 of the render scale to keep the frost
## the same strength on 4K
func _update_blur() -> void:
	if _material == null:
		return
	var k := maxf(UIScale.render_scale(self), 1.0)
	_material.set_shader_parameter("blur_lod", clampf(blur + log(k) / log(2.0), 0.0, 7.0))

func _notification(what: int):
	if what == NOTIFICATION_ENTER_TREE:
		if not get_tree().root.size_changed.is_connected(_update_blur):
			get_tree().root.size_changed.connect(_update_blur)
		_update_blur()
	elif what == NOTIFICATION_EXIT_TREE:
		if get_tree() and get_tree().root.size_changed.is_connected(_update_blur):
			get_tree().root.size_changed.disconnect(_update_blur)
	if what == NOTIFICATION_SORT_CHILDREN:
		var full = Rect2(Vector2.ZERO, size)
		for layer in [_shadow, _backdrop, _frame]:
			fit_child_in_rect(layer, full)

		var inner = Rect2(Vector2(padding, padding), size - Vector2(padding, padding) * 2.0)
		for child in get_children():
			if child is Control and child.visible and not child.top_level:
				fit_child_in_rect(child, inner)

func _get_minimum_size() -> Vector2:
	var min_size = Vector2.ZERO
	for child in get_children():
		if child is Control and child.visible and not child.top_level:
			min_size = min_size.max(child.get_combined_minimum_size())
	return min_size + Vector2(padding, padding) * 2.0
