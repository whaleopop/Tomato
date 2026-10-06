## Main player HUD, four corners on a 22 px margin: vitals card (bottom-left: portrait, HP, shield,
## heal / shield chips), a column top-right (minimap, alive / kills / zone time, zone + event lines,
## kill feed), alerts + the mode panel (top-center), abilities with a context lane above them
## (use progress, status, hints, "[E] Open"; bottom-center), ammo (bottom-right), crosshair and the
## elimination screen. A red edge vignette follows the missing HP under 30%.
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

var context_lane: VBoxContainer = null  # bottom center above the ability bar: use progress, status, hints
var top_center: VBoxContainer = null    # alerts (+ ModeView's panel in the other modes)
var top_right: VBoxContainer = null     # minimap, stats pill, zone / event lines, kill feed
var kills_label: Label = null
var stats_pill: PanelContainer = null
var hitmarker: Hitmarker = null
var kill_cards: KillCards = null
var zone_time_label: Label = null
var _low_vignette: TextureRect = null   # red edges, alpha follows the missing HP under 30%
var _use_progress: ConsumableBar = null
var _kills_timer: float = 0.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("player_hud")  # CameraController's view switch shows an alert

	_create_low_vignette()

	health_bar = HealthBar.new()
	health_bar.name = "HealthBar"
	health_bar.add_to_group("hud_health_bar")
	health_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	health_bar.offset_left = UITheme.MARGIN_MEDIUM
	health_bar.offset_bottom = -UITheme.MARGIN_MEDIUM
	add_child(health_bar)
	health_bar.percent_changed.connect(_on_hp_percent)

	# Top right: minimap, a stats pill, the zone / event lines, then the kill feed
	top_right = VBoxContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.offset_right = -UITheme.MARGIN_MEDIUM
	top_right.offset_top = UITheme.MARGIN_MEDIUM
	top_right.custom_minimum_size.x = 208
	top_right.add_theme_constant_override("separation", 8)
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_right)

	minimap = Minimap.new()
	minimap.name = "Minimap"
	top_right.add_child(minimap)

	stats_pill = PanelContainer.new()
	stats_pill.add_theme_stylebox_override("panel", UITheme.glass_box(UITheme.GLASS_TINT_HUD, Color(1, 1, 1, 0.08), UITheme.CORNER_RADIUS_SMALL, 12, 6))
	stats_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.add_child(stats_pill)
	var stats = HBoxContainer.new()
	stats.add_theme_constant_override("separation", 12)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_pill.add_child(stats)
	var alive_box = _stat_cell(stats, "leaf")  # TrainingGround hides this cell
	alive_label = alive_box.get_child(1)
	kills_label = _stat_cell(stats, "skull").get_child(1)
	zone_time_label = _stat_cell(stats, "timer").get_child(1)

	add_child(Scoreboard.new())  # hold Tab: everyone with kills and ping
	# zone / event lines are made in _create_zone_timer / _create_event_timer (they go in the column)
	_create_zone_timer()
	_create_event_timer()
	kill_feed = KillFeed.new()
	kill_feed.name = "KillFeed"
	kill_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_right.add_child(kill_feed)

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
	consumable_bar.set_anchors_preset(Control.PRESET_FULL_RECT)  # the heal / shield chips live in the vitals card
	health_bar.chips_holder.add_child(consumable_bar)

	ammo_display = AmmoDisplay.new()
	ammo_display.name = "AmmoDisplay"
	ammo_display.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_display.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo_display.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ammo_display.offset_left = -442
	ammo_display.offset_right = -UITheme.MARGIN_MEDIUM
	ammo_display.offset_bottom = -UITheme.MARGIN_MEDIUM
	add_child(ammo_display)  # _ready builds the slot strip and the card
	weapon_slots_ui = ammo_display.weapon_slots_ui

	_create_crosshair()
	hitmarker = Hitmarker.new()
	crosshair.add_child(hitmarker)

	# The kill card flies into the skull of the stats pill; it lands above the context lane
	kill_cards = KillCards.new()
	kill_cards.name = "KillCards"
	kill_cards.kills_anchor = kills_label.get_parent()
	kill_cards.lane_bottom = 260.0
	kill_cards.on_arrive = _on_kill_card_arrived
	add_child(kill_cards)

	# Top center: the mode panel (ModeView puts it here) and the alerts under it
	top_center = VBoxContainer.new()
	top_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_center.grow_horizontal = Control.GROW_DIRECTION_BOTH  # stay centered as it grows
	top_center.offset_top = UITheme.MARGIN_MEDIUM
	top_center.add_theme_constant_override("separation", 8)
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_center)
	alert_holder = CenterContainer.new()
	alert_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_child(alert_holder)
	alert_list = VBoxContainer.new()
	alert_list.alignment = BoxContainer.ALIGNMENT_BEGIN
	alert_list.add_theme_constant_override("separation", 6)
	alert_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_holder.add_child(alert_list)

	# Bottom center, above the ability bar: one lane for everything that comes and goes
	context_lane = VBoxContainer.new()
	context_lane.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	context_lane.grow_horizontal = Control.GROW_DIRECTION_BOTH
	context_lane.grow_vertical = Control.GROW_DIRECTION_BEGIN
	context_lane.offset_bottom = -108  # the ability bar's top (-100) and a gap
	context_lane.alignment = BoxContainer.ALIGNMENT_END
	context_lane.add_theme_constant_override("separation", 8)
	context_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(context_lane)
	_use_progress = ConsumableBar.new()
	_use_progress.progress_only = true
	_use_progress.custom_minimum_size = Vector2(260, 40)
	_use_progress.visible = false
	context_lane.add_child(_use_progress)
	_create_buff_pill()
	_create_hidden_hint()
	_create_reload_hint()
	_create_interact_hint()

	for c in [health_bar, ammo_display]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if Platform.touch_mode():
		_apply_touch_layout()

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_signal("match_ended"):
		network_manager.match_ended.connect(_on_match_ended)
	if network_manager and network_manager.has_signal("zone_changed"):
		network_manager.zone_changed.connect(_on_zone_changed)
	if network_manager and network_manager.has_signal("map_event"):
		network_manager.map_event.connect(_on_map_event)
	if network_manager and network_manager.has_signal("player_killed"):
		network_manager.player_killed.connect(_on_player_killed)

## Touch layout: health top-left (bottom-left is the move stick), ammo smaller under the top-right
## column (bottom-right is the aim stick), abilities hidden (they live on TouchControls' buttons).
## Safe-area margins keep corner elements clear of notches / rounded corners.
func _apply_touch_layout() -> void:
	var margins = UIScale.safe_margins(self)
	health_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	health_bar.grow_vertical = Control.GROW_DIRECTION_END
	health_bar.offset_left = UITheme.MARGIN_MEDIUM + margins.x
	health_bar.offset_top = UITheme.MARGIN_MEDIUM + margins.y + 64  # clear of a pause button
	health_bar.offset_bottom = 0
	top_right.offset_right = -UITheme.MARGIN_MEDIUM - margins.z
	top_right.offset_top = UITheme.MARGIN_MEDIUM + margins.y
	ability_bar.visible = false
	ammo_display.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ammo_display.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo_display.grow_vertical = Control.GROW_DIRECTION_END
	ammo_display.offset_left = -260
	ammo_display.offset_right = -UITheme.MARGIN_MEDIUM - margins.z
	ammo_display.offset_top = 220  # under the minimap / stats pill / kill feed column
	ammo_display.offset_bottom = 0
	ammo_display.scale = Vector2(0.78, 0.78)
	ammo_display.pivot_offset = Vector2(ammo_display.size.x, 0)

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
		_use_progress.inventory = inventory  # no icons needed for the bar
	if combat:
		ammo_display.setup(combat, inventory)  # also drives the slot strip

	crosshair.player = player
	hitmarker.player = player
	kill_cards.player = player
	kill_feed.my_id = player.entity_id
	aim_overlay.player = player
	damage_indicator.track(player)
	minimap.track(player)
	if hex_grid:
		minimap.setup_grid(hex_grid)
	_animate_hero_card_intro(player)

func _process(delta: float):
	if player and is_instance_valid(player):
		minimap.update_player_position(player.global_position)
	_update_alive_count()
	_update_kills(delta)
	_update_hidden_hint()
	_update_zone_timer(delta)
	_update_event_timer(delta)
	_update_buff_pill()
	_update_reload_hint()
	_update_interact_hint()
	_use_progress.visible = _use_progress.inventory != null and _use_progress.inventory.using != "" and death_screen == null

# ---------------------------------------------------------------- corners

## One "icon + number" cell of the stats pill; the number label is child 1
func _stat_cell(parent: Control, icon_name: String) -> HBoxContainer:
	var cell = HBoxContainer.new()
	cell.add_theme_constant_override("separation", 5)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cell)
	var icon = UITheme.create_icon(icon_name, cell, 18.0, UITheme.TEXT_SECONDARY)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label = UITheme.create_label("0", cell, UITheme.FONT_HEADING)
	label.add_theme_font_override("font", UITheme.font_black())
	return cell

var _kills_shown: int = 0

## A kill card landed in the counter: the number catches up and the pill punches
func _on_kill_card_arrived() -> void:
	_kills_timer = 0.0
	_kills_shown += 1
	kills_label.text = str(maxi(_kills_shown, int(_my_stats().get("kills", 0))))
	stats_pill.pivot_offset = stats_pill.size * 0.5
	var t = create_tween()
	t.tween_property(stats_pill, "scale", Vector2.ONE * 1.25, 0.001)
	t.tween_property(stats_pill, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## My eliminations (the stats are in the synced player state, so fog can't hide them)
func _update_kills(delta: float) -> void:
	_kills_timer -= delta
	if _kills_timer > 0.0:
		return
	_kills_timer = 0.25
	# never drops back: offline the stat doesn't count, online it already includes the card's kill
	_kills_shown = maxi(_kills_shown, int(_my_stats().get("kills", 0)))
	kills_label.text = str(_kills_shown)
	if zone_time_label:
		zone_time_label.text = "%d:%02d" % [int(ceil(_zone_left)) / 60, int(ceil(_zone_left)) % 60] if _zone_kind != "" else "-:--"

## A red wash on the screen edges, stronger the less HP is left (under 30%); no pulse
func _create_low_vignette() -> void:
	var grad = GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)  # offset 1.0 = the left / right edge midpoints
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(UITheme.ACCENT_DANGER, 0.0))
	grad.gradient.set_color(1, Color(UITheme.ACCENT_DANGER, 0.9))
	grad.gradient.set_offset(0, 0.55)
	grad.gradient.set_offset(1, 0.85)
	_low_vignette = TextureRect.new()
	_low_vignette.texture = grad
	_low_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_low_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_low_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_low_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_low_vignette.modulate.a = 0.0
	add_child(_low_vignette)

func _on_hp_percent(percent: float) -> void:
	var health = health_bar.health_component
	var dead = death_screen != null or (health != null and health.is_dead)
	var missing = clampf((HealthBar.LOW_PERCENT - percent) / HealthBar.LOW_PERCENT, 0.0, 1.0)
	_low_vignette.modulate.a = 0.0 if dead else missing * 0.6

# ---------------------------------------------------------------- zone countdown

var zone_pill: PanelContainer = null
var zone_label: Label = null
var _zone_kind: String = ""
var _zone_left: float = 0.0

func _create_zone_timer():
	zone_pill = PanelContainer.new()
	zone_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_pill.visible = false
	top_right.add_child(zone_pill)
	zone_label = UITheme.create_label("", zone_pill, UITheme.FONT_SMALL)
	zone_label.add_theme_font_override("font", UITheme.font_black())
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	zone_label.custom_minimum_size.x = 184

## A step of the zone (NetworkManager.zone_changed, on the host and on clients)
func _on_zone_changed(kind: String, _coords: Array, seconds: float, center: Vector2i, radius: int):
	_zone_kind = kind
	_zone_left = seconds
	minimap.set_zone(kind, center, radius)
	_punch(zone_pill)  # one punch on a phase change instead of an idle pulse
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
	zone_pill.add_theme_stylebox_override("panel", _line_box(color))
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
	event_pill = PanelContainer.new()  # under the zone line, only while an event runs
	event_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_pill.visible = false
	top_right.add_child(event_pill)
	event_label = UITheme.create_label("", event_pill, UITheme.FONT_SMALL)
	event_label.add_theme_font_override("font", UITheme.font_black())
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_label.custom_minimum_size.x = 184

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
	event_pill.add_theme_stylebox_override("panel", _line_box(color))
	event_label.text = text
	event_label.add_theme_color_override("font_color", color.lightened(0.35))
	event_pill.visible = text != ""

# ---------------------------------------------------------------- harvest bonus

var buff_pill: PanelContainer = null
var buff_label: Label = null

func _create_buff_pill():
	buff_pill = PanelContainer.new()
	buff_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buff_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buff_pill.visible = false
	context_lane.add_child(buff_pill)
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
	buff_pill.add_theme_stylebox_override("panel", _line_box(color))
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
	buff_pill.add_theme_stylebox_override("panel", _line_box(color))
	buff_pill.visible = true

# ---------------------------------------------------------------- hidden in a bush

var hidden_hint: Control = null

func _create_hidden_hint():
	var pill = PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _line_box(UITheme.ACCENT_SUCCESS))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	context_lane.add_child(pill)
	var label = UITheme.create_label("HIDDEN IN A BUSH - shooting gives you away", pill, UITheme.FONT_SMALL)
	label.add_theme_color_override("font_color", UITheme.ACCENT_SUCCESS.lightened(0.35))
	hidden_hint = pill
	hidden_hint.visible = false

# ---------------------------------------------------------------- reload / interact hints

var reload_hint: PanelContainer = null
var reload_label: Label = null
var interact_hint: PanelContainer = null
var interact_label: Label = null
var _interact_source: Object = null

## A quiet dark line with a thin color edge on the left (no glow): the lane's and the column's pills
func _line_box(color: Color) -> StyleBoxFlat:
	var box = UITheme.glass_box(UITheme.GLASS_TINT_HUD, Color(1, 1, 1, 0.08), UITheme.CORNER_RADIUS_SMALL, 14, 6)
	box.border_width_left = 3
	box.border_color = Color(color, 0.9)
	return box

## One punch (scale up and back) on a control that just changed
func _punch(control: Control) -> void:
	if not control or not control.visible:
		return
	control.pivot_offset = control.size / 2.0
	var tween = create_tween()
	tween.tween_property(control, "scale", Vector2(1.08, 1.08), 0.08)
	tween.tween_property(control, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _create_reload_hint():
	reload_hint = PanelContainer.new()
	reload_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reload_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reload_hint.visible = false
	context_lane.add_child(reload_hint)
	reload_label = UITheme.create_label("", reload_hint, UITheme.FONT_NORMAL)
	reload_label.add_theme_font_override("font", UITheme.font_black())

## "[R] RELOAD" when the magazine runs low and there is ammo to put in; "No ammo" when there is none
func _update_reload_hint():
	var combat = player.get_component("CombatComponent") if player and is_instance_valid(player) else null
	var weapon = combat.equipped_ranged_weapon if combat else null
	var text = ""
	var color = UITheme.ACCENT_WARNING
	if weapon and not combat.is_reloading and death_screen == null:
		var inventory = player.get_component("InventoryComponent")
		var endless = player.has_meta("endless_ammo")
		var reserve = inventory.get_ammo_count(weapon.ammo_type) if inventory else 0
		if weapon.current_ammo <= 0 and reserve <= 0 and not endless:
			text = tr("No ammo")
			color = UITheme.ACCENT_DANGER
		elif weapon.current_ammo <= weapon.magazine_size * 0.25 and (reserve > 0 or endless):
			text = "[%s] %s" % [Keybinds.label("reload"), tr("Reload").to_upper()]
			color = UITheme.ACCENT_DANGER if weapon.current_ammo <= 0 else UITheme.ACCENT_WARNING
	reload_hint.visible = text != ""
	if text != "":
		reload_label.text = text
		reload_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # translated above
		reload_label.add_theme_color_override("font_color", color.lightened(0.3))
		reload_hint.add_theme_stylebox_override("panel", _line_box(color))

func _create_interact_hint():
	interact_hint = PanelContainer.new()
	interact_hint.add_theme_stylebox_override("panel", _line_box(UITheme.ACCENT_PRIMARY))
	interact_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interact_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	interact_hint.visible = false
	context_lane.add_child(interact_hint)
	interact_label = UITheme.create_label("", interact_hint, UITheme.FONT_NORMAL)
	interact_label.add_theme_font_override("font", UITheme.font_black())
	interact_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # the caller translates

## A container in reach asks for the "[E] Open" line (LootContainer); the nearest asker wins
func set_interact(source: Object, text: String) -> void:
	_interact_source = source
	interact_label.text = text
	interact_hint.visible = true

func clear_interact(source: Object) -> void:
	if source == _interact_source:
		_interact_source = null
		interact_hint.visible = false

func _update_interact_hint():
	if interact_hint.visible and (_interact_source == null or not is_instance_valid(_interact_source) or death_screen != null):
		_interact_source = null
		interact_hint.visible = false

func _update_hidden_hint():
	var fog = get_tree().get_first_node_in_group("visibility_system") as VisibilitySystem
	var hidden = fog != null and fog.is_local_hidden() and death_screen == null
	if hidden_hint.visible != hidden:
		hidden_hint.visible = hidden

# ---------------------------------------------------------------- match end

var result_screen: Control = null
var _result_box: VBoxContainer = null   # the result card's column
var _reward_cols: Array = []             # its coins / mastery columns

const RESULT_WIDTH: int = 540

## A full-screen dark wash with a soft vignette (the main menu's shade); `stop` eats the clicks
func _wash(parent: Control, color: Color, stop: bool) -> void:
	var dim = ColorRect.new()
	dim.color = color
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP if stop else Control.MOUSE_FILTER_IGNORE
	parent.add_child(dim)
	var vignette = TextureRect.new()
	var grad = GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.05, 1.05)
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0.01, 0.02, 0.05, 0.0))
	grad.gradient.set_color(1, Color(0.01, 0.02, 0.05, 0.7))
	vignette.texture = grad
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(vignette)

## A full-screen card just went up: the HUD goes over the other UI added after it (mode panels,
## training notes) and the Tab scoreboard stays over the card
func _bring_screen_forward() -> void:
	var parent = get_parent()
	if parent:
		parent.move_child(self, -1)
		for c in parent.get_children():  # an open pause menu / inventory stays on top
			if c != self and c is CanvasItem and c.visible and c.is_in_group("blocks_game_input"):
				parent.move_child(c, -1)
	for c in get_children():
		if c is Scoreboard:
			move_child(c, -1)

## The small gold uppercase line over a title
func _kicker(text: String, parent: Control, centered: bool = false) -> Label:
	var k = UITheme.create_label(text, parent, 13)
	k.uppercase = true
	k.add_theme_font_override("font", UITheme.font_black())
	k.add_theme_color_override("font_color", UITheme.GOLD)
	if centered:
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return k

## A big Nunito black uppercase title with a dark drop shadow
func _big_title(text: String, parent: Control, color: Color, font_size: int = 52) -> Label:
	var t = UITheme.create_hero_title(text, parent)
	t.uppercase = true
	t.add_theme_font_size_override("font_size", font_size)
	t.add_theme_color_override("font_color", color)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	t.add_theme_constant_override("shadow_offset_y", 4)
	t.add_theme_constant_override("shadow_outline_size", 6)
	return t

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
	_bring_screen_forward()

	# The main menu's look: a dark wash, a navy card, a gold kicker over the big title
	_wash(result_screen, Color(0.10, 0.07, 0.0, 0.42) if i_won else Color(0.02, 0.03, 0.07, 0.55), true)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_screen.add_child(center)
	var card = UITheme.navy_panel(center, 32)
	card.custom_minimum_size.x = RESULT_WIDTH
	if i_won:
		var gold_box = UITheme.navy_box(Color(0.045, 0.06, 0.11, 0.94), Color(UITheme.GOLD, 0.7), 16, 32, 32)
		gold_box.shadow_color = Color(UITheme.GOLD, 0.28)
		gold_box.shadow_size = 28
		card.add_theme_stylebox_override("panel", gold_box)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	_result_box = box
	if i_won:
		var crown = UITheme.create_icon("crown", box, 38, UITheme.GOLD)
		crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var bob = crown.create_tween().set_loops()
		bob.tween_property(crown, "modulate", Color(1.15, 1.1, 0.9), 0.9).set_trans(Tween.TRANS_SINE)
		bob.tween_property(crown, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	_kicker(String(GameModes.info(GameModes.current()).name), box, true)

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
	var title = _big_title(title_text_override if title_text_override != "" else ("VICTORY!" if i_won else "MATCH OVER"), box, UITheme.GOLD if i_won else UITheme.TEXT_TITLE, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if i_won:
		title.add_theme_color_override("font_shadow_color", Color(UITheme.GOLD, 0.35))
		title.add_theme_constant_override("shadow_outline_size", 18)
		title.add_theme_constant_override("shadow_offset_y", 0)
	var sub = UITheme.create_label(sub_text, box, UITheme.FONT_NORMAL)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	# Coins on the left, mastery on the right (one column each keeps the card short)
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	box.add_child(cols)
	_reward_cols = []
	for i in 2:
		var col = VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		col.custom_minimum_size.x = 320
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(col)
		_reward_cols.append(col)
	_reward_row(_reward_cols[0], i_won, _reward_cols[1])
	for col in _reward_cols:
		col.visible = col.get_child_count() > 0
	cols.visible = _reward_cols[0].visible or _reward_cols[1].visible
	UITheme.create_spacer(false, box).custom_minimum_size.y = 4
	var leave = UITheme.create_play_button("BACK TO MENU", "NEXT MATCH FROM THE MENU", box)
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
	alive_label.text = str(alive)

## Short banner under the top edge ("The edges are crumbling!"); up to three stack
func show_alert(text: String, color: Color = UITheme.ACCENT_WARNING):
	var shown = alert_list.get_children().filter(func(c): return not c.is_queued_for_deletion())
	if shown.size() >= 3:
		shown[0].queue_free()
	var pill = PanelContainer.new()
	var pill_box = _line_box(color)  # icon + a 3px color bar, no glow
	pill_box.content_margin_left = 16
	pill_box.content_margin_right = 18
	pill_box.content_margin_top = 8
	pill_box.content_margin_bottom = 8
	pill.add_theme_stylebox_override("panel", pill_box)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	alert_list.add_child(pill)
	var line = HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(line)
	var icon = UITheme.create_icon("burst", line, 20.0, color.lightened(0.3))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label = UITheme.create_heading(text, line)
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
	_bring_screen_forward()

	_wash(death_screen, Color(0.07, 0.01, 0.03, 0.5), false)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_screen.add_child(center)

	var card = UITheme.navy_panel(center, 28)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	card.add_child(row)
	# Who took us out: their hero card and how they stand (filled by _fill_killer_card)
	_killer_slot = VBoxContainer.new()
	_killer_slot.add_theme_constant_override("separation", 8)
	_killer_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	_killer_slot.custom_minimum_size.x = 210
	row.add_child(_killer_slot)
	var divider = ColorRect.new()
	divider.color = Color(1, 1, 1, 0.08)
	divider.custom_minimum_size.x = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(divider)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size.x = 360
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(box)
	_kicker(String(GameModes.info(GameModes.current()).name), box)
	_big_title("ELIMINATED", box, UITheme.ACCENT_DANGER.lightened(0.25), 52)
	var sub = UITheme.create_label("You got mashed. Better luck next harvest!", box, UITheme.FONT_NORMAL)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	UITheme.create_spacer(false, box).custom_minimum_size.y = 4

	var watch = UITheme.create_play_button("SPECTATE", "WATCH WHO IS STILL STANDING", box)
	watch.pressed.connect(_start_spectating)
	var leave = UITheme.create_menu_row("BACK TO MENU", "", box)
	leave.pressed.connect(_on_leave_pressed)
	# The coins and the mastery of the match in a third column (only in a real match)
	var divider_right = divider.duplicate()
	row.add_child(divider_right)
	var side = VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.custom_minimum_size.x = 320
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(side)
	_reward_row(side, false)
	if side.get_child_count() == 0:
		side.queue_free()
		divider_right.queue_free()

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
	for c in [ability_bar, crosshair, aim_overlay, weapon_slots_ui, consumable_bar, context_lane, health_bar, ammo_display]:
		if c:
			c.visible = false
	_low_vignette.modulate.a = 0.0
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
	_bring_screen_forward()
	_wash(death_screen, Color(0.07, 0.01, 0.03, 0.3), false)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_screen.add_child(center)
	# A small navy card: the title, the seconds in gold and a gold bar running down
	var card = UITheme.navy_panel(center, 26)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size.x = 340
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	_kicker(String(GameModes.info(GameModes.current()).name), box, true)
	var title = _big_title("DOWN!", box, UITheme.ACCENT_DANGER.lightened(0.25), 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var count = UITheme.create_heading("", box)
	count.name = "Count"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_override("font", UITheme.font_black())
	count.add_theme_color_override("font_color", UITheme.GOLD)
	_respawn_left = float(GameModes.info(GameModes.current()).respawn)
	var bar = UITheme.create_progress_bar(maxf(_respawn_left, 0.01), _respawn_left, UITheme.GOLD, box)
	bar.custom_minimum_size = Vector2(0, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.create_tween().tween_property(bar, "value", 0.0, maxf(_respawn_left, 0.01))
	var t = create_tween().set_loops(int(ceil(_respawn_left)))
	count.text = tr("Back in %d s") % int(ceil(_respawn_left))
	t.tween_interval(1.0)
	t.tween_callback(func():
		_respawn_left -= 1.0
		if is_instance_valid(count):
			count.text = tr("Back in %d s") % int(max(ceil(_respawn_left), 0)))
	card.pivot_offset = Vector2(170, 90)
	card.scale = Vector2(0.9, 0.9)
	card.create_tween().tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Back in the fight (respawning modes): the countdown goes, the camera comes back to us
func _on_player_revived():
	if death_screen and is_instance_valid(death_screen):
		death_screen.queue_free()
	death_screen = null
	for c in [ability_bar, crosshair, aim_overlay, weapon_slots_ui, consumable_bar, context_lane, health_bar, ammo_display]:
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
			_kicker("Eliminated by", _killer_slot, true)
			var who = _big_title(weed, _killer_slot, Color.WHITE, 30)
			who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			who.add_theme_color_override("font_color", Weed.KINDS.get(weed, {}).get("color", Color.WHITE).lightened(0.2))
			var note = UITheme.create_label("A weed. Watch the bushes.", _killer_slot, UITheme.FONT_SMALL)
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			note.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
			return
		var lbl = _big_title("The island got you", _killer_slot, UITheme.ACCENT_WARNING, 26)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var hero_name = String(info.get("killer_hero", ""))
	var hero: CharacterData = CharacterRegistry.get_by_name(hero_name) if hero_name != "" else null
	var wear: Dictionary = info.get("killer_wear", {})
	_kicker("Eliminated by", _killer_slot, true)
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
		hero_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_killer_slot.add_child(hero_card)
		ItemRenderer.get_instance(get_tree()).hero(hero.character_name, skin, hat, func(tex): if is_instance_valid(hero_card): hero_card.set_art(tex))
	var name_lbl = UITheme.create_heading(String(info.get("killer_name", "")), _killer_slot)
	name_lbl.add_theme_font_override("font", UITheme.font_black())
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", KillFeed.hero_color(hero_name))
	var facts: Array = []
	var gun = KillFeed.weapon_name(int(info.get("weapon", -1)))
	if gun != "":
		facts.append(tr("with %s") % tr(gun))
	if info.has("killer_health"):
		facts.append(tr("%d / %d HP left") % [int(info["killer_health"]), int(info.get("killer_max_health", 0))])
	facts.append(tr("Kills: %d") % int(info.get("killer_kills", 0)))
	# The facts as small navy chips under the card
	var chips = HFlowContainer.new()
	chips.alignment = FlowContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	chips.custom_minimum_size.x = 210
	_killer_slot.add_child(chips)
	for f in facts:
		var chip = PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme.navy_box(UITheme.NAVY, Color(1, 1, 1, 0.1), 99, 10, 3))
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chips.add_child(chip)
		var l = UITheme.create_label(f, chip, UITheme.FONT_TINY)
		l.add_theme_font_override("font", UITheme.font_bold())
		l.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)

# ---------------------------------------------------------------- coins

var _rewarded: bool = false

## Coins for the match (once: at elimination or at the end), shown on the card
func _reward_row(box: Control, won: bool, mastery_box: Control = null) -> void:
	if _rewarded or not _is_real_match():
		return
	_rewarded = true
	var stats = _my_stats()
	if won:
		stats["place"] = 1
	var lines = PlayerProfile.match_reward(stats)
	_build_reward_rows(box, lines)
	Sfx.ui("coins")
	_mastery_rows(mastery_box if mastery_box else box, stats)

## The coins as navy rows (what for, how much of it, gold +coins at the end) and a gold total;
## the coins go to the profile here (PlayerProfile.add_coins)
func _build_reward_rows(box: Control, lines: Array) -> void:
	var total = 0
	_kicker("Rewards", box)
	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	box.add_child(list)
	for line in lines:
		total += int(line[2])
		var row = _navy_row(list)
		var what = UITheme.create_label(line[0], row, UITheme.FONT_SMALL)
		what.add_theme_font_override("font", UITheme.font_bold())
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var detail = UITheme.create_label(line[1], row, UITheme.FONT_SMALL)
		detail.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		var coins_row = UITheme.create_icon_label("coin", "+%d" % int(line[2]), row, UITheme.FONT_SMALL, UITheme.GOLD)
		coins_row.custom_minimum_size.x = 64
		coins_row.alignment = BoxContainer.ALIGNMENT_END
		var coins_label: Label = coins_row.get_meta("label")
		coins_label.add_theme_font_override("font", UITheme.font_black())
	PlayerProfile.add_coins(total)
	var sum = _navy_row(list, true)
	var sum_label = UITheme.create_label(tr("+%d coins") % total, sum, UITheme.FONT_NORMAL)
	sum_label.uppercase = true
	sum_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sum_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sum_label.add_theme_font_override("font", UITheme.font_black())
	sum_label.add_theme_color_override("font_color", UITheme.GOLD)

## One row of a navy list (an HBox inside a navy box); `gold` gives it the gold rim
func _navy_row(parent: Control, gold: bool = false) -> HBoxContainer:
	var panel = PanelContainer.new()
	var fill = Color(0.16, 0.12, 0.03, 0.85) if gold else UITheme.NAVY
	panel.add_theme_stylebox_override("panel", UITheme.navy_box(fill, Color(UITheme.GOLD, 0.6) if gold else Color(1, 1, 1, 0.08), 10, 14, 6))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	return row

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
	_build_mastery_rows(box, rows, report.unlocked)

## The mastery list: [display name, [before, after, xp]] rows and the ranks unlocked
func _build_mastery_rows(box: Control, rows: Array, unlocked: Array) -> void:
	if rows.is_empty():
		return
	_kicker("Mastery", box)
	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	box.add_child(list)
	for r in rows:
		var before: Dictionary = r[1][0]
		var after: Dictionary = r[1][1]
		var line = _navy_row(list)
		var name_label = UITheme.create_label(r[0], line, UITheme.FONT_SMALL)
		name_label.add_theme_font_override("font", UITheme.font_bold())
		name_label.custom_minimum_size.x = 120
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var lvl_text = tr("Lv %d") % after.level if before.level == after.level else tr("Lv %d  ›  %d") % [before.level, after.level]
		var lvl = UITheme.create_label(lvl_text, line, UITheme.FONT_SMALL)
		lvl.custom_minimum_size.x = 92
		lvl.add_theme_font_override("font", UITheme.font_black())
		lvl.add_theme_color_override("font_color", Mastery.tier_color(after.tier).lightened(0.2) if after.tier >= 0 else UITheme.TEXT_PRIMARY)
		var bar = UITheme.create_progress_bar(float(after.need), float(after.need if after.max else after.into), Mastery.tier_color(after.tier) if after.tier >= 0 else UITheme.ACCENT_INFO, line)
		bar.custom_minimum_size = Vector2(120, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var xp = UITheme.create_label("+%d XP" % int(r[1][2]), line, UITheme.FONT_SMALL)
		xp.custom_minimum_size.x = 64
		xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		xp.add_theme_font_override("font", UITheme.font_black())
		xp.add_theme_color_override("font_color", UITheme.ACCENT_INFO.lightened(0.3))
	for u in unlocked:
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
	var _spread_px: float = 11.0  # single guns: the ring is as wide as the bullets may stray at the cursor

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta):
		var want = _spread_ring()
		_spread_px = lerpf(_spread_px, want, 1.0 - exp(-delta * 18.0))
		queue_redraw()

	## How wide (px) a single bullet may stray where the cursor is: CombatComponent.current_spread
	## (accuracy, movement, bloom) at the aim point's distance, projected to the screen
	func _spread_ring() -> float:
		if not player or not is_instance_valid(player):
			return 11.0
		var combat = player.get_component("CombatComponent")
		var handler = player.get_node_or_null("InputHandler") as PlayerInputHandler
		var camera = get_viewport().get_camera_3d()
		if not combat or not handler or not camera or not combat.equipped_ranged_weapon:
			return 11.0
		var aim: Vector3 = handler.get_aim_position()
		if aim == Vector3.ZERO or camera.is_position_behind(aim):
			return 11.0
		var reach = combat.muzzle_position().distance_to(aim) * combat.current_spread()
		var side = camera.global_transform.basis.x
		var px = camera.unproject_position(aim).distance_to(camera.unproject_position(aim + side * reach))
		return clampf(px, 9.0, 120.0)

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
			_:  # single shots: ring + ticks, as wide as the bullets may stray (it opens up while
				# you run or hold the trigger and closes when you stop - fire then)
				# (no `grow`: current_spread already widens it by the quake's spread_factor)
				var r3 = maxf(_spread_px, 9.0)
				draw_arc(p, r3, 0, TAU, 32, shadow, 4.0, true)
				draw_arc(p, r3, 0, TAU, 32, col, 2.0, true)
				for v in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(p + v * (r3 + 4.0), p + v * (r3 + 10.0), col, 2.0, true)
				draw_circle(p, 2.5, accent)
		if far:  # past the gun's reach: a small cross over it
			draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), col, 2.0, true)
			draw_line(p + Vector2(-5, 5), p + Vector2(5, -5), col, 2.0, true)

# ---------------------------------------------------------------- weapon slots

# ---------------------------------------------------------------- hero card

## (The permanent corner card is the portrait in the vitals card now: HealthBar)
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
