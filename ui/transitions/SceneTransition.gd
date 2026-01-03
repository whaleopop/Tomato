## Singleton for smooth scene transitions with fade effects
## Autoload: SceneTransition
extends CanvasLayer

signal transition_started
signal transition_finished

var color_rect: ColorRect = null
var is_transitioning: bool = false

func _ready():
	layer = 100  # Above everything
	process_mode = Node.PROCESS_MODE_ALWAYS  # Work even when paused
	_create_overlay()

func _create_overlay():
	color_rect = ColorRect.new()
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.color = Color(0, 0, 0, 0)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(color_rect)

## Fade to black, change scene, fade back in
func fade_to_scene(scene_path: String, duration: float = 0.5, fade_color: Color = Color.BLACK):
	if is_transitioning:
		return

	is_transitioning = true
	transition_started.emit()

	color_rect.color = Color(fade_color.r, fade_color.g, fade_color.b, 0)

	# Fade out
	var tween = create_tween()
	tween.tween_property(color_rect, "color:a", 1.0, duration)
	await tween.finished

	# Change scene
	get_tree().change_scene_to_file(scene_path)

	# Wait a frame for scene to load
	await get_tree().process_frame

	# Fade in
	tween = create_tween()
	tween.tween_property(color_rect, "color:a", 0.0, duration)
	await tween.finished

	is_transitioning = false
	transition_finished.emit()

## Just fade out (useful for custom transitions)
func fade_out(duration: float = 0.3, fade_color: Color = Color.BLACK) -> Tween:
	color_rect.color = Color(fade_color.r, fade_color.g, fade_color.b, 0)
	var tween = create_tween()
	tween.tween_property(color_rect, "color:a", 1.0, duration)
	return tween

## Just fade in (useful for custom transitions)
func fade_in(duration: float = 0.3) -> Tween:
	var tween = create_tween()
	tween.tween_property(color_rect, "color:a", 0.0, duration)
	return tween

## Flash effect (quick bright flash)
func flash(flash_color: Color = Color.WHITE, duration: float = 0.15):
	var flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = flash_color
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_rect)

	var tween = create_tween()
	tween.tween_property(flash_rect, "color:a", 0.0, duration)
	tween.tween_callback(flash_rect.queue_free)

## Crossfade transition (fade out old, fade in new simultaneously)
func crossfade_to_scene(scene_path: String, duration: float = 0.5):
	if is_transitioning:
		return

	is_transitioning = true
	transition_started.emit()

	# Quick fade to black
	var tween = create_tween()
	color_rect.color = Color(0, 0, 0, 0)
	tween.tween_property(color_rect, "color:a", 1.0, duration * 0.4)
	await tween.finished

	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame

	# Fade in
	tween = create_tween()
	tween.tween_property(color_rect, "color:a", 0.0, duration * 0.6)
	await tween.finished

	is_transitioning = false
	transition_finished.emit()
