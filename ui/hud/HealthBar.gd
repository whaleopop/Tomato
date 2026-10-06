## Vitals card (bottom-left): hero portrait with a rim in the hero's color, name, a big HP number,
## a segmented shield bar over the HP bar (with the trailing "recent damage" bar) and the
## heal / shield chips (ConsumableBar goes into `chips_holder`). Under 30% HP the bar and the
## number turn red, one punch when crossing.
extends GlassPanel
class_name HealthBar

signal percent_changed(percent: float)

const LOW_PERCENT: float = 0.3
const SHIELD_SEGMENT: float = 25.0

var health_bar: ProgressBar = null
var health_label: Label = null
var max_label: Label = null
var name_label: Label = null
var damage_bar: ProgressBar = null  # Trailing "recent damage" bar
var shield_bar: SegmentBar = null   # Blue segments over the HP bar while a shield is up
var shield_label: Label = null
var chips_holder: Control = null    # PlayerHUD puts the ConsumableBar here
var portrait_rim: PanelContainer = null
var portrait: TextureRect = null

var health_component: HealthComponent = null
var _shown_percent: float = 1.0
var _low: bool = false

func _init():
	super._init()
	padding = 12
	corner_radius = UITheme.CORNER_RADIUS_SMALL
	show_shadow = false
	tint = UITheme.GLASS_TINT_HUD
	custom_minimum_size = Vector2(400, 0)

func _ready():
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	portrait_rim = PanelContainer.new()
	portrait_rim.custom_minimum_size = Vector2(88, 88)
	portrait_rim.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait_rim.clip_contents = true
	portrait_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rim(Color(1, 1, 1, 0.3))
	row.add_child(portrait_rim)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_rim.add_child(portrait)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)

	name_label = UITheme.create_label("", box, UITheme.FONT_NORMAL)
	name_label.add_theme_font_override("font", UITheme.font_black())
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var numbers = HBoxContainer.new()
	numbers.add_theme_constant_override("separation", 6)
	box.add_child(numbers)
	health_label = UITheme.create_label("100", numbers, UITheme.FONT_TITLE)
	health_label.add_theme_font_override("font", UITheme.font_black())
	health_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	health_label.pivot_offset = Vector2(20, 18)
	max_label = UITheme.create_label("/ 100", numbers, UITheme.FONT_SMALL)
	max_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	max_label.size_flags_vertical = Control.SIZE_SHRINK_END
	shield_label = UITheme.create_label("", numbers, UITheme.FONT_SMALL)
	shield_label.add_theme_font_override("font", UITheme.font_black())
	shield_label.add_theme_color_override("font_color", UITheme.ACCENT_INFO.lightened(0.2))
	shield_label.size_flags_vertical = Control.SIZE_SHRINK_END
	shield_label.visible = false
	chips_holder = Control.new()
	chips_holder.custom_minimum_size = Vector2(184, 34)
	chips_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL | Control.SIZE_SHRINK_END
	chips_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	numbers.add_child(chips_holder)

	shield_bar = SegmentBar.new()
	shield_bar.max_value = HealthComponent.MAX_SHIELD
	shield_bar.segment = SHIELD_SEGMENT
	shield_bar.color = UITheme.ACCENT_INFO
	shield_bar.custom_minimum_size = Vector2(0, 10)
	shield_bar.modulate.a = 0.0  # keeps its place so the HP bar doesn't jump
	box.add_child(shield_bar)

	# Two stacked bars: the white one lags behind to show the damage you just took
	var bars = Control.new()
	bars.custom_minimum_size = Vector2(0, 18)
	box.add_child(bars)

	damage_bar = UITheme.create_progress_bar(1.0, 1.0, Color(1, 1, 1, 0.55), bars)
	damage_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	health_bar = UITheme.create_progress_bar(1.0, 1.0, UITheme.ACCENT_SUCCESS, bars)
	health_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	health_bar.add_theme_stylebox_override("background", UITheme.empty_box())

func _set_rim(color: Color) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = color
	sb.anti_aliasing = true
	portrait_rim.add_theme_stylebox_override("panel", sb)

func setup(p_health_component: HealthComponent):
	health_component = p_health_component
	if health_component:
		health_component.health_changed.connect(_on_health_changed)
		health_component.shield_changed.connect(func(_s): _update_shield())
		_update_health()
		_update_shield()
		var player = health_component.entity
		if player and player.get("character_data"):
			var data = player.character_data
			name_label.text = tr(data.character_name)
			name_label.add_theme_color_override("font_color", data.color.lightened(0.35))
			_set_rim(data.color)
			var wear = PlayerProfile.equipped_for(data.character_name)
			var ref = weakref(portrait)
			ItemRenderer.get_instance(get_tree()).hero(data.character_name, wear.skin, wear.hat, func(tex):
				var p = ref.get_ref()
				if p:
					p.texture = HeroChips._crop(tex, false))
		else:
			name_label.text = tr("You")

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

	var low = percent < LOW_PERCENT
	var color = UITheme.ACCENT_DANGER if low else (UITheme.ACCENT_WARNING if percent < 0.6 else UITheme.ACCENT_SUCCESS)
	UITheme.set_bar_color(health_bar, color)
	health_label.add_theme_color_override("font_color", UITheme.ACCENT_DANGER if low else UITheme.TEXT_PRIMARY)
	if low and not _low and health_component.current_health > 0.0:
		_punch()
	_low = low

	health_label.text = str(int(ceil(health_component.current_health)))
	max_label.text = "/ %d" % int(health_component.max_health)
	percent_changed.emit(percent)

func _update_shield():
	if not health_component or not shield_bar:
		return
	var value = health_component.shield
	shield_bar.modulate.a = 1.0 if value > 0.0 else 0.0
	shield_label.visible = value > 0.0
	shield_bar.value = value
	shield_label.text = "+%d" % int(ceil(value))

func _flash():
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1.4, 0.8, 0.8), 0.06)
	tween.tween_property(self, "modulate", Color.WHITE, 0.25)

## One punch on the number when HP drops under the line
func _punch():
	var tween = create_tween()
	tween.tween_property(health_label, "scale", Vector2(1.35, 1.35), 0.08)
	tween.tween_property(health_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A bar cut into segments of `segment` units (the last one is shorter)
class SegmentBar extends Control:
	var max_value: float = 60.0
	var value: float = 0.0:
		set(v):
			value = v
			queue_redraw()
	var segment: float = 25.0
	var color: Color = Color.WHITE

	func _init():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw():
		var gap = 3.0
		var count = int(ceil(max_value / segment))
		var usable = size.x - gap * (count - 1)
		var x = 0.0
		for i in count:
			var from = i * segment
			var units = minf(segment, max_value - from)
			var w = usable * units / max_value
			var rect = Rect2(x, 0, w, size.y)
			draw_rect(rect, Color(1, 1, 1, 0.1))
			var fill = clampf((value - from) / units, 0.0, 1.0)
			if fill > 0.0:
				draw_rect(Rect2(x, 0, w * fill, size.y), color)
			x += w + gap
