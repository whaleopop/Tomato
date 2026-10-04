## The online queue (PLAY: mode -> hero -> here): the backend's matchmaker (tools/server/backend)
## puts us into a match with others of the same mode and starts a game server for it; we connect,
## show our ticket (NetworkLobby.client_present_ticket - the name and hero come with it) and go to
## the landing pick (SpawnSelectScene). CANCEL / Esc leave the queue.
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
var _spinner: Control

func _ready():
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		_mode = String(gm.game_mode)
		_hero = gm.selected_character
	_build_ui()
	var online = get_node_or_null("/root/Online")
	if online == null or _hero == null:
		_fail("No connection to the game server")
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
	UITheme.create_background(self)
	var info = GameModes.info(_mode)
	var color: Color = info.color
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = UITheme.create_panel(center, 36)
	var col = VBoxContainer.new()
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var kicker = UITheme.create_label(tr(String(info.name)), col, UITheme.FONT_SMALL)
	kicker.add_theme_font_override("font", UITheme.font_black())
	kicker.add_theme_color_override("font_color", color.lightened(0.3))
	kicker.uppercase = true
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title = UITheme.create_title("SEARCHING FOR A MATCH", col)
	_title.add_theme_font_override("font", UITheme.font_black())
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_spinner = _Spinner.new()
	_spinner.color = color
	_spinner.custom_minimum_size = Vector2(0, 90)
	col.add_child(_spinner)

	_timer_label = UITheme.create_label("0:00", col, UITheme.FONT_TITLE)
	_timer_label.add_theme_font_override("font", UITheme.font_black())
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = UITheme.create_label("Joining the queue...", col, UITheme.FONT_NORMAL)
	_status.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _hero:
		var hero_line = UITheme.create_label(tr("Hero: %s") % tr(_hero.character_name), col, UITheme.FONT_SMALL)
		hero_line.add_theme_color_override("font_color", _hero.color.lightened(0.3))
		hero_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_cancel = UITheme.create_button("CANCEL", col, Vector2(220, 52))
	_cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel.pressed.connect(_leave)

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
			_status.text = tr("Starting the server...")
		"found":
			_title.text = tr("MATCH FOUND")
			_join(int(res.port), String(res.ticket))
		"idle":
			_fail("You dropped out of the queue")

func _join(port: int, ticket: String):
	_polling = false
	_status.text = tr("Joining...")
	_cancel.disabled = true
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
	_spinner.visible = false
	_title.text = tr("NO MATCH")
	_status.text = tr(reason)
	_status.add_theme_color_override("font_color", UITheme.ACCENT_DANGER)
	_cancel.disabled = false
	_cancel.text = tr("BACK")

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

## Three dots chasing round a ring while we wait
class _Spinner extends Control:
	var color: Color = Color.WHITE
	var _t: float = 0.0

	func _process(delta: float):
		_t += delta
		queue_redraw()

	func _draw():
		var c = size / 2.0
		var r = minf(size.y, size.x) * 0.32
		draw_arc(c, r, 0.0, TAU, 48, Color(color, 0.15), 3.0, true)
		for i in 3:
			var a = _t * 3.2 - i * 0.45
			draw_circle(c + Vector2(cos(a), sin(a)) * r, 6.0 - i * 1.5, Color(color, 1.0 - i * 0.28))
