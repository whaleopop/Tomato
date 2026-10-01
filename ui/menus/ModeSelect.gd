## The host picks the match mode (GameModes) before the server starts: a row of tall ModeCards
## (the last mode played is chosen), a strip under them with what the chosen mode is about and
## PLAY. Click a card to choose it, double click / Enter to play; 1-4 or arrows choose, Esc closes.
## chosen(mode) / closed.
extends Control
class_name ModeSelect

signal chosen(mode: String)
signal closed

const TAGS = {GameModes.BR: "Free for all", GameModes.SURVIVORS: "Co-op", GameModes.CTF: "Teams", GameModes.KOTH: "Free for all"}

var current: String = GameModes.BR
var _cards: Array = []
var _wash: TextureRect
var _kicker: Label
var _detail_name: Label
var _detail_lines: HFlowContainer
var _play: Button

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	current = GameModes.current() if GameModes.INFO.has(GameModes.current()) else GameModes.BR
	var dim = ColorRect.new()
	dim.color = Color(0.015, 0.02, 0.04, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
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

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 26)
	center.add_child(col)
	# Header: a small colored kicker over a big title, left-aligned with the cards
	var head = VBoxContainer.new()
	head.add_theme_constant_override("separation", -4)
	col.add_child(head)
	_kicker = UITheme.create_label("NEW MATCH", head, UITheme.FONT_SMALL)
	_kicker.add_theme_font_override("font", UITheme.font_black())
	_kicker.uppercase = true
	var title = UITheme.create_title("CHOOSE A MODE", head)
	title.add_theme_font_override("font", UITheme.font_black())
	title.add_theme_font_size_override("font_size", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# The cards
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
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
	# The strip: what the chosen mode is about, BACK and PLAY
	var strip = PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.04, 0.05, 0.09, 0.92), Color(1, 1, 1, 0.1), 20, 26, 16))
	col.add_child(strip)
	var strip_row = HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 22)
	strip.add_child(strip_row)
	var text_box = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 6)
	strip_row.add_child(text_box)
	_detail_name = UITheme.create_heading("", text_box)
	_detail_name.add_theme_font_override("font", UITheme.font_black())
	_detail_name.add_theme_font_size_override("font_size", 22)
	_detail_name.uppercase = true
	_detail_lines = HFlowContainer.new()  # wraps: the strip is as wide as the cards
	_detail_lines.add_theme_constant_override("h_separation", 18)
	_detail_lines.add_theme_constant_override("v_separation", 4)
	text_box.add_child(_detail_lines)
	var back = UITheme.create_button("BACK", strip_row, Vector2(140, 56))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close)
	_play = UITheme.create_primary_button("PLAY", strip_row, Vector2(220, 60))
	_play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_play.add_theme_font_override("font", UITheme.font_black())
	_play.add_theme_font_size_override("font_size", 22)
	_play.pressed.connect(_confirm)
	var hint = UITheme.create_label("Double click or Enter to play   ·   1-4 / arrows to choose   ·   Esc - back", col, UITheme.FONT_TINY)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_select(current, true)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)

func _select(mode: String, instant: bool = false) -> void:
	current = mode
	var info = GameModes.info(mode)
	var color: Color = info.color
	for card in _cards:
		card.selected = card.mode == mode
	_kicker.add_theme_color_override("font_color", color.lightened(0.3))
	_detail_name.text = tr(String(info.name))
	_detail_name.add_theme_color_override("font_color", color.lightened(0.35))
	for c in _detail_lines.get_children():
		c.queue_free()
	for line in info.lines:
		var item = HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		_detail_lines.add_child(item)
		var dot = ColorRect.new()
		dot.color = color
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(dot)
		var l = UITheme.create_label(line, item, UITheme.FONT_SMALL)
		l.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	UITheme.set_accent(_play, color, Color(0.04, 0.05, 0.08))
	_play.text = tr("PLAY") + "  ▸"
	var wash = Color(color, 0.22)
	if instant:
		_wash.modulate = wash
	else:
		create_tween().tween_property(_wash, "modulate", wash, 0.3)

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
