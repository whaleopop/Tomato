## Spawn point selection on minimap
extends Control
class_name SpawnSelect

signal spawn_selected(position: Vector3)

var map_viewport: SubViewport = null
var map_camera: Camera3D = null
var hex_grid: HexGrid = null
var map_container: Control = null

var selected_position: Vector3 = Vector3.ZERO
var spawn_marker: Control = null
var countdown_timer: float = 30.0
var countdown_label: Label = null
var is_position_selected: bool = false

# Map parameters
var map_size: float = 50.0
var map_view_size: Vector2 = Vector2(500, 500)

func _ready():
	_create_ui()
	_setup_map_viewport()
	_generate_preview_map()

func _process(delta: float):
	if countdown_timer > 0:
		countdown_timer -= delta
		_update_countdown()

		if countdown_timer <= 0:
			_confirm_spawn()

	# Pulse animation on marker
	if spawn_marker and spawn_marker.visible:
		var pulse = (sin(Time.get_ticks_msec() * 0.005) + 1.0) * 0.5
		spawn_marker.modulate = Color(1, 0.3 + pulse * 0.4, 0.3 + pulse * 0.2)

func _create_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Main layout
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_FULL_RECT)
	vbox.set_anchor_and_offset(SIDE_LEFT, 0, 20)
	vbox.set_anchor_and_offset(SIDE_RIGHT, 1, -20)
	vbox.set_anchor_and_offset(SIDE_TOP, 0, 20)
	vbox.set_anchor_and_offset(SIDE_BOTTOM, 1, -20)
	vbox.add_theme_constant_override("separation", 15)
	add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "SELECT LANDING ZONE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	vbox.add_child(title)

	# Instructions
	var instructions = Label.new()
	instructions.text = "Click on the map to choose your spawn location"
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size", 16)
	instructions.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(instructions)

	# Map container (centered)
	var center_container = CenterContainer.new()
	center_container.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(center_container)

	# Map frame with border
	var map_frame = PanelContainer.new()
	map_frame.custom_minimum_size = map_view_size
	center_container.add_child(map_frame)

	# Style for frame
	var frame_style = StyleBoxFlat.new()
	frame_style.bg_color = Color(0.15, 0.15, 0.2)
	frame_style.border_width_left = 3
	frame_style.border_width_right = 3
	frame_style.border_width_top = 3
	frame_style.border_width_bottom = 3
	frame_style.border_color = Color(0.4, 0.4, 0.5)
	frame_style.corner_radius_top_left = 5
	frame_style.corner_radius_top_right = 5
	frame_style.corner_radius_bottom_left = 5
	frame_style.corner_radius_bottom_right = 5
	map_frame.add_theme_stylebox_override("panel", frame_style)

	# Map container for viewport
	map_container = Control.new()
	map_container.set_anchors_preset(PRESET_FULL_RECT)
	map_container.gui_input.connect(_on_map_input)
	map_frame.add_child(map_container)

	# Spawn marker (overlay on top of map)
	spawn_marker = _create_spawn_marker()
	spawn_marker.visible = false
	map_container.add_child(spawn_marker)

	# Bottom panel
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_theme_constant_override("separation", 50)
	vbox.add_child(bottom_hbox)

	# Countdown
	var countdown_container = VBoxContainer.new()
	bottom_hbox.add_child(countdown_container)

	var countdown_title = Label.new()
	countdown_title.text = "TIME REMAINING"
	countdown_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_title.add_theme_font_size_override("font_size", 14)
	countdown_container.add_child(countdown_title)

	countdown_label = Label.new()
	countdown_label.text = "30"
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 48)
	countdown_label.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	countdown_container.add_child(countdown_label)

	# Confirm button
	var confirm_button = Button.new()
	confirm_button.text = "CONFIRM LANDING"
	confirm_button.custom_minimum_size = Vector2(200, 60)
	confirm_button.add_theme_font_size_override("font_size", 18)
	confirm_button.pressed.connect(_confirm_spawn)
	bottom_hbox.add_child(confirm_button)

func _create_spawn_marker() -> Control:
	var marker = Control.new()
	marker.custom_minimum_size = Vector2(40, 40)
	marker.size = Vector2(40, 40)

	# Center circle
	var circle = ColorRect.new()
	circle.color = Color(1, 0.3, 0.3, 0.9)
	circle.size = Vector2(16, 16)
	circle.position = Vector2(12, 12)
	marker.add_child(circle)

	# Outer ring (using multiple small rectangles to simulate)
	var ring_color = Color(1, 1, 1, 0.8)
	for i in range(8):
		var angle = i * TAU / 8
		var line = ColorRect.new()
		line.color = ring_color
		line.size = Vector2(2, 8)
		line.position = Vector2(19 + cos(angle) * 15, 16 + sin(angle) * 15)
		line.rotation = angle + PI / 2
		marker.add_child(line)

	# Crosshair lines
	var h_line = ColorRect.new()
	h_line.color = Color.WHITE
	h_line.size = Vector2(40, 2)
	h_line.position = Vector2(0, 19)
	marker.add_child(h_line)

	var v_line = ColorRect.new()
	v_line.color = Color.WHITE
	v_line.size = Vector2(2, 40)
	v_line.position = Vector2(19, 0)
	marker.add_child(v_line)

	return marker

func _setup_map_viewport():
	# SubViewportContainer
	var viewport_container = SubViewportContainer.new()
	viewport_container.set_anchors_preset(PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_container.add_child(viewport_container)
	map_container.move_child(viewport_container, 0)  # Move behind marker

	map_viewport = SubViewport.new()
	map_viewport.size = Vector2i(int(map_view_size.x), int(map_view_size.y))
	map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(map_viewport)

	# Top-down camera
	map_camera = Camera3D.new()
	map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	map_camera.size = map_size
	map_camera.position = Vector3(0, 100, 0)
	map_camera.rotation = Vector3(deg_to_rad(-90), 0, 0)
	map_viewport.add_child(map_camera)

	# Lighting
	var light = DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-60), deg_to_rad(30), 0)
	light.light_energy = 1.2
	map_viewport.add_child(light)

	# Ambient light
	var world_env = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.15, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5)
	env.ambient_light_energy = 0.8
	world_env.environment = env
	map_viewport.add_child(world_env)

func _generate_preview_map():
	# Get seed from game manager or server
	var seed_value = 12345  # Default preview seed

	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_meta("map_seed"):
		seed_value = game_manager.get_meta("map_seed")

	# Generate map
	var hex_generator = HexGenerator.new()
	hex_grid = hex_generator.generate_grid(15, seed_value)
	map_viewport.add_child(hex_grid)

func _update_countdown():
	var remaining = int(ceil(countdown_timer))
	countdown_label.text = str(remaining)

	# Color changes as time runs out
	if remaining <= 5:
		countdown_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	elif remaining <= 10:
		countdown_label.add_theme_color_override("font_color", Color(1, 0.6, 0.2))

func _on_map_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos = event.position
		var world_pos = _screen_to_world(local_pos)

		# Validate spawn position
		if _is_valid_spawn(world_pos):
			selected_position = world_pos
			is_position_selected = true

			# Update marker position
			spawn_marker.position = local_pos - spawn_marker.size / 2
			spawn_marker.visible = true

			# Selection animation
			var tween = create_tween()
			spawn_marker.scale = Vector2(1.5, 1.5)
			tween.tween_property(spawn_marker, "scale", Vector2.ONE, 0.2)
			tween.set_ease(Tween.EASE_OUT)

			print("[SpawnSelect] Selected position: %s" % world_pos)
		else:
			print("[SpawnSelect] Invalid spawn location (water or destroyed)")

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	# Convert screen position to world position
	var normalized = screen_pos / map_view_size - Vector2(0.5, 0.5)
	normalized *= 2.0

	var world_x = normalized.x * (map_size / 2)
	var world_z = normalized.y * (map_size / 2)

	return Vector3(world_x, 0, world_z)

func _is_valid_spawn(world_pos: Vector3) -> bool:
	if not hex_grid:
		return true

	var hex_coords = hex_grid.world_to_hex(world_pos)
	var tile = hex_grid.get_tile(hex_coords)

	if not tile:
		return false
	if tile.is_destroyed:
		return false
	if tile.biome_type == HexTile.BiomeType.WATER:
		return false

	return true

func _confirm_spawn():
	if not is_position_selected:
		# Random spawn if not selected
		selected_position = _get_random_spawn_position()

	# Calculate proper Y position
	if hex_grid:
		var hex_coords = hex_grid.world_to_hex(selected_position)
		var tile = hex_grid.get_tile(hex_coords)
		if tile:
			selected_position.y = tile.height * HexTile.HEX_HEIGHT + HexTile.HEX_HEIGHT + 50.0

	# Store spawn position
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.set_meta("spawn_position", selected_position)

	spawn_selected.emit(selected_position)

	print("[SpawnSelect] Confirmed spawn at: %s" % selected_position)

	# Transition to drop sequence
	var scene_transition = get_node_or_null("/root/SceneTransition")
	if scene_transition:
		scene_transition.fade_to_scene("res://scenes/DropSequenceScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/DropSequenceScene.tscn")

func _get_random_spawn_position() -> Vector3:
	if not hex_grid:
		return Vector3.ZERO

	var valid_tiles: Array = []
	for tile in hex_grid.get_all_tiles():
		if not tile.is_destroyed and tile.biome_type != HexTile.BiomeType.WATER:
			valid_tiles.append(tile)

	if valid_tiles.is_empty():
		return Vector3.ZERO

	var random_tile = valid_tiles[randi() % valid_tiles.size()]
	return hex_grid.hex_to_world(random_tile.hex_coords)
