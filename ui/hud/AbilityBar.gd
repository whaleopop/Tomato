## Ability bar (bottom-center): quiet glass slots with an icon, a dark pie cooldown sweep,
## seconds, a key chip, one punch when ready - plus a small chip for the passive
extends HBoxContainer
class_name AbilityBar

const SLOT_SIZE: Vector2 = Vector2(72, 72)
const PASSIVE_SIZE: Vector2 = Vector2(44, 44)

var ability_component: AbilityComponent = null
var slots: Array[AbilitySlot] = []
var passive_chips: Array[PassiveChip] = []

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
	for chip in passive_chips:
		chip.queue_free()
	passive_chips.clear()
	if not ability_component:
		return

	for i in ability_component.active_abilities.size():
		var slot = AbilitySlot.new()
		slot.ability = ability_component.active_abilities[i]
		slot.component = ability_component
		slot.key_action = "ability_%d" % (i + 1)
		slot.key_text = Keybinds.label(slot.key_action)
		slot.custom_minimum_size = SLOT_SIZE
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(slot)
		slots.append(slot)

	for passive in ability_component.passive_abilities:
		var chip = PassiveChip.new()
		chip.ability = passive
		chip.custom_minimum_size = PASSIVE_SIZE
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(chip)
		passive_chips.append(chip)

func _on_cooldown_finished(ability: ActiveAbility):
	for slot in slots:
		if slot.ability == ability:
			slot.flash()

## The ability's icon (UITheme.icon) or null when it has none
static func _icon_of(ability: Ability) -> Texture2D:
	return UITheme.icon(ability.icon) if ability and ability.icon != "" else null

## Dark, mostly opaque tile with a thin light border so the world doesn't bleed through
static func _backing(border: Color) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.14, 0.85)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_corner_radius_all(UITheme.CORNER_RADIUS_SMALL)
	return sb

## Centered icon, or the first letter of the name when there is no icon
static func _draw_glyph(ci: Control, ability: Ability, px: float, color: Color):
	var center = ci.size / 2.0
	var tex = _icon_of(ability)
	if tex:
		var r = Rect2(center - Vector2(px, px) / 2.0, Vector2(px, px))
		ci.draw_texture_rect(tex, Rect2(r.position + Vector2(0, 1.5), r.size), false, Color(0, 0, 0, 0.55 * color.a))
		ci.draw_texture_rect(tex, r, false, color)
		return
	var font = UITheme.font_black()
	var initial = ci.tr(ability.ability_name).substr(0, 1).to_upper() if ability else "?"
	var fs = int(px * 0.9)
	var w = font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, Vector2(center.x - w / 2.0, center.y + fs * 0.35), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

## One ability button
class AbilitySlot extends Control:
	var ability: ActiveAbility = null
	var component: AbilityComponent = null
	var key_text: String = ""
	var key_action: String = ""  # rebinding in the pause menu shows up here (Keybinds)
	var _tween: Tween = null

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot_offset = size / 2.0
		tooltip_text = tr(ability.ability_name) if ability else ""

	func _notification(what: int):
		if what == NOTIFICATION_RESIZED:
			pivot_offset = size / 2.0

	## One quick punch when the ability is ready again
	func flash():
		if _tween:
			_tween.kill()
		scale = Vector2.ONE
		_tween = create_tween()
		_tween.tween_property(self, "scale", Vector2(1.14, 1.14), 0.06).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "scale", Vector2.ONE, 0.10).set_ease(Tween.EASE_IN)

	func _process(_delta: float):
		queue_redraw()

	func _draw():
		if key_action != "":
			key_text = Keybinds.label(key_action)
		var rect = Rect2(Vector2.ZERO, size)
		var remaining: float = component.get_ability_cooldown(ability) if component and ability else 0.0
		var is_ready_now = remaining <= 0.0

		var rim = Color(1, 1, 1, 0.55) if is_ready_now else Color(1, 1, 1, 0.3)
		draw_style_box(AbilityBar._backing(rim), rect)

		AbilityBar._draw_glyph(self, ability, 38.0, Color.WHITE if is_ready_now else Color(1, 1, 1, 0.55))

		var font = UITheme.font_black()
		if not is_ready_now and ability and ability.cooldown > 0:
			var ratio = clampf(remaining / ability.cooldown, 0.0, 1.0)
			# Dark pie over the part of the cooldown that is left, clockwise from the top
			var inner = rect.grow(-3.0)
			var half = inner.size / 2.0
			var c = rect.get_center()
			var a0 = -PI / 2.0 + TAU * (1.0 - ratio)
			var pts = PackedVector2Array([c])
			var steps = maxi(2, int(48 * ratio))
			for s in steps + 1:
				var a = a0 + TAU * ratio * float(s) / float(steps)
				var d = Vector2(cos(a), sin(a))
				var k = 1.0 / maxf(absf(d.x) / half.x, absf(d.y) / half.y)
				pts.append(c + d * k)
			draw_colored_polygon(pts, Color(0, 0, 0, 0.62))
			var label = ("%d" % ceil(remaining)) if remaining > 1.0 else ("%.1f" % remaining)
			var fs = UITheme.FONT_HEADING
			var w = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(c.x - w / 2.0, c.y + fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

		# Key hint chip
		var chip = Rect2(Vector2(5, 5), Vector2(22, 20))
		draw_style_box(UITheme.glass_box(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.2), 6, 0, 0), chip)
		var kw = font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, Vector2(chip.position.x + (chip.size.x - kw) / 2.0, chip.position.y + 15), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))

## The passive: a small chip with its icon; the tooltip names and explains it
class PassiveChip extends Control:
	var ability: PassiveAbility = null

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_STOP
		if ability:
			var t = tr(ability.ability_name)
			if ability.description != "":
				t += "\n" + tr(ability.description)
			tooltip_text = t

	func _draw():
		draw_style_box(AbilityBar._backing(Color(1, 1, 1, 0.3)), Rect2(Vector2.ZERO, size))
		AbilityBar._draw_glyph(self, ability, 24.0, Color(1, 1, 1, 0.85))
