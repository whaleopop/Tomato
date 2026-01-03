## Singleton for screen effects like camera shake and flashes
extends Node
class_name ScreenEffects

static var instance: ScreenEffects = null

var camera: Camera3D = null
var original_position: Vector3 = Vector3.ZERO
var shake_amount: float = 0.0
var shake_decay: float = 5.0
var is_shaking: bool = false

# Flash overlay
var flash_canvas: CanvasLayer = null

func _ready():
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_flash_canvas()

func _setup_flash_canvas():
	flash_canvas = CanvasLayer.new()
	flash_canvas.layer = 90
	add_child(flash_canvas)

func _process(delta: float):
	_process_shake(delta)

func _process_shake(delta: float):
	if shake_amount > 0:
		shake_amount = max(0, shake_amount - shake_decay * delta)

		if camera and is_instance_valid(camera):
			var offset = Vector3(
				randf_range(-1, 1) * shake_amount,
				randf_range(-1, 1) * shake_amount,
				0
			)
			camera.position = original_position + offset

			if shake_amount <= 0.01:
				camera.position = original_position
				is_shaking = false

## Start camera shake effect
static func shake(amount: float = 0.3, decay: float = 5.0):
	if instance:
		instance._do_shake(amount, decay)

func _do_shake(amount: float, decay: float):
	# Find camera if not cached
	if not camera or not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()

	if camera:
		if not is_shaking:
			original_position = camera.position
			is_shaking = true

		# Add to existing shake (don't reset)
		shake_amount = max(shake_amount, amount)
		shake_decay = decay

## Flash the screen with a color
static func flash(color: Color = Color.RED, duration: float = 0.1, intensity: float = 0.3):
	if instance:
		instance._do_flash(color, duration, intensity)

func _do_flash(color: Color, duration: float, intensity: float):
	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = color
	overlay.color.a = intensity
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	flash_canvas.add_child(overlay)

	var tween = create_tween()
	tween.tween_property(overlay, "color:a", 0.0, duration)
	tween.tween_callback(overlay.queue_free)

## Damage flash effect (red flash + shake)
static func damage_effect(damage_amount: float = 10.0):
	var shake_intensity = clamp(damage_amount / 50.0, 0.1, 0.5)
	shake(shake_intensity, 8.0)
	flash(Color(1, 0, 0), 0.15, 0.25)

## Heal flash effect (green flash)
static func heal_effect():
	flash(Color(0, 1, 0.3), 0.2, 0.15)

## Impact effect (white flash + strong shake)
static func impact_effect(intensity: float = 1.0):
	shake(0.5 * intensity, 6.0)
	flash(Color(1, 1, 0.8), 0.1, 0.4 * intensity)

## Explosion effect (orange flash + shake)
static func explosion_effect(distance: float = 0.0):
	# Closer = stronger effect
	var intensity = clamp(1.0 - (distance / 20.0), 0.2, 1.0)
	shake(0.6 * intensity, 4.0)
	flash(Color(1, 0.6, 0.2), 0.15, 0.35 * intensity)

## Low health pulse effect
static func low_health_pulse():
	flash(Color(0.8, 0, 0), 0.5, 0.1)

## Ability ready pulse (subtle)
static func ability_ready_pulse():
	flash(Color(0.5, 0.8, 1.0), 0.3, 0.08)
