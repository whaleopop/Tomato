## A collectible-style card (shop items, starter heroes): the picture of what is inside on layered
## backgrounds. Move the mouse over it and it tilts in perspective (shaders/card_tilt.gdshader)
## while its layers slide at different depths - the background away, the hero towards you.
## The card's content is drawn in its own 2D SubViewport, the tilt is applied to that picture.
## With `live` set, the card under the mouse shows a real 3D model (ItemRenderer.live_begin)
## that turns with the tilt; `always_live` keeps it (the shop's big card). The tilted card is
## drawn over a bigger area than the control (OVERSCAN), so its near edge is never cut off.
## Drag: give the card a `drag_payload` and it can be picked up - the card itself flies under the
## mouse in 3D (CardDragPreview: it leans into the motion), the slot it left stays faded until it
## is dropped. Drop targets get {"card_drag": true, "payload": drag_payload, "card": self}
## (_can_drop_data / _drop_data, or set_drag_forwarding, or a DropPad). While any card is in
## the air the others stay calm (no live model, no lift), so hovering them on the way is harmless.
## `pop()` flips / bounces the card in (the shop's big card after a purchase).
extends Control
class_name ParallaxCard

signal pressed
signal drag_started
signal drag_ended(dropped: bool)

const MAX_TILT: float = 0.38      # radians
const OVERSCAN: float = 0.4       # extra drawing area around the card for the tilt
const LIVE_YAW: float = 1.3       # radians the live model turns at full tilt
const CORNER_RADIUS: float = 26.0  # px of the 2x card picture: the frame, the name plate and the tilt mask
const DEPTHS = [-10.0, 6.0, 18.0, 26.0]  # pixels of slide: background, glow, art, sparkles

var title: String = ""
var subtitle: String = ""
var badge: String = ""           # price / "Owned" in the corner
var accent: Color = Color(0.4, 0.7, 1.0)
var art: Texture2D = null
var selected: bool = false
var locked: bool = false         # darker art with a lock
var card_size: Vector2 = Vector2(190, 264)
var live: Array = []              # [kind, args] for ItemRenderer ("hero" [name, skin, hat] / "gun" [type, finish])
var always_live: bool = false
## Mastery (Mastery.gd): the level in the top-left corner (0 = none) and the rank (-1 none,
## 0 bronze .. 4 diamond) - the background turns into that material and the frame with it
var level: int = 0
var mastery: int = -1
var _bg_material: ShaderMaterial
var _level_panel: PanelContainer
var _level_label: Label
var _level_caption: Label
var _live_on: bool = false

var _viewport: SubViewport
var _view: TextureRect
var _material: ShaderMaterial
var _layers: Array = []           # [Control, depth]
var _art_rect: TextureRect
var _badge_label: Label
var _title_label: Label
var _sub_label: Label
var _frame: Panel
var _lock: Label
var _hover: bool = false
## Anything (a card key, a dictionary): set it and the card can be dragged (null = it can't)
var drag_payload = null
var _dragging: bool = false
var _target := Vector2.ZERO       # tilt the mouse asks for (-1..1)
var _tilt := Vector2.ZERO
var _lift: float = 0.0
var _punch := Vector2.ONE         # extra scale for pop() (the hover scale is set every frame)

func _ready():
	custom_minimum_size = card_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(card_size * 2.0)  # drawn at double size: crisp when tilted
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var root = Control.new()
	root.size = card_size * 2.0
	root.scale = Vector2.ONE
	_viewport.add_child(root)
	_build(root, card_size * 2.0)

	_view = TextureRect.new()
	_view.texture = _viewport.get_texture()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var extra = card_size * OVERSCAN * 0.5
	_view.offset_left = -extra.x
	_view.offset_top = -extra.y
	_view.offset_right = extra.x
	_view.offset_bottom = extra.y
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/card_tilt.gdshader")
	_material.set_shader_parameter("aspect", card_size.x / card_size.y)
	_material.set_shader_parameter("inset", 1.0 + OVERSCAN)  # the card fills the control, not the bigger view
	_material.set_shader_parameter("corner", CORNER_RADIUS / card_size.y)  # viewport px -> half-heights (drawn at 2x)
	_view.material = _material
	add_child(_view)
	mouse_entered.connect(func():
		if _drag_in_air():
			return  # a card flying over it: no live model, no lift
		_hover = true
		z_index = 10  # over the neighbours while it turns
		_start_live())
	mouse_exited.connect(func():
		_hover = false
		_target = Vector2.ZERO
		z_index = 0
		if not always_live:
			_stop_live())
	refresh()
	if always_live:
		_start_live.call_deferred()

func _start_live() -> void:
	if live.is_empty() or _live_on:
		return
	_live_on = true
	var tex = ItemRenderer.get_instance(get_tree()).live_begin(self, live[0], live[1])
	if _art_rect:
		_art_rect.texture = tex

## Some card (this one or another) is being dragged right now
func _drag_in_air() -> bool:
	var vp = get_viewport()
	return vp != null and vp.gui_is_dragging()

## Bounce the card in: `flip` turns it over from edge-on (a bought card), else a quick swell
func pop(flip: bool = true) -> void:
	if not is_inside_tree():
		return
	_punch = Vector2(0.05, 1.04) if flip else Vector2.ONE * 1.14
	var t = create_tween()
	t.tween_property(self, "_punch", Vector2.ONE, 0.5 if flip else 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _stop_live() -> void:
	if not _live_on:
		return
	_live_on = false
	ItemRenderer.get_instance(get_tree()).live_end(self)
	if _art_rect:
		_art_rect.texture = art

func _exit_tree():
	if _live_on and ItemRenderer._instance and is_instance_valid(ItemRenderer._instance):
		ItemRenderer._instance.live_end(self)
		_live_on = false

func _build(root: Control, s: Vector2) -> void:
	var margin = 14.0
	# Layer 0: the backdrop (shaders/card_background.gdshader: rays, honeycomb, the mastery
	# material), sliding away from the mouse
	var bg = ColorRect.new()
	_bg_material = ShaderMaterial.new()
	_bg_material.shader = preload("res://shaders/card_background.gdshader")
	_bg_material.set_shader_parameter("aspect", Vector2(s.x / s.y, 1.0))
	_bg_material.set_shader_parameter("seed", float(get_instance_id() % 97) * 0.37)
	bg.material = _bg_material
	bg.position = Vector2(-30, -30)
	bg.size = s + Vector2(60, 60)
	root.add_child(bg)
	_layers.append([bg, DEPTHS[0]])
	# Layer 1: a glow behind the art
	var glow = TextureRect.new()
	glow.texture = FireTrail._soft_dot(Color(accent.lightened(0.3), 0.75), Color(accent, 0.0))
	glow.size = Vector2(s.x * 1.0, s.x * 1.0)
	glow.position = Vector2(0, s.y * 0.12)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(glow)
	_layers.append([glow, DEPTHS[1]])
	# Layer 2: what is inside (a render from ItemRenderer), popping towards you
	_art_rect = TextureRect.new()
	_art_rect.size = Vector2(s.x * 1.02, s.x * 1.02)
	_art_rect.position = Vector2(-s.x * 0.01, s.y * 0.08)
	_art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(_art_rect)
	_layers.append([_art_rect, DEPTHS[2]])
	# Layer 3: sparkles in front
	for i in 6:
		var dot = TextureRect.new()
		dot.texture = FireTrail._soft_dot(Color(1, 1, 1, 0.9), Color(1, 1, 1, 0))
		var r = 10.0 + (i % 3) * 6.0
		dot.size = Vector2(r, r)
		dot.position = Vector2(fmod(i * 97.0, s.x - 40.0) + 20.0, fmod(i * 61.0, s.y * 0.55) + 30.0)
		dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dot.modulate.a = 0.5
		root.add_child(dot)
		_layers.append([dot, DEPTHS[3] * (0.6 + 0.2 * (i % 3))])
	# Fixed: the name plate at the bottom, the badge, the frame
	var plate = Panel.new()
	var plate_box = StyleBoxFlat.new()
	plate_box.bg_color = Color(0.03, 0.04, 0.08, 0.82)
	plate_box.corner_radius_bottom_left = int(CORNER_RADIUS)
	plate_box.corner_radius_bottom_right = int(CORNER_RADIUS)
	plate.add_theme_stylebox_override("panel", plate_box)
	plate.position = Vector2(0, s.y * 0.72)
	plate.size = Vector2(s.x, s.y * 0.28)
	root.add_child(plate)
	_title_label = UITheme.create_heading("", root)
	_title_label.position = Vector2(margin * 2, s.y * 0.745)
	_title_label.size = Vector2(s.x - margin * 4, 60)
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_font_override("font", UITheme.font_black())
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_title_label.clip_text = true
	_sub_label = UITheme.create_label("", root, 22)
	_sub_label.position = Vector2(margin * 2, s.y * 0.745 + 50)
	_sub_label.size = Vector2(s.x - margin * 4, 40)
	_sub_label.add_theme_font_override("font", UITheme.font_black())
	_sub_label.clip_text = true
	# Top-left: the level (a chip in the rank's color), then the badge next to it
	var corner = HBoxContainer.new()
	corner.position = Vector2(margin * 1.5, margin * 1.5)
	corner.add_theme_constant_override("separation", 10)
	root.add_child(corner)
	_level_panel = PanelContainer.new()
	corner.add_child(_level_panel)
	var level_box = VBoxContainer.new()
	level_box.add_theme_constant_override("separation", -8)
	_level_panel.add_child(level_box)
	_level_caption = UITheme.create_label("LV", level_box, 15)
	_level_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_caption.add_theme_font_override("font", UITheme.font_black())
	_level_label = UITheme.create_heading("", level_box)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 34)
	_level_label.add_theme_font_override("font", UITheme.font_black())
	var badge_panel = PanelContainer.new()
	badge_panel.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.03, 0.04, 0.08, 0.8), Color(1, 1, 1, 0.3), 99, 16, 6))
	badge_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	corner.add_child(badge_panel)
	_badge_label = UITheme.create_heading("", badge_panel)
	_badge_label.add_theme_font_size_override("font_size", 22)
	_lock = UITheme.create_heading("LOCKED", root)
	_lock.add_theme_font_size_override("font_size", 22)
	_lock.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_lock.position = Vector2(s.x - 150, margin * 1.8)
	_frame = Panel.new()
	_frame.size = s
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_frame)

## Level and rank of one of our own heroes / guns (PlayerProfile), or from what another player
## wears (their cosmetics carry "level" / "mastery")
func show_hero_mastery(hero: String) -> void:
	var p = PlayerProfile.hero_progress(hero)
	level = p.level
	mastery = p.tier

func show_weapon_mastery(weapon_type: int) -> void:
	var p = PlayerProfile.weapon_progress(weapon_type)
	level = p.level
	mastery = p.tier

func show_wear_mastery(wear: Dictionary) -> void:
	level = int(wear.get("level", 0))
	mastery = int(wear.get("mastery", -1))

## Apply title / badge / accent / art / selected after changing them
func refresh() -> void:
	if not _title_label:
		return
	_title_label.text = tr(title)
	_sub_label.text = tr(subtitle)
	_sub_label.add_theme_color_override("font_color", accent.lightened(0.35))
	_badge_label.text = badge
	_badge_label.get_parent().visible = badge != ""
	_bg_material.set_shader_parameter("accent", accent)
	_bg_material.set_shader_parameter("tier", mastery)
	_level_panel.visible = level > 0
	if level > 0:
		var rank_col = Mastery.tier_color(mastery) if mastery >= 0 else Color(0.85, 0.9, 1.0)
		var chip = UITheme.glass_box(Color(0.03, 0.04, 0.08, 0.88), Color(rank_col, 0.95), 14, 12, 6)
		chip.set_border_width_all(4)
		chip.shadow_color = Color(rank_col, 0.45 if mastery >= 0 else 0.0)
		chip.shadow_size = 10
		_level_panel.add_theme_stylebox_override("panel", chip)
		_level_label.text = str(level)
		_level_label.add_theme_color_override("font_color", rank_col.lightened(0.25))
		_level_caption.add_theme_color_override("font_color", Color(rank_col, 0.85))
	if not _live_on:
		_art_rect.texture = art
	_art_rect.modulate = Color(0.68, 0.68, 0.76) if locked else Color.WHITE  # still shows what is inside
	_lock.visible = locked
	# Under the level / price row when there is one, else in the top-right corner
	_lock.position = Vector2(card_size.x * 2.0 - 150, 14.0 * 1.8 + (72.0 if level > 0 or badge != "" else 0.0))
	var frame = StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.set_corner_radius_all(int(CORNER_RADIUS))
	frame.set_border_width_all(10 if selected else (8 if mastery >= 0 else 5))
	frame.border_color = accent.lightened(0.45) if selected else Color(accent, 0.8)
	if mastery >= 0 and not selected:
		frame.border_color = Mastery.tier_color(mastery).lightened(0.15)  # a rank frame
	_frame.add_theme_stylebox_override("panel", frame)

func set_art(texture: Texture2D) -> void:
	art = texture
	if _art_rect and not _live_on:
		_art_rect.texture = art

## The card's own picture (its SubViewport, drawn at 2x): the drag preview shows it
func card_texture() -> Texture2D:
	return _viewport.get_texture() if _viewport else null

func is_dragging() -> bool:
	return _dragging

func _get_drag_data(at_position: Vector2):
	if drag_payload == null:
		return null
	_dragging = true
	_hover = false
	_target = Vector2.ZERO
	z_index = 0
	if not always_live:
		_stop_live()  # the flying copy shows the card's picture
	set_drag_preview(CardDragPreview.make(self, at_position))
	modulate.a = 0.3                  # the slot it left
	drag_started.emit()
	Sfx.ui("ui_hover")
	return {"card_drag": true, "payload": drag_payload, "card": self}

func _notification(what: int):
	if what == NOTIFICATION_DRAG_END and _dragging:
		_dragging = false
		var ok = get_viewport().gui_is_drag_successful()
		var t = create_tween()
		t.tween_property(self, "modulate:a", 1.0, 0.2)
		drag_ended.emit(ok)

func _gui_input(event: InputEvent):
	if event is InputEventMouseMotion:
		var p = event.position / size
		_target = Vector2(p.x - 0.5, p.y - 0.5) * 2.0
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		_tilt *= 0.4  # a little "press" jolt
		accept_event()

func _process(delta: float):
	var k = 1.0 - exp(-delta * 10.0)
	_tilt = _tilt.lerp(_target, k)
	_lift = lerp(_lift, 1.0 if (_hover or selected) else 0.0, k)
	if _material:
		_material.set_shader_parameter("yaw", -_tilt.x * MAX_TILT)
		_material.set_shader_parameter("pitch", _tilt.y * MAX_TILT)
		_material.set_shader_parameter("lift", _lift)
	if _live_on:
		ItemRenderer.get_instance(get_tree()).live_turn(self, _tilt.x * LIVE_YAW, _tilt.y * 0.25)
	for layer in _layers:
		var node: Control = layer[0]
		if not node.has_meta("rest"):
			node.set_meta("rest", node.position)
		node.position = node.get_meta("rest") + _tilt * float(layer[1])
	scale = Vector2.ONE * (1.0 + 0.04 * _lift) * _punch
	pivot_offset = size / 2.0
