## Singleton for smooth scene transitions with fade effects
## Autoload: SceneTransition
extends CanvasLayer

signal transition_started
signal transition_finished

const DEFAULT_FADE_COLOR := Color(0.03, 0.04, 0.08)

var color_rect: ColorRect = null
var is_transitioning: bool = false

# Scene that the running transition will switch to. A request that arrives
# while fading out simply retargets it; one that arrives while fading in is
# queued and started right after. Nothing is ever silently dropped.
var _target_scene: String = ""
var _queued_scene: String = ""
var _scene_changed: bool = false

func _ready():
	layer = 100  # Above everything
	process_mode = Node.PROCESS_MODE_ALWAYS  # Work even when paused
	# Glass theme for every Control in the game
	get_tree().root.theme = UITheme.get_theme()
	GameSettings.load_and_apply()
	_create_overlay()

func _create_overlay():
	color_rect = ColorRect.new()
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.color = Color(DEFAULT_FADE_COLOR, 0.0)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(color_rect)

## Fade out, change scene, fade back in
func fade_to_scene(scene_path: String, duration: float = 0.4, fade_color: Color = DEFAULT_FADE_COLOR):
	if is_transitioning:
		if _scene_changed:
			_queued_scene = scene_path
		else:
			_target_scene = scene_path
		return

	is_transitioning = true
	_scene_changed = false
	_target_scene = scene_path
	transition_started.emit()

	# Block clicks while the screen is covered
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	color_rect.color = Color(fade_color, color_rect.color.a)

	var tween = create_tween()
	tween.tween_property(color_rect, "color:a", 1.0, duration)
	await tween.finished

	var err = get_tree().change_scene_to_file(_target_scene)
	if err != OK:
		push_error("[SceneTransition] Failed to change scene to %s (error %d)" % [_target_scene, err])
	_scene_changed = true

	# Wait a frame for the new scene to enter the tree
	await get_tree().process_frame

	tween = create_tween()
	tween.tween_property(color_rect, "color:a", 0.0, duration)
	await tween.finished

	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false
	_scene_changed = false
	transition_finished.emit()

	if _queued_scene != "":
		var next_scene = _queued_scene
		_queued_scene = ""
		if next_scene != _target_scene or get_tree().current_scene == null or get_tree().current_scene.scene_file_path != next_scene:
			fade_to_scene(next_scene, duration, fade_color)

## Just fade out (useful for custom transitions)
func fade_out(duration: float = 0.3, fade_color: Color = DEFAULT_FADE_COLOR) -> Tween:
	color_rect.color = Color(fade_color, 0.0)
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

## Crossfade transition (kept for compatibility, same queueing rules as fade_to_scene)
func crossfade_to_scene(scene_path: String, duration: float = 0.5):
	fade_to_scene(scene_path, duration * 0.5)
