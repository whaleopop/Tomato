## Hold Tab in a match: everyone's name, hero, kills and ping (the server's round trip to them),
## your own ping on top. The data is GameServer.scoreboard(): once a second in the world state
## ("board", ClientWorld.last_board) on clients, straight from the server on the host. Not on the
## training ground (Tab picks the hero there). Doesn't catch the mouse or block the game.
extends Control
class_name Scoreboard

const GOOD_PING: int = 60
const OK_PING: int = 120

var _panel: PanelContainer
var _rows: VBoxContainer
var _own: Label
var _refresh: float = 0.0

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.03, 0.04, 0.08, 0.86), Color(1, 1, 1, 0.12), 18, 24, 18))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_panel)
	var col = VBoxContainer.new()
	col.custom_minimum_size = Vector2(560, 0)
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	var head = HBoxContainer.new()
	col.add_child(head)
	var title = UITheme.create_heading("PLAYERS", head)
	title.add_theme_font_override("font", UITheme.font_black())
	title.uppercase = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_own = UITheme.create_label("", head, UITheme.FONT_NORMAL)
	_own.add_theme_font_override("font", UITheme.font_black())
	UITheme.create_separator(col)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	col.add_child(_rows)

func _process(delta: float):
	var gm = get_node_or_null("/root/GameManager")
	var want = Input.is_key_pressed(KEY_TAB) and not (gm and gm.training_mode) and DisplayServer.window_is_focused()
	if want != visible:
		visible = want
		_refresh = 0.0
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.5
		_fill()

func _board() -> Dictionary:
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.game_server and nm.game_server.is_running:
		return nm.game_server.scoreboard()
	var scene = get_tree().current_scene
	var cw = scene.get_node_or_null("ClientWorld") if scene else null
	return cw.last_board if cw else {}

func _my_id() -> int:
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.game_client:
		return nm.game_client.local_player_id
	return 1

static func ping_color(ms: int) -> Color:
	if ms <= GOOD_PING:
		return UITheme.ACCENT_SUCCESS
	if ms <= OK_PING:
		return UITheme.ACCENT_WARNING
	return UITheme.ACCENT_DANGER

func _fill() -> void:
	var nm = get_node_or_null("/root/NetworkManager")
	var host = nm != null and nm.game_server != null and nm.game_server.is_running and not nm.game_server.dedicated
	var my_ping = 0 if host else int(NetClock.rtt_ms)
	_own.text = tr("Your ping: %d ms") % my_ping
	_own.add_theme_color_override("font_color", ping_color(my_ping))
	for c in _rows.get_children():
		c.queue_free()
	var board = _board()
	var ids = board.keys()
	ids.sort_custom(func(a, b):
		var ra: Array = board[a]
		var rb: Array = board[b]
		if bool(ra[4]) != bool(rb[4]):
			return bool(ra[4])
		return int(ra[2]) > int(rb[2]))
	_row(["Player", "Hero", "Kills", "Ping"], true, UITheme.TEXT_MUTED, UITheme.TEXT_MUTED, false)
	var me = _my_id()
	for id in ids:
		var r: Array = board[id]
		var team = int(r[5]) if r.size() > 5 else -1
		var name_color = GameModes.TEAM_COLORS[team].lightened(0.25) if team >= 0 and team < GameModes.TEAM_COLORS.size() else UITheme.TEXT_PRIMARY
		if int(id) == me:
			name_color = UITheme.ACCENT_PRIMARY.lightened(0.2)
		var ping = int(r[3])
		var ping_text = tr("host") if host and int(id) == 1 else tr("%d ms") % ping
		_row([String(r[0]), tr(String(r[1])), str(int(r[2])), ping_text], false, name_color, ping_color(ping), not bool(r[4]))

func _row(cells: Array, header: bool, name_color: Color, ping_color_value: Color, out: bool) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if out:
		row.modulate.a = 0.45  # eliminated / waiting to respawn
	_rows.add_child(row)
	var widths = [220, 140, 70, 90]
	for i in cells.size():
		var l = UITheme.create_label(tr(cells[i]) if header else cells[i], row, UITheme.FONT_SMALL if header else UITheme.FONT_NORMAL)
		l.custom_minimum_size.x = widths[i]
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if header:
			l.uppercase = true
		if i >= 2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if not header:
			if i == 0:
				l.add_theme_color_override("font_color", name_color)
				l.add_theme_font_override("font", UITheme.font_black())
			elif i == 3:
				l.add_theme_color_override("font_color", ping_color_value)
		else:
			l.add_theme_color_override("font_color", name_color)
