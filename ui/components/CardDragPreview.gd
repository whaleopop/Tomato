## What follows the mouse while a ParallaxCard is dragged: the card's own picture through the same
## perspective tilt (shaders/card_tilt.gdshader), held where it was grabbed. It leans into the
## motion like a real card in the air (yaw from the horizontal speed, pitch from the vertical,
## a little roll), lifted with a shadow under it, and settles when the mouse stops.
## Made by ParallaxCard._get_drag_data; Godot moves it with the mouse until the drop.
extends Control
class_name CardDragPreview

const LEAN: float = 0.0016        # radians of tilt per px/s of mouse speed
const MAX_LEAN: float = 0.55
const ROLL: float = 0.00022       # radians of roll per px/s sideways
const LIFT_SCALE: float = 1.08

var _card_size := Vector2(190, 264)
var _holder: Control
var _view: TextureRect
var _shadow: TextureRect
var _material: ShaderMaterial
var _last := Vector2.ZERO
var _velocity := Vector2.ZERO
var _tilt := Vector2.ZERO
var _first: bool = true

## A preview of `card` grabbed at `grab` (local position on the card)
static func make(card: ParallaxCard, grab: Vector2) -> CardDragPreview:
	var p = CardDragPreview.new()
	p._card_size = card.size if card.size.x > 0.0 else card.card_size
	p._build(card.card_texture(), grab, card.card_size)
	return p

func _build(texture: Texture2D, grab: Vector2, design_size: Vector2) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_as_relative = false
	z_index = 200                 # over the hovered cards (they rise to 10)
	# The holder turns around the grab point, the card hangs from it
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.size = _card_size
	_holder.position = -grab
	_holder.pivot_offset = grab
	add_child(_holder)
	_shadow = TextureRect.new()
	_shadow.texture = FireTrail._soft_dot(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0))
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	_shadow.size = _card_size * Vector2(1.25, 1.1)
	_shadow.position = -_card_size * Vector2(0.125, 0.05) + Vector2(14, 26)
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_shadow)
	var extra = _card_size * ParallaxCard.OVERSCAN * 0.5
	_view = TextureRect.new()
	_view.texture = texture
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.position = -extra
	_view.size = _card_size + extra * 2.0
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/card_tilt.gdshader")
	_material.set_shader_parameter("aspect", design_size.x / design_size.y)
	_material.set_shader_parameter("inset", 1.0 + ParallaxCard.OVERSCAN)
	_material.set_shader_parameter("corner", ParallaxCard.CORNER_RADIUS / design_size.y)
	_material.set_shader_parameter("lift", 1.0)
	_view.material = _material
	_holder.add_child(_view)
	_holder.scale = Vector2.ONE * 0.96
	var t = create_tween()
	t.tween_property(_holder, "scale", Vector2.ONE * LIFT_SCALE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float):
	var pos = get_global_mouse_position()
	if _first:
		_first = false
		_last = pos
	var v = (pos - _last) / max(delta, 0.001)
	_last = pos
	_velocity = _velocity.lerp(v, 1.0 - exp(-delta * 14.0))
	var want = Vector2(clamp(_velocity.x * LEAN, -MAX_LEAN, MAX_LEAN), clamp(_velocity.y * LEAN, -MAX_LEAN, MAX_LEAN))
	_tilt = _tilt.lerp(want, 1.0 - exp(-delta * 10.0))
	# Leaning into the motion: the leading edge dips away from you
	_material.set_shader_parameter("yaw", -_tilt.x)
	_material.set_shader_parameter("pitch", _tilt.y)
	_holder.rotation = clamp(_velocity.x * ROLL, -0.2, 0.2)
	# The shadow trails behind, further when it moves fast
	_shadow.position = -_card_size * Vector2(0.125, 0.05) + Vector2(14, 26) - _tilt * 40.0
