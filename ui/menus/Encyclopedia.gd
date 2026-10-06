## Guide: every hero, weapon, pickup and container with a 3D preview and the real numbers from
## the game data (CharacterRegistry, RangedWeapon.create_weapon, LootContainer, LootSpawner),
## plus the controls and the rules. Opened from the main menu as an overlay.
## Texts are English source strings: the Russian catalogue (ui/i18n) translates them.
extends Control
class_name Encyclopedia

signal closed

const TABS = ["Heroes", "Weapons", "Items", "Events", "How to play"]
const HOWTO_TAB: int = 4
const LIST_WIDTH = 300
const INFO_WIDTH = 410

const WEAPON_BLURBS = {
	RangedWeapon.WeaponType.PISTOL: "Reliable sidearm. Every veggie lands with one and 60 rounds.",
	RangedWeapon.WeaponType.SHOTGUN: "Eight pellets in a wide cone: devastating up close, useless far away.",
	RangedWeapon.WeaponType.SNIPER: "One heavy shot from very far. You also see further with it.",
	RangedWeapon.WeaponType.RIFLE: "Fast automatic fire and a big magazine. Good at any mid range.",
	RangedWeapon.WeaponType.FLAMETHROWER: "A stream of fire that keeps burning the target after it hits.",
	RangedWeapon.WeaponType.SMG: "Sprays pistol rounds very fast. Deadly up close, wild further out.",
	RangedWeapon.WeaponType.HAND_CANNON: "Six heavy rounds: slow, loud and it hits like a truck.",
	RangedWeapon.WeaponType.MARKSMAN: "A semi-automatic rifle with a scope: quicker than the sniper, a little weaker.",
	RangedWeapon.WeaponType.MINIGUN: "A wall of bullets, but it is heavy: you walk slower while holding it.",
	RangedWeapon.WeaponType.DOUBLE_BARREL: "Two barrels, ten pellets each. Reload after every second shot.",
	RangedWeapon.WeaponType.JAM_BLASTER: "Shoots sticky jam: whoever it hits is slowed for a moment.",
	RangedWeapon.WeaponType.LAUNCHER: "Lobs grenades over cover. They blow up where they land.",
}

const SIDE: int = 28                 # the screen's side margin (the header's)
const GAP: int = 20                  # between the list, the stage and the info panel
const ROW_HEIGHT: int = 58

var header: ScreenHeader
var _tab_buttons: Array[Button] = []
var _body: HBoxContainer
var _list_scroll: ScrollContainer
var _list_box: VBoxContainer
var _info_box: VBoxContainer
var _info_scroll: ScrollContainer
var _showcase: CharacterShowcase
var _stage_kicker: Label
var _stage_name: Label
var _stage_count: Label
var _howto: Control
var _entries: Array = []            # {title, subtitle, color, show: Callable, info: Callable}
var _entry_buttons: Array[Button] = []
var _tab: int = -1
## Open on this tab at the entry with this title (set before adding it to the tree)
var start_tab: int = 0
var start_entry: String = ""

func _ready():
	# Already in the tree here: plain set_anchors_preset would keep the empty rect via offsets
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UITheme.create_background(self)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", ScreenHeader.CONTENT_TOP)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# Section tabs, the line about the guide at the other end
	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	column.add_child(tabs)
	for i in TABS.size():
		var tab_button = UITheme.create_tab(tr(TABS[i]).to_upper(), tabs, Vector2(150, 46))
		tab_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # translated above
		tab_button.pressed.connect(_show_tab.bind(i))
		_tab_buttons.append(tab_button)
	UITheme.create_spacer(true, tabs)
	var about = UITheme.create_label("Everything you can meet on the island", tabs, UITheme.FONT_SMALL)
	about.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	about.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	# Body: list | 3D stage | details
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", GAP)
	column.add_child(_body)

	var list_panel = UITheme.navy_panel(_body, 10)
	list_panel.custom_minimum_size.x = LIST_WIDTH
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(_list_scroll)
	var list_pad = MarginContainer.new()  # room for the rows' hover zoom inside the scroll
	list_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		list_pad.add_theme_constant_override(side, 6)
	_list_scroll.add_child(list_pad)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	list_pad.add_child(_list_box)

	_body.add_child(_build_stage())

	var info_panel = UITheme.navy_panel(_body, 22)
	info_panel.custom_minimum_size.x = INFO_WIDTH
	_info_scroll = ScrollContainer.new()
	_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_panel.add_child(_info_scroll)
	_info_box = VBoxContainer.new()
	_info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_box.add_theme_constant_override("separation", 10)
	_info_scroll.add_child(_info_box)

	_howto = _build_howto()
	_howto.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_howto)

	# The shared top bar last: it draws over the content's shadows
	header = ScreenHeader.make(self, "GUIDE", "HEROES · WEAPONS · LOOT", true)
	header.back_pressed.connect(close)

	show_entry(start_tab, start_entry)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)

## The middle: the entry's 3D model you can turn (drag) and zoom (wheel), its name on the stage
## disc, arrows to the previous / next entry
func _build_stage() -> Control:
	var stage = Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_showcase = CharacterShowcase.new()
	_showcase.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_showcase.interactive = true
	stage.add_child(_showcase)

	_stage_count = UITheme.create_label("", stage, UITheme.FONT_SMALL)
	_stage_count.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_stage_count.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stage_count.offset_top = 6
	_stage_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_count.add_theme_font_override("font", UITheme.font_black())
	_stage_count.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_stage_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_stage_count.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var names = VBoxContainer.new()
	names.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	names.grow_horizontal = Control.GROW_DIRECTION_BOTH
	names.grow_vertical = Control.GROW_DIRECTION_BEGIN
	names.offset_bottom = -40  # on the stage disc, above the hint
	names.add_theme_constant_override("separation", -4)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(names)
	_stage_kicker = UITheme.create_label("", names, 13)
	_stage_kicker.uppercase = true
	_stage_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_kicker.add_theme_font_override("font", UITheme.font_black())
	_stage_kicker.add_theme_color_override("font_color", UITheme.GOLD)
	_stage_kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_name = UITheme.create_hero_title("", names)
	_stage_name.uppercase = true
	_stage_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_name.add_theme_font_size_override("font_size", 40)
	_stage_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_stage_name.add_theme_constant_override("shadow_offset_y", 3)
	_stage_name.add_theme_constant_override("shadow_outline_size", 4)
	_stage_name.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for step in [-1, 1]:
		var arrow = UITheme.create_icon_chip("chevron_left" if step < 0 else "chevron_right", stage, Vector2(52, 72))
		arrow.add_theme_font_override("font", UITheme.font_black())
		arrow.add_theme_font_size_override("font_size", 38)
		arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT if step < 0 else Control.PRESET_CENTER_RIGHT)
		arrow.grow_horizontal = Control.GROW_DIRECTION_END if step < 0 else Control.GROW_DIRECTION_BEGIN
		arrow.grow_vertical = Control.GROW_DIRECTION_BOTH
		arrow.pressed.connect(_step.bind(step))

	var hint = UITheme.create_label("Drag to turn  ·  wheel to zoom  ·  double click to reset", stage, UITheme.FONT_SMALL)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -10
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return stage

func close():
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		var step = 1 if event.is_action_pressed("ui_right") else -1
		_show_tab(wrapi(_tab + step, 0, TABS.size()))
		get_viewport().set_input_as_handled()
	elif _tab >= 0 and _tab < HOWTO_TAB and not _entries.is_empty():
		var current = _selected_index()
		if event.is_action_pressed("ui_down"):
			_select_entry(min(current + 1, _entries.size() - 1))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_up"):
			_select_entry(max(current - 1, 0))
			get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- tabs / list

func _show_tab(index: int):
	_tab = index
	for i in _tab_buttons.size():
		UITheme.set_tab_active(_tab_buttons[i], i == index)
	var is_howto = index == HOWTO_TAB
	_body.visible = not is_howto
	_howto.visible = is_howto
	if is_howto:
		return
	match index:
		0:
			_entries = _hero_entries()
		1:
			_entries = _weapon_entries()
		2:
			_entries = _item_entries()
		3:
			_entries = _event_entries()
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	_entry_buttons.clear()
	var section = TABS[index]
	for i in _entries.size():
		var entry = _entries[i]
		if entry.has("section"):
			section = entry.section
			_section(_list_box, entry.section).custom_minimum_size.y = 24 if i == 0 else 34
		entry["group"] = section
		_entry_buttons.append(_make_entry_button(entry, i))
	_list_scroll.scroll_vertical = 0
	_select_entry(0)

## A tab and, on it, the entry titled `title` (an item name, a hero name...; "" = the first)
func show_entry(tab: int, title: String = "") -> void:
	_show_tab(clampi(tab, 0, TABS.size() - 1))
	if title == "" or tab == HOWTO_TAB:
		return
	for i in _entries.size():
		if String(_entries[i].get("title", "")) == title:
			_select_entry(i)
			return

## The stage arrows: the previous / next entry, round the list
func _step(step: int):
	if _entries.is_empty():
		return
	_select_entry(wrapi(_selected_index() + step, 0, _entries.size()))

## A list row in the main menu's look: a colored dot, the name over a short line, a chevron
func _make_entry_button(entry: Dictionary, index: int) -> Button:
	var button = UITheme.create_button("", _list_box, Vector2(0, ROW_HEIGHT))
	button.pressed.connect(_select_entry.bind(index))

	var dot = Panel.new()
	dot.add_theme_stylebox_override("panel", UITheme.glow_box(entry.color, 0.5, 99, 6))
	dot.custom_minimum_size = Vector2(10, 10)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	dot.offset_left = 16
	dot.offset_right = 26
	dot.offset_top = -5
	dot.offset_bottom = 5
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(dot)

	var rows = VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 38
	rows.offset_right = -32
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", -2)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(rows)
	var name_label = UITheme.create_heading(entry.title, rows)
	name_label.uppercase = true
	name_label.add_theme_font_override("font", UITheme.font_black())
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub = UITheme.create_label(entry.subtitle, rows, UITheme.FONT_TINY)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var chevron = Label.new()
	chevron.text = "›"
	chevron.add_theme_font_override("font", UITheme.font_black())
	chevron.add_theme_font_size_override("font_size", 30)
	chevron.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	chevron.offset_left = -30
	chevron.offset_right = -8
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chevron.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(chevron)
	button.set_meta("chevron", chevron)
	_style_row(button, false)
	return button

## Navy like the main menu's rows; the selected one lit with a gold rim
func _style_row(button: Button, selected: bool):
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	if selected:
		normal = UITheme.navy_box(Color(0.11, 0.15, 0.26, 0.98), UITheme.GOLD, 12)
		normal.set_border_width_all(2)
		normal.shadow_color = Color(UITheme.GOLD, 0.22)
		normal.shadow_size = 12
		normal.shadow_offset = Vector2.ZERO
		hover = normal
	else:
		normal = UITheme.navy_box(UITheme.NAVY, Color(1, 1, 1, 0.1), 12)
		hover = UITheme.navy_box(UITheme.NAVY_HOVER, Color(UITheme.GOLD, 0.8), 12)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", normal)
	button.add_theme_stylebox_override("hover_pressed", hover)
	var chevron: Label = button.get_meta("chevron", null)
	if chevron:
		chevron.add_theme_color_override("font_color", UITheme.GOLD if selected else UITheme.TEXT_MUTED)

## Scrolls the list to a row (deferred: after the rows are laid out; a row of a tab left since is skipped)
func _scroll_to(button):
	if is_instance_valid(button) and button.is_inside_tree() and _list_scroll.is_ancestor_of(button):
		_list_scroll.ensure_control_visible(button)

func _selected_index() -> int:
	for i in _entry_buttons.size():
		if _entry_buttons[i].has_meta("selected"):
			return i
	return 0

func _select_entry(index: int):
	if index < 0 or index >= _entries.size():
		return
	for i in _entry_buttons.size():
		var on = i == index
		_style_row(_entry_buttons[i], on)
		if on:
			_entry_buttons[i].set_meta("selected", true)
		elif _entry_buttons[i].has_meta("selected"):
			_entry_buttons[i].remove_meta("selected")
	if index < _entry_buttons.size():
		_scroll_to.call_deferred(_entry_buttons[index])
	var entry = _entries[index]
	entry.show.call()
	_stage_kicker.text = entry.subtitle
	_stage_name.text = entry.title
	_stage_name.add_theme_color_override("font_color", entry.color.lightened(0.35))
	_stage_count.text = "%d / %d" % [index + 1, _entries.size()]
	for child in _info_box.get_children():
		_info_box.remove_child(child)
		child.queue_free()
	var titles = VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	_info_box.add_child(titles)
	_kicker(titles, entry.get("group", TABS[_tab]))
	var title = UITheme.create_title(entry.title, titles)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.uppercase = true
	title.add_theme_font_override("font", UITheme.font_black())
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", entry.color.lightened(0.3))
	entry.info.call(_info_box)
	_info_scroll.scroll_vertical = 0


# ---------------------------------------------------------------- heroes

func _hero_entries() -> Array:
	var roster = CharacterRegistry.get_all()
	var max_health = 1.0
	var max_speed = 1.0
	for c in roster:
		max_health = max(max_health, c.base_health)
		max_speed = max(max_speed, c.base_speed)
	var entries: Array = []
	for c in roster:
		entries.append({
			"title": c.character_name,
			"subtitle": tr("%d HP  ·  speed %.1f") % [int(c.base_health), c.base_speed],
			"color": c.color,
			"show": _showcase.show_character.bind(c),
			"info": _hero_info.bind(c, max_health, max_speed),
		})
	return entries

func _hero_info(box: VBoxContainer, c: CharacterData, max_health: float, max_speed: float):
	_paragraph(box, c.description)
	_section(box, "Stats")
	_stat(box, "Health", "%d" % int(c.base_health), c.base_health / max_health, UITheme.ACCENT_SUCCESS)
	_stat(box, "Speed", "%.1f" % c.base_speed, c.base_speed / max_speed, UITheme.ACCENT_INFO)
	_section(box, "Abilities")
	if c.active_ability:
		_ability_card(box, c.active_ability, "Active · F", UITheme.ACCENT_SECONDARY,
			tr("Cooldown: %d s") % int(round(c.active_ability.cooldown)))
	if c.passive_ability:
		_ability_card(box, c.passive_ability, "Passive", UITheme.ACCENT_BEET, tr("Always on"))

func _ability_card(box: VBoxContainer, data: AbilityData, kind: String, color: Color, footer: String):
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.navy_box(Color(0.08, 0.10, 0.18, 0.95), Color(color, 0.45), 12, 14, 10))
	box.add_child(card)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var name_label = UITheme.create_heading(data.ability_name, head)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.create_pill(kind, color, head).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_paragraph(col, data.description, UITheme.FONT_SMALL)
	var foot = UITheme.create_label(footer, col, UITheme.FONT_TINY)
	foot.add_theme_color_override("font_color", color.lightened(0.2))

# ---------------------------------------------------------------- weapons

var _weapon_count: int = 5

func _weapon_entries() -> Array:
	var total_weight = 0
	for w in LootContainer.WEAPON_WEIGHTS.values():
		total_weight += w
	_weapon_count = LootContainer.WEAPON_WEIGHTS.size()
	var entries: Array = []
	for type in RangedWeapon.WeaponType.values():
		var weapon = RangedWeapon.create_weapon(type)
		var share = float(LootContainer.WEAPON_WEIGHTS.get(type, 0)) / max(total_weight, 1)
		var color = _rarity_color(share)
		entries.append({
			"title": weapon.item_name,
			"subtitle": tr(_rarity_name(share)) + "  ·  " + tr(AmmoItem.get_ammo_type_name(weapon.ammo_type)),
			"color": color,
			"show": _show_pickup.bind(LootItem.ItemType.WEAPON, weapon, color, 1.2),
			"info": _weapon_info.bind(weapon, share),
		})
	return entries

func _weapon_info(box: VBoxContainer, w: RangedWeapon, share: float):
	var pills = HFlowContainer.new()
	pills.add_theme_constant_override("h_separation", 8)
	box.add_child(pills)
	UITheme.create_pill(_rarity_name(share), _rarity_color(share), pills)
	if w.weapon_type == RangedWeapon.WeaponType.PISTOL:
		UITheme.create_pill("Starting weapon", UITheme.ACCENT_PRIMARY, pills)
	_paragraph(box, WEAPON_BLURBS.get(w.weapon_type, ""))

	_section(box, "Stats")
	var per_shot = w.damage * w.pellet_count
	var damage_text = ("%d × %d" % [int(w.damage), w.pellet_count]) if w.pellet_count > 1 else "%d" % int(w.damage)
	_stat(box, "Damage per shot", damage_text, per_shot / 100.0, UITheme.ACCENT_DANGER)
	var rate = 1.0 / max(w.fire_rate, 0.01)
	_stat(box, "Shots per second", _num(rate), rate / 20.0, UITheme.ACCENT_SECONDARY)
	_stat(box, "Range", tr("%d m") % int(w.range), w.range / 80.0, UITheme.ACCENT_INFO)
	_stat(box, "Sight", tr("%d m") % int(w.visibility_range), w.visibility_range / 26.0, UITheme.ACCENT_PRIMARY)
	_stat(box, "Magazine", "%d" % w.magazine_size, w.magazine_size / 100.0, UITheme.ACCENT_BEET)
	_fact(box, "Reload", tr("%s s") % _num(w.reload_time))
	_fact(box, "Ammo", AmmoItem.get_ammo_type_name(w.ammo_type))
	if w.pellet_count > 1:
		_fact(box, "Spread", tr("%d pellets in a %d° cone") % [w.pellet_count, int(w.spread_angle)])
	if w.fire_trail_enabled:
		_fact(box, "Burning", tr("%d damage per second for %d s") % [int(w.burn_damage), int(w.burn_duration)])
	if w.blast_radius > 0.0:
		_fact(box, "Blast", tr("%d – %d damage in %s m around the landing spot") % [int(w.damage * 0.5), int(w.damage), _num(w.blast_radius)])
	if w.slow_on_hit > 0.0:
		_fact(box, "Sticky", tr("Hit enemies walk %d%% slower for %s s") % [roundi((1.0 - w.slow_on_hit) * 100.0), _num(w.slow_time)])
	if w.move_factor < 1.0:
		_fact(box, "Heavy", tr("You walk %d%% slower with it in hand") % roundi((1.0 - w.move_factor) * 100.0))
	_note(box, "Sight is how far the fog of war opens around you with this weapon in hand.")

## Rarity against an even share of the weapon pool (more guns: smaller shares for all)
func _rarity_name(share: float) -> String:
	var even = 1.0 / max(_weapon_count, 1)
	if share >= even * 1.25:
		return "Common"
	if share >= even * 0.75:
		return "Uncommon"
	return "Rare"

func _rarity_color(share: float) -> Color:
	match _rarity_name(share):
		"Common":
			return Color(0.75, 0.8, 0.9)
		"Uncommon":
			return UITheme.ACCENT_INFO
	return UITheme.ACCENT_SECONDARY

# ---------------------------------------------------------------- items and containers

func _loot_chance(type: int) -> String:
	var weights = LootContainer.DEFAULT_LOOT_WEIGHTS
	var total = 0
	for w in weights.values():
		total += w
	return tr("%d%% of the loot") % int(round(100.0 * weights.get(type, 0) / max(total, 1)))

func _item_entries() -> Array:
	var entries: Array = []
	var T = LootItem.ItemType
	entries.append(_pickup_entry("Health Pack", T.HEALTH, null, _loot_chance(T.HEALTH), [
		["Effect", tr("Heals %d HP") % int(LootContainer.HEALTH_PACK_HEAL)],
		["Use", tr("Health pack: %s, %.0f s (moving slowly, a shot cancels)") % [Keybinds.label("use_heal"), InventoryComponent.USE_TIMES["heal"]]],
		["Where", "Rare: now and then in any container; the golden drops always have one"],
	], tr("Picked up automatically when you walk over it, or with %s.") % Keybinds.label("interact")))
	entries.append(_pickup_entry("Shield", T.SHIELD, null, _loot_chance(T.SHIELD), [
		["Effect", tr("+%d shield, up to %d") % [30, int(HealthComponent.MAX_SHIELD)]],
		["How it works", "Takes the damage before your health does"],
		["Use", tr("Shield: %s, %.1f s (moving slowly, a shot cancels)") % [Keybinds.label("use_shield"), InventoryComponent.USE_TIMES["shield"]]],
		["Lasts", "Until it is shot away or you are eliminated"],
	], "Your shield is the blue bar under the health bar."))
	entries.append(_pickup_entry("Ability Boost", T.ABILITY_BOOST, null, _loot_chance(T.ABILITY_BOOST), [
		["Effect", "Your ability is ready again at once"],
	], "Grab it right after using your ability."))
	var A = AmmoItem.AmmoType
	var P = LootContainer.AMMO_PER_PICKUP
	entries.append(_pickup_entry("Ammo", T.AMMO, AmmoItem.new(A.PISTOL, P[A.PISTOL]), _loot_chance(T.AMMO), [
		["With every gun", "A pack of its own ammo"],
		["Pistol Ammo", tr("+%d  ·  Pistol, SMG, Hand Cannon, Jam Blaster") % P[A.PISTOL]],
		["Shotgun Shells", tr("+%d  ·  Shotgun, Double Barrel") % P[A.SHOTGUN]],
		["Rifle Ammo", tr("+%d  ·  Assault Rifle, Minigun") % P[A.RIFLE]],
		["Sniper Rounds", tr("+%d  ·  Sniper Rifle, Marksman Rifle") % P[A.SNIPER]],
		["Fuel", tr("+%d  ·  Flamethrower") % P[A.FUEL]],
		["Grenades", tr("+%d  ·  Grenade Launcher") % P[A.GRENADE]],
	], "Loose packs come in the types of the common guns. Ammo for weapons you don't carry waits in the inventory (I)."))
	var weapon_entry = _pickup_entry("Weapon", T.WEAPON, RangedWeapon.create_weapon(RangedWeapon.WeaponType.RIFLE), _loot_chance(T.WEAPON), [
		["Effect", "One of the twelve guns, see the Weapons tab"],
		["Where", "Every chest and supply drop, often in crates - always with a pack of its ammo"],
		["Slots", "Two weapons, switch with 1 / 2; X swaps the one in hand"],
	], "")
	entries.append(weapon_entry)

	var containers = [
		[LootContainer.ContainerType.CRATE, "Crate"],
		[LootContainer.ContainerType.BARREL, "Barrel"],
		[LootContainer.ContainerType.CHEST, "Chest"],
		[LootContainer.ContainerType.SUPPLY_DROP, "Supply Drop"],
	]
	var first = true
	for c in containers:
		var entry = _container_entry(c[0], c[1])
		if first:
			entry["section"] = "Containers"
			first = false
		entries.append(entry)
	entries[0]["section"] = "Pickups"
	return entries

func _pickup_entry(title: String, type: int, data: ItemData, subtitle: String, facts: Array, note: String) -> Dictionary:
	var color = LootVisuals.type_color(type)
	var size = 1.2 if type == LootItem.ItemType.WEAPON else 0.85
	return {
		"title": title,
		"subtitle": subtitle,
		"color": color,
		"show": _show_pickup.bind(type, data, color, size),
		"info": _pickup_info.bind(facts, note),
	}

func _show_pickup(type: int, data: ItemData, color: Color, size: float):
	_showcase.show_model(LootVisuals.pickup_model(type, data), color, size, true, 0.75)

func _pickup_info(box: VBoxContainer, facts: Array, note: String):
	for f in facts:
		_fact(box, f[0], f[1])
	if note != "":
		_note(box, note)

func _container_entry(type: int, title: String) -> Dictionary:
	var summary = LootContainer.loot_summary(type)
	var color = Color(0.95, 0.75, 0.45) if type != LootContainer.ContainerType.SUPPLY_DROP else UITheme.ACCENT_PRIMARY
	return {
		"title": title,
		"subtitle": _items_text(summary[0], summary[1]),
		"color": color,
		"show": _show_container.bind(type, color),
		"info": _container_info.bind(type, summary),
	}

func _items_text(fewest: int, most: int) -> String:
	if most > fewest:
		return tr("%d – %d items") % [fewest, most]
	return tr("%d items") % fewest if fewest > 1 else tr("1 item")

func _show_container(type: int, color: Color):
	_showcase.show_model(LootVisuals.container_model(type), color, 1.1, true, 0.0)

func _container_info(box: VBoxContainer, type: int, summary: Array):
	_fact(box, "Inside", _items_text(summary[0], summary[1]))
	var sure: Array = summary[2]
	if sure.has(LootItem.ItemType.WEAPON):
		_fact(box, "Always", "A gun with a pack of its ammo")
	if sure.has(LootItem.ItemType.SHIELD):
		_fact(box, "Also", "A shield")
	var table: Dictionary = LootContainer.LOOT_TABLES.get(type, {})
	if not table.is_empty():
		var total = 0
		for w in table.values():
			total += w
		var names = {LootItem.ItemType.AMMO: "Ammo", LootItem.ItemType.WEAPON: "Weapon", LootItem.ItemType.HEALTH: "Health Pack",
			LootItem.ItemType.SHIELD: "Shield", LootItem.ItemType.ABILITY_BOOST: "Ability Boost"}
		var parts: Array = []
		for t in table:
			parts.append("%s %d%%" % [tr(names[t]), int(round(100.0 * table[t] / total))])
		_fact(box, "Plus one of", ", ".join(parts))
	if type == LootContainer.ContainerType.SUPPLY_DROP:
		_fact(box, "When", "Falls from the sky every minute of the match")
		_note(box, "Watch for the parachute: everyone else sees it too.")
	else:
		var weights = LootSpawner.DEFAULT_CONTAINER_WEIGHTS
		var total = 0
		for w in weights.values():
			total += w
		_fact(box, "On the map", tr("%d%% of the containers") % int(round(100.0 * weights.get(type, 0) / max(total, 1))))
		_note(box, "Walk up and press X: it opens with a little show and throws the loot around.")

# ---------------------------------------------------------------- map events

func _event_entries() -> Array:
	var E = MapEvents
	var D = MapEventDirector
	var entries: Array = []
	entries.append(_event_entry("Meteor shower", "Red circles, then rocks from the sky", Color(1.0, 0.42, 0.2), _meteor_model, [
		["Warning", tr("%d s: red circles on the ground and on the minimap") % int(D.METEOR_WARN)],
		["Hit", tr("%d – %d damage and a knockback") % [int(E.METEOR_DAMAGE * 0.5), int(E.METEOR_DAMAGE)]],
		["After", tr("The crater burns for %d s") % int(E.METEOR_FIRE_TIME)],
	], "Some of them aim at where players stand: keep moving."))
	entries.append(_event_entry("Earthquake", "The island shakes", Color(0.92, 0.76, 0.52), CoverSpawner.load_prop.bind("wall_stone"), [
		["Lasts", tr("%d s") % int(D.QUAKE_TIME)],
		["Walls", tr("About %d%% of them fall") % int(D.QUAKE_WALL_SHARE * 100.0)],
		["Aim", tr("Spread x%.1f for everyone, even the sniper") % E.QUAKE_SPREAD],
	], "Your cover may be gone in a second: check it."))
	entries.append(_event_entry("Night or fog", "Everyone sees half as far", Color(0.62, 0.72, 1.0), _moon_model, [
		["Lasts", tr("%d s") % int(D.NIGHT_TIME)],
		["Sight", tr("x%.1f for everyone") % E.NIGHT_SIGHT],
		["Bushes", "Hide better: come twice as close to spot someone"],
	], "At night a small light stays around your hero."))
	entries.append(_event_entry("Flood", "The water rises", Color(0.4, 0.75, 1.0), _drop_model, [
		["Effect", "Shallows turn deep, low shores go under"],
		["Water", tr("Deep water: %d%% speed, shallows: %d%%") % [int(HexTile.speed_factor(HexTile.BiomeType.WATER) * 100.0), int(HexTile.speed_factor(HexTile.BiomeType.SHALLOW_WATER) * 100.0)]],
		["When", "Once per match"],
	], "Walls and bushes on the flooded shore are gone."))
	entries.append(_event_entry("Rift", "A crack splits the island", UITheme.ACCENT_WARNING, _ridge_model, [
		["Warning", tr("The line glows for %d s, then burns for %d s") % [int(D.RIFT_WARN), int(D.RIFT_BURN)]],
		["Then", "It rises into a rock ridge"],
		["On it", tr("Pushed to your side; stuck in the rock: %d damage") % int(DestructionSystem.CRUSH_DAMAGE)],
	], "The middle stays open, so the halves stay linked. Cross while you can."))
	entries.append(_event_entry("Harvest patch", "A rare bonus grows", UITheme.ACCENT_SUCCESS, LootVisuals.harvest_model.bind(E.harvest_color(E.Harvest.DAMAGE)), [
		["Ripens in", tr("%d s") % int(D.HARVEST_GROW)],
		["Speed Sprout", tr("+%d%% speed for %d s") % [roundi((E.HARVEST_SPEED - 1.0) * 100.0), int(E.HARVEST_TIME)]],
		["Power Sprout", tr("+%d%% damage for %d s") % [roundi((E.HARVEST_DAMAGE - 1.0) * 100.0), int(E.HARVEST_TIME)]],
		["Shield Sprout", tr("Full shield and +%d HP") % int(E.HARVEST_HEAL)],
	], "It grows away from everyone and shows on the minimap: expect a fight."))
	entries.append(_event_entry("Zone supply drop", "Good loot where the zone is going", LootContainer.RICH_COLOR, LootVisuals.container_model.bind(LootContainer.ContainerType.SUPPLY_DROP), [
		["When", tr("On zone steps %s") % ", ".join(D.ZONE_DROP_PHASES.map(func(p): return str(p)))],
		["Inside", "A strong weapon, a shield, a crystal, a health pack and one more"],
	], "The golden pillar marks it, on the minimap too."))
	entries.append(_event_entry("Zone shift", "The final zone moves", UITheme.ACCENT_WARNING, _ring_model, [
		["When", tr("Once the safe area is down to %d rings") % DestructionSystem.SHIFT_RADIUS],
		["Warning", "A few seconds ahead: a yellow ring on the minimap"],
	], "Don't settle in the middle too early."))
	entries[0]["section"] = tr("Random, every %d – %d s") % [int(D.GAP_MIN), int(D.GAP_MAX)]
	entries[6]["section"] = "With the zone"
	# The hostile weeds (world/enemies/Weed.gd), with their real numbers
	var weeds_start = entries.size()
	var how = {"Dandelion": ["Throws seed puffs from afar", "Keeps its distance: close in or step aside when it throws"],
		"Hogweed": ["Slow and tough, its sap burns and slows", "Don't trade blows: shoot it from range"],
		"Nettle": ["Fast, stings and slows", "It catches up: stand and shoot, or put a wall between you"]}
	for kind in ["Dandelion", "Hogweed", "Nettle"]:
		var c: Dictionary = Weed.KINDS[kind]
		var facts = [
			["Health", "%d" % int(c.health)],
			["Hit", tr("%d damage every %.1f s") % [int(c.damage), c.cooldown]],
			["Reach", tr("%.0f m") % c.range],
			["Notices you", tr("Within %.0f m") % c.aggro],
		]
		if c.slow > 0.0:
			facts.append(["Slows", tr("To %d%% speed") % int(c.slow * 100.0)])
		entries.append(_event_entry(kind, how[kind][0], c.color, _weed_model.bind(kind), facts, how[kind][1]))
	entries[weeds_start]["section"] = "Weeds"
	return entries

func _weed_model(kind: String) -> Node3D:
	var path: String = Weed.KINDS[kind].model
	if not ResourceLoader.exists(path):
		return Node3D.new()
	var inst = load(path).instantiate()
	ModelUtils.apply_lowpoly_look(inst)
	var holder = Node3D.new()
	holder.add_child(inst)
	ModelUtils.normalize_to_height(inst, 1.2)
	return holder

## make_model: builds the preview model when the entry is opened (null: nothing on the stage)
func _event_entry(title: String, subtitle: String, color: Color, make_model: Callable, facts: Array, note: String) -> Dictionary:
	return {
		"title": title,
		"subtitle": subtitle,
		"color": color,
		"show": func(): _showcase.show_model(make_model.call(), color, 1.0, true, 0.6),
		"info": _pickup_info.bind(facts, note),
	}

func _meteor_model() -> Node3D:
	var rock = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radial_segments = 7
	sphere.rings = 4
	rock.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.18, 0.14)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.1)
	mat.emission_energy_multiplier = 0.3
	mat.roughness = 0.9
	rock.material_override = mat
	return rock

func _moon_model() -> Node3D:
	var moon = MeshInstance3D.new()
	moon.mesh = SphereMesh.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.92, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.62, 0.9)
	moon.material_override = mat
	return moon

func _ridge_model() -> Node3D:
	var ridge = Node3D.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.39, 0.36)
	for i in 3:
		var peak = MeshInstance3D.new()
		var cone = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.5
		cone.height = 1.1 - abs(i - 1) * 0.3
		cone.radial_segments = 6
		peak.mesh = cone
		peak.material_override = mat
		peak.position = Vector3((i - 1) * 0.7, cone.height / 2.0, 0)
		ridge.add_child(peak)
	return ridge

func _ring_model() -> Node3D:
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	ring.mesh = torus
	var mat = StandardMaterial3D.new()
	mat.albedo_color = UITheme.ACCENT_WARNING
	mat.emission_enabled = true
	mat.emission = UITheme.ACCENT_WARNING
	ring.material_override = mat
	return ring

func _drop_model() -> Node3D:
	var drop = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.height = 1.4
	drop.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.65, 1.0)
	mat.roughness = 0.1
	drop.material_override = mat
	return drop

# ---------------------------------------------------------------- how to play

func _build_howto() -> Control:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)

	var controls = UITheme.navy_panel(row, 26)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cbox = VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 14)
	controls.add_child(cbox)
	_panel_title(cbox, "How to play", "Controls")
	# The keys as they are bound now (Settings -> Controls, Keybinds)
	var K = func(action): return Keybinds.label(action)
	var keys = [
		["%s %s %s %s" % [K.call("move_up"), K.call("move_left"), K.call("move_down"), K.call("move_right")], "Move"],
		["Mouse", "Mouse: turn the hero and the camera, up / down - aim nearer / further" if GameSettings.camera_locked else "Aim"],
		[K.call("attack"), "Shoot (hold for automatic fire)"],
		[K.call("reload"), "Reload"],
		["%s – %s" % [K.call("weapon_slot_1"), K.call("weapon_slot_2")], "Switch weapon"],
		[K.call("ability_1"), "Use your ability (hold to see its area, release to cast)"],
		[K.call("interact"), "Open containers, pick up loot"],
		[K.call("inventory"), "Inventory"],
		[K.call("use_heal"), "Use a health pack"],
		[K.call("use_shield"), "Drink a shield"],
		[K.call("jump"), "Jump"],
		[K.call("camera_mode"), "Third-person camera on / off"],
		["RMB", "Aim over the shoulder (third person)"],
		["Esc", "Pause"],
	]
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	_scrolled(cbox).add_child(grid)
	for k in keys:
		_key_cap(k[0], grid)
		var what = UITheme.create_label(k[1], grid, UITheme.FONT_SMALL)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)

	var rules = UITheme.navy_panel(row, 26)
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rules_column = VBoxContainer.new()
	rules_column.add_theme_constant_override("separation", 14)
	rules.add_child(rules_column)
	_panel_title(rules_column, "How to play", "How a match goes")
	var rbox = VBoxContainer.new()
	rbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rbox.add_theme_constant_override("separation", 10)
	_scrolled(rules_column).add_child(rbox)
	for line in [
		"Pick a landing spot, drop in from the meteor and grab what you find.",
		"The zone closes in on a random spot: the edge glows first, then burns, then mountains rise and shove everyone inwards.",
		"Watch the minimap: glowing tiles go next, the white ring is the safe area, the timer is at the top.",
		"Mountains ring the island: nobody falls off. When only the core is left, it catches fire again and again.",
		"The fog of war hides everything you can't see. Walls block sight; your weapon sets how far you see.",
		"In a bush nobody sees you, until you shoot or someone comes very close.",
		"Water and swamp slow you down; shallow water less than deep.",
		"The island stands on terraces: walk up a ramp or jump a ledge. From higher ground you see further.",
		"Landmarks (a windmill, a greenhouse, a giant watering can...) hold most of the chests; the greenhouse and the windmill the best ones.",
		"Special ground: the flower meadow heals, frost is fast but slippery, tall grass hides you, mushrooms recharge abilities but cut your sight, brambles hurt.",
		"From the second minute on the island throws events at you: meteors, quakes, night, floods... See the Events tab.",
		"The last veggie standing wins.",
	]:
		_bullet(rbox, line)
	return row

# ---------------------------------------------------------------- building blocks

## A gold uppercase caption over a group (the list's sections, the info panel's "Stats")
func _section(box: Control, text: String) -> Label:
	var label = _kicker(box, text)
	label.custom_minimum_size.y = 28
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return label

## The small gold kicker over a title
func _kicker(box: Control, text: String) -> Label:
	var label = UITheme.create_label(text, box, UITheme.FONT_TINY)
	label.uppercase = true
	label.add_theme_font_override("font", UITheme.font_black())
	label.add_theme_color_override("font_color", UITheme.GOLD)
	return label

## A panel's kicker over its white uppercase heading
func _panel_title(box: Control, kicker: String, title: String):
	var titles = VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	box.add_child(titles)
	_kicker(titles, kicker)
	var head = UITheme.create_heading(title, titles)
	head.uppercase = true
	head.add_theme_font_override("font", UITheme.font_black())
	head.add_theme_font_size_override("font_size", 24)

## A vertical scroll filling the rest of `box` (the How to play panels on small screens)
func _scrolled(box: Control) -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	return scroll

## A key as a navy key cap with a gold rim ("W A S D", "F", "Esc")
func _key_cap(text: String, parent: Control) -> PanelContainer:
	var cap = PanelContainer.new()
	cap.add_theme_stylebox_override("panel", UITheme.navy_box(Color(0.10, 0.13, 0.22, 0.98), Color(UITheme.GOLD, 0.5), 8, 12, 3))
	cap.custom_minimum_size.x = 110
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(cap)
	var label = UITheme.create_label(text, cap, 13)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UITheme.font_black())
	label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	return cap

func _paragraph(box: Control, text: String, size: int = UITheme.FONT_NORMAL) -> Label:
	var label = UITheme.create_label(text, box, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 100
	return label

func _stat(box: Control, stat_name: String, value_text: String, ratio: float, color: Color):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var name_label = UITheme.create_label(stat_name, row, UITheme.FONT_SMALL)
	name_label.custom_minimum_size.x = 150
	var bar = UITheme.create_progress_bar(1.0, clamp(ratio, 0.03, 1.0), color, row)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value = UITheme.create_label(value_text, row, UITheme.FONT_SMALL)
	value.custom_minimum_size.x = 58
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_override("font", UITheme.font_black())
	value.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)

func _fact(box: Control, key: String, value: String):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var key_label = UITheme.create_label(key, row, UITheme.FONT_SMALL)
	key_label.custom_minimum_size.x = 150
	key_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	var value_label = UITheme.create_label(value, row, UITheme.FONT_SMALL)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)

func _note(box: Control, text: String):
	var label = _paragraph(box, text, UITheme.FONT_SMALL)
	label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

func _bullet(box: Control, text: String):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var dot = UITheme.create_label("•", row)
	dot.add_theme_color_override("font_color", UITheme.GOLD)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var label = _paragraph(row, text, 15)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _num(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0")
