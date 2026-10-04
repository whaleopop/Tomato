## Guide: every hero, weapon, pickup and container with a 3D preview and the real numbers from
## the game data (CharacterRegistry, RangedWeapon.create_weapon, LootContainer, LootSpawner),
## plus the controls and the rules. Opened from the main menu as an overlay.
## Texts are English source strings: the Russian catalogue (ui/i18n) translates them.
extends Control
class_name Encyclopedia

signal closed

const TABS = ["Heroes", "Weapons", "Items", "Events", "How to play"]
const HOWTO_TAB: int = 4
const LIST_WIDTH = 270
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

var _tab_buttons: Array[Button] = []
var _body: HBoxContainer
var _list_box: VBoxContainer
var _info_box: VBoxContainer
var _info_scroll: ScrollContainer
var _showcase: CharacterShowcase
var _howto: Control
var _entries: Array = []            # {title, subtitle, color, show: Callable, info: Callable}
var _entry_buttons: Array[Button] = []
var _tab: int = -1

func _ready():
	# Already in the tree here: plain set_anchors_preset would keep the empty rect via offsets
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UITheme.create_background(self)

	var margin = UITheme.create_screen_margin(self, 32)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	# Header: back, title, tabs
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	column.add_child(header)
	var back = UITheme.create_button("←  BACK", header, Vector2(130, 46))
	back.pressed.connect(close)
	var titles = VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var title = UITheme.create_title("GUIDE", titles)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.create_label("Everything you can meet on the island", titles, UITheme.FONT_SMALL)

	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	column.add_child(tabs)
	for i in TABS.size():
		var tab_button = UITheme.create_button(TABS[i], tabs, Vector2(150, 44))
		tab_button.pressed.connect(_show_tab.bind(i))
		_tab_buttons.append(tab_button)

	# Body: list | 3D preview | details
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 16)
	column.add_child(_body)

	var list_panel = UITheme.create_panel(_body, 12)
	list_panel.custom_minimum_size.x = LIST_WIDTH
	var list_scroll = ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	list_scroll.add_child(_list_box)

	_showcase = CharacterShowcase.new()
	_showcase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_showcase)

	var info_panel = UITheme.create_panel(_body, 20)
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

	_show_tab(0)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)

func close():
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		close()
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
		UITheme.style_selectable(_tab_buttons[i], i == index)
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
		child.queue_free()
	_entry_buttons.clear()
	for i in _entries.size():
		var entry = _entries[i]
		if entry.has("section"):
			var caption = UITheme.create_caption(entry.section, _list_box)
			caption.custom_minimum_size.y = 26
			caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_entry_buttons.append(_make_entry_button(entry, i))
	_select_entry(0)

func _make_entry_button(entry: Dictionary, index: int) -> Button:
	var button = Button.new()
	button.custom_minimum_size = Vector2(0, 56)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_select_entry.bind(index))
	_list_box.add_child(button)

	var pad = MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 14)
	button.add_child(pad)
	var rows = VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", -2)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(rows)
	var name_label = UITheme.create_heading(entry.title, rows)
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", entry.color.lightened(0.35))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub = UITheme.create_label(entry.subtitle, rows, UITheme.FONT_TINY)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return button

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
		UITheme.style_selectable(_entry_buttons[i], on, _entries[i].color)
		if on:
			_entry_buttons[i].set_meta("selected", true)
		elif _entry_buttons[i].has_meta("selected"):
			_entry_buttons[i].remove_meta("selected")
	var entry = _entries[index]
	entry.show.call()
	for child in _info_box.get_children():
		child.queue_free()
	var title = UITheme.create_title(entry.title, _info_box)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	UITheme.create_caption("Stats", box)
	_stat(box, "Health", "%d" % int(c.base_health), c.base_health / max_health, UITheme.ACCENT_SUCCESS)
	_stat(box, "Speed", "%.1f" % c.base_speed, c.base_speed / max_speed, UITheme.ACCENT_INFO)
	UITheme.create_caption("Abilities", box)
	if c.active_ability:
		_ability_card(box, c.active_ability, "Active · F", UITheme.ACCENT_SECONDARY,
			tr("Cooldown: %d s") % int(round(c.active_ability.cooldown)))
	if c.passive_ability:
		_ability_card(box, c.passive_ability, "Passive", UITheme.ACCENT_BEET, tr("Always on"))

func _ability_card(box: VBoxContainer, data: AbilityData, kind: String, color: Color, footer: String):
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.glass_box(Color(color, 0.08), Color(color, 0.35), 14, 14, 10))
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

	UITheme.create_caption("Stats", box)
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
	row.add_theme_constant_override("separation", 16)

	var controls = UITheme.create_panel(row, 22)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cbox = VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 8)
	controls.add_child(cbox)
	UITheme.create_caption("Controls", cbox)
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
		[K.call("sprint"), "Sprint (uses stamina)"],
		[K.call("jump"), "Jump"],
		[K.call("camera_mode"), "Third-person camera on / off"],
		["RMB", "Aim over the shoulder (third person)"],
		["Esc", "Pause"],
	]
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	cbox.add_child(grid)
	for k in keys:
		var chip = UITheme.create_pill(k[0], UITheme.ACCENT_INFO, grid)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_END
		chip.custom_minimum_size.x = 96
		UITheme.create_label(k[1], grid)

	var rules = UITheme.create_panel(row, 22)
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rbox = VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 10)
	rules.add_child(rbox)
	UITheme.create_caption("How a match goes", rbox)
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
	dot.add_theme_color_override("font_color", UITheme.ACCENT_PRIMARY)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var label = _paragraph(row, text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _num(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0")
