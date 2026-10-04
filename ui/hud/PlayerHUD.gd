## Main player HUD: health (top-left), minimap (top-right), weapons (bottom-left),
## abilities (bottom-center), ammo (bottom-right), crosshair, alerts and the elimination screen.
extends Control
class_name PlayerHUD

var health_bar: HealthBar = null
var ability_bar: AbilityBar = null
var minimap: Minimap = null
var ammo_display: AmmoDisplay = null
var crosshair: Control = null
var aim_overlay: AimOverlay = null        # gun reach, ability areas, where the hero is
var damage_indicator: DamageIndicator = null  # where hits came from
var weapon_slots_ui: HBoxContainer = null
var alive_label: Label = null
var alert_holder: CenterContainer = null
var alert_list: VBoxContainer = null  # a few alerts stack (a zone step and its supply drop come together)
var death_screen: Control = null
var kill_feed: KillFeed = null      # every elimination, top right
var consumable_bar: ConsumableBar = null  # health packs / shields and their use progress
var spectator: Spectator = null     # after we are out: watch the killer / the survivors
var _death_info: Dictionary = {}    # our own elimination: {killer_id, info} (NetworkManager.player_killed)
var _killer_slot: Control = null    # the death card's killer part, filled when the kill arrives
var _known_names: Dictionary = {}   # player id -> nickname, from the kills so far (the spectator bar)

var player: Player = null

var _hero_card_small: ParallaxCard = null  # permanent small card bottom-left

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("player_hud")  # CameraController's view switch shows an alert

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

	kill_feed = KillFeed.new()
	kill_feed.name = "KillFeed"
	kill_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kill_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	kill_feed.offset_left = -460
	kill_feed.offset_right = -20
	kill_feed.offset_top = 276
	add_child(kill_feed)

	ability_bar = AbilityBar.new()
	ability_bar.name = "AbilityBar"
	ability_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ability_bar.offset_left = -200
	ability_bar.offset_right = 200
	ability_bar.offset_top = -100
	ability_bar.offset_bottom = -22
	add_child(ability_bar)

	consumable_bar = ConsumableBar.new()
	consumable_bar.name = "ConsumableBar"
	consumable_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	consumable_bar.offset_left = -160
	consumable_bar.offset_right = 160
	consumable_bar.offset_top = -196
	consumable_bar.offset_bottom = -106
	add_child(consumable_bar)

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
	_create_hero_card_small()

	alert_holder = CenterContainer.new()
	alert_holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	alert_holder.grow_horizontal = Control.GROW_DIRECTION_BOTH  # stay centered as it grows
	alert_holder.offset_top = 104
	alert_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(alert_holder)
	alert_list = VBoxContainer.new()
	alert_list.alignment = BoxContainer.ALIGNMENT_BEGIN
	alert_list.add_theme_constant_override("separation", 6)
	alert_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_holder.add_child(alert_list)

	_create_hidden_hint()
	_create_zone_timer()
	_create_event_timer()
	_create_buff_pill()

	for c in [health_bar, ammo_display]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_signal("match_ended"):
		network_manager.match_ended.connect(_on_match_ended)
	if network_manager and network_manager.has_signal("zone_changed"):
		network_manager.zone_changed.connect(_on_zone_changed)
	if network_manager and network_manager.has_signal("map_event"):
		network_manager.map_event.connect(_on_map_event)
	if network_manager and network_manager.has_signal("player_killed"):
		network_manager.player_killed.connect(_on_player_killed)

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
		health.revived.connect(_on_player_revived)

	var ability_component = player.get_component("AbilityComponent")
	if ability_component:
		ability_bar.setup(ability_component)

	var combat = player.get_component("CombatComponent")
	var inventory = player.get_component("InventoryComponent")
	if inventory:
		consumable_bar.setup(inventory)
	if combat:
		ammo_display.setup(combat, inventory)
	if inventory:
		inventory.weapon_equipped.connect(func(_w, _s): _update_weapon_slots_display(inventory))
		inventory.weapon_slot_changed.connect(func(_s): _update_weapon_slots_display(inventory))
		_update_weapon_slots_display(inventory)

	crosshair.player = player
	kill_feed.my_id = player.entity_id
	aim_overlay.player = player
	damage_indicator.track(player)
	minimap.track(player)
	if hex_grid:
		minimap.setup_grid(hex_grid)
	_setup_hero_card(player)
	_animate_hero_card_intro(player)

func _process(delta: float):
	if player and is_instance_valid(player):
		minimap.update_player_position(player.global_position)
	_update_alive_count()
	_update_hidden_hint()
	_update_zone_timer(delta)
	_update_event_timer(delta)
	_update_buff_pill()

# ---------------------------------------------------------------- zone countdown

var zone_pill: PanelContainer = null
var zone_label: Label = null
var _zone_kind: String = ""
var _zone_left: float = 0.0

func _create_zone_timer():
	var holder = CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.offset_top = 22
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	zone_pill = PanelContainer.new()
	zone_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_pill.visible = false
	holder.add_child(zone_pill)
	zone_label = UITheme.create_heading("", zone_pill)
	zone_label.add_theme_font_size_override("font_size", 17)

## A step of the zone (NetworkManager.zone_changed, on the host and on clients)
func _on_zone_changed(kind: String, _coords: Array, seconds: float, center: Vector2i, radius: int):
	_zone_kind = kind
	_zone_left = seconds
	minimap.set_zone(kind, center, radius)
	match kind:
		"warn", "core_warn":
			Sfx.ui("zone_warn")
		"rise":
			Sfx.own("rumble", -6.0)
	match kind:
		"warn":
			show_alert(tr("The zone is closing in - leave the glowing edge!"), UITheme.ACCENT_WARNING)
		"burn", "core_burn":
			show_alert(tr("The edge is on fire!") if kind == "burn" else tr("The last patch is on fire!"), UITheme.ACCENT_DANGER)
		"rise":
			show_alert(tr("Mountains are rising!"), Color(0.85, 0.78, 0.7))
		"core_warn":
			show_alert(tr("Nowhere left to go: the core will catch fire!"), UITheme.ACCENT_DANGER)
	_update_zone_timer(0.0)

func _update_zone_timer(delta: float):
	if not zone_pill or _zone_kind == "":
		return
	_zone_left = max(0.0, _zone_left - delta)
	var secs = int(ceil(_zone_left))
	var text = ""
	var color = UITheme.ACCENT_INFO
	match _zone_kind:
		"warn":
			text = tr("Zone moves in %d s") % secs
			color = UITheme.ACCENT_WARNING
		"burn":
			text = tr("The edge burns: %d s") % secs
			color = UITheme.ACCENT_DANGER
		"rise":
			text = tr("Next zone step in %d s") % secs
		"core_warn", "calm":
			text = tr("The core catches fire in %d s") % secs
			color = UITheme.ACCENT_DANGER if _zone_kind == "core_warn" else UITheme.ACCENT_WARNING
		"core_burn":
			text = tr("The core burns: %d s") % secs
			color = UITheme.ACCENT_DANGER
	var urgent = _zone_kind in ["burn", "core_burn"] or (_zone_kind in ["warn", "core_warn"] and _zone_left < 5.0)
	var box = UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.8), Color(color, 0.85), 99, 20, 6)
	box.shadow_color = Color(color, 0.25 + (0.35 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 110.0)) if urgent else 0.0))
	box.shadow_size = 12
	zone_pill.add_theme_stylebox_override("panel", box)
	zone_label.text = text
	zone_label.add_theme_color_override("font_color", color.lightened(0.35))
	zone_pill.visible = text != ""

# ---------------------------------------------------------------- map events

var event_pill: PanelContainer = null
var event_label: Label = null
var _event_kind: String = ""
var _event_left: float = 0.0
var _event_style: String = ""

func _create_event_timer():
	var holder = CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.offset_top = 62  # under the zone countdown
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	event_pill = PanelContainer.new()
	event_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_pill.visible = false
	holder.add_child(event_pill)
	event_label = UITheme.create_heading("", event_pill)
	event_label.add_theme_font_size_override("font_size", 15)

## A map event (NetworkManager.map_event): alert, a countdown while it runs, minimap hints
func _on_map_event(kind: String, data: Dictionary, elapsed: float):
	var fresh = elapsed < 1.5  # a late joiner catching up gets no alerts for old news
	var seconds := 0.0
	match kind:
		"meteors":
			var delays: Array = data.get("delays", [])
			seconds = (float(delays.max()) if not delays.is_empty() else 3.0) - elapsed
			if fresh:
				show_alert(tr("Meteor shower! Get out of the red circles"), UITheme.ACCENT_DANGER)
		"quake":
			seconds = float(data.get("seconds", 5.0)) - elapsed
			if fresh:
				show_alert(tr("Earthquake! Walls fall, aim shakes"), Color(0.92, 0.76, 0.52))
		"night":
			seconds = float(data.get("seconds", 25.0)) - elapsed
			_event_style = String(data.get("style", "night"))
			if fresh:
				show_alert(tr("Night falls: everyone sees half as far") if _event_style == "night" else tr("Thick fog: everyone sees half as far"), Color(0.62, 0.72, 1.0))
		"flood":
			if fresh:
				show_alert(tr("Flood! The shores are going under"), Color(0.4, 0.75, 1.0))
		"rift":
			seconds = float(data.get("warn", 10.0)) + float(data.get("burn", 3.0)) - elapsed
			if fresh:
				show_alert(tr("The island splits - cross the glowing crack!"), UITheme.ACCENT_WARNING)
		"harvest":
			var bonus = int(data.get("bonus", 0))
			seconds = float(data.get("grow", 10.0)) - elapsed
			if fresh:
				show_alert(tr("A rare bonus is growing: %s") % tr(MapEvents.harvest_name(bonus)), MapEvents.harvest_color(bonus))
		"zone_drop":
			if fresh:
				show_alert(tr("Supply drop into the next zone!"), LootContainer.RICH_COLOR)
		"center_shift":
			seconds = float(data.get("seconds", 10.0)) - elapsed
			minimap.set_zone_shift(data.get("center", Vector2i.ZERO), int(data.get("radius", 1)), seconds)
			if fresh:
				show_alert(tr("The final zone is moving!"), UITheme.ACCENT_WARNING)
	if seconds > 0.0:
		_event_kind = kind
		_event_left = seconds
		_update_event_timer(0.0)

func _update_event_timer(delta: float):
	if not event_pill:
		return
	_event_left = max(0.0, _event_left - delta)
	if _event_left <= 0.0:
		event_pill.visible = false
		return
	var secs = int(ceil(_event_left))
	var text = ""
	var color = UITheme.ACCENT_WARNING
	match _event_kind:
		"meteors":
			text = tr("Meteors: %d s") % secs
			color = UITheme.ACCENT_DANGER
		"quake":
			text = tr("Earthquake: %d s") % secs
			color = Color(0.92, 0.76, 0.52)
		"night":
			text = (tr("Night: %d s") if _event_style == "night" else tr("Fog: %d s")) % secs
			color = Color(0.62, 0.72, 1.0)
		"rift":
			text = tr("The rift rises in %d s") % secs
		"harvest":
			text = tr("The bonus ripens in %d s") % secs
			color = UITheme.ACCENT_SUCCESS
		"center_shift":
			text = tr("The zone center moves in %d s") % secs
	var box = UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.78), Color(color, 0.8), 99, 16, 5)
	event_pill.add_theme_stylebox_override("panel", box)
	event_label.text = text
	event_label.add_theme_color_override("font_color", color.lightened(0.35))
	event_pill.visible = text != ""

# ---------------------------------------------------------------- harvest bonus

var buff_pill: PanelContainer = null
var buff_label: Label = null

func _create_buff_pill():
	var holder = CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.offset_top = -196  # above the bush hint
	holder.offset_bottom = -156
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	buff_pill = PanelContainer.new()
	buff_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buff_pill.visible = false
	holder.add_child(buff_pill)
	buff_label = UITheme.create_label("", buff_pill, UITheme.FONT_SMALL)
	buff_label.add_theme_font_override("font", UITheme.font_black())

func _update_buff_pill():
	if not buff_pill:
		return
	var left = 0.0
	if player and is_instance_valid(player):
		left = (int(player.get_meta("harvest_until", 0)) - Time.get_ticks_msec()) / 1000.0
	if left <= 0.0:
		_show_status_pill()
		return
	var bonus = int(player.get_meta("harvest_bonus", 0))
	var color = MapEvents.harvest_color(bonus)
	var secs = int(ceil(left))
	match bonus:
		MapEvents.Harvest.SPEED:
			buff_label.text = tr("Speed +%d%%: %d s") % [roundi((MapEvents.HARVEST_SPEED - 1.0) * 100.0), secs]
		MapEvents.Harvest.DAMAGE:
			buff_label.text = tr("Damage +%d%%: %d s") % [roundi((MapEvents.HARVEST_DAMAGE - 1.0) * 100.0), secs]
		_:
			buff_label.text = tr("Full shield!")
	buff_label.add_theme_color_override("font_color", color.lightened(0.4))
	var box = UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.8), Color(color, 0.85), 99, 18, 6)
	box.shadow_color = Color(color, 0.3)
	box.shadow_size = 10
	buff_pill.add_theme_stylebox_override("panel", box)
	buff_pill.visible = true

## No bonus running: what an ability did to us (StatusComponent), if anything
func _show_status_pill():
	var status = player.get_component("StatusComponent") if player and is_instance_valid(player) else null
	var text = ""
	var color = UITheme.ACCENT_WARNING
	if status:
		if status.is_stunned():
			text = tr("Stunned!")
			color = Color(1.0, 0.9, 0.35)
		elif status.has("blind"):
			text = tr("Blinded: you can hardly see")
			color = Color(0.75, 0.7, 0.95)
		elif status.is_stealthed():
			text = tr("Unseen - a shot gives you away")
			color = Color(0.72, 0.55, 1.0)
		elif status.has("slow"):
			text = tr("Slowed")
			color = UITheme.ACCENT_INFO
	# Otherwise: what the ground under us does (BiomeRules)
	var movement = player.get_component("MovementComponent") if text == "" and player and is_instance_valid(player) else null
	if movement and movement.is_grounded:
		var info = BiomeRules.describe(movement.terrain_biome)
		if not info.is_empty():
			text = tr(info[0]) + ": " + info[1]
			color = info[2]
	if text == "":
		buff_pill.visible = false
		return
	buff_label.text = text
	buff_label.add_theme_color_override("font_color", color.lightened(0.35))
	buff_pill.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.8), Color(color, 0.85), 99, 18, 6))
	buff_pill.visible = true

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
	var title_text_override = ""
	# Team modes: winner_id -1 - team
	if winner_id < 0 and player and is_instance_valid(player) and player.has_meta("team"):
		i_won = int(player.get_meta("team")) == -1 - winner_id
	Sfx.ui("victory" if i_won else "defeat")
	var winner_text = winner_name.to_upper() if winner_name != "" else tr("NOBODY")
	if death_screen:
		# Already eliminated: tell who took it
		death_screen.queue_free()
		death_screen = null
	if spectator:
		spectator.visible = false
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

	var sub_text = "Last veggie standing - the island is yours!" if i_won else (tr("%s is the last one standing") % winner_text if winner_id != 0 else "Nobody survived the harvest")
	match GameModes.current():
		GameModes.SURVIVORS:
			var parts = winner_name.split("|")
			title_text_override = "THE WEEDS WON"
			if parts.size() >= 3:
				sub_text = tr("You held out %s: wave %s, %s weeds felled") % [parts[0], parts[1], parts[2]]
		GameModes.CTF:
			if winner_id < 0:
				sub_text = tr("%s takes the match") % tr(winner_name)
				title_text_override = "VICTORY!" if i_won else "DEFEAT"
			else:
				sub_text = "A draw"
		GameModes.KOTH:
			if winner_id > 0:
				sub_text = "You ruled the hill!" if i_won else tr("%s ruled the hill") % winner_text
	var title = UITheme.create_title(title_text_override if title_text_override != "" else ("VICTORY!" if i_won else "MATCH OVER"), box)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", (UITheme.ACCENT_SUCCESS if i_won else UITheme.ACCENT_WARNING).lightened(0.25))
	var sub = UITheme.create_label(sub_text, box)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_row(box, i_won)
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
	alive_label.text = tr("%d  ALIVE") % alive

## Short banner under the top edge ("The edges are crumbling!"); up to three stack
func show_alert(text: String, color: Color = UITheme.ACCENT_WARNING):
	var shown = alert_list.get_children().filter(func(c): return not c.is_queued_for_deletion())
	if shown.size() >= 3:
		shown[0].queue_free()
	var pill = PanelContainer.new()
	var pill_box = UITheme.glass_box(Color(0.05, 0.07, 0.12, 0.85), Color(color, 0.8), 99, 22, 8)
	pill_box.shadow_color = Color(color, 0.35)
	pill_box.shadow_size = 14
	pill.add_theme_stylebox_override("panel", pill_box)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	alert_list.add_child(pill)
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
	if GameModes.respawns(GameModes.current()):
		_show_respawn_countdown()
		return
	death_screen = Control.new()
	death_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(death_screen)

	var dim = ColorRect.new()
	dim.color = Color(0.12, 0.0, 0.02, 0.3)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_screen.add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_screen.add_child(center)

	var card = UITheme.create_panel(center, 30)
	card.tint = UITheme.GLASS_TINT_DARK
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	card.add_child(row)
	# Who took us out: their hero card and how they stand (filled by _fill_killer_card)
	_killer_slot = VBoxContainer.new()
	_killer_slot.add_theme_constant_override("separation", 10)
	row.add_child(_killer_slot)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = 340
	row.add_child(box)
	var title = UITheme.create_title("ELIMINATED", box)
	title.add_theme_color_override("font_color", UITheme.ACCENT_DANGER.lightened(0.2))
	var sub = UITheme.create_label("You got mashed. Better luck next harvest!", box)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_row(box, false)

	var watch = UITheme.create_primary_button("SPECTATE", box, Vector2(300, 56))
	watch.pressed.connect(_start_spectating)
	var leave = UITheme.create_button("BACK TO MENU", box, Vector2(300, 50))
	leave.pressed.connect(_on_leave_pressed)

	_fill_killer_card()
	# The camera goes to whoever did it right away; the bar comes with SPECTATE
	spectator = Spectator.new()
	spectator.name = "Spectator"
	spectator.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	spectator.grow_horizontal = Control.GROW_DIRECTION_BOTH
	spectator.grow_vertical = Control.GROW_DIRECTION_BEGIN
	spectator.offset_bottom = -24
	spectator.visible = false
	add_child(spectator)
	spectator.leave_pressed.connect(_on_leave_pressed)
	spectator._names = _known_names.duplicate()
	spectator.start(player, int(_death_info.get("killer_id", 0)))
	for c in [ability_bar, crosshair, aim_overlay, weapon_slots_ui, consumable_bar]:
		if c:
			c.visible = false
	if ammo_display:
		ammo_display.modulate.a = 0.0  # it shows itself again on every update

	death_screen.modulate.a = 0.0
	create_tween().tween_property(death_screen, "modulate:a", 1.0, 0.5)

## Respawning modes: a short countdown instead of the elimination card
var _respawn_left: float = 0.0
func _show_respawn_countdown():
	death_screen = Control.new()
	death_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(death_screen)
	var dim = ColorRect.new()
	dim.color = Color(0.15, 0.0, 0.02, 0.28)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_screen.add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_screen.add_child(center)
	var box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	var title = UITheme.create_title("DOWN!", box)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UITheme.ACCENT_DANGER.lightened(0.2))
	var count = UITheme.create_heading("", box)
	count.name = "Count"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_left = float(GameModes.info(GameModes.current()).respawn)
	var t = create_tween().set_loops(int(ceil(_respawn_left)))
	count.text = tr("Back in %d s") % int(ceil(_respawn_left))
	t.tween_interval(1.0)
	t.tween_callback(func():
		_respawn_left -= 1.0
		if is_instance_valid(count):
			count.text = tr("Back in %d s") % int(max(ceil(_respawn_left), 0)))

## Back in the fight (respawning modes): the countdown goes, the camera comes back to us
func _on_player_revived():
	if death_screen and is_instance_valid(death_screen):
		death_screen.queue_free()
	death_screen = null
	for c in [ability_bar, crosshair, aim_overlay, weapon_slots_ui, consumable_bar]:
		if c:
			c.visible = true
	if ammo_display:
		ammo_display.modulate.a = 1.0
	var cam = get_viewport().get_camera_3d()
	if cam and cam.has_method("set_target") and player:
		cam.set_target(player)

func _start_spectating():
	if death_screen:
		var t = create_tween()
		t.tween_property(death_screen, "modulate:a", 0.0, 0.25)
		t.tween_callback(func(): if death_screen: death_screen.visible = false)
	if spectator:
		spectator.visible = true

## Someone went down (NetworkManager.player_killed): if it was us, remember who did it
func _on_player_killed(victim_id: int, killer_id: int, info: Dictionary):
	if info.has("victim_name"):
		_known_names[victim_id] = String(info["victim_name"])
	if killer_id != 0 and info.has("killer_name"):
		_known_names[killer_id] = String(info["killer_name"])
	if player and is_instance_valid(player) and killer_id == player.entity_id and victim_id != killer_id:
		Sfx.ui("kill")
	if not player or not is_instance_valid(player) or victim_id != player.entity_id:
		return
	Sfx.ui("death")
	_death_info = {"killer_id": killer_id, "info": info}
	_fill_killer_card()
	if spectator and killer_id != 0:
		var killer = spectator._player_by_id(killer_id)
		if killer and spectator._alive(killer):
			spectator.follow(killer)

func _fill_killer_card():
	if not is_instance_valid(_killer_slot) or _death_info.is_empty():
		return
	for c in _killer_slot.get_children():
		c.queue_free()
	var killer_id = int(_death_info.get("killer_id", 0))
	var info: Dictionary = _death_info.get("info", {})
	if killer_id == 0:
		if info.has("npc"):
			var weed = String(info["npc"])
			UITheme.create_caption("Eliminated by", _killer_slot).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var who = UITheme.create_heading(weed, _killer_slot)
			who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			who.add_theme_color_override("font_color", Weed.KINDS.get(weed, {}).get("color", Color.WHITE).lightened(0.2))
			var note = UITheme.create_label("A weed. Watch the bushes.", _killer_slot, UITheme.FONT_SMALL)
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			note.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
			return
		var lbl = UITheme.create_heading("The island got you", _killer_slot)
		lbl.add_theme_color_override("font_color", UITheme.ACCENT_WARNING)
		return
	var hero_name = String(info.get("killer_hero", ""))
	var hero: CharacterData = CharacterRegistry.get_by_name(hero_name) if hero_name != "" else null
	var wear: Dictionary = info.get("killer_wear", {})
	var cap = UITheme.create_caption("Eliminated by", _killer_slot)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if hero:
		var skin = String(wear.get("skin", ""))
		var hat = String(wear.get("hat", ""))
		var hero_card = ParallaxCard.new()
		hero_card.title = hero.character_name
		hero_card.subtitle = Cosmetics.name_of(skin) if skin != "" else ""
		hero_card.accent = hero.color
		hero_card.badge = String(info.get("killer_name", ""))
		hero_card.live = ["hero", [hero.character_name, skin, hat]]
		hero_card.show_wear_mastery(wear)  # the killer's level and rank come with what they wear
		hero_card.always_live = true
		hero_card.custom_minimum_size = hero_card.card_size
		_killer_slot.add_child(hero_card)
		ItemRenderer.get_instance(get_tree()).hero(hero.character_name, skin, hat, func(tex): if is_instance_valid(hero_card): hero_card.set_art(tex))
	var name_lbl = UITheme.create_heading(String(info.get("killer_name", "")), _killer_slot)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", KillFeed.hero_color(hero_name))
	var facts: Array = []
	var gun = KillFeed.weapon_name(int(info.get("weapon", -1)))
	if gun != "":
		facts.append(tr("with %s") % tr(gun))
	if info.has("killer_health"):
		facts.append(tr("%d / %d HP left") % [int(info["killer_health"]), int(info.get("killer_max_health", 0))])
	facts.append(tr("Kills: %d") % int(info.get("killer_kills", 0)))
	for f in facts:
		var l = UITheme.create_label(f, _killer_slot, UITheme.FONT_SMALL)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

# ---------------------------------------------------------------- coins

var _rewarded: bool = false

## Coins for the match (once: at elimination or at the end), shown on the card
func _reward_row(box: Control, won: bool) -> void:
	if _rewarded or not _is_real_match():
		return
	_rewarded = true
	var stats = _my_stats()
	if won:
		stats["place"] = 1
	var lines = PlayerProfile.match_reward(stats)
	var total = 0
	var table = GridContainer.new()
	table.columns = 3
	table.add_theme_constant_override("h_separation", 22)
	table.add_theme_constant_override("v_separation", 2)
	table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(table)
	for line in lines:
		total += int(line[2])
		UITheme.create_label(line[0], table, UITheme.FONT_SMALL).add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
		UITheme.create_label(line[1], table, UITheme.FONT_SMALL)
		var coins_label = UITheme.create_label("+%d" % int(line[2]), table, UITheme.FONT_SMALL)
		coins_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	PlayerProfile.add_coins(total)
	Sfx.ui("coins")
	var pill = UITheme.create_pill(tr("+%d coins") % total, Color(1.0, 0.8, 0.3), box)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mastery_rows(box, stats)

## Mastery XP for the hero and the guns used (Mastery.gd): bars, level-ups and what got unlocked
func _mastery_rows(box: Control, stats: Dictionary) -> void:
	var hero = player.character_data.character_name if player and is_instance_valid(player) and player.character_data else ""
	var report = PlayerProfile.add_match_xp(hero, stats)
	var rows: Array = []
	if report.has("hero"):
		rows.append([tr(hero), report.hero])
	var guns: Array = report.weapons.keys()
	guns.sort_custom(func(a, b): return report.weapons[a][2] > report.weapons[b][2])
	for t in guns.slice(0, 3):
		rows.append([tr(RangedWeapon.create_weapon(t).item_name), report.weapons[t]])
	if rows.is_empty():
		return
	UITheme.create_separator(box)
	for r in rows:
		var before: Dictionary = r[1][0]
		var after: Dictionary = r[1][1]
		var line = HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		box.add_child(line)
		var name_label = UITheme.create_label(r[0], line, UITheme.FONT_SMALL)
		name_label.custom_minimum_size.x = 130
		var lvl_text = tr("Lv %d") % after.level if before.level == after.level else tr("Lv %d → %d") % [before.level, after.level]
		var lvl = UITheme.create_label(lvl_text, line, UITheme.FONT_SMALL)
		lvl.custom_minimum_size.x = 92
		lvl.add_theme_font_override("font", UITheme.font_black())
		lvl.add_theme_color_override("font_color", Mastery.tier_color(after.tier).lightened(0.2) if after.tier >= 0 else UITheme.TEXT_PRIMARY)
		var bar = UITheme.create_progress_bar(float(after.need), float(after.need if after.max else after.into), Mastery.tier_color(after.tier) if after.tier >= 0 else UITheme.ACCENT_INFO, line)
		bar.custom_minimum_size = Vector2(150, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var xp = UITheme.create_label("+%d XP" % int(r[1][2]), line, UITheme.FONT_SMALL)
		xp.add_theme_color_override("font_color", UITheme.ACCENT_INFO.lightened(0.3))
	for u in report.unlocked:
		var rank: int = u[1]
		var unlock = UITheme.create_pill(tr("Unlocked: %s — %s") % [tr(u[0]), tr(Mastery.TIER_NAMES[rank])], Mastery.tier_color(rank), box)
		unlock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func _is_real_match() -> bool:
	var network_manager = get_node_or_null("/root/NetworkManager")
	return network_manager != null and (network_manager.is_server() or network_manager.game_client != null)

## How our match went: the server counts it (ServerPlayer), clients read it from the state
func _my_stats() -> Dictionary:
	if not player or not is_instance_valid(player):
		return {}
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_server and network_manager.game_server.players.has(player.entity_id):
		var sp = network_manager.game_server.players[player.entity_id]
		var t = sp.alive_time if sp.place > 0 else network_manager.game_server.match_time()
		var st = sp.stats()
		st["time"] = int(t)
		return st
	var scene = get_tree().current_scene
	var client_world = scene.get_node_or_null("ClientWorld") if scene else null
	if client_world:
		return client_world.last_player_states.get(player.entity_id, {}).get("stats", {}).duplicate()
	return {}

func _on_leave_pressed():
	# MainMenu stops the server/client when it opens
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")

# ---------------------------------------------------------------- crosshair

func _create_crosshair():
	damage_indicator = DamageIndicator.new()
	damage_indicator.name = "DamageIndicator"
	damage_indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(damage_indicator)
	aim_overlay = AimOverlay.new()
	aim_overlay.name = "AimOverlay"
	aim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(aim_overlay)
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

		var mouse_pos = CameraController.aim_screen_point(get_viewport())
		# The gun's own reticle (fire_mode); an ability being aimed; red past the gun's reach
		# (the aim line and range circle are AimOverlay's)
		var handler = player.get_node_or_null("InputHandler") as PlayerInputHandler
		var combat = player.get_component("CombatComponent")
		var weapon: RangedWeapon = combat.equipped_ranged_weapon if combat else null
		var mode = weapon.fire_mode if weapon else "single"
		if handler and handler.aiming_ability >= 0:
			mode = "ability"
		var col = Color(1, 1, 1, 0.92)
		var far = mode != "ability" and AimOverlay.out_of_range(player)
		if far:
			col = AimOverlay.OUT_OF_RANGE
		var shadow = Color(0, 0, 0, 0.35)
		var accent = UITheme.ACCENT_PRIMARY

		# An earthquake (MapEvents) widens and shakes it
		var wobble = MapEvents.spread_factor - 1.0
		var grow = 1.0 + wobble * 0.35
		if wobble > 0.0:
			mouse_pos += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * wobble
		var p = mouse_pos
		match mode:
			"pierce":  # sniper / marksman: a fine cross with a gap and a dot
				for v in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(p + v * 7.0, p + v * 24.0, shadow, 4.0, true)
					draw_line(p + v * 7.0, p + v * 24.0, col, 1.6, true)
				draw_arc(p, 30.0, 0, TAU, 48, Color(col, 0.35), 1.2, true)
				draw_circle(p, 2.0, accent)
			"spread":  # shotguns: four wide brackets, as wide as the spread
				var angle = weapon.spread_angle if weapon else 25.0
				var r = (12.0 + angle * 0.7) * grow
				for k in 4:
					var m = TAU * k / 4.0 + PI / 4.0
					draw_arc(p, r, m - 0.42, m + 0.42, 10, shadow, 5.0, true)
					draw_arc(p, r, m - 0.42, m + 0.42, 10, col, 2.4, true)
				draw_circle(p, 2.5, accent)
			"flame":  # flamethrower: a chevron and a soft ring
				draw_arc(p, 16.0 * grow, 0, TAU, 32, Color(1.0, 0.6, 0.3, 0.35), 5.0, true)
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -9), p + Vector2(8, 6), p + Vector2(-8, 6)]), Color(1.0, 0.65, 0.3, 0.9))
			"lob":  # grenade launcher: a dashed landing circle and a cross
				var r2 = 15.0 * grow
				for k in 12:
					var a0 = TAU * k / 12.0
					draw_arc(p, r2, a0, a0 + TAU / 24.0, 4, col, 2.4, true)
				draw_line(p + Vector2(-6, 0), p + Vector2(6, 0), col, 2.0, true)
				draw_line(p + Vector2(0, -6), p + Vector2(0, 6), col, 2.0, true)
			"ability":  # an ability is being aimed: a diamond in the hero's color
				var hc = player.character_data.color.lightened(0.3) if player.character_data else UITheme.ACCENT_SECONDARY
				var d = 13.0
				var pts = PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)])
				draw_polyline(pts, shadow, 5.0, true)
				draw_polyline(pts, hc, 2.5, true)
				draw_circle(p, 3.0, hc)
			_:  # single shots: ring + ticks
				var r3 = 11.0 * grow
				draw_arc(p, r3, 0, TAU, 32, shadow, 4.0, true)
				draw_arc(p, r3, 0, TAU, 32, col, 2.0, true)
				for v in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(p + v * (r3 + 4.0), p + v * (r3 + 10.0), col, 2.0, true)
				draw_circle(p, 2.5, accent)
		if far:  # past the gun's reach: a small cross over it
			draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), col, 2.0, true)
			draw_line(p + Vector2(-5, 5), p + Vector2(5, -5), col, 2.0, true)

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
	slot.custom_minimum_size = Vector2(80, 78)  # room for "ПИСТОЛЕТ"
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
	# The gun's own picture (ItemRenderer, in its finish); the color bar stands in until it's there
	var pic = TextureRect.new()
	pic.name = "WeaponPic"
	pic.custom_minimum_size = Vector2(66, 30)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.visible = false
	box.add_child(pic)

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
			var glow = UITheme.glow_box(Color(UITheme.ACCENT_SECONDARY, 0.22), 0.35, 16, 10)
			glow.set_content_margin_all(6)  # same as the other slots: the name needs the width
			slot_panel.add_theme_stylebox_override("panel", glow)
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
		var pic = slot_panel.find_child("WeaponPic", true, false) as TextureRect
		if pic:
			pic.visible = false
			if icon:
				icon.visible = true
			if weapon:
				pic.set_meta("weapon", weapon)
				ItemRenderer.get_instance(get_tree()).icon_for(weapon, func(tex):
					if is_instance_valid(pic) and pic.get_meta("weapon", null) == weapon:
						pic.texture = tex
						pic.visible = true
						if is_instance_valid(icon):
							icon.visible = false)
			else:
				pic.set_meta("weapon", null)

		var name_label = slot_panel.find_child("WeaponName", true, false) as Label
		if name_label:
			name_label.text = tr(weapon.item_name, "short").substr(0, 9).to_upper() if weapon else ""

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
		RangedWeapon.WeaponType.SMG:
			return Color("f2a65a")
		RangedWeapon.WeaponType.HAND_CANNON:
			return Color("ff8f6b")
		RangedWeapon.WeaponType.MARKSMAN:
			return Color("f5d76e")
		RangedWeapon.WeaponType.MINIGUN:
			return Color("5fd3a6")
		RangedWeapon.WeaponType.DOUBLE_BARREL:
			return Color("63d6b0")
		RangedWeapon.WeaponType.JAM_BLASTER:
			return Color("b48cff")
		RangedWeapon.WeaponType.LAUNCHER:
			return Color("ffd24a")
		_:
			return Color(0.6, 0.6, 0.6)

# ---------------------------------------------------------------- hero card

func _create_hero_card_small() -> void:
	_hero_card_small = ParallaxCard.new()
	_hero_card_small.card_size = Vector2(110, 153)
	_hero_card_small.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hero_card_small.offset_left = 20
	_hero_card_small.offset_bottom = -108  # just above the weapon slots row
	_hero_card_small.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_card_small.visible = false
	add_child(_hero_card_small)

func _setup_hero_card(p: Player) -> void:
	if not _hero_card_small or not p:
		return
	var data: CharacterData = p.get_meta("character_data", null) if p.has_meta("character_data") else null
	if not data and p.has_method("get_component"):
		pass  # data lives on Player directly after setup_character
	# Player stores it as player.character_data after setup_character
	if "character_data" in p:
		data = p.character_data
	if not data:
		return
	var wear = PlayerProfile.equipped_for(data.character_name)
	_hero_card_small.title = tr(data.character_name)
	_hero_card_small.subtitle = Cosmetics.TIER_NAMES[Cosmetics.tier_of(Cosmetics.hero_id(data.character_name))]
	_hero_card_small.accent = data.color
	_hero_card_small.live = ["hero", [data.character_name, wear.skin, wear.hat]]
	_hero_card_small.show_hero_mastery(data.character_name)
	if _hero_card_small.mastery >= 0:
		_hero_card_small.subtitle = Mastery.tier_name(_hero_card_small.mastery)
	_hero_card_small.always_live = true
	_hero_card_small.refresh()
	_hero_card_small.visible = true

func _animate_hero_card_intro(p: Player) -> void:
	if not p:
		return
	var data: CharacterData = p.character_data if "character_data" in p else null
	if not data:
		return
	var wear = PlayerProfile.equipped_for(data.character_name)

	# Big card in the center for 2.5 seconds, then shrinks to the corner
	var big = ParallaxCard.new()
	big.card_size = Vector2(240, 334)
	big.title = tr(data.character_name)
	big.subtitle = Cosmetics.TIER_NAMES[Cosmetics.tier_of(Cosmetics.hero_id(data.character_name))]
	big.accent = data.color
	big.live = ["hero", [data.character_name, wear.skin, wear.hat]]
	big.show_hero_mastery(data.character_name)
	if big.mastery >= 0:
		big.subtitle = Mastery.tier_name(big.mastery)
	big.always_live = true
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.set_anchors_preset(Control.PRESET_CENTER)
	big.offset_left = -120
	big.offset_top = -167
	big.offset_right = 120
	big.offset_bottom = 167
	add_child(big)

	# Label below the card
	var label = UITheme.create_title(tr("YOUR HERO"), self)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.offset_top = 180
	label.offset_bottom = 220
	label.offset_left = -200
	label.offset_right = 200
	label.add_theme_color_override("font_color", data.color.lightened(0.3))
	label.modulate.a = 0.0

	big.modulate.a = 0.0
	big.scale = Vector2(0.7, 0.7)
	big.pivot_offset = big.card_size / 2.0

	var t = create_tween().set_parallel()
	t.tween_property(big, "modulate:a", 1.0, 0.4)
	t.tween_property(big, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 1.0, 0.4)

	await get_tree().create_timer(2.5).timeout
	if not is_instance_valid(big):
		return
	var t2 = create_tween().set_parallel()
	t2.tween_property(big, "modulate:a", 0.0, 0.4)
	t2.tween_property(label, "modulate:a", 0.0, 0.3)
	await t2.finished
	if is_instance_valid(big):
		big.queue_free()
	if is_instance_valid(label):
		label.queue_free()
