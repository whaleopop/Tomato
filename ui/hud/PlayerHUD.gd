## Main player HUD: health (top-left), minimap (top-right), weapons (bottom-left),
## abilities (bottom-center), ammo (bottom-right), crosshair, alerts and the elimination screen.
extends Control
class_name PlayerHUD

var health_bar: HealthBar = null
var ability_bar: AbilityBar = null
var minimap: Minimap = null
var ammo_display: AmmoDisplay = null
var crosshair: Control = null
var weapon_slots_ui: HBoxContainer = null
var alive_label: Label = null
var alert_holder: CenterContainer = null
var death_screen: Control = null

var player: Player = null

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	health_bar = HealthBar.new()
	health_bar.name = "HealthBar"
	_place(health_bar, Control.PRESET_TOP_LEFT, Vector2(20, 20))
	add_child(health_bar)

	minimap = Minimap.new()
	minimap.name = "Minimap"
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -228
	minimap.offset_right = -20
	minimap.offset_top = 20
	minimap.offset_bottom = 228
	add_child(minimap)

	var alive_holder = PanelContainer.new()
	alive_holder.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.14), 99, 14, 4))
	alive_holder.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	alive_holder.offset_left = -228
	alive_holder.offset_right = -20
	alive_holder.offset_top = 236
	alive_holder.offset_bottom = 266
	alive_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(alive_holder)
	alive_label = UITheme.create_label("", alive_holder, UITheme.FONT_SMALL)
	alive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alive_label.add_theme_font_override("font", UITheme.font_black())

	ability_bar = AbilityBar.new()
	ability_bar.name = "AbilityBar"
	ability_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ability_bar.offset_left = -200
	ability_bar.offset_right = 200
	ability_bar.offset_top = -100
	ability_bar.offset_bottom = -22
	add_child(ability_bar)

	ammo_display = AmmoDisplay.new()
	ammo_display.name = "AmmoDisplay"
	ammo_display.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_display.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo_display.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ammo_display.offset_left = -230
	ammo_display.offset_right = -20
	ammo_display.offset_top = -130
	ammo_display.offset_bottom = -20
	add_child(ammo_display)

	_create_weapon_slots_ui()
	_create_crosshair()

	alert_holder = CenterContainer.new()
	alert_holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	alert_holder.grow_horizontal = Control.GROW_DIRECTION_BOTH  # stay centered as it grows
	alert_holder.offset_top = 96
	alert_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(alert_holder)

	_create_hidden_hint()

	for c in [health_bar, ammo_display]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_signal("match_ended"):
		network_manager.match_ended.connect(_on_match_ended)

func _place(control: Control, preset: int, offset: Vector2):
	control.set_anchors_preset(preset)
	control.position = offset

func setup(p_player: Player, hex_grid: HexGrid = null):
	player = p_player
	if not player:
		return

	var health = player.get_component("HealthComponent")
	if health:
		health_bar.setup(health)
		health.died.connect(_on_player_died)

	var ability_component = player.get_component("AbilityComponent")
	if ability_component:
		ability_bar.setup(ability_component)

	var combat = player.get_component("CombatComponent")
	var inventory = player.get_component("InventoryComponent")
	if combat:
		ammo_display.setup(combat, inventory)
	if inventory:
		inventory.weapon_equipped.connect(func(_w, _s): _update_weapon_slots_display(inventory))
		inventory.weapon_slot_changed.connect(func(_s): _update_weapon_slots_display(inventory))
		_update_weapon_slots_display(inventory)

	crosshair.player = player
	minimap.track(player)
	if hex_grid:
		minimap.setup_grid(hex_grid)

func _process(_delta: float):
	if player and is_instance_valid(player):
		minimap.update_player_position(player.global_position)
	_update_alive_count()
	_update_hidden_hint()

# ---------------------------------------------------------------- hidden in a bush

var hidden_hint: Control = null

func _create_hidden_hint():
	var holder = CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.offset_top = -152  # above the ability bar
	holder.offset_bottom = -112
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var pill = PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.05, 0.16, 0.08, 0.8), Color(UITheme.ACCENT_SUCCESS, 0.7), 99, 18, 6))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pill)
	var label = UITheme.create_label("HIDDEN IN A BUSH - shooting gives you away", pill, UITheme.FONT_SMALL)
	label.add_theme_color_override("font_color", UITheme.ACCENT_SUCCESS.lightened(0.35))
	hidden_hint = holder
	hidden_hint.visible = false

func _update_hidden_hint():
	var fog = get_tree().get_first_node_in_group("visibility_system") as VisibilitySystem
	var hidden = fog != null and fog.is_local_hidden() and death_screen == null
	if hidden_hint.visible != hidden:
		hidden_hint.visible = hidden

# ---------------------------------------------------------------- match end

var result_screen: Control = null

func _on_match_ended(winner_id: int, winner_name: String):
	if result_screen:
		return
	var i_won = player != null and is_instance_valid(player) and winner_id != 0 and player.entity_id == winner_id
	var winner_text = winner_name.to_upper() if winner_name != "" else "NOBODY"
	if death_screen:
		# Already eliminated: tell who took it
		death_screen.queue_free()
		death_screen = null
	result_screen = Control.new()
	result_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_screen.add_to_group("blocks_game_input")  # clicking the button must not fire
	add_child(result_screen)

	var dim = ColorRect.new()
	dim.color = Color(0.02, 0.08, 0.04, 0.35) if i_won else Color(0.05, 0.03, 0.1, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_screen.add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_screen.add_child(center)
	var card = UITheme.create_panel(center, 30)
	card.tint = UITheme.GLASS_TINT_DARK
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	var title = UITheme.create_title("VICTORY!" if i_won else "MATCH OVER", box)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", (UITheme.ACCENT_SUCCESS if i_won else UITheme.ACCENT_WARNING).lightened(0.25))
	var sub_text = "Last veggie standing - the island is yours!" if i_won else ("%s is the last one standing" % winner_text if winner_id != 0 else "Nobody survived the harvest")
	var sub = UITheme.create_label(sub_text, box)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var leave = UITheme.create_primary_button("BACK TO MENU", box, Vector2(300, 56))
	leave.pressed.connect(_on_leave_pressed)

	card.scale = Vector2(0.8, 0.8)
	card.resized.connect(func(): card.pivot_offset = card.size / 2.0)
	result_screen.modulate.a = 0.0
	var t = create_tween().set_parallel()
	t.tween_property(result_screen, "modulate:a", 1.0, 0.4)
	t.tween_property(card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if i_won and ScreenEffects.instance:
		ScreenEffects.flash(Color(1, 0.95, 0.6), 0.25, 0.4)

func _update_alive_count():
	var alive = 0
	# Remote clients don't have a copy of everyone (server-side fog): ask the synced state
	var scene = get_tree().current_scene
	var client_world = scene.get_node_or_null("ClientWorld") if scene else null
	if client_world and not client_world.is_host_view and not client_world.last_player_states.is_empty():
		alive = client_world.count_alive()
	else:
		for p in get_tree().get_nodes_in_group("players"):
			var h = p.get_component("HealthComponent") if p.has_method("get_component") else null
			if h and not h.is_dead:
				alive += 1
	alive_label.text = "%d  ALIVE" % alive

## Short banner under the top edge ("The edges are crumbling!")
func show_alert(text: String, color: Color = UITheme.ACCENT_WARNING):
	for child in alert_holder.get_children():
		child.queue_free()
	var pill = PanelContainer.new()
	var pill_box = UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.85), Color(color, 0.8), 99, 22, 8)
	pill_box.shadow_color = Color(color, 0.35)
	pill_box.shadow_size = 14
	pill.add_theme_stylebox_override("panel", pill_box)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_holder.add_child(pill)
	var label = UITheme.create_heading(text, pill)
	label.add_theme_color_override("font_color", color.lightened(0.3))

	pill.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(pill, "modulate:a", 1.0, 0.2)
	tween.tween_interval(3.0)
	tween.tween_property(pill, "modulate:a", 0.0, 0.6)
	tween.tween_callback(pill.queue_free)

func _on_player_died():
	if death_screen or result_screen:
		return
	death_screen = Control.new()
	death_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(death_screen)

	var dim = ColorRect.new()
	dim.color = Color(0.12, 0.0, 0.02, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_screen.add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_screen.add_child(center)

	var card = UITheme.create_panel(center, 30)
	card.tint = UITheme.GLASS_TINT_DARK
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	var title = UITheme.create_title("ELIMINATED", box)
	title.add_theme_color_override("font_color", UITheme.ACCENT_DANGER.lightened(0.2))
	var sub = UITheme.create_label("You got mashed. Better luck next harvest!", box)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var leave = UITheme.create_primary_button("BACK TO MENU", box, Vector2(300, 56))
	leave.pressed.connect(_on_leave_pressed)

	death_screen.modulate.a = 0.0
	create_tween().tween_property(death_screen, "modulate:a", 1.0, 0.5)

func _on_leave_pressed():
	# MainMenu stops the server/client when it opens
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")

# ---------------------------------------------------------------- crosshair

func _create_crosshair():
	crosshair = Crosshair.new()
	crosshair.name = "Crosshair"
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(crosshair)

class Crosshair extends Control:
	var player: Player = null

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta):
		queue_redraw()

	func _draw():
		if not player or not is_instance_valid(player):
			return
		var camera = get_viewport().get_camera_3d()
		if not camera:
			return

		var mouse_pos = get_viewport().get_mouse_position()
		var accent = UITheme.ACCENT_PRIMARY

		# Dashed aim line from the character to the cursor
		var start = camera.unproject_position(player.global_position + Vector3(0, 1.0, 0))
		var dir = (mouse_pos - start).normalized()
		var dist = start.distance_to(mouse_pos)
		var d = 26.0
		while d < dist - 22.0:
			draw_line(start + dir * d, start + dir * min(d + 7.0, dist - 22.0), Color(1, 1, 1, 0.35), 2.0, true)
			d += 14.0

		# Ring + ticks
		draw_arc(mouse_pos, 11.0, 0, TAU, 32, Color(0, 0, 0, 0.35), 4.0, true)
		draw_arc(mouse_pos, 11.0, 0, TAU, 32, Color(1, 1, 1, 0.9), 2.0, true)
		for v in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(mouse_pos + v * 15.0, mouse_pos + v * 21.0, Color(1, 1, 1, 0.9), 2.0, true)
		draw_circle(mouse_pos, 2.5, accent)

# ---------------------------------------------------------------- weapon slots

func _create_weapon_slots_ui():
	weapon_slots_ui = HBoxContainer.new()
	weapon_slots_ui.name = "WeaponSlots"
	weapon_slots_ui.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	weapon_slots_ui.offset_left = 20
	weapon_slots_ui.offset_right = 380
	weapon_slots_ui.offset_top = -98
	weapon_slots_ui.offset_bottom = -20
	weapon_slots_ui.add_theme_constant_override("separation", 8)
	weapon_slots_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(weapon_slots_ui)

	for i in range(5):
		weapon_slots_ui.add_child(_create_weapon_slot(i))

func _create_weapon_slot(index: int) -> PanelContainer:
	var slot = PanelContainer.new()
	slot.name = "WeaponSlot_%d" % (index + 1)
	slot.custom_minimum_size = Vector2(64, 78)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.1), 16, 6, 6))

	var box = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	slot.add_child(box)

	var number_label = UITheme.create_label(str(index + 1), box, UITheme.FONT_TINY)
	number_label.name = "NumberLabel"
	number_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	var icon = Panel.new()
	icon.name = "WeaponIcon"
	icon.custom_minimum_size = Vector2(30, 14)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)

	var name_label = UITheme.create_label("", box, 9)
	name_label.name = "WeaponName"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_font_override("font", UITheme.font_black())
	return slot

func _update_weapon_slots_display(inventory: InventoryComponent):
	for i in range(5):
		var slot_panel = weapon_slots_ui.get_node_or_null("WeaponSlot_%d" % (i + 1))
		if not slot_panel:
			continue

		var weapon = inventory.get_weapon_in_slot(i)
		var is_selected = i == inventory.current_weapon_slot and weapon != null
		var color = _get_weapon_color(weapon.weapon_type) if weapon else Color(1, 1, 1, 0.15)

		if is_selected:
			slot_panel.add_theme_stylebox_override("panel", UITheme.glow_box(Color(UITheme.ACCENT_SECONDARY, 0.22), 0.35, 16, 10))
		elif weapon:
			slot_panel.add_theme_stylebox_override("panel", UITheme.glass_box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.16), 16, 6, 6))
		else:
			slot_panel.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0, 0, 0, 0.25), Color(1, 1, 1, 0.07), 16, 6, 6))

		var icon = slot_panel.find_child("WeaponIcon", true, false) as Panel
		if icon:
			var icon_box = StyleBoxFlat.new()
			icon_box.bg_color = color
			icon_box.set_corner_radius_all(5)
			icon.add_theme_stylebox_override("panel", icon_box)

		var name_label = slot_panel.find_child("WeaponName", true, false) as Label
		if name_label:
			name_label.text = weapon.item_name.substr(0, 7).to_upper() if weapon else ""

func _get_weapon_color(weapon_type: RangedWeapon.WeaponType) -> Color:
	match weapon_type:
		RangedWeapon.WeaponType.PISTOL:
			return Color("9aa7c7")
		RangedWeapon.WeaponType.SHOTGUN:
			return Color("e0915a")
		RangedWeapon.WeaponType.SNIPER:
			return Color("6fd08c")
		RangedWeapon.WeaponType.RIFLE:
			return Color("7ab8ff")
		RangedWeapon.WeaponType.FLAMETHROWER:
			return Color("ff7a45")
		_:
			return Color(0.6, 0.6, 0.6)
