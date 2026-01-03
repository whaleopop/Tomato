## Main menu scene - styled programmatically
extends Control
class_name MainMenu

var start_button: Button = null
var connect_button: Button = null
var settings_button: Button = null
var quit_button: Button = null

func _ready():
	_create_ui()

func _create_ui():
	# Background
	UITheme.create_background(self)

	# Main container
	var vbox = UITheme.create_centered_container(self, 350)

	# Title
	var title = UITheme.create_title("ROYALTIM", vbox)
	title.add_theme_font_size_override("font_size", 48)

	# Subtitle
	var subtitle = UITheme.create_label("Battle Royale", vbox, UITheme.FONT_SUBTITLE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size.y = 40
	vbox.add_child(spacer1)

	# Buttons container (centered)
	var buttons_container = VBoxContainer.new()
	buttons_container.add_theme_constant_override("separation", 15)
	buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons_container)

	# Play button (primary)
	start_button = UITheme.create_primary_button("PLAY", buttons_container, Vector2(280, 60))
	start_button.pressed.connect(_on_start_pressed)

	# Connect button
	connect_button = UITheme.create_button("JOIN SERVER", buttons_container, Vector2(280, 50))
	connect_button.pressed.connect(_on_connect_pressed)

	# Settings button
	settings_button = UITheme.create_button("SETTINGS", buttons_container, Vector2(280, 50))
	settings_button.pressed.connect(_on_settings_pressed)

	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size.y = 20
	vbox.add_child(spacer2)

	# Quit button (danger)
	quit_button = UITheme.create_danger_button("QUIT", vbox, Vector2(200, 45))
	quit_button.pressed.connect(_on_quit_pressed)

	# Version label at bottom
	var version = Label.new()
	version.text = "v0.3.0"
	version.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	version.position = Vector2(-80, -30)
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	add_child(version)

func _on_start_pressed():
	print("[MainMenu] Play button pressed")
	# Start as host/server for now
	if NetworkManager:
		var success = NetworkManager.start_server(7777)
		if success:
			print("[MainMenu] Server started, switching to character select")
			_transition_to("res://scenes/CharacterSelectScene.tscn")
		else:
			print("[MainMenu] Failed to start server!")
	else:
		# Offline mode - go straight to character select
		_transition_to("res://scenes/CharacterSelectScene.tscn")

func _on_connect_pressed():
	_transition_to("res://scenes/ConnectScene.tscn")

func _on_settings_pressed():
	# TODO: Open settings panel
	print("[MainMenu] Settings pressed (not implemented)")

func _on_quit_pressed():
	get_tree().quit()

func _transition_to(scene_path: String):
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene(scene_path)
	else:
		get_tree().change_scene_to_file(scene_path)
