## Character selection: roster (left), 3D showcase (center), stats & abilities (right)
extends Control
class_name CharacterSelect

signal character_selected(character_data: CharacterData)

var available_characters: Array[CharacterData] = []
var selected_character: CharacterData = null
var selected_index: int = 0

# UI Elements
var roster_buttons: Array[Button] = []
var roster_scroll: ScrollContainer = null
var showcase: CharacterShowcase = null
var name_label: Label = null
var description_label: Label = null
var stats_container: VBoxContainer = null
var ability_container: VBoxContainer = null
var select_button: Button = null

func _ready():
	available_characters = CharacterRegistry.get_all()
	_create_ui()

	# Keep the previous pick when coming back from the lobby
	var start_index = 0
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.selected_character:
		for i in available_characters.size():
			if available_characters[i].character_name == game_manager.selected_character.character_name:
				start_index = i
	_select_character(start_index)

func get_selected_character() -> CharacterData:
	return selected_character

func _create_ui():
	UITheme.create_background(self)

	var margin = UITheme.create_screen_margin(self, 32)
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
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
	header.add_child(title_box)
	var title = UITheme.create_title("CHOOSE YOUR VEGGIE", title_box)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var hint = UITheme.create_label("← →  to browse   ·   Enter to confirm", title_box, UITheme.FONT_SMALL)
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	UITheme.create_spacer(false, header).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_server():
		UITheme.create_pill("Hosting", UITheme.ACCENT_PRIMARY, header).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	elif network_manager and network_manager.game_client:
		UITheme.create_pill("Connected", UITheme.ACCENT_INFO, header).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# ---- Body
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	root.add_child(body)

	# Roster
	var roster_card = UITheme.create_panel(body, 14)
	roster_card.custom_minimum_size.x = 250
	roster_scroll = ScrollContainer.new()
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_card.add_child(roster_scroll)
	var roster = VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation", 8)
	roster_scroll.add_child(roster)

	for i in available_characters.size():
		var character = available_characters[i]
		var button = UITheme.create_button("", roster, Vector2(0, 58))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "      %s" % character.character_name
		button.pressed.connect(_select_character.bind(i))

		# Colored orb in front of the name
		var orb = Panel.new()
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var orb_box = StyleBoxFlat.new()
		orb_box.bg_color = character.color
		orb_box.set_corner_radius_all(99)
		orb_box.shadow_color = Color(character.color, 0.6)
		orb_box.shadow_size = 6
		orb.add_theme_stylebox_override("panel", orb_box)
		orb.position = Vector2(16, 21)
		orb.size = Vector2(16, 16)
		button.add_child(orb)

		roster_buttons.append(button)

	# Showcase
	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	showcase = CharacterShowcase.new()
	showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(showcase)

	# Info card
	var info_card = UITheme.create_panel(body, 26)
	info_card.custom_minimum_size.x = 350
	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 12)
	info_card.add_child(info)

	name_label = UITheme.create_title("", info)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.add_theme_font_size_override("font_size", 40)

	description_label = UITheme.create_label("", info)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	UITheme.create_separator(info)
	UITheme.create_caption("Stats", info)
	stats_container = VBoxContainer.new()
	stats_container.add_theme_constant_override("separation", 8)
	info.add_child(stats_container)

	UITheme.create_caption("Abilities", info)
	ability_container = VBoxContainer.new()
	ability_container.add_theme_constant_override("separation", 12)
	info.add_child(ability_container)

	UITheme.create_spacer(true, info)

	select_button = UITheme.create_primary_button("SELECT & CONTINUE", info, Vector2(0, 60))
	select_button.pressed.connect(_on_select_pressed)

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

	for i in roster_buttons.size():
		UITheme.style_selectable(roster_buttons[i], i == index, available_characters[i].color)
	if roster_scroll and index < roster_buttons.size():
		roster_scroll.call_deferred("ensure_control_visible", roster_buttons[index])

	showcase.show_character(selected_character)
	_update_info_panel()

func _update_info_panel():
	var c = selected_character
	name_label.text = c.character_name
	name_label.add_theme_color_override("font_color", c.color.lightened(0.3))
	description_label.text = c.description if c.description else "A brave vegetable warrior!"

	for child in stats_container.get_children():
		child.queue_free()
	UITheme.create_stat_row("Health", c.base_health, 150.0, UITheme.ACCENT_SUCCESS, stats_container)
	UITheme.create_stat_row("Speed", c.base_speed, 8.0, UITheme.ACCENT_INFO, stats_container)

	for child in ability_container.get_children():
		child.queue_free()
	if c.active_ability:
		_add_ability_info(c.active_ability, "Active · F", UITheme.ACCENT_SECONDARY)
	if c.passive_ability:
		_add_ability_info(c.passive_ability, "Passive", UITheme.ACCENT_BEET)

func _add_ability_info(ability_data: AbilityData, tag: String, tag_color: Color):
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	ability_container.add_child(box)

	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	UITheme.create_heading(ability_data.ability_name, head)
	UITheme.create_pill(tag, tag_color, head).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var desc = UITheme.create_label(ability_data.description if ability_data.description else "No description", box, UITheme.FONT_SMALL)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _on_select_pressed():
	if not selected_character:
		return

	character_selected.emit(selected_character)

	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.selected_character = selected_character

	select_button.disabled = true
	var scene_transition = get_node_or_null("/root/SceneTransition")
	if scene_transition:
		scene_transition.fade_to_scene("res://scenes/SpawnSelectScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/SpawnSelectScene.tscn")

func _on_back_pressed():
	var scene_transition = get_node_or_null("/root/SceneTransition")
	if scene_transition:
		scene_transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")
