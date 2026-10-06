## Loot container (chest, crate, barrel, supply drop) that is opened to reveal items.
## Opening is a small show that plays identically on every peer (NetworkLootManager replays
## interact() everywhere): the container rattles, the lid bursts open, a beam in the color of
## the best item shoots up and the items pop out in arcs onto the ground around it. The empty
## container stays for a few seconds, then sinks away.
extends StaticBody3D
class_name LootContainer

signal container_opened(container: LootContainer, player: Player)
signal container_destroyed(container: LootContainer)

enum ContainerType {
	CRATE,
	CHEST,
	BARREL,
	SUPPLY_DROP
}

@export var container_type: ContainerType = ContainerType.CRATE
@export var health: float = 50.0
@export var loot_count: int = 2  # Number of items to drop

const INTERACT_RANGE: float = 2.5
const INTERACT_COLLISION_LAYER: int = 8  # Layer 4 for interactive objects
const ANTICIPATION_TIME: float = 0.3     # rattle before the lid bursts open
const EMPTY_LINGER_TIME: float = 9.0     # opened container stays this long before sinking away
const GROUND_MASK: int = 1               # hex tiles

var is_opened: bool = false
## Seed for the loot roll, assigned by LootSpawner. Every peer uses the same seed for the
## same container, so opening it produces identical items everywhere.
var loot_seed: int = 0
var loot_rng := RandomNumberGenerator.new()
var visual: Node3D = null        # rattles / squashes; holds the model
var lid: Node3D = null           # "Lid" node of the prop (hinge / lid center as pivot)
var parachute: Node3D = null     # supply drops only
var interact_prompt: Label3D = null
var is_opening: bool = false  # Prevents double-opening during animation
var is_falling: bool = false  # supply drop still in the air
## Zone drop (MapEventDirector): a supply drop with the good stuff - a strong weapon, a shield, a
## crystal and a medkit for sure - and a golden pillar over it (also on the minimap)
var rich: bool = false
var _lid_rest: Transform3D
var _glint: GPUParticles3D = null
var _sway: Tween = null
var _kit_ammo: Array = []  # ammo types owed to the guns rolled in this container

## Which weapon a WEAPON roll gives (the guide shows these as rarity too)
const WEAPON_WEIGHTS = {
	RangedWeapon.WeaponType.PISTOL: 22,
	RangedWeapon.WeaponType.SHOTGUN: 18,
	RangedWeapon.WeaponType.SNIPER: 7,
	RangedWeapon.WeaponType.RIFLE: 15,
	RangedWeapon.WeaponType.FLAMETHROWER: 10,
	RangedWeapon.WeaponType.SMG: 18,
	RangedWeapon.WeaponType.HAND_CANNON: 11,
	RangedWeapon.WeaponType.MARKSMAN: 8,
	RangedWeapon.WeaponType.MINIGUN: 5,
	RangedWeapon.WeaponType.DOUBLE_BARREL: 11,
	RangedWeapon.WeaponType.JAM_BLASTER: 10,
	RangedWeapon.WeaponType.LAUNCHER: 5,
}
const RICH_WEAPON_WEIGHTS = {
	RangedWeapon.WeaponType.SNIPER: 20,
	RangedWeapon.WeaponType.RIFLE: 15,
	RangedWeapon.WeaponType.FLAMETHROWER: 10,
	RangedWeapon.WeaponType.MARKSMAN: 15,
	RangedWeapon.WeaponType.MINIGUN: 15,
	RangedWeapon.WeaponType.LAUNCHER: 15,
	RangedWeapon.WeaponType.DOUBLE_BARREL: 10,
}
const RICH_COLOR := Color(1.0, 0.8, 0.3)
## A health pack heals this much (heroes have 150-320 HP: fewer packs, each one counts)
const HEALTH_PACK_HEAL: float = 25.0
## Rounds in one ammo pickup: about two magazines of the guns that use it (the guide shows them)
const AMMO_PER_PICKUP = {
	AmmoItem.AmmoType.PISTOL: 36,
	AmmoItem.AmmoType.SHOTGUN: 12,
	AmmoItem.AmmoType.SNIPER: 10,
	AmmoItem.AmmoType.RIFLE: 60,
	AmmoItem.AmmoType.FUEL: 100,
	AmmoItem.AmmoType.GRENADE: 6,
}

## The loot, battle-royale style: guns and the rounds for them first, heals and the rest around
## them. A gun always drops with a pack of its own ammo (never a gun you can't shoot); a loose ammo
## pack is of a type as common as the guns that use it (ammo_weights: plenty of pistol rounds, few
## grenades). Each container: its GUARANTEED items, then loot_count rolls on its table.
## (The order of each table matters: the seeded roll walks it.)
const LOOT_TABLES = {
	ContainerType.CRATE: {       # everywhere, one item: often ammo, sometimes a gun
		LootItem.ItemType.AMMO: 48,
		LootItem.ItemType.WEAPON: 27,
		LootItem.ItemType.SHIELD: 11,
		LootItem.ItemType.ABILITY_BOOST: 8,
		LootItem.ItemType.HEALTH: 6,
	},
	ContainerType.BARREL: {      # small: ammo, now and then a shield / heal, never a gun
		LootItem.ItemType.AMMO: 72,
		LootItem.ItemType.SHIELD: 12,
		LootItem.ItemType.ABILITY_BOOST: 8,
		LootItem.ItemType.HEALTH: 8,
	},
	ContainerType.CHEST: {       # landmarks: a gun for sure, then one of these
		LootItem.ItemType.AMMO: 52,
		LootItem.ItemType.SHIELD: 26,
		LootItem.ItemType.ABILITY_BOOST: 14,
		LootItem.ItemType.HEALTH: 8,
	},
	ContainerType.SUPPLY_DROP: { # a gun and a shield for sure, then one of these
		LootItem.ItemType.AMMO: 55,
		LootItem.ItemType.ABILITY_BOOST: 30,
		LootItem.ItemType.HEALTH: 15,
	},
}
## Heals are rare on purpose: you get health back by playing safe (meadows, passives), not by
## hoarding packs. Only the rich drops bring one for sure.
const GUARANTEED = {
	ContainerType.CRATE: [],
	ContainerType.BARREL: [],
	ContainerType.CHEST: [LootItem.ItemType.WEAPON],
	ContainerType.SUPPLY_DROP: [LootItem.ItemType.WEAPON, LootItem.ItemType.SHIELD],
}
## What the guide quotes as "% of the loot" (a crate's roll)
const DEFAULT_LOOT_WEIGHTS = {
	LootItem.ItemType.AMMO: 48,
	LootItem.ItemType.WEAPON: 27,
	LootItem.ItemType.SHIELD: 11,
	LootItem.ItemType.ABILITY_BOOST: 8,
	LootItem.ItemType.HEALTH: 6,
}
var loot_weights: Dictionary = {}  # set from LOOT_TABLES in _ready (a test may override it)

## For the guide and the trailer: [fewest items, most items, the sure things] of a container
## (the sure things + their ammo + one roll, which may be a gun with its own pack)
static func loot_summary(type: int) -> Array:
	var sure: Array = GUARANTEED.get(type, [])
	var fewest = sure.size() + sure.count(LootItem.ItemType.WEAPON) + 1
	var most = fewest + (1 if LOOT_TABLES.get(type, {}).has(LootItem.ItemType.WEAPON) else 0)
	return [fewest, most, sure]

## A loose ammo pack's type: as common as the guns that shoot it (WEAPON_WEIGHTS per ammo type)
static func ammo_weights() -> Dictionary:
	var out = {}
	for type in AmmoItem.AmmoType.values():
		out[type] = 0
	for weapon_type in WEAPON_WEIGHTS:
		var gun = RangedWeapon.create_weapon(weapon_type)
		out[gun.ammo_type] += WEAPON_WEIGHTS[weapon_type]
	return out

func _ready():
	if loot_weights.is_empty():
		loot_weights = LOOT_TABLES.get(container_type, DEFAULT_LOOT_WEIGHTS)
	add_to_group("loot_containers")
	_create_visual()
	_create_collision()

# ---------------------------------------------------------------- look

func _create_visual():
	visual = Node3D.new()
	visual.name = "ContainerVisual"
	add_child(visual)
	# A little deterministic turn so rows of containers don't look stamped, front still to the camera
	visual.rotation.y = float((loot_seed % 7) - 3) * 0.12

	var model = LootVisuals.container_model(container_type)
	if model:
		visual.add_child(model)
		lid = model.find_child("Lid", true, false) as Node3D
		parachute = model.find_child("Parachute", true, false) as Node3D
		if parachute:
			parachute.visible = false
		if lid:
			_lid_rest = lid.transform
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		visual.add_child(_fallback_mesh())

	# Chests and supply drops glint now and then so they are spotted from afar
	if container_type == ContainerType.CHEST or container_type == ContainerType.SUPPLY_DROP:
		_glint = GPUParticles3D.new()
		_glint.amount = 3
		_glint.lifetime = 1.4
		var pm = ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.4, 0.05, 0.25)
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 10.0
		pm.initial_velocity_min = 0.2
		pm.initial_velocity_max = 0.4
		pm.gravity = Vector3.ZERO
		var curve = Curve.new()
		curve.add_point(Vector2(0, 0))
		curve.add_point(Vector2(0.3, 1))
		curve.add_point(Vector2(1, 0))
		var curve_tex = CurveTexture.new()
		curve_tex.curve = curve
		pm.scale_curve = curve_tex
		pm.color = Color(1.0, 0.9, 0.55)
		_glint.process_material = pm
		var quad = QuadMesh.new()
		quad.size = Vector2(0.14, 0.14)
		quad.material = LandingImpact.soft_particle_material(true)
		_glint.draw_pass_1 = quad
		_glint.position.y = 0.55 if container_type == ContainerType.CHEST else 0.72
		visual.add_child(_glint)

	if rich:
		var pillar = LootVisuals.beam(RICH_COLOR, 9.0, 0.45)
		pillar.name = "RichBeam"
		(pillar.material_override as StandardMaterial3D).albedo_color.a = 0.5
		add_child(pillar)
		add_to_group("map_markers")
		set_meta("marker_color", RICH_COLOR)

func _fallback_mesh() -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = _body_size()
	mesh_instance.mesh = box
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.5, 0.2) if container_type == ContainerType.SUPPLY_DROP else Color(0.6, 0.45, 0.25)
	mesh_instance.material_override = material
	mesh_instance.position.y = box.size.y / 2.0
	return mesh_instance

## Size of the container body (Godot axes: x width, y height, z depth)
func _body_size() -> Vector3:
	match container_type:
		ContainerType.CHEST:
			return Vector3(0.92, 0.66, 0.58)
		ContainerType.BARREL:
			return Vector3(0.78, 0.86, 0.78)
		ContainerType.SUPPLY_DROP:
			return Vector3(1.12, 0.7, 0.78)
	return Vector3(0.8, 0.74, 0.8)

func _create_collision():
	var collision = CollisionShape3D.new()
	collision.name = "ContainerCollision"
	var size = _body_size()
	var shape: Shape3D
	if container_type == ContainerType.BARREL:
		shape = CylinderShape3D.new()
		shape.radius = size.x / 2.0
		shape.height = size.y
	else:
		shape = BoxShape3D.new()
		shape.size = size
	collision.shape = shape
	collision.position = Vector3(0, size.y / 2.0, 0)
	collision.rotation.y = visual.rotation.y if visual else 0.0
	add_child(collision)

	# Set collision layer for interact detection
	collision_layer = INTERACT_COLLISION_LAYER
	collision_mask = 2  # Can interact with player layer

# ---------------------------------------------------------------- prompt

func _process(_delta: float):
	_update_interact_prompt()

func _update_interact_prompt():
	var hud = get_tree().get_first_node_in_group("player_hud")
	if is_opened or is_opening or is_falling:
		if hud:
			hud.clear_interact(self)
		if interact_prompt:
			interact_prompt.queue_free()
			interact_prompt = null
		return

	# Find local player
	var local_player: Player = null
	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p is Player and p.is_local_player:
			local_player = p
			break

	if not local_player:
		if hud:
			hud.clear_interact(self)
		if interact_prompt and interact_prompt.visible:
			interact_prompt.visible = false
		return

	var dist = global_position.distance_to(local_player.global_position)

	if hud and hud.has_method("set_interact"):
		# The HUD's context lane shows "[E] Open" (no 3D label over the hero's head)
		if dist <= INTERACT_RANGE:
			hud.set_interact(self, "[%s] %s" % [Keybinds.label("interact"), tr("Open")])
		else:
			hud.clear_interact(self)
		return

	if dist <= INTERACT_RANGE:
		if not interact_prompt:
			_create_interact_prompt()
		if not interact_prompt.visible:
			interact_prompt.text = "[%s] %s" % [Keybinds.label("interact"), tr("Open")]  # the current key
		interact_prompt.visible = true
	elif interact_prompt:
		interact_prompt.visible = false

func _create_interact_prompt():
	interact_prompt = Label3D.new()
	interact_prompt.text = "[%s] %s" % [Keybinds.label("interact"), tr("Open")]
	interact_prompt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # translated above
	interact_prompt.position = Vector3(0, _body_size().y + 0.55, 0)
	interact_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	interact_prompt.font_size = 48
	interact_prompt.outline_size = 8
	interact_prompt.modulate = Color(1, 1, 0.8)
	interact_prompt.no_depth_test = true
	add_child(interact_prompt)

# ---------------------------------------------------------------- opening

func take_damage(amount: float, source = null):
	if is_opened or is_opening:
		return

	health -= amount
	_play_hit_effect()

	if health <= 0:
		# Shot open: same show, but the lid gets blasted off harder
		is_opening = true
		_play_open_animation(source as Player if source is Player else null)

## Called when player presses interact key (X) near container
func interact(player: Player = null):
	if is_opened or is_opening:
		return

	# Check distance if player provided
	if player:
		var dist = global_position.distance_to(player.global_position)
		if dist > INTERACT_RANGE:
			print("[LootContainer] Player too far to interact (%.1f > %.1f)" % [dist, INTERACT_RANGE])
			return

	is_opening = true
	if interact_prompt:
		interact_prompt.visible = false
	_play_open_animation(player)

func _play_open_animation(player: Player = null):
	# 1) anticipation: rattle and crouch, the lid jitters
	var rattle = create_tween()
	rattle.tween_method(_rattle, 0.0, 1.0, ANTICIPATION_TIME)
	rattle.tween_callback(open.bind(player))

func _rattle(t: float):
	if not visual:
		return
	var k = t * t
	visual.rotation.z = sin(t * 55.0) * 0.07 * k
	visual.scale = Vector3(1.0 + 0.06 * k, 1.0 - 0.1 * k, 1.0 + 0.06 * k)
	if lid:
		lid.transform = _lid_rest
		lid.position.y += abs(sin(t * 40.0)) * 0.04 * k

func open(player: Player = null):
	if is_opened:
		return

	is_opened = true
	is_opening = false
	remove_from_group("map_markers")
	var pillar = get_node_or_null("RichBeam")
	if pillar:
		create_tween().tween_property(pillar, "scale", Vector3(0.01, 1.0, 0.01), 0.6)
	container_opened.emit(self, player)
	Sfx.at("chest_open", global_position)

	var items = _spawn_loot()
	_burst_open(items)

	# The empty container lingers, then sinks away
	var fade = create_tween()
	fade.tween_interval(EMPTY_LINGER_TIME)
	fade.tween_property(visual, "scale", Vector3(1.1, 0.01, 1.1), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	fade.tween_callback(func():
		container_destroyed.emit(self)
		queue_free()
	)

## Late joiner: this container was opened before we arrived. No show - its loot simply lies
## around (NetworkLootManager removes what was already picked up) and the container is gone.
func open_instantly():
	if is_opened:
		return
	is_opened = true
	is_opening = false
	container_opened.emit(self, null)
	_spawn_loot()
	container_destroyed.emit(self)
	queue_free()

## 2) the pop: body springs back, lid bursts open, beam + flash + sparkles
func _burst_open(items: Array):
	if _glint:
		_glint.emitting = false
	visual.rotation.z = 0.0
	var body = create_tween()
	body.tween_property(visual, "scale", Vector3(0.94, 1.12, 0.94), 0.08).set_ease(Tween.EASE_OUT)
	body.tween_property(visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if lid:
		lid.transform = _lid_rest
	_open_lid()

	var color = _best_color(items)
	var top_y = _body_size().y * 0.85
	var beam = LootVisuals.beam(color, 3.2, 0.28)
	beam.scale = Vector3(0.3, 0.05, 0.3)
	visual.add_child(beam)
	var beam_mat: StandardMaterial3D = beam.material_override
	var bt = create_tween().set_parallel()
	bt.tween_property(beam, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	bt.tween_property(beam, "position:y", top_y + 1.6, 0.25)
	bt.chain().tween_property(beam_mat, "albedo_color:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	bt.chain().tween_callback(beam.queue_free)

	var light = OmniLight3D.new()
	light.light_color = color.lerp(Color.WHITE, 0.3)
	light.light_energy = 6.0
	light.omni_range = 5.0
	light.position.y = top_y + 0.3
	visual.add_child(light)
	var lt = create_tween()
	lt.tween_property(light, "light_energy", 0.8, 0.5)
	lt.tween_property(light, "light_energy", 0.0, 1.5)
	lt.tween_callback(light.queue_free)

	var sparks = LootVisuals.sparkles(color.lerp(Color(1, 0.95, 0.7), 0.5), 26, 6.0)
	sparks.position.y = top_y
	visual.add_child(sparks)
	sparks.emitting = true
	get_tree().create_timer(1.5).timeout.connect(sparks.queue_free)

	# 3) the items fly out one after another
	var from = global_position + Vector3(0, top_y, 0)
	for i in items.size():
		items[i].launch(from, 0.05 + i * 0.12)

func _open_lid():
	if not lid:
		return
	var t = create_tween()
	if container_type == ContainerType.CHEST:
		# Hinged: swing back past vertical, bounce, settle
		t.tween_property(lid, "rotation:x", -deg_to_rad(118.0), 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(lid, "rotation:x", -deg_to_rad(104.0), 0.25).set_trans(Tween.TRANS_SINE)
		return
	# Loose lid: pops off, tumbles through the air and lands next to the container
	var side = Vector3(0.75, 0, 0.66)  # model space: off to the side, towards the camera
	var land = lid.position + side * (_body_size().x * 0.9) - Vector3(0, _lid_rest.origin.y - 0.03, 0)
	var peak = lid.position.lerp(land, 0.4) + Vector3(0, 1.1, 0)
	t.set_parallel()
	t.tween_property(lid, "position", peak, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(lid, "rotation", Vector3(1.9, 0.6, 0.4), 0.5)
	t.chain().tween_property(lid, "position", land, 0.26).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.chain().tween_property(lid, "rotation", Vector3(PI, 0.7, 0.0), 0.12)

func _best_color(items: Array) -> Color:
	var best = Color(1.0, 0.9, 0.6)
	var rank = -1
	# Rarer loot wins the beam color
	var order = [LootItem.ItemType.AMMO, LootItem.ItemType.HEALTH, LootItem.ItemType.ABILITY_BOOST,
		LootItem.ItemType.SHIELD, LootItem.ItemType.WEAPON]
	for item in items:
		var r = order.find(item.item_type)
		if r > rank:
			rank = r
			best = LootVisuals.type_color(item.item_type)
	return best

# ---------------------------------------------------------------- loot

func _spawn_loot() -> Array:
	loot_rng.seed = loot_seed
	var items_to_spawn: Array[LootItem.ItemType] = []

	# The sure things, then the rolls on this container's table
	if rich:
		items_to_spawn.append_array([LootItem.ItemType.WEAPON, LootItem.ItemType.SHIELD, LootItem.ItemType.ABILITY_BOOST, LootItem.ItemType.HEALTH])
	else:
		items_to_spawn.append_array(GUARANTEED.get(container_type, []))
	for i in range(loot_count):
		items_to_spawn.append(_roll_loot_type())
	# Every gun brings a pack of its own ammo (two in the rich drops): _spawn_loot_item makes it
	var guns = items_to_spawn.count(LootItem.ItemType.WEAPON)
	for i in guns * (2 if rich else 1):
		items_to_spawn.append(LootItem.ItemType.AMMO)

	# Items land around the container, on whatever tile is there
	var spawned: Array = []
	_kit_ammo.clear()
	for i in range(items_to_spawn.size()):
		var angle = (TAU / items_to_spawn.size()) * i + loot_rng.randf() * 0.5
		var distance = 1.0 + loot_rng.randf() * 0.5
		var spot = global_position + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		spot.y = _ground_height(spot) + 0.45

		var item = _spawn_loot_item(items_to_spawn[i], spot)
		_register_network_item(item, i)
		if not item.is_queued_for_deletion():  # already picked up (late joiner)
			spawned.append(item)
	return spawned

func _ground_height(spot: Vector3) -> float:
	var space = get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		var query = PhysicsRayQueryParameters3D.create(spot + Vector3(0, 2.5, 0), spot - Vector3(0, 4.0, 0), GROUND_MASK)
		var hit = space.intersect_ray(query)
		if hit:
			return hit.position.y
	return global_position.y

func _roll_loot_type() -> LootItem.ItemType:
	var total_weight = 0
	for weight in loot_weights.values():
		total_weight += weight

	var roll = loot_rng.randi() % total_weight
	var current = 0

	for item_type in loot_weights:
		current += loot_weights[item_type]
		if roll < current:
			return item_type

	return LootItem.ItemType.HEALTH

func _spawn_loot_item(item_type: LootItem.ItemType, spawn_pos: Vector3) -> LootItem:
	var item = LootItem.new()
	item.item_type = item_type
	item.respawn_time = 0.0  # Loot from containers is one-shot

	# Set item properties based on type
	match item_type:
		LootItem.ItemType.HEALTH:
			item.item_name = "Health Pack"
			item.item_value = HEALTH_PACK_HEAL
		LootItem.ItemType.AMMO:
			# The pack for a gun from this container first, else as common as its guns
			var ammo_type: int
			if not _kit_ammo.is_empty():
				ammo_type = _kit_ammo.pop_front()
			else:
				var aw = ammo_weights()
				ammo_type = _weighted_random(aw.keys(), aw.values())
			item.item_name = AmmoItem.get_ammo_type_name(ammo_type)
			item.item_value = float(ammo_type)  # Store type as value
			item.item_data = AmmoItem.new(ammo_type, AMMO_PER_PICKUP.get(ammo_type, 30))
		LootItem.ItemType.WEAPON:
			# Random weapon type, weighted (pistol most common, sniper rare)
			var weights = RICH_WEAPON_WEIGHTS if rich else WEAPON_WEIGHTS
			var weapon_type = _weighted_random(weights.keys(), weights.values())
			var weapon = RangedWeapon.create_weapon(weapon_type)
			item.item_name = weapon.item_name
			item.item_data = weapon
			for n in (2 if rich else 1):
				_kit_ammo.append(weapon.ammo_type)  # its packs come right after
		LootItem.ItemType.ABILITY_BOOST:
			item.item_name = "Ability Boost"
			item.item_value = 1.0  # recharges the ability at once (AbilityComponent.boost_cooldowns)
		LootItem.ItemType.SHIELD:
			item.item_name = "Shield"
			item.item_value = 30.0

	# Add to scene (next to the container, so the item outlives it)
	var parent = get_parent() if get_parent() else get_tree().current_scene
	parent.add_child(item)
	item.global_position = spawn_pos
	item.original_position = item.position

	print("[LootContainer] Spawned %s at %s" % [item.item_name, spawn_pos])
	return item

## Give the item a network id derived from this container's id so it matches on every peer
func _register_network_item(item: LootItem, index: int) -> void:
	if not has_meta("network_id"):
		return
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.loot_manager:
		var item_id = int(get_meta("network_id")) * 100 + index
		network_manager.loot_manager.register_item(item, item_id)

func _weighted_random(items: Array, weights: Array):
	var total = 0
	for w in weights:
		total += w

	var roll = loot_rng.randi() % total
	var current = 0

	for i in range(items.size()):
		current += weights[i]
		if roll < current:
			return items[i]

	return items[0]

# ---------------------------------------------------------------- supply drop

## Supply drop under its parachute: sways while LootSpawner lowers it
func start_falling():
	is_falling = true
	Sfx.at("supply_drop", global_position)
	if parachute:
		parachute.visible = true
		parachute.scale = Vector3(0.2, 0.2, 0.2)
		create_tween().tween_property(parachute, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sway = create_tween().set_loops()
	_sway.tween_property(visual, "rotation:z", 0.08, 0.9).set_trans(Tween.TRANS_SINE)
	_sway.tween_property(visual, "rotation:z", -0.08, 0.9).set_trans(Tween.TRANS_SINE)

## Touchdown: thud on the tiles, dust, the parachute collapses and drifts off
func land():
	is_falling = false
	if _sway:
		_sway.kill()
	visual.rotation.z = 0.0
	visual.scale = Vector3(1.15, 0.8, 1.15)
	create_tween().tween_property(visual, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	LandingImpact.create_at(get_parent(), global_position, Color(1.0, 0.9, 0.7), 0.9)
	HexTile.shake_around(self, global_position, 1.0)
	if parachute:
		var t = create_tween().set_parallel()
		t.tween_property(parachute, "scale", Vector3(1.3, 0.05, 1.3), 0.7).set_ease(Tween.EASE_IN)
		t.tween_property(parachute, "position", parachute.position + Vector3(0.9, -0.5, 0.4), 0.7)
		t.chain().tween_callback(parachute.queue_free)

# ---------------------------------------------------------------- feedback

func _play_hit_effect():
	if not visual:
		return
	var tween = create_tween()
	tween.tween_property(visual, "rotation:z", 0.09, 0.04)
	tween.tween_property(visual, "rotation:z", -0.07, 0.05)
	tween.tween_property(visual, "rotation:z", 0.0, 0.06)
	visual.scale = Vector3(1.06, 0.92, 1.06)
	create_tween().tween_property(visual, "scale", Vector3.ONE, 0.18)
