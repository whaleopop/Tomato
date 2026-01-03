## Connect to server menu - styled programmatically
extends Control
class_name ConnectMenu

var ip_input: LineEdit = null
var port_input: LineEdit = null
var connect_button: Button = null
var back_button: Button = null
var status_label: Label = null

func _ready():
	_create_ui()

func _create_ui():
	# Background
	UITheme.create_background(self)

	# Main container
	var vbox = UITheme.create_centered_container(self, 380)

	# Title
	UITheme.create_title("JOIN SERVER", vbox)

	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size.y = 30
	vbox.add_child(spacer1)

	# Panel for inputs
	var panel = UITheme.create_panel(vbox)
	var panel_vbox = VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	panel.add_child(panel_vbox)

	# IP Address
	var ip_container = VBoxContainer.new()
	ip_container.add_theme_constant_override("separation", 5)
	panel_vbox.add_child(ip_container)

	UITheme.create_label("Server IP Address", ip_container)
	ip_input = UITheme.create_line_edit("127.0.0.1", ip_container)
	ip_input.text = "127.0.0.1"
	ip_input.custom_minimum_size.x = 300

	# Port
	var port_container = VBoxContainer.new()
	port_container.add_theme_constant_override("separation", 5)
	panel_vbox.add_child(port_container)

	UITheme.create_label("Port", port_container)
	port_input = UITheme.create_line_edit("7777", port_container)
	port_input.text = "7777"
	port_input.custom_minimum_size.x = 300

	# Status label
	status_label = UITheme.create_label("", panel_vbox)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", UITheme.ACCENT_PRIMARY)

	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size.y = 20
	vbox.add_child(spacer2)

	# Buttons
	var buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)

	back_button = UITheme.create_button("BACK", buttons, Vector2(140, 50))
	back_button.pressed.connect(_on_back_pressed)

	connect_button = UITheme.create_primary_button("CONNECT", buttons, Vector2(180, 50))
	connect_button.pressed.connect(_on_connect_pressed)

func _on_connect_pressed():
	print("[ConnectMenu] Connect button pressed")
	var ip = ip_input.text if ip_input and ip_input.text != "" else "127.0.0.1"
	var port = int(port_input.text) if port_input and port_input.text != "" else 7777

	print("[ConnectMenu] Connecting to %s:%d" % [ip, port])
	status_label.text = "Connecting..."
	status_label.add_theme_color_override("font_color", UITheme.ACCENT_PRIMARY)

	if NetworkManager:
		var success = NetworkManager.start_client(ip, port)

		if success:
			await get_tree().process_frame
			if NetworkManager.game_client:
				NetworkManager.game_client.connected_to_server.connect(_on_connected)
				NetworkManager.game_client.connection_failed.connect(_on_connection_failed)
		else:
			status_label.text = "Failed to start connection"
			status_label.add_theme_color_override("font_color", UITheme.ACCENT_DANGER)
	else:
		status_label.text = "Error: NetworkManager missing"
		status_label.add_theme_color_override("font_color", UITheme.ACCENT_DANGER)

func _on_back_pressed():
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")

func _on_connected():
	print("[ConnectMenu] Connected!")
	status_label.text = "Connected!"
	status_label.add_theme_color_override("font_color", UITheme.ACCENT_SUCCESS)

	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/CharacterSelectScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/CharacterSelectScene.tscn")

func _on_connection_failed():
	print("[ConnectMenu] Connection failed!")
	status_label.text = "Connection failed!"
	status_label.add_theme_color_override("font_color", UITheme.ACCENT_DANGER)
