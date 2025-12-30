## Pause menu
extends Control
class_name PauseMenu

@onready var resume_button: Button = $VBoxContainer/ResumeButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton

var is_paused: bool = false
var settings_panel: Control = null

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS  # Continue processing when paused
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func _input(event: InputEvent):
	if event.is_action_pressed("pause"):
		if settings_panel and settings_panel.visible:
			_hide_settings()
		else:
			toggle_pause()

func toggle_pause():
	is_paused = not is_paused
	visible = is_paused
	get_tree().paused = is_paused

func _on_resume_pressed():
	toggle_pause()

func _on_settings_pressed():
	if settings_panel == null:
		_create_settings_panel()
	settings_panel.visible = true

func _hide_settings():
	if settings_panel:
		settings_panel.visible = false

func _create_settings_panel():
	settings_panel = PanelContainer.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.custom_minimum_size = Vector2(300, 250)
	settings_panel.set_anchors_preset(Control.PRESET_CENTER)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	settings_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Master Volume
	var volume_label = Label.new()
	volume_label.text = "Master Volume"
	vbox.add_child(volume_label)

	var volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.value = 1.0
	volume_slider.step = 0.05
	volume_slider.custom_minimum_size = Vector2(250, 20)
	volume_slider.value_changed.connect(_on_volume_changed)
	vbox.add_child(volume_slider)

	# Fullscreen toggle
	var fullscreen_check = CheckButton.new()
	fullscreen_check.text = "Fullscreen"
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vbox.add_child(fullscreen_check)

	# Mouse sensitivity
	var sens_label = Label.new()
	sens_label.text = "Mouse Sensitivity"
	vbox.add_child(sens_label)

	var sens_slider = HSlider.new()
	sens_slider.min_value = 0.1
	sens_slider.max_value = 2.0
	sens_slider.value = 1.0
	sens_slider.step = 0.1
	sens_slider.custom_minimum_size = Vector2(250, 20)
	vbox.add_child(sens_slider)

	# Back button
	var back_button = Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(_hide_settings)
	vbox.add_child(back_button)

	add_child(settings_panel)

func _on_volume_changed(value: float):
	AudioServer.set_bus_volume_db(0, linear_to_db(value))

func _on_fullscreen_toggled(pressed: bool):
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_quit_pressed():
	get_tree().quit()

