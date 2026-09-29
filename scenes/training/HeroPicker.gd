## Training ground hero picker (Tab): every hero as a shop card (ParallaxCard), portraits come
## from ItemRenderer in what the hero wears. Clicking one reloads the arena with that hero
## (TrainingGround._switch_to). Esc / Tab close it; while open the game gets no input.
extends Control
class_name HeroPicker

signal picked(data: CharacterData)

const COLUMNS: int = 7

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("blocks_game_input")  # clicking a card must not fire
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var shade = ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	center.add_child(column)
	var title = UITheme.create_title("CHOOSE YOUR VEGGIE", column)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint = UITheme.create_label("Click a card to play it   ·   Tab / Esc  -  close", column, UITheme.FONT_NORMAL)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

	var pad = MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(side, 30)  # room for the hover zoom and the tilt
	column.add_child(pad)
	var grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	pad.add_child(grid)

	var current = ""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.selected_character:
		current = game_manager.selected_character.character_name
	var renderer = ItemRenderer.get_instance(get_tree())
	for data in CharacterRegistry.get_all():
		var hero_name: String = data.character_name
		var wear = PlayerProfile.equipped_for(hero_name)
		var card = ParallaxCard.new()
		card.card_size = Vector2(150, 208)
		card.title = hero_name
		card.subtitle = Cosmetics.TIER_NAMES[Cosmetics.tier_of(Cosmetics.hero_id(hero_name))]
		card.accent = data.color
		card.badge = tr("Playing") if hero_name == current else ""
		card.selected = hero_name == current
		card.live = ["hero", [hero_name, wear.skin, wear.hat]]
		card.pressed.connect(func(): picked.emit(data))
		grid.add_child(card)
		renderer.hero(hero_name, wear.skin, wear.hat, func(tex): if is_instance_valid(card): card.set_art(tex))

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)

func _input(event: InputEvent):
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB):
		get_viewport().set_input_as_handled()
		queue_free()
