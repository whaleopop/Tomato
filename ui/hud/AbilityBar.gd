## Ability bar UI component with cooldown visualization and pulse effects
extends Control
class_name AbilityBar

var ability_component: AbilityComponent = null
var ability_buttons: Array[Button] = []
var cooldown_overlays: Array[ColorRect] = []
var cooldown_labels: Array[Label] = []
var pulse_timers: Array[float] = []

const BUTTON_SIZE: Vector2 = Vector2(80, 80)
const BUTTON_SPACING: float = 10.0

func _ready():
	pass

func setup(p_ability_component: AbilityComponent):
	ability_component = p_ability_component

	if ability_component:
		ability_component.ability_activated.connect(_on_ability_activated)
		ability_component.ability_cooldown_finished.connect(_on_cooldown_finished)
		_update_abilities()

func _process(delta: float):
	_update_cooldown_display(delta)
	_update_pulse_effects(delta)

func _update_abilities():
	# Clear existing buttons
	for button in ability_buttons:
		button.queue_free()
	ability_buttons.clear()
	cooldown_overlays.clear()
	cooldown_labels.clear()
	pulse_timers.clear()

	if not ability_component:
		return

	# Create buttons for each active ability
	for i in range(ability_component.active_abilities.size()):
		var ability = ability_component.active_abilities[i]

		# Container for button and overlay
		var container = Control.new()
		container.custom_minimum_size = BUTTON_SIZE
		container.position = Vector2(i * (BUTTON_SIZE.x + BUTTON_SPACING), 0)
		add_child(container)

		# Main button
		var button = Button.new()
		button.text = ability.ability_name
		button.custom_minimum_size = BUTTON_SIZE
		button.size = BUTTON_SIZE
		container.add_child(button)
		ability_buttons.append(button)

		# Cooldown overlay (fills from bottom to top)
		var overlay = ColorRect.new()
		overlay.color = Color(0, 0, 0, 0.7)
		overlay.size = BUTTON_SIZE
		overlay.position = Vector2.ZERO
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(overlay)
		cooldown_overlays.append(overlay)

		# Cooldown text label
		var label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = BUTTON_SIZE
		label.position = Vector2.ZERO
		label.add_theme_font_size_override("font_size", 20)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(label)
		cooldown_labels.append(label)

		# Initialize pulse timer
		pulse_timers.append(0.0)

		# Hotkey hint
		var hotkey = Label.new()
		hotkey.text = str(i + 1)
		hotkey.position = Vector2(5, 5)
		hotkey.add_theme_font_size_override("font_size", 14)
		hotkey.add_theme_color_override("font_color", Color(1, 1, 0.7))
		container.add_child(hotkey)

		# Connect button
		button.pressed.connect(_on_ability_button_pressed.bind(i))

func _update_cooldown_display(_delta: float):
	if not ability_component:
		return

	for i in range(ability_component.active_abilities.size()):
		if i >= cooldown_overlays.size():
			continue

		var ability = ability_component.active_abilities[i]
		var overlay = cooldown_overlays[i]
		var label = cooldown_labels[i]

		if ability.is_ready():
			# Ability ready - hide overlay
			overlay.visible = false
			label.text = ""
		else:
			# On cooldown - show overlay
			overlay.visible = true
			var cooldown_ratio = ability.get_cooldown_remaining() / ability.cooldown

			# Overlay shrinks from top as cooldown progresses
			var overlay_height = BUTTON_SIZE.y * cooldown_ratio
			overlay.size.y = overlay_height
			overlay.position.y = 0

			# Show remaining time
			var remaining = ability.get_cooldown_remaining()
			if remaining > 1.0:
				label.text = "%d" % ceil(remaining)
			else:
				label.text = "%.1f" % remaining

func _update_pulse_effects(delta: float):
	if not ability_component:
		return

	for i in range(ability_component.active_abilities.size()):
		if i >= ability_buttons.size():
			continue

		var ability = ability_component.active_abilities[i]
		var button = ability_buttons[i]

		if ability.is_ready():
			# Pulse effect when ready
			pulse_timers[i] += delta * 3.0
			var pulse = (sin(pulse_timers[i]) + 1.0) * 0.5
			button.modulate = Color(1.0 + pulse * 0.3, 1.0 + pulse * 0.3, 1.0)

			# Glow border effect
			if pulse_timers[i] < 0.1:
				# Just became ready - flash effect
				button.modulate = Color(1.5, 1.5, 1.2)
		else:
			# On cooldown - dimmed
			pulse_timers[i] = 0.0
			button.modulate = Color(0.6, 0.6, 0.6)

func _on_ability_button_pressed(index: int):
	if ability_component:
		# Get mouse position in world
		var camera = get_viewport().get_camera_3d()
		if camera:
			var mouse_pos = get_viewport().get_mouse_position()
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 1000.0

			# Get world_3d from viewport (Control doesn't have get_world_3d())
			var world_3d = get_viewport().world_3d
			if not world_3d:
				return

			var space_state = world_3d.direct_space_state
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			var result = space_state.intersect_ray(query)

			var target_pos = Vector3.ZERO
			if result:
				target_pos = result.position

			ability_component.activate_ability(index, target_pos)

func _on_ability_activated(_ability: ActiveAbility):
	# Reset pulse timer for visual feedback
	for i in range(pulse_timers.size()):
		if i < ability_component.active_abilities.size():
			if ability_component.active_abilities[i] == _ability:
				pulse_timers[i] = 0.0
				break

func _on_cooldown_finished(ability: ActiveAbility):
	# Flash effect when ability becomes ready
	for i in range(ability_component.active_abilities.size()):
		if ability_component.active_abilities[i] == ability:
			if i < ability_buttons.size():
				var button = ability_buttons[i]
				var tween = create_tween()
				tween.tween_property(button, "modulate", Color(1.8, 1.8, 1.5), 0.1)
				tween.tween_property(button, "modulate", Color.WHITE, 0.2)
			break
