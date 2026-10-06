## Pause menu (Esc), laid out like the main menu: a column on the left over a dark wash - a gold
## kicker (the mode), the big title, the golden CONTINUE, navy rows (settings) and the red ones
## (leave the match, quit the game) - and your hero's card on the right, the live model turning
## under the mouse (built when the menu opens, freed when it closes: no live model all match).
## In multiplayer the game keeps running underneath: pausing the tree would freeze the server
## (host) or the network processing (client) for everybody.
extends Control
class_name PauseMenu

const COLUMN_WIDTH: int = 420
const HERO_CARD_SIZE := Vector2(230, 320)

var resume_button: Button = null
var settings_button: Button = null
var main_menu_button: Button = null
var quit_button: Button = null

var is_paused: bool = false
var pause_tree: bool = true  # Set to false by GameSceneController when networked
var settings_panel: SettingsPanel = null
var main_panel: Control = null           # the column and the hero card (hidden while the settings show)
var _center: CenterContainer = null      # the settings panel sits in it
var _hero_slot: VBoxContainer = null     # right side: "YOUR HERO" over the card
var _hero_card: ParallaxCard = null

func _ready():
	visible = false
	add_to_group("blocks_game_input")  # PlayerInputHandler ignores the game while we're open
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_create_ui()

func _create_ui():
	# A dark wash over the game, deeper on the left under the column (the main menu's shade)
	var dim = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.5)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)
	var shade = TextureRect.new()
	var grad = GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0.02, 0.03, 0.07, 0.88))
	grad.gradient.set_color(1, Color(0.02, 0.03, 0.07, 0.0))
	grad.fill_to = Vector2(1, 0)
	shade.texture = grad
	shade.set_anchors_and_offsets_preset(PRESET_LEFT_WIDE)
	shade.offset_right = 820
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	main_panel = UITheme.create_screen_margin(self, 56)
	main_panel.add_theme_constant_override("margin_top", 48)
	main_panel.add_theme_constant_override("margin_bottom", 48)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_panel.add_child(row)

	# ---- Left: kicker, title, the actions
	var column = VBoxContainer.new()
	column.custom_minimum_size.x = COLUMN_WIDTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	row.add_child(column)

	var training = _training()
	var kicker = UITheme.create_label("TRAINING GROUND" if training else String(GameModes.info(GameModes.current()).name), column, 14)
	kicker.uppercase = true
	kicker.add_theme_font_override("font", UITheme.font_black())
	kicker.add_theme_color_override("font_color", UITheme.GOLD)
	var title = UITheme.create_hero_title("PAUSED", column)
	title.uppercase = true
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 6)
	var hint = UITheme.create_label("The game is paused" if pause_tree else "The match keeps going in multiplayer", column, UITheme.FONT_SUBTITLE)
	hint.add_theme_color_override("font_color", Color.WHITE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	UITheme.create_spacer(false, column).custom_minimum_size.y = 10

	var buttons = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)

	resume_button = UITheme.create_play_button("RESUME", "BACK TO THE GAME", buttons)
	resume_button.pressed.connect(_on_resume_pressed)
	UITheme.create_spacer(false, buttons).custom_minimum_size.y = 2

	settings_button = UITheme.create_menu_row("SETTINGS", "SOUND · CONTROLS · GRAPHICS", buttons)
	settings_button.pressed.connect(_on_settings_pressed)

	UITheme.create_spacer(false, buttons).custom_minimum_size.y = 8
	main_menu_button = UITheme.create_menu_row("LEAVE TRAINING" if training else "LEAVE MATCH", "BACK TO THE MAIN MENU", buttons, true)
	main_menu_button.pressed.connect(_on_main_menu_pressed)

	quit_button = UITheme.create_menu_row("QUIT GAME", "", buttons, true)
	quit_button.pressed.connect(_on_quit_pressed)

	var footer = UITheme.create_label("Esc  -  back to the game", column, UITheme.FONT_SMALL)
	footer.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	# ---- Right: your hero's card, where the main menu has the hero on its stand
	var right = CenterContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	_hero_slot = VBoxContainer.new()
	_hero_slot.add_theme_constant_override("separation", 12)
	_hero_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_hero_slot)

	# The settings panel (over the wash, centered) takes the column's place while it is open
	_center = CenterContainer.new()
	_center.set_anchors_preset(PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

func _training() -> bool:
	var gm = get_node_or_null("/root/GameManager")
	return gm != null and gm.training_mode

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		if settings_panel and settings_panel.visible:
			_hide_settings()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause():
	is_paused = not is_paused
	visible = is_paused
	if pause_tree:
		get_tree().paused = is_paused
	if is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if get_parent():
			get_parent().move_child(self, -1)  # over the HUD bits added after us (training notes)
		main_panel.visible = true
		if settings_panel:
			settings_panel.visible = false
		_show_hero_card()
		_animate_in()
	else:
		_free_hero_card()

## Fade in, the column sliding in from the left like a page
func _animate_in() -> void:
	modulate.a = 0.0
	main_panel.position.x = -28.0
	var t = create_tween().set_parallel()
	t.tween_property(self, "modulate:a", 1.0, 0.14)
	t.tween_property(main_panel, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## The local hero (the HUD's player, else the chosen one) on a card with its level and rank
func _show_hero_card() -> void:
	_free_hero_card()
	var data: CharacterData = null
	var hud = get_tree().get_first_node_in_group("player_hud")
	if hud and "player" in hud and hud.player and is_instance_valid(hud.player) and hud.player.character_data:
		data = hud.player.character_data
	var gm = get_node_or_null("/root/GameManager")
	if data == null and gm and gm.selected_character:
		data = gm.selected_character
	if data == null:
		return
	var hero_name = data.character_name
	var wear = PlayerProfile.equipped_for(hero_name)
	var kicker = UITheme.create_label("YOUR HERO", _hero_slot, 14)
	kicker.uppercase = true
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_font_override("font", UITheme.font_black())
	kicker.add_theme_color_override("font_color", UITheme.GOLD)
	_hero_card = ParallaxCard.new()
	_hero_card.card_size = HERO_CARD_SIZE
	_hero_card.title = hero_name
	_hero_card.subtitle = Cosmetics.TIER_NAMES[Cosmetics.tier_of(Cosmetics.hero_id(hero_name))]
	_hero_card.accent = data.color
	_hero_card.live = ["hero", [hero_name, wear.skin, wear.hat]]
	_hero_card.always_live = true  # only while the menu is open: freed on close
	_hero_card.show_hero_mastery(hero_name)
	if _hero_card.mastery >= 0:
		_hero_card.subtitle = Mastery.tier_name(_hero_card.mastery)
	_hero_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hero_slot.add_child(_hero_card)
	var card = _hero_card
	ItemRenderer.get_instance(get_tree()).hero(hero_name, wear.skin, wear.hat, func(tex): if is_instance_valid(card): card.set_art(tex))

func _free_hero_card() -> void:
	_hero_card = null
	if _hero_slot:
		for c in _hero_slot.get_children():
			c.queue_free()

func _on_resume_pressed():
	toggle_pause()

func _on_settings_pressed():
	if settings_panel == null:
		settings_panel = SettingsPanel.new()
		if "tint" in settings_panel:
			settings_panel.tint = UITheme.GLASS_TINT_DARK
		settings_panel.closed.connect(_hide_settings)
		_center.add_child(settings_panel)
	main_panel.visible = false
	settings_panel.visible = true

func _hide_settings():
	if settings_panel:
		settings_panel.visible = false
		GameSettings.save()
	main_panel.visible = true

func _on_main_menu_pressed():
	get_tree().paused = false
	is_paused = false
	_free_hero_card()

	# MainMenu tears the server/client down on entry (after the fade, so the map
	# does not vanish mid-transition)
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")

func _on_quit_pressed():
	get_tree().quit()
