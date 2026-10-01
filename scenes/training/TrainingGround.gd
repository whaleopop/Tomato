## Training ground (main menu -> TRAINING GROUND): an offline arena to try heroes, guns and
## abilities. Every gun lies on the racks (taken ones come back), ammo and pickups too, dummies
## that heal up after a moment (one walks back and forth), target boards at 10 / 20 / 35 m and a
## damage meter. Tab opens the hero cards (HeroPicker), [ and ] step through the heroes
## (the scene reloads with the new one).
## GameSceneController builds it instead of a match when GameManager.training_mode is set.
extends Node3D
class_name TrainingGround

const RADIUS: int = 9
const DUMMY_HEALTH: float = 1000.0
const HEAL_DELAY: float = 2.5
const METER_WINDOW: float = 5.0

var grid: HexGrid = null
var player: Player = null
var dummies: Array = []
var _last_hit: Dictionary = {}     # dummy -> msec of the last hit
var _hits: Array = []              # [msec, damage] for the meter
var _meter: Label = null
var _walker: Node3D = null
var _walk_t: float = 0.0
var _ui_layer: Node = null
var _picker: HeroPicker = null

## Build the arena and the local player; returns the player (the controller wires input / HUD)
func build(selected: CharacterData) -> Player:
	_build_arena()
	_build_racks()
	_build_targets()
	_build_dummies()
	_build_weeds()
	player = Player.new()
	player.name = "TrainingPlayer"
	player.is_local_player = true
	add_child(player)
	player.setup_character(selected if selected else CharacterRegistry.get_all()[0])
	player.spawn(_top(Vector2i(0, 3)) + Vector3(0, 0.5, 0))
	player.give_starting_loadout()
	var inventory = player.get_component("InventoryComponent")
	for type in AmmoItem.AmmoType.values():
		inventory.add_item(AmmoItem.new(type, 300))
	return player

func _top(c: Vector2i) -> Vector3:
	var tile = grid.get_tile(c)
	return grid.hex_to_world(c) + Vector3(0, CoverSpawner.tile_top(tile) if tile else 0.3, 0)

## Flat grass, a strip of sand for the racks, the mountain rim around
func _build_arena():
	grid = HexGrid.new(RADIUS)
	grid.name = "TrainingGrid"
	add_child(grid)
	for q in range(-RADIUS, RADIUS + 1):
		for r in range(max(-RADIUS, -q - RADIUS), min(RADIUS, -q + RADIUS) + 1):
			var c = Vector2i(q, r)
			var d = max(abs(q), abs(r), abs(q + r))
			var tile = HexTile.new()
			tile.hex_coords = c
			tile.position = grid.hex_to_world(c)
			tile.set_height(0.45)
			tile.biome_type = HexTile.BiomeType.MOUNTAIN if d >= RADIUS else (HexTile.BiomeType.BEACH if r >= 4 else HexTile.BiomeType.GRASS)
			tile.can_spawn = d < RADIUS
			grid.add_tile(c, tile)
	grid.update_tile_edges()
	var sign_label = Label3D.new()
	sign_label.text = tr("TRAINING GROUND")
	sign_label.font_size = 96
	sign_label.outline_size = 16
	sign_label.pixel_size = 0.01
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sign_label)
	sign_label.position = _top(Vector2i(0, -6)) + Vector3(0, 3.2, 0)

## Every gun on the sand behind the start, ammo and pickups next to them; taken ones come back
func _build_racks():
	var types = RangedWeapon.WeaponType.values()
	for i in types.size():
		var weapon = RangedWeapon.create_weapon(types[i])
		var row = i / 6  # two racks of six
		var rack = Vector2i(-row, 6 + row * 2)
		var pos = grid.hex_to_world(rack) + Vector3(((i % 6) - 2.5) * 2.4, 0, 0)
		pos.y = _top(rack).y + LootItem.HOVER_HEIGHT
		_pickup(LootItem.ItemType.WEAPON, weapon.item_name, 0.0, weapon, pos)
		_label(weapon.item_name, pos + Vector3(0, 1.1, 0), Color(1, 0.95, 0.8))
	var extras = [[LootItem.ItemType.HEALTH, "Health Pack", 25.0], [LootItem.ItemType.SHIELD, "Shield", 30.0],
		[LootItem.ItemType.ABILITY_BOOST, "Ability Boost", 1.0]]
	for i in extras.size():
		var pos = grid.hex_to_world(Vector2i(-6, 7)) + Vector3(i * 1.6, 0, 0)
		pos.y = _top(Vector2i(-6, 7)).y + LootItem.HOVER_HEIGHT
		_pickup(extras[i][0], extras[i][1], extras[i][2], null, pos)

## A pickup that comes back 3 s after it is taken (placed before _ready: it returns there)
func _pickup(type: int, item_name: String, value: float, data: ItemData, pos: Vector3) -> LootItem:
	var item = LootItem.new()
	item.item_type = type
	item.item_name = item_name
	item.item_value = value
	item.item_data = data
	item.respawn_time = 3.0
	item.position = pos
	add_child(item)
	return item

func _label(text: String, pos: Vector3, color: Color) -> Label3D:
	var label = Label3D.new()
	label.text = tr(text)
	label.font_size = 36
	label.outline_size = 9
	label.pixel_size = 0.0065
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	label.position = pos
	return label

## Blaster Kit target boards at 10 / 20 / 35 m straight ahead: bullets stop on them
func _build_targets():
	var start = _top(Vector2i(0, 3))
	for dist in [10.0, 20.0, 35.0]:
		var spot = start + Vector3(0, 0, -dist)
		var board = StaticBody3D.new()
		board.collision_layer = HitscanSystem.LAYER_ENVIRONMENT
		board.collision_mask = 0
		var model = LootVisuals._instance("res://models/target-large.glb")
		if model:
			LootVisuals.fit(model, 1.4)
			board.add_child(model)
		var shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(1.4, 1.4, 0.2)
		shape.shape = box
		board.add_child(shape)
		add_child(board)
		var tile = grid.get_tile(grid.world_to_hex(spot))
		spot.y = CoverSpawner.tile_top(tile) if tile else spot.y
		board.position = spot + Vector3(2.6, 1.0, 0)
		_label("%d m" % int(dist), board.position + Vector3(0, 1.1, 0), Color(1, 1, 1))

## Three dummies standing, one walking; they heal up HEAL_DELAY after the last hit
func _build_dummies():
	var roster = CharacterRegistry.get_all()
	var start = _top(Vector2i(0, 3))
	var spots = [start + Vector3(-3.0, 0, -7.0), start + Vector3(0.0, 0, -8.0), start + Vector3(3.0, 0, -7.0)]
	for i in spots.size() + 1:
		var dummy = Player.new()
		dummy.name = "Dummy_%d" % i
		dummy.entity_id = 9000 + i
		dummy.set_meta("training_dummy", true)  # weeds leave them alone
		add_child(dummy)
		dummy.setup_character(roster[(i * 4 + 5) % roster.size()])
		var pos = spots[i] if i < spots.size() else start + Vector3(-6.0, 0, -13.0)
		dummy.spawn(pos + Vector3(0, 0.3, 0))
		var animator = dummy.get_node_or_null("Animator")
		if animator:
			animator.set("_spawn_delay", -1.0)
			animator.set("_spawn_t", -1.0)
		dummy.rotation.y = PI  # facing the player
		var health = dummy.get_component("HealthComponent")
		health.set_max_health(DUMMY_HEALTH, true)
		health.damage_taken.connect(_on_dummy_hit.bind(dummy))
		dummies.append(dummy)
		if i == spots.size():
			_walker = dummy

## Three weeds far up the field to try your guns on (they fight back); a felled one grows again
const WEED_SPOTS = [["Dandelion", Vector2i(-4, -3)], ["Hogweed", Vector2i(0, -6)], ["Nettle", Vector2i(4, -6)]]
var _weed_id: int = 100

func _build_weeds():
	for w in WEED_SPOTS:
		_grow_weed(w[0], w[1])

func _grow_weed(kind: String, c: Vector2i):
	var weed = Weed.new()
	_weed_id += 1
	weed.npc_id = _weed_id
	weed.kind = kind
	weed.authority = true
	weed.position = _top(c) + Vector3(0, 0.2, 0)
	add_child(weed)
	weed.tree_exited.connect(func():
		if is_inside_tree():
			get_tree().create_timer(8.0).timeout.connect(func(): if is_inside_tree(): _grow_weed(kind, c)))

func _on_dummy_hit(amount: float, _source, dummy: Node3D) -> void:
	_last_hit[dummy] = Time.get_ticks_msec()
	if amount > 0.0:
		_hits.append([Time.get_ticks_msec(), amount])
	var health = dummy.get_component("HealthComponent")
	if health.current_health < DUMMY_HEALTH * 0.2:
		health.heal(DUMMY_HEALTH)  # dummies never go down

func _process(delta: float):
	var now = Time.get_ticks_msec()
	for dummy in dummies:
		if not is_instance_valid(dummy):
			continue
		var health = dummy.get_component("HealthComponent")
		if health.current_health < health.max_health and now - int(_last_hit.get(dummy, 0)) > HEAL_DELAY * 1000.0:
			health.heal(health.max_health)
	# The walker paces left and right
	if _walker and is_instance_valid(_walker):
		_walk_t += delta
		var mv = _walker.get_component("MovementComponent")
		var dir = 1.0 if fmod(_walk_t, 6.0) < 3.0 else -1.0
		mv.set_move_direction(Vector3(dir, 0, 0))
		_walker.rotation.y = atan2(dir, 0.0)
	# Damage meter: the last METER_WINDOW seconds
	while not _hits.is_empty() and now - int(_hits[0][0]) > METER_WINDOW * 1000.0:
		_hits.pop_front()
	if _meter:
		var total = 0.0
		for h in _hits:
			total += h[1]
		_meter.text = tr("Damage in the last %d s: %d  (%d per second)") % [int(METER_WINDOW), int(total), int(total / METER_WINDOW)]

## Hint card + damage meter on the HUD layer
func add_hud(ui_layer: Node) -> void:
	_ui_layer = ui_layer
	var hud = ui_layer.get_node_or_null("PlayerHUD")
	if hud and hud.alive_label:
		hud.alive_label.get_parent().visible = false  # nobody to outlive here
	var holder = MarginContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	holder.offset_left = 20
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(holder)
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.glass_box(Color(0.04, 0.06, 0.1, 0.72), Color(1, 1, 1, 0.14), 16, 16, 12))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(card)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var title = UITheme.create_heading("TRAINING GROUND", box)
	title.add_theme_color_override("font_color", UITheme.ACCENT_PRIMARY.lightened(0.3))
	for line in ["Guns are on the racks behind you", "Dummies heal up after a moment", "Weeds up the field fight back",
			"Tab  -  choose the hero", "[ and ]  -  next / previous hero", "Esc  -  back to the menu"]:
		UITheme.create_label(line, box, UITheme.FONT_TINY)
	_meter = UITheme.create_label("", box, UITheme.FONT_SMALL)
	_meter.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB and _ui_layer and not is_instance_valid(_picker):
			_picker = HeroPicker.new()
			_picker.picked.connect(_switch_to)
			_ui_layer.add_child(_picker)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_BRACKETRIGHT or event.keycode == KEY_BRACKETLEFT:
			_switch_hero(1 if event.keycode == KEY_BRACKETRIGHT else -1)
			get_viewport().set_input_as_handled()

func _switch_hero(step: int):
	var roster = CharacterRegistry.get_all()
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		return
	var index = 0
	for i in roster.size():
		if game_manager.selected_character and roster[i].character_name == game_manager.selected_character.character_name:
			index = i
	_switch_to(roster[(index + step + roster.size()) % roster.size()])

func _switch_to(data: CharacterData):
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		return
	game_manager.selected_character = data
	get_tree().reload_current_scene()
