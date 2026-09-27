## Pause menu (Esc). In multiplayer the game keeps running underneath: pausing the tree
## would freeze the server (host) or the network processing (client) for everybody.
extends Control
class_name PauseMenu

var resume_button: Button = null
var settings_button: Button = null
var main_menu_button: Button = null
var quit_button: Button = null

var is_paused: bool = false
var pause_tree: bool = true  # Set to false by GameSceneController when networked
var settings_panel: SettingsPanel = null
var main_panel: GlassPanel = null
var _center: CenterContainer = null

func _ready():
	visible = false
	add_to_group("blocks_game_input")  # PlayerInputHandler ignores the game while we're open
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_create_ui()

func _create_ui():
	var dim = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.55)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)

	_center = CenterContainer.new()
	_center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_center)

	main_panel = UITheme.create_panel(_center, 28)
	main_panel.tint = UITheme.GLASS_TINT_DARK
	main_panel.custom_minimum_size = Vector2(360, 0)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	main_panel.add_child(vbox)

	UITheme.create_title("PAUSED", vbox)
	var hint = UITheme.create_label("The match keeps going in multiplayer", vbox, UITheme.FONT_SMALL)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	UITheme.create_separator(vbox)

	resume_button = UITheme.create_primary_button("RESUME", vbox, Vector2(0, 56))
	resume_button.pressed.connect(_on_resume_pressed)

	settings_button = UITheme.create_button("SETTINGS", vbox, Vector2(0, 50))
	settings_button.pressed.connect(_on_settings_pressed)

	main_menu_button = UITheme.create_button("LEAVE TO MENU", vbox, Vector2(0, 50))
	main_menu_button.pressed.connect(_on_main_menu_pressed)

	quit_button = UITheme.create_danger_button("QUIT GAME", vbox, Vector2(0, 46))
	quit_button.pressed.connect(_on_quit_pressed)

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		if settings_panel and settings_panel.visible:
			_hide_settings()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause():
	is_paused = not is_paused
	visible = is_paused
	if pause_tree:
		get_tree().paused = is_paused
	if is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		main_panel.visible = true
		if settings_panel:
			settings_panel.visible = false

func _on_resume_pressed():
	toggle_pause()

func _on_settings_pressed():
	if settings_panel == null:
		settings_panel = SettingsPanel.new()
		settings_panel.tint = UITheme.GLASS_TINT_DARK
		settings_panel.closed.connect(_hide_settings)
		_center.add_child(settings_panel)
	main_panel.visible = false
	settings_panel.visible = true

func _hide_settings():
	if settings_panel:
		settings_panel.visible = false
		GameSettings.save()
	main_panel.visible = true

func _on_main_menu_pressed():
	get_tree().paused = false
	is_paused = false

	# MainMenu tears the server/client down on entry (after the fade, so the map
	# does not vanish mid-transition)
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")

func _on_quit_pressed():
	get_tree().quit()
