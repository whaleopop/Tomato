## Main menu: title, glass action card; behind them MenuDiorama (a piece of the map, your arsenal,
## the heroes you own taking turns on the dais)
extends Control
class_name MainMenu

const SHOWCASE_INTERVAL: float = 4.0
const VERSION = "v0.8.2"

var start_button: Button = null
var connect_button: Button = null
var settings_button: Button = null
var guide_button: Button = null
var shop_button: Button = null
var training_button: Button = null
var quit_button: Button = null
var coins_label: Label = null
var players_pill: Control = null  # registered / online right now (the backend's /status)
var players_label: Label = null
var _players_timer: float = 0.0
const PLAYERS_EVERY: float = 15.0
var shop: Shop = null

var showcase: MenuDiorama = null  # the scene behind the menu, with the hero on its dais
var showcase_name: Label = null
var toast: Control = null
var settings_layer: Control = null
var guide: Encyclopedia = null
var _language_dirty: bool = false  # formatted texts (LAN hint...) need a rebuild

var _roster: Array[CharacterData] = []
var _showcase_index: int = 0
var _showcase_timer: float = 0.0

func _ready():
	# A headless server for the beta: no menu, straight to serving matches
	if DedicatedServer.requested():
		set_process(false)
		get_tree().change_scene_to_file.call_deferred(DedicatedServer.SCENE)
		return

	# Coming back from a lobby/match: make sure no server/client is left running,
	# otherwise PLAY fails with "server already exists"
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.stop_all()

	var game_manager_node = get_node_or_null("/root/GameManager")
	if game_manager_node:
		game_manager_node.training_mode = false
		game_manager_node.matchmaking = false
	# The showcase walks through the heroes you own (all of them before you own any)
	_roster = CharacterRegistry.get_all()
	var mine = _roster.filter(func(c): return PlayerProfile.owns_hero(c.character_name))
	if not mine.is_empty():
		_roster.assign(mine)
	_showcase_index = randi() % _roster.size()
	_create_ui()
	_show_next_character()

	# Online the profile is the server's: wait for the login (the first start depends on it) and
	# take fresh numbers after a match (the game server credited the coins and XP)
	var online = get_node_or_null("/root/Online")
	if online:
		online.profile_changed.connect(_update_coins)
		if not online.login_done:
			await online.wait_login()
		elif online.logged_in:
			online.refresh()
		else:
			online.login()  # try again in the background
		if not is_inside_tree():
			return
		_update_coins()
		_refresh_players()
	_check_update()

	# First start: a name and the first hero
	if not PlayerProfile.has_account() or PlayerProfile.needs_starter():
		var onboarding = Onboarding.new()
		add_child(onboarding)
		showcase.visible = false
		onboarding.finished.connect(func():
			showcase.visible = true
			_update_coins())

	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.last_error != "":
		show_toast(game_manager.last_error, UITheme.ACCENT_DANGER)
		game_manager.last_error = ""
	elif online and online.login_done and not online.logged_in:
		show_toast(tr("Offline: %s") % tr(online.last_error), UITheme.ACCENT_WARNING)

func _process(delta: float):
	_players_timer += delta
	if _players_timer >= PLAYERS_EVERY:
		_refresh_players()
	_showcase_timer += delta
	if _showcase_timer >= SHOWCASE_INTERVAL:
		_showcase_timer = 0.0
		_show_next_character()

func _create_ui():
	UITheme.create_background(self)
	# Behind everything: a piece of the map with your arsenal and your hero (MenuDiorama)
	showcase = MenuDiorama.new()
	showcase.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(showcase)
	# A soft shade on the left, under the menu card, so the buttons read over the scene
	var shade = TextureRect.new()
	var grad = GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0.03, 0.04, 0.08, 0.75))
	grad.gradient.set_color(1, Color(0.03, 0.04, 0.08, 0.0))
	grad.fill_to = Vector2(1, 0)
	shade.texture = grad
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 760
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

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

	start_button = UITheme.create_primary_button("PLAY  ·  FIND A MATCH", buttons, Vector2(0, 62))
	start_button.pressed.connect(_on_start_pressed)

	connect_button = UITheme.create_button("JOIN SERVER", buttons, Vector2(0, 52))
	connect_button.pressed.connect(_on_connect_pressed)

	guide_button = UITheme.create_button("GUIDE  ·  HEROES, WEAPONS, LOOT", buttons, Vector2(0, 52))
	guide_button.pressed.connect(_on_guide_pressed)

	var extra_row = HBoxContainer.new()
	extra_row.add_theme_constant_override("separation", 12)
	buttons.add_child(extra_row)
	shop_button = UITheme.create_button("SHOP", extra_row, Vector2(0, 52))
	shop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_button.pressed.connect(_on_shop_pressed)
	training_button = UITheme.create_button("TRAINING GROUND", extra_row, Vector2(0, 52))
	training_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	training_button.pressed.connect(_on_training_pressed)

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

	var space = Control.new()  # the hero stands in the scene behind (MenuDiorama)
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(space)

	showcase_name = UITheme.create_title("", right)
	showcase_name.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	# ---- Coins (top-right)
	var wallet = PanelContainer.new()
	wallet.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.7), Color(1.0, 0.8, 0.3, 0.7), 99, 20, 7))
	wallet.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wallet.offset_left = -330
	wallet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wallet.offset_right = -32
	wallet.offset_top = 28
	add_child(wallet)
	coins_label = UITheme.create_heading("", wallet)
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_update_coins()

	# ---- Players (under the coins): how many signed up and how many are on right now
	players_pill = PanelContainer.new()
	players_pill.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.7), Color(UITheme.ACCENT_SUCCESS, 0.6), 99, 18, 6))
	players_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	players_pill.offset_left = -330
	players_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	players_pill.offset_right = -32
	players_pill.offset_top = 84
	players_pill.visible = false
	add_child(players_pill)
	players_label = UITheme.create_label("", players_pill, UITheme.FONT_SMALL)
	players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	players_label.add_theme_color_override("font_color", UITheme.ACCENT_SUCCESS.lightened(0.25))

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
	var wear = PlayerProfile.equipped_for(data.character_name)
	showcase.show_hero(data, wear.skin, wear.hat)
	showcase_name.text = data.character_name  # translated, then uppercased
	showcase_name.uppercase = true
	showcase_name.add_theme_color_override("font_color", data.color.lightened(0.35))

## A newer release on GitHub (exported Windows game only): offer to update right here
func _check_update():
	var release = await UpdateDialog.check(self, VERSION)
	if release.is_empty() or not is_inside_tree():
		return
	var dialog = UpdateDialog.new()
	dialog.release = release
	add_child(dialog)

## "Online: N · Registered: M" from the backend (asking also keeps us counted as online)
func _refresh_players():
	_players_timer = 0.0
	var online = get_node_or_null("/root/Online")
	if online == null or not online.logged_in:
		players_pill.visible = false
		return
	var res = await online.request(HTTPClient.METHOD_GET, "/status")
	if not is_inside_tree() or not res.get("ok", false):
		return
	players_label.text = "●  " + tr("Online: %d  ·  Registered: %d") % [int(res.get("online", 0)), int(res.get("registered", 0))]
	players_pill.visible = true

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
	for b in [start_button, connect_button, guide_button, shop_button, training_button, settings_button, quit_button]:
		if b:
			b.disabled = not enabled

## PLAY: the mode first (ModeSelect), then the hero and the online queue (MatchmakingScreen) -
## or HOST LAN: this computer hosts the match
func _on_start_pressed():
	var picker = ModeSelect.new()
	add_child(picker)
	picker.chosen.connect(_find_match)
	picker.host_chosen.connect(func(mode):
		var gm = get_node_or_null("/root/GameManager")
		if gm:
			gm.game_mode = mode
		_host_game())

func _find_match(mode: String):
	var online = get_node_or_null("/root/Online")
	if online == null or not online.logged_in:
		var why = tr("No connection to the game server - host a LAN game or try again")
		if online and online.login_done and online.last_error != "No connection to the game server":
			why = tr(online.last_error)  # the server answered: an old game, ...
		show_toast(why, UITheme.ACCENT_DANGER)
		if online:
			online.login()
		return
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.game_mode = mode
		gm.matchmaking = true
	_transition_to("res://scenes/CharacterSelectScene.tscn")

func _host_game():
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

func _update_coins():
	if coins_label:
		var who = PlayerProfile.nickname
		coins_label.text = (who + "  ·  " if who != "" else "") + tr("%d coins") % PlayerProfile.get_coins()

func _on_shop_pressed():
	if shop:
		return
	shop = Shop.new()
	add_child(shop)
	showcase.visible = false  # one 3D preview at a time
	shop.closed.connect(func():
		shop = null
		showcase.visible = true
		_update_coins())

## Offline arena with every gun and dummies: go through character select first
func _on_training_pressed():
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.training_mode = true
	_transition_to("res://scenes/CharacterSelectScene.tscn")

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
