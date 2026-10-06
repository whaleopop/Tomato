## A player's profile (yours from PROFILE, a friend's from FRIENDS / the party bar), a screen in the
## main menu's look: the shared top bar (their nickname, kicker PROFILE; BACK closes), on the left
## the hero they play in what it wears in an interactive 3D showcase (drag to turn, wheel to zoom)
## with their state and ADD FRIEND / INVITE TO PARTY; on the right level / matches / coins earned /
## collection as navy stat tiles and everything they own - heroes, skins, hats, gun finishes - as
## shop cards under tabs. Click a card (or drag it onto the golden pad) to try it on the showcase.
## Data: POST /users/profile. Offline: a "No connection to the game server" notice.
extends Control
class_name ProfileView

signal closed

const SIDE_WIDTH: int = 440
const CARD_SIZE = Vector2(150, 208)
const CARD_GAP: int = 16
const SECTIONS = [
	{"kind": "hero", "title": "Heroes", "key": "heroes"},
	{"kind": "skin", "title": "Skins", "key": "skins"},
	{"kind": "hat", "title": "Hats", "key": "hats"},
	{"kind": "finish", "title": "Gun finishes", "key": "finishes"},
]

var account_id: int = 0
var _header: ScreenHeader
var _body: HBoxContainer
var _notice: Control = null
var _loading: Label
var _showcase: CharacterShowcase
var _state: Label
var _hero_name: Label
var _sub: Label
var _actions: VBoxContainer
var _pad: DropPad
var _tiles: HBoxContainer
var _tabs: Array[Button] = []
var _grid: GridContainer
var _scroll: ScrollContainer
var _section: int = 0
var _player: Dictionary = {}
# What the showcase shows (starts as what they wear)
var _shown_hero: String = ""
var _shown_skin: String = "classic"
var _shown_hat: String = "no_hat"
var _cards: Dictionary = {}        # id -> ParallaxCard of the open tab
var _nick_label: Label = null      # whose profile, in the fixed sub-nav row

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
	var page = VBoxContainer.new()
	page.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(page)
	# The fixed sub-nav row: the kicker and whose profile it is (the bar carries no title)
	var title_row = HBoxContainer.new()
	title_row.custom_minimum_size.y = ScreenHeader.SUBNAV_H
	title_row.add_theme_constant_override("separation", 14)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(title_row)
	var kicker = UITheme.create_label("PROFILE", title_row, UITheme.FONT_TINY)
	kicker.uppercase = true
	kicker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kicker.add_theme_font_override("font", UITheme.font_black())
	kicker.add_theme_color_override("font_color", UITheme.GOLD)
	_nick_label = UITheme.create_label("...", title_row, UITheme.FONT_SUBTITLE)
	_nick_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # a nickname, not a text
	_nick_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nick_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_nick_label.clip_text = true
	_nick_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_nick_label.add_theme_font_override("font", UITheme.font_black())
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 24)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.visible = false
	page.add_child(_body)

	# Left: the hero they play
	var left = UITheme.navy_panel(_body, 20)
	left.custom_minimum_size.x = SIDE_WIDTH
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	left.add_child(col)
	_state = UITheme.create_label("", col, 12)
	_state.uppercase = true
	_state.add_theme_font_override("font", UITheme.font_black())
	_state.add_theme_color_override("font_color", UITheme.GOLD)
	var name_row = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	col.add_child(name_row)
	_hero_name = UITheme.create_heading("", name_row)
	_hero_name.add_theme_font_override("font", UITheme.font_black())
	_hero_name.add_theme_font_size_override("font_size", 30)
	_hero_name.uppercase = true
	_hero_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_name.clip_text = true
	_hero_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var reset = UITheme.create_icon_chip("↺", name_row, Vector2(44, 40))
	reset.tooltip_text = "Back to what they wear"
	reset.pressed.connect(_reset_wear)
	_sub = UITheme.create_label("", col, UITheme.FONT_SMALL)
	_sub.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	var stage = PanelContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.02, 0.03, 0.06, 0.6), Color(1, 1, 1, 0.06), 14, 0, 0))
	col.add_child(stage)
	_showcase = CharacterShowcase.new()
	_showcase.custom_minimum_size = Vector2(0, 220)
	_showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_showcase.interactive = true
	stage.add_child(_showcase)
	var hint = UITheme.create_label("Drag to turn  ·  wheel to zoom  ·  double click to reset", col, 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_pad = DropPad.new()
	_pad.caption = "DRAG A CARD HERE"
	_pad.detail = tr("to try it on")
	_pad.icon = "✦"
	_pad.custom_minimum_size.y = 84
	_pad.accepts = func(payload): return payload is Dictionary and payload.has("try_on")
	_pad.dropped.connect(func(payload): _try_on(String(payload.kind), String(payload.try_on)))
	col.add_child(_pad)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	col.add_child(_actions)

	# Right: the numbers and the collection
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 16)
	_body.add_child(right)
	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", 14)
	right.add_child(_tiles)
	var tab_row = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	right.add_child(tab_row)
	for i in SECTIONS.size():
		var tab = UITheme.create_tab("", tab_row)
		tab.pressed.connect(_show_section.bind(i))
		_tabs.append(tab)
	var shelf = UITheme.navy_panel(right, 18)
	shelf.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shelf.add_child(_scroll)
	var pad_box = MarginContainer.new()  # room for the cards to tilt / grow on hover
	pad_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad_box.add_theme_constant_override("margin_" + side, 8)
	_scroll.add_child(pad_box)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", CARD_GAP)
	_grid.add_theme_constant_override("v_separation", CARD_GAP)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pad_box.add_child(_grid)
	_scroll.resized.connect(_fit_columns)

	_loading = UITheme.create_label("Loading...", self, UITheme.FONT_NORMAL)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH

	MenuShell.show_bar()
	_header = MenuShell.header
	MenuShell.current = MenuShell.SceneId.PROFILE
	MenuShell._mark_active()
	if not _header.back_pressed.is_connected(_close):
		_header.back_pressed.connect(_close)
	_load()

func _load() -> void:
	if _notice:
		_notice.queue_free()
		_notice = null
	var online = get_node_or_null("/root/Online")
	if online == null or not online.logged_in:
		_show_error("No connection to the game server")
		return
	_loading.visible = true
	var res = await online.request(HTTPClient.METHOD_POST, "/users/profile", {"id": account_id if account_id > 0 else online.account_id})
	if not is_inside_tree():
		return
	if not res.get("ok", false):
		_show_error(String(res.get("error", "No connection to the game server")))
		return
	_fill(res.player)

## No profile to show: the notice (with TRY AGAIN) under the bar
func _show_error(error: String) -> void:
	_loading.visible = false
	_body.visible = false
	if _notice:
		_notice.queue_free()
	_notice = FriendsPanel.make_notice(self, error, "Profiles live on the game server. Check your internet connection and try again.", _load)

func _fill(p: Dictionary) -> void:
	_player = p
	_loading.visible = false
	if _notice:
		_notice.queue_free()
		_notice = null
	_body.visible = true
	var hero_name = String(p.hero)
	_nick_label.text = String(p.nickname)
	var state = String(p.get("state", "offline"))
	_state.text = tr(FriendsPanel.STATE_NAMES.get(state, state))
	_state.add_theme_color_override("font_color", FriendsPanel.STATE_COLORS.get(state, UITheme.GOLD))
	_reset_wear()
	_fill_actions(p)
	# Stat tiles
	for c in _tiles.get_children():
		c.queue_free()
	var owned = 0
	for s in SECTIONS:
		owned += p.get(s.key, []).size()
	_tile("Hero level", str(int(p.level)), Color.WHITE)
	_tile("Matches", UITheme.format_coins(int(p.matches)), Color.WHITE)
	_tile("Coins earned", UITheme.format_coins(int(p.earned)), Color(1.0, 0.85, 0.42), "coin")
	_tile("Collection", str(owned), UITheme.ACCENT_INFO.lightened(0.2))
	for i in SECTIONS.size():
		_tabs[i].text = tr(SECTIONS[i].title).to_upper() + "   %d" % p.get(SECTIONS[i].key, []).size()
	_show_section(_section)

## ADD FRIEND / ACCEPT / INVITE TO PARTY - whatever fits who they are to you
func _fill_actions(p: Dictionary) -> void:
	for c in _actions.get_children():
		c.queue_free()
	var online = get_node_or_null("/root/Online")
	match String(p.relation):
		"none":
			var add = UITheme.create_play_button("ADD FRIEND", "Play together", _actions)
			add.pressed.connect(func():
				add.disabled = true
				await online.request(HTTPClient.METHOD_POST, "/friends/add", {"id": int(p.id)})
				if is_instance_valid(add):
					add.queue_free()
					_note("request sent", UITheme.TEXT_SECONDARY))
		"incoming":
			var acc = UITheme.create_play_button("ACCEPT", "wants to be your friend", _actions)
			acc.pressed.connect(func():
				acc.disabled = true
				await online.request(HTTPClient.METHOD_POST, "/friends/accept", {"id": int(p.id)})
				if is_instance_valid(acc):
					acc.queue_free()
					_note("friend", UITheme.ACCENT_SUCCESS))
		"requested":
			_note("request sent", UITheme.TEXT_SECONDARY)
		"friend":
			var together = online != null and online.party().get("members", []).any(func(m): return int(m.id) == int(p.id))
			if together:
				_note("In your party", UITheme.ACCENT_INFO)
			elif String(p.state) != "offline":
				var inv = UITheme.create_play_button("INVITE TO PARTY", "Play together", _actions)
				inv.pressed.connect(func():
					inv.disabled = true
					var r = await online.party_action("/party/invite", {"id": int(p.id)})
					if is_instance_valid(inv):
						inv.queue_free()
						var ok = r.get("ok", false)
						_note("Invitation sent" if ok else String(r.get("error", "")), UITheme.ACCENT_SUCCESS if ok else UITheme.ACCENT_DANGER))
			else:
				_note("Offline", UITheme.TEXT_MUTED)

## A status line in place of an action
func _note(text: String, color: Color) -> void:
	var note = PanelContainer.new()
	note.custom_minimum_size.y = 56
	note.add_theme_stylebox_override("panel", UITheme.navy_box(Color(color, 0.12), Color(color, 0.5), 12, 16, 8))
	_actions.add_child(note)
	var l = UITheme.create_label(text, note, UITheme.FONT_NORMAL)
	l.uppercase = true
	l.add_theme_font_override("font", UITheme.font_black())
	l.add_theme_color_override("font_color", color.lightened(0.2))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

## A navy stat tile: a small muted caption over a big number
func _tile(caption: String, value: String, color: Color, icon_name: String = "") -> void:
	var tile = PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.add_theme_stylebox_override("panel", UITheme.navy_box(UITheme.NAVY, Color(1, 1, 1, 0.1), 14, 18, 12))
	_tiles.add_child(tile)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	tile.add_child(col)
	var cap = UITheme.create_label(caption, col, 11)
	cap.uppercase = true
	cap.add_theme_font_override("font", UITheme.font_black())
	cap.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	var line: Control = col
	if icon_name != "":
		line = HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		col.add_child(line)
		var ic = UITheme.create_icon(icon_name, line, 28, color)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var big = UITheme.create_heading(value, line)
	big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	big.add_theme_font_override("font", UITheme.font_black())
	big.add_theme_font_size_override("font_size", 30)
	big.add_theme_color_override("font_color", color)
	big.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	big.clip_text = true
	big.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

# ---------------------------------------------------------------- the collection

## One kind of thing they own as cards (nothing yet: says so)
func _show_section(index: int) -> void:
	_section = index
	for i in _tabs.size():
		UITheme.set_tab_active(_tabs[i], i == index)
	for c in _grid.get_children():
		c.queue_free()
	_cards.clear()
	var empty = _scroll.get_parent().get_node_or_null("Empty")
	if empty:
		# Out of the tree right away: a second "Empty" added in the same frame was renamed and stayed
		# over the next tab's cards
		empty.get_parent().remove_child(empty)
		empty.queue_free()
	var s = SECTIONS[index]
	var ids: Array = _player.get(s.key, [])
	if ids.is_empty():
		var label = UITheme.create_label("Nothing yet", null, UITheme.FONT_NORMAL)
		label.name = "Empty"
		label.uppercase = true
		label.add_theme_font_override("font", UITheme.font_black())
		label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scroll.get_parent().add_child(label)
		return
	var renderer = ItemRenderer.get_instance(get_tree())
	var levels: Dictionary = _player.get("hero_levels", {})
	var hero_name = String(_player.get("hero", ""))
	for raw in ids:
		var id = String(raw)
		var card = ParallaxCard.new()
		card.card_size = CARD_SIZE
		var ref = weakref(card)  # the picture may come after the tab changed (the card is gone)
		var put = func(tex):
			var c = ref.get_ref()
			if c:
				c.set_art(tex)
		match s.kind:
			"hero":
				var data: CharacterData = CharacterRegistry.get_by_name(id)
				var skin = String(_player.get("skin", "classic")) if id == hero_name else "classic"
				var hat = String(_player.get("hat", "no_hat")) if id == hero_name else "no_hat"
				card.title = id
				card.accent = data.color if data else UITheme.ACCENT_INFO
				card.level = int(levels.get(id, 0))
				card.mastery = Mastery.tier_for_level(card.level)
				card.subtitle = Mastery.tier_name(card.mastery) if card.mastery >= 0 else "Hero"
				card.badge = tr("Equipped") if id == hero_name else ""
				card.live = ["hero", [id, skin, hat]]
				renderer.hero(id, skin, hat, put)
			"skin", "hat":
				_style_cosmetic(card, id)
				var skin = id if s.kind == "skin" else String(_player.get("skin", "classic"))
				var hat = id if s.kind == "hat" else String(_player.get("hat", "no_hat"))
				card.badge = tr("Equipped") if id == String(_player.get(s.kind, "")) else ""
				card.live = ["hero", [hero_name, skin, hat]]
				renderer.hero(hero_name, skin, hat, put)
			"finish":
				_style_cosmetic(card, id)
				card.live = ["gun", [0, id]]
				renderer.weapon(0, id, put)
		if s.kind != "finish":  # guns don't go on the hero: only the rest can be tried on
			card.drag_payload = {"try_on": id, "kind": s.kind}
			card.pressed.connect(_try_on.bind(s.kind, id))
		_cards[id] = card
		_grid.add_child(card)
	_mark_cards()
	_fit_columns()

func _style_cosmetic(card: ParallaxCard, id: String) -> void:
	var tier = Cosmetics.tier_of(id)
	card.title = Cosmetics.name_of(id)
	card.accent = Cosmetics.TIER_COLORS[tier]
	card.subtitle = Cosmetics.TIER_NAMES[tier]
	var rank = Mastery.tier_of_id(id)
	if rank >= 0:
		card.accent = Mastery.tier_color(rank)
		card.subtitle = Mastery.tier_name(rank)

## As many card columns as the shelf fits
func _fit_columns() -> void:
	var width = _scroll.size.x - 16 - 12  # the margins, a scroll bar
	_grid.columns = maxi(1, int((width + CARD_GAP) / (CARD_SIZE.x + CARD_GAP)))

## The showcase wears this hero / skin / hat (a card clicked or dropped on the pad)
func _try_on(kind: String, id: String) -> void:
	match kind:
		"hero":
			_shown_hero = id
			var theirs = id == String(_player.get("hero", ""))
			_shown_skin = String(_player.get("skin", "classic")) if theirs else "classic"
			_shown_hat = String(_player.get("hat", "no_hat")) if theirs else "no_hat"
		"skin":
			_shown_skin = id
		"hat":
			_shown_hat = id
	_show_hero()

## Back to the hero they play in what it wears
func _reset_wear() -> void:
	_shown_hero = String(_player.get("hero", ""))
	_shown_skin = String(_player.get("skin", "classic"))
	_shown_hat = String(_player.get("hat", "no_hat"))
	_show_hero()

func _show_hero() -> void:
	var data: CharacterData = CharacterRegistry.get_by_name(_shown_hero)
	_hero_name.text = tr(_shown_hero)
	_hero_name.add_theme_color_override("font_color", data.color.lightened(0.45) if data else Color.WHITE)
	var levels: Dictionary = _player.get("hero_levels", {})
	var level = int(levels.get(_shown_hero, _player.get("level", 1) if _shown_hero == String(_player.get("hero", "")) else 1))
	var wear = []
	if _shown_skin != "classic":
		wear.append(tr(Cosmetics.name_of(_shown_skin)))
	if _shown_hat != "no_hat":
		wear.append(tr(Cosmetics.name_of(_shown_hat)))
	_sub.text = tr("Lv %d") % level + ("  ·  " + "  ·  ".join(wear) if not wear.is_empty() else "")
	if data:
		_showcase.show_character_with_wear(data, _shown_skin, _shown_hat)
	_mark_cards()

## The cards of what the showcase wears are lit
func _mark_cards() -> void:
	var kind = SECTIONS[_section].kind
	for id in _cards:
		var card: ParallaxCard = _cards[id]
		var on = (kind == "hero" and id == _shown_hero) or (kind == "skin" and id == _shown_skin) or (kind == "hat" and id == _shown_hat)
		if card.selected != on:
			card.selected = on
			card.refresh()

func _close() -> void:
	MenuShell.goto(MenuShell.SceneId.MAIN)

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()
