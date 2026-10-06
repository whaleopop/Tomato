## The settings card, used by the main menu, ScreenHeader.open_settings (over the other screens) and
## the pause menu. The main menu's look: a navy panel, a gold kicker over the title, section tabs
## (AUDIO / VIDEO / CONTROLS, the last one is remembered), the template's rows - a title with a
## caption on the left, the slider / switch / choice on the right, a gold rim under the mouse - and
## a close chip + the gold DONE. CONTROLS lists every Keybinds.ACTIONS entry as a tile with its key:
## click the key, press the new one (Esc cancels).
extends GlassPanel
class_name SettingsPanel

signal closed
signal language_changed  # formatted texts are built once: the owner may want to rebuild

const WIDTH: int = 720
const ROW_HEIGHT: int = 56
const TABS = ["Audio", "Video", "Controls"]
const KEY_CHIP := Vector2(136, 36)

static var _last_tab: int = 0             # the tab it opens on

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _pages_holder: Control
var _footer_hint: Label
var _reset_button: Button
var _language_chips: Dictionary = {}      # language code -> Button
var _scale_chips: Dictionary = {}         # preset -> Button
var _key_buttons: Dictionary = {}         # action -> Button
var _listening: String = ""               # the action waiting for a key

func _init():
	super()  # GlassPanel builds its layers there (an own _init replaces it otherwise)
	# Before the owner's own changes (the pause menu sets its darker tint after new())
	tint = Color(0.045, 0.06, 0.11, 0.95)
	rim_color = Color(1, 1, 1, 0.12)
	corner_radius = 18

func _ready():
	padding = 26
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	# The title, a gold kicker over it, and the close chip
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	var titles = VBoxContainer.new()
	titles.add_theme_constant_override("separation", -4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(titles)
	_kicker("Sound · picture · controls", titles)
	var title = UITheme.create_heading("SETTINGS", titles)
	title.uppercase = true
	title.add_theme_font_override("font", UITheme.font_black())
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 2)
	var close_chip = UITheme.create_icon_chip("✕", top)
	close_chip.tooltip_text = "Close"
	close_chip.pressed.connect(close)

	# The sections: navy chips, the open one lit with a gold line
	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	for i in TABS.size():
		var tab = UITheme.create_tab("", tabs)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # set translated + uppercased
		tab.pressed.connect(_show_tab.bind(i))
		_tab_buttons.append(tab)
	_retitle_tabs()

	# The pages, one at a time in the same place (the card keeps its size between tabs)
	_pages_holder = Control.new()
	_pages_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_pages_holder)
	for builder in [_build_audio, _build_video, _build_controls]:
		var page = ScrollContainer.new()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_pages_holder.add_child(page)
		# The controls scroll: their tiles keep clear of the scroll bar
		var margin = MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_right", 14 if builder == _build_controls else 0)
		page.add_child(margin)
		var box = VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 10)
		margin.add_child(box)
		builder.call(box)
		_pages.append(page)

	UITheme.create_separator(root)
	var footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	_reset_button = UITheme.create_button("RESET TO DEFAULTS", footer, Vector2(0, 48))
	_reset_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reset_button.pressed.connect(func():
		_stop_listening()
		Keybinds.reset_all()
		GameSettings.save()
		_refresh_keys())
	_footer_hint = UITheme.create_label("", footer, UITheme.FONT_SMALL)
	_footer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer_hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	var done = UITheme.create_primary_button("DONE", footer, Vector2(170, 52))
	done.pressed.connect(close)

	_fit_to_screen()
	get_viewport().size_changed.connect(_fit_to_screen)  # fullscreen on / off resizes the window
	_show_tab(clampi(_last_tab, 0, TABS.size() - 1))
	_refresh_keys()

## As wide as the template's cards, as tall as the window allows (720p keeps a margin)
func _fit_to_screen() -> void:
	if not is_inside_tree():
		return
	var screen = get_viewport_rect().size
	custom_minimum_size.x = min(WIDTH, screen.x - 48.0)
	_pages_holder.custom_minimum_size.y = clamp(screen.y - 330.0, 240.0, 380.0)

# ---------------------------------------------------------------- tabs

func _show_tab(index: int) -> void:
	_stop_listening()
	_last_tab = index
	for i in _tab_buttons.size():
		UITheme.set_tab_active(_tab_buttons[i], i == index)
		_pages[i].visible = i == index
	_pages[index].scroll_vertical = 0
	var controls = TABS[index] == "Controls"
	_reset_button.visible = controls
	_footer_hint.text = "You hear each sound when you let go of its slider" if TABS[index] == "Audio" else ""

## Button texts can't uppercase a translation on their own: translated here (again after a
## language change)
func _retitle_tabs() -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].text = tr(TABS[i]).to_upper()

# ---------------------------------------------------------------- pages

func _build_audio(box: VBoxContainer) -> void:
	_volume_row("Master volume", "Every sound of the game", GameSettings.master_volume, func(v): GameSettings.master_volume = v, box, "gun_pistol", "SFX")
	_volume_row("Effects", "Shots, blasts, loot", GameSettings.sfx_volume, func(v): GameSettings.sfx_volume = v, box, "gun_pistol", "SFX")
	_volume_row("Interface", "Menus, countdown, results", GameSettings.ui_volume, func(v): GameSettings.ui_volume = v, box, "ui_click", "UI")
	_volume_row("Ambience", "Wind, water, birds", GameSettings.ambient_volume, func(v): GameSettings.ambient_volume = v, box)

func _build_video(box: VBoxContainer) -> void:
	_kicker("Video", box)
	var fullscreen = _switch_row("Fullscreen", "", GameSettings.fullscreen, box)
	fullscreen.toggled.connect(func(on):
		GameSettings.fullscreen = on
		GameSettings.apply())
	var vsync = _switch_row("VSync", "Locks the frame rate to the screen", GameSettings.vsync, box)
	vsync.toggled.connect(func(on):
		GameSettings.vsync = on
		GameSettings.apply())
	var juice = _switch_row("Juice splatter", "Juice sprays, stains and footprints when someone is hit", GameSettings.juice_splatter, box)
	juice.toggled.connect(func(on):
		GameSettings.juice_splatter = on
		GameSettings.save())
	UITheme.create_spacer(false, box).custom_minimum_size.y = 4
	_kicker("Interface", box)
	# The languages side by side, each written in its own language
	var row = _row("Language", "", box)
	var chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chips)
	for code in Locale.LANGUAGES:
		var chip = UITheme.create_tab(Locale.LANGUAGES[code], chips, Vector2(120, 40))
		chip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # names in their own language
		chip.pressed.connect(_set_language.bind(code))
		_language_chips[code] = chip
	_mark_language()
	var srow = _row("UI scale", "Size of menus and the HUD", box)
	var schips = HBoxContainer.new()
	schips.add_theme_constant_override("separation", 6)
	schips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(schips)
	for p in UIScale.PRESETS:
		var sc = UITheme.create_tab("%d%%" % roundi(p * 100.0), schips, Vector2(72, 40))
		sc.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		sc.pressed.connect(_set_ui_scale.bind(p))
		_scale_chips[p] = sc
	_mark_scale()

func _build_controls(box: VBoxContainer) -> void:
	_kicker("Camera", box)
	var lock = _switch_row("Camera turns with the hero (mouse turns)", "", GameSettings.camera_locked, box)
	lock.toggled.connect(func(on):
		GameSettings.camera_locked = on
		GameSettings.save()
		var cam = get_viewport().get_camera_3d()
		if cam is CameraController:
			cam.set_locked(on))
	UITheme.create_spacer(false, box).custom_minimum_size.y = 4
	var keys_head = HBoxContainer.new()
	keys_head.add_theme_constant_override("separation", 12)
	box.add_child(keys_head)
	_kicker("Keys", keys_head)
	var hint = UITheme.create_label("Click a key, then press the new one (Esc cancels)", keys_head, UITheme.FONT_SMALL)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	# Two columns of tiles: what it does, its key
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for entry in Keybinds.ACTIONS:
		var action: String = entry[0]
		if not InputMap.has_action(action):
			continue
		var tile = _tile(grid, 14, 6)
		tile.custom_minimum_size.y = 50
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var line = HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		tile.add_child(line)
		var name_label = UITheme.create_label(entry[1], line, UITheme.FONT_SMALL)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_override("font", UITheme.font_bold())
		name_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		var button = UITheme.create_button("", line, KEY_CHIP)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # key names as they are
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(_listen.bind(action))
		_key_buttons[action] = button

# ---------------------------------------------------------------- rows

## A small gold uppercase line over a group of rows ("VIDEO", "KEYS")
func _kicker(text: String, parent: Control) -> Label:
	var label = UITheme.create_label(text, parent, 12)
	label.uppercase = true
	label.add_theme_font_override("font", UITheme.font_black())
	label.add_theme_color_override("font_color", UITheme.GOLD)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## A navy tile with a thin rim; under the mouse the rim turns gold (the main menu's rows)
func _tile(parent: Control, margin_h: float = 18, margin_v: float = 8) -> PanelContainer:
	var tile = PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var normal = UITheme.navy_box(UITheme.NAVY, Color(1, 1, 1, 0.08), 12, margin_h, margin_v)
	normal.shadow_size = 0  # rows inside a card: one shadow is the card's
	var hover = UITheme.navy_box(UITheme.NAVY_HOVER, Color(UITheme.GOLD, 0.7), 12, margin_h, margin_v)
	hover.shadow_size = 0
	tile.add_theme_stylebox_override("panel", normal)
	tile.mouse_entered.connect(func(): tile.add_theme_stylebox_override("panel", hover))
	tile.mouse_exited.connect(func(): tile.add_theme_stylebox_override("panel", normal))
	parent.add_child(tile)
	return tile

## A template row: the title (uppercase, a muted caption under it) on the left; the caller puts
## its control on the right of the returned box
func _row(title: String, caption: String, parent: Control) -> HBoxContainer:
	var tile = _tile(parent)
	tile.custom_minimum_size.y = ROW_HEIGHT
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	tile.add_child(row)
	var texts = VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var head = UITheme.create_heading(title, texts)
	head.uppercase = true
	head.add_theme_font_override("font", UITheme.font_black())
	head.add_theme_font_size_override("font_size", 15)
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if caption != "":
		var sub = UITheme.create_label(caption, texts, 11)
		sub.uppercase = true
		sub.add_theme_font_override("font", UITheme.font_bold())
		sub.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row

## A row with a gold switch on the right; a click anywhere on the row flips it
func _switch_row(title: String, caption: String, on: bool, parent: Control) -> Button:
	var row = _row(title, caption, parent)
	var switch = _Switch.new(on)
	row.add_child(switch)
	var tile: Control = row.get_parent()
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Sfx.ui("ui_click")
			switch.button_pressed = not switch.button_pressed  # emits toggled
			tile.accept_event())
	return switch

## A volume row: name, slider, percent -> `store` (a GameSettings volume); `sample` plays on `bus`
## when you let go, so you hear what you set
func _volume_row(title: String, caption: String, value: float, store: Callable, box: Control, sample: String = "", bus: String = "UI") -> void:
	var row = _row(title, caption, box)
	var slider = UITheme.create_slider(0.0, 1.0, value, row)
	slider.custom_minimum_size = Vector2(250, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.scrollable = false  # the wheel scrolls the page, it doesn't change the volume
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var value_label = UITheme.create_heading("", row)
	value_label.custom_minimum_size.x = 56
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_label.add_theme_font_override("font", UITheme.font_black())
	value_label.add_theme_font_size_override("font_size", 17)
	value_label.add_theme_color_override("font_color", UITheme.GOLD)
	value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var show = func(v: float):
		store.call(v)
		GameSettings.apply()
		value_label.text = "%d%%" % int(round(v * 100.0))
	slider.value_changed.connect(show)
	if sample != "":
		slider.drag_ended.connect(func(_changed): Sfx.ui(sample, 0.0, 1.0, bus))
	show.call(value)

# ---------------------------------------------------------------- language

func _set_language(code: String) -> void:
	if code == GameSettings.language:
		return
	GameSettings.language = code
	Locale.setup(GameSettings.language)
	GameSettings.save()
	_mark_language()
	_retitle_tabs()
	_refresh_keys()  # LMB / RMB are translated
	language_changed.emit()

func _set_ui_scale(p: float) -> void:
	GameSettings.ui_scale = p
	UIScale.apply(get_tree().root)
	GameSettings.save()
	_mark_scale()

func _mark_scale() -> void:
	for p in _scale_chips:
		UITheme.set_tab_active(_scale_chips[p], is_equal_approx(p, GameSettings.ui_scale))

func _mark_language() -> void:
	for code in _language_chips:
		UITheme.set_tab_active(_language_chips[code], code == GameSettings.language)

# ---------------------------------------------------------------- controls

func _refresh_keys():
	for action in _key_buttons:
		var b: Button = _key_buttons[action]
		b.text = Keybinds.label(action)
		_style_key(b, false, not Keybinds.is_default(action))

## A key chip: navy with the key in white (gold when it was rebound), all gold while it waits
func _style_key(b: Button, listening: bool, custom: bool = false) -> void:
	var fill = UITheme.GOLD if listening else Color(0.03, 0.04, 0.08, 0.95)
	var rim = UITheme.GOLD.lightened(0.3) if listening else (Color(UITheme.GOLD, 0.55) if custom else Color(1, 1, 1, 0.18))
	var normal = UITheme.navy_box(fill, rim, 10, 8, 4)
	normal.shadow_size = 0
	if listening:
		normal.shadow_color = Color(UITheme.GOLD, 0.45)
		normal.shadow_size = 10
		normal.shadow_offset = Vector2.ZERO
	var hover = normal.duplicate() if listening else UITheme.navy_box(UITheme.NAVY_HOVER, Color(UITheme.GOLD, 0.9), 10, 8, 4)
	if not listening:
		hover.shadow_size = 0
	for state in ["normal", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, normal)
	for state in ["hover", "hover_pressed"]:
		b.add_theme_stylebox_override(state, hover)
	var text_color = Color(0.10, 0.06, 0.0) if listening else (UITheme.GOLD if custom else Color.WHITE)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, text_color)
	b.add_theme_font_override("font", UITheme.font_bold() if listening else UITheme.font_black())
	b.add_theme_font_size_override("font_size", 12 if listening else 15)

func _listen(action: String):
	_stop_listening()
	_listening = action
	var b: Button = _key_buttons[action]
	b.text = tr("Press a key...")
	_style_key(b, true)

func _stop_listening():
	if _listening != "":
		_listening = ""
		_refresh_keys()

## The next key or mouse button goes to the action being changed (before the game or the pause
## menu can see it)
func _input(event: InputEvent):
	if _listening == "" or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_stop_listening()
		get_viewport().set_input_as_handled()
		return
	if not Keybinds.accepts(event):
		return
	# A click on one of the key buttons picks that row instead (no accidental "LMB")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		for b in _key_buttons.values():
			if b.get_global_rect().has_point(event.position):
				_stop_listening()
				return
	Keybinds.bind(_listening, Keybinds.clean(event))
	_listening = ""
	GameSettings.save()
	_refresh_keys()
	get_viewport().set_input_as_handled()

func close():
	_stop_listening()
	GameSettings.save()
	closed.emit()

## The template's toggle: a pill that slides gold when on (a toggle Button, `toggled` as usual)
class _Switch extends Button:
	var _t: float = 0.0

	func _init(on: bool):
		toggle_mode = true
		button_pressed = on
		_t = 1.0 if on else 0.0
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(56, 30)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		pressed.connect(func(): Sfx.ui("ui_click"))
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _process(delta: float):
		var want = 1.0 if button_pressed else 0.0
		if not is_equal_approx(_t, want):
			_t = move_toward(_t, want, delta * 7.0)
			queue_redraw()

	func _draw():
		var k = smoothstep(0.0, 1.0, _t)
		var r = size.y / 2.0
		var track = StyleBoxFlat.new()
		track.bg_color = Color(0.0, 0.0, 0.0, 0.45).lerp(UITheme.GOLD, k)
		track.set_corner_radius_all(int(r))
		track.set_border_width_all(1)
		track.border_color = Color(1, 1, 1, 0.22).lerp(UITheme.GOLD.lightened(0.35), k)
		if is_hovered():
			track.border_color = Color(UITheme.GOLD, 0.9)
		track.anti_aliasing = true
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		var knob = Vector2(lerp(r, size.x - r, k), r)
		draw_circle(knob + Vector2(0, 1.5), r - 4.0, Color(0, 0, 0, 0.25), true, -1.0, true)
		draw_circle(knob, r - 4.0, Color(0.96, 0.97, 1.0).lerp(Color(0.12, 0.08, 0.0), k), true, -1.0, true)
