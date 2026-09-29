## Map events: the part every peer plays the same way. MapEventDirector (server) decides what
## happens where and sends it out (NetworkManager.broadcast_map_event); the host plays it here on
## the shared world, remote clients through ClientWorld.apply_map_event. This does the warnings and
## visuals, the world changes that must match everywhere (fallen walls, flooded shores, the rift's
## rock, the harvest bonus) and the global modifiers the rules read. With `authority` (the server)
## it also deals the damage and moves every player; a client only moves its own predicted player,
## like the zone (DestructionSystem.shove).
##   meteors  red circles on the ground, meteors a few seconds later: area damage, knockback, fire
##   quake    the island shakes, walls fall, shots scatter (spread_factor)
##   night    night or thick fog: everybody sees half as far, bushes hide better
##   flood    shallows turn deep, shores next to the water go under
##   rift     a crack across the island glows, burns and rises into a rock ridge
##   harvest  a rare bonus grows somewhere: speed, damage or a full shield
## zone_drop and center_shift only concern the HUD (the drop is a supply drop, the shift is
## DestructionSystem's). `elapsed` > 0: a late joiner catching up - what is over is skipped.
extends Node3D
class_name MapEvents

signal tile_raised(coords: Vector2i)  # the rift turned a tile into rock (ServerWorld remembers it)

# Read by the rules on every peer. Static: on the host the server and the local view share them.
static var sight_factor: float = 1.0   # VisibilitySystem, ServerVisibility
static var bush_factor: float = 1.0    # how close you must come to spot someone in a bush
static var spread_factor: float = 1.0  # CombatComponent aim spread

const METEOR_RADIUS: float = 2.6       # world units
const METEOR_DAMAGE: float = 30.0      # at the center, half of it at the edge
const METEOR_PUSH: float = 9.0
const METEOR_FIRE_TIME: float = 5.0   # the crater keeps burning
const QUAKE_SPREAD: float = 3.5
const NIGHT_SIGHT: float = 0.5
const NIGHT_BUSH: float = 0.5
const FLOOD_TIME: float = 2.5          # the shores sink this long
const HARVEST_TIME: float = 25.0       # the speed / damage bonus lasts this long
const HARVEST_SPEED: float = 1.35
const HARVEST_DAMAGE: float = 1.5
const HARVEST_HEAL: float = 25.0       # the shield bonus also heals
enum Harvest { SPEED, DAMAGE, SHIELD }
const HARVEST_NAMES = ["Speed Sprout", "Power Sprout", "Shield Sprout"]
const HARVEST_COLORS = [Color(0.35, 1.0, 0.9), Color(1.0, 0.36, 0.22), Color(0.45, 0.62, 1.0)]

var grid: HexGrid = null
var cover: CoverSpawner = null
var authority: bool = false

var _quake_left: float = 0.0
var _quake_tick: float = 0.0
var _night_left: float = 0.0
var _rift_burning: Dictionary = {}     # coords -> true while a rift burns (authority: damage)
var _rift_burn_left: float = 0.0
var _rift_tick: float = 0.0
var _harvest_ids: Dictionary = {}      # loot item id -> bonus
var _atmo: Dictionary = {}             # the normal day look, saved when the first night / fog comes
var _atmo_tween: Tween = null
var _lantern: OmniLight3D = null
var _mist: GPUParticles3D = null

func setup(p_grid: HexGrid, p_cover: CoverSpawner, p_authority: bool) -> void:
	grid = p_grid
	cover = p_cover
	authority = p_authority
	var loot_manager = _loot_manager()
	if loot_manager and not loot_manager.item_picked_up_network.is_connected(_on_item_picked):
		loot_manager.item_picked_up_network.connect(_on_item_picked)

func _exit_tree():
	MapEvents.sight_factor = 1.0
	MapEvents.bush_factor = 1.0
	MapEvents.spread_factor = 1.0
	_restore_atmosphere(0.0)

func play(kind: String, data: Dictionary, elapsed: float = 0.0) -> void:
	if not grid or not is_instance_valid(grid) or not is_inside_tree():
		return
	match kind:
		"meteors":
			_meteors(data, elapsed)
		"quake":
			_quake(data, elapsed)
		"night":
			_night(data, elapsed)
		"flood":
			_flood(data, elapsed)
		"rift":
			_rift(data, elapsed)
		"harvest":
			_harvest(data, elapsed)
		"peel_gone":  # a banana peel caught someone on the server: our copy of it goes too
			BananaPeel.remove_near(get_tree(), data.get("pos", Vector3.ZERO), int(data.get("owner", 0)))

func _process(delta: float):
	if _quake_left > 0.0:
		_quake_left -= delta
		_shake_ground(delta)
		if _quake_left <= 0.0:
			MapEvents.spread_factor = 1.0
	if _night_left > 0.0:
		_night_left -= delta
		_follow_viewer()
		if _night_left <= 0.0:
			MapEvents.sight_factor = 1.0
			MapEvents.bush_factor = 1.0
			_restore_atmosphere(3.0)
	if _rift_burn_left > 0.0:
		_rift_burn_left -= delta
		_rift_tick -= delta
		if _rift_tick <= 0.0:
			_rift_tick += DestructionSystem.BURN_TICK
			_burn_rift()

# ---------------------------------------------------------------- who is affected

## The players this peer moves: all of them on the server, only our own predicted one on a client
func movers() -> Array:
	var result: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and p is Node3D and p.has_method("get_component") and (authority or p.get("is_local_player")):
			var health = p.get_component("HealthComponent")
			if not health or not health.is_dead:
				result.append(p)
	return result

## Whose screen this is (the local player), for the camera-bound effects
func viewer() -> Node3D:
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and p.get("is_local_player"):
			return p
	return null

func _loot_manager() -> NetworkLootManager:
	var network_manager = get_node_or_null("/root/NetworkManager")
	return network_manager.loot_manager if network_manager else null

# ---------------------------------------------------------------- meteors

func _meteors(data: Dictionary, elapsed: float) -> void:
	var points: Array = data.get("points", [])
	var delays: Array = data.get("delays", [])
	for i in points.size():
		var left = (float(delays[i]) if i < delays.size() else 3.0) - elapsed
		if left < 0.0:
			continue  # already down (a late joiner sees the fire, if any, next time)
		var strike = MeteorStrike.new()
		strike.events = self
		strike.delay = max(left, 0.05)
		add_child(strike)
		strike.global_position = points[i]

## A meteor came down at `pos`: knockback for whoever this peer moves, damage on the server
func meteor_impact(pos: Vector3) -> void:
	for p in movers():
		var off: Vector3 = p.global_position - pos
		off.y = 0.0
		var d = off.length()
		if d > METEOR_RADIUS:
			continue
		var movement = p.get_component("MovementComponent")
		if movement and d > 0.05:
			movement.dash(off.normalized() * METEOR_PUSH, 0.22)
		if authority:
			var health = p.get_component("HealthComponent")
			if health:
				health.take_damage(METEOR_DAMAGE * (1.0 - 0.5 * d / METEOR_RADIUS), null)
	var me = viewer()
	var dist = me.global_position.distance_to(pos) if me else 20.0
	ScreenEffects.shake(clamp(0.7 - dist / 30.0, 0.08, 0.7), 5.0)

# ---------------------------------------------------------------- earthquake

func _quake(data: Dictionary, elapsed: float) -> void:
	for entry in data.get("walls", []):
		var wall = cover.get_node_or_null(String(entry[0])) if cover else null
		if not wall is CoverWall:
			continue
		var t = float(entry[1]) - elapsed
		if t <= 0.0:
			wall.fall()
		else:
			get_tree().create_timer(t).timeout.connect(_topple.bind(wall))
	var left = float(data.get("seconds", 5.0)) - elapsed
	if left <= 0.0:
		return
	_quake_left = max(_quake_left, left)
	MapEvents.spread_factor = QUAKE_SPREAD
	ScreenEffects.shake(0.45, 1.2)

func _topple(wall: CoverWall) -> void:
	if not is_instance_valid(wall) or not wall.is_inside_tree():
		return
	LandingImpact.create_at(self, wall.global_position, Color(0.72, 0.66, 0.58), 0.55)
	wall.fall()

## The ground under the camera keeps bouncing, the rest of the island now and then
func _shake_ground(delta: float) -> void:
	_quake_tick -= delta
	if _quake_tick > 0.0:
		return
	_quake_tick = 0.12
	ScreenEffects.shake(0.16 + 0.1 * min(_quake_left, 1.0), 2.5)
	var me = viewer()
	if me:
		var around = me.global_position + Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
		HexTile.shake_around(self, around, randf_range(0.3, 0.55), 1.4)
	var keys = grid.tiles.keys()
	for i in 4:
		var tile = grid.get_tile(keys[randi() % keys.size()])
		if tile:
			tile.bounce(randf_range(0.25, 0.5), 0.0, tile.global_position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)))

# ---------------------------------------------------------------- night / fog

func _night(data: Dictionary, elapsed: float) -> void:
	var left = float(data.get("seconds", 25.0)) - elapsed
	if left <= 0.0:
		return
	_night_left = left
	MapEvents.sight_factor = NIGHT_SIGHT
	MapEvents.bush_factor = NIGHT_BUSH
	_darken(String(data.get("style", "night")), 2.0 if elapsed < 0.5 else 0.0)

func _environment() -> Environment:
	var node = _find_in_scene("WorldEnvironment")
	return node.environment if node is WorldEnvironment else null

func _sun() -> DirectionalLight3D:
	return _find_in_scene("Sun") as DirectionalLight3D

func _find_in_scene(node_name: String) -> Node:
	var scene = get_tree().current_scene
	var found = scene.find_child(node_name, true, false) if scene else null
	return found if found else get_tree().root.find_child(node_name, true, false)

func _darken(style: String, seconds: float) -> void:
	_set_atmosphere(style, seconds)
	if style == "fog":
		_put_out_lantern()
		_start_mist()
	else:
		_stop_mist()
		_light_lantern()

func _restore_atmosphere(seconds: float) -> void:
	_put_out_lantern()
	_stop_mist()
	if not _atmo.is_empty():
		_set_atmosphere("", seconds)

## Tween the environment to the look of `style` ("night", "fog", "" = the normal day). The day
## values are saved the first time, so night after fog (or the other way round) starts from them.
func _set_atmosphere(style: String, seconds: float) -> void:
	if _atmo.is_empty():
		var env0 = _environment()
		var sun0 = _sun()
		_atmo = {"env": env0, "sun": sun0}
		if env0:
			_atmo.merge({"ambient": env0.ambient_light_energy, "sky": env0.background_energy_multiplier,
				"adjust": env0.adjustment_enabled, "brightness": env0.adjustment_brightness,
				"saturation": env0.adjustment_saturation, "fog_density": env0.fog_density,
				"fog_color": env0.fog_light_color, "fog_energy": env0.fog_light_energy,
				"fog_scatter": env0.fog_sun_scatter})
		if sun0:
			_atmo.merge({"sun_energy": sun0.light_energy, "sun_color": sun0.light_color})
	var b = _atmo
	var env: Environment = b.get("env")
	var sun = b.get("sun")
	var night = style == "night"
	var fog = style == "fog"
	var targets := []  # [object, property, value]
	if env:
		if style != "":
			env.adjustment_enabled = true
		targets.append([env, "ambient_light_energy", b.ambient * (0.5 if night else 1.0)])
		targets.append([env, "background_energy_multiplier", 0.3 if night else b.sky])
		targets.append([env, "adjustment_brightness", 0.72 if night else b.brightness])
		targets.append([env, "adjustment_saturation", 0.75 if night else (0.62 if fog else b.saturation)])
		targets.append([env, "fog_density", 0.03 if fog else b.fog_density])
		targets.append([env, "fog_light_color", Color(0.8, 0.82, 0.86) if fog else b.fog_color])
		targets.append([env, "fog_light_energy", 1.0 if fog else b.fog_energy])
		targets.append([env, "fog_sun_scatter", 0.0 if fog else b.fog_scatter])
	if sun and is_instance_valid(sun):
		# Back to the day's light as it is now: GameEnvironment moves it towards the sunset
		var day_color: Color = b.sun_color
		var day_energy: float = b.sun_energy
		var environment = _find_in_scene("GameEnvironment")
		if environment and environment.has_method("day_light"):
			var light = environment.day_light()
			day_color = light[0]
			day_energy = light[1]
		targets.append([sun, "light_energy", day_energy * (0.3 if night else 1.0)])
		targets.append([sun, "light_color", Color(0.6, 0.7, 1.0) if night else day_color])
	var back_to_day = env and style == ""
	if targets.is_empty():
		return
	if seconds <= 0.0 or not is_inside_tree() or is_queued_for_deletion():
		for v in targets:
			v[0].set(v[1], v[2])
		if back_to_day:
			env.adjustment_enabled = b.adjust
		return
	var t = _fresh_atmo_tween()
	for v in targets:
		t.tween_property(v[0], v[1], v[2], seconds)
	if back_to_day:
		var adjust: bool = b.adjust
		t.chain().tween_callback(func(): env.adjustment_enabled = adjust)

func _put_out_lantern() -> void:
	if _lantern and is_instance_valid(_lantern):
		_lantern.queue_free()
	_lantern = null

func _stop_mist() -> void:
	if _mist and is_instance_valid(_mist):
		_mist.emitting = false
		var mist = _mist
		get_tree().create_timer(mist.lifetime).timeout.connect(mist.queue_free)
	_mist = null

func _fresh_atmo_tween() -> Tween:
	if _atmo_tween and _atmo_tween.is_valid():
		_atmo_tween.kill()
	_atmo_tween = create_tween().set_parallel(true)
	return _atmo_tween

## Night: a warm light around your own hero, so the ground near you stays readable
func _light_lantern() -> void:
	var me = viewer()
	if not me or (_lantern and is_instance_valid(_lantern)):
		return
	_lantern = OmniLight3D.new()
	_lantern.name = "NightLantern"
	_lantern.light_color = Color(1.0, 0.86, 0.62)
	_lantern.light_energy = 0.0
	_lantern.omni_range = 7.5
	_lantern.shadow_enabled = false
	me.add_child(_lantern)
	_lantern.position = Vector3(0, 2.4, 0)
	create_tween().tween_property(_lantern, "light_energy", 1.5, 2.0)

## Fog: soft puffs drifting over the ground around you
func _start_mist() -> void:
	if _mist and is_instance_valid(_mist):
		return
	_mist = GPUParticles3D.new()
	_mist.name = "Mist"
	_mist.amount = 36
	_mist.lifetime = 7.0
	_mist.preprocess = 3.0
	_mist.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 8, 40))
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13, 0.6, 13)
	pm.direction = Vector3(1, 0, 0.3)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.8
	pm.scale_max = 1.5
	var fade = Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.3, 1.0))
	fade.add_point(Vector2(0.7, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var fade_tex = CurveTexture.new()
	fade_tex.curve = fade
	pm.scale_curve = fade_tex
	pm.color = Color(0.92, 0.94, 0.97, 0.22)
	_mist.process_material = pm
	var quad = QuadMesh.new()
	quad.size = Vector2(5.0, 5.0)
	quad.material = LandingImpact.soft_particle_material(false)
	_mist.draw_pass_1 = quad
	add_child(_mist)
	_follow_viewer()

func _follow_viewer() -> void:
	if not _mist or not is_instance_valid(_mist):
		return
	var me = viewer()
	if me:
		_mist.global_position = me.global_position + Vector3(0, 0.8, 0)

# ---------------------------------------------------------------- flood

func _flood(data: Dictionary, elapsed: float) -> void:
	var left = max(FLOOD_TIME - elapsed, 0.0)
	for c in data.get("deepen", []):
		var tile = grid.get_tile(c)
		if tile and tile.biome_type == HexTile.BiomeType.SHALLOW_WATER:
			tile.flood(HexTile.BiomeType.WATER, tile.position.y, left * 0.5)
	for entry in data.get("drown", []):
		var tile = grid.get_tile(entry[0])
		if not tile or not tile.is_playable() or tile.is_water():
			continue
		var water_y = float(entry[1])
		_carry_loot(tile, water_y - tile.position.y, left)
		tile.flood(HexTile.BiomeType.SHALLOW_WATER, water_y, left)
		if left > 0.0:
			get_tree().create_timer(left).timeout.connect(_splash_on.bind(tile))

func _splash_on(tile: HexTile) -> void:
	if is_instance_valid(tile) and tile.is_inside_tree():
		WaterRipples.splash(tile.global_position + Vector3(0, HexTile.HEX_HEIGHT * 0.5, 0), 0.8)

## Containers and items lying on a sinking shore go down with it
func _carry_loot(tile: HexTile, dy: float, seconds: float) -> void:
	var center = Vector2(tile.global_position.x, tile.global_position.z)
	for group in ["loot_items", "loot_containers"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D and Vector2(node.global_position.x, node.global_position.z).distance_to(center) < HexTile.HEX_RADIUS * 0.95:
				if seconds > 0.0:
					node.create_tween().tween_property(node, "position:y", node.position.y + dy, seconds).set_trans(Tween.TRANS_SINE)
				else:
					node.position.y += dy

# ---------------------------------------------------------------- rift

func _rift(data: Dictionary, elapsed: float) -> void:
	var coords: Array = data.get("coords", [])
	var warn = float(data.get("warn", 10.0))
	var burn = float(data.get("burn", 3.0))
	var origin: Vector3 = data.get("origin", Vector3.ZERO)
	var dir: Vector3 = data.get("dir", Vector3.RIGHT)
	var rise_in = warn + burn - elapsed
	if rise_in <= 0.0:
		_rift_rise(coords, origin, dir, false)
		return
	if elapsed < warn:
		_set_rift_state(coords, HexTile.ZoneState.WARNED)
		get_tree().create_timer(warn - elapsed).timeout.connect(_rift_burn.bind(coords, burn))
	else:
		_rift_burn(coords, rise_in)
	get_tree().create_timer(rise_in).timeout.connect(_rift_rise.bind(coords, origin, dir, true))

func _set_rift_state(coords: Array, state: int) -> void:
	for c in coords:
		var tile = grid.get_tile(c)
		if tile and tile.is_playable():
			tile.set_zone_state(state)

func _rift_burn(coords: Array, seconds: float) -> void:
	_set_rift_state(coords, HexTile.ZoneState.BURNING)
	_rift_burning.clear()
	for c in coords:
		_rift_burning[c] = true
	_rift_burn_left = seconds
	_rift_tick = 0.0

## Server: whoever stands in the burning crack gets burned like in the zone fire
func _burn_rift() -> void:
	if not authority:
		return
	for p in movers():
		if _rift_burning.has(grid.world_to_hex(p.global_position - grid.global_position)):
			var health = p.get_component("HealthComponent")
			if health:
				health.take_damage(DestructionSystem.BURN_DAMAGE, null)

func _rift_rise(coords: Array, origin: Vector3, dir: Vector3, animated: bool) -> void:
	_rift_burning.clear()
	_rift_burn_left = 0.0
	var raising := {}
	for c in coords:
		raising[c] = true
	if animated:
		for p in movers():
			shove_sideways(p, grid, raising, origin, dir)
	for c in coords:
		var tile = grid.get_tile(c)
		if tile and tile.is_playable():
			tile.raise_mountain(animated)
			tile_raised.emit(c)
	if animated:
		get_tree().create_timer(HexTile.MOUNTAIN_RISE_TIME + 0.1).timeout.connect(_rift_unstick)

## Whoever got stuck in the rock anyway is put next to it (and hurt, on the server)
func _rift_unstick() -> void:
	for p in movers():
		if DestructionSystem.unstick(p, grid) and authority:
			var health = p.get_component("HealthComponent")
			if health:
				health.take_damage(DestructionSystem.CRUSH_DAMAGE, null)

## Standing on the rift when it rises: pushed off to the side you are on
static func shove_sideways(entity: Node, hex_grid: HexGrid, raising: Dictionary, origin: Vector3, dir: Vector3) -> void:
	if not entity is Node3D or not entity.has_method("get_component"):
		return
	if not raising.has(hex_grid.world_to_hex(entity.global_position - hex_grid.global_position)):
		return
	var side = Vector3(-dir.z, 0.0, dir.x).normalized()
	var off: Vector3 = entity.global_position - origin
	if off.dot(side) < 0.0:
		side = -side
	var movement = entity.get_component("MovementComponent")
	if movement:
		movement.dash(side * DestructionSystem.PUSH_SPEED, DestructionSystem.PUSH_TIME)

# ---------------------------------------------------------------- harvest

func _harvest(data: Dictionary, elapsed: float) -> void:
	var patch = HarvestPatch.new()
	patch.bonus = int(data.get("bonus", 0))
	patch.item_id = int(data.get("item_id", 0))
	patch.grow_time = max(float(data.get("grow", 10.0)) - elapsed, 0.0)
	_harvest_ids[patch.item_id] = patch.bonus
	add_child(patch)
	patch.global_position = data.get("pos", Vector3.ZERO)
	# The picker glows: here when this peer picks it (server, the picker's own client, offline),
	# through NetworkLootManager when someone else does (_on_item_picked)
	if is_instance_valid(patch.item):
		patch.item.item_picked_up.connect(_on_harvest_taken.bind(patch.item_id))

static func harvest_color(bonus: int) -> Color:
	return HARVEST_COLORS[clamp(bonus, 0, HARVEST_COLORS.size() - 1)]

static func harvest_name(bonus: int) -> String:
	return HARVEST_NAMES[clamp(bonus, 0, HARVEST_NAMES.size() - 1)]

## The picker gets the bonus (LootItem: on the server entity and on the picker's own client)
static func apply_harvest(player: Node, bonus: int) -> void:
	if not player or not player.has_method("get_component") or not player.is_inside_tree():
		return
	var tree = player.get_tree()
	var seconds = HARVEST_TIME
	match bonus:
		Harvest.SPEED:
			var movement = player.get_component("MovementComponent")
			if movement:
				movement.speed *= HARVEST_SPEED
				tree.create_timer(HARVEST_TIME).timeout.connect(func(): movement.speed /= HARVEST_SPEED)
		Harvest.DAMAGE:
			var combat = player.get_component("CombatComponent")
			if combat:
				combat.ranged_damage_multiplier *= HARVEST_DAMAGE
				tree.create_timer(HARVEST_TIME).timeout.connect(func(): combat.ranged_damage_multiplier /= HARVEST_DAMAGE)
		_:
			var health = player.get_component("HealthComponent")
			if health:
				health.set_shield(HealthComponent.MAX_SHIELD)
				health.heal(HARVEST_HEAL)
			seconds = 3.0
	# PlayerHUD shows the bonus and how long it lasts
	player.set_meta("harvest_bonus", bonus)
	player.set_meta("harvest_until", Time.get_ticks_msec() + int(seconds * 1000.0))

## Someone took a harvest bonus: everyone who has a copy of them sees the glow around them
func _on_item_picked(item_id: int, player_id: int) -> void:
	if not _harvest_ids.has(item_id):
		return
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and p.get("entity_id") == player_id:
			_on_harvest_taken(null, p, item_id)
			return

func _on_harvest_taken(_item, player: Node, item_id: int) -> void:
	if not _harvest_ids.has(item_id) or not player is Node3D or not is_instance_valid(player):
		return
	var bonus: int = _harvest_ids[item_id]
	_harvest_ids.erase(item_id)
	_aura(player, harvest_color(bonus), HARVEST_TIME if bonus != Harvest.SHIELD else 2.5)

func _aura(player: Node3D, color: Color, seconds: float) -> void:
	var old = player.get_node_or_null("HarvestAura")
	if old:
		old.queue_free()
	var aura = GPUParticles3D.new()
	aura.name = "HarvestAura"
	aura.amount = 18
	aura.lifetime = 0.9
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.55
	pm.emission_ring_inner_radius = 0.4
	pm.emission_ring_height = 0.05
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3.ZERO
	var shrink = Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	var shrink_tex = CurveTexture.new()
	shrink_tex.curve = shrink
	pm.scale_curve = shrink_tex
	pm.color = color
	aura.process_material = pm
	var quad = QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	quad.material = LandingImpact.soft_particle_material(true)
	aura.draw_pass_1 = quad
	player.add_child(aura)
	aura.position = Vector3(0, 0.1, 0)
	player.get_tree().create_timer(seconds).timeout.connect(func():
		if is_instance_valid(aura):
			aura.emitting = false
			aura.get_tree().create_timer(1.0).timeout.connect(aura.queue_free))
