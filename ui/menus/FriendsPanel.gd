## FRIENDS (main menu): a screen in the main menu's look - the shared top bar (BACK closes), tabs
## FRIENDS / REQUESTS / FIND PLAYERS over a navy list, and on the right the chosen player's hero in
## an interactive 3D showcase (drag to turn, wheel to zoom) with what you can do with them.
## Friends show what they are doing (in the menu / searching / in a match / offline); INVITE to the
## party (or drag a friend's row onto the golden pad), PROFILE, remove; requests to you with
## ACCEPT / DECLINE; find players by nickname and send a request. Talks to the backend through
## Online (GET /friends, /users/search, /friends/*, /party/invite). Esc or BACK closes; it refreshes
## itself every few seconds. Offline: a "No connection to the game server" notice with TRY AGAIN.
extends Control
class_name FriendsPanel

signal closed
signal open_profile(account_id: int)

const REFRESH: float = 5.0
const STATE_COLORS = {"online": Color(0.4, 0.9, 0.5), "searching": Color(1.0, 0.8, 0.35), "match": Color(0.95, 0.45, 0.4), "offline": Color(0.5, 0.52, 0.6)}
const STATE_NAMES = {"online": "In the menu", "searching": "Searching for a match", "match": "In a match", "offline": "Offline"}
const SIDE_WIDTH: int = 420
const ROW_HEIGHT: int = 68

var _search: LineEdit
var _results: VBoxContainer        # search results
var _friends: VBoxContainer        # your friends
var _requests: VBoxContainer       # requests to you and from you
var _status: Label
var _timer: float = 0.0
var _header: ScreenHeader
var _body: HBoxContainer
var _notice: Control = null
var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _tab: int = 0
var _last: Dictionary = {}         # the last /friends answer
var _first_fill: bool = true
# The chosen player (right side)
var _side: VBoxContainer
var _selected: Dictionary = {}     # {"p": player card, "relation": friend / incoming / requested / none}
var _selected_wear: String = ""
var _sel_state: Label
var _sel_name: Label
var _sel_line: Label
var _sel_hint: Label
var _sel_empty: Label
var _showcase: CharacterShowcase
var _sel_actions: VBoxContainer
var _pad: DropPad

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UITheme.create_background(self)  # the menus' night sky: the main menu stays out of sight

	var content = MarginContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_top = ScreenHeader.CONTENT_TOP
	content.offset_left = ScreenHeader.SIDE_MARGIN
	content.offset_right = -ScreenHeader.SIDE_MARGIN
	content.offset_bottom = -28
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 24)
	content.add_child(_body)

	# Left: tabs over the list
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 14)
	_body.add_child(left)
	var tab_row = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	left.add_child(tab_row)
	for i in 3:
		var tab = UITheme.create_tab("", tab_row)
		tab.pressed.connect(_show_tab.bind(i))
		_tabs.append(tab)
	_status = UITheme.create_label("", tab_row, UITheme.FONT_SMALL)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.clip_text = true
	_status.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	var list_panel = UITheme.navy_panel(left, 18)
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stack = Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_panel.add_child(stack)
	_friends = VBoxContainer.new()
	_requests = VBoxContainer.new()
	_results = VBoxContainer.new()
	_pages.append(_page(stack, _scroll(_friends)))
	_pages.append(_page(stack, _scroll(_requests)))
	var search_page = VBoxContainer.new()
	search_page.add_theme_constant_override("separation", 14)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	search_page.add_child(row)
	_search = UITheme.create_line_edit("Nickname...", row)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.y = 48
	_search.text_submitted.connect(func(_t): _do_search())
	var go = UITheme.create_primary_button("FIND", row, Vector2(130, 48))
	go.pressed.connect(_do_search)
	search_page.add_child(_scroll(_results))
	_pages.append(_page(stack, search_page))
	_empty_state(_results, "⌕", "Find players", "Type at least 2 letters of the nickname")
	var tip = UITheme.create_label("Click a player to see their hero  ·  double click opens the profile  ·  drag a friend onto the golden pad to invite them", left, 11)
	tip.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Right: the chosen player
	_side = VBoxContainer.new()
	_side.custom_minimum_size.x = SIDE_WIDTH
	_side.add_theme_constant_override("separation", 14)
	_body.add_child(_side)
	var card = UITheme.navy_panel(_side, 20)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	_sel_state = UITheme.create_label("", col, 12)
	_sel_state.uppercase = true
	_sel_state.add_theme_font_override("font", UITheme.font_black())
	_sel_state.add_theme_color_override("font_color", UITheme.GOLD)
	_sel_name = UITheme.create_heading("", col)
	_sel_name.add_theme_font_override("font", UITheme.font_black())
	_sel_name.add_theme_font_size_override("font_size", 30)
	_sel_name.clip_text = true
	_sel_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sel_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_sel_line = UITheme.create_label("", col, UITheme.FONT_SMALL)
	_sel_line.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	var stage = PanelContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.02, 0.03, 0.06, 0.6), Color(1, 1, 1, 0.06), 14, 0, 0))
	col.add_child(stage)
	_showcase = CharacterShowcase.new()
	_showcase.custom_minimum_size = Vector2(0, 200)
	_showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_showcase.interactive = true
	_showcase.visible = false
	stage.add_child(_showcase)
	_sel_empty = UITheme.create_label("Pick a player on the left", stage, UITheme.FONT_SMALL)
	_sel_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sel_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sel_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_empty.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_sel_hint = UITheme.create_label("Drag to turn  ·  wheel to zoom  ·  double click to reset", col, 11)
	_sel_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sel_hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_sel_hint.visible = false
	_sel_actions = VBoxContainer.new()
	_sel_actions.add_theme_constant_override("separation", 8)
	col.add_child(_sel_actions)
	# The golden slot: drag a friend's row here to invite them
	_pad = DropPad.new()
	_pad.caption = "DRAG A FRIEND HERE"
	_pad.detail = tr("to invite them to your party")
	_pad.icon = "crown"
	_pad.accepts = func(payload): return payload is Dictionary and payload.has("invite")
	_pad.dropped.connect(func(payload): _invite(int(payload.invite), String(payload.get("nickname", ""))))
	_side.add_child(_pad)

	MenuShell.show_bar()
	_header = MenuShell.header
	MenuShell.current = MenuShell.SceneId.FRIENDS
	MenuShell._mark_active()
	if not _header.back_pressed.is_connected(_close):
		_header.back_pressed.connect(_close)
	if not open_profile.is_connected(_goto_profile):
		open_profile.connect(_goto_profile)
	_update_tabs()
	_show_tab(0)
	_select({})
	_refresh()

func _goto_profile(account_id: int) -> void:
	ProfileScene.open_account_id = account_id
	MenuShell.goto(MenuShell.SceneId.PROFILE)

## A page of the tab stack: fills it, only the active one shows
func _page(stack: Control, page: Control) -> Control:
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.visible = false
	stack.add_child(page)
	return page

func _scroll(content: Control) -> ScrollContainer:
	var s = ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	s.add_child(content)
	return s

func _show_tab(index: int) -> void:
	_tab = index
	for i in _tabs.size():
		UITheme.set_tab_active(_tabs[i], i == index)
		_pages[i].visible = i == index
	_update_tabs()
	if index == 2 and is_inside_tree():
		_search.grab_focus.call_deferred()

## Tab texts with their counts
func _update_tabs() -> void:
	var friends: Array = _last.get("friends", [])
	var incoming: Array = _last.get("incoming", [])
	_tabs[0].text = tr("FRIENDS") + ("   %d" % friends.size() if not friends.is_empty() else "")
	_tabs[1].text = tr("Requests").to_upper() + ("   %d" % incoming.size() if not incoming.is_empty() else "")
	_tabs[2].text = tr("Find players").to_upper()
	# Requests waiting for an answer: the tab glows gold
	_tabs[1].add_theme_color_override("font_color", UITheme.GOLD if not incoming.is_empty() and _tab != 1 else (Color.WHITE if _tab == 1 else UITheme.TEXT_SECONDARY))

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
		_show_offline(true)
		return
	var res = await online.request(HTTPClient.METHOD_GET, "/friends")
	if not is_inside_tree():
		return
	if not res.get("ok", false):
		if _last.is_empty():
			_show_offline(true)
		return
	_show_offline(false)
	_fill_friends(res)

## Offline / no answer: the notice instead of the lists
func _show_offline(offline: bool) -> void:
	_body.visible = not offline
	if offline and _notice == null:
		_notice = make_notice(self, "No connection to the game server", "Friends, parties and profiles live on the game server. Check your internet connection and try again.", _refresh)
	elif not offline and _notice:
		_notice.queue_free()
		_notice = null

func _fill_friends(res: Dictionary) -> void:
	_last = res
	for c in _friends.get_children() + _requests.get_children():
		c.queue_free()
	var online = _online()
	var party_ids = {}
	for m in online.party().get("members", []):
		party_ids[int(m.id)] = true
	var still_there = false
	var sel_id = int(_selected.get("p", {}).get("id", 0))
	# Requests
	for f in res.get("incoming", []):
		var row = _player_row(_requests, f, tr("wants to be your friend"), UITheme.GOLD)
		_selectable(row, f, "incoming")
		_btn(row, "ACCEPT", "primary", func(): _act("/friends/accept", {"id": int(f.id)}))
		_btn(row, "DECLINE", "", func(): _act("/friends/decline", {"id": int(f.id)}))
		if int(f.id) == sel_id:
			still_there = true
			_select(f, "incoming")
	for f in res.get("outgoing", []):
		var row = _player_row(_requests, f, tr("request sent"), UITheme.TEXT_MUTED)
		_selectable(row, f, "requested")
		_btn(row, "PROFILE", "", func(): open_profile.emit(int(f.id)))
		if int(f.id) == sel_id:
			still_there = true
			_select(f, "requested")
	if _requests.get_child_count() == 0:
		_empty_state(_requests, "mail", "No requests", "Friend requests to you and from you show up here")
	# Friends: online ones first
	var friends: Array = res.get("friends", []).duplicate()
	friends.sort_custom(func(a, b): return (String(a.state) != "offline") and (String(b.state) == "offline"))
	for f in friends:
		var state = String(f.state)
		var row = _player_row(_friends, f, tr(STATE_NAMES.get(state, state)), STATE_COLORS.get(state, Color.WHITE))
		_selectable(row, f, "friend")
		if party_ids.has(int(f.id)):
			var tag = UITheme.create_label("In your party", row, UITheme.FONT_TINY)
			tag.add_theme_font_override("font", UITheme.font_black())
			tag.add_theme_color_override("font_color", UITheme.ACCENT_INFO)
			tag.uppercase = true
		else:
			_btn(row, "INVITE", "primary", func(): _invite(int(f.id), String(f.nickname)))
			_draggable(row, f)
		_btn(row, "PROFILE", "", func(): open_profile.emit(int(f.id)))
		_btn(row, "", "danger", func(): _act("/friends/remove", {"id": int(f.id)}), "close", "Remove from friends")
		if int(f.id) == sel_id:
			still_there = true
			_select(f, "friend")
	if friends.is_empty():
		var empty = _empty_state(_friends, "friends", "No friends yet", "Find a player by nickname and send a request")
		var find = UITheme.create_primary_button("FIND PLAYERS", empty, Vector2(220, 48))
		find.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		find.pressed.connect(_show_tab.bind(2))
	# Keep the chosen player; nobody chosen (or gone): the first friend
	if not still_there and _selected.get("relation", "") != "none":
		if not friends.is_empty():
			_select(friends[0], "friend")
		elif not res.get("incoming", []).is_empty():
			_select(res.incoming[0], "incoming")
		else:
			_select({})
	if _first_fill:
		_first_fill = false
		if friends.is_empty() and not res.get("incoming", []).is_empty():
			_show_tab(1)
	_update_tabs()
	_mark_rows()

func _do_search() -> void:
	var online = _online()
	var q = _search.text.strip_edges()
	if online == null or q.length() < 2:
		_say(tr("Type at least 2 letters of the nickname"), UITheme.TEXT_SECONDARY)
		return
	var res = await online.request(HTTPClient.METHOD_POST, "/users/search", {"q": q})
	if not is_inside_tree():
		return
	_fill_results(res)

## Search results: each with what you can do (ADD / ACCEPT / sent / friend) and PROFILE
func _fill_results(res: Dictionary) -> void:
	for c in _results.get_children():
		c.queue_free()
	var players: Array = res.get("players", [])
	if players.is_empty():
		_empty_state(_results, "⌕", "Nobody found", "Check the nickname and try again")
	for pl in players:
		var state = String(pl.state)
		var relation = String(pl.relation)
		var row = _player_row(_results, pl, tr(STATE_NAMES.get(state, state)), STATE_COLORS.get(state, Color.WHITE))
		_selectable(row, pl, "none" if relation in ["none", "self"] else relation)
		match relation:
			"none":
				_btn(row, "ADD", "primary", func():
					await _act("/friends/add", {"id": int(pl.id)})
					_do_search())
			"incoming":
				_btn(row, "ACCEPT", "primary", func():
					await _act("/friends/accept", {"id": int(pl.id)})
					_do_search())
			"requested":
				_tag(row, "request sent", UITheme.TEXT_MUTED)
			"friend":
				_tag(row, "friend", UITheme.ACCENT_SUCCESS)
		_btn(row, "PROFILE", "", func(): open_profile.emit(int(pl.id)))
	_mark_rows()

func _act(path: String, body: Dictionary) -> void:
	var res = await _online().request(HTTPClient.METHOD_POST, path, body)
	if is_inside_tree() and res.get("ok", false) and res.has("friends"):
		_fill_friends(res)

func _invite(id: int, nickname: String) -> void:
	var online = _online()
	if online == null:
		return
	_say(tr("Inviting %s...") % nickname, UITheme.TEXT_SECONDARY)
	var r = await online.party_action("/party/invite", {"id": id})
	if not is_inside_tree():
		return
	var ok = r.get("ok", false)
	_say(tr("Invitation sent to %s") % nickname if ok else tr(String(r.get("error", ""))), UITheme.ACCENT_SUCCESS if ok else UITheme.ACCENT_DANGER)

func _say(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)

# ---------------------------------------------------------------- rows

## A row: the hero's portrait with a status dot, nickname over what they do / the hero, then the
## caller's buttons (returns the box they go in; the navy row panel is its parent)
func _player_row(parent: Control, p: Dictionary, sub: String, dot_color: Color) -> HBoxContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_meta("player_id", int(p.get("id", 0)))
	parent.add_child(panel)
	_style_row(panel, false, false)
	panel.mouse_entered.connect(func(): _style_row(panel, true, panel.get_meta("selected", false)))
	panel.mouse_exited.connect(func(): _style_row(panel, false, panel.get_meta("selected", false)))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	row.add_child(_portrait(p, dot_color, 48))
	var names = VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(names)
	var nick = UITheme.create_label(String(p.nickname), names, UITheme.FONT_NORMAL)
	nick.add_theme_font_override("font", UITheme.font_black())
	nick.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nick.clip_text = true
	nick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line_box = HBoxContainer.new()
	line_box.add_theme_constant_override("separation", 6)
	line_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(line_box)
	var what = UITheme.create_label(sub, line_box, UITheme.FONT_TINY)
	what.add_theme_font_override("font", UITheme.font_bold())
	what.add_theme_color_override("font_color", dot_color.lightened(0.15))
	what.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hero = String(p.get("hero", ""))
	if hero != "":
		var level = int(p.get("level", 0))
		var hero_text = tr("%s  ·  Lv %d") % [tr(hero), level] if level > 0 else tr(hero)
		var hl = UITheme.create_label("·  " + hero_text, line_box, UITheme.FONT_TINY)
		hl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row

func _style_row(panel: PanelContainer, hover: bool, selected: bool) -> void:
	var fill = UITheme.NAVY_HOVER if hover or selected else UITheme.NAVY
	var rim = Color(UITheme.GOLD, 0.9) if selected else (Color(UITheme.GOLD, 0.5) if hover else Color(1, 1, 1, 0.1))
	var box = UITheme.navy_box(fill, rim, 12, 12, 8)
	if selected:
		box.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", box)

## A click on the row (not on its buttons) shows that player on the right
func _selectable(row: HBoxContainer, p: Dictionary, relation: String) -> void:
	var panel = row.get_parent() as PanelContainer
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(event):
		if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			return
		if event.double_click:
			open_profile.emit(int(p.id))
			return
		Sfx.ui("ui_click")
		_select(p, relation)
		_mark_rows())

## A friend you can invite: their row can be dragged onto the golden pad
func _draggable(row: HBoxContainer, f: Dictionary) -> void:
	var panel = row.get_parent() as PanelContainer
	panel.set_drag_forwarding(func(_at):
		panel.set_drag_preview(_drag_chip(f))
		return {"card_drag": true, "payload": {"invite": int(f.id), "nickname": String(f.nickname)}}, Callable(), Callable())

## What flies under the mouse while a friend is dragged: their portrait and nickname
func _drag_chip(f: Dictionary) -> Control:
	var holder = Control.new()
	var chip = PanelContainer.new()
	var box = UITheme.navy_box(UITheme.NAVY_HOVER, UITheme.GOLD, 14, 12, 8)
	box.set_border_width_all(2)
	box.shadow_color = Color(UITheme.GOLD, 0.35)
	box.shadow_size = 16
	chip.add_theme_stylebox_override("panel", box)
	chip.position = Vector2(-30, -34)
	chip.rotation = -0.05
	holder.add_child(chip)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	chip.add_child(row)
	row.add_child(_portrait(f, STATE_COLORS.get(String(f.state), Color.WHITE), 44))
	var nick = UITheme.create_label(String(f.nickname), row, UITheme.FONT_NORMAL)
	nick.add_theme_font_override("font", UITheme.font_black())
	nick.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return holder

## The hero's picture in a rounded frame, a status dot on its corner
func _portrait(p: Dictionary, dot_color: Color, side: int) -> Control:
	var holder = Control.new()
	holder.custom_minimum_size = Vector2(side, side)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame = PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.13, 0.17, 0.28, 0.95), Color(dot_color, 0.55), 12, 0, 0))
	holder.add_child(frame)
	var pic = TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(pic)
	var hero = String(p.get("hero", ""))
	if hero != "" and CharacterRegistry.get_by_name(hero) and is_inside_tree():
		var ref = weakref(pic)  # the list may be rebuilt before the picture comes
		ItemRenderer.get_instance(get_tree()).hero(hero, String(p.get("skin", "classic")), String(p.get("hat", "no_hat")), func(tex):
			var r = ref.get_ref()
			if r:
				r.texture = HeroChips._crop(tex, false))
	var dot = Panel.new()
	var round_box = StyleBoxFlat.new()
	round_box.bg_color = dot_color
	round_box.set_corner_radius_all(99)
	round_box.set_border_width_all(2)
	round_box.border_color = Color(0.04, 0.05, 0.1)
	dot.add_theme_stylebox_override("panel", round_box)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.size = Vector2(14, 14)
	dot.position = Vector2(side - 11, side - 11)  # on the frame's corner
	holder.add_child(dot)
	return holder

## A row button: "primary" gold, "danger" red, "" navy
func _btn(row: Control, text: String, kind: String, action: Callable, icon_name: String = "", tip: String = "") -> void:
	var size = Vector2(40 if icon_name != "" else 100, 38)
	var b: Button
	match kind:
		"primary":
			b = UITheme.create_primary_button(text, row, size)
		"danger":
			b = UITheme.create_danger_button(text, row, size)
		_:
			b = UITheme.create_button(text, row, size)
	b.add_theme_font_override("font", UITheme.font_black())
	b.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if icon_name != "":
		b.icon = UITheme.icon(icon_name)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 18)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.tooltip_text = tip
	b.pressed.connect(action)

func _tag(row: Control, text: String, color: Color) -> void:
	var tag = UITheme.create_label(text, row, UITheme.FONT_TINY)
	tag.add_theme_font_override("font", UITheme.font_black())
	tag.add_theme_color_override("font_color", color)
	tag.uppercase = true
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER

## A list's empty state: a big icon, a heading and a line (returns the column for extra buttons)
## icon: a Kenney icon name (UITheme.ICON_PATHS) or a text glyph (the old emoji look)
func _empty_state(parent: Control, icon: String, title: String, text: String) -> VBoxContainer:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(col)
	UITheme.create_spacer(false, col).custom_minimum_size.y = 60
	var tex = UITheme.icon_texture(icon)
	if tex:
		var pic = TextureRect.new()
		pic.texture = tex
		pic.custom_minimum_size = Vector2(52, 52)
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.modulate = Color(UITheme.GOLD, 0.8)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(pic)
	else:
		var big = UITheme.create_heading(icon, col)
		big.add_theme_font_size_override("font_size", 46)
		big.add_theme_color_override("font_color", Color(UITheme.GOLD, 0.8))
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var head = UITheme.create_heading(title, col)
	head.uppercase = true
	head.add_theme_font_override("font", UITheme.font_black())
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var line = UITheme.create_label(text, col, UITheme.FONT_SMALL)
	line.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return col

# ---------------------------------------------------------------- the chosen player

## Show a player on the right: their hero in 3D and what you can do with them ({} = nobody)
func _select(p: Dictionary, relation: String = "friend") -> void:
	_selected = {"p": p, "relation": relation} if not p.is_empty() else {}
	for c in _sel_actions.get_children():
		c.queue_free()
	if p.is_empty():
		_sel_state.text = tr("FRIENDS")
		_sel_state.add_theme_color_override("font_color", UITheme.GOLD)
		_sel_name.text = ""
		_sel_line.text = ""
		_showcase.visible = false
		_sel_hint.visible = false
		_sel_empty.visible = true
		_selected_wear = ""
		return
	var state = String(p.get("state", "offline"))
	_sel_state.text = tr(STATE_NAMES.get(state, state))
	_sel_state.add_theme_color_override("font_color", STATE_COLORS.get(state, UITheme.GOLD))
	_sel_name.text = String(p.nickname)
	var hero = String(p.get("hero", ""))
	_sel_line.text = tr("Plays %s  ·  Lv %d") % [tr(hero), int(p.get("level", 1))] if hero != "" else ""
	var data: CharacterData = CharacterRegistry.get_by_name(hero)
	var wear = "%s|%s|%s" % [hero, p.get("skin", "classic"), p.get("hat", "no_hat")]
	_sel_empty.visible = data == null
	_showcase.visible = data != null
	_sel_hint.visible = data != null
	if data and wear != _selected_wear:  # the 5 s refresh doesn't reload the model
		_selected_wear = wear
		_showcase.show_character_with_wear(data, String(p.get("skin", "classic")), String(p.get("hat", "no_hat")))
	var id = int(p.id)
	var online = _online()
	var buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	match relation:
		"friend":
			var together = online != null and online.party().get("members", []).any(func(m): return int(m.id) == id)
			if together:
				_side_note("In your party", UITheme.ACCENT_INFO)
			else:
				var inv = UITheme.create_play_button("INVITE TO PARTY", tr("Play together"), _sel_actions)
				inv.pressed.connect(func(): _invite(id, String(p.nickname)))
			_sel_actions.add_child(buttons)
			_side_button(buttons, "PROFILE", "", func(): open_profile.emit(id))
			_side_button(buttons, "REMOVE FRIEND", "danger", func(): _act("/friends/remove", {"id": id}))
		"incoming":
			var acc = UITheme.create_play_button("ACCEPT", tr("wants to be your friend"), _sel_actions)
			acc.pressed.connect(func(): _act("/friends/accept", {"id": id}))
			_sel_actions.add_child(buttons)
			_side_button(buttons, "DECLINE", "danger", func(): _act("/friends/decline", {"id": id}))
			_side_button(buttons, "PROFILE", "", func(): open_profile.emit(id))
		"requested":
			_side_note("request sent", UITheme.TEXT_MUTED)
			_sel_actions.add_child(buttons)
			_side_button(buttons, "PROFILE", "", func(): open_profile.emit(id))
		_:
			var add = UITheme.create_play_button("ADD FRIEND", tr("Play together"), _sel_actions)
			add.pressed.connect(func():
				add.disabled = true
				await _act("/friends/add", {"id": id})
				if is_inside_tree() and _tab == 2:
					_do_search())
			_sel_actions.add_child(buttons)
			_side_button(buttons, "PROFILE", "", func(): open_profile.emit(id))

func _side_button(parent: Control, text: String, kind: String, action: Callable) -> void:
	var b = UITheme.create_danger_button(text, parent, Vector2(0, 46)) if kind == "danger" else UITheme.create_button(text, parent, Vector2(0, 46))
	b.add_theme_font_override("font", UITheme.font_black())
	b.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)

func _side_note(text: String, color: Color) -> void:
	var note = PanelContainer.new()
	note.custom_minimum_size.y = 52
	note.add_theme_stylebox_override("panel", UITheme.navy_box(Color(color, 0.12), Color(color, 0.5), 12, 16, 8))
	_sel_actions.add_child(note)
	var l = UITheme.create_label(text, note, UITheme.FONT_NORMAL)
	l.uppercase = true
	l.add_theme_font_override("font", UITheme.font_black())
	l.add_theme_color_override("font_color", color.lightened(0.2))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

## The chosen player's rows wear a gold rim
func _mark_rows() -> void:
	var id = int(_selected.get("p", {}).get("id", -1))
	for list in [_friends, _requests, _results]:
		for panel in list.get_children():
			if panel is PanelContainer and panel.has_meta("player_id") and not panel.is_queued_for_deletion():
				var on = int(panel.get_meta("player_id")) == id
				panel.set_meta("selected", on)
				_style_row(panel, false, on)

# ---------------------------------------------------------------- shared with ProfileView

## A full-screen "nothing to show" notice under the top bar: a no-signal icon, a title, a line
## and TRY AGAIN (`retry`; empty: no button). Returns the layer (free it to hide the notice).
static func make_notice(host: Control, title: String, text: String, retry: Callable = Callable()) -> Control:
	var layer = CenterContainer.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.offset_top = ScreenHeader.CONTENT_TOP
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(layer)
	var panel = UITheme.navy_panel(layer, 34)
	var col = VBoxContainer.new()
	col.custom_minimum_size.x = 520
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var icon = _NoSignalIcon.new()
	icon.custom_minimum_size = Vector2(0, 92)
	col.add_child(icon)
	var kicker = UITheme.create_label("Offline", col, 12)
	kicker.uppercase = true
	kicker.add_theme_font_override("font", UITheme.font_black())
	kicker.add_theme_color_override("font_color", UITheme.GOLD)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var head = UITheme.create_heading(title, col)
	head.uppercase = true
	head.add_theme_font_override("font", UITheme.font_black())
	head.add_theme_font_size_override("font_size", 24)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var line = UITheme.create_label(text, col, UITheme.FONT_SMALL)
	line.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if retry.is_valid():
		UITheme.create_spacer(false, col).custom_minimum_size.y = 6
		var again = UITheme.create_primary_button("TRY AGAIN", col, Vector2(240, 52))
		again.add_theme_font_override("font", UITheme.font_black())
		again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		again.pressed.connect(retry)
	return layer

## A Wi-Fi fan crossed out, drawn (no icon font needed): the offline notice's picture
class _NoSignalIcon extends Control:
	var _time: float = 0.0

	func _process(delta: float):
		_time += delta
		queue_redraw()

	func _draw():
		var c = Vector2(size.x * 0.5, size.y * 0.82)
		var pulse = 0.5 + 0.5 * sin(_time * 2.4)
		draw_circle(c + Vector2(0, -2), 34.0, Color(UITheme.GOLD, 0.06 + 0.05 * pulse))
		for i in 3:
			var r = 22.0 + i * 20.0
			draw_arc(c, r, PI * 1.22, PI * 1.78, 24, Color(UITheme.TEXT_SECONDARY, 0.55 - i * 0.12), 7.0, true)
		draw_circle(c, 7.0, UITheme.TEXT_SECONDARY)
		var a = c + Vector2(-46, -62)
		var b = c + Vector2(46, 4)
		draw_line(a, b, Color(0.04, 0.05, 0.1), 12.0, true)
		draw_line(a, b, UITheme.ACCENT_DANGER, 6.0, true)

func _close() -> void:
	MenuShell.goto(MenuShell.SceneId.MAIN)

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()
