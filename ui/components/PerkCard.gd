## Weed Swarm pick (ModeView): a double holographic card - the buff on top, "BUT" across the
## middle, the debuff under it (SwarmPerks). Drawn in its own SubViewport like ParallaxCard and
## shown through shaders/holo_card.gdshader: it tilts towards the mouse, the foil shimmers, and
## it materialises with a scan line when it appears.
extends Control
class_name PerkCard

signal pressed

const CARD_SIZE := Vector2(290, 440)
const MAX_TILT: float = 0.32
const OVERSCAN: float = 0.35
const RADIUS: float = 40.0        # px of the 2x picture

var buff: String = ""
var debuff: String = ""
var hotkey: String = ""
var delay: float = 0.0            # before it materialises

var _material: ShaderMaterial
var _hover: bool = false
var _target := Vector2.ZERO
var _tilt := Vector2.ZERO
var _lift: float = 0.0
var _appear: float = 0.0

func _ready():
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var viewport = SubViewport.new()
	viewport.size = Vector2i(CARD_SIZE * 2.0)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var root = Control.new()
	root.size = CARD_SIZE * 2.0
	viewport.add_child(root)
	_build(root, CARD_SIZE * 2.0)

	var view = TextureRect.new()
	view.texture = viewport.get_texture()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var extra = CARD_SIZE * OVERSCAN * 0.5
	view.offset_left = -extra.x
	view.offset_top = -extra.y
	view.offset_right = extra.x
	view.offset_bottom = extra.y
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/holo_card.gdshader")
	_material.set_shader_parameter("aspect", CARD_SIZE.x / CARD_SIZE.y)
	_material.set_shader_parameter("inset", 1.0 + OVERSCAN)
	_material.set_shader_parameter("corner", RADIUS / CARD_SIZE.y)
	_material.set_shader_parameter("rim_color", Color(0.65, 0.9, 1.0))
	_material.set_shader_parameter("appear", 0.0)
	view.material = _material
	add_child(view)
	mouse_entered.connect(func():
		_hover = true
		z_index = 10)
	mouse_exited.connect(func():
		_hover = false
		_target = Vector2.ZERO
		z_index = 0)

func _build(root: Control, s: Vector2) -> void:
	var back = Panel.new()
	var back_box = StyleBoxFlat.new()
	back_box.bg_color = Color(0.04, 0.06, 0.11)
	back_box.set_corner_radius_all(int(RADIUS))
	back.add_theme_stylebox_override("panel", back_box)
	back.size = s
	root.add_child(back)
	var half = s.y * 0.5
	_half(root, buff, Rect2(0, 0, s.x, half - 6), true)
	_half(root, debuff, Rect2(0, half + 6, s.x, half - 6), false)
	# "BUT" across the middle
	var line = ColorRect.new()
	line.color = Color(1.0, 0.85, 0.35, 0.8)
	line.position = Vector2(30, half - 2)
	line.size = Vector2(s.x - 60, 4)
	root.add_child(line)
	var pill = PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.08, 0.07, 0.03, 1.0), Color(1.0, 0.85, 0.35, 0.95), 99, 26, 4))
	root.add_child(pill)
	var but = UITheme.create_heading(tr("BUT").to_upper(), pill)
	but.add_theme_font_size_override("font_size", 32)
	but.add_theme_font_override("font", UITheme.font_black())
	but.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	pill.reset_size()
	pill.position = Vector2((s.x - pill.size.x) * 0.5, half - pill.size.y * 0.5)
	# The key that picks it
	if hotkey != "":
		var key = PanelContainer.new()
		key.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.5), 14, 16, 2))
		root.add_child(key)
		var k = UITheme.create_heading(hotkey, key)
		k.add_theme_font_size_override("font_size", 30)
		k.add_theme_font_override("font", UITheme.font_black())
		key.position = Vector2(s.x - 76, 22)

func _half(root: Control, id: String, rect: Rect2, top: bool) -> void:
	var p = SwarmPerks.get_perk(id)
	var color = SwarmPerks.BUFF_COLOR if top else SwarmPerks.DEBUFF_COLOR
	var panel = Panel.new()
	var box = StyleBoxFlat.new()
	box.bg_color = Color(color.darkened(0.55), 0.55)
	box.border_color = Color(color, 0.35)
	box.set_border_width_all(2)
	if top:
		box.corner_radius_top_left = int(RADIUS)
		box.corner_radius_top_right = int(RADIUS)
	else:
		box.corner_radius_bottom_left = int(RADIUS)
		box.corner_radius_bottom_right = int(RADIUS)
	panel.add_theme_stylebox_override("panel", box)
	panel.position = rect.position
	panel.size = rect.size
	root.add_child(panel)
	var col = VBoxContainer.new()
	col.position = rect.position + Vector2(30, 34 if top else 52)
	col.size = Vector2(rect.size.x - 60, rect.size.y - 70)
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(col)
	var tag = UITheme.create_label(tr("BUFF" if top else "DEBUFF").to_upper(), col, 24)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_override("font", UITheme.font_black())
	tag.add_theme_color_override("font_color", Color(color, 0.8))
	var icon = UITheme.create_icon(SwarmPerks.icon(id), col, 72, color.lightened(0.2))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if p.is_empty():
		return
	var name_label = UITheme.create_heading(tr(String(p[0])), col)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 44)
	name_label.add_theme_font_override("font", UITheme.font_black())
	name_label.add_theme_color_override("font_color", color.lightened(0.45))
	var text = UITheme.create_label(tr(String(p[1])), col, 30)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = rect.size.x - 60
	text.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))

func _gui_input(event: InputEvent):
	if event is InputEventMouseMotion:
		var p = event.position / size
		_target = Vector2(p.x - 0.5, p.y - 0.5) * 2.0
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_tilt *= 0.4
		accept_event()
		if _appear >= 0.9:
			pressed.emit()

func _process(delta: float):
	if delay > 0.0:
		delay -= delta
	else:
		_appear = min(1.0, _appear + delta * 1.8)
	var k = 1.0 - exp(-delta * 10.0)
	_tilt = _tilt.lerp(_target, k)
	_lift = lerp(_lift, 1.0 if _hover else 0.0, k)
	if _material:
		# An idle sway so the foil plays even when the mouse is elsewhere
		var t = Time.get_ticks_msec() / 1000.0
		var sway = Vector2(sin(t * 0.9 + delay), cos(t * 0.7)) * 0.12 * (1.0 - _lift)
		_material.set_shader_parameter("yaw", -(_tilt.x + sway.x) * MAX_TILT)
		_material.set_shader_parameter("pitch", (_tilt.y + sway.y) * MAX_TILT)
		_material.set_shader_parameter("lift", _lift)
		_material.set_shader_parameter("appear", _appear)
	scale = Vector2.ONE * (1.0 + 0.05 * _lift)
	pivot_offset = size / 2.0
