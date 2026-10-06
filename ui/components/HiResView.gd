## A 3D preview that renders at the physical resolution: SubViewportContainer(stretch) sizes its
## viewport in virtual (canvas_items) units, so on 4K the preview was half res. This owns a
## SubViewport (created here, subclasses set its options) shown by a TextureRect, and sizes it
## to the control times UIScale.render_scale (1..2).
extends Control
class_name HiResView

var viewport: SubViewport
var _tex: TextureRect

func _init() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(2, 2)
	add_child(viewport)
	_tex = TextureRect.new()
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_tex.texture = viewport.get_texture()
	add_child(_tex)

func _enter_tree() -> void:
	var root := get_tree().root
	if not root.size_changed.is_connected(_update_viewport_size):
		root.size_changed.connect(_update_viewport_size)
	_update_viewport_size()

func _exit_tree() -> void:
	var tree := get_tree()
	if tree and tree.root.size_changed.is_connected(_update_viewport_size):
		tree.root.size_changed.disconnect(_update_viewport_size)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_viewport_size()

func _update_viewport_size() -> void:
	if viewport == null:
		return
	var k := clampf(UIScale.render_scale(self), 1.0, 2.0)
	var s := Vector2i((size * k).round())
	viewport.size = Vector2i(maxi(s.x, 1), maxi(s.y, 1))

## Control-local position -> viewport pixels
func to_vp(local: Vector2) -> Vector2:
	if size.x <= 0.0 or size.y <= 0.0:
		return local
	return local * Vector2(viewport.size) / size

## Viewport pixels -> control-local position
func from_vp(p: Vector2) -> Vector2:
	var vs := Vector2(viewport.size)
	if vs.x <= 0.0 or vs.y <= 0.0:
		return p
	return p * size / vs
