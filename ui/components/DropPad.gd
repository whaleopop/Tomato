## A golden slot a dragged card is dropped on (the shop's "drag here to buy"): dashed gold rim,
## an icon, a caption and a line under it. Idle it is quiet; while a card it accepts is being
## dragged anywhere it pulses; with the card over it it lights up and grows. Dropped: a burst,
## then `dropped(payload)`. `accepts` decides which payloads it takes (default: any card).
## `shake()` refuses it after the fact (not enough coins): the pad shudders and flushes red.
##   var pad = DropPad.new()
##   pad.caption = "DRAG HERE TO BUY"; pad.detail = tr("%d coins") % price; pad.icon = "◉"
##   pad.dropped.connect(func(payload): ...)
extends PanelContainer
class_name DropPad

signal dropped(payload)

var caption: String = "DRAG A CARD HERE":
	set(value):
		caption = value
		if _caption_label:
			_caption_label.text = value
var detail: String = "":
	set(value):
		detail = value
		if _detail_label:
			_detail_label.text = value
			_detail_label.visible = value != ""
var icon: String = "⬇":
	set(value):
		icon = value
		_apply_icon()
var color: Color = UITheme.GOLD
## func(payload) -> bool; empty: every card drag
var accepts: Callable = Callable()
var enabled: bool = true

var _caption_label: Label
var _detail_label: Label
var _icon_label: Label
var _icon_rect: TextureRect
var _over: bool = false
var _active: bool = false          # a card it takes is in the air
var _time: float = 0.0
var _glow: float = 0.0
var _deny: float = 0.0             # 1 -> 0: the red of a refused drop
var _shake: float = 0.0            # seconds of shudder left
var _shake_wait: int = 0           # frames until the container has placed it (a fresh pad)
var _shake_x: float = 0.0

const SHAKE_TIME: float = 0.5
var _mouse := Vector2(-1, -1)      # the pointer from the events (the OS one is not moved by replays)

## An icon name or legacy glyph becomes a texture; anything else stays as text
func _apply_icon() -> void:
	if not _icon_rect:
		return
	var tex = UITheme.icon(icon)
	_icon_rect.texture = tex
	_icon_rect.visible = tex != null
	_icon_label.text = "" if tex else icon
	_icon_label.visible = tex == null

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 96)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon_rect = UITheme.create_icon("", row, 40, color)
	_icon_label = UITheme.create_heading("", row)
	_icon_label.add_theme_font_size_override("font_size", 34)
	_icon_label.add_theme_color_override("font_color", color)
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_icon()
	var texts = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # long captions wrap instead of widening it
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	_caption_label = UITheme.create_heading(caption, texts)
	_caption_label.uppercase = true
	_caption_label.add_theme_font_override("font", UITheme.font_black())
	_caption_label.add_theme_font_size_override("font_size", 15)
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_label = UITheme.create_label(detail, texts, UITheme.FONT_SMALL)
	_detail_label.add_theme_color_override("font_color", color.lightened(0.25))
	_detail_label.add_theme_font_override("font", UITheme.font_bold())
	_detail_label.visible = detail != ""
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(func(): pivot_offset = size / 2.0)
	_restyle()

func _input(event: InputEvent):
	if event is InputEventMouse:
		_mouse = event.position

func _accepts(data) -> bool:
	if not enabled or not (data is Dictionary) or not data.get("card_drag", false):
		return false
	return not accepts.is_valid() or bool(accepts.call(data.get("payload")))

func _can_drop_data(_at_position: Vector2, data) -> bool:
	var ok = _accepts(data)
	if ok != _over:
		_over = ok
		if ok:
			Sfx.ui("ui_hover")
	return ok

func _drop_data(_at_position: Vector2, data) -> void:
	_over = false
	Sfx.ui("ui_click")
	ScreenEffects.flash(color, 0.12, 0.12)
	scale = Vector2.ONE * 1.12
	var t = create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	dropped.emit(data.get("payload"))

## Refuse a drop that was taken (the shop: not enough coins): shudder sideways, flush red
func shake() -> void:
	_shake = SHAKE_TIME
	_shake_wait = 2
	_deny = 1.0
	Sfx.ui("ui_click", -2.0, 0.6)  # a low knock
	_restyle()

func _process(delta: float):
	_time += delta
	if _shake > 0.0:
		if _shake_wait > 0:
			_shake_wait -= 1
			if _shake_wait == 0:
				_shake_x = position.x
		else:
			_shake -= delta
			var k = max(_shake, 0.0) / SHAKE_TIME
			position.x = _shake_x + sin(_shake * 70.0) * 12.0 * k
			if _shake <= 0.0:
				position.x = _shake_x
	if _deny > 0.0:
		_deny = max(_deny - delta * 1.4, 0.0)
		_restyle()
	var vp = get_viewport()
	var dragging = vp != null and vp.gui_is_dragging()
	_active = dragging and _accepts(vp.gui_get_drag_data())
	if not dragging:
		_over = false
	elif _over and not get_global_rect().has_point(_mouse):
		_over = false
	var want = 1.0 if _over else (0.45 + 0.25 * sin(_time * 6.0) if _active else 0.0)
	var before = _glow
	_glow = lerp(_glow, want, 1.0 - exp(-delta * 12.0))
	if dragging:  # grows towards the card (the drop "punch" is a tween once the drag is over)
		scale = Vector2.ONE * (1.0 + 0.05 * _glow)
	if abs(_glow - before) > 0.002:
		_restyle()
		queue_redraw()

func _restyle() -> void:
	var col = color.lerp(UITheme.ACCENT_DANGER, _deny)
	var lit = max(_glow, _deny)
	var box = StyleBoxFlat.new()
	box.bg_color = Color(UITheme.NAVY, 0.85).lerp(Color(col, 0.3), 0.15 + 0.6 * lit)
	box.set_corner_radius_all(14)
	box.set_border_width_all(2)
	box.border_color = Color(col, 0.35 + 0.65 * lit)
	box.shadow_color = Color(col, 0.45 * lit)
	box.shadow_size = int(4 + 18 * lit)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	box.anti_aliasing = true
	add_theme_stylebox_override("panel", box)
	if _caption_label:
		_caption_label.add_theme_color_override("font_color", Color.WHITE if _glow > 0.5 else Color(1, 1, 1, 0.75 + 0.25 * _glow))
		_icon_label.add_theme_color_override("font_color", col.lightened(0.15 * _glow))
		_icon_rect.self_modulate = col.lightened(0.15 * _glow)
		_detail_label.add_theme_color_override("font_color", col.lightened(0.25))
	modulate.a = 1.0 if enabled else 0.55

func _draw():
	# Dashes along the rim while it waits for a card
	if _glow > 0.6 or not enabled:
		return
	var r = Rect2(Vector2(7, 7), size - Vector2(14, 14))
	var dash = 10.0
	var gap = 7.0
	var col = Color(color, 0.5 + 0.3 * _glow)
	var x = r.position.x + 14.0
	while x < r.end.x - 14.0:
		draw_line(Vector2(x, r.position.y), Vector2(min(x + dash, r.end.x - 14.0), r.position.y), col, 1.5)
		draw_line(Vector2(x, r.end.y), Vector2(min(x + dash, r.end.x - 14.0), r.end.y), col, 1.5)
		x += dash + gap
	var y = r.position.y + 14.0
	while y < r.end.y - 14.0:
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x, min(y + dash, r.end.y - 14.0)), col, 1.5)
		draw_line(Vector2(r.end.x, y), Vector2(r.end.x, min(y + dash, r.end.y - 14.0)), col, 1.5)
		y += dash + gap
