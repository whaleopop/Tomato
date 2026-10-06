## Floating-base virtual joystick for touch controls: tracks one finger by its touch index,
## hit-tested against this control's own screen rect on touch-down so several sticks (move +
## aim) work independently at once. `vector` is 0..1 in magnitude, zero while untouched.
extends Control
class_name VirtualStick

const BASE_RADIUS: float = 100.0
const KNOB_RADIUS: float = 42.0
const DEAD_ZONE: float = 0.2

var vector: Vector2 = Vector2.ZERO
var active: bool = false

var _touch_index: int = -1
var _base_pos: Vector2 = Vector2.ZERO
var _knob_pos: Vector2 = Vector2.ZERO

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func _process(_delta: float) -> void:
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1 and get_global_rect().has_point(event.position):
				_touch_index = event.index
				_base_pos = _clamp_to_screen(event.position)
				_knob_pos = _base_pos
				active = true
				vector = Vector2.ZERO
				get_viewport().set_input_as_handled()
		else:
			if event.index == _touch_index:
				_touch_index = -1
				active = false
				vector = Vector2.ZERO
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			_update_knob(event.position)
			get_viewport().set_input_as_handled()

func _update_knob(screen_pos: Vector2) -> void:
	var delta = screen_pos - _base_pos
	var dist = delta.length()
	if dist > BASE_RADIUS:
		delta = delta / dist * BASE_RADIUS
		dist = BASE_RADIUS
	_knob_pos = _base_pos + delta
	var ratio = dist / BASE_RADIUS
	if ratio < DEAD_ZONE:
		vector = Vector2.ZERO
	else:
		var scaled = (ratio - DEAD_ZONE) / (1.0 - DEAD_ZONE)
		vector = delta.normalized() * clampf(scaled, 0.0, 1.0)

## Keep the floating base fully on screen (it may appear anywhere inside this control's zone)
func _clamp_to_screen(pos: Vector2) -> Vector2:
	var rect = get_global_rect()
	return Vector2(
		clampf(pos.x, rect.position.x + BASE_RADIUS, rect.position.x + rect.size.x - BASE_RADIUS),
		clampf(pos.y, rect.position.y + BASE_RADIUS, rect.position.y + rect.size.y - BASE_RADIUS)
	)

func _draw() -> void:
	if not active:
		return
	var opacity = clampf(GameSettings.touch_opacity, 0.0, 1.0)
	var local_base = _base_pos - global_position
	var local_knob = _knob_pos - global_position
	draw_circle(local_base, BASE_RADIUS, Color(1, 1, 1, 0.15 * opacity))
	draw_arc(local_base, BASE_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.35 * opacity), 2.0)
	draw_circle(local_knob, KNOB_RADIUS, Color(1, 1, 1, 0.35 * opacity))
