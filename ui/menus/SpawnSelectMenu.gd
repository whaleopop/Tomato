## Spawn selection menu with hex map preview
extends Control
class_name SpawnSelectMenu

signal spawn_confirmed(hex_coords: Vector2i)
signal ready_toggled(is_ready: bool)

# UI elements
var map_container: Control = null
var hex_buttons: Dictionary = {}  # Vector2i -> Button
var info_label: Label = null
var ready_button: Button = null
var countdown_label: Label = null
var players_list: VBoxContainer = null

# State
var selected_spawn: Vector2i = Vector2i(-9999, -9999)
var is_ready: bool = false
var hex_grid_data: Dictionary = {}  # coords -> {biome, height}
var reserved_spawns: Array = []
var my_player_id: int = 0

# Map display settings
const HEX_BUTTON_SIZE: float = 24.0
const MAP_SCALE: float = 1.0

func _ready():
	# Only create UI if not already created by setup()
	if not map_container:
		_create_ui()

func _create_ui():
	# Background
	UITheme.create_background(self)

	# Main layout
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_preset(PRESET_FULL_RECT)
	main_hbox.set_anchor_and_offset(SIDE_LEFT, 0, 20)
	main_hbox.set_anchor_and_offset(SIDE_RIGHT, 1, -20)
	main_hbox.set_anchor_and_offset(SIDE_TOP, 0, 20)
	main_hbox.set_anchor_and_offset(SIDE_BOTTOM, 1, -20)
	main_hbox.add_theme_constant_override("separation", 20)
	add_child(main_hbox)

	# Left panel - Players list
	var left_panel = _create_left_panel()
	main_hbox.add_child(left_panel)

	# Center - Map
	var center_panel = _create_center_panel()
	main_hbox.add_child(center_panel)

	# Right panel - Info and actions
	var right_panel = _create_right_panel()
	main_hbox.add_child(right_panel)

func _create_left_panel() -> VBoxContainer:
	var panel = VBoxContainer.new()
	panel.custom_minimum_size.x = 200

	UITheme.create_title("PLAYERS", panel)

	UITheme.create_separator(panel)

	players_list = VBoxContainer.new()
	players_list.add_theme_constant_override("separation", 8)
	panel.add_child(players_list)

	return panel

func _create_center_panel() -> VBoxContainer:
	var panel = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	UITheme.create_title("SELECT SPAWN POINT", panel)

	# Countdown label (hidden by default)
	countdown_label = Label.new()
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 48)
	countdown_label.add_theme_color_override("font_color", UITheme.ACCENT_WARNING)
	countdown_label.visible = false
	panel.add_child(countdown_label)

	# Map scroll container
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	# Map container (will hold hex buttons)
	map_container = Control.new()
	map_container.custom_minimum_size = Vector2(800, 800)
	scroll.add_child(map_container)

	return panel

func _create_right_panel() -> VBoxContainer:
	var panel = VBoxContainer.new()
	panel.custom_minimum_size.x = 250
	panel.add_theme_constant_override("separation", 15)

	UITheme.create_title("SPAWN INFO", panel)

	UITheme.create_separator(panel)

	# Info about selected hex
	info_label = UITheme.create_label("Click on the map to select your spawn point", panel)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_label.custom_minimum_size.y = 100

	# Legend
	var legend_title = UITheme.create_label("LEGEND:", panel)
	legend_title.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	var legend = VBoxContainer.new()
	legend.add_theme_constant_override("separation", 5)
	panel.add_child(legend)

	_add_legend_item(legend, Color(0.3, 0.6, 0.3), "Grass")
	_add_legend_item(legend, Color(0.2, 0.5, 0.2), "Forest")
	_add_legend_item(legend, Color(0.7, 0.6, 0.4), "Desert")
	_add_legend_item(legend, Color(0.45, 0.42, 0.4), "Rock")
	_add_legend_item(legend, Color(0.2, 0.4, 0.7), "Water (blocked)")
	_add_legend_item(legend, Color(0.7, 0.2, 0.2), "Reserved")
	_add_legend_item(legend, Color(0.2, 0.8, 0.3), "Your selection")

	# Spacer
	UITheme.create_spacer(true, panel)

	# Ready button
	ready_button = UITheme.create_primary_button("READY", panel, Vector2(200, 55))
	ready_button.pressed.connect(_on_ready_pressed)
	ready_button.disabled = true  # Disabled until spawn selected

	# Back button
	var back_btn = UITheme.create_button("BACK", panel, Vector2(200, 45))
	back_btn.pressed.connect(_on_back_pressed)

	return panel

func _add_legend_item(parent: Control, color: Color, text: String):
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	parent.add_child(hbox)

	var color_rect = ColorRect.new()
	color_rect.color = color
	color_rect.custom_minimum_size = Vector2(20, 20)
	hbox.add_child(color_rect)

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(label)

func setup(grid_data: Dictionary, p_reserved_spawns: Array, player_id: int):
	hex_grid_data = grid_data
	reserved_spawns = p_reserved_spawns
	my_player_id = player_id

	# Ensure UI is created (may be called before _ready)
	if not map_container:
		_create_ui()

	_build_map()

func _build_map():
	# Clear existing hex buttons
	for btn in hex_buttons.values():
		btn.queue_free()
	hex_buttons.clear()

	if hex_grid_data.is_empty():
		return

	# Find bounds
	var min_q = 9999
	var max_q = -9999
	var min_r = 9999
	var max_r = -9999

	for coords_key in hex_grid_data.keys():
		var coords = coords_key as Vector2i
		min_q = mini(min_q, coords.x)
		max_q = maxi(max_q, coords.x)
		min_r = mini(min_r, coords.y)
		max_r = maxi(max_r, coords.y)

	# Center offset
	var center_offset = Vector2(400, 400)

	# Create hex buttons
	for coords_key in hex_grid_data.keys():
		var coords = coords_key as Vector2i
		var tile_data = hex_grid_data[coords_key]

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(HEX_BUTTON_SIZE, HEX_BUTTON_SIZE)
		btn.size = Vector2(HEX_BUTTON_SIZE, HEX_BUTTON_SIZE)

		# Calculate position (hex to screen)
		var screen_x = (coords.x * sqrt(3.0) + coords.y * sqrt(3.0) / 2.0) * HEX_BUTTON_SIZE * 0.6
		var screen_y = coords.y * 1.5 * HEX_BUTTON_SIZE * 0.6

		btn.position = Vector2(screen_x, screen_y) + center_offset

		# Style based on biome
		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4

		var biome = tile_data.get("biome", 0)
		match biome:
			0:  # GRASS
				style.bg_color = Color(0.3, 0.6, 0.3)
			1:  # FOREST
				style.bg_color = Color(0.2, 0.5, 0.2)
			2:  # DESERT
				style.bg_color = Color(0.7, 0.6, 0.4)
			3:  # ROCK
				style.bg_color = Color(0.45, 0.42, 0.4)
			4:  # WATER
				style.bg_color = Color(0.2, 0.4, 0.7)
				btn.disabled = true
			_:
				style.bg_color = Color(0.4, 0.4, 0.4)

		# Check if reserved
		if coords in reserved_spawns:
			style.bg_color = Color(0.7, 0.2, 0.2)
			btn.disabled = true

		btn.add_theme_stylebox_override("normal", style)

		var hover_style = style.duplicate()
		hover_style.bg_color = style.bg_color.lightened(0.2)
		btn.add_theme_stylebox_override("hover", hover_style)

		var pressed_style = style.duplicate()
		pressed_style.bg_color = style.bg_color.darkened(0.2)
		btn.add_theme_stylebox_override("pressed", pressed_style)

		var disabled_style = style.duplicate()
		disabled_style.bg_color = style.bg_color.darkened(0.3)
		btn.add_theme_stylebox_override("disabled", disabled_style)

		btn.pressed.connect(_on_hex_pressed.bind(coords))
		btn.mouse_entered.connect(_on_hex_hovered.bind(coords))

		map_container.add_child(btn)
		hex_buttons[coords] = btn

func _on_hex_pressed(coords: Vector2i):
	if coords in reserved_spawns:
		return

	var tile_data = hex_grid_data.get(coords, {})
	var biome = tile_data.get("biome", 0)

	# Can't spawn on water
	if biome == 4:  # WATER
		return

	# Deselect previous
	if selected_spawn.x != -9999 and hex_buttons.has(selected_spawn):
		_reset_hex_style(selected_spawn)

	# Select new
	selected_spawn = coords
	_highlight_selected(coords)

	# Update info
	var biome_name = _get_biome_name(biome)
	info_label.text = "Selected: %s\nCoordinates: (%d, %d)\nBiome: %s" % [
		"Spawn Point", coords.x, coords.y, biome_name
	]

	# Enable ready button
	ready_button.disabled = false

	# Emit signal for network
	spawn_confirmed.emit(coords)

func _on_hex_hovered(coords: Vector2i):
	var tile_data = hex_grid_data.get(coords, {})
	var biome = tile_data.get("biome", 0)
	var biome_name = _get_biome_name(biome)

	if coords in reserved_spawns:
		info_label.text = "RESERVED\nCoordinates: (%d, %d)" % [coords.x, coords.y]
	elif biome == 4:  # WATER
		info_label.text = "WATER (cannot spawn)\nCoordinates: (%d, %d)" % [coords.x, coords.y]
	elif coords == selected_spawn:
		info_label.text = "YOUR SPAWN POINT\nCoordinates: (%d, %d)\nBiome: %s" % [
			coords.x, coords.y, biome_name
		]
	else:
		info_label.text = "Available\nCoordinates: (%d, %d)\nBiome: %s" % [
			coords.x, coords.y, biome_name
		]

func _get_biome_name(biome: int) -> String:
	match biome:
		0: return "Grass"
		1: return "Forest"
		2: return "Desert"
		3: return "Rock"
		4: return "Water"
		_: return "Unknown"

func _highlight_selected(coords: Vector2i):
	if not hex_buttons.has(coords):
		return

	var btn = hex_buttons[coords]
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.8, 0.3)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(1, 1, 1)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)

func _reset_hex_style(coords: Vector2i):
	if not hex_buttons.has(coords):
		return

	var tile_data = hex_grid_data.get(coords, {})
	var biome = tile_data.get("biome", 0)

	var btn = hex_buttons[coords]
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	match biome:
		0: style.bg_color = Color(0.3, 0.6, 0.3)
		1: style.bg_color = Color(0.2, 0.5, 0.2)
		2: style.bg_color = Color(0.7, 0.6, 0.4)
		3: style.bg_color = Color(0.45, 0.42, 0.4)
		4: style.bg_color = Color(0.2, 0.4, 0.7)
		_: style.bg_color = Color(0.4, 0.4, 0.4)

	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = style.bg_color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover_style)

func _on_ready_pressed():
	is_ready = not is_ready

	if is_ready:
		ready_button.text = "NOT READY"
		var style = StyleBoxFlat.new()
		style.bg_color = UITheme.ACCENT_DANGER
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		ready_button.add_theme_stylebox_override("normal", style)
	else:
		ready_button.text = "READY"
		ready_button.remove_theme_stylebox_override("normal")

	ready_toggled.emit(is_ready)

func _on_back_pressed():
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/CharacterSelectScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/CharacterSelectScene.tscn")

func update_reserved_spawns(new_reserved: Array):
	reserved_spawns = new_reserved

	# Update all hex button styles
	for coords in hex_buttons.keys():
		if coords == selected_spawn:
			continue

		var btn = hex_buttons[coords]
		if coords in reserved_spawns:
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.7, 0.2, 0.2)
			style.corner_radius_top_left = 4
			style.corner_radius_top_right = 4
			style.corner_radius_bottom_left = 4
			style.corner_radius_bottom_right = 4
			btn.add_theme_stylebox_override("normal", style)
			btn.disabled = true
		else:
			_reset_hex_style(coords)
			var tile_data = hex_grid_data.get(coords, {})
			var biome = tile_data.get("biome", 0)
			btn.disabled = (biome == 4)  # Only water is disabled

func update_players_list(players_data: Dictionary):
	# Clear existing
	for child in players_list.get_children():
		child.queue_free()

	# Add player entries
	for player_id in players_data.keys():
		var data = players_data[player_id]
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		players_list.add_child(hbox)

		# Ready indicator
		var indicator = ColorRect.new()
		indicator.custom_minimum_size = Vector2(12, 12)
		indicator.color = UITheme.ACCENT_SUCCESS if data.get("ready", false) else Color(0.5, 0.5, 0.5)
		hbox.add_child(indicator)

		# Player name
		var name_lbl = Label.new()
		var is_me = player_id == my_player_id
		name_lbl.text = data.get("name", "Player %d" % player_id)
		if is_me:
			name_lbl.text += " (You)"
			name_lbl.add_theme_color_override("font_color", UITheme.ACCENT_PRIMARY)
		hbox.add_child(name_lbl)

func show_countdown(seconds: int):
	countdown_label.visible = true
	countdown_label.text = "Starting in %d..." % seconds

func hide_countdown():
	countdown_label.visible = false
