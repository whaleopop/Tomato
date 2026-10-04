## The party on the main menu (top right, under the players pill): you and your friend with your
## heroes' portraits, the leader's star, LEAVE; an invitation pops up above it with ACCEPT / DECLINE.
## Fed by Online.party_changed (MainMenu polls Online.poll_party every few seconds).
extends VBoxContainer
class_name PartyBar

signal open_profile(account_id: int)

var _panel: PanelContainer
var _members: VBoxContainer
var _invite_box: VBoxContainer
var _shown_invites: Dictionary = {}  # from -> true: popped up already

func _ready():
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_invite_box = VBoxContainer.new()
	_invite_box.add_theme_constant_override("separation", 8)
	add_child(_invite_box)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.78), Color(UITheme.ACCENT_INFO, 0.5), 18, 16, 10))
	_panel.visible = false
	add_child(_panel)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	var head = HBoxContainer.new()
	col.add_child(head)
	var title = UITheme.create_label("PARTY", head, UITheme.FONT_SMALL)
	title.add_theme_font_override("font", UITheme.font_black())
	title.add_theme_color_override("font_color", UITheme.ACCENT_INFO.lightened(0.3))
	title.uppercase = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var leave = UITheme.create_button("LEAVE", head, Vector2(90, 30))
	leave.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	leave.pressed.connect(func():
		var online = get_node_or_null("/root/Online")
		if online:
			online.party_action("/party/leave"))
	_members = VBoxContainer.new()
	_members.add_theme_constant_override("separation", 6)
	col.add_child(_members)
	var online = get_node_or_null("/root/Online")
	if online:
		online.party_changed.connect(_show)
		if not online.party_data.is_empty():
			_show(online.party_data)

func _show(data: Dictionary) -> void:
	var online = get_node_or_null("/root/Online")
	var party = data.get("party") if data.get("party") is Dictionary else {}
	_panel.visible = not party.is_empty()
	for c in _members.get_children():
		c.queue_free()
	for m in party.get("members", []):
		_member_row(m, int(m.id) == int(party.leader), online != null and int(m.id) == online.account_id)
	# Invitations: each pops up once
	var live = {}
	for inv in data.get("invites", []):
		live[int(inv.from)] = true
		if not _shown_invites.has(int(inv.from)):
			_shown_invites[int(inv.from)] = true
			_invite_popup(int(inv.from), String(inv.nickname))
			Sfx.ui("match_found")
	for frm in _shown_invites.keys():
		if not live.has(frm):
			_shown_invites.erase(frm)
			for c in _invite_box.get_children():
				if int(c.get_meta("from", 0)) == frm:
					c.queue_free()

func _member_row(m: Dictionary, leader: bool, me: bool) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_members.add_child(row)
	var pic = TextureRect.new()
	pic.custom_minimum_size = Vector2(44, 44)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(pic)
	ItemRenderer.get_instance(get_tree()).hero(String(m.hero), String(m.get("skin", "classic")), String(m.get("hat", "no_hat")), func(tex):
		if is_instance_valid(pic):
			pic.texture = HeroChips._crop(tex, false))
	var names = VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	var nick = UITheme.create_label(("★ " if leader else "") + String(m.nickname) + ("  ·  " + tr("you") if me else ""), names, UITheme.FONT_SMALL)
	nick.add_theme_font_override("font", UITheme.font_black())
	var data: CharacterData = CharacterRegistry.get_by_name(String(m.hero))
	var hero = UITheme.create_label(tr("%s  ·  Lv %d") % [tr(String(m.hero)), int(m.get("level", 1))], names, UITheme.FONT_TINY)
	hero.add_theme_color_override("font_color", data.color.lightened(0.3) if data else UITheme.TEXT_SECONDARY)
	var look = UITheme.create_button("PROFILE", row, Vector2(84, 30))
	look.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	look.pressed.connect(func(): open_profile.emit(int(m.id)))

func _invite_popup(from: int, nickname: String) -> void:
	var box = PanelContainer.new()
	box.set_meta("from", from)
	box.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.05, 0.09, 0.07, 0.92), Color(UITheme.ACCENT_PRIMARY, 0.8), 18, 14, 10))
	_invite_box.add_child(box)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	var text = UITheme.create_label(tr("%s invites you to a party") % nickname, col, UITheme.FONT_SMALL)
	text.add_theme_font_override("font", UITheme.font_black())
	text.add_theme_color_override("font_color", Color.WHITE)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var accept = UITheme.create_primary_button("ACCEPT", row, Vector2(110, 34))
	accept.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	var decline = UITheme.create_button("DECLINE", row, Vector2(110, 34))
	decline.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	var online = get_node_or_null("/root/Online")
	accept.pressed.connect(func():
		box.queue_free()
		if online:
			var res = await online.party_action("/party/accept", {"from": from})
			if not res.get("ok", false):
				_say(String(res.get("error", ""))))
	decline.pressed.connect(func():
		box.queue_free()
		if online:
			online.party_action("/party/decline", {"from": from}))

func _say(text: String) -> void:
	var menu = get_parent()
	while menu and not menu.has_method("show_toast"):
		menu = menu.get_parent()
	if menu and text != "":
		menu.show_toast(tr(text), UITheme.ACCENT_DANGER)
