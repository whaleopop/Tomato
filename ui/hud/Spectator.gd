## After you are eliminated you stay and watch: the camera follows whoever took you out, then
## anyone still standing (A / D or the arrows switch). A bar at the bottom says who you watch.
## Eliminated players see the whole map (ServerVisibility / VisibilitySystem.reveal_all), so every
## survivor is there to follow.
extends PanelContainer
class_name Spectator

signal leave_pressed

var me: Player = null
var target: Player = null
var _name_label: Label = null
var _hero_label: Label = null
var _hp_bar: ProgressBar = null
var _dot: Panel = null
var _names: Dictionary = {}   # player id -> nickname (lobby state + kill feed)

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.82), Color(1, 1, 1, 0.12), 18, 18, 10))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	var prev = UITheme.create_button("‹", row, Vector2(46, 46))
	prev.pressed.connect(func(): step(-1))

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size.x = 260
	row.add_child(box)
	var cap = UITheme.create_caption("SPECTATING", box)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var line = HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 8)
	box.add_child(line)
	_dot = Panel.new()
	_dot.custom_minimum_size = Vector2(12, 12)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_dot)
	_name_label = UITheme.create_heading("", line)
	_hero_label = UITheme.create_label("", line, UITheme.FONT_SMALL)
	_hero_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_hp_bar = UITheme.create_progress_bar(100, 100, UITheme.ACCENT_SUCCESS, box)
	_hp_bar.custom_minimum_size = Vector2(0, 6)
	var hint = UITheme.create_label("A / D - next player", box, UITheme.FONT_TINY)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	var next = UITheme.create_button("›", row, Vector2(46, 46))
	next.pressed.connect(func(): step(1))

	var leave = UITheme.create_button("MENU", row, Vector2(110, 46))
	leave.pressed.connect(func(): leave_pressed.emit())

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_signal("player_killed"):
		network_manager.player_killed.connect(_on_kill)

func start(p_me: Player, first_id: int):
	me = p_me
	var cam = _camera()
	if cam and cam.third_person:
		cam.set_third_person(false, false)  # watching works from above (no captured mouse)
	var first = _player_by_id(first_id) if first_id != 0 else null
	if first and _alive(first):
		follow(first)
	else:
		step(1)

## Everyone still standing, in a stable order
func candidates() -> Array:
	var out: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and p != me and _alive(p) and not p.get_meta("net_hidden", false):
			out.append(p)
	out.sort_custom(func(a, b): return a.entity_id < b.entity_id)
	return out

func step(dir: int):
	var list = candidates()
	if list.is_empty():
		target = null
		_refresh()
		return
	var i = list.find(target)
	i = (i + dir) % list.size() if i >= 0 else 0
	if i < 0:
		i += list.size()
	follow(list[i])

func follow(p: Player):
	target = p
	var cam = _camera()
	if cam:
		cam.set_target(p)
	_refresh()

func _process(_delta):
	if not visible:
		return
	if target == null or not is_instance_valid(target) or not _alive(target):
		step(1)
	if target and is_instance_valid(target):
		var health = target.get_component("HealthComponent")
		if health:
			_hp_bar.max_value = health.max_health
			_hp_bar.value = health.current_health

func _unhandled_input(event: InputEvent):
	if not visible:
		return
	if event.is_action_pressed("move_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_LEFT):
		step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_RIGHT):
		step(1)
		get_viewport().set_input_as_handled()

func _refresh():
	if target == null or not is_instance_valid(target):
		_name_label.text = tr("Nobody left to watch")
		_hero_label.text = ""
		return
	var hero = target.character_data.character_name if target.character_data else ""
	_name_label.text = _nick(target.entity_id, hero)
	_hero_label.text = tr(hero) if hero != "" and _name_label.text != tr(hero) else ""
	var col = target.character_data.color.lightened(0.3) if target.character_data else Color.WHITE
	_name_label.add_theme_color_override("font_color", col)
	var dot_box = StyleBoxFlat.new()
	dot_box.bg_color = col
	dot_box.set_corner_radius_all(99)
	_dot.add_theme_stylebox_override("panel", dot_box)

func _nick(id: int, hero: String) -> String:
	if _names.has(id):
		return _names[id]
	var network_manager = get_node_or_null("/root/NetworkManager")
	var lobby = network_manager.get_network_lobby() if network_manager and network_manager.has_method("get_network_lobby") else null
	if lobby:
		var names: Dictionary = lobby.last_lobby_state.get("players_names", {})
		if names.has(id):
			return String(names[id])
	return tr(hero) if hero != "" else tr("Player %d") % id

func _on_kill(victim_id: int, killer_id: int, info: Dictionary):
	if info.has("victim_name"):
		_names[victim_id] = String(info["victim_name"])
	if killer_id != 0 and info.has("killer_name"):
		_names[killer_id] = String(info["killer_name"])

func _alive(p: Node) -> bool:
	if not is_instance_valid(p) or not p.is_inside_tree():
		return false
	var health = p.get_component("HealthComponent") if p.has_method("get_component") else null
	return health != null and not health.is_dead

func _player_by_id(id: int) -> Player:
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and p.entity_id == id:
			return p
	return null

func _camera() -> CameraController:
	return get_viewport().get_camera_3d() as CameraController
