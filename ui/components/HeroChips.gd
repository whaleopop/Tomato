## A row of small portraits (heroes in what they wear, or guns) to pick from: the shop's "choose a
## hero / gun" strip, the character select above its stage. Wraps onto more rows when narrow.
## Pictures come from ItemRenderer (cropped to the face / the gun). `dim` greys out entries
## (heroes we don't own) but they stay clickable.
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
		renderer.hero(hero_name, wear.skin, wear.hat, func(tex): if is_instance_valid(chip): chip.icon = _crop(tex, false))
	_mark()

## Pictures of every gun (plain finish)
func show_guns() -> void:
	_clear()
	var renderer = ItemRenderer.get_instance(get_tree())
	for i in RangedWeapon.WeaponType.size():
		var chip = _add_chip(i, tr(RangedWeapon.create_weapon(i).item_name), UITheme.ACCENT_PRIMARY, false)
		renderer.weapon(i, "default", func(tex): if is_instance_valid(chip): chip.icon = _crop(tex, true))
	_mark()

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
	chip.add_theme_constant_override("icon_max_width", int(chip_size - 6))
	chip.tooltip_text = tip
	UITheme.add_hover_animation(chip, 1.1)
	chip.pressed.connect(func(): chosen.emit(index))
	add_child(chip)
	_buttons.append(chip)
	_colors.append(color)
	_dim.append(dim)
	return chip

func _mark() -> void:
	for i in _buttons.size():
		var on = i == _selected
		var accent = _colors[i]
		var box = UITheme.glass_box(Color(accent, 0.3 if on else 0.06), Color(accent.lightened(0.3), 1.0) if on else Color(1, 1, 1, 0.12), 14, 4, 4)
		box.set_border_width_all(3 if on else 1)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			_buttons[i].add_theme_stylebox_override(state, box)
		if on:
			_buttons[i].modulate = Color.WHITE
		elif _dim[i]:
			_buttons[i].modulate = Color(0.55, 0.55, 0.62, 0.7)  # not ours yet
		else:
			_buttons[i].modulate = Color(1, 1, 1, 0.8)

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
