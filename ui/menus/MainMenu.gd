## Main menu: title, glass action card; behind them MenuDiorama (a piece of the map, your arsenal,
## the heroes you own taking turns on the dais). The scene is clickable: the hero -> their
## wardrobe (shop skins), a gun on the rack -> its finishes, the containers -> the shop's heroes,
## the ARSENAL sign -> the guide's weapons, a shelf pickup -> its guide entry
extends Control
class_name MainMenu

const SCENE_CLICK_DELAY: float = 0.25  # the clicked thing's juice plays before the screen opens
const VERSION = "v0.8.10"
const LEFT_W: int = 380  # the left column's width (x = ScreenHeader.SIDE_MARGIN)
const PARTY_W: int = 360  # the right column's width (players pill, party)

var start_button: Button = null
var connect_button: Button = null
var settings_button: Button = null
var guide_button: Button = null
var shop_button: Button = null
var training_button: Button = null
var quit_button: Button = null
var coins_label: Label = null
var header: ScreenHeader = null    # the top bar (brand, tabs, wallet)
var players_pill: Control = null  # registered / online right now (the backend's /status)
var party_bar: PartyBar = null     # the party and invitations (Online.poll_party)
var friends_button: Button = null
var profile_button: Button = null
var _party_timer: float = 0.0
const PARTY_EVERY: float = 3.0
var players_label: Label = null
var _players_timer: float = 0.0
const PLAYERS_EVERY: float = 15.0

var showcase: MenuDiorama = null  # the scene behind the menu, with the hero on its dais
var showcase_name: Label = null   # the hero's name on the nameplate under the dais
var nameplate: PanelContainer = null
var _nameplate_level: Label = null
var _nameplate_hint: Label = null
var _nameplate_styles: Array = []  # [at rest, the hero pointed at]
var _shown_hero: String = ""      # whose wear the dais was last put up in ("": the empty slot)
var _shown_wear: Dictionary = {}  # the skin / hat the hero on the dais was put up in
var _scene_action_pending: bool = false
var _mode_picker: Control = null
var _onboarding: Control = null
var _update_dialog: Control = null
# the left column's parts that shrink on short windows (_fit_to_height)
var _margin: MarginContainer = null
var _crown: Control = null
var _title: Label = null
var _three: Label = null
var _title_gap: Control = null
var _buttons_box: VBoxContainer = null
var toast: Control = null
var guide: Encyclopedia = null

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
		game_manager_node.matchmaking_follow = false
	_create_ui()
	_refresh_dais()

	# Online the profile is the server's: wait for the login (the first start depends on it) and
	# take fresh numbers after a match (the game server credited the coins and XP)
	var online = get_node_or_null("/root/Online")
	if online:
		online.profile_changed.connect(func():
			_update_coins()
			_refresh_dais())  # the server's profile can bring a different selected_hero
		online.party_changed.connect(func(_data): _refresh_party_slot())
		if not online.login_done:
			await online.wait_login()
		elif online.logged_in:
			online.refresh()
		else:
			online.login()  # try again in the background
		if not is_inside_tree():
			return
		_update_coins()
		_refresh_dais()
		_refresh_players()
		_poll_party()
		_refresh_party_slot()
	_check_update()

	# First start: a name and the first hero
	if not PlayerProfile.has_account() or PlayerProfile.needs_starter():
		var onboarding = Onboarding.new()
		add_child(onboarding)
		MenuShell.cover(onboarding)
		_onboarding = onboarding
		showcase.visible = false
		onboarding.finished.connect(func():
			showcase.visible = true
			_update_coins()
			_refresh_dais())

	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.last_error != "":
		show_toast(game_manager.last_error, UITheme.ACCENT_DANGER)
		game_manager.last_error = ""
	elif online and online.login_done and not online.logged_in:
		show_toast(tr("Offline: %s") % tr(online.last_error), UITheme.ACCENT_WARNING)

func _process(delta: float):
	_party_timer += delta
	if _party_timer >= PARTY_EVERY:
		_party_timer = 0.0
		_poll_party()
	_players_timer += delta
	if _players_timer >= PLAYERS_EVERY:
		_refresh_players()
	# The scene reacts only while nothing is open over it
	var scene_free = not _modal_open()
	if showcase and showcase.interactive != scene_free:
		showcase.interactive = scene_free
	_place_nameplate(delta)

func _create_ui():
	UITheme.create_background(self)
	# Behind everything: a piece of the map with your arsenal and your hero (MenuDiorama)
	showcase = MenuDiorama.new()
	showcase.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(showcase)
	showcase.interactive = true  # point at and click the hero, the guns, the props
	showcase.hero_clicked.connect(_on_scene_hero)
	showcase.gun_clicked.connect(_on_scene_gun)
	showcase.prop_clicked.connect(_on_scene_prop)
	showcase.invite_clicked.connect(_open_friends)
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

	# ---- Left column, bottom-left: secondary rows, then PLAY (the only gold element).
	# SHOP / PROFILE / FRIENDS are tabs in the bar now.
	var left = VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left.grow_horizontal = Control.GROW_DIRECTION_END
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	left.offset_left = ScreenHeader.SIDE_MARGIN
	left.offset_right = ScreenHeader.SIDE_MARGIN + LEFT_W
	left.offset_top = -40
	left.offset_bottom = -40
	left.custom_minimum_size.x = LEFT_W
	left.alignment = BoxContainer.ALIGNMENT_END
	left.add_theme_constant_override("separation", UITheme.SPACING_SMALL)
	add_child(left)
	_buttons_box = left

	training_button = UITheme.create_menu_row("TRAINING GROUND", "", left)
	training_button.pressed.connect(_on_training_pressed)

	connect_button = UITheme.create_menu_row("JOIN SERVER", "", left)
	connect_button.pressed.connect(_on_connect_pressed)

	guide_button = UITheme.create_menu_row("GUIDE", "", left)
	guide_button.pressed.connect(_on_guide_pressed)

	UITheme.create_spacer(false, left).custom_minimum_size.y = UITheme.SPACING_LARGE - UITheme.SPACING_SMALL

	start_button = UITheme.create_play_button("PLAY", "FIND A MATCH", left)
	start_button.pressed.connect(_on_start_pressed)

	# The hero stands in the scene behind (MenuDiorama); their nameplate hangs under the dais
	# (_place_nameplate)
	_build_nameplate()
	# Clicks over the empty scene reach the diorama, the buttons keep theirs
	_let_clicks_through(left)

	# ---- Top bar: one persistent ScreenHeader (MenuShell), shared and kept alive across every
	# menu screen - this scene only tells it which tab is active and what BACK does here
	MenuShell.show_bar()
	header = MenuShell.header
	MenuShell.current = MenuShell.SceneId.MAIN
	MenuShell._mark_active()
	coins_label = header.coins_label
	_update_coins()

	# ---- Right column, top-right under the bar: the players pill, then the party
	var right_col = VBoxContainer.new()
	right_col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_col.offset_left = -ScreenHeader.SIDE_MARGIN - PARTY_W
	right_col.offset_right = -ScreenHeader.SIDE_MARGIN
	right_col.offset_top = ScreenHeader.CONTENT_TOP
	right_col.add_theme_constant_override("separation", UITheme.SPACING_SMALL)
	add_child(right_col)

	# Players: how many signed up and how many are on right now - a compact navy chip with a
	# green dot, right-aligned
	players_pill = PanelContainer.new()
	players_pill.add_theme_stylebox_override("panel", UITheme.navy_box(Color(0.04, 0.06, 0.11, 0.82), Color(1, 1, 1, 0.1), 99, 14, 5))
	players_pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	players_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	players_pill.visible = false
	right_col.add_child(players_pill)
	var pill_row = HBoxContainer.new()
	pill_row.add_theme_constant_override("separation", 8)
	pill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	players_pill.add_child(pill_row)
	var dot = UITheme.create_icon("dot", pill_row, 12, UITheme.ACCENT_SUCCESS)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	players_label = UITheme.create_label("", pill_row, UITheme.FONT_TINY)
	players_label.add_theme_font_override("font", UITheme.font_bold())

	# ---- The party (under the players pill): members, LEAVE, invitations
	party_bar = PartyBar.new()
	party_bar.custom_minimum_size.x = PARTY_W
	right_col.add_child(party_bar)
	party_bar.open_profile.connect(_open_profile)
	players_label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	# ---- Footer (bottom-right): the LAN address for friends in a quiet chip, the version
	var footer = HBoxContainer.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.offset_left = -ScreenHeader.SIDE_MARGIN
	footer.offset_right = -ScreenHeader.SIDE_MARGIN
	footer.offset_top = -40
	footer.offset_bottom = -40
	footer.add_theme_constant_override("separation", 14)
	add_child(footer)
	quit_button = UITheme.create_menu_row("QUIT", "", footer, true)
	quit_button.custom_minimum_size.x = 120
	quit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	quit_button.pressed.connect(_on_quit_pressed)
	var hint_chip = PanelContainer.new()
	hint_chip.add_theme_stylebox_override("panel", UITheme.navy_box(Color(0.04, 0.06, 0.11, 0.78), Color(1, 1, 1, 0.08), 99, 14, 5))
	footer.add_child(hint_chip)
	var hint = UITheme.create_label(_lan_hint(), hint_chip, UITheme.FONT_TINY)
	hint.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	var version = UITheme.create_label(VERSION, footer, UITheme.FONT_TINY)
	version.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	version.add_theme_font_override("font", UITheme.font_bold())
	version.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	version.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.07, 0.7))
	version.add_theme_constant_override("outline_size", 4)
	_let_clicks_through(footer)
	resized.connect(_fit_to_height)
	_fit_to_height()

	_intro_animation(left)

func _intro_animation(node: Control):
	node.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(node, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC)

## The dais always shows the player's own preferred hero (PlayerProfile.preferred_hero_or_first;
## set by CharacterSelect / HeroLineup, remembered across restarts) - never a carousel of them.
## No hero picked yet (a fresh profile before `choose_starters`, or the server hasn't answered):
## an empty dais with an inviting "+" (showcase.show_empty_slot) that opens FRIENDS when clicked.
## force: rebuild even if it is the same hero (the shop just closed - their wear may have changed).
func _refresh_dais(force: bool = false):
	if not showcase:
		return
	var hero_name = PlayerProfile.preferred_hero_or_first()
	if hero_name == _shown_hero and hero_name != "" and not force:
		return  # already showing them (a redundant call after a purchase elsewhere)
	_shown_hero = hero_name
	var data = CharacterRegistry.get_by_name(hero_name) if hero_name != "" else null
	if data == null:
		showcase.show_empty_slot()
		_shown_wear = {}
		showcase_name.text = tr("Invite a friend")
		showcase_name.add_theme_color_override("font_color", UITheme.GOLD.lightened(0.3))
		_nameplate_level.text = ""
		_nameplate_hint.text = tr("Click: friends")
		var empty_bar = nameplate.get_meta("bar") as Panel
		if empty_bar:
			empty_bar.add_theme_stylebox_override("panel", UITheme.glow_box(UITheme.GOLD.lightened(0.15), 0.6, 3, 4))
		return
	var wear = PlayerProfile.equipped_for(data.character_name)
	showcase.show_hero(data, wear.skin, wear.hat)
	_shown_wear = {"skin": wear.skin, "hat": wear.hat}
	showcase_name.text = data.character_name  # translated, then uppercased
	showcase_name.add_theme_color_override("font_color", data.color.lightened(0.45))
	_nameplate_level.text = tr("Lv %d") % PlayerProfile.hero_progress(data.character_name).level
	_nameplate_hint.text = tr("Click the hero: wardrobe")
	var bar = nameplate.get_meta("bar") as Panel
	if bar:
		bar.add_theme_stylebox_override("panel", UITheme.glow_box(data.color.lightened(0.15), 0.6, 3, 4))
	# a little pop as the hero lands
	nameplate.pivot_offset = nameplate.size / 2.0
	nameplate.scale = Vector2.ONE * 0.94
	create_tween().tween_property(nameplate, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Short windows (720 p): the left column tightens up so QUIT stays on screen
func _fit_to_height() -> void:
	if not _buttons_box:
		return
	var compact = size.y > 0.0 and size.y < 840.0
	_buttons_box.add_theme_constant_override("separation", 5 if compact else UITheme.SPACING_SMALL)

## The hero's nameplate under the dais: a colour bar, the name, the mastery level and what a click
## on the hero does (template style: navy chip, the rim turns gold while the hero is pointed at)
func _build_nameplate() -> void:
	nameplate = PanelContainer.new()
	nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nameplate_styles = [
		UITheme.navy_box(Color(0.04, 0.06, 0.11, 0.86), Color(1, 1, 1, 0.12), 14, 16, 9),
		UITheme.navy_box(Color(0.05, 0.07, 0.13, 0.92), Color(UITheme.GOLD, 0.9), 14, 16, 9),
	]
	nameplate.add_theme_stylebox_override("panel", _nameplate_styles[0])
	add_child(nameplate)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	nameplate.add_child(row)
	var bar = Panel.new()
	bar.custom_minimum_size = Vector2(5, 0)
	row.add_child(bar)
	nameplate.set_meta("bar", bar)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)
	showcase_name = UITheme.create_label("", top, 26)
	showcase_name.add_theme_font_override("font", UITheme.font_black())
	showcase_name.uppercase = true
	_nameplate_level = UITheme.create_label("", top, UITheme.FONT_SMALL)
	_nameplate_level.add_theme_font_override("font", UITheme.font_black())
	_nameplate_level.add_theme_color_override("font_color", UITheme.GOLD)
	_nameplate_level.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_nameplate_hint = UITheme.create_label("Click the hero: wardrobe", col, UITheme.FONT_TINY)
	_nameplate_hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_let_clicks_through(nameplate)

## Keeps the nameplate centred under the dais as the camera leans (clear of the left column)
func _place_nameplate(_delta: float) -> void:
	if not nameplate or not showcase:
		return
	nameplate.visible = showcase.visible and showcase_name.text != ""
	if not nameplate.visible:
		return
	var style = _nameplate_styles[1 if showcase.hovered_kind() == "hero" else 0]
	if nameplate.get_theme_stylebox("panel") != style:  # not every frame: a theme change re-lays the labels
		nameplate.add_theme_stylebox_override("panel", style)
	nameplate.reset_size()
	var at = showcase.dais_screen_point() + Vector2(-nameplate.size.x / 2.0, 14.0)
	at.x = clampf(at.x, ScreenHeader.SIDE_MARGIN + LEFT_W + 22.0, maxf(500.0, size.x - nameplate.size.x - 32.0))
	at.y = clampf(at.y, ScreenHeader.CONTENT_TOP, maxf(ScreenHeader.CONTENT_TOP, size.y - nameplate.size.y - 56.0))
	nameplate.position = at

# ---------------------------------------------------------------- the clickable scene

## Every Control under node but the buttons lets the mouse through, so the empty parts of the
## menu don't cover the scene (the buttons stay STOP)
func _let_clicks_through(node: Node) -> void:
	for child in node.get_children():
		if child is BaseButton:
			continue
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_let_clicks_through(child)
	if node is Control and not node is BaseButton:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Something is open over the menu (the guide, settings, mode select, the first start, the update
## offer - shop / profile / friends are separate scenes now, so they replace this one instead):
## the scene doesn't react under it
func _modal_open() -> bool:
	for node in [guide, _mode_picker, _onboarding, _update_dialog]:
		if node != null and is_instance_valid(node) and node.is_inside_tree() and node.visible:
			return true
	return MenuShell._settings_layer != null and is_instance_valid(MenuShell._settings_layer)

## The hero on the dais: their wardrobe (the shop's skins with that hero chosen)
func _on_scene_hero(data: CharacterData) -> void:
	_after_scene_click(func(): _on_shop_pressed("skin", data.character_name))

## A gun on the rack: its finishes
func _on_scene_gun(weapon_type: int) -> void:
	_after_scene_click(func(): _on_shop_pressed("weapon", "", weapon_type))

## The sign -> the guide's weapons, a shelf pickup -> its guide entry, a container -> the shop
func _on_scene_prop(kind: String, data) -> void:
	match kind:
		"sign":
			_after_scene_click(func(): _on_guide_pressed(1))
		"shelf":
			_after_scene_click(func(): _on_guide_pressed(2, String(data)))
		_:
			_after_scene_click(func(): _on_shop_pressed("hero"))

## The clicked thing's juice plays first, then the screen opens (one at a time)
func _after_scene_click(action: Callable) -> void:
	if _scene_action_pending or _modal_open():
		return
	_scene_action_pending = true
	await get_tree().create_timer(SCENE_CLICK_DELAY).timeout
	_scene_action_pending = false
	if not is_inside_tree() or _modal_open():
		return
	action.call()

## A newer release on GitHub (exported Windows game only): offer to update right here
func _check_update():
	var release = await UpdateDialog.check(self, VERSION)
	if release.is_empty() or not is_inside_tree():
		return
	var dialog = UpdateDialog.new()
	dialog.release = release
	add_child(dialog)
	MenuShell.cover(dialog)
	_update_dialog = dialog

# ---------------------------------------------------------------- friends and the party

## Every few seconds: the party / invitations (PartyBar shows them) and, for a party member,
## the leader's search - then we go to the search screen with them
func _poll_party() -> void:
	var online = get_node_or_null("/root/Online")
	if online == null or not online.logged_in:
		return
	var res = await online.poll_party()
	if not is_inside_tree() or res.is_empty() or not online.in_party() or online.is_party_leader():
		return
	if String(res.get("queue", "idle")) in ["searching", "starting", "found"]:
		var gm = get_node_or_null("/root/GameManager")
		var me = online.my_party_member()
		if gm:
			gm.game_mode = String(res.get("mode", gm.game_mode))
			gm.matchmaking = true
			gm.matchmaking_follow = true
			var hero = CharacterRegistry.get_by_name(String(me.get("hero", "")))
			if hero:
				gm.selected_character = hero
		set_process(false)
		_transition_to(MatchmakingScreen.SCENE)

## The small second dais beside the hero: lit up and clickable only while there is a real free
## spot to fill (solo - no party yet - or in a party that isn't full; PartyBar.PARTY_MAX friends).
## Fed by Online.party_changed (poll_party, every PARTY_EVERY s) and the first poll at start.
func _refresh_party_slot() -> void:
	if not showcase:
		return
	var online = get_node_or_null("/root/Online")
	var free = online != null and online.logged_in and (not online.in_party() or online.party().get("members", []).size() < PartyBar.PARTY_MAX)
	showcase.set_party_slot(free)

func _open_friends() -> void:
	MenuShell.goto(MenuShell.SceneId.FRIENDS)

func _open_profile(account_id: int) -> void:
	ProfileScene.open_account_id = account_id
	MenuShell.goto(MenuShell.SceneId.PROFILE)

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
	players_label.text = tr("Online: %d  ·  Registered: %d") % [int(res.get("online", 0)), int(res.get("registered", 0))]
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

	# At the bottom in the middle: the overlays opened over the menu (shop, guide...) keep their
	# headers, tabs and titles up top, and a toast that arrives late (offline) lands over them
	var holder = CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH  # centered, long messages don't run off
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.offset_bottom = -72
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	toast = holder

	var pill = PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	for b in [start_button, connect_button, guide_button, shop_button, training_button, friends_button, profile_button, quit_button]:
		if b:
			b.disabled = not enabled

## PLAY: the mode first (ModeSelect), then the hero and the online queue (MatchmakingScreen) -
## or HOST LAN: this computer hosts the match
func _on_start_pressed():
	if _mode_picker and is_instance_valid(_mode_picker):
		return
	var picker = ModeSelect.new()
	add_child(picker)
	MenuShell.cover(picker)
	_mode_picker = picker
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
	if online.in_party() and not online.is_party_leader():
		show_toast(tr("Only the party leader starts the search"), UITheme.ACCENT_WARNING)
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
	MenuShell._open_settings()

## The guide over the menu; tab / entry: open it on that tab at the entry with that title
func _on_guide_pressed(tab: int = 0, entry: String = ""):
	if guide:
		return
	guide = Encyclopedia.new()
	guide.start_tab = tab
	guide.start_entry = entry
	add_child(guide)
	MenuShell.cover(guide)
	showcase.visible = false  # one 3D preview at a time
	guide.closed.connect(func():
		guide = null
		showcase.visible = true)

func _update_coins():
	if header:
		header.update_coins()

## The shop screen; kind / hero / weapon_type: open it on that tab with that hero or gun chosen
## (the 3D scene's hero -> skins, a gun on the rack -> its finishes)
func _on_shop_pressed(kind: String = "hero", hero: String = "", weapon_type: int = -1):
	ShopScene.open_kind = kind
	ShopScene.open_hero = hero
	ShopScene.open_weapon = weapon_type
	MenuShell.goto(MenuShell.SceneId.SHOP)

## Offline arena with every gun and dummies: go through character select first
func _on_training_pressed():
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.training_mode = true
	_transition_to("res://scenes/CharacterSelectScene.tscn")

func _on_quit_pressed():
	get_tree().quit()

func _transition_to(scene_path: String):
	var transition = get_node_or_null("/root/SceneTransition")
	MenuShell.hide_bar()
	if transition:
		transition.fade_to_scene(scene_path)
	else:
		get_tree().change_scene_to_file(scene_path)
