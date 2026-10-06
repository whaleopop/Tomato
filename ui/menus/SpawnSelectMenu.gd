## Lobby / spawn selection: players (left), hex map (center), spawn info + READY (right).
## The map is a 3D diorama (HexMap3DView) by default; the flat HexMapView is one click away.
## Both get the same tiles / reserved / selection, map_view answers the questions.
## Looks like the main menu: the screen header (the mode as its kicker), navy panels and rows,
## the gold READY and a gold countdown over the map.
extends Control
class_name SpawnSelectMenu

signal spawn_confirmed(hex_coords: Vector2i)
signal ready_toggled(is_ready: bool)

const INVALID = Vector2i(-9999, -9999)
const BIOME_NAMES = ["Grass", "Forest", "Desert", "Rock", "Water", "Shallow water", "Swamp", "Beach", "Mountain",
	"Flower meadow", "Frost", "Tall grass", "Mushroom grove", "Brambles"]
const GOLD_TEXT = Color(0.10, 0.06, 0.0)  # dark text on the gold button
const SIDE_WIDTH = 300

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
var header: ScreenHeader = null
var _hover_card: ParallaxCard = null
var _mode_holder: VBoxContainer = null
var _mode_shown: String = ""  # the mode shown in the header / the mode block
var _info_kicker: Label = null

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
	# The plain backdrop: the 3D map is this screen's scene (a second 3D garden behind it would
	# only cost frames while the host builds the match)
	UITheme.create_background(self)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_top = ScreenHeader.CONTENT_TOP
	margin.offset_left = ScreenHeader.SIDE_MARGIN
	margin.offset_right = -ScreenHeader.SIDE_MARGIN
	margin.offset_bottom = -24
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(body)
	body.add_child(_create_left_panel())
	body.add_child(_create_center_panel())
	body.add_child(_create_right_panel())

	# ---- The bar every screen has: back to the hero pick, the mode the host picked as the kicker
	# (clients learn it with the lobby state), settings without a scene reload (we are in a lobby)
	header = ScreenHeader.make(self, "PICK YOUR LANDING SPOT", "")
	header.back_pressed.connect(_on_back_pressed)
	header.add_settings_chip(false)
	_refresh_mode()

## A small gold uppercase kicker (the template's section label)
func _kicker(text: String, parent: Control) -> Label:
	var label = UITheme.create_label(text, parent, 12)
	label.uppercase = true
	label.add_theme_font_override("font", UITheme.font_black())
	label.add_theme_color_override("font_color", UITheme.GOLD)
	return label

func _create_left_panel() -> Control:
	var card = UITheme.navy_panel(null, 18)
	card.custom_minimum_size.x = SIDE_WIDTH

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)

	var head = HBoxContainer.new()
	box.add_child(head)
	_kicker("Players", head).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_count = UITheme.create_label("", head, UITheme.FONT_TINY)
	players_count.add_theme_font_override("font", UITheme.font_bold())
	players_count.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	players_list = VBoxContainer.new()
	players_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_list.add_theme_constant_override("separation", 8)
	scroll.add_child(players_list)

	var hint = UITheme.create_label("Hover a player to see their hero", box, UITheme.FONT_TINY)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	return card

func _create_center_panel() -> Control:
	var card = UITheme.navy_panel(null, 12)
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

	# 3D / 2D switch and the camera hint in the map's corners, the status at the bottom
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
	map_hint.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	map_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	map_hint.add_theme_constant_override("shadow_offset_y", 1)
	map_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_button = UITheme.create_button("2D MAP", top_row, Vector2(120, 40))
	view_button.add_theme_font_override("font", UITheme.font_black())
	view_button.add_theme_font_size_override("font_size", 15)
	view_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	view_button.pressed.connect(_toggle_map_view)
	UITheme.create_spacer(true, corners).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var status_row = CenterContainer.new()
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corners.add_child(status_row)
	var status_box = PanelContainer.new()
	status_box.add_theme_stylebox_override("panel", UITheme.navy_box(Color(0.03, 0.045, 0.09, 0.88), Color(UITheme.GOLD, 0.45), 999, 22, 8))
	status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(status_box)
	status_label = UITheme.create_label("Click a free hex, then press READY", status_box, UITheme.FONT_SMALL)
	status_label.add_theme_font_override("font", UITheme.font_bold())
	status_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	countdown_label.add_theme_font_override("font", UITheme.font_black())
	countdown_label.add_theme_font_size_override("font_size", 120)
	countdown_label.add_theme_color_override("font_color", UITheme.GOLD)
	countdown_label.add_theme_color_override("font_outline_color", Color(0.10, 0.06, 0.0, 0.85))
	countdown_label.add_theme_constant_override("outline_size", 14)
	countdown_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	countdown_label.add_theme_constant_override("shadow_offset_y", 6)
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_label.visible = false
	return card

func _create_right_panel() -> Control:
	var card = UITheme.navy_panel(null, 20)
	card.custom_minimum_size.x = SIDE_WIDTH

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)

	# The match mode the host picked (GameModes; clients learn it with the lobby state)
	_mode_holder = VBoxContainer.new()
	_mode_holder.add_theme_constant_override("separation", 6)
	box.add_child(_mode_holder)

	UITheme.create_separator(box)
	_info_kicker = _kicker("Landing spot", box)
	info_label = UITheme.create_heading("Nothing selected", box)
	info_label.add_theme_font_override("font", UITheme.font_black())
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size.y = 52

	UITheme.create_separator(box)
	_kicker("Legend", box)
	var legend = GridContainer.new()
	legend.columns = 2
	legend.add_theme_constant_override("h_separation", 14)
	legend.add_theme_constant_override("v_separation", 5)
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
	ready_button.add_theme_font_size_override("font_size", 24)
	ready_button.pressed.connect(_on_ready_pressed)
	ready_button.disabled = true
	return card

func _add_legend_item(parent: Control, color: Color, text: String):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var swatch = Panel.new()
	swatch.custom_minimum_size = Vector2(12, 12)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(3)
	box.border_color = Color(color.lightened(0.4), 0.6)
	box.set_border_width_all(1)
	swatch.add_theme_stylebox_override("panel", box)
	row.add_child(swatch)

	var label = UITheme.create_label(text, row, UITheme.FONT_TINY)
	label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

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
	info_label.add_theme_color_override("font_color", UITheme.GOLD)
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
		UITheme.set_accent(ready_button, UITheme.GOLD, GOLD_TEXT)
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
	info_label.remove_theme_color_override("font_color")
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

## The mode in the header's kicker and as the right panel's first block (its color, name and line)
func _refresh_mode():
	var mode = GameModes.current()
	if mode == _mode_shown or not _mode_holder:
		return
	_mode_shown = mode
	for c in _mode_holder.get_children():
		c.queue_free()
	var info = GameModes.info(mode)
	if header:
		header.set_title("PICK YOUR LANDING SPOT", String(info.name))
	_kicker("Mode", _mode_holder)
	var line = HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	_mode_holder.add_child(line)
	var gem = Panel.new()
	gem.custom_minimum_size = Vector2(14, 14)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem.add_theme_stylebox_override("panel", UITheme.glow_box(info.color, 0.6, 99, 6))
	line.add_child(gem)
	var name_lbl = UITheme.create_heading(String(info.name), line)
	name_lbl.add_theme_font_override("font", UITheme.font_black())
	name_lbl.add_theme_color_override("font_color", Color(info.color).lightened(0.3))
	name_lbl.uppercase = true
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var short = UITheme.create_label(String(info.short), _mode_holder, UITheme.FONT_TINY)
	short.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	short.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
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
		var rim = Color(UITheme.GOLD, 0.7) if is_me else Color(1, 1, 1, 0.1)
		var normal_box = UITheme.navy_box(UITheme.NAVY_HOVER if is_me else UITheme.NAVY, rim, 12, 10, 8)
		var hover_box = UITheme.navy_box(UITheme.NAVY_HOVER, Color(UITheme.GOLD, 0.95), 12, 10, 8)
		row.add_theme_stylebox_override("panel", normal_box)
		players_list.add_child(row)

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hbox)

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
		frame.add_theme_stylebox_override("panel", UITheme.glass_box(Color(accent, 0.18), Color(accent.lightened(0.3), 0.8), 10, 2, 2))
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(portrait)
		hbox.add_child(frame)
		if hero:
			var portrait_ref = weakref(portrait)  # the list is rebuilt with every lobby state
			ItemRenderer.get_instance(get_tree()).hero(hero.character_name, String(wear.get("skin", "")), String(wear.get("hat", "")),
				func(tex): if portrait_ref.get_ref(): portrait_ref.get_ref().texture = HeroChips._crop(tex, false))

		var names = VBoxContainer.new()
		names.add_theme_constant_override("separation", -2)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		names.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(names)
		var name_lbl = UITheme.create_label(data.get("name", tr("Player %d") % player_id), names, UITheme.FONT_SMALL)
		name_lbl.clip_text = true
		name_lbl.add_theme_font_override("font", UITheme.font_black())
		name_lbl.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		name_lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var hero_lbl = UITheme.create_label(hero.character_name if hero else "Choosing a hero...", names, UITheme.FONT_TINY)
		hero_lbl.clip_text = true
		hero_lbl.add_theme_color_override("font_color", hero.color.lightened(0.35) if hero else UITheme.TEXT_MUTED)

		var pill: Control = null
		if is_me:
			pill = UITheme.create_pill("You", UITheme.GOLD, hbox)
		elif player_id == 1:
			pill = UITheme.create_pill("Host", UITheme.ACCENT_INFO, hbox)
		if pill:
			pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pill.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Ready: a glowing mint dot, waiting: a dim one
		var dot = Panel.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var dot_box = StyleBoxFlat.new()
		dot_box.bg_color = UITheme.ACCENT_SUCCESS if player_ready else Color(1, 1, 1, 0.22)
		dot_box.set_corner_radius_all(99)
		if player_ready:
			dot_box.shadow_color = Color(UITheme.ACCENT_SUCCESS, 0.6)
			dot_box.shadow_size = 5
		dot.add_theme_stylebox_override("panel", dot_box)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(dot)

		if hero:
			row.mouse_default_cursor_shape = Control.CURSOR_HELP
			row.mouse_entered.connect(func():
				row.add_theme_stylebox_override("panel", hover_box)
				_show_hero_card(row, hero, wear, String(data.get("name", ""))))
			row.mouse_exited.connect(func():
				if is_instance_valid(row):
					row.add_theme_stylebox_override("panel", normal_box)
				_hide_hero_card())
			row.gui_input.connect(func(event):
				if event is InputEventMouseMotion and is_instance_valid(_hover_card):
					var p = event.position / row.size
					_hover_card._target = Vector2(p.x - 0.5, p.y - 0.5) * 2.0)

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
	at.y = clamp(at.y, ScreenHeader.CONTENT_TOP, size.y - card.card_size.y - 20.0)
	card.position = at
	card.modulate.a = 0.0
	card.create_tween().tween_property(card, "modulate:a", 1.0, 0.12)
	var card_ref = weakref(card)  # gone again if the mouse moved on before the picture
	ItemRenderer.get_instance(get_tree()).hero(hero.character_name, skin, hat, func(tex): if card_ref.get_ref(): card_ref.get_ref().set_art(tex))
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
