## A player's profile (yours from PROFILE, a friend's from FRIENDS / the party bar): the hero they
## play in what it wears and its mastery level, matches played and coins earned, and everything
## they bought - heroes, skins, hats, gun finishes - as pictures (ItemRenderer, like the shop's
## cards). Friends / strangers get ADD FRIEND / INVITE TO PARTY. Data: POST /users/profile.
extends Control
class_name ProfileView

signal closed

var account_id: int = 0
var _body: VBoxContainer
var _showcase: CharacterShowcase
var _title: Label
var _sub: Label
var _actions: HBoxContainer

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("blocks_game_input")
	var dim = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = UITheme.create_panel(center, 24)
	var root = HBoxContainer.new()
	root.custom_minimum_size = Vector2(1080, 600)
	root.add_theme_constant_override("separation", 22)
	panel.add_child(root)
	# Left: the hero they play
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 320
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)
	_title = UITheme.create_title("", left)
	_title.add_theme_font_override("font", UITheme.font_black())
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_sub = UITheme.create_label("", left, UITheme.FONT_SMALL)
	_sub.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_showcase = CharacterShowcase.new()
	_showcase.custom_minimum_size = Vector2(320, 360)
	_showcase.interactive = true
	left.add_child(_showcase)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	left.add_child(_actions)
	# Right: what they own
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	var head = HBoxContainer.new()
	right.add_child(head)
	var cap = UITheme.create_heading("COLLECTION", head)
	cap.uppercase = true
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back = UITheme.create_button("BACK", head, Vector2(130, 44))
	back.pressed.connect(_close)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)
	_load()

func _load() -> void:
	var online = get_node_or_null("/root/Online")
	if online == null or not online.logged_in:
		_title.text = tr("No connection to the game server")
		return
	var res = await online.request(HTTPClient.METHOD_POST, "/users/profile", {"id": account_id if account_id > 0 else online.account_id})
	if not is_inside_tree():
		return
	if not res.get("ok", false):
		_title.text = tr(String(res.get("error", "No connection to the game server")))
		return
	_fill(res.player)

func _fill(p: Dictionary) -> void:
	var hero_name = String(p.hero)
	var data: CharacterData = CharacterRegistry.get_by_name(hero_name)
	_title.text = String(p.nickname)
	_sub.text = tr("Plays %s  ·  Lv %d") % [tr(hero_name), int(p.level)] + "\n" + tr("Matches: %d  ·  Coins earned: %d") % [int(p.matches), int(p.earned)]
	if data:
		_showcase.show_character_with_wear(data, String(p.skin), String(p.hat))
	var online = get_node_or_null("/root/Online")
	match String(p.relation):
		"none":
			var add = UITheme.create_primary_button("ADD FRIEND", _actions, Vector2(170, 42))
			add.pressed.connect(func():
				add.disabled = true
				await online.request(HTTPClient.METHOD_POST, "/friends/add", {"id": int(p.id)})
				add.text = tr("request sent"))
		"incoming":
			var acc = UITheme.create_primary_button("ACCEPT", _actions, Vector2(170, 42))
			acc.pressed.connect(func():
				acc.disabled = true
				await online.request(HTTPClient.METHOD_POST, "/friends/accept", {"id": int(p.id)}))
		"friend":
			var together = online.party().get("members", []).any(func(m): return int(m.id) == int(p.id))
			if together:
				UITheme.create_label("In your party", _actions, UITheme.FONT_SMALL).add_theme_color_override("font_color", UITheme.ACCENT_INFO)
			elif String(p.state) != "offline":
				var inv = UITheme.create_primary_button("INVITE TO PARTY", _actions, Vector2(200, 42))
				inv.pressed.connect(func():
					inv.disabled = true
					var r = await online.party_action("/party/invite", {"id": int(p.id)})
					inv.text = tr("Invitation sent") if r.get("ok", false) else tr(String(r.get("error", ""))))
	var levels: Dictionary = p.get("hero_levels", {})
	_section("Heroes", p.get("heroes", []), func(id): return [id, "classic", "no_hat"], func(id): return tr(id) + ("  ·  " + tr("Lv %d") % int(levels[id]) if levels.has(id) else ""))
	_section("Skins", p.get("skins", []), func(id): return [hero_name, id, "no_hat"], func(id): return tr(Cosmetics.name_of(id)))
	_section("Hats", p.get("hats", []), func(id): return [hero_name, "classic", id], func(id): return tr(Cosmetics.name_of(id)))
	_section("Gun finishes", p.get("finishes", []), func(id): return ["gun", id], func(id): return tr(Cosmetics.name_of(id)))

## One kind of thing they own: a grid of pictures with names (nothing bought yet: says so)
func _section(title: String, ids: Array, picture: Callable, label: Callable) -> void:
	var cap = UITheme.create_caption("%s  (%d)" % [tr(title), ids.size()], _body)
	cap.add_theme_color_override("font_color", UITheme.ACCENT_INFO.lightened(0.2))
	if ids.is_empty():
		UITheme.create_label("Nothing yet", _body, UITheme.FONT_SMALL).add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		return
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	var renderer = ItemRenderer.get_instance(get_tree())
	for id in ids:
		var tile = PanelContainer.new()
		tile.add_theme_stylebox_override("panel", UITheme.glass_box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.12), 14, 6, 6))
		tile.custom_minimum_size = Vector2(130, 150)
		grid.add_child(tile)
		var col = VBoxContainer.new()
		tile.add_child(col)
		var pic = TextureRect.new()
		pic.custom_minimum_size = Vector2(118, 112)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		col.add_child(pic)
		var name_label = UITheme.create_label(label.call(String(id)), col, UITheme.FONT_TINY)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var args: Array = picture.call(String(id))
		var put = func(tex):
			if is_instance_valid(pic):
				pic.texture = tex
		if args[0] == "gun":
			renderer.weapon(0, String(args[1]), put)
		else:
			renderer.hero(String(args[0]), String(args[1]), String(args[2]), put)

func _close() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()
