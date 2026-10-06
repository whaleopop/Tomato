## A row of small portraits (heroes in what they wear, or guns) to pick from: the shop's "choose a
## hero / gun" strip, the character select under its stage. Wraps onto more rows when narrow.
## Pictures come from ItemRenderer (cropped to the face / the gun). Navy chips like the main menu's
## rows: gold rim on hover, a gold ring on the chosen one. `dim` greys out entries (heroes we don't
## own, with a little padlock) but they stay clickable.
extends HFlowContainer
class_name HeroChips

signal chosen(index: int)

var chip_size: float = 66.0
var _buttons: Array[Button] = []
var _colors: Array[Color] = []
var _dim: Array[bool] = []
var _selected: int = -1

func _init():
	alignment = FlowContainer.ALIGNMENT_CENTER
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 8)

## Portraits of these heroes wearing what they have on
func show_heroes(roster: Array, dim: Array = []) -> void:
	_clear()
	var renderer = ItemRenderer.get_instance(get_tree())
	for i in roster.size():
		var hero_name: String = roster[i].character_name
		var wear = PlayerProfile.equipped_for(hero_name)
		var chip = _add_chip(i, tr(hero_name), roster[i].color, i < dim.size() and dim[i])
		renderer.hero(hero_name, wear.skin, wear.hat, _icon_to(chip, false))
	_mark()

## Pictures of every gun (plain finish)
func show_guns() -> void:
	_clear()
	var renderer = ItemRenderer.get_instance(get_tree())
	for i in RangedWeapon.WeaponType.size():
		var chip = _add_chip(i, tr(RangedWeapon.create_weapon(i).item_name), UITheme.ACCENT_PRIMARY, false)
		renderer.weapon(i, "default", _icon_to(chip, true))
	_mark()

## The picture's callback for `chip`, holding it only weakly: the strip is rebuilt (a purchase, an
## equip) before the pictures come, and a lambda holding a freed chip printed "Lambda capture ... was freed"
func _icon_to(chip: Button, gun: bool) -> Callable:
	var ref = weakref(chip)
	return func(tex):
		var c = ref.get_ref()
		if c:
			c.icon = _crop(tex, gun)

func select(index: int) -> void:
	_selected = index
	_mark()

func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_buttons.clear()
	_colors.clear()
	_dim.clear()

func _add_chip(index: int, tip: String, color: Color, dim: bool) -> Button:
	var chip = Button.new()
	chip.custom_minimum_size = Vector2(chip_size, chip_size)
	chip.focus_mode = Control.FOCUS_NONE
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.expand_icon = true
	chip.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_theme_constant_override("icon_max_width", int(chip_size - 8))
	chip.tooltip_text = tip
	UITheme.add_hover_animation(chip, 1.1)
	chip.pressed.connect(func(): chosen.emit(index))
	add_child(chip)
	if dim:
		# Not ours yet: a padlock in the corner (stays bright while the chip is greyed)
		var lock = LockBadge.new()
		lock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		lock.offset_left = -20
		lock.offset_top = 2
		lock.offset_right = -2
		lock.offset_bottom = 20
		chip.add_child(lock)
	_buttons.append(chip)
	_colors.append(color)
	_dim.append(dim)
	return chip

func _mark() -> void:
	for i in _buttons.size():
		var on = i == _selected
		var chip = _buttons[i]
		var normal: StyleBoxFlat
		var hover: StyleBoxFlat
		if on:
			normal = UITheme.navy_box(Color(0.16, 0.15, 0.12, 0.96), UITheme.GOLD, 14, 4, 4)
			normal.set_border_width_all(3)
			normal.shadow_color = Color(UITheme.GOLD, 0.35)
			normal.shadow_size = 8
			hover = normal
		else:
			normal = UITheme.navy_box(UITheme.NAVY, Color(1, 1, 1, 0.1), 14, 4, 4)
			hover = UITheme.navy_box(UITheme.NAVY_HOVER, Color(UITheme.GOLD, 0.8), 14, 4, 4)
			hover.set_border_width_all(2)
		for state in ["normal", "pressed"]:
			chip.add_theme_stylebox_override(state, normal)
		for state in ["hover", "hover_pressed"]:
			chip.add_theme_stylebox_override(state, hover)
		chip.modulate = Color.WHITE
		if on:
			chip.self_modulate = Color.WHITE
		elif _dim[i]:
			chip.self_modulate = Color(0.5, 0.5, 0.58, 0.75)  # not ours yet
		else:
			chip.self_modulate = Color(1, 1, 1, 0.9)

## The middle of a card picture (the hero's face / the gun), so the small chips show it big
static func _crop(tex: Texture2D, gun: bool) -> Texture2D:
	if tex == null:
		return null
	var size = Vector2(tex.get_size())
	var part = 0.7 if gun else 0.5
	var atlas = AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(size.x * (0.5 - part / 2.0), size.y * (0.47 if gun else 0.42) - size.y * part / 2.0, size.x * part, size.y * part)
	return atlas

## A tiny drawn padlock on a navy disc (no glyph a font might lack)
class LockBadge extends Control:
	func _init():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw():
		var c = size / 2.0
		var r = minf(size.x, size.y) / 2.0
		draw_circle(c, r, Color(0.04, 0.055, 0.1, 0.92))
		draw_arc(c, r - 0.5, 0, TAU, 20, Color(UITheme.GOLD, 0.7), 1.0, true)
		var w = r * 0.95
		var body = Rect2(c.x - w / 2.0, c.y - r * 0.12, w, r * 0.72)
		draw_arc(Vector2(c.x, body.position.y), w * 0.32, PI, TAU, 10, UITheme.GOLD, 1.6, true)
		draw_rect(body, UITheme.GOLD)
