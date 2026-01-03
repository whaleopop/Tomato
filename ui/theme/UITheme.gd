## Unified UI theme and style constants for all menus
## Use this class to create consistent UI across the game
extends RefCounted
class_name UITheme

# Colors
const BG_DARK = Color(0.08, 0.08, 0.12)
const BG_MEDIUM = Color(0.12, 0.12, 0.18)
const BG_LIGHT = Color(0.18, 0.18, 0.25)
const BG_PANEL = Color(0.15, 0.15, 0.22, 0.95)

const TEXT_PRIMARY = Color(1.0, 0.95, 0.85)
const TEXT_SECONDARY = Color(0.7, 0.7, 0.75)
const TEXT_TITLE = Color(1.0, 0.9, 0.6)
const TEXT_ACCENT = Color(0.4, 0.8, 1.0)

const ACCENT_PRIMARY = Color(0.3, 0.7, 1.0)
const ACCENT_SECONDARY = Color(1.0, 0.7, 0.2)
const ACCENT_SUCCESS = Color(0.3, 0.85, 0.4)
const ACCENT_DANGER = Color(1.0, 0.35, 0.35)

const BUTTON_NORMAL = Color(0.2, 0.2, 0.28)
const BUTTON_HOVER = Color(0.28, 0.28, 0.38)
const BUTTON_PRESSED = Color(0.15, 0.15, 0.2)

# Font sizes
const FONT_TITLE = 36
const FONT_SUBTITLE = 24
const FONT_HEADING = 20
const FONT_NORMAL = 16
const FONT_SMALL = 14

# Spacing
const MARGIN_LARGE = 40
const MARGIN_MEDIUM = 20
const MARGIN_SMALL = 10
const SPACING_LARGE = 20
const SPACING_MEDIUM = 15
const SPACING_SMALL = 10

# Corner radius
const CORNER_RADIUS = 8
const CORNER_RADIUS_SMALL = 4

## Create styled background
static func create_background(parent: Control) -> ColorRect:
	var bg = ColorRect.new()
	bg.color = BG_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	return bg

## Create a styled panel
static func create_panel(parent: Control = null) -> PanelContainer:
	var panel = PanelContainer.new()

	var style = StyleBoxFlat.new()
	style.bg_color = BG_PANEL
	style.corner_radius_top_left = CORNER_RADIUS
	style.corner_radius_top_right = CORNER_RADIUS
	style.corner_radius_bottom_left = CORNER_RADIUS
	style.corner_radius_bottom_right = CORNER_RADIUS
	style.content_margin_left = MARGIN_MEDIUM
	style.content_margin_right = MARGIN_MEDIUM
	style.content_margin_top = MARGIN_MEDIUM
	style.content_margin_bottom = MARGIN_MEDIUM
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.4, 0.5)

	panel.add_theme_stylebox_override("panel", style)

	if parent:
		parent.add_child(panel)
	return panel

## Create a styled title label
static func create_title(text: String, parent: Control = null) -> Label:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_TITLE)
	label.add_theme_color_override("font_color", TEXT_TITLE)

	if parent:
		parent.add_child(label)
	return label

## Create a styled subtitle label
static func create_subtitle(text: String, parent: Control = null) -> Label:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SUBTITLE)
	label.add_theme_color_override("font_color", TEXT_PRIMARY)

	if parent:
		parent.add_child(label)
	return label

## Create a styled heading label
static func create_heading(text: String, parent: Control = null) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_HEADING)
	label.add_theme_color_override("font_color", TEXT_PRIMARY)

	if parent:
		parent.add_child(label)
	return label

## Create a styled text label
static func create_label(text: String, parent: Control = null, size: int = FONT_NORMAL) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT_SECONDARY)

	if parent:
		parent.add_child(label)
	return label

## Create a styled button
static func create_button(text: String, parent: Control = null, size: Vector2 = Vector2(200, 50)) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.add_theme_font_size_override("font_size", FONT_NORMAL)

	# Normal style
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = BUTTON_NORMAL
	normal_style.corner_radius_top_left = CORNER_RADIUS_SMALL
	normal_style.corner_radius_top_right = CORNER_RADIUS_SMALL
	normal_style.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	normal_style.corner_radius_bottom_right = CORNER_RADIUS_SMALL
	button.add_theme_stylebox_override("normal", normal_style)

	# Hover style
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = BUTTON_HOVER
	hover_style.corner_radius_top_left = CORNER_RADIUS_SMALL
	hover_style.corner_radius_top_right = CORNER_RADIUS_SMALL
	hover_style.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	hover_style.corner_radius_bottom_right = CORNER_RADIUS_SMALL
	hover_style.border_width_left = 2
	hover_style.border_width_right = 2
	hover_style.border_width_top = 2
	hover_style.border_width_bottom = 2
	hover_style.border_color = ACCENT_PRIMARY
	button.add_theme_stylebox_override("hover", hover_style)

	# Pressed style
	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = BUTTON_PRESSED
	pressed_style.corner_radius_top_left = CORNER_RADIUS_SMALL
	pressed_style.corner_radius_top_right = CORNER_RADIUS_SMALL
	pressed_style.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	pressed_style.corner_radius_bottom_right = CORNER_RADIUS_SMALL
	button.add_theme_stylebox_override("pressed", pressed_style)

	if parent:
		parent.add_child(button)
	return button

## Create a primary action button (highlighted)
static func create_primary_button(text: String, parent: Control = null, size: Vector2 = Vector2(200, 55)) -> Button:
	var button = create_button(text, parent, size)
	button.add_theme_font_size_override("font_size", FONT_HEADING)

	# Override with accent color
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.2, 0.45, 0.7)
	normal_style.corner_radius_top_left = CORNER_RADIUS_SMALL
	normal_style.corner_radius_top_right = CORNER_RADIUS_SMALL
	normal_style.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	normal_style.corner_radius_bottom_right = CORNER_RADIUS_SMALL
	button.add_theme_stylebox_override("normal", normal_style)

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.55, 0.85)
	hover_style.corner_radius_top_left = CORNER_RADIUS_SMALL
	hover_style.corner_radius_top_right = CORNER_RADIUS_SMALL
	hover_style.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	hover_style.corner_radius_bottom_right = CORNER_RADIUS_SMALL
	button.add_theme_stylebox_override("hover", hover_style)

	return button

## Create a danger button (red)
static func create_danger_button(text: String, parent: Control = null, size: Vector2 = Vector2(200, 50)) -> Button:
	var button = create_button(text, parent, size)

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.5, 0.15, 0.15)
	normal_style.corner_radius_top_left = CORNER_RADIUS_SMALL
	normal_style.corner_radius_top_right = CORNER_RADIUS_SMALL
	normal_style.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	normal_style.corner_radius_bottom_right = CORNER_RADIUS_SMALL
	button.add_theme_stylebox_override("normal", normal_style)

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.7, 0.2, 0.2)
	hover_style.corner_radius_top_left = CORNER_RADIUS_SMALL
	hover_style.corner_radius_top_right = CORNER_RADIUS_SMALL
	hover_style.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	hover_style.corner_radius_bottom_right = CORNER_RADIUS_SMALL
	button.add_theme_stylebox_override("hover", hover_style)

	return button

## Create a styled text input
static func create_line_edit(placeholder: String = "", parent: Control = null) -> LineEdit:
	var edit = LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(200, 40)
	edit.add_theme_font_size_override("font_size", FONT_NORMAL)

	var style = StyleBoxFlat.new()
	style.bg_color = BG_MEDIUM
	style.corner_radius_top_left = CORNER_RADIUS_SMALL
	style.corner_radius_top_right = CORNER_RADIUS_SMALL
	style.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	style.corner_radius_bottom_right = CORNER_RADIUS_SMALL
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	edit.add_theme_stylebox_override("normal", style)

	var focus_style = style.duplicate()
	focus_style.border_color = ACCENT_PRIMARY
	edit.add_theme_stylebox_override("focus", focus_style)

	if parent:
		parent.add_child(edit)
	return edit

## Create a styled slider
static func create_slider(min_val: float, max_val: float, value: float, parent: Control = null) -> HSlider:
	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = value
	slider.custom_minimum_size = Vector2(200, 20)

	if parent:
		parent.add_child(slider)
	return slider

## Create a styled checkbox
static func create_checkbox(text: String, checked: bool = false, parent: Control = null) -> CheckButton:
	var check = CheckButton.new()
	check.text = text
	check.button_pressed = checked
	check.add_theme_font_size_override("font_size", FONT_NORMAL)

	if parent:
		parent.add_child(check)
	return check

## Create a styled progress bar
static func create_progress_bar(max_val: float, value: float, color: Color, parent: Control = null) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.max_value = max_val
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(100, 20)

	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.corner_radius_top_left = CORNER_RADIUS_SMALL
	fill_style.corner_radius_top_right = CORNER_RADIUS_SMALL
	fill_style.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	fill_style.corner_radius_bottom_right = CORNER_RADIUS_SMALL
	bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = BG_MEDIUM
	bg_style.corner_radius_top_left = CORNER_RADIUS_SMALL
	bg_style.corner_radius_top_right = CORNER_RADIUS_SMALL
	bg_style.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	bg_style.corner_radius_bottom_right = CORNER_RADIUS_SMALL
	bar.add_theme_stylebox_override("background", bg_style)

	if parent:
		parent.add_child(bar)
	return bar

## Create a horizontal separator
static func create_separator(parent: Control = null) -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 10)

	if parent:
		parent.add_child(sep)
	return sep

## Create a spacer control
static func create_spacer(expand: bool = true, parent: Control = null) -> Control:
	var spacer = Control.new()
	if expand:
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if parent:
		parent.add_child(spacer)
	return spacer

## Create centered container for menu content
static func create_centered_container(parent: Control, width: int = 400) -> VBoxContainer:
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size.x = width
	vbox.add_theme_constant_override("separation", SPACING_MEDIUM)
	center.add_child(vbox)

	return vbox
