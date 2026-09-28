## Glass settings card, used by the main menu and the pause menu
extends GlassPanel
class_name SettingsPanel

signal closed
signal language_changed  # formatted texts are built once: the owner may want to rebuild

var _volume_value: Label

func _ready():
	padding = 28
	custom_minimum_size = Vector2(420, 0)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	add_child(box)

	UITheme.create_title("SETTINGS", box)
	UITheme.create_separator(box)

	# Volume
	UITheme.create_caption("Audio", box)
	var volume_row = UITheme.create_setting_row("Master volume", box)
	_volume_value = UITheme.create_label("", volume_row, UITheme.FONT_SMALL)
	var volume = UITheme.create_slider(0.0, 1.0, GameSettings.master_volume, box)
	volume.value_changed.connect(_on_volume_changed)
	_on_volume_changed(GameSettings.master_volume)

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

	UITheme.create_spacer(false, box).custom_minimum_size.y = 8

	var back = UITheme.create_primary_button("DONE", box, Vector2(0, 52))
	back.pressed.connect(close)

func _on_volume_changed(value: float):
	GameSettings.master_volume = value
	GameSettings.apply()
	if _volume_value:
		_volume_value.text = "%d%%" % int(round(value * 100.0))

func close():
	GameSettings.save()
	closed.emit()
