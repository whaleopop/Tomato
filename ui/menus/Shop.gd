## Shop: heroes, hero skins, hats and gun finishes as collectible cards (ParallaxCard: move the
## mouse over a card and it tilts, its layers slide). Pictures are rendered from the real models
## (ItemRenderer). The chosen card shows big on the right with the buy / equip button. Skins and
## hats are bought once and put on per hero; a gun finish goes on every gun. Coins: PlayerProfile.
extends Control
class_name Shop

signal closed

const TABS = ["Heroes", "Hero skins", "Hats", "Weapon finishes"]
const KINDS = ["hero", "skin", "hat", "weapon"]
const COIN_COLOR := Color(1.0, 0.8, 0.3)
const COLUMNS: int = 4

var _kind: String = "hero"
var _roster: Array[CharacterData] = []
var _hero_index: int = 0          # the hero skins / hats are shown and put on
var _weapon_type: int = 0         # the gun finishes are shown on
var _selected: String = ""        # card key (hero name, skin / hat id, finish name)
var _tab_buttons: Array[Button] = []
var _grid: GridContainer
var _side: VBoxContainer
var _big: ParallaxCard
var _coins_label: Label
var _cards: Dictionary = {}       # key -> ParallaxCard
var _renderer: ItemRenderer
var _showcase: CharacterShowcase = null  # the big 3D preview in the middle
var _steps_label: Label                  # what to do on this tab, under the title
var _chips_caption: Label
var _chips: HeroChips                    # heroes (skins, hats) or guns (finishes) to try the cards on
var _stage_name: Label

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

	var margin = UITheme.create_screen_margin(self, 28)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	column.add_child(header)
	var back = UITheme.create_button("←  BACK", header, Vector2(130, 46))
	back.pressed.connect(close)
	var titles = VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var title = UITheme.create_title("SHOP", titles)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_steps_label = UITheme.create_label("", titles, UITheme.FONT_NORMAL)
	_steps_label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	var wallet = PanelContainer.new()
	wallet.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.8), Color(COIN_COLOR, 0.8), 99, 22, 8))
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(wallet)
	_coins_label = UITheme.create_heading("", wallet)
	_coins_label.add_theme_color_override("font_color", COIN_COLOR.lightened(0.3))

	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	column.add_child(tabs)
	for i in TABS.size():
		var tab_button = UITheme.create_button(TABS[i], tabs, Vector2(180, 44))
		tab_button.pressed.connect(_show_tab.bind(i))
		_tab_buttons.append(tab_button)

	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	column.add_child(body)

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var pad = MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(side, 40)  # room for the hover zoom and the tilt
	scroll.add_child(pad)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	pad.add_child(_grid)

	# The big 3D preview between the cards and the side panel: drag to turn, wheel to zoom.
	# Above it: who the cards are tried on (hero / gun chips), arrows at its sides do the same.
	var stage = Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(stage)
	_showcase = CharacterShowcase.new()
	_showcase.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_showcase.interactive = true
	stage.add_child(_showcase)
	var top = VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 8
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(top)
	_chips_caption = UITheme.create_label("", top, UITheme.FONT_SMALL)
	_chips_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chips_caption.uppercase = true
	_chips_caption.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	_chips = HeroChips.new()
	_chips.chosen.connect(_choose)
	top.add_child(_chips)
	_stage_name = UITheme.create_title("", stage)
	_stage_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_stage_name.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stage_name.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stage_name.offset_bottom = -40  # on the stage disc, above the hint
	_stage_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_name.add_theme_constant_override("shadow_offset_y", 3)
	_stage_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	for step in [-1, 1]:
		var arrow = UITheme.create_button("◀" if step < 0 else "▶", stage, Vector2(56, 72))
		arrow.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
		arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT if step < 0 else Control.PRESET_CENTER_RIGHT)
		arrow.grow_horizontal = Control.GROW_DIRECTION_END if step < 0 else Control.GROW_DIRECTION_BEGIN
		arrow.grow_vertical = Control.GROW_DIRECTION_BOTH
		arrow.pressed.connect(_step.bind(step))
	var hint = UITheme.create_label("Drag to turn  ·  wheel to zoom  ·  double click to reset", stage, UITheme.FONT_SMALL)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -12
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var side_panel = UITheme.create_panel(body, 18)
	side_panel.custom_minimum_size.x = 340
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 10)
	side_panel.add_child(_side)

	_update_coins()
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

func _update_coins():
	_coins_label.text = tr("%d coins") % PlayerProfile.get_coins()

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

func _keys() -> Array:
	if _kind == "hero":
		return _roster.map(func(c): return c.character_name)
	return Cosmetics.catalog(_kind).keys()

# ---------------------------------------------------------------- cards

func _show_tab(index: int):
	_kind = KINDS[index]
	for i in _tab_buttons.size():
		UITheme.style_selectable(_tab_buttons[i], i == index)
	match _kind:
		"hero":
			_selected = _hero().character_name
		"weapon":
			var w = PlayerProfile.equipped_for(_hero().character_name).weapon
			_selected = "default" if w == "default" else w.substr(2)
		_:
			_selected = String(PlayerProfile.equipped_for(_hero().character_name)[_kind])
	_steps_label.text = tr(STEPS[_kind])
	_build_chips()
	_build_cards()
	_select(_selected)

# ---------------------------------------------------------------- who the cards are tried on

## Portraits of the heroes (skins, hats) or pictures of the guns (finishes) above the stage
func _build_chips():
	_chips_caption.text = {"hero": "", "weapon": "Choose a gun"}.get(_kind, "Choose a hero")
	_chips_caption.visible = _kind != "hero"
	_chips.visible = _kind != "hero"
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

func _build_cards():
	for child in _grid.get_children():
		child.queue_free()
	_cards.clear()
	for key in _keys():
		var card = ParallaxCard.new()
		_cards[key] = card
		_style_card(card, key)
		card.pressed.connect(_select.bind(key))
		card.live = _live_source(key)
		_grid.add_child(card)
		_render_art(key, func(tex): if is_instance_valid(card): card.set_art(tex))

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
	card.locked = not PlayerProfile.owns(id)
	if PlayerProfile.owns(id):
		card.badge = tr("Equipped") if (_kind != "hero" and PlayerProfile.is_equipped(id, _hero().character_name)) else tr("Owned")
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

func _build_side():
	for child in _side.get_children():
		child.queue_free()
	var id = _id(_selected)
	_big = ParallaxCard.new()
	_big.card_size = Vector2(250, 348)
	_big.live = _live_source(_selected)
	_big.always_live = true
	_big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_side.add_child(_big)
	_style_card(_big, _selected)
	_big.selected = false
	_big.locked = false  # the big one shows it in full color
	_big.refresh()
	var big = _big
	_render_art(_selected, func(tex): if is_instance_valid(big): big.set_art(tex))

	if _kind == "hero":
		var data: CharacterData = _roster.filter(func(c): return c.character_name == _selected)[0]
		var facts = UITheme.create_label(tr("%d HP  ·  speed %.1f") % [int(data.base_health), data.base_speed], _side, UITheme.FONT_SMALL)
		facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
		var target = UITheme.create_label(tr("Goes on every gun") if _kind == "weapon" else tr("For hero: %s") % tr(hero), _side, UITheme.FONT_NORMAL)
		target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		target.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY if _kind == "weapon" else _hero().color.lightened(0.3))
	if _kind == "hero" and PlayerProfile.owns(id):
		var owned = UITheme.create_button("OWNED", _side, Vector2(0, 52))
		owned.disabled = true
	elif PlayerProfile.is_equipped(id, hero):
		var on = UITheme.create_button("EQUIPPED", _side, Vector2(0, 52))
		on.disabled = true
	elif PlayerProfile.owns(id):
		var equip = UITheme.create_primary_button("EQUIP", _side, Vector2(0, 52))
		equip.pressed.connect(func():
			PlayerProfile.equip(id, hero)
			_build_chips()  # the hero's portrait wears it now
			_select(_selected))
	else:
		var price = Cosmetics.price_of(id)
		var buy = UITheme.create_primary_button(tr("BUY FOR %d") % price, _side, Vector2(0, 52))
		if PlayerProfile.get_coins() < price:
			buy.disabled = true
			var need = UITheme.create_label("Not enough coins: play matches to earn them", _side, UITheme.FONT_SMALL)
			need.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		buy.pressed.connect(func():
			if PlayerProfile.buy(id):
				if _kind != "hero":
					PlayerProfile.equip(id, hero)
				_update_coins()
				ScreenEffects.flash(COIN_COLOR, 0.15, 0.15)
				_build_chips()
				_select(_selected))

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
