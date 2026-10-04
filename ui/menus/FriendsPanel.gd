## FRIENDS (main menu): find players by nickname and send a request; your friends with what they are
## doing (in the menu / searching / in a match / offline), INVITE to the party, PROFILE, remove;
## requests to you with ACCEPT / DECLINE. Talks to the backend through Online (GET /friends,
## /users/search, /friends/*, /party/invite). Esc or BACK closes; it refreshes itself every few seconds.
extends Control
class_name FriendsPanel

signal closed
signal open_profile(account_id: int)

const REFRESH: float = 5.0
const STATE_COLORS = {"online": Color(0.4, 0.9, 0.5), "searching": Color(1.0, 0.8, 0.35), "match": Color(0.95, 0.45, 0.4), "offline": Color(0.5, 0.52, 0.6)}
const STATE_NAMES = {"online": "In the menu", "searching": "Searching for a match", "match": "In a match", "offline": "Offline"}

var _search: LineEdit
var _results: VBoxContainer
var _friends: VBoxContainer
var _status: Label
var _timer: float = 0.0

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("blocks_game_input")
	var dim = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = UITheme.create_panel(center, 26)
	var col = VBoxContainer.new()
	col.custom_minimum_size = Vector2(900, 560)
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var head = HBoxContainer.new()
	col.add_child(head)
	var title = UITheme.create_title("FRIENDS", head)
	title.add_theme_font_override("font", UITheme.font_black())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var back = UITheme.create_button("BACK", head, Vector2(140, 48))
	back.pressed.connect(_close)
	_status = UITheme.create_label("", col, UITheme.FONT_SMALL)
	_status.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(columns)
	# Left: find players
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 360
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	UITheme.create_caption("Find players", left)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	left.add_child(row)
	_search = UITheme.create_line_edit("Nickname...", row)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t): _do_search())
	var go = UITheme.create_primary_button("FIND", row, Vector2(100, 44))
	go.pressed.connect(_do_search)
	_results = VBoxContainer.new()
	_results.add_theme_constant_override("separation", 6)
	left.add_child(_scroll(_results))
	# Right: friends and requests
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	UITheme.create_caption("Your friends", right)
	_friends = VBoxContainer.new()
	_friends.add_theme_constant_override("separation", 6)
	right.add_child(_scroll(_friends))
	_refresh()

func _scroll(content: Control) -> ScrollContainer:
	var s = ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s

func _process(delta: float):
	_timer += delta
	if _timer >= REFRESH:
		_refresh()

func _online():
	return get_node_or_null("/root/Online")

func _refresh() -> void:
	_timer = 0.0
	var online = _online()
	if online == null or not online.logged_in:
		_status.text = tr("No connection to the game server")
		return
	var res = await online.request(HTTPClient.METHOD_GET, "/friends")
	if not is_inside_tree() or not res.get("ok", false):
		return
	_fill_friends(res)

func _fill_friends(res: Dictionary) -> void:
	for c in _friends.get_children():
		c.queue_free()
	for f in res.get("incoming", []):
		var row = _player_row(_friends, f, tr("wants to be your friend"), UITheme.ACCENT_PRIMARY)
		_btn(row, "ACCEPT", true, func(): _act("/friends/accept", {"id": int(f.id)}))
		_btn(row, "DECLINE", false, func(): _act("/friends/decline", {"id": int(f.id)}))
	var party_ids = {}
	var online = _online()
	for m in online.party().get("members", []):
		party_ids[int(m.id)] = true
	for f in res.get("friends", []):
		var state = String(f.state)
		var row = _player_row(_friends, f, tr(STATE_NAMES.get(state, state)), STATE_COLORS.get(state, Color.WHITE))
		if party_ids.has(int(f.id)):
			UITheme.create_label("In your party", row, UITheme.FONT_TINY).add_theme_color_override("font_color", UITheme.ACCENT_INFO)
		elif state != "offline":
			_btn(row, "INVITE", true, func():
				var r = await online.party_action("/party/invite", {"id": int(f.id)})
				_status.text = tr("Invitation sent to %s") % String(f.nickname) if r.get("ok", false) else tr(String(r.get("error", "")))
				_status.add_theme_color_override("font_color", UITheme.ACCENT_SUCCESS if r.get("ok", false) else UITheme.ACCENT_DANGER))
		_btn(row, "PROFILE", false, func(): open_profile.emit(int(f.id)))
		_btn(row, "✕", false, func(): _act("/friends/remove", {"id": int(f.id)}))
	for f in res.get("outgoing", []):
		_player_row(_friends, f, tr("request sent"), UITheme.TEXT_MUTED)
	if _friends.get_child_count() == 0:
		var hint = UITheme.create_label("No friends yet: find a player by nickname on the left", _friends, UITheme.FONT_SMALL)
		hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _do_search() -> void:
	var online = _online()
	var q = _search.text.strip_edges()
	if online == null or q.length() < 2:
		_status.text = tr("Type at least 2 letters of the nickname")
		return
	var res = await online.request(HTTPClient.METHOD_POST, "/users/search", {"q": q})
	if not is_inside_tree():
		return
	for c in _results.get_children():
		c.queue_free()
	var players: Array = res.get("players", [])
	if players.is_empty():
		UITheme.create_label("Nobody found", _results, UITheme.FONT_SMALL).add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	for pl in players:
		var state = String(pl.state)
		var row = _player_row(_results, pl, tr(STATE_NAMES.get(state, state)), STATE_COLORS.get(state, Color.WHITE))
		match String(pl.relation):
			"none":
				_btn(row, "ADD", true, func():
					await _act("/friends/add", {"id": int(pl.id)})
					_do_search())
			"incoming":
				_btn(row, "ACCEPT", true, func():
					await _act("/friends/accept", {"id": int(pl.id)})
					_do_search())
			"requested":
				UITheme.create_label("request sent", row, UITheme.FONT_TINY).add_theme_color_override("font_color", UITheme.TEXT_MUTED)
			"friend":
				UITheme.create_label("friend", row, UITheme.FONT_TINY).add_theme_color_override("font_color", UITheme.ACCENT_SUCCESS)
		_btn(row, "PROFILE", false, func(): open_profile.emit(int(pl.id)))

func _act(path: String, body: Dictionary) -> void:
	var res = await _online().request(HTTPClient.METHOD_POST, path, body)
	if is_inside_tree() and res.get("ok", false) and res.has("friends"):
		_fill_friends(res)

## A row: status dot, nickname over what they do / the hero, then the caller's buttons
func _player_row(parent: Control, p: Dictionary, sub: String, dot_color: Color) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var dot = ColorRect.new()
	dot.color = dot_color
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var names = VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	var nick = UITheme.create_label(String(p.nickname), names, UITheme.FONT_NORMAL)
	nick.add_theme_font_override("font", UITheme.font_black())
	var line = UITheme.create_label("%s  ·  %s" % [sub, tr(String(p.get("hero", "")))], names, UITheme.FONT_TINY)
	line.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	return row

func _btn(row: Control, text: String, primary: bool, action: Callable) -> void:
	var b = UITheme.create_primary_button(text, row, Vector2(0, 34)) if primary else UITheme.create_button(text, row, Vector2(0, 34))
	b.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	b.custom_minimum_size.x = 44 if text == "✕" else 92
	b.pressed.connect(action)

func _close() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()
