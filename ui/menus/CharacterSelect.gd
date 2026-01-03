## Enhanced character selection menu with 3D preview
extends Control
class_name CharacterSelect

signal character_selected(character_data: CharacterData)

var available_characters: Array[CharacterData] = []
var selected_character: CharacterData = null
var selected_index: int = 0

# UI Elements
var character_list: ItemList = null
var preview_viewport: SubViewport = null
var preview_camera: Camera3D = null
var preview_model: Node3D = null
var preview_container: SubViewportContainer = null

# Info panel elements
var name_label: Label = null
var description_label: RichTextLabel = null
var stats_container: VBoxContainer = null
var ability_container: VBoxContainer = null
var select_button: Button = null

# Animation
var rotation_speed: float = 30.0  # degrees per second

func _ready():
	_load_characters()
	_create_ui()
	_setup_preview_viewport()

	if available_characters.size() > 0:
		_select_character(0)

func _process(delta: float):
	# Rotate preview model
	if preview_model:
		preview_model.rotation.y += deg_to_rad(rotation_speed * delta)

func get_selected_character() -> CharacterData:
	return selected_character

func _load_characters():
	available_characters = [
		TomatoCharacter.new(),
		CarrotCharacter.new(),
		PumpkinCharacter.new(),
		CornCharacter.new(),
		BroccoliCharacter.new(),
		BeetCharacter.new(),
		GreenPepperCharacter.new(),
		TurnipCharacter.new(),
	]

func _create_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Main horizontal layout
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_preset(PRESET_FULL_RECT)
	main_hbox.set_anchor_and_offset(SIDE_LEFT, 0, 20)
	main_hbox.set_anchor_and_offset(SIDE_RIGHT, 1, -20)
	main_hbox.set_anchor_and_offset(SIDE_TOP, 0, 20)
	main_hbox.set_anchor_and_offset(SIDE_BOTTOM, 1, -20)
	main_hbox.add_theme_constant_override("separation", 20)
	add_child(main_hbox)

	# Left panel - character list
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size.x = 220
	main_hbox.add_child(left_panel)

	var list_title = Label.new()
	list_title.text = "CHARACTERS"
	list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_title.add_theme_font_size_override("font_size", 20)
	left_panel.add_child(list_title)

	character_list = ItemList.new()
	character_list.size_flags_vertical = SIZE_EXPAND_FILL
	character_list.item_selected.connect(_on_character_list_selected)
	character_list.add_theme_font_size_override("font_size", 16)
	left_panel.add_child(character_list)

	for character in available_characters:
		character_list.add_item(character.character_name)

	# Center panel - 3D preview
	var center_panel = VBoxContainer.new()
	center_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	main_hbox.add_child(center_panel)

	var preview_title = Label.new()
	preview_title.text = "PREVIEW"
	preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_title.add_theme_font_size_override("font_size", 20)
	center_panel.add_child(preview_title)

	# Preview container with border
	var preview_frame = PanelContainer.new()
	preview_frame.size_flags_vertical = SIZE_EXPAND_FILL
	center_panel.add_child(preview_frame)

	preview_container = SubViewportContainer.new()
	preview_container.stretch = true
	preview_frame.add_child(preview_container)

	# Right panel - stats and abilities
	var right_panel = VBoxContainer.new()
	right_panel.custom_minimum_size.x = 280
	right_panel.add_theme_constant_override("separation", 15)
	main_hbox.add_child(right_panel)

	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	right_panel.add_child(name_label)

	description_label = RichTextLabel.new()
	description_label.custom_minimum_size.y = 60
	description_label.bbcode_enabled = true
	description_label.fit_content = true
	description_label.scroll_active = false
	right_panel.add_child(description_label)

	# Stats section
	var stats_title = Label.new()
	stats_title.text = "STATS"
	stats_title.add_theme_font_size_override("font_size", 18)
	stats_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	right_panel.add_child(stats_title)

	stats_container = VBoxContainer.new()
	stats_container.add_theme_constant_override("separation", 8)
	right_panel.add_child(stats_container)

	# Abilities section
	var ability_title = Label.new()
	ability_title.text = "ABILITIES"
	ability_title.add_theme_font_size_override("font_size", 18)
	ability_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	right_panel.add_child(ability_title)

	ability_container = VBoxContainer.new()
	ability_container.add_theme_constant_override("separation", 10)
	right_panel.add_child(ability_container)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	right_panel.add_child(spacer)

	# Buttons
	select_button = Button.new()
	select_button.text = "SELECT & PLAY"
	select_button.custom_minimum_size.y = 50
	select_button.add_theme_font_size_override("font_size", 18)
	select_button.pressed.connect(_on_select_pressed)
	right_panel.add_child(select_button)

	var back_button = Button.new()
	back_button.text = "BACK"
	back_button.custom_minimum_size.y = 40
	back_button.pressed.connect(_on_back_pressed)
	right_panel.add_child(back_button)

func _setup_preview_viewport():
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(400, 500)
	preview_viewport.transparent_bg = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_container.add_child(preview_viewport)

	# Environment
	var world_env = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.15, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.ambient_light_energy = 1.0
	world_env.environment = env
	preview_viewport.add_child(world_env)

	# Key light
	var key_light = DirectionalLight3D.new()
	key_light.rotation = Vector3(deg_to_rad(-45), deg_to_rad(45), 0)
	key_light.light_energy = 1.2
	preview_viewport.add_child(key_light)

	# Fill light (softer, from other side)
	var fill_light = DirectionalLight3D.new()
	fill_light.rotation = Vector3(deg_to_rad(-30), deg_to_rad(-45), 0)
	fill_light.light_energy = 0.5
	fill_light.light_color = Color(0.8, 0.9, 1.0)
	preview_viewport.add_child(fill_light)

	# Camera
	preview_camera = Camera3D.new()
	preview_camera.position = Vector3(0, 1.0, 2.5)
	preview_camera.look_at(Vector3(0, 0.7, 0))
	preview_viewport.add_child(preview_camera)

	# Floor for reference
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(3, 3)
	floor_mesh.mesh = plane
	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.2, 0.2, 0.25)
	floor_mesh.set_surface_override_material(0, floor_mat)
	preview_viewport.add_child(floor_mesh)

func _select_character(index: int):
	if index < 0 or index >= available_characters.size():
		return

	selected_index = index
	selected_character = available_characters[index]
	character_list.select(index)

	_update_preview()
	_update_info_panel()
	_play_select_animation()

func _update_preview():
	# Remove old model
	if preview_model:
		preview_model.queue_free()
		preview_model = null

	# Create new model container
	preview_model = Node3D.new()
	preview_model.name = "PreviewModel"
	preview_viewport.add_child(preview_model)

	# Try to load character model
	if selected_character.model_path != "" and ResourceLoader.exists(selected_character.model_path):
		var model_scene = load(selected_character.model_path)
		if model_scene:
			var model_instance = model_scene.instantiate()
			model_instance.scale = Vector3.ONE * selected_character.model_scale
			model_instance.position = selected_character.model_offset
			preview_model.add_child(model_instance)
			return

	# Fallback - create capsule with character color
	var mesh = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.2
	mesh.mesh = capsule

	var material = StandardMaterial3D.new()
	material.albedo_color = selected_character.color
	material.metallic = 0.1
	material.roughness = 0.7
	mesh.set_surface_override_material(0, material)
	mesh.position.y = 0.6

	preview_model.add_child(mesh)

	# Add simple face (eyes)
	var eye_mesh = SphereMesh.new()
	eye_mesh.radius = 0.08
	eye_mesh.height = 0.16

	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color.WHITE

	var left_eye = MeshInstance3D.new()
	left_eye.mesh = eye_mesh
	left_eye.set_surface_override_material(0, eye_mat)
	left_eye.position = Vector3(-0.12, 0.95, 0.28)
	preview_model.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_mesh
	right_eye.set_surface_override_material(0, eye_mat)
	right_eye.position = Vector3(0.12, 0.95, 0.28)
	preview_model.add_child(right_eye)

func _update_info_panel():
	name_label.text = selected_character.character_name
	description_label.text = selected_character.description if selected_character.description else "A brave vegetable warrior!"

	# Clear and rebuild stats
	for child in stats_container.get_children():
		child.queue_free()

	_add_stat_bar("Health", selected_character.base_health, 150.0, Color(0.3, 0.8, 0.3))
	_add_stat_bar("Speed", selected_character.base_speed, 10.0, Color(0.3, 0.6, 0.9))

	# Clear and rebuild abilities
	for child in ability_container.get_children():
		child.queue_free()

	if selected_character.active_ability:
		_add_ability_info(selected_character.active_ability, "ACTIVE", Color(1, 0.7, 0.2))
	if selected_character.passive_ability:
		_add_ability_info(selected_character.passive_ability, "PASSIVE", Color(0.5, 0.8, 1.0))

func _add_stat_bar(stat_name: String, value: float, max_value: float, color: Color):
	var hbox = HBoxContainer.new()
	stats_container.add_child(hbox)

	var label = Label.new()
	label.text = stat_name
	label.custom_minimum_size.x = 70
	hbox.add_child(label)

	var progress = ProgressBar.new()
	progress.max_value = max_value
	progress.value = value
	progress.size_flags_horizontal = SIZE_EXPAND_FILL
	progress.show_percentage = false
	progress.custom_minimum_size.y = 20

	# Custom style
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	progress.add_theme_stylebox_override("fill", style)

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2)
	bg_style.corner_radius_top_left = 3
	bg_style.corner_radius_top_right = 3
	bg_style.corner_radius_bottom_left = 3
	bg_style.corner_radius_bottom_right = 3
	progress.add_theme_stylebox_override("background", bg_style)

	hbox.add_child(progress)

	var value_label = Label.new()
	value_label.text = str(int(value))
	value_label.custom_minimum_size.x = 40
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value_label)

func _add_ability_info(ability_data: AbilityData, ability_type: String, type_color: Color):
	var vbox = VBoxContainer.new()
	ability_container.add_child(vbox)

	var type_label = Label.new()
	type_label.text = "[%s]" % ability_type
	type_label.add_theme_font_size_override("font_size", 12)
	type_label.add_theme_color_override("font_color", type_color)
	vbox.add_child(type_label)

	var name_label_ab = Label.new()
	name_label_ab.text = ability_data.ability_name
	name_label_ab.add_theme_font_size_override("font_size", 16)
	name_label_ab.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	vbox.add_child(name_label_ab)

	var desc_label = Label.new()
	desc_label.text = ability_data.description if ability_data.description else "No description"
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(desc_label)

func _play_select_animation():
	if preview_model:
		var tween = create_tween()
		preview_model.scale = Vector3.ONE * 0.8
		tween.tween_property(preview_model, "scale", Vector3.ONE, 0.25)
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)

func _on_character_list_selected(index: int):
	_select_character(index)

func _on_select_pressed():
	if not selected_character:
		return

	character_selected.emit(selected_character)

	# Store in GameManager
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.selected_character = selected_character
		print("[CharacterSelect] Stored character: %s" % selected_character.character_name)

	# Transition to game with fade
	var scene_transition = get_node_or_null("/root/SceneTransition")
	if scene_transition:
		scene_transition.fade_to_scene("res://scenes/GameScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/GameScene.tscn")

func _on_back_pressed():
	var scene_transition = get_node_or_null("/root/SceneTransition")
	if scene_transition:
		scene_transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")
