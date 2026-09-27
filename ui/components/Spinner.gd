## Minimal animated loading ring
extends Control
class_name Spinner

@export var color: Color = Color(0.52, 0.91, 0.42)
@export var thickness: float = 5.0
@export var speed: float = 5.0

var _angle: float = 0.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float):
	_angle = fmod(_angle + delta * speed, TAU)
	queue_redraw()

func _draw():
	var center = size / 2.0
	var radius = min(size.x, size.y) / 2.0 - thickness
	draw_arc(center, radius, 0.0, TAU, 48, Color(color, 0.15), thickness, true)
	var sweep = PI * (0.9 + 0.35 * sin(_angle * 0.8))
	draw_arc(center, radius, _angle, _angle + sweep, 32, color, thickness, true)
