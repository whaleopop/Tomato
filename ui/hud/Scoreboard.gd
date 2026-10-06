## Hold Tab in a match: everyone's name, hero, kills and ping (the server's round trip to them),
## your own ping on top. The data is GameServer.scoreboard(): once a second in the world state
## ("board", ClientWorld.last_board) on clients, straight from the server on the host. Not on the
## training ground (Tab picks the hero there). Doesn't catch the mouse or block the game.
extends Control
class_name Scoreboard

const GOOD_PING: int = 60
const OK_PING: int = 120
const WIDTH: int = 620
const COLUMN_WIDTHS = [28, 180, 130, 84, 80]  # #, player, hero, kills, ping

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
	# The main menu's navy card: a gold kicker (the mode) over the title, your ping on the right
	_panel = UITheme.navy_panel(center, 24)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col = VBoxContainer.new()
	col.custom_minimum_size = Vector2(WIDTH, 0)
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)
	var head = HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var titles = UITheme.create_screen_title("PLAYERS", String(GameModes.info(GameModes.current()).name), head)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ping_pill = PanelContainer.new()
	ping_pill.add_theme_stylebox_override("panel", UITheme.navy_box(UITheme.NAVY, Color(1, 1, 1, 0.12), 99, 14, 6))
	ping_pill.size_flags_vertical = Control.SIZE_SHRINK_END
	ping_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(ping_pill)
	_own = UITheme.create_label("", ping_pill, UITheme.FONT_SMALL)
	_own.add_theme_font_override("font", UITheme.font_black())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_row(["#", "Player", "Hero", "Kills", "Ping"], true, UITheme.TEXT_MUTED, UITheme.TEXT_MUTED, false)
	var me = _my_id()
	var place = 0
	for id in ids:
		var r: Array = board[id]
		place += 1
		var team = int(r[5]) if r.size() > 5 else -1
		var team_color = GameModes.TEAM_COLORS[team] if team >= 0 and team < GameModes.TEAM_COLORS.size() else Color(0, 0, 0, 0)
		var name_color = team_color.lightened(0.25) if team_color.a > 0.0 else UITheme.TEXT_PRIMARY
		var mine = int(id) == me
		if mine:
			name_color = UITheme.GOLD
		var ping = int(r[3])
		var ping_text = tr("host") if host and int(id) == 1 else tr("%d ms") % ping
		_row([str(place), String(r[0]), tr(String(r[1])), str(int(r[2])), ping_text], false, name_color, ping_color(ping), not bool(r[4]), mine, team_color)

## One line of the table: the header plain, a player as a navy row (yours gold, a team stripe on
## the left in team modes, faded when out)
func _row(cells: Array, header: bool, name_color: Color, ping_color_value: Color, out: bool, mine: bool = false, team_color: Color = Color(0, 0, 0, 0)) -> void:
	var holder: Control
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if header:
		var pad = MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 16)
		pad.add_theme_constant_override("margin_right", 16)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(row)
		holder = pad
	else:
		var panel = PanelContainer.new()
		var fill = Color(0.20, 0.15, 0.03, 0.92) if mine else UITheme.NAVY
		var rim = Color(UITheme.GOLD, 0.85) if mine else Color(1, 1, 1, 0.08)
		var box = UITheme.navy_box(fill, rim, 10, 16, 7)
		if mine:
			box.set_border_width_all(2)
			box.shadow_color = Color(UITheme.GOLD, 0.25)
			box.shadow_size = 10
		elif team_color.a > 0.0:
			box.border_width_left = 4
			box.border_color = Color(team_color, 0.7)
		panel.add_theme_stylebox_override("panel", box)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		holder = panel
		if out:
			holder.modulate.a = 0.45  # eliminated / waiting to respawn
	_rows.add_child(holder)
	for i in cells.size():
		var l = UITheme.create_label(tr(cells[i]) if header else cells[i], row, UITheme.FONT_TINY if header else UITheme.FONT_NORMAL)
		l.custom_minimum_size.x = COLUMN_WIDTHS[i]
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 1:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i >= 3:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if header:
			l.uppercase = true
			l.add_theme_font_override("font", UITheme.font_black())
			l.add_theme_color_override("font_color", name_color)
			continue
		match i:
			0:
				l.add_theme_font_override("font", UITheme.font_black())
				l.add_theme_color_override("font_color", UITheme.GOLD if mine else UITheme.TEXT_MUTED)
			1:
				l.add_theme_color_override("font_color", name_color)
				l.add_theme_font_override("font", UITheme.font_black())
			2:
				l.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
			3:
				l.add_theme_font_override("font", UITheme.font_black())
				l.add_theme_color_override("font_color", UITheme.GOLD if mine else UITheme.TEXT_PRIMARY)
			4:
				l.add_theme_color_override("font_color", ping_color_value)
