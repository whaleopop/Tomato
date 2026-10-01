## Lobby / spawn selection: players (left), hex map (center), spawn info + READY (right).
## The map is a 3D diorama (HexMap3DView) by default; the flat HexMapView is one click away.
## Both get the same tiles / reserved / selection, map_view answers the questions.
extends Control
class_name SpawnSelectMenu

signal spawn_confirmed(hex_coords: Vector2i)
signal ready_toggled(is_ready: bool)

const INVALID = Vector2i(-9999, -9999)
const BIOME_NAMES = ["Grass", "Forest", "Desert", "Rock", "Water", "Shallow water", "Swamp", "Beach", "Mountain",
	"Flower meadow", "Frost", "Tall grass", "Mushroom grove", "Brambles"]

# UI elements
var map_view: HexMapView = null
var map_3d: HexMap3DView = null
var view_button: Button = null
var map_hint: Label = null
var info_label: Label = null
var ready_button: Button = null
var countdown_label: Label = null
var players_list: VBoxContainer = null
var players_count: Label = null
var status_label: Label = null
var map_spinner: Control = null
var _hover_card: ParallaxCard = null
var _mode_holder: HBoxContainer = null
var _mode_shown: String = ""  # the hero card of the player row under the mouse

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
	# The match mode the host picked (GameModes; clients learn it with the lobby state)
	UITheme.create_spacer(true, header).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_holder = HBoxContainer.new()
	_mode_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_mode_holder)
	_refresh_mode()

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
	card.custom_minimum_size.x = 290

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

	map_3d = HexMap3DView.new()
	map_3d.hex_clicked.connect(_on_hex_pressed)
	map_3d.hex_hovered.connect(_on_hex_hovered)
	card.add_child(map_3d)
	map_view.visible = false

	# 3D / 2D switch and the camera hint in the map's corners
	var corners = VBoxContainer.new()
	corners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(corners)
	var top_row = HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 12)
	corners.add_child(top_row)
	map_hint = UITheme.create_label("Drag to turn  ·  right drag to move  ·  wheel to zoom  ·  double click to reset", top_row, UITheme.FONT_TINY)
	map_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_hint.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	map_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	map_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_button = UITheme.create_button("2D MAP", top_row, Vector2(120, 38))
	view_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	view_button.pressed.connect(_toggle_map_view)

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
	for biome in [0, 1, 2, 7, 6, 3, 8, 4, 9, 10, 11, 12, 13]:
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
	for view in _views():
		view.set_tiles(hex_grid_data)
		view.set_reserved(reserved_spawns)
	map_spinner.visible = hex_grid_data.is_empty()
	show_status("Click a free hex, then press READY")

func _views() -> Array:
	return [map_view, map_3d]

func _toggle_map_view():
	var flat = not map_view.visible
	map_view.visible = flat
	map_3d.visible = not flat
	map_hint.visible = not flat
	view_button.text = "3D MAP" if flat else "2D MAP"

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
	for view in _views():
		view.set_selected(coords)
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
		for view in _views():
			view.set_selected(INVALID)
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
		for view in _views():
			view.set_reserved(filtered)

func _refresh_mode():
	var mode = GameModes.current()
	if mode == _mode_shown or not _mode_holder:
		return
	_mode_shown = mode
	for c in _mode_holder.get_children():
		c.queue_free()
	var info = GameModes.info(mode)
	var pill = UITheme.create_pill(info.name, info.color, _mode_holder)
	pill.tooltip_text = tr(info.short)
	if mode == GameModes.CTF:
		show_status("Teams start at their base: the spot you pick is ignored")

func update_players_list(players_data: Dictionary):
	_refresh_mode()
	_hide_hero_card()
	for child in players_list.get_children():
		child.queue_free()

	var ready_count = 0
	for player_id in players_data.keys():
		var data = players_data[player_id]
		var player_ready: bool = data.get("ready", false)
		if player_ready:
			ready_count += 1

		var row = PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var is_me = player_id == my_player_id
		var fill = Color(UITheme.ACCENT_PRIMARY, 0.12) if is_me else Color(1, 1, 1, 0.05)
		row.add_theme_stylebox_override("panel", UITheme.glass_box(fill, Color(1, 1, 1, 0.08), 14, 12, 8))
		players_list.add_child(row)

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(dot)

		# The hero's portrait (like the shop's chips); hover the row for the hero's card
		var hero: CharacterData = CharacterRegistry.get_by_name(String(data.get("character", "")))
		var wear: Dictionary = data.get("cosmetics", {})
		var portrait = TextureRect.new()
		portrait.custom_minimum_size = Vector2(44, 44)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var frame = PanelContainer.new()
		var accent = hero.color if hero else Color(1, 1, 1, 0.3)
		frame.add_theme_stylebox_override("panel", UITheme.glass_box(Color(accent, 0.18), Color(accent.lightened(0.3), 0.8), 12, 2, 2))
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(portrait)
		hbox.add_child(frame)
		if hero:
			ItemRenderer.get_instance(get_tree()).hero(hero.character_name, String(wear.get("skin", "")), String(wear.get("hat", "")),
				func(tex): if is_instance_valid(portrait): portrait.texture = HeroChips._crop(tex, false))

		var names = VBoxContainer.new()
		names.add_theme_constant_override("separation", -2)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		names.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(names)
		var name_lbl = UITheme.create_label(data.get("name", tr("Player %d") % player_id), names, UITheme.FONT_SMALL)
		name_lbl.clip_text = true
		name_lbl.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		var hero_lbl = UITheme.create_label(hero.character_name if hero else "Choosing a hero...", names, UITheme.FONT_TINY)
		hero_lbl.clip_text = true
		hero_lbl.add_theme_color_override("font_color", hero.color.lightened(0.35) if hero else UITheme.TEXT_MUTED)

		if hero:
			row.mouse_default_cursor_shape = Control.CURSOR_HELP
			row.mouse_entered.connect(_show_hero_card.bind(row, hero, wear, String(data.get("name", ""))))
			row.mouse_exited.connect(_hide_hero_card)
			row.gui_input.connect(func(event):
				if event is InputEventMouseMotion and is_instance_valid(_hover_card):
					var p = event.position / row.size
					_hover_card._target = Vector2(p.x - 0.5, p.y - 0.5) * 2.0)

		var pill: Control = null
		if is_me:
			pill = UITheme.create_pill("You", UITheme.ACCENT_PRIMARY, hbox)
		elif player_id == 1:
			pill = UITheme.create_pill("Host", UITheme.ACCENT_SECONDARY, hbox)
		if pill:
			pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	players_count.text = tr("%d / %d ready") % [ready_count, players_data.size()]

## A shop card of the player's hero (in their skin and hat) next to the list
func _show_hero_card(row: Control, hero: CharacterData, wear: Dictionary, player_name: String):
	_hide_hero_card()
	var skin = String(wear.get("skin", ""))
	var hat = String(wear.get("hat", ""))
	var card = ParallaxCard.new()
	card.title = hero.character_name
	card.subtitle = Cosmetics.name_of(skin) if skin != "" else Cosmetics.TIER_NAMES[Cosmetics.tier_of(Cosmetics.hero_id(hero.character_name))]
	card.accent = hero.color
	card.badge = player_name
	card.live = ["hero", [hero.character_name, skin, hat]]
	card.show_wear_mastery(wear)
	card.always_live = true
	card.z_index = 20
	add_child(card)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the row keeps the hover
	var at = row.global_position - global_position + Vector2(row.size.x + 40, row.size.y / 2.0 - card.card_size.y / 2.0)
	at.y = clamp(at.y, 20.0, size.y - card.card_size.y - 20.0)
	card.position = at
	card.modulate.a = 0.0
	card.create_tween().tween_property(card, "modulate:a", 1.0, 0.12)
	ItemRenderer.get_instance(get_tree()).hero(hero.character_name, skin, hat, func(tex): if is_instance_valid(card): card.set_art(tex))
	_hover_card = card

func _hide_hero_card():
	if is_instance_valid(_hover_card):
		_hover_card.queue_free()
	_hover_card = null

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
