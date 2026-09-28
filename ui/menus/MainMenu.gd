## Main menu: title, glass action card, rotating character showcase
extends Control
class_name MainMenu

const SHOWCASE_INTERVAL: float = 4.0
const VERSION = "v0.4.0"

var start_button: Button = null
var connect_button: Button = null
var settings_button: Button = null
var guide_button: Button = null
var quit_button: Button = null

var showcase: CharacterShowcase = null
var showcase_name: Label = null
var toast: Control = null
var settings_layer: Control = null
var guide: Encyclopedia = null
var _language_dirty: bool = false  # formatted texts (LAN hint...) need a rebuild

var _roster: Array[CharacterData] = []
var _showcase_index: int = 0
var _showcase_timer: float = 0.0

func _ready():
	# Coming back from a lobby/match: make sure no server/client is left running,
	# otherwise PLAY fails with "server already exists"
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.stop_all()

	_roster = CharacterRegistry.get_all()
	_showcase_index = randi() % _roster.size()
	_create_ui()
	_show_next_character()

	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.last_error != "":
		show_toast(game_manager.last_error, UITheme.ACCENT_DANGER)
		game_manager.last_error = ""

func _process(delta: float):
	_showcase_timer += delta
	if _showcase_timer >= SHOWCASE_INTERVAL:
		_showcase_timer = 0.0
		_show_next_character()

func _create_ui():
	UITheme.create_background(self)

	var margin = UITheme.create_screen_margin(self, 56)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	margin.add_child(row)

	# ---- Left column: title + actions
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 420
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 18)
	row.add_child(left)

	UITheme.create_pill("Battle Royale", UITheme.ACCENT_PRIMARY, left)
	var title = UITheme.create_hero_title("ROYALTIM", left)
	title.add_theme_font_size_override("font_size", 76)
	var tagline = UITheme.create_label("Veggies. Hexes. One survivor.", left, UITheme.FONT_SUBTITLE)
	tagline.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	UITheme.create_spacer(false, left).custom_minimum_size.y = 10

	var card = UITheme.create_panel(left, 22)
	var buttons = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	card.add_child(buttons)

	start_button = UITheme.create_primary_button("PLAY  ·  HOST GAME", buttons, Vector2(0, 62))
	start_button.pressed.connect(_on_start_pressed)

	connect_button = UITheme.create_button("JOIN SERVER", buttons, Vector2(0, 52))
	connect_button.pressed.connect(_on_connect_pressed)

	guide_button = UITheme.create_button("GUIDE  ·  HEROES, WEAPONS, LOOT", buttons, Vector2(0, 52))
	guide_button.pressed.connect(_on_guide_pressed)

	var small_row = HBoxContainer.new()
	small_row.add_theme_constant_override("separation", 12)
	buttons.add_child(small_row)

	settings_button = UITheme.create_button("SETTINGS", small_row, Vector2(0, 48))
	settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_button.pressed.connect(_on_settings_pressed)

	quit_button = UITheme.create_danger_button("QUIT", small_row, Vector2(0, 48))
	quit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit_button.pressed.connect(_on_quit_pressed)

	var hint = UITheme.create_label(_lan_hint(), left, UITheme.FONT_SMALL)
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ---- Right: character showcase
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)

	showcase = CharacterShowcase.new()
	showcase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(showcase)

	showcase_name = UITheme.create_title("", right)
	showcase_name.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	# ---- Version (bottom-right)
	var version = UITheme.create_label(VERSION, self, UITheme.FONT_TINY)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -80
	version.offset_top = -34
	version.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	_intro_animation(left)

func _intro_animation(node: Control):
	node.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(node, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC)

func _show_next_character():
	if _roster.is_empty() or not showcase:
		return
	var data = _roster[_showcase_index % _roster.size()]
	_showcase_index += 1
	showcase.show_character(data)
	showcase_name.text = data.character_name  # translated, then uppercased
	showcase_name.uppercase = true
	showcase_name.add_theme_color_override("font_color", data.color.lightened(0.35))

## Friends need the host's LAN address to join
func _lan_hint() -> String:
	var ips: Array = []
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or (address.begins_with("172.") and not address.begins_with("172.1.")):
			ips.append(address)
	if ips.is_empty():
		return tr("Host a game, friends join with your IP on port 7777.")
	return tr("Friends on your network join with  %s : 7777") % ips[0]

func show_toast(text: String, color: Color = UITheme.ACCENT_INFO):
	if toast and is_instance_valid(toast):
		toast.queue_free()

	var holder = CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH  # centered, long messages don't run off
	holder.offset_top = 24
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	toast = holder

	var pill = PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UITheme.glow_box(Color(color, 0.22), 0.3, UITheme.CORNER_RADIUS_PILL, 16))
	holder.add_child(pill)
	var label = UITheme.create_label(text, pill)
	label.add_theme_color_override("font_color", Color.WHITE)

	holder.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(holder, "modulate:a", 1.0, 0.25)
	tween.tween_interval(4.0)
	tween.tween_property(holder, "modulate:a", 0.0, 0.5)
	tween.tween_callback(holder.queue_free)

func _set_buttons_enabled(enabled: bool):
	for b in [start_button, connect_button, guide_button, settings_button, quit_button]:
		if b:
			b.disabled = not enabled

func _on_start_pressed():
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		_transition_to("res://scenes/CharacterSelectScene.tscn")
		return

	_set_buttons_enabled(false)
	if network_manager.start_server(7777):
		_transition_to("res://scenes/CharacterSelectScene.tscn")
	else:
		_set_buttons_enabled(true)
		show_toast("Could not start a server on port 7777 - is another game already hosting?", UITheme.ACCENT_DANGER)

func _on_connect_pressed():
	_transition_to("res://scenes/ConnectScene.tscn")

func _on_settings_pressed():
	if settings_layer:
		return
	settings_layer = Control.new()
	settings_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(settings_layer)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_layer.add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_layer.add_child(center)

	var panel = SettingsPanel.new()
	center.add_child(panel)
	panel.closed.connect(_close_settings)
	panel.language_changed.connect(func(): _language_dirty = true)

func _close_settings():
	if settings_layer:
		settings_layer.queue_free()
		settings_layer = null
	GameSettings.save()
	if _language_dirty:
		get_tree().reload_current_scene()  # rebuild the texts formatted in code

func _on_guide_pressed():
	if guide:
		return
	guide = Encyclopedia.new()
	add_child(guide)
	showcase.visible = false  # one 3D preview at a time
	guide.closed.connect(func():
		guide = null
		showcase.visible = true)

func _unhandled_input(event: InputEvent):
	if settings_layer and event.is_action_pressed("pause"):
		_close_settings()
		get_viewport().set_input_as_handled()

func _on_quit_pressed():
	get_tree().quit()

func _transition_to(scene_path: String):
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene(scene_path)
	else:
		get_tree().change_scene_to_file(scene_path)
