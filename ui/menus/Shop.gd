## Shop: heroes, hero skins, hats and gun finishes as collectible cards (ParallaxCard: move the
## mouse over a card and it tilts, its layers slide). Pictures are rendered from the real models
## (ItemRenderer). The chosen card shows big on the right with the buy / equip button. Skins and
## hats are bought once and put on per hero; a gun finish goes on every gun. Coins: PlayerProfile.
## Laid out like the main menu: the ScreenHeader bar (back, title, wallet), section tabs, the grid,
## the 3D stage in the middle and a navy side panel. Buying by hand: drag a card into the golden
## DropPad under the big card (buy / equip - the same path as the buttons), or onto the stage to
## try it on (equipped if it is yours). A purchase throws coins at the wallet and flips the card.
extends Control
class_name Shop

signal closed

const TABS = ["Heroes", "Hero skins", "Hats", "Weapon finishes"]
const KINDS = ["hero", "skin", "hat", "weapon"]
const COIN_COLOR := Color(1.0, 0.8, 0.3)
const COLUMNS: int = 4            # on wide screens; fewer when narrow (_fit_layout)
const SIDE_WIDTH: int = 340
const GAP: int = 20

var _kind: String = "hero"
var _roster: Array[CharacterData] = []
var _hero_index: int = 0          # the hero skins / hats are shown and put on
var _weapon_type: int = 0         # the gun finishes are shown on
var _selected: String = ""        # card key (hero name, skin / hat id, finish name)
var _tab_buttons: Array[Button] = []
var _grid: GridContainer
var _side: VBoxContainer
var _big: ParallaxCard
var _header: ScreenHeader
var _cards: Dictionary = {}       # key -> ParallaxCard
var _renderer: ItemRenderer
var _showcase: CharacterShowcase = null  # the big 3D preview in the middle
var _stage: Control
var _stage_glow: StageGlow               # the "drop to try on" ring over the stage
var _owned_label: Label                  # "4 / 21 owned" at the toolbar's right end
var _steps_label: Label                 # what to do on this tab, next to the tabs
var _chips_caption: Label
var _chips: HeroChips                    # heroes (skins, hats) or guns (finishes) to try the cards on
var _stage_name: Label
var _pad: DropPad = null                 # the side panel's "drag a card here" slot
var _need_label: Label = null            # "not enough coins" under the buy button
var _fx: Control                         # flying coins, over everything
var _mouse := Vector2(-1, -1)            # last pointer position (_input)
## Open on this tab ("hero", "skin", "hat", "weapon") with this hero / gun chosen (set before
## adding the shop to the tree; the main menu's 3D scene does: the hero -> skins, a gun -> finishes)
var start_kind: String = "hero"
var start_hero: String = ""
var start_weapon: int = -1

const STEPS = {
	"hero": "Pick a hero card: it appears on the stage",
	"skin": "1. Choose a hero above the stage   2. Click a skin to try it on",
	"hat": "1. Choose a hero above the stage   2. Click a hat to try it on",
	"weapon": "1. Choose a gun above the stage   2. Click a finish to try it on",
}

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UITheme.create_background(self)
	_renderer = ItemRenderer.get_instance(get_tree())
	_roster = CharacterRegistry.get_all()
	var owned = PlayerProfile.owned_heroes()
	var game_manager = get_node_or_null("/root/GameManager")
	for i in _roster.size():
		var n = _roster[i].character_name
		if (game_manager and game_manager.selected_character and game_manager.selected_character.character_name == n) or (_hero_index == 0 and n in owned):
			_hero_index = i
	for i in _roster.size():
		if start_hero != "" and _roster[i].character_name == start_hero:
			_hero_index = i
	if start_weapon >= 0 and start_weapon < RangedWeapon.WeaponType.size():
		_weapon_type = start_weapon

	# Everything under the bar
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", ScreenHeader.SIDE_MARGIN)
	margin.add_theme_constant_override("margin_right", ScreenHeader.SIDE_MARGIN)
	margin.add_theme_constant_override("margin_top", ScreenHeader.CONTENT_TOP)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# Section tabs, what to do on this one at the right
	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(toolbar)
	for i in TABS.size():
		var tab_button = UITheme.create_tab(TABS[i], toolbar, Vector2(150, 46))
		tab_button.pressed.connect(_show_tab.bind(i))
		_tab_buttons.append(tab_button)
	UITheme.create_spacer(false, toolbar).custom_minimum_size.x = 16
	_steps_label = UITheme.create_label("", toolbar, UITheme.FONT_SMALL)
	_steps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_steps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_steps_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_steps_label.custom_minimum_size.x = 60
	_steps_label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	_owned_label = UITheme.create_label("", toolbar, UITheme.FONT_SMALL)
	_owned_label.custom_minimum_size = Vector2(120, ScreenHeader.SUBNAV_H)
	_owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_owned_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_owned_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_owned_label.add_theme_font_override("font", UITheme.font_black())
	_owned_label.add_theme_color_override("font_color", UITheme.GOLD)

	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", GAP)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var pad = MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(side, 22)  # room for the hover zoom and the tilt
	scroll.add_child(pad)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	pad.add_child(_grid)

	# The big 3D preview between the cards and the side panel: drag to turn, wheel to zoom, drop a
	# card on it to try it on. Above it: who the cards are tried on (hero / gun chips), the arrows
	# at its sides do the same.
	_stage = Control.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_stage)
	_showcase = CharacterShowcase.new()
	_showcase.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_showcase.interactive = true
	_showcase.set_drag_forwarding(Callable(), _stage_can_drop, _stage_drop)
	_stage.add_child(_showcase)
	_stage_glow = StageGlow.new()
	_stage_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(_stage_glow)
	var top = VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 4
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(top)
	_chips_caption = UITheme.create_label("", top, 12)
	_chips_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chips_caption.uppercase = true
	_chips_caption.add_theme_font_override("font", UITheme.font_black())
	_chips_caption.add_theme_color_override("font_color", UITheme.GOLD)
	_chips = HeroChips.new()
	_chips.chip_size = 52.0
	_chips.chosen.connect(_choose)
	top.add_child(_chips)
	_stage_name = UITheme.create_title("", _stage)
	_stage_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_stage_name.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stage_name.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stage_name.offset_bottom = -34  # on the stage disc, above the hint
	_stage_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_name.uppercase = true
	_stage_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_name.add_theme_font_override("font", UITheme.font_black())
	_stage_name.add_theme_constant_override("shadow_offset_y", 3)
	_stage_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	for step in [-1, 1]:
		var arrow = UITheme.create_icon_chip("chevron_left" if step < 0 else "chevron_right", _stage, Vector2(48, 68))
		arrow.add_theme_font_size_override("font_size", 34)
		arrow.add_theme_font_override("font", UITheme.font_black())
		arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT if step < 0 else Control.PRESET_CENTER_RIGHT)
		arrow.grow_horizontal = Control.GROW_DIRECTION_END if step < 0 else Control.GROW_DIRECTION_BEGIN
		arrow.grow_vertical = Control.GROW_DIRECTION_BOTH
		arrow.pressed.connect(_step.bind(step))
	var hint = UITheme.create_label("Drag to turn  ·  wheel to zoom  ·  double click to reset", _stage, UITheme.FONT_TINY)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -10
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var side_panel = UITheme.navy_panel(body, 18)
	side_panel.custom_minimum_size.x = SIDE_WIDTH
	var side_scroll = ScrollContainer.new()  # only scrolls on short screens
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(side_scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.add_theme_constant_override("separation", 8)
	side_scroll.add_child(_side)

	MenuShell.show_bar()
	_header = MenuShell.header
	MenuShell.current = MenuShell.SceneId.SHOP
	MenuShell._mark_active()
	if not _header.back_pressed.is_connected(close):
		_header.back_pressed.connect(close)
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.z_index = 100
	add_child(_fx)

	_fit_layout()
	get_viewport().size_changed.connect(_on_screen_resized)
	_show_tab(max(KINDS.find(start_kind), 0))

func close():
	MenuShell.goto(MenuShell.SceneId.MAIN)

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()

func _update_coins():
	_header.update_coins()
	_update_kicker()

## "HERO SKINS · 4 / 21 OWNED" over the title
func _update_kicker() -> void:
	var keys = _keys()
	var mine = keys.filter(func(k): return _owns(_id(k))).size()
	_owned_label.text = tr("%d / %d owned") % [mine, keys.size()]

func _screen() -> Vector2:
	return get_viewport_rect().size

## Columns of cards by the screen width (the stage keeps room in the middle)
func _fit_layout() -> void:
	var w = _screen().x
	_grid.columns = COLUMNS if w >= 1800 else (3 if w >= 1400 else 2)

func _on_screen_resized() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_fit_layout()
	if not get_viewport().gui_is_dragging():
		_build_side()  # the big card's size follows the height

func _hero() -> CharacterData:
	return _roster[_hero_index]

## Profile id of a card key on the current tab
func _id(key: String) -> String:
	match _kind:
		"hero":
			return Cosmetics.hero_id(key)
		"weapon":
			return Cosmetics.weapon_id(key)
	return key

## Owned for the hero / gun the cards are tried on (mastery ones are earned per hero / per gun)
func _owns(id: String) -> bool:
	match _kind:
		"hero":
			return PlayerProfile.owns(id)
		"weapon":
			return PlayerProfile.owns_for(id, "", _weapon_type)
	return PlayerProfile.owns_for(id, _hero().character_name)

func _is_on(id: String) -> bool:
	return PlayerProfile.is_equipped(id, _hero().character_name, _weapon_type if _kind == "weapon" else -1)

## Levels belong to heroes (and guns), not to things you wear: only hero cards show the level and
## the rank backdrop. A mastery skin / finish card shows its own rank's material, without a level.
func _show_mastery(card: ParallaxCard, key: String) -> void:
	if _kind == "hero":
		card.show_hero_mastery(key)
		return
	card.level = 0
	card.mastery = Mastery.tier_of_id(_id(key))

func _keys() -> Array:
	if _kind == "hero":
		return _roster.map(func(c): return c.character_name)
	return Cosmetics.catalog(_kind).keys()

# ---------------------------------------------------------------- cards

func _show_tab(index: int):
	_kind = KINDS[index]
	for i in _tab_buttons.size():
		UITheme.set_tab_active(_tab_buttons[i], i == index)
	match _kind:
		"hero":
			_selected = _hero().character_name
		"weapon":
			var w = PlayerProfile.weapon_finish_for(_weapon_type)
			_selected = "default" if w == "default" else w.substr(2)
		_:
			_selected = String(PlayerProfile.equipped_for(_hero().character_name)[_kind])
	_steps_label.text = tr(STEPS[_kind])
	_build_chips()
	_build_cards()
	_select(_selected)
	_update_kicker()

# ---------------------------------------------------------------- who the cards are tried on

## Portraits of the heroes (skins, hats) or pictures of the guns (finishes) above the stage
func _build_chips():
	_chips_caption.text = {"hero": "", "weapon": "Choose a gun"}.get(_kind, "Choose a hero")
	_chips_caption.visible = _kind != "hero"
	_chips.visible = _kind != "hero"
	# The model (and its ring) stand under the chips, not behind them
	var below = 0.0 if _kind == "hero" else 136.0
	_showcase.offset_top = below
	_stage_glow.offset_top = below
	if _kind == "weapon":
		_chips.show_guns()
	elif _kind != "hero":
		_chips.show_heroes(_roster)
	_mark_chips()

func _mark_chips():
	_chips.select(_weapon_type if _kind == "weapon" else _hero_index)

## The stage arrows: the previous / next hero or gun (on the heroes tab: the next hero card)
func _step(step: int):
	var count = RangedWeapon.WeaponType.size() if _kind == "weapon" else _roster.size()
	var current = _weapon_type if _kind == "weapon" else _hero_index
	_choose((current + step + count) % count)

func _choose(index: int):
	if get_viewport().gui_is_dragging():
		return  # never rebuild the grid under a card in the air
	if _kind == "weapon":
		_weapon_type = index
	else:
		_hero_index = index
	if _kind == "hero":
		_select(_hero().character_name)
		return
	_mark_chips()
	_build_cards()  # the card pictures show the new hero / gun
	_select(_selected)
	_update_kicker()  # mastery ones are owned per hero / gun

func _build_cards():
	for child in _grid.get_children():
		child.queue_free()
	_cards.clear()
	for key in _keys():
		var card = ParallaxCard.new()
		_cards[key] = card
		_style_card(card, key)
		# Selected already on press (ParallaxCard emits on mouse down): a drag right after that
		# only restyles the cards and rebuilds the side panel, never this grid
		card.pressed.connect(func(): if key != _selected: _select(key))
		card.drag_payload = key
		card.live = _live_source(key)
		_grid.add_child(card)
		_render_art(key, _art_to(card))

func _render_art(key: String, callback: Callable):
	var wear = PlayerProfile.equipped_for(_hero().character_name)
	match _kind:
		"hero":
			var hero_wear = PlayerProfile.equipped_for(key)
			_renderer.hero(key, hero_wear.skin, hero_wear.hat, callback)
		"skin":
			_renderer.hero(_hero().character_name, key, wear.hat, callback)
		"hat":
			_renderer.hero(_hero().character_name, wear.skin, key, callback)
		"weapon":
			_renderer.weapon(_weapon_type, _id(key), callback)

## The picture's callback for `card`, holding it only weakly: the grid / side panel is often rebuilt
## before ItemRenderer delivers, and a lambda holding a freed card printed "Lambda capture ... was freed"
func _art_to(card: ParallaxCard) -> Callable:
	var ref = weakref(card)
	return func(tex):
		var c = ref.get_ref()
		if c:
			c.set_art(tex)

## What the card's live 3D model is (ItemRenderer.live_begin)
func _live_source(key: String) -> Array:
	var wear = PlayerProfile.equipped_for(_hero().character_name)
	match _kind:
		"hero":
			var hero_wear = PlayerProfile.equipped_for(key)
			return ["hero", [key, hero_wear.skin, hero_wear.hat]]
		"skin":
			return ["hero", [_hero().character_name, key, wear.hat]]
		"hat":
			return ["hero", [_hero().character_name, wear.skin, key]]
	return ["gun", [_weapon_type, _id(key)]]

func _style_card(card: ParallaxCard, key: String):
	var id = _id(key)
	var tier = Cosmetics.tier_of(id)
	card.title = key if _kind == "hero" else Cosmetics.name_of(id)
	card.accent = _roster.filter(func(c): return c.character_name == key)[0].color if _kind == "hero" else Cosmetics.TIER_COLORS[tier]
	card.subtitle = Cosmetics.TIER_NAMES[tier]
	_show_mastery(card, key)
	var rank = Mastery.tier_of_id(id)
	if rank >= 0:
		card.accent = Mastery.tier_color(rank)
		card.subtitle = Mastery.tier_name(rank)
	elif _kind == "hero" and card.mastery >= 0:
		card.subtitle = Mastery.tier_name(card.mastery)
	var mine = _owns(id)
	card.locked = not mine
	if mine:
		card.badge = tr("Equipped") if (_kind != "hero" and _is_on(id)) else tr("Owned")
	elif rank >= 0:
		card.badge = tr("From Lv %d") % Mastery.TIER_LEVELS[rank]  # the hero / gun level that unlocks it
	else:
		card.badge = tr("%d coins") % Cosmetics.price_of(id)
	card.selected = key == _selected
	card.refresh()

func _select(key: String):
	if not key in _keys():
		key = _keys()[0]
	_selected = key
	if _kind == "hero":  # the hero card chosen here is the one the skins and hats are tried on
		for i in _roster.size():
			if _roster[i].character_name == key:
				_hero_index = i
	for k in _cards:
		_style_card(_cards[k], k)
	_build_side()

# ---------------------------------------------------------------- the chosen card

## The big card's size: as tall as the side panel allows (the rest of the panel is ~fixed)
func _big_size(with_abilities: bool) -> Vector2:
	var room = _screen().y - ScreenHeader.CONTENT_TOP - 20 - 62 - 36
	var rest = 310.0 if _kind != "hero" else (420.0 if with_abilities else 300.0)
	var h = clamp(room - rest, 200.0, 348.0)
	return Vector2(round(h * 250.0 / 348.0), round(h))

func _build_side():
	for child in _side.get_children():
		child.queue_free()
	_pad = null
	_need_label = null
	var id = _id(_selected)
	var with_abilities = _screen().y >= 820
	_big = ParallaxCard.new()
	_big.card_size = _big_size(with_abilities)
	_big.live = _live_source(_selected)
	_big.always_live = true
	_big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_side.add_child(_big)
	_style_card(_big, _selected)
	_big.selected = false
	_big.locked = false  # the big one shows it in full color
	_big.refresh()
	_render_art(_selected, _art_to(_big))
	UITheme.create_spacer(false, _side).custom_minimum_size.y = 2

	_mastery_line(_kind == "weapon", _selected if _kind == "hero" else _hero().character_name)
	if _kind == "hero":
		var data: CharacterData = _roster.filter(func(c): return c.character_name == _selected)[0]
		var facts = UITheme.create_label(tr("%d HP  ·  speed %.1f") % [int(data.base_health), data.base_speed], _side, UITheme.FONT_SMALL)
		facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		facts.add_theme_font_override("font", UITheme.font_bold())
		if with_abilities:
			for a in [data.active_ability, data.passive_ability]:
				if a:
					var line = UITheme.create_label(tr(a.ability_name) + ": " + tr(a.description), _side, UITheme.FONT_TINY)
					line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					line.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	_update_showcase()

	UITheme.create_spacer(false, _side).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hero = _hero().character_name
	if _kind != "hero":
		# Who it goes on: skins and hats are worn per hero, a finish goes on every gun
		var gun_name = tr(RangedWeapon.create_weapon(_weapon_type).item_name)
		var where = (tr("Only on: %s") % gun_name if Cosmetics.is_mastery(id) else tr("Goes on every gun")) if _kind == "weapon" else tr("For hero: %s") % tr(hero)
		var target = UITheme.create_label(where, _side, UITheme.FONT_SMALL)
		target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		target.add_theme_font_override("font", UITheme.font_bold())
		target.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY if _kind == "weapon" else _hero().color.lightened(0.3))

	# The slot a card is dragged into, then the button doing the same
	_pad = DropPad.new()
	_pad.accepts = func(payload): return payload is String and _cards.has(payload)
	_pad.dropped.connect(_on_pad_dropped)
	if _kind == "hero" and PlayerProfile.owns(id):
		_pad_state("OWNED", "", "✓", UITheme.ACCENT_SUCCESS, false)
	elif _kind != "hero" and _is_on(id):
		_pad_state("EQUIPPED", "", "✓", UITheme.ACCENT_SUCCESS, false)
	elif _owns(id):
		_pad_state("DRAG HERE TO EQUIP", "", "✓", UITheme.GOLD, true)
	elif Cosmetics.is_mastery(id):
		# Earned, not bought: play the hero / use the gun
		var rank = Mastery.tier_of_id(id)
		var how = tr("Reach level %d with this gun") % Mastery.TIER_LEVELS[rank] if _kind == "weapon" else tr("Reach level %d with %s") % [Mastery.TIER_LEVELS[rank], tr(hero)]
		_pad_state("LOCKED", how, "◆", Mastery.tier_color(rank).lightened(0.2), false)
	else:
		_pad_state("DRAG A CARD HERE TO BUY", tr("%d coins") % Cosmetics.price_of(id), "◉", UITheme.GOLD, true)
	_side.add_child(_pad)
	_pad.custom_minimum_size.y = 84

	# Buying is drag-only (the pad above): no button duplicates it. Still say why it's disabled.
	if not _owns(id) and not Cosmetics.is_mastery(id) and PlayerProfile.get_coins() < Cosmetics.price_of(id):
		_pad.enabled = false
		_need_label = UITheme.create_label("Not enough coins: play matches to earn them", _side, UITheme.FONT_SMALL)
		_need_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_need_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_need_label.add_theme_color_override("font_color", UITheme.ACCENT_DANGER.lerp(UITheme.TEXT_SECONDARY, 0.45))

func _pad_state(caption: String, detail: String, icon: String, color: Color, enabled: bool) -> void:
	_pad.caption = caption
	_pad.detail = detail
	_pad.icon = icon
	_pad.color = color
	_pad.enabled = enabled

## "Tomato  Lv 7 · Silver" and a bar to the next level, under the big card
func _mastery_line(gun: bool, hero: String) -> void:
	var p = PlayerProfile.weapon_progress(_weapon_type) if gun else PlayerProfile.hero_progress(hero)
	var who = tr(RangedWeapon.create_weapon(_weapon_type).item_name) if gun else tr(hero)
	var rank_col = Mastery.tier_color(p.tier) if p.tier >= 0 else UITheme.ACCENT_INFO
	var text = tr("%s  ·  Lv %d") % [who, p.level]
	if p.tier >= 0:
		text += "  ·  " + tr(Mastery.tier_name(p.tier))
	var line = UITheme.create_label(text, _side, UITheme.FONT_SMALL)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_override("font", UITheme.font_black())
	line.add_theme_color_override("font_color", rank_col.lightened(0.2))
	var bar = UITheme.create_progress_bar(float(p.need), float(p.need if p.max else p.into), rank_col, _side)
	bar.custom_minimum_size.y = 8
	var next_rank = Mastery.tier_for_level(p.level) + 1
	if next_rank < Mastery.TIERS.size():
		var next = UITheme.create_label(tr("%s at level %d") % [tr(Mastery.TIER_NAMES[next_rank]), Mastery.TIER_LEVELS[next_rank]], _side, UITheme.FONT_TINY)
		next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		next.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

## Put the chosen card's hero (with the skin / hat) or gun (with the finish) on the big preview
func _update_showcase():
	if _kind == "weapon":
		_stage_name.text = tr(RangedWeapon.create_weapon(_weapon_type).item_name)
		_stage_name.add_theme_color_override("font_color", UITheme.TEXT_TITLE)
	else:
		_stage_name.text = tr(_hero().character_name)
		_stage_name.add_theme_color_override("font_color", _hero().color.lightened(0.35))
	if _kind == "weapon":
		var model = LootVisuals.pickup_model(LootItem.ItemType.WEAPON, RangedWeapon.create_weapon(_weapon_type))
		var turn: Node3D = null
		if model:
			Cosmetics.apply_to_weapon(model, _id(_selected))
			turn = Node3D.new()
			turn.add_child(model)
			model.rotation = Vector3(deg_to_rad(8), deg_to_rad(-70), 0)  # side-on like the cards
		_showcase.show_model(turn, Cosmetics.TIER_COLORS[Cosmetics.tier_of(_id(_selected))], 1.3, true, 0.6)
		return
	var data = _hero()
	if _kind == "hero":
		data = _roster.filter(func(c): return c.character_name == _selected)[0]
	var wear = PlayerProfile.equipped_for(data.character_name)
	var skin_id = _selected if _kind == "skin" else wear.skin
	var hat_id = _selected if _kind == "hat" else wear.hat
	_showcase.show_character_with_wear(data, skin_id, hat_id)

# ---------------------------------------------------------------- buying and equipping

## The BUY / EQUIP buttons and the drop pad all end here: buy what can be bought, equip what is ours
func _act(from: Vector2) -> void:
	var id = _id(_selected)
	if (_kind == "hero" and PlayerProfile.owns(id)) or (_kind != "hero" and _is_on(id)):
		return
	if _owns(id):
		_equip()
	elif not Cosmetics.is_mastery(id):
		_buy(from)

func _equip() -> void:
	var id = _id(_selected)
	if _kind == "weapon":
		PlayerProfile.equip_weapon(id, _weapon_type)
	else:
		PlayerProfile.equip(id, _hero().character_name)
	_build_chips()  # the hero's portrait wears it now
	_select(_selected)
	if is_instance_valid(_big):
		_big.pop(false)
	Sfx.ui("ui_click")

## `from`: where the coins fly from (the button / the pad) to the wallet in the bar
func _buy(from: Vector2) -> void:
	var id = _id(_selected)
	var hero = _hero().character_name
	if PlayerProfile.get_coins() < Cosmetics.price_of(id) or not PlayerProfile.buy(id):
		_refuse()
		return
	if _kind == "weapon":
		PlayerProfile.equip_weapon(id, _weapon_type)
	elif _kind != "hero":
		PlayerProfile.equip(id, hero)
	_update_coins()
	ScreenEffects.flash(COIN_COLOR, 0.15, 0.15)
	_build_chips()
	_select(_selected)
	_coin_burst(from)
	if is_instance_valid(_big):
		_big.pop(true)

## Not enough coins: the pad shakes red, the line under the button flushes
func _refuse() -> void:
	if is_instance_valid(_pad):
		_pad.shake()
	if is_instance_valid(_need_label):
		_need_label.modulate = Color(1.8, 0.7, 0.7)
		_need_label.create_tween().tween_property(_need_label, "modulate", Color.WHITE, 0.8)

func _on_pad_dropped(payload) -> void:
	var from = _pad.get_global_rect().get_center() if is_instance_valid(_pad) else get_global_mouse_position()
	var key = String(payload)
	if key != _selected:
		_select(key)  # a fresh side panel (and pad) for that card
	_act(from)

## The stage takes cards too: try it on (and put it on when it is ours)
func _stage_can_drop(_at: Vector2, data) -> bool:
	return data is Dictionary and data.get("card_drag", false) and _cards.has(data.get("payload"))

func _stage_drop(_at: Vector2, data) -> void:
	var key = String(data.get("payload"))
	if key != _selected:
		_select(key)
	_stage_glow.burst()
	var id = _id(key)
	if _kind != "hero" and _owns(id) and not _is_on(id):
		_equip()
	else:
		Sfx.ui("ui_click")
		if is_instance_valid(_big):
			_big.pop(false)

## Gold coins burst out of `from` and rain into the wallet, which bumps when they arrive
func _coin_burst(from: Vector2) -> void:
	var to = _header.coins_label.get_global_rect().get_center() if _header.coins_label else Vector2(_screen().x - 100, 36)
	var origin = _fx.get_global_transform().affine_inverse()
	for i in 16:
		var coin = UITheme.create_icon("coin", null, 20 + randi() % 12, UITheme.GOLD.lightened(randf() * 0.3))
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx.add_child(coin)
		var half = coin.custom_minimum_size / 2.0
		coin.pivot_offset = half
		coin.position = origin * from - half
		var out = coin.position + Vector2(randf_range(-120, 120), randf_range(-130, -10))
		var t = coin.create_tween()
		t.tween_property(coin, "position", out, 0.26 + randf() * 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_interval(i * 0.025)
		t.tween_property(coin, "position", origin * to - half, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(coin, "scale", Vector2.ONE * 0.45, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(coin.queue_free)
	var wallet = _header.wallet
	if wallet:
		wallet.pivot_offset = wallet.size / 2.0
		var w = wallet.create_tween()
		w.tween_interval(0.72)
		w.tween_property(wallet, "scale", Vector2.ONE * 1.14, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		w.tween_property(wallet, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The pointer from the events themselves (get_global_mouse_position asks the OS, which a drag
## replayed by a test never moves)
func _input(event: InputEvent):
	if event is InputEventMouse:
		_mouse = event.position

func _process(_delta: float):
	# The stage's ring: a grid card in the air wakes it, over the stage it lights up
	var vp = get_viewport()
	var data = vp.gui_get_drag_data() if vp.gui_is_dragging() else null
	var carrying = data is Dictionary and data.get("card_drag", false) and _cards.has(data.get("payload"))
	var over = carrying and _stage.get_global_rect().has_point(_mouse)
	_stage_glow.want = 1.0 if over else (0.5 if carrying else 0.0)

## Over the 3D stage while a card is dragged: a golden ring on the podium and "DROP TO TRY ON"
## (looks only, lets every click through)
class StageGlow extends Control:
	var want: float = 0.0
	var _level: float = 0.0
	var _burst: float = 0.0
	var _time: float = 0.0
	var _caption: Label

	func _init():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready():
		_caption = UITheme.create_heading("DROP TO TRY ON", self)
		_caption.uppercase = true
		_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_caption.grow_vertical = Control.GROW_DIRECTION_BOTH
		_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_caption.add_theme_font_override("font", UITheme.font_black())
		_caption.add_theme_font_size_override("font_size", 24)
		_caption.add_theme_color_override("font_color", UITheme.GOLD)
		_caption.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.07, 0.9))
		_caption.add_theme_constant_override("outline_size", 8)
		_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_caption.modulate.a = 0.0

	## A flash of the ring (a card was dropped on the stage)
	func burst() -> void:
		_burst = 1.0

	func _process(delta: float):
		_time += delta
		var target = want
		if want > 0.0 and want < 1.0:
			target = want + 0.15 * sin(_time * 6.0)
		_level = lerp(_level, target, 1.0 - exp(-delta * 14.0))
		_burst = max(_burst - delta * 1.8, 0.0)
		_caption.modulate.a = clamp((_level - 0.55) / 0.35, 0.0, 1.0)
		# On the ring (the card in the air usually hangs higher, over the model)
		_caption.position.y = size.y * 0.8 - _caption.size.y / 2.0 + 4.0 * sin(_time * 3.0)
		if _level > 0.01 or _burst > 0.0:
			queue_redraw()
		elif _level > 0.0:
			_level = 0.0
			queue_redraw()

	func _draw():
		if _level <= 0.01 and _burst <= 0.0:
			return
		var c = Vector2(size.x / 2.0, size.y * 0.8)
		var r = min(size.x * 0.36, 210.0)
		draw_set_transform(c, 0.0, Vector2(1.0, 0.3))
		for i in 4:
			var a = (0.55 - i * 0.12) * _level
			draw_arc(Vector2.ZERO, r + i * 7.0, 0.0, TAU, 96, Color(UITheme.GOLD, a), 7.0 - i * 1.5, true)
		draw_circle(Vector2.ZERO, r, Color(UITheme.GOLD, 0.08 * _level))
		if _burst > 0.0:
			draw_arc(Vector2.ZERO, r * (1.0 + (1.0 - _burst) * 0.7), 0.0, TAU, 96, Color(UITheme.GOLD, _burst), 4.0 + 6.0 * _burst, true)
		draw_set_transform(Vector2.ZERO)
