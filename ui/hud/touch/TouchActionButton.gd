## One on-screen touch button driving an InputMap action (press/release), with an optional
## ability icon + cooldown sweep drawn the same way AbilityBar's slots do.
extends Control
class_name TouchActionButton

@export var action: StringName = &""
@export var drag_aim: bool = false  # dragging from the button reports an aim direction instead of firing in place
@export var radius: float = 38.0    # visual + touch radius (min touch target is 76 virtual units across)

var ability: Ability = null          # optional: feeds the cooldown sweep / icon
var ability_component: AbilityComponent = null

signal drag_direction_changed(dir: Vector2)  # only emitted when drag_aim is true
signal tapped  # touch released while still inside the button (for buttons with no InputMap action)

var _pressed: bool = false
var _touch_index: int = -1
var _press_pos: Vector2 = Vector2.ZERO
var _sb_normal: StyleBoxFlat = null
var _sb_pressed: StyleBoxFlat = null

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = size / 2.0
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	_rebuild_styleboxes()
	# TouchControls.setup() assigns `ability` after _ready() (buttons are built before the player
	# is known), so this can't gate on `ability` yet; _process itself only redraws when one is
	# actually set, which still kills the per-frame StyleBox allocation (bug 8) for the ~7 of 11
	# buttons that never have one.
	set_process(true)

func _notification(what: int):
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size / 2.0
		_sb_normal = null  # corner radius depends on size: rebuilt lazily in _draw

func _process(_delta: float) -> void:
	if ability:
		queue_redraw()  # the cooldown sweep ticks down even while idle

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1 and get_global_rect().has_point(event.position):
				_touch_index = event.index
				_press_pos = event.position
				_set_pressed(true)
				get_viewport().set_input_as_handled()
		else:
			if event.index == _touch_index:
				_touch_index = -1
				var was_inside = get_global_rect().has_point(event.position)
				_set_pressed(false)
				if was_inside:
					tapped.emit()
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			if not get_global_rect().has_point(event.position) and not drag_aim:
				# Dragged off a plain button: release it (standard touch-button behavior)
				_touch_index = -1
				_set_pressed(false)
			elif drag_aim:
				emit_signal("drag_direction_changed", event.position - _press_pos)

func _set_pressed(on: bool) -> void:
	if _pressed == on or action == &"":
		return
	_pressed = on
	# A parsed InputEventAction updates the Input singleton's own polled state too (Godot routes
	# it there), so is_action_pressed/is_action_just_pressed and _unhandled_input/_input handlers
	# (PauseMenu, InventoryMenu) both see it from one call - action_press/release alone never
	# produced an InputEvent, so event-based consumers saw nothing (bug 3).
	var ev = InputEventAction.new()
	ev.action = action
	ev.pressed = on
	Input.parse_input_event(ev)
	queue_redraw()

func _rebuild_styleboxes() -> void:
	var opacity = clampf(GameSettings.touch_opacity, 0.0, 1.0)
	_sb_normal = StyleBoxFlat.new()
	_sb_normal.bg_color = Color(0.05, 0.07, 0.14, 0.75 * 0.6 * opacity)
	_sb_normal.set_border_width_all(1)
	_sb_normal.border_color = Color(1, 1, 1, 0.6 * 0.6 * opacity)
	_sb_normal.set_corner_radius_all(int(min(size.x, size.y) / 2.0))
	_sb_pressed = StyleBoxFlat.new()
	_sb_pressed.bg_color = Color(0.05, 0.07, 0.14, 0.75 * 0.9 * opacity)
	_sb_pressed.set_border_width_all(1)
	_sb_pressed.border_color = Color(1, 1, 1, 0.9 * 0.6 * opacity)
	_sb_pressed.set_corner_radius_all(int(min(size.x, size.y) / 2.0))

func _draw() -> void:
	if not visible:
		return
	if _sb_normal == null:
		_rebuild_styleboxes()
	var rect = Rect2(Vector2.ZERO, size)
	var opacity = clampf(GameSettings.touch_opacity, 0.0, 1.0)
	var alpha = 0.9 if _pressed else 0.6
	var s = Vector2(0.92, 0.92) if _pressed else Vector2.ONE
	var sb = _sb_pressed if _pressed else _sb_normal
	var drawn_rect = Rect2(rect.get_center() - rect.size * s / 2.0, rect.size * s)
	draw_style_box(sb, drawn_rect)

	if ability:
		var color = Color(1, 1, 1, alpha * opacity)
		var remaining = ability_component.get_ability_cooldown(ability) if ability_component else 0.0
		if remaining > 0.0:
			color.a = 0.4
		AbilityBar._draw_glyph(self, ability, radius * 0.9, color)
		if remaining > 0.0 and ability.cooldown > 0:
			var ratio = clampf(remaining / ability.cooldown, 0.0, 1.0)
			var inner = rect.grow(-3.0)
			var half = inner.size / 2.0
			var c = rect.get_center()
			var a0 = -PI / 2.0 + TAU * (1.0 - ratio)
			var pts = PackedVector2Array([c])
			var steps = 24
			for i in steps + 1:
				var a = -PI / 2.0 + TAU * (float(i) / steps) * (1.0 - ratio)
				pts.append(c + Vector2(cos(a), sin(a)) * half)
			pts.append(c)
			draw_colored_polygon(pts, Color(0, 0, 0, 0.5))
