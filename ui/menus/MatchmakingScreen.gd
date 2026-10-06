## The online queue (PLAY: mode -> hero -> here): the backend's matchmaker (tools/server/backend)
## puts us into a match with others of the same mode and starts a game server for it; we connect,
## show our ticket (NetworkLobby.client_present_ticket - the name and hero come with it) and go to
## the landing pick (SpawnSelectScene). BACK / CANCEL / Esc leave the queue.
## Looks like the main menu: the screen header (the mode as its kicker), our hero on a turntable
## (drag to turn it) and a navy panel with the gold search ring, the time and what we queued for.
extends Control
class_name MatchmakingScreen

const SCENE: String = "res://scenes/MatchmakingScene.tscn"
const POLL_EVERY: float = 1.0

var _mode: String = GameModes.BR
var _hero: CharacterData = null
var _elapsed: float = 0.0
var _poll_timer: float = 0.0
var _polling: bool = false
var _asking: bool = false
var _leaving: bool = false
var _title: Label
var _timer_label: Label
var _status: Label
var _cancel: Button
var _spinner: _Spinner
var _header: ScreenHeader
var _showcase: CharacterShowcase = null
var _following: bool = false  # a party member: the leader queued us

func _ready():
	MenuShell.hide_bar()  # this screen has its own header
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		_mode = String(gm.game_mode)
		_hero = gm.selected_character
	_build_ui()
	var online = get_node_or_null("/root/Online")
	if online == null or _hero == null:
		_fail("No connection to the game server")
		return
	# In a party but not its leader: the leader's search took us along, we only follow it
	if gm and gm.matchmaking_follow:
		_following = true
		_status.text = tr("The party leader is searching for a match")
		_polling = true
		return
	var res = await online.request(HTTPClient.METHOD_POST, "/queue/join", {"mode": _mode, "hero": _hero.character_name})
	if not is_inside_tree() or _leaving:
		return
	if not res.get("ok", false):
		_fail(String(res.get("error", "No connection to the game server")))
		return
	_polling = true
	_show_state(res)

func _build_ui():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.create_background(self, true)
	var info = GameModes.info(_mode)
	var color: Color = info.color

	# The bar every screen has: back = leave the queue, the mode as the kicker, settings without a
	# scene reload (that would drop us out of the queue)
	_header = ScreenHeader.make(self, "SEARCHING FOR A MATCH", String(info.name))
	_header.back_pressed.connect(_on_back)
	_header.add_settings_chip(false)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_top = ScreenHeader.CONTENT_TOP
	margin.offset_left = 40
	margin.offset_right = -40
	margin.offset_bottom = -32
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var body = HBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 48)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(body)

	# Our hero on a turntable (drag to turn it, wheel to zoom) while we wait
	if _hero:
		var stage = VBoxContainer.new()
		stage.custom_minimum_size.x = 420
		stage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stage.add_theme_constant_override("separation", 0)
		stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(stage)
		_showcase = CharacterShowcase.new()
		_showcase.custom_minimum_size = Vector2(420, 480)
		stage.add_child(_showcase)
		_showcase.interactive = true
		var wear = PlayerProfile.equipped_for(_hero.character_name)
		_showcase.show_character_with_wear(_hero, wear.skin, wear.hat)
		var names = UITheme.create_screen_title(_hero.character_name, "YOUR HERO", stage)
		for label in names.get_children():
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		names.get_child(names.get_child_count() - 1).add_theme_color_override("font_color", _hero.color.lightened(0.35))

	var panel = UITheme.navy_panel(body, 32)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col = VBoxContainer.new()
	col.custom_minimum_size = Vector2(480, 0)
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)

	var kicker = UITheme.create_label("Matchmaking", col, 12)
	kicker.add_theme_font_override("font", UITheme.font_black())
	kicker.add_theme_color_override("font_color", UITheme.GOLD)
	kicker.uppercase = true
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title = UITheme.create_title("IN QUEUE", col)
	_title.add_theme_font_override("font", UITheme.font_black())
	_title.add_theme_font_size_override("font_size", 30)
	_title.uppercase = true
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# The ring with the search time inside it
	_spinner = _Spinner.new()
	_spinner.color = UITheme.GOLD
	_spinner.custom_minimum_size = Vector2(0, 150)
	col.add_child(_spinner)
	_timer_label = UITheme.create_label("0:00", _spinner, UITheme.FONT_TITLE)
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_timer_label.add_theme_font_override("font", UITheme.font_black())
	_timer_label.add_theme_color_override("font_color", UITheme.GOLD)
	_timer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_timer_label.add_theme_constant_override("shadow_offset_y", 2)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_status = UITheme.create_label("Joining the queue...", col, UITheme.FONT_NORMAL)
	_status.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 26

	# What we queued for: the mode and the hero, as the menu's navy rows
	var rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	col.add_child(rows)
	_info_row(rows, _ModeDot.new(color), "Mode", String(info.name), String(info.short), color)
	if _hero:
		var portrait = TextureRect.new()
		portrait.custom_minimum_size = Vector2(40, 40)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wear = PlayerProfile.equipped_for(_hero.character_name)
		var portrait_ref = weakref(portrait)  # the render may land after the screen is gone
		ItemRenderer.get_instance(get_tree()).hero(_hero.character_name, String(wear.skin), String(wear.hat),
			func(tex): if portrait_ref.get_ref(): portrait_ref.get_ref().texture = HeroChips._crop(tex, false))
		_info_row(rows, portrait, "Hero", _hero.character_name, "", _hero.color)

	_cancel = UITheme.create_button("CANCEL", col, Vector2(0, 52))
	_cancel.add_theme_font_override("font", UITheme.font_black())
	_cancel.pressed.connect(_leave)
	var esc = UITheme.create_label("Esc - leave the queue", col, UITheme.FONT_TINY)
	esc.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	esc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## A navy row: an icon in a tinted frame, a small gold kicker over a name and a muted line
func _info_row(parent: Control, icon: Control, kicker: String, title: String, detail: String, accent: Color):
	var row = PanelContainer.new()
	row.add_theme_stylebox_override("panel", UITheme.navy_box(UITheme.NAVY, Color(accent, 0.35), 12, 12, 8))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var line = HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var frame = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.glass_box(Color(accent, 0.16), Color(accent.lightened(0.3), 0.7), 10, 2, 2))
	frame.custom_minimum_size = Vector2(44, 44)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(icon)
	line.add_child(frame)
	var texts = VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -3)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(texts)
	var k = UITheme.create_label(kicker, texts, 11)
	k.uppercase = true
	k.add_theme_font_override("font", UITheme.font_black())
	k.add_theme_color_override("font_color", UITheme.GOLD)
	var t = UITheme.create_label(title, texts, UITheme.FONT_NORMAL)
	t.add_theme_font_override("font", UITheme.font_black())
	t.add_theme_color_override("font_color", accent.lightened(0.35))
	if detail != "":
		var d = UITheme.create_label(detail, texts, UITheme.FONT_TINY)
		d.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _process(delta: float):
	if not _polling:
		return
	_elapsed += delta
	_timer_label.text = "%d:%02d" % [int(_elapsed) / 60, int(_elapsed) % 60]
	_poll_timer += delta
	if _poll_timer >= POLL_EVERY and not _asking:
		_poll_timer = 0.0
		_poll()

func _poll():
	_asking = true
	var online = get_node("/root/Online")
	var res = await online.request(HTTPClient.METHOD_GET, "/queue/status")
	_asking = false
	if not is_inside_tree() or not _polling:
		return
	if not res.get("ok", false):
		_status.text = tr(String(res.get("error", "No connection to the game server")))
		return
	_show_state(res)

func _show_state(res: Dictionary):
	match String(res.get("state", "")):
		"searching":
			if res.get("busy", false):
				_status.text = tr("All servers are busy - waiting for a free one")
			else:
				_status.text = tr("In queue: %d  ·  needed: %d") % [int(res.get("in_queue", 1)), int(res.get("need", 2))]
		"starting":
			_title.text = tr("MATCH FOUND")
			_spinner.found = true
			_status.text = tr("Starting the server...")
		"found":
			_title.text = tr("MATCH FOUND")
			_spinner.found = true
			Sfx.ui("match_found")
			_join(int(res.port), String(res.ticket))
		"idle":
			_fail("The party leader stopped the search" if _following else "You dropped out of the queue")

func _join(port: int, ticket: String):
	_polling = false
	_status.text = tr("Joining...")
	_set_leavable(false)
	var nm = get_node("/root/NetworkManager")
	if not nm.start_client(get_node("/root/Online").host(), port):
		_fail("Could not join the match")
		return
	nm.game_client.connected_to_server.connect(func():
		nm.network_lobby.client_present_ticket(ticket)
		_go("res://scenes/SpawnSelectScene.tscn"), CONNECT_ONE_SHOT)
	nm.game_client.connection_failed.connect(func(): _fail("Could not join the match"), CONNECT_ONE_SHOT)

func _fail(reason: String):
	_polling = false
	_spinner.found = false
	_spinner.failed = true
	_timer_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_title.text = tr("NO MATCH")
	_title.add_theme_color_override("font_color", UITheme.ACCENT_DANGER.lightened(0.25))
	_status.text = tr(reason)
	_status.add_theme_color_override("font_color", UITheme.ACCENT_DANGER)
	_set_leavable(true)
	_cancel.text = tr("BACK")
	UITheme.set_accent(_cancel, UITheme.GOLD, Color(0.10, 0.06, 0.0))

## The header's BACK: leaves the queue like CANCEL - not while we are connecting to the match
func _on_back():
	if not _cancel.disabled:
		_leave()

func _set_leavable(on: bool):
	_cancel.disabled = not on
	if _header and _header.back_button:
		_header.back_button.disabled = not on

func _leave():
	if _leaving:
		return
	_leaving = true
	_polling = false
	var online = get_node_or_null("/root/Online")
	if online:
		online.request(HTTPClient.METHOD_POST, "/queue/leave")
	_go("res://scenes/MainMenuScene.tscn")  # the menu stops any half-made connection

func _go(scene: String):
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene(scene)
	else:
		get_tree().change_scene_to_file(scene)

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause") and not _cancel.disabled:
		_leave()
		get_viewport().set_input_as_handled()

## Three gold dots chasing round a ring while we wait (the time sits inside it); `found` lights the
## ring up, `failed` stops it and turns it red
class _Spinner extends Control:
	var color: Color = Color.WHITE
	var found: bool = false
	var failed: bool = false
	var _t: float = 0.0

	func _init():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float):
		if not failed:
			_t += delta
		queue_redraw()

	func _draw():
		var c = size / 2.0
		var r = minf(size.y, size.x) * 0.42
		draw_circle(c, r - 4.0, Color(0.02, 0.03, 0.07, 0.55))
		if failed:
			draw_arc(c, r, 0.0, TAU, 64, Color(UITheme.ACCENT_DANGER, 0.6), 4.0, true)
			return
		var pulse = 0.5 + 0.5 * sin(_t * 2.4)
		draw_arc(c, r + 8.0, 0.0, TAU, 64, Color(color, 0.05 + 0.06 * pulse), 10.0, true)
		draw_arc(c, r, 0.0, TAU, 64, Color(color, 0.9 if found else 0.18 + 0.06 * pulse), 4.0 if found else 3.0, true)
		if found:
			return
		for i in 3:
			var a = _t * 3.2 - i * 0.45
			draw_circle(c + Vector2(cos(a), sin(a)) * r, 7.0 - i * 1.6, Color(color, 1.0 - i * 0.28))

## The mode's color as a small glowing hex (the mode row's icon)
class _ModeDot extends Control:
	var color: Color

	func _init(c: Color):
		color = c
		custom_minimum_size = Vector2(40, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw():
		var c = size / 2.0
		draw_circle(c, 15.0, Color(color, 0.22))
		var pts = PackedVector2Array()
		for i in 7:
			var a = TAU * i / 6.0 + PI / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * 10.0)
		var fill = pts.slice(0, 6)
		draw_colored_polygon(fill, color)
		draw_polyline(pts, color.lightened(0.5), 1.5, true)
