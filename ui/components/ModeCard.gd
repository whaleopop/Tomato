## A tall card for one match mode (ModeSelect): a deep navy card in the menu's look - the mode's
## backdrop (shaders/card_background.gdshader in its color, under a navy wash), a drawn emblem
## (ModeEmblem: no font glyphs, so all four look alike), a gold tag, the name and what it is, a thin
## light rim that turns into a gold ring with a glow when chosen. Drawn in its own SubViewport and
## tilted towards the mouse (shaders/card_tilt.gdshader) while the layers slide at different depths,
## like ParallaxCard.
extends Control
class_name ModeCard

signal pressed
signal double_pressed

const CARD_SIZE := Vector2(250, 410)
const MAX_TILT: float = 0.3
const OVERSCAN: float = 0.35
const RADIUS: float = 36.0                 # px of the 2x picture
const DEPTHS = [-12.0, 8.0, 22.0]          # backdrop, glow, emblem

var mode: String = GameModes.BR
var index: int = 0
var tag: String = ""
var selected: bool = false

var _material: ShaderMaterial
var _layers: Array = []
var _frame_box: StyleBoxFlat
var _inner_box: StyleBoxFlat             # gold light inside the ring (border_blend: fades inwards)
var _halo: Panel                         # the gold glow around the chosen card (outside the picture)
var _hover: bool = false
var _target := Vector2.ZERO
var _tilt := Vector2.ZERO
var _lift: float = 0.0
var _sel: float = 0.0
var _emblem: ModeEmblem

func _ready():
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# The glow around the chosen card, behind the tilted picture
	_halo = Panel.new()
	_halo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_halo.add_theme_stylebox_override("panel", UITheme.glow_box(Color(UITheme.GOLD, 0.0), 0.55, int(RADIUS * 0.5), 26))
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_halo.modulate.a = 0.0
	add_child(_halo)
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
	_material.shader = preload("res://shaders/card_tilt.gdshader")
	_material.set_shader_parameter("aspect", CARD_SIZE.x / CARD_SIZE.y)
	_material.set_shader_parameter("inset", 1.0 + OVERSCAN)
	_material.set_shader_parameter("corner", RADIUS / CARD_SIZE.y)
	_material.set_shader_parameter("glare", 0.4)
	view.material = _material
	add_child(view)
	mouse_entered.connect(func():
		_hover = true
		z_index = 10
		Sfx.ui("ui_hover"))
	mouse_exited.connect(func():
		_hover = false
		_target = Vector2.ZERO
		z_index = 0)

func _build(root: Control, s: Vector2) -> void:
	var info = GameModes.info(mode)
	var color: Color = info.color
	# Backdrop: rays and honeycomb in the mode's color
	var bg = ColorRect.new()
	var bg_mat = ShaderMaterial.new()
	bg_mat.shader = preload("res://shaders/card_background.gdshader")
	bg_mat.set_shader_parameter("accent", color.darkened(0.3))
	bg_mat.set_shader_parameter("aspect", Vector2(s.x / s.y, 1.0))
	bg_mat.set_shader_parameter("seed", float(index) * 1.7)
	bg.material = bg_mat
	bg.position = Vector2(-30, -30)
	bg.size = s + Vector2(60, 60)
	root.add_child(bg)
	_layers.append([bg, DEPTHS[0]])
	# A navy wash over it: the menu's deep navy, the mode's color shows through
	var navy = ColorRect.new()
	navy.color = Color(0.03, 0.045, 0.1, 0.42)
	navy.size = s
	navy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(navy)
	# A glow behind the emblem
	var glow = TextureRect.new()
	glow.texture = FireTrail._soft_dot(Color(color.lightened(0.35), 0.7), Color(color, 0.0))
	glow.size = Vector2(s.x * 1.1, s.x * 1.1)
	glow.position = Vector2(-s.x * 0.05, s.y * 0.3 - s.x * 0.55)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(glow)
	_layers.append([glow, DEPTHS[1]])
	# The emblem
	_emblem = ModeEmblem.new()
	_emblem.mode = mode
	_emblem.color = color
	_emblem.size = Vector2(320, 320)
	_emblem.position = Vector2((s.x - 320) * 0.5, s.y * 0.3 - 160)
	root.add_child(_emblem)
	_layers.append([_emblem, DEPTHS[2]])
	# Darkening towards the bottom, where the text sits
	var shade = TextureRect.new()
	var grad = Gradient.new()
	grad.set_color(0, Color(0.03, 0.045, 0.1, 0.0))
	grad.set_color(1, Color(0.03, 0.045, 0.1, 0.97))
	var gt = GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	shade.texture = gt
	shade.position = Vector2(0, s.y * 0.48)
	shade.size = Vector2(s.x, s.y * 0.52)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(shade)
	# Top: the number and the tag
	var num = UITheme.create_heading("%02d" % (index + 1), root)
	num.add_theme_font_override("font", UITheme.font_black())
	num.add_theme_font_size_override("font_size", 30)
	num.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	num.position = Vector2(32, 24)
	var pill = PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.03, 0.045, 0.1, 0.82), Color(UITheme.GOLD, 0.65), 99, 18, 5))
	root.add_child(pill)
	var tag_label = UITheme.create_label(tr(tag), pill, 20)
	tag_label.uppercase = true
	tag_label.add_theme_font_override("font", UITheme.font_black())
	tag_label.add_theme_color_override("font_color", UITheme.GOLD)
	pill.reset_size()
	pill.position = Vector2(s.x - pill.size.x - 28, 26)
	# Bottom: the name, a colored rule, what it is
	var col = VBoxContainer.new()
	col.position = Vector2(34, s.y * 0.6)
	col.size = Vector2(s.x - 68, s.y * 0.36)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 10)
	root.add_child(col)
	var name_label = UITheme.create_heading(tr(String(info.name)), col)
	name_label.uppercase = true
	name_label.add_theme_font_override("font", UITheme.font_black())
	name_label.add_theme_font_size_override("font_size", 44)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	name_label.add_theme_constant_override("shadow_offset_y", 3)
	name_label.add_theme_constant_override("line_spacing", -8)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = s.x - 68
	var rule = ColorRect.new()
	rule.color = color
	rule.custom_minimum_size = Vector2(70, 6)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)
	var short = UITheme.create_label(tr(String(info.short)), col, 25)
	short.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	short.custom_minimum_size.x = s.x - 68
	short.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	# Gold light inside the ring when chosen, fading inwards
	var inner = Panel.new()
	inner.size = s
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner_box = StyleBoxFlat.new()
	_inner_box.bg_color = Color(UITheme.GOLD, 0.0)
	_inner_box.set_corner_radius_all(int(RADIUS))
	_inner_box.set_border_width_all(34)
	_inner_box.border_blend = true
	_inner_box.border_color = Color(UITheme.GOLD, 0.0)
	inner.add_theme_stylebox_override("panel", _inner_box)
	root.add_child(inner)
	# Frame: a thin light rim, a gold ring when chosen
	var frame = Panel.new()
	frame.size = s
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_box = StyleBoxFlat.new()
	_frame_box.bg_color = Color(0, 0, 0, 0)
	_frame_box.set_corner_radius_all(int(RADIUS))
	_frame_box.set_border_width_all(4)
	_frame_box.border_color = Color(1, 1, 1, 0.14)
	frame.add_theme_stylebox_override("panel", _frame_box)
	root.add_child(frame)

func _gui_input(event: InputEvent):
	if event is InputEventMouseMotion:
		var p = event.position / size
		_target = Vector2(p.x - 0.5, p.y - 0.5) * 2.0
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_tilt *= 0.4
		Sfx.ui("ui_click")
		if event.double_click:
			double_pressed.emit()
		else:
			pressed.emit()

func _process(delta: float):
	var k = 1.0 - exp(-delta * 10.0)
	_tilt = _tilt.lerp(_target, k)
	_lift = lerp(_lift, 1.0 if _hover else 0.0, k)
	_sel = lerp(_sel, 1.0 if selected else 0.0, k)
	if _material:
		_material.set_shader_parameter("yaw", -_tilt.x * MAX_TILT)
		_material.set_shader_parameter("pitch", _tilt.y * MAX_TILT)
		_material.set_shader_parameter("lift", max(_lift, _sel * 0.6))
	for layer in _layers:
		var node: Control = layer[0]
		if not node.has_meta("rest"):
			node.set_meta("rest", node.position)
		node.position = node.get_meta("rest") + _tilt * float(layer[1])
	if _frame_box:
		# Hover: the rim brightens a little; chosen: a gold ring, light inside and a glow around
		var rim = Color(1, 1, 1, 0.14).lerp(Color(UITheme.GOLD, 0.55), _lift * (1.0 - _sel))
		_frame_box.border_color = rim.lerp(UITheme.GOLD, _sel)
		_frame_box.set_border_width_all(int(round(lerp(4.0, 7.0, _sel))))
		_inner_box.border_color = Color(UITheme.GOLD, 0.32 * _sel)
		_halo.modulate.a = _sel
	if _emblem:
		_emblem.pulse = _sel
	scale = Vector2.ONE * (1.0 + 0.03 * _lift + 0.04 * _sel)
	pivot_offset = size / 2.0
	modulate = Color(1, 1, 1).lerp(Color(0.58, 0.6, 0.7), (1.0 - _sel) * (1.0 - _lift))
