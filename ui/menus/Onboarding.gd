## First start: make a profile (a nickname - local, there are no online accounts yet) and pick
## any PlayerProfile.STARTER_PICKS heroes from the whole roster, shown as cards. The rest are bought
## in the shop with coins from matches. Shown by the main menu until both are done.
extends Control
class_name Onboarding

signal finished

var _center: CenterContainer
var _name_edit: LineEdit
var _error: Label

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("blocks_game_input")
	UITheme.create_background(self)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	if not PlayerProfile.has_account():
		_show_register()
	else:
		_show_starters()

func _clear():
	for child in _center.get_children():
		child.queue_free()

# ---------------------------------------------------------------- nickname

func _show_register():
	_clear()
	var card = UITheme.create_panel(_center, 30)
	card.custom_minimum_size.x = 520
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	var title = UITheme.create_title("WELCOME TO ROYALTIM", box)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub = UITheme.create_label("Pick a name: everyone in the match will see it", box)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("Your name")
	_name_edit.max_length = PlayerProfile.NAME_MAX
	_name_edit.custom_minimum_size.y = 52
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.add_theme_font_size_override("font_size", 22)
	box.add_child(_name_edit)
	_name_edit.text_submitted.connect(func(_t): _register())
	_error = UITheme.create_label("", box, UITheme.FONT_SMALL)
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.add_theme_color_override("font_color", UITheme.ACCENT_DANGER)
	var go = UITheme.create_primary_button("CREATE PROFILE", box, Vector2(0, 56))
	go.pressed.connect(_register)
	var note = UITheme.create_label("The profile lives on this computer: coins, heroes and cosmetics are saved here.", box, UITheme.FONT_TINY)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_name_edit.grab_focus.call_deferred()

func _register():
	var problem = PlayerProfile.check_name(_name_edit.text)
	if problem != "":
		_error.text = tr(problem)
		return
	PlayerProfile.register(_name_edit.text)
	_show_starters()

# ---------------------------------------------------------------- the first heroes

var _picked: Array = []            # hero names, in the order they were clicked
var _cards: Dictionary = {}        # hero -> ParallaxCard
var _count_label: Label
var _info_label: Label
var _take: Button

func _show_starters():
	if not PlayerProfile.needs_starter():
		_done()
		return
	_clear()
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_center.add_child(box)
	var title = UITheme.create_title(tr("%s, pick %d heroes") % [PlayerProfile.nickname, PlayerProfile.STARTER_PICKS], box)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub = UITheme.create_label("They are yours for free. The rest can be bought in the shop with coins from matches", box)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var grid = GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(grid)
	var renderer = ItemRenderer.get_instance(get_tree())
	for data in CharacterRegistry.get_all():
		var hero = data.character_name
		var card = ParallaxCard.new()
		card.card_size = Vector2(150, 208)
		card.title = hero
		card.subtitle = tr("%d HP  ·  speed %.1f") % [int(data.base_health), data.base_speed]
		card.accent = data.color
		card.live = ["hero", [hero, "classic", "no_hat"]]
		grid.add_child(card)
		card.refresh()
		_cards[hero] = card
		renderer.hero(hero, "classic", "no_hat", func(tex): if is_instance_valid(card): card.set_art(tex))
		card.pressed.connect(_toggle.bind(hero))
	_info_label = UITheme.create_label("", box, UITheme.FONT_SMALL)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(900, 44)
	_info_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	_count_label = UITheme.create_heading("", row)
	_take = UITheme.create_primary_button("TAKE THESE HEROES", row, Vector2(320, 56))
	_take.pressed.connect(_confirm)
	_refresh()

## Click a card: it joins the pick (the oldest one drops out when there are too many), or leaves it
func _toggle(hero: String):
	if hero in _picked:
		_picked.erase(hero)
	else:
		_picked.append(hero)
		if _picked.size() > PlayerProfile.STARTER_PICKS:
			_picked.pop_front()
	var data = CharacterRegistry.get_by_name(hero)
	_info_label.text = tr(hero) + "  ·  " + tr(data.active_ability.ability_name) + ": " + tr(data.active_ability.description) 		+ "  ·  " + tr(data.passive_ability.ability_name) + ": " + tr(data.passive_ability.description)
	_refresh()

func _refresh():
	for hero in _cards:
		var card: ParallaxCard = _cards[hero]
		card.selected = hero in _picked
		card.badge = ("%d" % (_picked.find(hero) + 1)) if card.selected else ""
		card.refresh()
	_count_label.text = tr("Picked %d of %d") % [_picked.size(), PlayerProfile.STARTER_PICKS]
	_take.disabled = _picked.size() != PlayerProfile.STARTER_PICKS

func _confirm():
	if _picked.size() != PlayerProfile.STARTER_PICKS:
		return
	PlayerProfile.choose_starters(_picked)
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.selected_character = CharacterRegistry.get_by_name(_picked[0])
	ScreenEffects.flash(Color(1, 0.9, 0.5), 0.2, 0.2)
	_done()

func _done():
	finished.emit()
	var t = create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.tween_callback(queue_free)
