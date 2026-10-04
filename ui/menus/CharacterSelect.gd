## Character selection (before a match and before the training ground), laid out like the shop:
## hero portraits above a big 3D stage you can turn (center), the hero's card with stats,
## abilities and the button (right). Heroes we don't own can be bought right here.
extends Control
class_name CharacterSelect

signal character_selected(character_data: CharacterData)

const COIN_COLOR := Color(1.0, 0.8, 0.3)

var available_characters: Array[CharacterData] = []
var selected_character: CharacterData = null
var selected_index: int = 0

# UI Elements
var chips: HeroChips = null
var showcase: CharacterShowcase = null
var stage_name: Label = null
var coins_label: Label = null
var info: VBoxContainer = null
var select_button: Button = null

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	_select_character(max(start_index, 0))

func get_selected_character() -> CharacterData:
	return selected_character

## Owned heroes; the training ground lets you try them all
func _can_play(data: CharacterData) -> bool:
	var game_manager = get_node_or_null("/root/GameManager")
	return (game_manager and game_manager.training_mode) or PlayerProfile.owns_hero(data.character_name)

func _create_ui():
	UITheme.create_background(self)

	var margin = UITheme.create_screen_margin(self, 32)
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# ---- Header
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)

	var back_button = UITheme.create_button("←  BACK", header, Vector2(130, 46))
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(_on_back_pressed)

	var title_box = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	var title = UITheme.create_title("CHOOSE YOUR VEGGIE", title_box)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var hint = UITheme.create_label("Click a portrait or use ← →   ·   Enter to confirm", title_box, UITheme.FONT_NORMAL)
	hint.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_server():
		UITheme.create_pill("Hosting", UITheme.ACCENT_PRIMARY, header).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	elif network_manager and network_manager.game_client:
		UITheme.create_pill("Connected", UITheme.ACCENT_INFO, header).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var wallet = PanelContainer.new()
	wallet.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.8), Color(COIN_COLOR, 0.8), 99, 22, 8))
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(wallet)
	coins_label = UITheme.create_heading("", wallet)
	coins_label.add_theme_color_override("font_color", COIN_COLOR.lightened(0.3))
	_update_coins()

	# ---- Body
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	root.add_child(body)

	# Stage: portraits on top, the hero you can turn, arrows at the sides, the name below
	var stage = Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(stage)
	showcase = CharacterShowcase.new()
	showcase.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	showcase.interactive = true
	stage.add_child(showcase)
	var top = VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 4
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(top)
	var caption = UITheme.create_label("Choose a hero", top, UITheme.FONT_SMALL)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.uppercase = true
	caption.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	chips = HeroChips.new()
	chips.chosen.connect(_select_character)
	top.add_child(chips)
	var dim: Array = []
	for c in available_characters:
		dim.append(not _can_play(c))
	chips.show_heroes(available_characters, dim)
	for step in [-1, 1]:
		var arrow = UITheme.create_button("◀" if step < 0 else "▶", stage, Vector2(56, 72))
		arrow.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
		arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT if step < 0 else Control.PRESET_CENTER_RIGHT)
		arrow.grow_horizontal = Control.GROW_DIRECTION_END if step < 0 else Control.GROW_DIRECTION_BEGIN
		arrow.grow_vertical = Control.GROW_DIRECTION_BOTH
		arrow.pressed.connect(func(): _select_character((selected_index + step + available_characters.size()) % available_characters.size()))
	stage_name = UITheme.create_title("", stage)
	stage_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	stage_name.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stage_name.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stage_name.offset_bottom = -40
	stage_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_name.add_theme_constant_override("shadow_offset_y", 3)
	stage_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	stage_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var turn_hint = UITheme.create_label("Drag to turn  ·  wheel to zoom  ·  double click to reset", stage, UITheme.FONT_SMALL)
	turn_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	turn_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	turn_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	turn_hint.offset_bottom = -12
	turn_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	turn_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The hero's card, like the shop's side panel
	var info_card = UITheme.create_panel(body, 20)
	info_card.custom_minimum_size.x = 360
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_card.add_child(scroll)
	info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 10)
	scroll.add_child(info)

func _update_coins():
	coins_label.text = tr("%d coins") % PlayerProfile.get_coins()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_select_character((selected_index + 1) % available_characters.size())
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_select_character((selected_index - 1 + available_characters.size()) % available_characters.size())
	elif event.is_action_pressed("ui_accept"):
		_on_select_pressed()
	elif event.is_action_pressed("ui_cancel"):
		_on_back_pressed()

func _select_character(index: int):
	if index < 0 or index >= available_characters.size():
		return
	selected_index = index
	selected_character = available_characters[index]
	chips.select(index)
	var wear = PlayerProfile.equipped_for(selected_character.character_name)
	showcase.show_character_with_wear(selected_character, wear.skin, wear.hat)
	stage_name.text = tr(selected_character.character_name)
	stage_name.add_theme_color_override("font_color", selected_character.color.lightened(0.35))
	_build_info()

func _build_info():
	for child in info.get_children():
		child.queue_free()
	var c = selected_character
	var id = Cosmetics.hero_id(c.character_name)
	var owned = PlayerProfile.owns_hero(c.character_name)

	var card = ParallaxCard.new()
	card.card_size = Vector2(200, 278)
	card.title = c.character_name
	card.subtitle = Cosmetics.TIER_NAMES[Cosmetics.tier_of(id)]
	card.accent = c.color
	card.badge = tr("Owned") if owned else tr("%d coins") % Cosmetics.price_of(id)
	var wear = PlayerProfile.equipped_for(c.character_name)
	card.live = ["hero", [c.character_name, wear.skin, wear.hat]]
	card.show_hero_mastery(c.character_name)
	if card.mastery >= 0:
		card.subtitle = Mastery.tier_name(card.mastery)
	card.always_live = true
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	info.add_child(card)
	ItemRenderer.get_instance(get_tree()).hero(c.character_name, wear.skin, wear.hat, func(tex): if is_instance_valid(card): card.set_art(tex))

	var description = UITheme.create_label(c.description if c.description else "A brave vegetable warrior!", info, UITheme.FONT_SMALL)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.create_stat_row("Health", c.base_health, 320.0, UITheme.ACCENT_SUCCESS, info)
	UITheme.create_stat_row("Speed", c.base_speed, 8.0, UITheme.ACCENT_INFO, info)
	if c.active_ability:
		_add_ability_info(c.active_ability, "Active · F", UITheme.ACCENT_SECONDARY)
	if c.passive_ability:
		_add_ability_info(c.passive_ability, "Passive", UITheme.ACCENT_BEET)

	UITheme.create_spacer(true, info).size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _can_play(c):
		select_button = UITheme.create_primary_button("SELECT & CONTINUE", info, Vector2(0, 58))
		select_button.pressed.connect(_on_select_pressed)
		return
	# Not ours yet: buy it right here, like in the shop
	var price = Cosmetics.price_of(id)
	select_button = UITheme.create_primary_button(tr("BUY FOR %d") % price, info, Vector2(0, 58))
	if PlayerProfile.get_coins() < price:
		select_button.disabled = true
		var need = UITheme.create_label("Not enough coins: play matches to earn them", info, UITheme.FONT_SMALL)
		need.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		need.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		need.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	select_button.pressed.connect(func():
		if PlayerProfile.buy(id):
			_update_coins()
			ScreenEffects.flash(COIN_COLOR, 0.15, 0.15)
			var dim: Array = []
			for h in available_characters:
				dim.append(not _can_play(h))
			chips.show_heroes(available_characters, dim)
			_select_character(selected_index))

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
	var online = get_node_or_null("/root/Online")
	if online and not (game_manager and game_manager.training_mode):
		online.set_hero(selected_character.character_name)  # profile, party bar, the party's queue

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
