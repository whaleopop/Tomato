## Ability bar (bottom-center): glass slots with key hint and a radial cooldown sweep
extends HBoxContainer
class_name AbilityBar

const SLOT_SIZE: Vector2 = Vector2(76, 76)

var ability_component: AbilityComponent = null
var slots: Array[AbilitySlot] = []

func _ready():
	add_theme_constant_override("separation", 12)
	alignment = BoxContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(p_ability_component: AbilityComponent):
	ability_component = p_ability_component
	if ability_component:
		ability_component.ability_cooldown_finished.connect(_on_cooldown_finished)
		_rebuild()

func _rebuild():
	for slot in slots:
		slot.queue_free()
	slots.clear()
	if not ability_component:
		return

	for i in ability_component.active_abilities.size():
		var slot = AbilitySlot.new()
		slot.ability = ability_component.active_abilities[i]
		slot.component = ability_component
		slot.key_text = _key_for_action("ability_%d" % (i + 1))
		slot.custom_minimum_size = SLOT_SIZE
		add_child(slot)
		slots.append(slot)

func _key_for_action(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			return OS.get_keycode_string(code)
	return "?"

func _on_cooldown_finished(ability: ActiveAbility):
	for slot in slots:
		if slot.ability == ability:
			slot.flash()

## One ability button
class AbilitySlot extends Control:
	var ability: ActiveAbility = null
	var component: AbilityComponent = null
	var key_text: String = ""
	var _flash: float = 0.0
	var _pulse: float = 0.0

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		tooltip_text = ability.ability_name if ability else ""

	func flash():
		_flash = 1.0

	func _process(delta: float):
		_flash = max(0.0, _flash - delta * 2.5)
		_pulse += delta * 2.0
		queue_redraw()

	func _draw():
		var rect = Rect2(Vector2.ZERO, size)
		var remaining: float = component.get_ability_cooldown(ability) if component and ability else 0.0
		var is_ready_now = remaining <= 0.0
		var accent = UITheme.ACCENT_SECONDARY

		var fill = Color(1, 1, 1, 0.08) if is_ready_now else Color(0, 0, 0, 0.35)
		var rim = Color(accent, 0.55 + 0.25 * sin(_pulse)) if is_ready_now else Color(1, 1, 1, 0.12)
		var box = UITheme.glass_box(fill, rim, 18, 0, 0)
		if is_ready_now:
			box.shadow_color = Color(accent, 0.25 + 0.5 * _flash)
			box.shadow_size = 8 + int(10 * _flash)
		draw_style_box(box, rect)

		var center = size / 2.0
		var font = UITheme.font_black()

		# Ability initial as the "icon"
		var initial = tr(ability.ability_name).substr(0, 1).to_upper() if ability else "?"
		var icon_color = Color.WHITE if is_ready_now else Color(1, 1, 1, 0.35)
		var icon_size = 30
		var text_w = font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_size).x
		draw_string(font, Vector2(center.x - text_w / 2.0, center.y + icon_size * 0.35), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_size, icon_color)

		if not is_ready_now and ability and ability.cooldown > 0:
			var ratio = clamp(remaining / ability.cooldown, 0.0, 1.0)
			# Radial sweep of the remaining cooldown
			var radius = min(size.x, size.y) * 0.36
			draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * ratio, 40, Color(accent, 0.9), 4.0, true)
			var label = ("%d" % ceil(remaining)) if remaining > 1.0 else ("%.1f" % remaining)
			var w = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, Vector2(center.x - w / 2.0, size.y - 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

		# Key hint chip
		var chip = Rect2(Vector2(6, 6), Vector2(22, 20))
		draw_style_box(UITheme.glass_box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.2), 6, 0, 0), chip)
		var kw = font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, Vector2(chip.position.x + (chip.size.x - kw) / 2.0, chip.position.y + 15), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))
