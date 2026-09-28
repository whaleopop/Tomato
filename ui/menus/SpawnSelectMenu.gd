## Lobby / spawn selection: players (left), hex map (center), spawn info + READY (right)
extends Control
class_name SpawnSelectMenu

signal spawn_confirmed(hex_coords: Vector2i)
signal ready_toggled(is_ready: bool)

const INVALID = Vector2i(-9999, -9999)
const BIOME_NAMES = ["Grass", "Forest", "Desert", "Rock", "Water", "Shallow water", "Swamp", "Beach", "Mountain"]

# UI elements
var map_view: HexMapView = null
var info_label: Label = null
var ready_button: Button = null
var countdown_label: Label = null
var players_list: VBoxContainer = null
var players_count: Label = null
var status_label: Label = null
var map_spinner: Control = null

# State
var selected_spawn: Vector2i = INVALID
var is_ready: bool = false
var hex_grid_data: Dictionary = {}  # coords -> {biome, height, spawnable}
var reserved_spawns: Array = []
var my_player_id: int = 0

func _ready():
	if not map_view:
		_create_ui()

func _create_ui():
	UITheme.create_background(self)

	var margin = UITheme.create_screen_margin(self, 28)
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	# ---- Header
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)

	var back_btn = UITheme.create_button("←  BACK", header, Vector2(130, 46))
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(_on_back_pressed)

	var title_box = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	header.add_child(title_box)
	var title = UITheme.create_title("PICK YOUR LANDING SPOT", title_box)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_label = UITheme.create_label("Click a free hex, then press READY", title_box, UITheme.FONT_SMALL)
	status_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	# ---- Body
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)

	body.add_child(_create_left_panel())
	body.add_child(_create_center_panel())
	body.add_child(_create_right_panel())

func _create_left_panel() -> Control:
	var card = UITheme.create_panel(null, 20)
	card.custom_minimum_size.x = 250

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)

	var head = HBoxContainer.new()
	box.add_child(head)
	UITheme.create_caption("Players", head).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_count = UITheme.create_label("", head, UITheme.FONT_TINY)

	players_list = VBoxContainer.new()
	players_list.add_theme_constant_override("separation", 8)
	box.add_child(players_list)
	return card

func _create_center_panel() -> Control:
	var card = UITheme.create_panel(null, 14)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	map_view = HexMapView.new()
	map_view.hex_clicked.connect(_on_hex_pressed)
	map_view.hex_hovered.connect(_on_hex_hovered)
	card.add_child(map_view)

	# Overlays on top of the map (spinner while waiting, countdown)
	var overlay = CenterContainer.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(overlay)

	var stack = VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(stack)

	map_spinner = Spinner.new()
	map_spinner.custom_minimum_size = Vector2(56, 56)
	map_spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(map_spinner)

	countdown_label = UITheme.create_hero_title("", stack)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 96)
	countdown_label.visible = false
	return card

func _create_right_panel() -> Control:
	var card = UITheme.create_panel(null, 24)
	card.custom_minimum_size.x = 300

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)

	UITheme.create_caption("Landing spot", box)
	info_label = UITheme.create_heading("Nothing selected", box)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size.y = 70

	UITheme.create_separator(box)
	UITheme.create_caption("Legend", box)
	var legend = GridContainer.new()
	legend.columns = 2
	legend.add_theme_constant_override("h_separation", 14)
	legend.add_theme_constant_override("v_separation", 6)
	box.add_child(legend)
	for biome in [0, 1, 2, 7, 6, 3, 8, 4]:
		_add_legend_item(legend, HexMapView.BIOME_COLORS[biome], BIOME_NAMES[biome])
	_add_legend_item(legend, Color(1.0, 0.38, 0.40), "Taken")
	_add_legend_item(legend, UITheme.ACCENT_PRIMARY, "Yours")

	UITheme.create_spacer(true, box)

	var hint = UITheme.create_label("The match starts when everyone is ready", box, UITheme.FONT_SMALL)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	ready_button = UITheme.create_primary_button("READY", box, Vector2(0, 60))
	ready_button.pressed.connect(_on_ready_pressed)
	ready_button.disabled = true
	return card

func _add_legend_item(parent: Control, color: Color, text: String):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var swatch = Panel.new()
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	swatch.add_theme_stylebox_override("panel", box)
	row.add_child(swatch)

	UITheme.create_label(text, row, UITheme.FONT_TINY)

## Map data arrived (from the server or the host's own world)
func setup(grid_data: Dictionary, p_reserved_spawns: Array, player_id: int):
	hex_grid_data = grid_data
	reserved_spawns = p_reserved_spawns
	my_player_id = player_id
	call_deferred("_deferred_setup")

func _deferred_setup():
	if not map_view:
		_create_ui()
	map_view.set_tiles(hex_grid_data)
	map_view.set_reserved(reserved_spawns)
	map_spinner.visible = hex_grid_data.is_empty()
	show_status("Click a free hex, then press READY")

func has_map() -> bool:
	return map_view != null and not map_view.tiles.is_empty()

func is_hex_selectable(coords: Vector2i) -> bool:
	return map_view != null and map_view.is_selectable(coords)

func show_status(text: String):
	if status_label:
		status_label.text = text

func _describe(coords: Vector2i) -> String:
	var biome = hex_grid_data.get(coords, {}).get("biome", 0)
	var biome_name = tr(BIOME_NAMES[biome] if biome < BIOME_NAMES.size() else "Unknown")
	return "%s  ·  (%d, %d)" % [biome_name, coords.x, coords.y]

func _on_hex_pressed(coords: Vector2i):
	if is_ready:
		show_status("Cancel READY to change your spot")
		return
	if not map_view.is_selectable(coords):
		show_status("You can't land there")
		return

	selected_spawn = coords
	map_view.set_selected(coords)
	info_label.text = _describe(coords)
	ready_button.disabled = false
	spawn_confirmed.emit(coords)

func _on_hex_hovered(coords: Vector2i):
	if selected_spawn != INVALID:
		return
	if map_view.reserved.has(coords):
		info_label.text = tr("Taken  ·  (%d, %d)") % [coords.x, coords.y]
	elif not map_view.is_selectable(coords):
		info_label.text = "Can't land here"
	else:
		info_label.text = _describe(coords)

func _on_ready_pressed():
	is_ready = not is_ready

	if is_ready:
		ready_button.text = "CANCEL READY"
		UITheme.set_accent(ready_button, UITheme.ACCENT_DANGER, Color.WHITE)
		show_status("Waiting for the other players...")
	else:
		ready_button.text = "READY"
		UITheme.set_accent(ready_button, UITheme.ACCENT_PRIMARY)
		show_status("Click a free hex, then press READY")

	ready_toggled.emit(is_ready)

func _on_back_pressed():
	# Leaving while READY could start the match without us (the host then never got in)
	if is_ready:
		is_ready = false
		ready_toggled.emit(false)
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/CharacterSelectScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/CharacterSelectScene.tscn")

## The server refused our spot (someone was faster): back to picking, READY off
func clear_selection(message: String = ""):
	selected_spawn = INVALID
	if map_view:
		map_view.set_selected(INVALID)
	info_label.text = ""
	ready_button.disabled = true
	if is_ready:
		_on_ready_pressed()
	if message != "":
		show_status(message)

func update_reserved_spawns(new_reserved: Array):
	# Our own reservation area is not "taken" for us
	var filtered: Array = []
	for c in new_reserved:
		if c != selected_spawn:
			filtered.append(c)
	reserved_spawns = filtered
	if map_view:
		map_view.set_reserved(filtered)

func update_players_list(players_data: Dictionary):
	for child in players_list.get_children():
		child.queue_free()

	var ready_count = 0
	for player_id in players_data.keys():
		var data = players_data[player_id]
		var player_ready: bool = data.get("ready", false)
		if player_ready:
			ready_count += 1

		var row = PanelContainer.new()
		var is_me = player_id == my_player_id
		var fill = Color(UITheme.ACCENT_PRIMARY, 0.12) if is_me else Color(1, 1, 1, 0.05)
		row.add_theme_stylebox_override("panel", UITheme.glass_box(fill, Color(1, 1, 1, 0.08), 14, 12, 8))
		players_list.add_child(row)

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		row.add_child(hbox)

		var dot = Panel.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var dot_box = StyleBoxFlat.new()
		dot_box.bg_color = UITheme.ACCENT_SUCCESS if player_ready else Color(1, 1, 1, 0.25)
		dot_box.set_corner_radius_all(99)
		if player_ready:
			dot_box.shadow_color = Color(UITheme.ACCENT_SUCCESS, 0.6)
			dot_box.shadow_size = 5
		dot.add_theme_stylebox_override("panel", dot_box)
		hbox.add_child(dot)

		var name_lbl = UITheme.create_label(data.get("name", tr("Player %d") % player_id), hbox, UITheme.FONT_SMALL)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)

		if is_me:
			UITheme.create_pill("You", UITheme.ACCENT_PRIMARY, hbox)
		elif player_id == 1:
			UITheme.create_pill("Host", UITheme.ACCENT_SECONDARY, hbox)

	players_count.text = tr("%d / %d ready") % [ready_count, players_data.size()]

func show_countdown(seconds: int):
	countdown_label.visible = true
	countdown_label.text = str(seconds)
	countdown_label.pivot_offset = countdown_label.size / 2.0
	countdown_label.scale = Vector2.ONE * 1.4
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(countdown_label, "scale", Vector2.ONE, 0.35)
	show_status(tr("Match starting in %d...") % seconds)

func hide_countdown():
	if countdown_label.visible:
		countdown_label.visible = false
		if is_ready:
			show_status("Waiting for the other players...")
