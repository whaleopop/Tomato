## Button with hover and press animations
extends Button
class_name AnimatedButton

@export var hover_scale: float = 1.05
@export var press_scale: float = 0.95
@export var animation_duration: float = 0.1
@export var enable_glow: bool = true
@export var glow_color: Color = Color(1.2, 1.2, 1.2)
@export var enable_sound: bool = true

var original_scale: Vector2 = Vector2.ONE
var original_modulate: Color = Color.WHITE
var current_tween: Tween = null

func _ready():
	original_scale = scale
	original_modulate = modulate

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)

	# Set pivot to center for proper scaling
	pivot_offset = size / 2

func _on_mouse_entered():
	_animate_scale(original_scale * hover_scale)

	if enable_glow:
		_animate_modulate(glow_color)

func _on_mouse_exited():
	_animate_scale(original_scale)
	_animate_modulate(original_modulate)

func _on_button_down():
	_animate_scale(original_scale * press_scale)

func _on_button_up():
	if is_hovered():
		_animate_scale(original_scale * hover_scale)
	else:
		_animate_scale(original_scale)

func _animate_scale(target: Vector2):
	if current_tween:
		current_tween.kill()

	current_tween = create_tween()
	current_tween.tween_property(self, "scale", target, animation_duration)
	current_tween.set_ease(Tween.EASE_OUT)
	current_tween.set_trans(Tween.TRANS_BACK)

func _animate_modulate(target: Color):
	var tween = create_tween()
	tween.tween_property(self, "modulate", target, animation_duration)

## Call this to play a "bounce" animation (useful for notifications)
func play_bounce():
	var tween = create_tween()
	tween.tween_property(self, "scale", original_scale * 1.15, 0.1)
	tween.tween_property(self, "scale", original_scale * 0.95, 0.1)
	tween.tween_property(self, "scale", original_scale, 0.1)

## Call this to play a "shake" animation (useful for errors)
func play_shake():
	var original_pos = position
	var tween = create_tween()
	tween.tween_property(self, "position:x", original_pos.x + 5, 0.05)
	tween.tween_property(self, "position:x", original_pos.x - 5, 0.05)
	tween.tween_property(self, "position:x", original_pos.x + 3, 0.05)
	tween.tween_property(self, "position:x", original_pos.x - 3, 0.05)
	tween.tween_property(self, "position:x", original_pos.x, 0.05)

## Call this to play a "pulse" animation (useful for highlighting)
func play_pulse():
	var tween = create_tween()
	tween.set_loops(3)
	tween.tween_property(self, "modulate", Color(1.3, 1.3, 1.3), 0.2)
	tween.tween_property(self, "modulate", original_modulate, 0.2)
