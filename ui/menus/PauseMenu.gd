## Pause menu - styled programmatically
extends Control
class_name PauseMenu

var resume_button: Button = null
var settings_button: Button = null
var main_menu_button: Button = null
var quit_button: Button = null

var is_paused: bool = false
var settings_panel: Control = null
var main_panel: PanelContainer = null

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()

func _create_ui():
	# Semi-transparent background overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	add_child(overlay)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	# Main panel
	main_panel = UITheme.create_panel()
	main_panel.custom_minimum_size = Vector2(320, 380)
	center.add_child(main_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	main_panel.add_child(vbox)

	# Title
	UITheme.create_title("PAUSED", vbox)

	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size.y = 20
	vbox.add_child(spacer1)

	# Buttons
	resume_button = UITheme.create_primary_button("RESUME", vbox, Vector2(250, 55))
	resume_button.pressed.connect(_on_resume_pressed)

	settings_button = UITheme.create_button("SETTINGS", vbox, Vector2(250, 45))
	settings_button.pressed.connect(_on_settings_pressed)

	main_menu_button = UITheme.create_button("MAIN MENU", vbox, Vector2(250, 45))
	main_menu_button.pressed.connect(_on_main_menu_pressed)

	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size.y = 10
	vbox.add_child(spacer2)

	quit_button = UITheme.create_danger_button("QUIT GAME", vbox, Vector2(200, 40))
	quit_button.pressed.connect(_on_quit_pressed)

func _input(event: InputEvent):
	if event.is_action_pressed("pause"):
		if settings_panel and settings_panel.visible:
			_hide_settings()
		else:
			toggle_pause()

func toggle_pause():
	is_paused = not is_paused
	visible = is_paused
	get_tree().paused = is_paused

	if is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		# Return to game mouse mode if needed
		pass

func _on_resume_pressed():
	toggle_pause()

func _on_settings_pressed():
	if settings_panel == null:
		_create_settings_panel()
	main_panel.visible = false
	settings_panel.visible = true

func _hide_settings():
	if settings_panel:
		settings_panel.visible = false
	main_panel.visible = true

func _create_settings_panel():
	var center = get_child(1)  # CenterContainer

	settings_panel = UITheme.create_panel()
	settings_panel.custom_minimum_size = Vector2(350, 400)
	center.add_child(settings_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	settings_panel.add_child(vbox)

	# Title
	UITheme.create_title("SETTINGS", vbox)

	# Master Volume
	var volume_container = VBoxContainer.new()
	volume_container.add_theme_constant_override("separation", 5)
	vbox.add_child(volume_container)

	UITheme.create_label("Master Volume", volume_container)
	var volume_slider = UITheme.create_slider(0.0, 1.0, 1.0, volume_container)
	volume_slider.custom_minimum_size.x = 280
	volume_slider.value_changed.connect(_on_volume_changed)

	# Fullscreen
	var fullscreen = UITheme.create_checkbox(
		"Fullscreen",
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
		vbox
	)
	fullscreen.toggled.connect(_on_fullscreen_toggled)

	# VSync
	var vsync = UITheme.create_checkbox("VSync", true, vbox)
	vsync.toggled.connect(_on_vsync_toggled)

	# Mouse Sensitivity
	var sens_container = VBoxContainer.new()
	sens_container.add_theme_constant_override("separation", 5)
	vbox.add_child(sens_container)

	UITheme.create_label("Mouse Sensitivity", sens_container)
	var sens_slider = UITheme.create_slider(0.1, 2.0, 1.0, sens_container)
	sens_slider.custom_minimum_size.x = 280

	# Spacer
	UITheme.create_spacer(true, vbox)

	# Back button
	var back_btn = UITheme.create_button("BACK", vbox, Vector2(150, 40))
	back_btn.pressed.connect(_hide_settings)

func _on_volume_changed(value: float):
	AudioServer.set_bus_volume_db(0, linear_to_db(value))

func _on_fullscreen_toggled(pressed: bool):
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_vsync_toggled(pressed: bool):
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if pressed else DisplayServer.VSYNC_DISABLED
	)

func _on_main_menu_pressed():
	get_tree().paused = false
	is_paused = false

	# Disconnect from server if connected
	if NetworkManager:
		NetworkManager.disconnect_from_server()

	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")

func _on_quit_pressed():
	get_tree().quit()
