## Character selection (before a match and before the training ground), in the main menu's look:
## the header bar on top, every hero standing in 3D on a turning circle (HeroLineup: click one to
## choose it, drag to turn, wheel to step) with the portraits strip under it, and on the right the
## hero's card with stats, abilities and the golden button. Heroes we don't own can be bought right
## here: the BUY button, or drag the hero's card onto the golden pad under it.
extends Control
class_name CharacterSelect

signal character_selected(character_data: CharacterData)

const COIN_COLOR := Color(1.0, 0.8, 0.3)
const SIDE_WIDTH: int = 380

var available_characters: Array[CharacterData] = []
var selected_character: CharacterData = null
var selected_index: int = 0

# UI Elements
var header: ScreenHeader = null
var chips: HeroChips = null
var lineup: HeroLineup = null
var stage_name: Label = null
var stage_kicker: Label = null
var coins_label: Label = null       # the header's wallet
var info: VBoxContainer = null
var actions: VBoxContainer = null   # the button under the scrolling info
var select_button: Button = null

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MenuShell.hide_bar()  # the persistent menu bar stays off through the lobby and the match
	available_characters = CharacterRegistry.get_all()
	_create_ui()

	# Keep the previous pick when coming back from the lobby
	var start_index = -1
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.selected_character:
		for i in available_characters.size():
			if available_characters[i].character_name == game_manager.selected_character.character_name and _can_play(available_characters[i]):
				start_index = i
	if start_index < 0:  # the first hero we own
		for i in available_characters.size():
			if start_index < 0 and _can_play(available_characters[i]):
				start_index = i
	_select_character(max(start_index, 0), false)

func get_selected_character() -> CharacterData:
	return selected_character

## Owned heroes; the training ground lets you try them all
func _can_play(data: CharacterData) -> bool:
	var game_manager = get_node_or_null("/root/GameManager")
	return (game_manager and game_manager.training_mode) or PlayerProfile.owns_hero(data.character_name)

func _locked_list() -> Array:
	var locked: Array = []
	for c in available_characters:
		locked.append(not _can_play(c))
	return locked

func _create_ui():
	UITheme.create_background(self, true)

	# ---- Header: back, the title over what we are choosing for, hosting / connected, the wallet
	var game_manager = get_node_or_null("/root/GameManager")
	var kicker = "TRAINING GROUND"
	if not (game_manager and game_manager.training_mode):
		kicker = String(GameModes.info(GameModes.current()).name)
	header = ScreenHeader.make(self, "CHOOSE YOUR VEGGIE", kicker, true)
	header.back_pressed.connect(_on_back_pressed)
	coins_label = header.coins_label
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_server():
		header.add_right(UITheme.create_pill("Hosting", UITheme.ACCENT_PRIMARY)).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	elif network_manager and network_manager.game_client:
		header.add_right(UITheme.create_pill("Connected", UITheme.ACCENT_INFO)).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# ---- Body under the bar
	var body = HBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_top = ScreenHeader.CONTENT_TOP
	body.offset_left = ScreenHeader.SIDE_MARGIN
	body.offset_right = -ScreenHeader.SIDE_MARGIN
	body.offset_bottom = -24
	body.add_theme_constant_override("separation", 24)
	add_child(body)

	# Stage: the heroes in 3D, their name, the portraits strip
	var stage = Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(stage)
	var column = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 10)
	stage.add_child(column)
	lineup = HeroLineup.new()
	lineup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lineup.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lineup.hero_clicked.connect(_select_character)
	column.add_child(lineup)
	lineup.show_heroes(available_characters, _locked_list(), func(hero): return PlayerProfile.equipped_for(hero))

	# The name between the arrows: ‹ TOMATO ›
	var name_row = HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 22)
	column.add_child(name_row)
	var arrows: Array = []
	for step in [-1, 1]:
		var arrow = UITheme.create_icon_chip("chevron_left" if step < 0 else "chevron_right", null, Vector2(48, 56))
		arrow.add_theme_font_override("font", UITheme.font_black())
		arrow.add_theme_font_size_override("font_size", 32)
		arrow.pressed.connect(func(): _select_character((selected_index + step + available_characters.size()) % available_characters.size()))
		arrows.append(arrow)
	name_row.add_child(arrows[0])
	var names = VBoxContainer.new()
	names.add_theme_constant_override("separation", -6)
	names.custom_minimum_size.x = 300
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(names)
	name_row.add_child(arrows[1])
	stage_kicker = UITheme.create_label("", names, 13)
	stage_kicker.uppercase = true
	stage_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_kicker.add_theme_font_override("font", UITheme.font_black())
	stage_kicker.add_theme_color_override("font_color", UITheme.GOLD)
	stage_name = UITheme.create_title("", names)
	stage_name.uppercase = true
	stage_name.clip_text = true
	stage_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stage_kicker.clip_text = true
	stage_kicker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stage_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_name.add_theme_font_override("font", UITheme.font_black())
	stage_name.add_theme_font_size_override("font_size", 40)
	stage_name.add_theme_constant_override("shadow_offset_y", 3)
	stage_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))

	var strip = PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UITheme.navy_box(Color(0.03, 0.045, 0.09, 0.72), Color(1, 1, 1, 0.08), 18, 12, 10))
	strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(strip)
	chips = HeroChips.new()
	chips.chip_size = 54.0
	chips.chosen.connect(_select_character)
	strip.add_child(chips)
	chips.show_heroes(available_characters, _locked_list())
	# A flow container in a shrinking panel would fold into one column: give it the row's width
	var fit_strip = func():
		var needed = available_characters.size() * (chips.chip_size + 8.0)
		chips.custom_minimum_size.x = minf(needed, maxf(stage.size.x - 40.0, chips.chip_size))
	stage.resized.connect(fit_strip)
	fit_strip.call()

	# Over the 3D: how to use it
	var hint = UITheme.create_label("Click a hero or drag to turn the circle   ·   Left / Right   ·   Enter to confirm", stage, UITheme.FONT_SMALL)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.offset_top = 2
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	hint.add_theme_constant_override("shadow_offset_y", 1)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ---- The hero's card, stats, abilities and the button
	var side = UITheme.navy_panel(body, 18)
	side.custom_minimum_size.x = SIDE_WIDTH
	var side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 12)
	side.add_child(side_box)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_box.add_child(scroll)
	info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 12)
	scroll.add_child(info)
	actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	side_box.add_child(actions)

func _update_coins():
	header.update_coins()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_select_character((selected_index + 1) % available_characters.size())
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_select_character((selected_index - 1 + available_characters.size()) % available_characters.size())
	elif event.is_action_pressed("ui_accept"):
		_on_select_pressed()
	elif event.is_action_pressed("ui_cancel"):
		_on_back_pressed()

func _select_character(index: int, animate: bool = true):
	if index < 0 or index >= available_characters.size():
		return
	selected_index = index
	selected_character = available_characters[index]
	chips.select(index)
	lineup.select(index, animate)
	var c = selected_character
	stage_name.text = tr(c.character_name)
	if not _can_play(c):
		stage_kicker.text = tr("LOCKED") + "  ·  " + tr("%d coins") % Cosmetics.price_of(Cosmetics.hero_id(c.character_name))
	else:
		var p = PlayerProfile.hero_progress(c.character_name)
		stage_kicker.text = tr("Lv %d") % int(p.level) + "  ·  " + tr(Mastery.tier_name(int(p.tier)) if int(p.tier) >= 0 else Cosmetics.TIER_NAMES[Cosmetics.tier_of(Cosmetics.hero_id(c.character_name))])
	_build_info()

func _build_info():
	for child in info.get_children():
		child.queue_free()
	for child in actions.get_children():
		child.queue_free()
	var c = selected_character
	var id = Cosmetics.hero_id(c.character_name)
	var owned = PlayerProfile.owns_hero(c.character_name)
	var playable = _can_play(c)
	var price = Cosmetics.price_of(id)

	var card = ParallaxCard.new()
	card.card_size = Vector2(190, 264)
	card.title = c.character_name
	card.subtitle = Cosmetics.TIER_NAMES[Cosmetics.tier_of(id)]
	card.accent = c.color
	card.badge = tr("Owned") if owned else tr("%d coins") % price
	var wear = PlayerProfile.equipped_for(c.character_name)
	card.live = ["hero", [c.character_name, wear.skin, wear.hat]]
	card.show_hero_mastery(c.character_name)
	if card.mastery >= 0:
		card.subtitle = Mastery.tier_name(card.mastery)
	card.always_live = true
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not playable:
		card.drag_payload = c.character_name  # pick it up and drop it on the pad to buy
	info.add_child(card)
	var ref = weakref(card)  # gone when another hero is picked before the picture comes
	ItemRenderer.get_instance(get_tree()).hero(c.character_name, wear.skin, wear.hat, func(tex):
		var shown = ref.get_ref()
		if shown:
			shown.set_art(tex))

	var can_afford = PlayerProfile.get_coins() >= price
	if not playable:
		var pad = DropPad.new()
		pad.caption = "DRAG THE CARD HERE TO BUY"
		pad.detail = tr("%d coins") % price
		pad.icon = "◉"
		pad.enabled = can_afford
		var hero = c.character_name
		pad.accepts = func(payload): return payload == hero
		pad.dropped.connect(func(_payload): _buy(id))
		info.add_child(pad)

	var description = UITheme.create_label(c.description if c.description else "A brave vegetable warrior!", info, UITheme.FONT_SMALL)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	UITheme.create_stat_row("Health", c.base_health, 320.0, UITheme.ACCENT_SUCCESS, info)
	UITheme.create_stat_row("Speed", c.base_speed, 8.0, UITheme.ACCENT_INFO, info)
	if c.active_ability:
		_add_ability_info(c.active_ability, "Active · F", UITheme.ACCENT_SECONDARY)
	if c.passive_ability:
		_add_ability_info(c.passive_ability, "Passive", UITheme.ACCENT_BEET)

	if playable:
		select_button = UITheme.create_primary_button("SELECT & CONTINUE", actions, Vector2(0, 58))
		select_button.pressed.connect(_on_select_pressed)
		return
	# Not ours yet: buying is drag-only (the pad above); just say why it's out of reach
	select_button = null
	if not can_afford:
		var need = UITheme.create_label("Not enough coins: play matches to earn them", actions, UITheme.FONT_SMALL)
		need.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		need.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		need.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

## The BUY button and the drop pad: the hero becomes ours, the lineup unlocks it with a hop
func _buy(id: String):
	if not PlayerProfile.buy(id):
		return
	_update_coins()
	ScreenEffects.flash(COIN_COLOR, 0.15, 0.15)
	lineup.set_locked(selected_index, not _can_play(selected_character))
	chips.show_heroes(available_characters, _locked_list())
	_select_character(selected_index)

func _add_ability_info(ability_data: AbilityData, tag: String, tag_color: Color):
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	info.add_child(box)

	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	UITheme.create_heading(ability_data.ability_name, head)
	UITheme.create_pill(tag, tag_color, head).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var desc = UITheme.create_label(ability_data.description if ability_data.description else "No description", box, UITheme.FONT_SMALL)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

func _on_select_pressed():
	if not selected_character or not _can_play(selected_character):
		return

	character_selected.emit(selected_character)

	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.selected_character = selected_character
	if not (game_manager and game_manager.training_mode):
		# Remembered for next time (the main menu's dais, a party member's queue); profile, party
		# bar and the queue hear about it too when online (PlayerProfile._remote)
		PlayerProfile.set_preferred_hero(selected_character.character_name)

	if select_button:
		select_button.disabled = true
	var next_scene = "res://scenes/SpawnSelectScene.tscn"
	if game_manager and game_manager.matchmaking:
		next_scene = MatchmakingScreen.SCENE  # the queue, then the landing pick
	elif game_manager and game_manager.training_mode:
		next_scene = "res://scenes/GameScene.tscn"
	var scene_transition = get_node_or_null("/root/SceneTransition")
	if scene_transition:
		scene_transition.fade_to_scene(next_scene)
	else:
		get_tree().change_scene_to_file(next_scene)

func _on_back_pressed():
	var scene_transition = get_node_or_null("/root/SceneTransition")
	if scene_transition:
		scene_transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")
