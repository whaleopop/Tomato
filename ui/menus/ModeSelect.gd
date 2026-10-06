## The host picks the match mode (GameModes) before the server starts, over the main menu's 3D garden
## (a navy wash, so the diorama shows through): the template's top bar (ScreenHeader: BACK, title,
## wallet), a row of tall ModeCards (the last mode played is chosen; a gold ring on the chosen one), a
## navy strip under them with the chosen mode's emblem and what it is about, HOST LAN (this computer
## hosts) and the golden PLAY (find an online match). Click a card to choose it, double click / Enter
## to play; 1-4 or arrows choose, Esc / BACK closes. chosen(mode) / host_chosen(mode) / closed.
extends Control
class_name ModeSelect

signal chosen(mode: String)
signal host_chosen(mode: String)
signal closed

const TAGS = {GameModes.BR: "Free for all", GameModes.SURVIVORS: "Co-op", GameModes.CTF: "Teams", GameModes.KOTH: "Free for all"}
const CARD_GAP: int = 22

var current: String = GameModes.BR
var header: ScreenHeader
var _cards: Array = []
var _wash: TextureRect
var _kicker: Label
var _detail_name: Label
var _detail_lines: HFlowContainer
var _emblem: ModeEmblem
var _emblem_glow: TextureRect
var _play: Button
var _host: Button

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	current = GameModes.current() if GameModes.INFO.has(GameModes.current()) else GameModes.BR
	# A navy wash instead of a flat black dim: lighter in the middle, where the garden shows through
	var dim = TextureRect.new()
	var grad = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.035, 0.08, 0.8), Color(0.03, 0.045, 0.1, 0.5), Color(0.02, 0.03, 0.07, 0.9)])
	var gt = GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	dim.texture = gt
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dim.stretch_mode = TextureRect.STRETCH_SCALE
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	# The sides a little deeper (the main menu's column sits on the left), the garden open in the middle
	var sides = TextureRect.new()
	var side_grad = Gradient.new()
	side_grad.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	side_grad.colors = PackedColorArray([Color(0.02, 0.03, 0.07, 0.6), Color(0.02, 0.03, 0.07, 0.0), Color(0.02, 0.03, 0.07, 0.0), Color(0.02, 0.03, 0.07, 0.35)])
	var side_tex = GradientTexture2D.new()
	side_tex.gradient = side_grad
	side_tex.width = 128
	side_tex.height = 4
	sides.texture = side_tex
	sides.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sides.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sides.stretch_mode = TextureRect.STRETCH_SCALE
	sides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sides)
	# A wash of the chosen mode's color rising from the bottom
	_wash = TextureRect.new()
	_wash.texture = FireTrail._soft_dot(Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0))
	_wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wash.offset_top = 400
	_wash.offset_bottom = 300
	_wash.offset_left = -200
	_wash.offset_right = 200
	_wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wash.stretch_mode = TextureRect.STRETCH_SCALE
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wash)

	# Under the bar: the cards and the strip, centered in what is left of the screen
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = ScreenHeader.CONTENT_TOP
	center.offset_bottom = -12
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	# A plain holder between them: a container resets its children's scale, the holder lets _fit
	# shrink the column on small windows
	var holder = Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(holder)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 30)  # room for the chosen card's lift
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(col)
	center.resized.connect(_fit.bind(center, holder, col))
	col.minimum_size_changed.connect(_fit.bind(center, holder, col))
	# The cards
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", CARD_GAP)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	for i in GameModes.ORDER.size():
		var mode: String = GameModes.ORDER[i]
		var card = ModeCard.new()
		card.mode = mode
		card.index = i
		card.tag = TAGS.get(mode, "")
		card.pressed.connect(_select.bind(mode))
		card.double_pressed.connect(func():
			_select(mode)
			_confirm())
		row.add_child(card)
		_cards.append(card)
	# The strip: the chosen mode's emblem and what it is about, HOST LAN and PLAY
	var strip = UITheme.navy_panel(col, 0)
	strip.add_theme_stylebox_override("panel", UITheme.navy_box(Color(0.045, 0.06, 0.11, 0.92), Color(1, 1, 1, 0.1), 16, 22, 16))
	var strip_row = HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 20)
	strip.add_child(strip_row)
	var badge = Control.new()  # the emblem on a soft glow of the mode's color
	badge.custom_minimum_size = Vector2(76, 76)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_row.add_child(badge)
	_emblem_glow = TextureRect.new()
	_emblem_glow.texture = FireTrail._soft_dot(Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0))
	_emblem_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_emblem_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_emblem_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(_emblem_glow)
	_emblem = ModeEmblem.new()
	_emblem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_emblem.pulse = 1.0
	badge.add_child(_emblem)
	var text_box = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 4)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_row.add_child(text_box)
	_kicker = UITheme.create_label("", text_box, 13)  # "02 · TEAMS"
	_kicker.uppercase = true
	_kicker.add_theme_font_override("font", UITheme.font_black())
	_kicker.add_theme_color_override("font_color", UITheme.GOLD)
	_detail_name = UITheme.create_heading("", text_box)
	_detail_name.add_theme_font_override("font", UITheme.font_black())
	_detail_name.add_theme_font_size_override("font_size", 26)
	_detail_name.add_theme_color_override("font_color", Color.WHITE)
	_detail_name.uppercase = true
	_detail_lines = HFlowContainer.new()  # wraps: the strip is as wide as the cards
	_detail_lines.add_theme_constant_override("h_separation", 18)
	_detail_lines.add_theme_constant_override("v_separation", 2)
	_detail_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(_detail_lines)
	_host = UITheme.create_menu_row("HOST LAN", "THIS COMPUTER HOSTS", strip_row)
	_host.custom_minimum_size = Vector2(244, 56)  # the Russian caption ran under the chevron at 212
	_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_host.tooltip_text = tr("This computer hosts, friends join by IP")
	_host.pressed.connect(func():
		host_chosen.emit(current)
		queue_free())
	_play = UITheme.create_play_button("PLAY", "FIND A MATCH", strip_row)
	_play.custom_minimum_size = Vector2(250, 68)
	_play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_play.pressed.connect(_confirm)
	var hint = UITheme.create_label("Double click or Enter to play   ·   1-4 / arrows to choose   ·   Esc - back", col, UITheme.FONT_TINY)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	# The bar on top: BACK does what Esc does. A solid backing under it: the main menu has its own bar
	# right under this one, its tabs and wallet would show through the glass
	var backing = ColorRect.new()
	backing.color = Color(0.03, 0.045, 0.09)
	backing.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	backing.offset_bottom = ScreenHeader.HEIGHT
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backing)
	header = ScreenHeader.make(self, "CHOOSE A MODE", "NEW MATCH", true)
	header.back_pressed.connect(_close)
	_select(current, true)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)

## Choose a mode: the cards' rings, the strip's emblem, kicker, name and lines, the color wash
func _select(mode: String, instant: bool = false) -> void:
	current = mode
	var info = GameModes.info(mode)
	var color: Color = info.color
	for card in _cards:
		card.selected = card.mode == mode
	_kicker.text = "%02d  ·  %s" % [GameModes.ORDER.find(mode) + 1, tr(String(TAGS.get(mode, "")))]
	_detail_name.text = tr(String(info.name))
	_emblem.mode = mode
	_emblem.color = color
	_emblem_glow.modulate = Color(color, 0.5)
	for c in _detail_lines.get_children():
		c.queue_free()
	for line in info.lines:
		var item = HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_detail_lines.add_child(item)
		var dot = Panel.new()  # a small round dot in the mode's color
		var dot_box = StyleBoxFlat.new()
		dot_box.bg_color = color.lightened(0.15)
		dot_box.set_corner_radius_all(4)
		dot.add_theme_stylebox_override("panel", dot_box)
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(dot)
		var l = UITheme.create_label(line, item, UITheme.FONT_SMALL)
		l.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	var wash = Color(color, 0.2)
	if instant:
		_wash.modulate = wash
	else:
		create_tween().tween_property(_wash, "modulate", wash, 0.3)

## Small windows (1280x720): shrink the cards and the strip together until they fit under the bar
func _fit(center: Control, holder: Control, col: Control) -> void:
	var need = col.get_combined_minimum_size()
	if need.x <= 0.0 or need.y <= 0.0 or center.size.y <= 0.0:
		return
	var k = minf(1.0, minf(center.size.y / (need.y + 24.0), center.size.x / (need.x + 48.0)))
	col.position = Vector2.ZERO
	col.size = need
	col.scale = Vector2(k, k)
	holder.custom_minimum_size = need * k

func _confirm() -> void:
	chosen.emit(current)
	queue_free()

func _close() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		_close()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var i = GameModes.ORDER.find(current)
	match event.keycode:
		KEY_LEFT, KEY_A:
			_select(GameModes.ORDER[(i - 1 + GameModes.ORDER.size()) % GameModes.ORDER.size()])
		KEY_RIGHT, KEY_D:
			_select(GameModes.ORDER[(i + 1) % GameModes.ORDER.size()])
		KEY_1, KEY_2, KEY_3, KEY_4:
			_select(GameModes.ORDER[mini(event.keycode - KEY_1, GameModes.ORDER.size() - 1)])
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm()
		_:
			return
	get_viewport().set_input_as_handled()
