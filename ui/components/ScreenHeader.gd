## The top bar every menu screen shares (the main menu's look): a back chip, the brand and the
## screen's title (a small gold kicker over it) on the left, tabs after them (the main menu's
## navigation), the wallet (nickname over the coins) and icon chips on the right. HEIGHT tall,
## across the top of its parent: screens start their content at CONTENT_TOP.
##   var header = ScreenHeader.make(self, "SHOP", "Skins · hats · finishes")
##   header.back_pressed.connect(close)
## The wallet follows the profile by itself (Online.profile_changed); call update_coins() after
## a purchase made offline. add_settings_chip() opens the settings over the screen.
extends PanelContainer
class_name ScreenHeader

signal back_pressed

const HEIGHT: int = 72
const CONTENT_TOP: int = 92        # where a screen's content starts under the bar
const SIDE_MARGIN: int = 40
const SUBNAV_H: int = 46           # the fixed row a screen may keep under the bar (title / toolbar)

var row: HBoxContainer
var back_button: Button = null
var title_label: Label = null
var kicker_label: Label = null
var _title_divider: ColorRect = null
var _titles_box: VBoxContainer = null
var coins_label: Label = null
var name_label: Label = null
var right: HBoxContainer           # chips / pills before the wallet (add_right)
var wallet: PanelContainer
var _tabs: Array[Button] = []
var _tab_box: HBoxContainer
var _settings_layer: Control = null

## A header across the top of `parent`. Empty title: the brand alone (the main menu). has_title
## reserves the title / kicker layout (a bigger brand otherwise) even if `title` starts empty -
## MenuShell always passes true so later set_title() calls (switching screens) don't need to
## rebuild the bar; a screen that truly never has a title (the main menu) can still pass false.
static func make(parent: Control, title: String = "", kicker: String = "", back: bool = true, has_title: bool = true) -> ScreenHeader:
	var header = ScreenHeader.new()
	header._build(title, kicker, back, has_title)
	parent.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = HEIGHT
	return header

func _build(title: String, kicker: String, back: bool, has_title: bool) -> void:
	name = "ScreenHeader"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = HEIGHT
	var box = UITheme.glass_box(Color(0.03, 0.045, 0.09, 0.86), Color(1, 1, 1, 0.06), 0, SIDE_MARGIN, 0)
	box.border_width_left = 0
	box.border_width_right = 0
	box.border_width_top = 0
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 12
	add_theme_stylebox_override("panel", box)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	if back:
		back_button = UITheme.create_button("BACK", row, Vector2(118, 44))
		back_button.icon = UITheme.icon("chevron_left")
		back_button.expand_icon = true
		back_button.add_theme_constant_override("icon_max_width", 16)
		back_button.add_theme_constant_override("h_separation", 6)
		back_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		back_button.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0.85))
		back_button.add_theme_color_override("icon_hover_color", UITheme.GOLD)
		back_button.add_theme_color_override("icon_pressed_color", UITheme.GOLD)
		back_button.add_theme_font_override("font", UITheme.font_black())
		back_button.add_theme_font_size_override("font_size", 15)
		back_button.add_theme_stylebox_override("normal", UITheme.navy_box(UITheme.NAVY, Color(1, 1, 1, 0.12), 12, 14, 6))
		back_button.add_theme_stylebox_override("hover", UITheme.navy_box(UITheme.NAVY_HOVER, Color(UITheme.GOLD, 0.85), 12, 14, 6))
		back_button.add_theme_stylebox_override("pressed", UITheme.navy_box(UITheme.NAVY.darkened(0.2), Color(UITheme.GOLD, 1.0), 12, 14, 6))
		back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		back_button.pressed.connect(func(): back_pressed.emit())

	# The brand: just the wordmark, the main menu's own (no tagline - the bar is tight enough as is)
	var brand_row = HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 0)
	brand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(brand_row)
	var brand_name = UITheme.create_heading("ROYALTIM", brand_row)
	brand_name.add_theme_font_override("font", UITheme.font_black())
	brand_name.add_theme_font_size_override("font_size", 18 if has_title else 22)
	brand_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var brand_three = UITheme.create_heading("3", brand_row)
	brand_three.add_theme_font_override("font", UITheme.font_black())
	brand_three.add_theme_font_size_override("font_size", 18 if has_title else 22)
	brand_three.add_theme_color_override("font_color", UITheme.ACCENT_INFO)

	if has_title:
		_title_divider = ColorRect.new()
		_title_divider.color = Color(1, 1, 1, 0.12)
		_title_divider.custom_minimum_size = Vector2(1, 38)
		_title_divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_title_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_title_divider)
		_titles_box = VBoxContainer.new()
		_titles_box.alignment = BoxContainer.ALIGNMENT_CENTER
		_titles_box.add_theme_constant_override("separation", -4)
		_titles_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_titles_box)
		var titles = _titles_box
		kicker_label = UITheme.create_label(kicker, titles, 12)
		kicker_label.uppercase = true
		kicker_label.add_theme_font_override("font", UITheme.font_black())
		kicker_label.add_theme_color_override("font_color", UITheme.GOLD)
		kicker_label.visible = kicker != ""
		title_label = UITheme.create_heading(title, titles)
		title_label.uppercase = true
		title_label.add_theme_font_override("font", UITheme.font_black())
		title_label.add_theme_font_size_override("font_size", 26)
		title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		title_label.add_theme_constant_override("shadow_offset_y", 2)

	UITheme.create_spacer(false, row).custom_minimum_size.x = 18
	_tab_box = HBoxContainer.new()
	_tab_box.add_theme_constant_override("separation", 2)
	row.add_child(_tab_box)
	UITheme.create_spacer(false, row).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right = HBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(right)

	# The wallet: who you are over how many coins you have
	wallet = PanelContainer.new()
	wallet.add_theme_stylebox_override("panel", UITheme.navy_box(UITheme.NAVY, Color(UITheme.GOLD, 0.55), 12, 16, 4))
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wallet.custom_minimum_size.x = 200
	row.add_child(wallet)
	var lines = VBoxContainer.new()
	lines.add_theme_constant_override("separation", -4)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet.add_child(lines)
	var name_row = UITheme.create_icon_label("crown", "", lines, 15, Color.WHITE)
	name_label = name_row.get_meta("label")
	name_label.add_theme_font_override("font", UITheme.font_black())
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var coin_row = UITheme.create_icon_label("coin", "", lines, 17, Color(1.0, 0.85, 0.42))
	coins_label = coin_row.get_meta("label")
	coins_label.add_theme_font_override("font", UITheme.font_black())
	coins_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	update_coins()

func _ready():
	var online = get_node_or_null("/root/Online")
	if online and online.has_signal("profile_changed"):
		online.profile_changed.connect(update_coins)

## The wallet from PlayerProfile (call after a purchase)
func update_coins() -> void:
	if not coins_label:
		return
	var who = PlayerProfile.nickname
	name_label.text = (who if who != "" else tr("Player"))
	var f = name_label.get_theme_font("font")
	name_label.custom_minimum_size.x = minf(180.0, ceilf(f.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x) + 2.0)
	coins_label.text = UITheme.format_coins(PlayerProfile.get_coins())

## The screen's title / kicker after building (a mode name that arrives later...)
## "" hides the title / kicker and the divider that separates them from the brand (MAIN's own tab).
## title / kicker are translated as source keys unless raw_title / raw_kicker say they are already
## display text (a nickname, or a kicker someone already ran through tr() and formatted).
func set_title(title: String, kicker: String = "", raw_title: bool = false, raw_kicker: bool = false) -> void:
	if title_label:
		# A Label only re-translates its `text` on its own when it is still entering the tree;
		# MenuShell's header is persistent, so later calls land on a Label already in the tree
		# and need tr() by hand, or the text would stick in English (ui/components/MenuShell.gd).
		title_label.text = title if raw_title or title == "" else tr(title)
	if kicker_label:
		kicker_label.text = kicker if raw_kicker or kicker == "" else tr(kicker)
		kicker_label.visible = kicker != ""
	if _titles_box:
		_titles_box.visible = title != ""
	if _title_divider:
		_title_divider.visible = title != ""

## A tab in the bar (the main menu's navigation). The active one is underlined and does nothing.
func add_tab(text: String, callback: Callable, active: bool = false) -> Button:
	var tab = Button.new()
	tab.text = text
	tab.flat = true
	tab.custom_minimum_size.x = 132
	tab.focus_mode = Control.FOCUS_NONE
	tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tab.add_theme_font_override("font", UITheme.font_black())
	tab.add_theme_font_size_override("font_size", UITheme.FONT_NORMAL)
	tab.add_theme_color_override("font_hover_color", UITheme.GOLD)
	tab.add_theme_color_override("font_pressed_color", UITheme.GOLD)
	tab.pressed.connect(func():
		Sfx.ui("ui_click")
		if not tab.get_meta("active", false) and callback.is_valid():
			callback.call())
	tab.mouse_entered.connect(func(): Sfx.ui("ui_hover"))
	_tab_box.add_child(tab)
	_tabs.append(tab)
	_style_tab(tab, active)
	return tab

func set_active_tab(index: int) -> void:
	for i in _tabs.size():
		_style_tab(_tabs[i], i == index)

func _style_tab(tab: Button, active: bool) -> void:
	tab.set_meta("active", active)
	tab.add_theme_color_override("font_color", Color.WHITE if active else UITheme.TEXT_SECONDARY)
	var line = StyleBoxFlat.new()
	line.bg_color = Color(0, 0, 0, 0)
	line.border_width_bottom = 3
	line.border_color = UITheme.ACCENT_INFO if active else Color(0, 0, 0, 0)
	line.content_margin_left = 16
	line.content_margin_right = 16
	line.content_margin_top = 10
	line.content_margin_bottom = 10
	var hover = line.duplicate()
	if not active:
		hover.border_color = Color(UITheme.GOLD, 0.5)
	for state in ["normal", "pressed", "focus"]:
		tab.add_theme_stylebox_override(state, line)
	tab.add_theme_stylebox_override("hover", hover)

## A control on the right, before the wallet (a status pill, a counter...)
func add_right(control: Control) -> Control:
	right.add_child(control)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return control

## A square icon chip after the wallet (friends, settings). icon: a text glyph or a Texture2D
## (UITheme.icon_texture("name")).
func add_icon_chip(icon, callback: Callable, tooltip: String = "") -> Button:
	var chip = UITheme.create_icon_chip(icon, row)
	chip.tooltip_text = tooltip
	chip.pressed.connect(callback)
	return chip

## The gear: settings over this screen. `reload_on_language`: rebuild the scene when the language
## changed (texts formatted in code); off where a reload would restart something (a queue).
func add_settings_chip(reload_on_language: bool = true) -> Button:
	return add_icon_chip(UITheme.icon_texture("settings"), func(): open_settings(get_parent(), reload_on_language), "Settings")

## Settings (SettingsPanel) over `host`, dimmed behind; Esc or the panel's close button closes it
static func open_settings(host: Control, reload_on_language: bool = true) -> Control:
	var layer = _SettingsLayer.new()
	layer.reload_on_language = reload_on_language
	host.add_child(layer)
	return layer

class _SettingsLayer extends Control:
	var reload_on_language: bool = true
	var _language_dirty: bool = false

	func _ready():
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_to_group("blocks_game_input")
		var dim = ColorRect.new()
		dim.color = Color(0, 0, 0, 0.45)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var center = CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var panel = SettingsPanel.new()
		center.add_child(panel)
		panel.closed.connect(close)
		panel.language_changed.connect(func(): _language_dirty = true)

	func close():
		if is_queued_for_deletion():
			return
		GameSettings.save()
		var tree = get_tree() if is_inside_tree() else null
		queue_free()
		if _language_dirty and reload_on_language and tree:
			tree.reload_current_scene()  # rebuild the texts formatted in code

	func _unhandled_input(event: InputEvent):
		if event.is_action_pressed("pause"):
			close()
			get_viewport().set_input_as_handled()
