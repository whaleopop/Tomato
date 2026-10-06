## Connect to server menu (main menu -> CONNECT): the main menu's look - the shared top bar
## (back -> main menu), the living garden behind, on the left a gold kicker over the big title
## and a navy card with the address form (IP and port side by side, a THIS PC chip for
## 127.0.0.1), the status line and the golden CONNECT. Enter in a field connects, Esc goes back.
extends Control
class_name ConnectMenu

const COLUMN_LEFT: int = 56
const COLUMN_WIDTH: int = 470

var ip_input: LineEdit = null
var port_input: LineEdit = null
var connect_button: Button = null
var back_button: Button = null      # the header's back chip
var status_label: Label = null
var spinner: Spinner = null
var header: ScreenHeader = null

var _connecting: bool = false

func _ready():
	MenuShell.hide_bar()  # this screen has its own header
	_create_ui()

func _create_ui():
	UITheme.create_background(self, true)
	header = ScreenHeader.make(self, "JOIN SERVER", "Multiplayer", true)
	header.back_pressed.connect(_on_back_pressed)
	header.add_settings_chip(true)
	back_button = header.back_button

	# The column on the left, like the main menu's (the garden stays in view on the right)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.offset_left = COLUMN_LEFT
	column.offset_right = COLUMN_LEFT + COLUMN_WIDTH
	add_child(column)
	# Centred in the space under the bar, never under it
	var place = func():
		var free_h = size.y - ScreenHeader.CONTENT_TOP
		var h = column.get_combined_minimum_size().y
		column.offset_top = ScreenHeader.CONTENT_TOP + max(12.0, (free_h - h) / 2.0 - 20.0)
		column.offset_bottom = column.offset_top + h
	resized.connect(place)
	column.minimum_size_changed.connect(place)
	place.call_deferred()

	UITheme.create_screen_title("BY IP ADDRESS", "Direct connection", column)
	var sub = UITheme.create_label("Enter the host's IP address. On the same PC use 127.0.0.1", column, UITheme.FONT_NORMAL)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	sub.add_theme_constant_override("shadow_offset_y", 1)

	var card = UITheme.navy_panel(column, 22)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	# IP and port side by side, a small caption over each
	var fields = HBoxContainer.new()
	fields.add_theme_constant_override("separation", 12)
	box.add_child(fields)
	var ip_box = _field_box("Server IP address", fields)
	ip_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_input = _field(ip_box, "127.0.0.1")
	ip_input.text = GameSettings.last_server_ip
	ip_input.text_submitted.connect(func(_t): _on_connect_pressed())
	var port_box = _field_box("Port", fields)
	port_box.custom_minimum_size.x = 120
	port_input = _field(port_box, "7777")
	port_input.text = str(GameSettings.last_server_port)
	port_input.text_submitted.connect(func(_t): _on_connect_pressed())

	# Quick pick: the host on this computer
	var chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	box.add_child(chips)
	var local_chip = UITheme.create_tab("This PC  ·  127.0.0.1", chips, Vector2(0, 36))
	local_chip.add_theme_font_size_override("font_size", 13)
	local_chip.pressed.connect(func():
		ip_input.text = "127.0.0.1"
		ip_input.grab_focus()
		ip_input.caret_column = ip_input.text.length())

	var status_row = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 10)
	status_row.custom_minimum_size.y = 30
	box.add_child(status_row)

	spinner = Spinner.new()
	spinner.custom_minimum_size = Vector2(22, 22)
	spinner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spinner.thickness = 3.0
	spinner.visible = false
	status_row.add_child(spinner)

	status_label = UITheme.create_label("", status_row, UITheme.FONT_SMALL)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_override("font", UITheme.font_bold())

	connect_button = UITheme.create_play_button("CONNECT", "Join the host's lobby", box)
	connect_button.pressed.connect(_on_connect_pressed)

	ip_input.call_deferred("grab_focus")

## A small muted uppercase caption over a field
func _field_box(caption: String, parent: Control) -> VBoxContainer:
	var holder = VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	parent.add_child(holder)
	var label = UITheme.create_label(caption, holder, 12)
	label.uppercase = true
	label.add_theme_font_override("font", UITheme.font_black())
	label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	return holder

## A deep navy field with a thin rim, gold while you type in it
func _field(parent: Control, placeholder: String) -> LineEdit:
	var edit = UITheme.create_line_edit(placeholder, parent)
	edit.custom_minimum_size = Vector2(0, 50)
	edit.add_theme_font_override("font", UITheme.font_bold())
	edit.add_theme_font_size_override("font_size", 18)
	var normal = UITheme.navy_box(Color(0.02, 0.03, 0.06, 0.92), Color(1, 1, 1, 0.14), 10, 14, 6)
	normal.shadow_size = 0
	edit.add_theme_stylebox_override("normal", normal)
	var focus = StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(10)
	focus.set_border_width_all(2)
	focus.border_color = UITheme.GOLD
	focus.anti_aliasing = true
	edit.add_theme_stylebox_override("focus", focus)
	edit.add_theme_color_override("caret_color", UITheme.GOLD)
	edit.add_theme_color_override("selection_color", Color(UITheme.GOLD, 0.35))
	edit.add_theme_color_override("font_placeholder_color", UITheme.TEXT_MUTED)
	return edit

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()

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
