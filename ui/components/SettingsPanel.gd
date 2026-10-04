## Glass settings card, used by the main menu and the pause menu
extends GlassPanel
class_name SettingsPanel

signal closed
signal language_changed  # formatted texts are built once: the owner may want to rebuild

var _main_box: VBoxContainer = null
var _keys_box: VBoxContainer = null       # Controls: one row per Keybinds.ACTIONS entry
var _key_buttons: Dictionary = {}         # action -> Button
var _listening: String = ""               # the action waiting for a key

func _ready():
	padding = 28
	custom_minimum_size = Vector2(420, 0)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	add_child(box)
	_main_box = box

	UITheme.create_title("SETTINGS", box)
	UITheme.create_separator(box)

	# Volume
	UITheme.create_caption("Audio", box)
	_volume_slider("Master volume", GameSettings.master_volume, func(v): GameSettings.master_volume = v, box, "gun_pistol", "SFX")
	_volume_slider("Effects", GameSettings.sfx_volume, func(v): GameSettings.sfx_volume = v, box, "gun_pistol", "SFX")
	_volume_slider("Interface", GameSettings.ui_volume, func(v): GameSettings.ui_volume = v, box, "ui_click", "UI")
	_volume_slider("Ambience", GameSettings.ambient_volume, func(v): GameSettings.ambient_volume = v, box)

	# Video
	UITheme.create_caption("Video", box)
	var fullscreen = UITheme.create_checkbox("Fullscreen", GameSettings.fullscreen, box)
	fullscreen.toggled.connect(func(on):
		GameSettings.fullscreen = on
		GameSettings.apply())
	var vsync = UITheme.create_checkbox("VSync", GameSettings.vsync, box)
	vsync.toggled.connect(func(on):
		GameSettings.vsync = on
		GameSettings.apply())

	# Interface
	UITheme.create_caption("Interface", box)
	var language_row = UITheme.create_setting_row("Language", box)
	var language = OptionButton.new()
	language.focus_mode = Control.FOCUS_NONE
	language.custom_minimum_size = Vector2(170, 40)
	language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # names in their own language
	var codes = Locale.LANGUAGES.keys()
	for i in codes.size():
		language.add_item(Locale.LANGUAGES[codes[i]], i)
		if codes[i] == GameSettings.language:
			language.select(i)
	language_row.add_child(language)
	language.item_selected.connect(func(index):
		GameSettings.language = codes[index]
		Locale.setup(GameSettings.language)
		GameSettings.save()
		language_changed.emit())

	# Controls: rebind the keys
	UITheme.create_caption("Controls", box)
	var lock = UITheme.create_checkbox("Camera turns with the hero (mouse turns)", GameSettings.camera_locked, box)
	lock.toggled.connect(func(on):
		GameSettings.camera_locked = on
		GameSettings.save()
		var cam = get_viewport().get_camera_3d()
		if cam is CameraController:
			cam.set_locked(on))
	var controls = UITheme.create_button("CHANGE CONTROLS", box, Vector2(0, 46))
	controls.pressed.connect(_show_keys)

	UITheme.create_spacer(false, box).custom_minimum_size.y = 8

	var back = UITheme.create_primary_button("DONE", box, Vector2(0, 52))
	back.pressed.connect(close)

# ---------------------------------------------------------------- controls

func _show_keys():
	if _keys_box == null:
		_build_keys()
	_main_box.visible = false
	_keys_box.visible = true
	_refresh_keys()

func _hide_keys():
	_stop_listening()
	GameSettings.save()
	_keys_box.visible = false
	_main_box.visible = true

func _build_keys():
	_keys_box = VBoxContainer.new()
	_keys_box.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	add_child(_keys_box)
	UITheme.create_title("CONTROLS", _keys_box)
	var hint = UITheme.create_label("Click a key, then press the new one (Esc cancels)", _keys_box, UITheme.FONT_SMALL)
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.create_separator(_keys_box)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_keys_box.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for entry in Keybinds.ACTIONS:
		var action: String = entry[0]
		if not InputMap.has_action(action):
			continue
		var name_label = UITheme.create_label(entry[1], grid, UITheme.FONT_SMALL)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var button = UITheme.create_button("", grid, Vector2(140, 40))
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # key names as they are
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_listen.bind(action))
		_key_buttons[action] = button

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_keys_box.add_child(row)
	var reset = UITheme.create_button("RESET TO DEFAULTS", row, Vector2(0, 48))
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func():
		_stop_listening()
		Keybinds.reset_all()
		GameSettings.save()
		_refresh_keys())
	var done = UITheme.create_primary_button("BACK", row, Vector2(140, 48))
	done.pressed.connect(_hide_keys)

func _refresh_keys():
	for action in _key_buttons:
		var b: Button = _key_buttons[action]
		b.text = Keybinds.label(action)
		UITheme.style_selectable(b, false)

func _listen(action: String):
	_stop_listening()
	_listening = action
	var b: Button = _key_buttons[action]
	b.text = tr("Press a key...")
	UITheme.style_selectable(b, true)

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

## A volume row: name, percent, slider -> `store` (a GameSettings volume); `sample` plays on `bus`
## when you let go, so you hear what you set
func _volume_slider(title: String, value: float, store: Callable, box: Control, sample: String = "", bus: String = "UI") -> void:
	var row = UITheme.create_setting_row(title, box)
	var value_label = UITheme.create_label("", row, UITheme.FONT_SMALL)
	var slider = UITheme.create_slider(0.0, 1.0, value, box)
	var show = func(v: float):
		store.call(v)
		GameSettings.apply()
		value_label.text = "%d%%" % int(round(v * 100.0))
	slider.value_changed.connect(show)
	if sample != "":
		slider.drag_ended.connect(func(_changed): Sfx.ui(sample, 0.0, 1.0, bus))
	show.call(value)

func close():
	GameSettings.save()
	closed.emit()
