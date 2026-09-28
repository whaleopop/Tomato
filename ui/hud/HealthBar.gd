## Health card (top-left): character name, glowing HP bar and numbers
extends GlassPanel
class_name HealthBar

var health_bar: ProgressBar = null
var health_label: Label = null
var name_label: Label = null
var damage_bar: ProgressBar = null  # Trailing "recent damage" bar
var shield_bar: ProgressBar = null  # Blue strip under the HP bar while a shield is up
var shield_label: Label = null

var health_component: HealthComponent = null
var _shown_percent: float = 1.0

func _init():
	super._init()
	padding = 16
	tint = UITheme.GLASS_TINT_HUD
	custom_minimum_size = Vector2(300, 0)

func _ready():
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var head = HBoxContainer.new()
	box.add_child(head)
	name_label = UITheme.create_heading("", head)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shield_label = UITheme.create_label("", head, UITheme.FONT_SMALL)
	shield_label.add_theme_font_override("font", UITheme.font_black())
	shield_label.add_theme_color_override("font_color", UITheme.ACCENT_INFO.lightened(0.2))
	shield_label.visible = false
	health_label = UITheme.create_label("100 / 100", head, UITheme.FONT_SMALL)
	health_label.add_theme_font_override("font", UITheme.font_black())
	health_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)

	# Two stacked bars: the white one lags behind to show the damage you just took
	var bars = Control.new()
	bars.custom_minimum_size = Vector2(0, 14)
	box.add_child(bars)

	damage_bar = UITheme.create_progress_bar(1.0, 1.0, Color(1, 1, 1, 0.55), bars)
	damage_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	health_bar = UITheme.create_progress_bar(1.0, 1.0, UITheme.ACCENT_SUCCESS, bars)
	health_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	health_bar.add_theme_stylebox_override("background", UITheme.empty_box())

	shield_bar = UITheme.create_progress_bar(HealthComponent.MAX_SHIELD, 0.0, UITheme.ACCENT_INFO, box)
	shield_bar.custom_minimum_size = Vector2(0, 6)
	shield_bar.visible = false

func setup(p_health_component: HealthComponent):
	health_component = p_health_component
	if health_component:
		health_component.health_changed.connect(_on_health_changed)
		health_component.shield_changed.connect(func(_s): _update_shield())
		_update_health()
		_update_shield()
		var player = health_component.entity
		if player and player.get("character_data"):
			name_label.text = player.character_data.character_name
			name_label.add_theme_color_override("font_color", player.character_data.color.lightened(0.35))
		else:
			name_label.text = "You"

func _process(delta: float):
	if damage_bar and health_bar:
		damage_bar.value = move_toward(damage_bar.value, health_bar.value, delta * 0.6)

func _on_health_changed(_current: float, _max_health: float):
	_update_health()

func _update_health():
	if not health_component or not health_bar:
		return

	var percent = health_component.get_health_percent()
	if percent < _shown_percent:
		_flash()
	_shown_percent = percent
	health_bar.value = percent
	if damage_bar.value < percent:
		damage_bar.value = percent

	var color = UITheme.ACCENT_SUCCESS
	if percent < 0.3:
		color = UITheme.ACCENT_DANGER
	elif percent < 0.6:
		color = UITheme.ACCENT_WARNING
	UITheme.set_bar_color(health_bar, color)

	health_label.text = "%d / %d" % [int(ceil(health_component.current_health)), int(health_component.max_health)]

func _update_shield():
	if not health_component or not shield_bar:
		return
	var value = health_component.shield
	shield_bar.visible = value > 0.0
	shield_label.visible = value > 0.0
	shield_bar.value = value
	shield_label.text = "+%d" % int(ceil(value))

func _flash():
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1.4, 0.8, 0.8), 0.06)
	tween.tween_property(self, "modulate", Color.WHITE, 0.25)
