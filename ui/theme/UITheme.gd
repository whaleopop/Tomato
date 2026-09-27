## Unified "glass" UI theme: palette, fonts, a global Theme and factory helpers for all menus/HUD.
## The Theme returned by get_theme() is applied to the root window (see SceneTransition), so
## every Control in the game gets the glass look even without using these helpers.
extends RefCounted
class_name UITheme

# ---------------------------------------------------------------- palette
const BG_DARK = Color(0.043, 0.059, 0.118)          # deep night
const BG_MEDIUM = Color(0.08, 0.10, 0.18)
const BG_LIGHT = Color(0.14, 0.17, 0.28)
const BG_PANEL = Color(0.07, 0.09, 0.16, 0.42)       # glass tint

const TEXT_PRIMARY = Color(1.0, 1.0, 1.0, 0.95)
const TEXT_SECONDARY = Color(0.78, 0.82, 0.92, 0.78)
const TEXT_MUTED = Color(0.78, 0.82, 0.92, 0.48)
const TEXT_TITLE = Color(1.0, 1.0, 1.0)
const TEXT_ACCENT = Color(0.55, 0.95, 0.55)
const TEXT_ON_ACCENT = Color(0.04, 0.10, 0.05)

const ACCENT_PRIMARY = Color(0.52, 0.91, 0.42)       # fresh lime
const ACCENT_SECONDARY = Color(1.0, 0.78, 0.34)      # corn
const ACCENT_SUCCESS = Color(0.36, 0.89, 0.58)       # mint
const ACCENT_DANGER = Color(1.0, 0.38, 0.40)         # tomato
const ACCENT_WARNING = Color(1.0, 0.78, 0.34)        # corn
const ACCENT_INFO = Color(0.40, 0.78, 1.0)           # sky
const ACCENT_BEET = Color(0.70, 0.45, 1.0)           # beet

# Darker glass for panels shown over the bright 3D game
const GLASS_TINT_DARK = Color(0.04, 0.05, 0.10, 0.74)
const GLASS_TINT_HUD = Color(0.04, 0.05, 0.10, 0.6)

const GLASS_FILL = Color(1, 1, 1, 0.07)
const GLASS_FILL_HOVER = Color(1, 1, 1, 0.14)
const GLASS_FILL_PRESSED = Color(1, 1, 1, 0.04)
const GLASS_RIM = Color(1, 1, 1, 0.16)
const GLASS_RIM_HOVER = Color(1, 1, 1, 0.34)

# Kept for older code
const BUTTON_NORMAL = GLASS_FILL
const BUTTON_HOVER = GLASS_FILL_HOVER
const BUTTON_PRESSED = GLASS_FILL_PRESSED

# ---------------------------------------------------------------- metrics
const FONT_HERO = 64
const FONT_TITLE = 34
const FONT_SUBTITLE = 22
const FONT_HEADING = 20
const FONT_NORMAL = 17
const FONT_SMALL = 14
const FONT_TINY = 12

const MARGIN_LARGE = 40
const MARGIN_MEDIUM = 22
const MARGIN_SMALL = 12
const SPACING_LARGE = 22
const SPACING_MEDIUM = 14
const SPACING_SMALL = 8

const CORNER_RADIUS = 22
const CORNER_RADIUS_SMALL = 14
const CORNER_RADIUS_PILL = 999

const BACKGROUND_SHADER = preload("res://shaders/ui_background.gdshader")
const FONT_PATH = "res://ui/theme/fonts/Nunito.ttf"

static var _theme: Theme = null
static var _fonts: Dictionary = {}

# ---------------------------------------------------------------- fonts

## Nunito is a variable font: every weight comes from the same file
static func font(weight: int = 500) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var fv = FontVariation.new()
	# Loaded lazily: a preload would fail on the very first import of the project
	var base = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	if base:
		fv.base_font = base
	var ts = TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	_fonts[weight] = fv
	return fv

static func font_regular() -> Font:
	return font(500)

static func font_bold() -> Font:
	return font(750)

static func font_black() -> Font:
	return font(900)

# ---------------------------------------------------------------- style boxes

static func glass_box(fill: Color = GLASS_FILL, rim: Color = GLASS_RIM, radius: int = CORNER_RADIUS_SMALL, margin_h: float = 18, margin_v: float = 10) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.set_border_width_all(1)
	box.border_color = rim
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	box.anti_aliasing = true
	return box

static func glow_box(color: Color, glow: float = 0.45, radius: int = CORNER_RADIUS_SMALL, glow_size: int = 14) -> StyleBoxFlat:
	var box = glass_box(color, color.lightened(0.35), radius)
	box.shadow_color = Color(color, glow)
	box.shadow_size = glow_size
	return box

static func empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

# ---------------------------------------------------------------- global theme

## Theme for the whole game. Built once and cached.
static func get_theme() -> Theme:
	if _theme:
		return _theme

	var t = Theme.new()
	t.default_font = font_regular()
	t.default_font_size = FONT_NORMAL

	# Labels
	t.set_color("font_color", "Label", TEXT_PRIMARY)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("shadow_offset_x", "Label", 0)

	# Buttons
	for type_name in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type_name, glass_box())
		t.set_stylebox("hover", type_name, glass_box(GLASS_FILL_HOVER, GLASS_RIM_HOVER))
		t.set_stylebox("pressed", type_name, glass_box(GLASS_FILL_PRESSED, Color(ACCENT_PRIMARY, 0.6)))
		t.set_stylebox("hover_pressed", type_name, glass_box(GLASS_FILL_HOVER, Color(ACCENT_PRIMARY, 0.8)))
		t.set_stylebox("disabled", type_name, glass_box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.06)))
		t.set_stylebox("focus", type_name, glass_box(Color(0, 0, 0, 0), Color(ACCENT_PRIMARY, 0.7)))
		t.set_color("font_color", type_name, TEXT_PRIMARY)
		t.set_color("font_hover_color", type_name, Color.WHITE)
		t.set_color("font_pressed_color", type_name, ACCENT_PRIMARY)
		t.set_color("font_focus_color", type_name, Color.WHITE)
		t.set_color("font_disabled_color", type_name, TEXT_MUTED)
		t.set_font("font", type_name, font_bold())

	# Check buttons / boxes: plain rows
	for type_name in ["CheckButton", "CheckBox"]:
		t.set_stylebox("normal", type_name, empty_box())
		t.set_stylebox("hover", type_name, glass_box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), CORNER_RADIUS_SMALL, 10, 6))
		t.set_stylebox("pressed", type_name, empty_box())
		t.set_stylebox("hover_pressed", type_name, glass_box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), CORNER_RADIUS_SMALL, 10, 6))
		t.set_stylebox("focus", type_name, empty_box())
		t.set_color("font_color", type_name, TEXT_PRIMARY)
		t.set_color("font_hover_color", type_name, Color.WHITE)
		t.set_color("font_pressed_color", type_name, TEXT_PRIMARY)
		t.set_color("font_hover_pressed_color", type_name, Color.WHITE)

	# Text inputs
	var edit_normal = glass_box(Color(0, 0, 0, 0.28), Color(1, 1, 1, 0.14), CORNER_RADIUS_SMALL, 16, 10)
	var edit_focus = glass_box(Color(0, 0, 0, 0.34), Color(ACCENT_PRIMARY, 0.85), CORNER_RADIUS_SMALL, 16, 10)
	edit_focus.shadow_color = Color(ACCENT_PRIMARY, 0.25)
	edit_focus.shadow_size = 8
	t.set_stylebox("normal", "LineEdit", edit_normal)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_stylebox("read_only", "LineEdit", edit_normal)
	t.set_color("font_color", "LineEdit", TEXT_PRIMARY)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	t.set_color("caret_color", "LineEdit", ACCENT_PRIMARY)
	t.set_color("selection_color", "LineEdit", Color(ACCENT_PRIMARY, 0.35))

	# Panels (generic)
	var panel_box = glass_box(Color(0.07, 0.09, 0.16, 0.72), GLASS_RIM, CORNER_RADIUS, 22, 22)
	panel_box.shadow_color = Color(0, 0, 0, 0.3)
	panel_box.shadow_size = 24
	panel_box.shadow_offset = Vector2(0, 8)
	t.set_stylebox("panel", "PanelContainer", panel_box)
	t.set_stylebox("panel", "Panel", panel_box)

	# Item lists
	t.set_stylebox("panel", "ItemList", glass_box(Color(0, 0, 0, 0.2), Color(1, 1, 1, 0.08), CORNER_RADIUS_SMALL, 8, 8))
	t.set_stylebox("focus", "ItemList", empty_box())
	t.set_stylebox("hovered", "ItemList", glass_box(GLASS_FILL, Color(0, 0, 0, 0), 10, 10, 6))
	t.set_stylebox("selected", "ItemList", glass_box(Color(ACCENT_PRIMARY, 0.22), Color(ACCENT_PRIMARY, 0.6), 10, 10, 6))
	t.set_stylebox("selected_focus", "ItemList", glass_box(Color(ACCENT_PRIMARY, 0.22), Color(ACCENT_PRIMARY, 0.6), 10, 10, 6))
	t.set_color("font_color", "ItemList", TEXT_SECONDARY)
	t.set_color("font_hovered_color", "ItemList", Color.WHITE)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)

	# Progress bars
	var bar_bg = glass_box(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.08), CORNER_RADIUS_PILL, 0, 0)
	var bar_fill = glass_box(ACCENT_PRIMARY, Color(1, 1, 1, 0.25), CORNER_RADIUS_PILL, 0, 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", TEXT_PRIMARY)

	# Sliders
	var slider_track = glass_box(Color(1, 1, 1, 0.10), Color(0, 0, 0, 0), CORNER_RADIUS_PILL, 0, 3)
	var slider_fill = glass_box(ACCENT_PRIMARY, Color(0, 0, 0, 0), CORNER_RADIUS_PILL, 0, 3)
	t.set_stylebox("slider", "HSlider", slider_track)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	t.set_icon("grabber", "HSlider", _circle_texture(18, Color.WHITE))
	t.set_icon("grabber_highlight", "HSlider", _circle_texture(20, ACCENT_PRIMARY.lightened(0.3)))

	# Scrollbars: thin pills
	for type_name in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type_name, glass_box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), CORNER_RADIUS_PILL, 3, 3))
		t.set_stylebox("grabber", type_name, glass_box(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), CORNER_RADIUS_PILL, 3, 3))
		t.set_stylebox("grabber_highlight", type_name, glass_box(Color(1, 1, 1, 0.38), Color(0, 0, 0, 0), CORNER_RADIUS_PILL, 3, 3))
		t.set_stylebox("grabber_pressed", type_name, glass_box(Color(ACCENT_PRIMARY, 0.7), Color(0, 0, 0, 0), CORNER_RADIUS_PILL, 3, 3))

	# Separators
	var sep_line = StyleBoxLine.new()
	sep_line.color = Color(1, 1, 1, 0.10)
	sep_line.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep_line)
	t.set_constant("separation", "HSeparator", 12)

	# Tooltips and popups
	t.set_stylebox("panel", "TooltipPanel", glass_box(Color(0.06, 0.08, 0.14, 0.95), GLASS_RIM, 10, 12, 8))
	t.set_color("font_color", "TooltipLabel", TEXT_PRIMARY)
	t.set_stylebox("panel", "PopupMenu", glass_box(Color(0.06, 0.08, 0.14, 0.96), GLASS_RIM, CORNER_RADIUS_SMALL, 8, 8))
	t.set_stylebox("hover", "PopupMenu", glass_box(Color(ACCENT_PRIMARY, 0.2), Color(0, 0, 0, 0), 8, 8, 4))

	# Rich text
	t.set_color("default_color", "RichTextLabel", TEXT_SECONDARY)
	t.set_font("bold_font", "RichTextLabel", font_bold())

	_theme = t
	return t

static func _circle_texture(diameter: int, color: Color) -> ImageTexture:
	var img = Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r = diameter / 2.0
	for y in diameter:
		for x in diameter:
			var d = Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a = clamp(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(color, a * color.a))
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- backgrounds / layout

## Animated aurora background filling the parent
static func create_background(parent: Control) -> ColorRect:
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	mat.shader = BACKGROUND_SHADER
	bg.material = mat
	parent.add_child(bg)
	parent.move_child(bg, 0)
	return bg

## Frosted glass card
static func create_panel(parent: Control = null, padding: int = MARGIN_MEDIUM) -> GlassPanel:
	var panel = GlassPanel.new()
	panel.padding = padding
	if parent:
		parent.add_child(panel)
	return panel

## Full-screen centered column
static func create_centered_container(parent: Control, width: int = 400) -> VBoxContainer:
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size.x = width
	vbox.add_theme_constant_override("separation", SPACING_MEDIUM)
	center.add_child(vbox)
	return vbox

## Full-screen margin container (safe area for menu layouts)
static func create_screen_margin(parent: Control, margin: int = MARGIN_LARGE) -> MarginContainer:
	var m = MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, margin)
	parent.add_child(m)
	return m

# ---------------------------------------------------------------- text

static func create_hero_title(text: String, parent: Control = null) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_override("font", font_black())
	label.add_theme_font_size_override("font_size", FONT_HERO)
	label.add_theme_color_override("font_color", TEXT_TITLE)
	label.add_theme_color_override("font_shadow_color", Color(ACCENT_PRIMARY, 0.45))
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_constant_override("shadow_outline_size", 18)
	if parent:
		parent.add_child(label)
	return label

static func create_title(text: String, parent: Control = null) -> Label:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font_black())
	label.add_theme_font_size_override("font_size", FONT_TITLE)
	label.add_theme_color_override("font_color", TEXT_TITLE)
	if parent:
		parent.add_child(label)
	return label

static func create_subtitle(text: String, parent: Control = null) -> Label:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font_bold())
	label.add_theme_font_size_override("font_size", FONT_SUBTITLE)
	label.add_theme_color_override("font_color", TEXT_SECONDARY)
	if parent:
		parent.add_child(label)
	return label

static func create_heading(text: String, parent: Control = null) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_override("font", font_bold())
	label.add_theme_font_size_override("font_size", FONT_HEADING)
	label.add_theme_color_override("font_color", TEXT_PRIMARY)
	if parent:
		parent.add_child(label)
	return label

## Small uppercase caption above a section ("PLAYERS", "STATS"...)
static func create_caption(text: String, parent: Control = null) -> Label:
	var label = Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", font_black())
	label.add_theme_font_size_override("font_size", FONT_TINY)
	label.add_theme_color_override("font_color", TEXT_MUTED)
	if parent:
		parent.add_child(label)
	return label

static func create_label(text: String, parent: Control = null, size: int = FONT_NORMAL) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT_SECONDARY)
	if parent:
		parent.add_child(label)
	return label

## Colored chip ("READY", "HOST", "ACTIVE"...)
static func create_pill(text: String, color: Color, parent: Control = null) -> PanelContainer:
	var pill = PanelContainer.new()
	pill.add_theme_stylebox_override("panel", glass_box(Color(color, 0.18), Color(color, 0.55), CORNER_RADIUS_PILL, 10, 3))
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var label = Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", font_black())
	label.add_theme_font_size_override("font_size", FONT_TINY)
	label.add_theme_color_override("font_color", color.lightened(0.25))
	pill.add_child(label)
	if parent:
		parent.add_child(pill)
	return pill

# ---------------------------------------------------------------- buttons

static func create_button(text: String, parent: Control = null, size: Vector2 = Vector2(200, 50)) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", font_bold())
	button.add_theme_font_size_override("font_size", FONT_NORMAL)
	add_hover_animation(button)
	if parent:
		parent.add_child(button)
	return button

## Main call-to-action: glowing lime button with dark text
static func create_primary_button(text: String, parent: Control = null, size: Vector2 = Vector2(200, 56)) -> Button:
	var button = create_button(text, parent, size)
	_apply_accent_style(button, ACCENT_PRIMARY, TEXT_ON_ACCENT)
	button.add_theme_font_override("font", font_black())
	button.add_theme_font_size_override("font_size", FONT_HEADING)
	return button

static func create_danger_button(text: String, parent: Control = null, size: Vector2 = Vector2(200, 50)) -> Button:
	var button = create_button(text, parent, size)
	button.add_theme_stylebox_override("normal", glass_box(Color(ACCENT_DANGER, 0.12), Color(ACCENT_DANGER, 0.45)))
	button.add_theme_stylebox_override("hover", glow_box(Color(ACCENT_DANGER, 0.30), 0.35))
	button.add_theme_stylebox_override("pressed", glass_box(Color(ACCENT_DANGER, 0.2), ACCENT_DANGER))
	button.add_theme_color_override("font_color", ACCENT_DANGER.lightened(0.3))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	return button

static func _apply_accent_style(button: Button, color: Color, text_color: Color):
	button.add_theme_stylebox_override("normal", glow_box(color, 0.35))
	button.add_theme_stylebox_override("hover", glow_box(color.lightened(0.15), 0.6, CORNER_RADIUS_SMALL, 22))
	button.add_theme_stylebox_override("pressed", glow_box(color.darkened(0.12), 0.25))
	button.add_theme_stylebox_override("hover_pressed", glow_box(color.darkened(0.05), 0.4))
	button.add_theme_stylebox_override("disabled", glass_box(Color(color, 0.15), Color(color, 0.2)))
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_hover_pressed_color", text_color)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))

## Re-color an accent button at runtime (e.g. READY -> NOT READY)
static func set_accent(button: Button, color: Color, text_color: Color = TEXT_ON_ACCENT):
	_apply_accent_style(button, color, text_color)

## Toggle-style selectable card (character list etc.)
static func style_selectable(button: Button, selected: bool, accent: Color = ACCENT_PRIMARY):
	if selected:
		button.add_theme_stylebox_override("normal", glow_box(Color(accent, 0.22), 0.25, CORNER_RADIUS_SMALL, 10))
		button.add_theme_stylebox_override("hover", glow_box(Color(accent, 0.30), 0.35, CORNER_RADIUS_SMALL, 12))
	else:
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_stylebox_override("hover")

## Subtle scale bounce on hover / press
static func add_hover_animation(control: Control, hover_scale: float = 1.035):
	control.resized.connect(func(): control.pivot_offset = control.size / 2.0)
	control.mouse_entered.connect(func():
		if control is BaseButton and control.disabled:
			return
		_tween_scale(control, hover_scale, 0.12))
	control.mouse_exited.connect(func(): _tween_scale(control, 1.0, 0.15))
	if control is BaseButton:
		control.button_down.connect(func(): _tween_scale(control, 0.97, 0.06))
		control.button_up.connect(func(): _tween_scale(control, hover_scale if control.is_hovered() else 1.0, 0.1))

static func _tween_scale(control: Control, target: float, duration: float):
	if not control.is_inside_tree():
		return
	var tween = control.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE * target, duration)

# ---------------------------------------------------------------- inputs

static func create_line_edit(placeholder: String = "", parent: Control = null) -> LineEdit:
	var edit = LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(200, 46)
	edit.add_theme_font_size_override("font_size", FONT_NORMAL)
	if parent:
		parent.add_child(edit)
	return edit

static func create_slider(min_val: float, max_val: float, value: float, parent: Control = null) -> HSlider:
	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = (max_val - min_val) / 100.0
	slider.value = value
	slider.custom_minimum_size = Vector2(200, 24)
	if parent:
		parent.add_child(slider)
	return slider

static func create_checkbox(text: String, checked: bool = false, parent: Control = null) -> CheckButton:
	var check = CheckButton.new()
	check.text = text
	check.button_pressed = checked
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_font_size_override("font_size", FONT_NORMAL)
	if parent:
		parent.add_child(check)
	return check

## Labeled row with a value on the right: "Master Volume ........ 80%"
static func create_setting_row(text: String, parent: Control) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACING_MEDIUM)
	var label = create_label(text, row)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	return row

# ---------------------------------------------------------------- bars

static func create_progress_bar(max_val: float, value: float, color: Color, parent: Control = null) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.max_value = max_val
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(100, 10)
	set_bar_color(bar, color)
	if parent:
		parent.add_child(bar)
	return bar

static func set_bar_color(bar: ProgressBar, color: Color):
	var fill = glass_box(color, Color(1, 1, 1, 0.25), CORNER_RADIUS_PILL, 0, 0)
	fill.shadow_color = Color(color, 0.45)
	fill.shadow_size = 6
	bar.add_theme_stylebox_override("fill", fill)

## "Health  ██████░░  90" row for character stats
static func create_stat_row(stat_name: String, value: float, max_value: float, color: Color, parent: Control) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACING_MEDIUM)
	parent.add_child(row)

	var label = create_label(stat_name, row, FONT_SMALL)
	label.custom_minimum_size.x = 64

	var bar = create_progress_bar(max_value, value, color, row)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var value_label = Label.new()
	value_label.text = str(snappedf(value, 0.1)).trim_suffix(".0")
	value_label.custom_minimum_size.x = 36
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_override("font", font_black())
	value_label.add_theme_font_size_override("font_size", FONT_SMALL)
	row.add_child(value_label)
	return row

static func create_separator(parent: Control = null) -> HSeparator:
	var sep = HSeparator.new()
	if parent:
		parent.add_child(sep)
	return sep

static func create_spacer(expand: bool = true, parent: Control = null) -> Control:
	var spacer = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if parent:
		parent.add_child(spacer)
	return spacer

# ---------------------------------------------------------------- loading overlay

## Full-screen loading curtain with a spinner (used while the match map is prepared)
static func create_loading_overlay(text: String) -> Control:
	var overlay = Control.new()
	overlay.name = "LoadingOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	create_background(overlay)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card = create_panel(center, 28)
	var box = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", SPACING_MEDIUM)
	card.add_child(box)

	var spinner = Spinner.new()
	spinner.custom_minimum_size = Vector2(56, 56)
	spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(spinner)

	var label = create_heading(text, box)
	label.name = "LoadingText"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = 280
	return overlay

static func set_loading_text(overlay: Control, text: String):
	var label = overlay.find_child("LoadingText", true, false)
	if label:
		label.text = text
