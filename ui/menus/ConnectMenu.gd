## Connect to server menu
extends Control
class_name ConnectMenu

var ip_input: LineEdit = null
var port_input: LineEdit = null
var connect_button: Button = null
var back_button: Button = null
var status_label: Label = null
var spinner: Spinner = null

var _connecting: bool = false

func _ready():
	_create_ui()

func _create_ui():
	UITheme.create_background(self)

	var column = UITheme.create_centered_container(self, 440)

	UITheme.create_pill("Multiplayer", UITheme.ACCENT_INFO, column).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.create_title("JOIN SERVER", column)
	var sub = UITheme.create_label("Enter the host's IP address. On the same PC use 127.0.0.1", column, UITheme.FONT_SMALL)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	var card = UITheme.create_panel(column, 26)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	card.add_child(box)

	UITheme.create_caption("Server IP address", box)
	ip_input = UITheme.create_line_edit("127.0.0.1", box)
	ip_input.text = GameSettings.last_server_ip
	ip_input.text_submitted.connect(func(_t): _on_connect_pressed())

	UITheme.create_caption("Port", box)
	port_input = UITheme.create_line_edit("7777", box)
	port_input.text = str(GameSettings.last_server_port)
	port_input.text_submitted.connect(func(_t): _on_connect_pressed())

	var status_row = HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 10)
	status_row.custom_minimum_size.y = 34
	box.add_child(status_row)

	spinner = Spinner.new()
	spinner.custom_minimum_size = Vector2(24, 24)
	spinner.thickness = 3.0
	spinner.visible = false
	status_row.add_child(spinner)

	status_label = UITheme.create_label("", status_row, UITheme.FONT_SMALL)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 300
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	back_button = UITheme.create_button("BACK", buttons, Vector2(0, 54))
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(_on_back_pressed)

	connect_button = UITheme.create_primary_button("CONNECT", buttons, Vector2(0, 54))
	connect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connect_button.size_flags_stretch_ratio = 1.6
	connect_button.pressed.connect(_on_connect_pressed)

	ip_input.call_deferred("grab_focus")

func _set_status(text: String, color: Color, busy: bool = false):
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)
	spinner.visible = busy
	spinner.color = color

func _on_connect_pressed():
	if _connecting:
		return

	var ip = ip_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	var port = int(port_input.text) if port_input.text.strip_edges().is_valid_int() else 7777
	if port <= 0 or port > 65535:
		_set_status("Port must be between 1 and 65535", UITheme.ACCENT_DANGER)
		return

	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		_set_status("NetworkManager is missing", UITheme.ACCENT_DANGER)
		return

	_connecting = true
	connect_button.disabled = true
	_set_status(tr("Connecting to %s:%d...") % [ip, port], UITheme.ACCENT_INFO, true)

	if not network_manager.start_client(ip, port):
		_connecting = false
		connect_button.disabled = false
		_set_status("Could not start the connection. Check the address.", UITheme.ACCENT_DANGER)
		return

	# Connected before we return to the event loop is impossible, so this is race-free
	network_manager.game_client.connected_to_server.connect(_on_connected, CONNECT_ONE_SHOT)
	network_manager.game_client.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)

	GameSettings.last_server_ip = ip
	GameSettings.last_server_port = port
	GameSettings.save()

func _on_back_pressed():
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.stop_all()
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")

func _on_connected():
	_set_status("Connected!", UITheme.ACCENT_SUCCESS)

	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/CharacterSelectScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/CharacterSelectScene.tscn")

func _on_connection_failed():
	_connecting = false
	connect_button.disabled = false
	_set_status(tr("No answer from the server. Is it running? Firewall allows port %s?") % port_input.text, UITheme.ACCENT_DANGER)
	# Drop the dead client so the next attempt starts clean
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.call_deferred("stop_client")
