## The party on the main menu (top right, under the bar), in the menu's navy look: a PARTY kicker
## with the head count and LEAVE, then a chip per member - the hero's portrait (a gold crown on the
## leader's), nickname, hero and level; click a chip for the profile. A free place shows as a
## dashed slot that opens FRIENDS. An invitation slides in above it: a navy card with a gold rim,
## ACCEPT / DECLINE. Fed by Online.party_changed (MainMenu polls Online.poll_party every few seconds).
extends VBoxContainer
class_name PartyBar

signal open_profile(account_id: int)

const PARTY_MAX: int = 2           # the backend's PARTY_MAX

var _panel: PanelContainer
var _members: VBoxContainer
var _count: Label
var _invite_box: VBoxContainer
var _shown_invites: Dictionary = {}  # from -> true: popped up already

func _ready():
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_invite_box = VBoxContainer.new()
	_invite_box.add_theme_constant_override("separation", 8)
	_invite_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_invite_box)
	_panel = PanelContainer.new()
	var box = UITheme.navy_box(Color(0.045, 0.06, 0.11, 0.92), Color(1, 1, 1, 0.1), 16, 14, 12)
	box.shadow_size = 14
	box.shadow_offset = Vector2(0, 5)
	_panel.add_theme_stylebox_override("panel", box)
	_panel.visible = false
	add_child(_panel)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var title = UITheme.create_label("PARTY", head, 12)
	title.add_theme_font_override("font", UITheme.font_black())
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.uppercase = true
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count = UITheme.create_label("", head, 12)
	_count.add_theme_font_override("font", UITheme.font_black())
	_count.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var leave = UITheme.create_danger_button("LEAVE", head, Vector2(84, 30))
	leave.add_theme_font_override("font", UITheme.font_black())
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
	var members: Array = party.get("members", [])
	for m in members:
		_member_row(m, int(m.id) == int(party.get("leader", 0)), online != null and int(m.id) == online.account_id)
	for i in range(members.size(), PARTY_MAX):
		_free_slot()
	_count.text = "%d / %d" % [members.size(), PARTY_MAX]
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

## A member's chip: portrait (crown on the leader), nickname over hero · level; click = profile
func _member_row(m: Dictionary, leader: bool, me: bool) -> void:
	var data: CharacterData = CharacterRegistry.get_by_name(String(m.hero))
	var hero_color = data.color if data else UITheme.ACCENT_INFO
	var chip = Button.new()
	chip.focus_mode = Control.FOCUS_NONE
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.custom_minimum_size.y = 60
	chip.tooltip_text = "PROFILE"
	chip.add_theme_stylebox_override("normal", UITheme.navy_box(UITheme.NAVY, Color(UITheme.GOLD, 0.45) if leader else Color(1, 1, 1, 0.1), 12, 10, 6))
	chip.add_theme_stylebox_override("hover", UITheme.navy_box(UITheme.NAVY_HOVER, Color(UITheme.GOLD, 0.85), 12, 10, 6))
	chip.add_theme_stylebox_override("pressed", UITheme.navy_box(UITheme.NAVY.darkened(0.2), UITheme.GOLD, 12, 10, 6))
	chip.add_theme_stylebox_override("focus", UITheme.empty_box())
	chip.pressed.connect(func():
		Sfx.ui("ui_click")
		open_profile.emit(int(m.id)))
	chip.mouse_entered.connect(func(): Sfx.ui("ui_hover"))
	_members.add_child(chip)
	var row = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -10
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	# The portrait in a rounded frame, the crown riding its top edge
	var holder = Control.new()
	holder.custom_minimum_size = Vector2(46, 46)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(holder)
	var frame = PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UITheme.glass_box(Color(hero_color.darkened(0.55), 0.95), Color(UITheme.GOLD, 0.9) if leader else Color(hero_color, 0.6), 12, 0, 0))
	holder.add_child(frame)
	var pic = TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(pic)
	var ref = weakref(pic)  # the bar may be rebuilt before the picture comes
	ItemRenderer.get_instance(get_tree()).hero(String(m.hero), String(m.get("skin", "classic")), String(m.get("hat", "no_hat")), func(tex):
		var r = ref.get_ref()
		if r:
			r.texture = HeroChips._crop(tex, false))
	if leader:
		var crown = UITheme.create_icon("crown", null, 24, UITheme.GOLD)
		crown.position = Vector2(-10, -18)
		crown.rotation = -0.3
		crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(crown)
	var names = VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(names)
	var nick_row = HBoxContainer.new()
	nick_row.add_theme_constant_override("separation", 6)
	nick_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(nick_row)
	var nick = UITheme.create_label(String(m.nickname), nick_row, UITheme.FONT_SMALL)
	nick.add_theme_font_override("font", UITheme.font_black())
	nick.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nick.clip_text = true
	nick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if me:
		var you = UITheme.create_label("you", nick_row, 11)
		you.uppercase = true
		you.add_theme_font_override("font", UITheme.font_black())
		you.add_theme_color_override("font_color", UITheme.ACCENT_INFO)
		you.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hero = UITheme.create_label(tr("%s  ·  Lv %d") % [tr(String(m.hero)), int(m.get("level", 1))], names, UITheme.FONT_TINY)
	hero.clip_text = true
	hero.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hero.add_theme_font_override("font", UITheme.font_bold())
	hero.add_theme_color_override("font_color", hero_color.lightened(0.35) if data else UITheme.TEXT_SECONDARY)
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chevron = UITheme.create_icon("chevron_right", row, 20, UITheme.TEXT_SECONDARY)
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE

## A free place in the party: a quiet dashed slot that opens FRIENDS (the main menu's)
func _free_slot() -> void:
	var slot = Button.new()
	slot.focus_mode = Control.FOCUS_NONE
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.custom_minimum_size.y = 46
	slot.text = "+   " + tr("Invite a friend").to_upper()
	slot.add_theme_font_override("font", UITheme.font_black())
	slot.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	slot.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	slot.add_theme_color_override("font_hover_color", UITheme.GOLD)
	slot.add_theme_stylebox_override("normal", UITheme.navy_box(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.12), 12, 10, 6))
	slot.add_theme_stylebox_override("hover", UITheme.navy_box(Color(UITheme.GOLD, 0.06), Color(UITheme.GOLD, 0.6), 12, 10, 6))
	slot.add_theme_stylebox_override("pressed", UITheme.navy_box(Color(UITheme.GOLD, 0.1), UITheme.GOLD, 12, 10, 6))
	slot.add_theme_stylebox_override("focus", UITheme.empty_box())
	slot.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # translated above
	slot.pressed.connect(func():
		var menu = _menu("_open_friends")
		if menu:
			menu._open_friends())
	_members.add_child(slot)

## An invitation card: kicker, who invites you, ACCEPT / DECLINE; slides in from the right
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _invite_box and _invite_box.get_child_count() > 0:
		# Settings, the pause menu etc. (group blocks_game_input) get Esc first
		for n in get_tree().get_nodes_in_group("blocks_game_input"):
			if n is CanvasItem and n.is_visible_in_tree():
				return
		var card = _invite_box.get_child(_invite_box.get_child_count() - 1)
		card.queue_free()
		var online = get_node_or_null("/root/Online")
		if online and card.has_meta("from"):
			online.party_action("/party/decline", {"from": card.get_meta("from")})
		get_viewport().set_input_as_handled()

func _invite_popup(from: int, nickname: String) -> void:
	var box = PanelContainer.new()
	box.set_meta("from", from)
	var style = UITheme.navy_box(Color(0.06, 0.08, 0.14, 0.97), UITheme.GOLD, 16, 16, 14)
	style.set_border_width_all(2)
	style.shadow_color = Color(UITheme.GOLD, 0.3)
	style.shadow_size = 18
	style.shadow_offset = Vector2.ZERO
	box.add_theme_stylebox_override("panel", style)
	_invite_box.add_child(box)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	var kicker_row = UITheme.create_icon_label("crown", tr("Party invitation").to_upper(), col, 12, UITheme.GOLD)
	var kicker: Label = kicker_row.get_meta("label")
	kicker.add_theme_font_override("font", UITheme.font_black())
	kicker.add_theme_color_override("font_color", UITheme.GOLD)
	kicker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # translated above
	var text = UITheme.create_label(tr("%s invites you to a party") % nickname, col, UITheme.FONT_NORMAL)
	text.add_theme_font_override("font", UITheme.font_black())
	text.add_theme_color_override("font_color", Color.WHITE)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # has the nickname in it
	UITheme.create_spacer(false, col).custom_minimum_size.y = 2
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var accept = UITheme.create_primary_button("ACCEPT", row, Vector2(0, 40))
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept.add_theme_font_override("font", UITheme.font_black())
	accept.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	var decline = UITheme.create_button("DECLINE", row, Vector2(0, 40))
	decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decline.add_theme_font_override("font", UITheme.font_black())
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
	# Slide in: the card's content starts to the right and fades in (the box keeps its place)
	col.modulate.a = 0.0
	box.modulate.a = 0.0
	var t = box.create_tween().set_parallel(true)
	t.tween_property(box, "modulate:a", 1.0, 0.25)
	t.tween_property(col, "modulate:a", 1.0, 0.35).set_delay(0.08)
	box.pivot_offset = Vector2(160, 40)
	box.scale = Vector2(0.92, 0.92)
	t.tween_property(box, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The nearest ancestor with that method (the main menu)
func _menu(method: String) -> Node:
	var menu = get_parent()
	while menu and not menu.has_method(method):
		menu = menu.get_parent()
	return menu

func _say(text: String) -> void:
	var menu = _menu("show_toast")
	if menu and text != "":
		menu.show_toast(tr(text), UITheme.ACCENT_DANGER)
