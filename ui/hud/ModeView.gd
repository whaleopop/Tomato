## What the match mode shows (every peer, from NetworkManager.mode_state = ModeRules.state_for):
## - all modes: a top panel (time, score), the mode's announcements as HUD alerts;
## - King of the Hill: the platform (a ring and a light column, colored by who holds it) and the
##   points of the best players;
## - Capture the Flag: both flags (on their pole, or over the carrier's head), the bases, a colored
##   ring under every hero (the "team" meta, also read by friendly fire and the fog);
## - Weed Swarm: wave, time left, the perks taken; after a wave two double perk cards come up
##   (PerkCard, SwarmPerks: a buff over a debuff) - the host applies its pick directly, clients
##   send the card index as input. Also turns on auto-fire / endless ammo for our own hero.
extends Control
class_name ModeView

var player: Player = null
var hud: Node = null
var mode: String = GameModes.BR
var state: Dictionary = {}

var _panel: PanelContainer
var _title: Label
var _line: Label
var _bar: ProgressBar
var _board: VBoxContainer
var _hint: Label
var _picker: Control = null
var _last_event: int = 0
var _world: Node3D = null
var _hill: Node3D = null
var _hill_mat: StandardMaterial3D
var _flags: Array = [null, null]
var _bases_built: bool = false
var _rings: Dictionary = {}       # player node -> ring

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # in the tree already: plain anchors would keep the 0x0 size
	mode = GameModes.current()
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.glass_box(UITheme.GLASS_TINT_HUD, Color(GameModes.info(mode).color, 0.6), UITheme.CORNER_RADIUS_SMALL, 18, 8))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# PlayerHUD's top-center column stacks it over the alerts; a bare parent gets its own holder
	var column = get_parent().get("top_center") if get_parent() else null
	if column is VBoxContainer:
		_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(_panel)
		column.move_child(_panel, 0)
	else:
		var holder = CenterContainer.new()
		holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
		holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
		holder.offset_top = UITheme.MARGIN_MEDIUM
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		holder.add_child(_panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_title = UITheme.create_heading("", box)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", UITheme.font_black())
	_line = UITheme.create_label("", box, UITheme.FONT_SMALL)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	_bar = UITheme.create_progress_bar(1.0, 0.0, GameModes.info(mode).color, box)
	_bar.custom_minimum_size = Vector2(300, 8)
	_bar.visible = mode == GameModes.SURVIVORS
	_hint = UITheme.create_label("", box, UITheme.FONT_SMALL)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_hint.visible = false
	# The scoreboard (King of the Hill) in the top-left corner
	_board = VBoxContainer.new()
	_board.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_board.position = Vector2(UITheme.MARGIN_MEDIUM, UITheme.MARGIN_MEDIUM)
	_board.add_theme_constant_override("separation", 4)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.has_signal("mode_state"):
		nm.mode_state.connect(_on_state)

func setup(p_player: Player, p_hud: Node) -> void:
	player = p_player
	hud = p_hud
	_world = p_player.get_parent() as Node3D
	if mode == GameModes.SURVIVORS and player:
		player.set_meta("auto_fire", true)
		player.set_meta("endless_ammo", true)

func _my_id() -> int:
	return player.entity_id if player and is_instance_valid(player) else 0

static func _clock(seconds: float) -> String:
	var t = int(max(seconds, 0.0))
	return "%d:%02d" % [t / 60, t % 60]

func _name(id) -> String:
	if int(id) == _my_id():
		return tr("You")
	return String(state.get("names", {}).get(id, state.get("names", {}).get(int(id), "?")))

func _on_state(s: Dictionary) -> void:
	if s.is_empty():
		return
	state = s
	mode = String(s.get("mode", mode))
	_announce(s.get("event", []))
	match mode:
		GameModes.KOTH:
			_koth(s)
		GameModes.CTF:
			_ctf(s)
		GameModes.SURVIVORS:
			_survivors(s)

func _announce(e: Array) -> void:
	if e.size() < 4 or int(e[0]) == _last_event:
		return
	_last_event = int(e[0])
	var args: Array = []
	for a in e[2]:
		args.append(tr(a) if a is String else a)
	var text = tr(String(e[1]))
	if not args.is_empty():
		text = text % args
	if hud and hud.has_method("show_alert"):
		hud.show_alert(text, Color.html(String(e[3])))

# ---------------------------------------------------------------- King of the Hill

func _koth(s: Dictionary) -> void:
	var limit = float(s.get("limit", 480.0))
	var holder = int(s.get("holder", 0))
	_title.text = tr("KING OF THE HILL") + "   " + _clock(limit - float(s.time))
	if bool(s.get("contested", false)):
		_line.text = tr("The hill is contested!")
	elif holder != 0:
		_line.text = tr("%s holds the hill") % _name(holder)
	else:
		_line.text = tr("Nobody on the hill")
	# Board: the top five
	var pts: Dictionary = s.get("points", {})
	var ids = pts.keys()
	ids.sort_custom(func(a, b): return int(pts[a]) > int(pts[b]))
	for c in _board.get_children():
		c.queue_free()
	for id in ids.slice(0, 5):
		var row = UITheme.create_label("%s   %d / %d" % [_name(id), int(pts[id]), int(s.get("goal", 100))], _board, UITheme.FONT_SMALL)
		row.add_theme_font_override("font", UITheme.font_black())
		row.add_theme_color_override("font_color", UITheme.ACCENT_PRIMARY.lightened(0.3) if int(id) == _my_id() else Color(1, 1, 1, 0.85))
	# The platform
	var h: Array = s.get("hill", [])
	if h.size() >= 4 and _world and _hill == null:
		_hill = Node3D.new()
		_world.add_child(_hill)
		_hill.global_position = Vector3(h[0], h[1] + 0.05, h[2])
		_hill_mat = StandardMaterial3D.new()
		_hill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var ring = MeshInstance3D.new()
		var torus = TorusMesh.new()
		torus.inner_radius = float(h[3]) - 0.25
		torus.outer_radius = float(h[3])
		ring.mesh = torus
		ring.material_override = _hill_mat
		_hill.add_child(ring)
		var column = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = float(h[3])
		cyl.bottom_radius = float(h[3])
		cyl.height = 9.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		column.mesh = cyl
		column.position.y = 4.5
		var col_mat = _hill_mat.duplicate()
		column.material_override = col_mat
		column.set_meta("column", true)
		_hill.add_child(column)
		_hill.add_to_group("map_markers")
		_hill.set_meta("marker_color", GameModes.info(GameModes.KOTH).color)
	if _hill:
		var c = Color(1, 1, 1)
		if bool(s.get("contested", false)):
			c = Color(1.0, 0.8, 0.25)
		elif holder == _my_id():
			c = UITheme.ACCENT_PRIMARY
		elif holder != 0:
			c = UITheme.ACCENT_DANGER
		_hill_mat.albedo_color = Color(c, 0.9)
		for n in _hill.get_children():
			if n.get_meta("column", false):
				(n.material_override as StandardMaterial3D).albedo_color = Color(c, 0.12)

# ---------------------------------------------------------------- Capture the Flag

func _ctf(s: Dictionary) -> void:
	var score: Array = s.get("score", [0, 0])
	var limit = float(s.get("limit", 600.0))
	var teams: Dictionary = s.get("teams", {})
	var my_team = int(teams.get(_my_id(), -1))
	_title.text = "%s %d  :  %d %s" % [tr("RED"), int(score[0]), int(score[1]), tr("BLUE")]
	var line = _clock(limit - float(s.time))
	if my_team >= 0:
		line += "   ·   " + tr("You play for the %s") % tr(GameModes.TEAM_NAMES[my_team])
		_line.add_theme_color_override("font_color", GameModes.TEAM_COLORS[my_team].lightened(0.3))
	_line.text = line
	var flags: Array = s.get("flags", [])
	var carrying = false
	for f in flags:
		if int(f[4]) == _my_id():
			carrying = true
	_hint.visible = carrying
	_hint.text = tr("You have the flag! Bring it to your base")
	# Teams and carriers on every hero we have
	for p in get_tree().get_nodes_in_group("players"):
		if not (p is Player):
			continue
		var t = int(teams.get(p.entity_id, -1))
		if t >= 0:
			p.set_meta("team", t)
			_ring(p, GameModes.TEAM_COLORS[t])
		var carries = false
		for i in flags.size():
			if int(flags[i][4]) == p.entity_id:
				carries = true
		if carries:
			p.set_meta("flag_carrier", true)
		elif p.has_meta("flag_carrier"):
			p.remove_meta("flag_carrier")
	if not _world:
		return
	# Bases
	if not _bases_built:
		_bases_built = true
		var bases: Array = s.get("bases", [])
		for t in bases.size():
			var b = bases[t]
			var ring = _glow_ring(2.8, GameModes.TEAM_COLORS[t])
			_world.add_child(ring)
			ring.global_position = Vector3(b[0], b[1] + 0.06, b[2])
			ring.add_to_group("map_markers")
			ring.set_meta("marker_color", GameModes.TEAM_COLORS[t])
	# Flags
	for t in flags.size():
		var f = flags[t]
		if _flags[t] == null:
			_flags[t] = _make_flag(GameModes.TEAM_COLORS[t])
			_world.add_child(_flags[t])
		var pos = Vector3(f[0], f[1], f[2])
		var carried = int(f[4]) != 0
		var target = pos + (Vector3(0, 1.9, 0) if carried else Vector3.ZERO)
		var node: Node3D = _flags[t]
		node.global_position = node.global_position.lerp(target, 0.5) if node.global_position.distance_to(target) < 4.0 else target
		node.scale = Vector3.ONE * (0.6 if carried else 1.0)

func _make_flag(color: Color) -> Node3D:
	var n = Node3D.new()
	var pole = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.06
	cyl.height = 2.6
	pole.mesh = cyl
	pole.position.y = 1.3
	var pm = StandardMaterial3D.new()
	pm.albedo_color = Color(0.85, 0.85, 0.9)
	pm.metallic = 0.7
	pole.material_override = pm
	n.add_child(pole)
	var cloth = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(1.1, 0.7)
	cloth.mesh = quad
	cloth.position = Vector3(0.58, 2.2, 0)
	var cm = StandardMaterial3D.new()
	cm.albedo_color = color
	cm.emission_enabled = true
	cm.emission = color
	cm.emission_energy_multiplier = 0.8
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.material_override = cm
	n.add_child(cloth)
	var glow = OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 1.5
	glow.omni_range = 4.0
	glow.position.y = 2.0
	n.add_child(glow)
	n.add_to_group("map_markers")
	n.set_meta("marker_color", color)
	return n

func _glow_ring(radius: float, color: Color) -> MeshInstance3D:
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = radius - 0.2
	torus.outer_radius = radius
	ring.mesh = torus
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	ring.material_override = m
	return ring

func _ring(p: Node3D, color: Color) -> void:
	if _rings.has(p) and is_instance_valid(_rings[p]):
		return
	var ring = _glow_ring(0.75, color)
	ring.position.y = 0.06
	p.add_child(ring)
	_rings[p] = ring

# ---------------------------------------------------------------- Weed Swarm

func _survivors(s: Dictionary) -> void:
	# The server hasn't seen our pick yet: that offer is used up already
	if int(s.get("seq", 0)) == _picked_seq and s.has("offer"):
		s.erase("offer")
		s["pending"] = max(0, int(s.get("pending", 0)) - 1)
	var phase = String(s.get("phase", "wait"))
	var left = float(s.get("left", 0.0))
	_title.text = "%s %d   ·   %s" % [tr("WAVE"), max(int(s.get("wave", 0)), 1), _clock(float(s.time))]
	match phase:
		"fight":
			_line.text = tr("Weeds felled: %d") % int(s.get("kills", 0)) + "   ·   " + tr("Wave ends in %d s") % int(ceil(left))
		"break":
			_line.text = tr("Break: next wave in %d s") % int(ceil(left))
		_:
			_line.text = tr("The weeds are coming in %d s") % int(ceil(left))
	_bar.max_value = max(0.1, float(s.get("wave_time", 1.0)))
	_bar.value = left
	var pending = int(s.get("pending", 0))
	_hint.visible = pending > 0 and _picker == null
	_hint.text = tr("Tab: pick a card (%d)") % pending
	_perk_list(s.get("taken", []))
	# A new offer: the cards come up on their own (once; Tab brings them back)
	var seq = int(s.get("seq", 0))
	if pending > 0 and s.has("offer") and seq != _seen_seq and _alive():
		_seen_seq = seq
		_close_picker()
		_open_picker()

var _seen_seq: int = 0
var _picked_seq: int = -1
var _taken_count: int = -1

func _alive() -> bool:
	var h = player.get_component("HealthComponent") if player and is_instance_valid(player) else null
	return h != null and not h.is_dead

## What we picked so far, summed up per perk: buffs green, debuffs red (left, under the health card)
func _perk_list(taken: Array) -> void:
	if taken.size() == _taken_count:
		return
	_taken_count = taken.size()
	for c in _board.get_children():
		c.queue_free()
	var counts = {}
	var order: Array = []
	for card in taken:
		for id in card:
			if not counts.has(id):
				order.append(id)
			counts[id] = int(counts.get(id, 0)) + 1
	order.sort_custom(func(a, b): return SwarmPerks.is_buff(a) and not SwarmPerks.is_buff(b))
	for id in order:
		var p = SwarmPerks.get_perk(String(id))
		if p.is_empty():
			continue
		var text = tr(String(p[0]))
		if counts[id] > 1:
			text += "  ×%d" % counts[id]
		var pcol = SwarmPerks.BUFF_COLOR if SwarmPerks.is_buff(id) else SwarmPerks.DEBUFF_COLOR
		var row = UITheme.create_icon_label(SwarmPerks.icon(id), text, _board, UITheme.FONT_SMALL, pcol)
		var row_label: Label = row.get_meta("label")
		row_label.add_theme_font_override("font", UITheme.font_black())
		row.tooltip_text = tr(String(p[1]))

func _unhandled_input(event: InputEvent):
	if mode != GameModes.SURVIVORS or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB:
		if _picker:
			_close_picker()
		elif int(state.get("pending", 0)) > 0 and state.has("offer"):
			_open_picker()
		get_viewport().set_input_as_handled()
	elif _picker and event.keycode in [KEY_1, KEY_2, KEY_KP_1, KEY_KP_2]:
		_pick(0 if event.keycode in [KEY_1, KEY_KP_1] else 1)
		get_viewport().set_input_as_handled()

func _open_picker() -> void:
	var cards: Array = state.get("offer", [])
	if cards.is_empty():
		return
	_picker = Control.new()
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker.add_to_group("blocks_game_input")  # the mouse comes free, gameplay input waits
	add_child(_picker)
	var dim = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(center)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)
	var title = UITheme.create_title("PICK A CARD", col)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub = UITheme.create_label("Every card gives something and takes something", col, UITheme.FONT_NORMAL)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for i in cards.size():
		if not SwarmPerks.valid_card(cards[i]):
			continue
		var card = PerkCard.new()
		card.buff = String(cards[i][0])
		card.debuff = String(cards[i][1])
		card.hotkey = str(i + 1)
		card.delay = i * 0.15
		card.pressed.connect(_pick.bind(i))
		row.add_child(card)
	var hint = UITheme.create_label("Click or 1 / 2   ·   Tab - later", col, UITheme.FONT_SMALL)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_hint.visible = false

func _close_picker() -> void:
	if _picker:
		_picker.queue_free()
		_picker = null

func _pick(index: int) -> void:
	var cards: Array = state.get("offer", [])
	_close_picker()
	if index < 0 or index >= cards.size() or not SwarmPerks.valid_card(cards[index]):
		return
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.game_server and nm.game_server.rules:
		nm.game_server.rules.on_choice(_my_id(), str(index))  # the host: its hero is the server's entity
	else:
		var handler = player.get_node_or_null("InputHandler") if player else null
		if handler and handler.has_method("send_ui_action"):
			handler.send_ui_action({"mode_choice": str(index)})
		# Our own copy, so speed / fire rate / range feel right at once
		SwarmPerks.apply(player, String(cards[index][0]))
		SwarmPerks.apply(player, String(cards[index][1]))
	# Until the next state says otherwise: this offer is used up
	_picked_seq = int(state.get("seq", 0))
	state.erase("offer")
	state["pending"] = int(state.get("pending", 0)) - 1
	var taken: Array = state.get("taken", []).duplicate()
	taken.append(cards[index])
	state["taken"] = taken
	_hint.visible = int(state.pending) > 0
	_perk_list(taken)
