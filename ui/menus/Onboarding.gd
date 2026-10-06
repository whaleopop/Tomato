## First start: make a profile (a nickname - local, there are no online accounts yet) and pick
## any PlayerProfile.STARTER_PICKS heroes from the whole roster, shown as cards. The rest are bought
## in the shop with coins from matches. Shown by the main menu until both are done.
## The main menu's look: the shared top bar (no back - there is nowhere to go yet; the gear sets
## the language first), the living garden behind, navy cards, gold for the call to action.
## Picking: click a card, or drag it onto one of the golden slots; the hero you touched last stands
## in a big interactive 3D showcase on the left (drag to turn, wheel to zoom).
extends Control
class_name Onboarding

signal finished

const SIDE: int = 56                # the main menu's column margin
const GAP: int = 24

var _center: CenterContainer
var _content: Control              # the step on screen (register card or the hero picker)
var _name_edit: LineEdit
var _error: Label
var _header: ScreenHeader

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("blocks_game_input")
	UITheme.create_background(self, true)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.offset_top = ScreenHeader.CONTENT_TOP - 20
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_header = ScreenHeader.make(self, "NEW PROFILE", "First start", false)
	_header.add_settings_chip(true)
	if not PlayerProfile.has_account():
		_show_register()
	else:
		_show_starters()

func _clear():
	for child in _center.get_children():
		child.queue_free()
	if _content and is_instance_valid(_content) and _content.get_parent() == self:
		_content.queue_free()
	_content = null

## A big title with the gold kicker over it, centred or left-aligned
func _title(text: String, kicker: String, parent: Control, size: int, centred: bool) -> Label:
	var box = UITheme.create_screen_title(text, kicker, parent)
	var label: Label = box.get_child(box.get_child_count() - 1)
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centred:
		for l in box.get_children():
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

## A muted line under a title
func _sub(text: String, parent: Control, centred: bool) -> Label:
	var sub = UITheme.create_label(text, parent, UITheme.FONT_NORMAL)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	sub.add_theme_constant_override("shadow_offset_y", 1)
	if centred:
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return sub

# ---------------------------------------------------------------- nickname

func _show_register():
	_clear()
	var card = UITheme.navy_panel(_center, 30)
	card.custom_minimum_size.x = 600
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)
	_title("WELCOME TO ROYALTIM", "First start", box, 34, true)
	_sub("Pick a name: everyone in the match will see it", box, true)
	UITheme.create_spacer(false, box).custom_minimum_size.y = 2
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("Your name")
	_name_edit.max_length = PlayerProfile.NAME_MAX
	_name_edit.custom_minimum_size.y = 58
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.add_theme_font_override("font", UITheme.font_black())
	_name_edit.add_theme_font_size_override("font_size", 24)
	var normal = UITheme.navy_box(Color(0.02, 0.03, 0.06, 0.92), Color(1, 1, 1, 0.14), 12, 16, 6)
	normal.shadow_size = 0
	_name_edit.add_theme_stylebox_override("normal", normal)
	var focus = StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(12)
	focus.set_border_width_all(2)
	focus.border_color = UITheme.GOLD
	focus.anti_aliasing = true
	_name_edit.add_theme_stylebox_override("focus", focus)
	_name_edit.add_theme_color_override("caret_color", UITheme.GOLD)
	_name_edit.add_theme_color_override("selection_color", Color(UITheme.GOLD, 0.35))
	_name_edit.add_theme_color_override("font_placeholder_color", UITheme.TEXT_MUTED)
	box.add_child(_name_edit)
	_name_edit.text_submitted.connect(func(_t): _register())
	_error = UITheme.create_label("", box, UITheme.FONT_SMALL)
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.add_theme_font_override("font", UITheme.font_bold())
	_error.add_theme_color_override("font_color", UITheme.ACCENT_DANGER)
	var go = UITheme.create_play_button("CREATE PROFILE", "Next: your first heroes", box)
	go.pressed.connect(_register)
	var note = UITheme.create_label("The profile lives on this computer: coins, heroes and cosmetics are saved here.", box, UITheme.FONT_TINY)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_name_edit.grab_focus.call_deferred()

func _register():
	var problem = PlayerProfile.check_name(_name_edit.text)
	if problem != "":
		_error.text = tr(problem)
		return
	PlayerProfile.register(_name_edit.text)
	_header.update_coins()
	_show_starters()

# ---------------------------------------------------------------- the first heroes

var _picked: Array = []            # hero names, in the order they were clicked
var _cards: Dictionary = {}        # hero -> ParallaxCard
var _count_label: Label
var _info_label: Label
var _take: Button
var _showcase: CharacterShowcase
var _shown: String = ""            # the hero in the showcase
var _hero_name: Label
var _hero_stats: Label
var _slots: Array = []             # DropPad per pick
var _pending: String = ""          # the card pressed, picked when the button comes up on it

func _show_starters():
	if not PlayerProfile.needs_starter():
		_done()
		return
	_build_starters()

## The hero picker itself (tests show it without a fresh profile)
func _build_starters():
	_clear()
	_header.set_title("PICK YOUR HEROES", "First start")
	var screen = get_viewport_rect().size
	var avail_h = screen.y - ScreenHeader.CONTENT_TOP - 24.0
	var show_w = clampf(screen.x * 0.3, 340.0, 540.0)
	var right_w = screen.x - SIDE * 2 - show_w - GAP

	var root = HBoxContainer.new()
	root.add_theme_constant_override("separation", GAP)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = SIDE
	root.offset_right = -SIDE
	root.offset_top = ScreenHeader.CONTENT_TOP
	root.offset_bottom = -24
	add_child(root)
	_content = root

	# Left: the hero you touched last, big and turnable, its abilities under it
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = show_w
	left.add_theme_constant_override("separation", 12)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	var stage = UITheme.navy_panel(left, 0)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stage_box = stage.get_theme_stylebox("panel").duplicate()
	stage_box.bg_color = Color(0.045, 0.06, 0.11, 0.55)
	stage.add_theme_stylebox_override("panel", stage_box)
	_showcase = CharacterShowcase.new()
	_showcase.interactive = true
	_showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(_showcase)
	# Dropping a card on the hero picks it too
	_showcase.set_drag_forwarding(Callable(), _can_drop_hero, func(_at, data): _drop_hero(data, -1))
	var hint = UITheme.create_label("Drag to turn  ·  wheel to zoom  ·  double click to reset", stage, 11)
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info = UITheme.navy_panel(left, 18)
	var info_box = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 4)
	info.add_child(info_box)
	_hero_name = UITheme.create_heading("", info_box)
	_hero_name.uppercase = true
	_hero_name.add_theme_font_override("font", UITheme.font_black())
	_hero_name.add_theme_font_size_override("font_size", 24)
	_hero_stats = UITheme.create_label("", info_box, 12)
	_hero_stats.uppercase = true
	_hero_stats.add_theme_font_override("font", UITheme.font_black())
	_hero_stats.add_theme_color_override("font_color", UITheme.GOLD)
	_info_label = UITheme.create_label("", info_box, UITheme.FONT_SMALL)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size.y = 58
	_info_label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	# Right: the title, every hero as a card, the slots and the gold button
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 16)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(right)
	_title(tr("%s, pick %d heroes") % [PlayerProfile.nickname, PlayerProfile.STARTER_PICKS], "Free starter heroes", right, 34, false)
	_sub("They are yours for free. The rest can be bought in the shop with coins from matches", right, false)

	var heroes = CharacterRegistry.get_all()
	var columns = 7
	var rows = int(ceil(heroes.size() / float(columns)))
	var card_w = floorf((right_w - (columns - 1) * 10.0) / columns)
	# Never taller than the screen leaves for the grid (title, slots and button take ~330 px)
	var card_h = minf(card_w * 1.39, (avail_h - 330.0 - (rows - 1) * 10.0) / rows)
	card_w = minf(card_w, floorf(card_h / 1.39))
	var grid = GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	right.add_child(grid)
	var renderer = ItemRenderer.get_instance(get_tree())
	for data in heroes:
		var hero = data.character_name
		var card = ParallaxCard.new()
		card.card_size = Vector2(card_w, floorf(card_w * 1.39))
		card.title = hero
		card.subtitle = tr("%d HP  ·  speed %.1f") % [int(data.base_health), data.base_speed]
		card.accent = data.color
		card.live = ["hero", [hero, "classic", "no_hat"]]
		card.drag_payload = hero
		grid.add_child(card)
		card.refresh()
		_cards[hero] = card
		renderer.hero(hero, "classic", "no_hat", func(tex): if is_instance_valid(card): card.set_art(tex))
		# A click picks on release, so a press that turns into a drag doesn't pick it as well
		card.pressed.connect(func():
			_pending = hero
			_show_hero(hero))
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _pending == hero:
				_pending = ""
				_toggle(hero))
		card.drag_started.connect(func():
			_pending = ""
			_show_hero(hero))

	# The picks: a golden slot each - drop a card on it (or click the card); click a full one to empty it
	var slots = HBoxContainer.new()
	slots.add_theme_constant_override("separation", 12)
	right.add_child(slots)
	for i in PlayerProfile.STARTER_PICKS:
		var pad = DropPad.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.accepts = func(payload): return payload is String and _cards.has(payload)
		pad.dropped.connect(func(payload): _drop_hero({"card_drag": true, "payload": payload}, i))
		pad.gui_input.connect(_on_slot_input.bind(i))
		slots.add_child(pad)
		_slots.append(pad)

	UITheme.create_spacer(true, right)  # the button sits at the bottom, level with the hero panel
	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	right.add_child(bottom)
	_count_label = UITheme.create_heading("", bottom)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count_label.uppercase = true
	_count_label.add_theme_font_override("font", UITheme.font_black())
	_count_label.add_theme_font_size_override("font_size", 20)
	_take = UITheme.create_primary_button("TAKE THESE HEROES", bottom, Vector2(340, 58))
	_take.add_theme_font_override("font", UITheme.font_black())
	_take.pressed.connect(_confirm)
	_show_hero(heroes[0].character_name if heroes.size() > 0 else "")
	_refresh()

## Click a card: it joins the pick (the oldest one drops out when there are too many), or leaves it
func _toggle(hero: String):
	if hero in _picked:
		_picked.erase(hero)
	else:
		_picked.append(hero)
		if _picked.size() > PlayerProfile.STARTER_PICKS:
			_picked.pop_front()
	_show_hero(hero)
	_refresh()

func _can_drop_hero(_at: Vector2, data) -> bool:
	return data is Dictionary and data.get("card_drag", false) and _cards.has(data.get("payload"))

## A card dropped on slot `slot` (-1: on the showcase - the first free slot, else like a click)
func _drop_hero(data, slot: int) -> void:
	var hero = data.get("payload")
	if not _cards.has(hero):
		return
	if slot < 0:
		if not hero in _picked:
			_toggle(hero)
		else:
			_show_hero(hero)
		return
	var had = _picked.find(hero)
	if had >= 0 and had != slot and slot < _picked.size():
		# Moved from the other slot: the two swap
		_picked[had] = _picked[slot]
		_picked[slot] = hero
	elif had < 0:
		if slot < _picked.size():
			_picked[slot] = hero
		else:
			_picked.append(hero)
	_show_hero(hero)
	_refresh()

## A click on a full slot empties it
func _on_slot_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if slot < _picked.size():
			Sfx.ui("ui_click")
			_picked.remove_at(slot)
			_refresh()

## The hero in the big showcase and its abilities under it
func _show_hero(hero: String) -> void:
	var data = CharacterRegistry.get_by_name(hero)
	if data == null:
		return
	if hero != _shown:
		_shown = hero
		_showcase.show_character(data)
	_hero_name.text = tr(hero)
	_hero_name.add_theme_color_override("font_color", data.color.lightened(0.35))
	_hero_stats.text = tr("%d HP  ·  speed %.1f") % [int(data.base_health), data.base_speed]
	_info_label.text = tr(data.active_ability.ability_name) + ": " + tr(data.active_ability.description) \
		+ "\n" + tr(data.passive_ability.ability_name) + ": " + tr(data.passive_ability.description)

func _refresh():
	for hero in _cards:
		var card: ParallaxCard = _cards[hero]
		card.selected = hero in _picked
		card.badge = ("%d" % (_picked.find(hero) + 1)) if card.selected else ""
		card.refresh()
	for i in _slots.size():
		var pad: DropPad = _slots[i]
		if i < _picked.size():
			pad.icon = "%d" % (i + 1)
			pad.caption = tr(_picked[i])
			pad.detail = tr("Click to remove")
		else:
			pad.icon = "⬇"
			pad.caption = tr("DRAG A HERO HERE")
			pad.detail = tr("or click its card")
	_count_label.text = tr("Picked %d of %d") % [_picked.size(), PlayerProfile.STARTER_PICKS]
	var ready_ = _picked.size() == PlayerProfile.STARTER_PICKS
	_count_label.add_theme_color_override("font_color", UITheme.GOLD if ready_ else UITheme.TEXT_SECONDARY)
	_take.disabled = not ready_

func _confirm():
	if _picked.size() != PlayerProfile.STARTER_PICKS:
		return
	PlayerProfile.choose_starters(_picked)
	PlayerProfile.set_preferred_hero(_picked[0])  # the main menu's dais shows them right away
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.selected_character = CharacterRegistry.get_by_name(_picked[0])
	ScreenEffects.flash(Color(1, 0.9, 0.5), 0.2, 0.2)
	_done()

func _done():
	finished.emit()
	var t = create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.tween_callback(queue_free)
