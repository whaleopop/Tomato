## Picks the map events (server only). Every GAP_MIN..GAP_MAX seconds one comes out of a shuffled
## bag (meteors, harvest, quake, night / fog, flood, rift); the zone brings its own: a rich supply
## drop into the next safe area on some steps (ZONE_DROP_PHASES) and the final center shift
## (DestructionSystem.center_shift_announced). The director chooses the spots, walls and tiles and
## hands the event to MapEvents (the host's world) and NetworkManager.broadcast_map_event (the
## clients and every HUD). `history` keeps what a late joiner still has to see.
extends Node
class_name MapEventDirector

const FIRST_EVENT: float = 60.0       # after GameServer.LATE_JOIN_WINDOW: late joiners rarely miss one
const GAP_MIN: float = 32.0
const GAP_MAX: float = 46.0
const BAG = ["meteors", "harvest", "quake", "night", "flood", "rift", "meteors", "harvest"]
const ONCE = ["flood", "rift"]        # once per match
const HUD_ONLY = ["zone_drop", "center_shift"]
const ZONE_DROP_PHASES = [2, 4, 6]
const HARVEST_ID_BASE: int = 9000000  # loot item ids of the harvest bonuses (container loot: id * 100 + n)
const HARVEST_GROW: float = 10.0
const METEOR_WARN: float = 3.0
const METEOR_SPACING: float = 3.2
const QUAKE_TIME: float = 5.0
const QUAKE_WALL_SHARE: float = 0.4
const NIGHT_TIME: float = 25.0
const RIFT_WARN: float = 10.0
const RIFT_BURN: float = 3.0
const RIFT_KEEP: int = 2              # the rift stops this close to the zone center: the halves stay linked
const RIFT_MIN_RADIUS: int = 4        # only while the island is still big

var grid: HexGrid = null
var destruction: DestructionSystem = null
var events: MapEvents = null
var loot_spawner: LootSpawner = null
var cover: CoverSpawner = null
var is_active: bool = false
var time_scale: float = 1.0           # tests fast-forward it
var history: Array = []               # [kind, data, start_s]
var rng := RandomNumberGenerator.new()
var _next: float = 0.0
var _bag: Array = []
var _done: Dictionary = {}
var _harvests: int = 0

func setup(p_grid: HexGrid, p_destruction: DestructionSystem, p_events: MapEvents, p_loot: LootSpawner, p_cover: CoverSpawner) -> void:
	grid = p_grid
	destruction = p_destruction
	events = p_events
	loot_spawner = p_loot
	cover = p_cover
	if destruction:
		if not destruction.phase_warned.is_connected(_on_phase_warned):
			destruction.phase_warned.connect(_on_phase_warned)
		if not destruction.center_shift_announced.is_connected(_on_center_shift):
			destruction.center_shift_announced.connect(_on_center_shift)

func start() -> void:
	rng.randomize()
	is_active = true
	history.clear()
	_bag.clear()
	_done.clear()
	_harvests = 0
	_next = FIRST_EVENT

func stop() -> void:
	is_active = false

func _process(delta: float):
	if not is_active or not grid or not is_instance_valid(grid):
		return
	_next -= delta * time_scale
	if _next > 0.0:
		return
	_next = rng.randf_range(GAP_MIN, GAP_MAX)
	fire_random()

## The next event from the bag that can happen right now ("" if none)
func fire_random() -> String:
	for attempt in BAG.size() + 1:
		if _bag.is_empty():
			_bag = BAG.duplicate()
			for i in range(_bag.size() - 1, 0, -1):  # own RNG, not Array.shuffle()
				var j = rng.randi_range(0, i)
				var tmp = _bag[i]
				_bag[i] = _bag[j]
				_bag[j] = tmp
		var kind: String = _bag.pop_back()
		if trigger(kind):
			return kind
	return ""

## Plan `kind` and play it now (also used by tests and the trailer). False if it can't happen now.
func trigger(kind: String) -> bool:
	var data = plan(kind)
	if data.is_empty():
		return false
	send(kind, data)
	return true

func send(kind: String, data: Dictionary) -> void:
	print("[MapEventDirector] %s" % kind)
	if kind in ONCE:
		_done[kind] = true
	if not kind in HUD_ONLY:
		history.append([kind, data, _now()])
	if events and is_instance_valid(events):
		events.play(kind, data, 0.0)
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_method("broadcast_map_event"):
		network_manager.broadcast_map_event(kind, data)

func plan(kind: String) -> Dictionary:
	if not grid or not is_instance_valid(grid):
		return {}
	if kind in ONCE and _done.has(kind):
		return {}
	match kind:
		"meteors":
			return _plan_meteors()
		"quake":
			return _plan_quake()
		"night":
			return {"seconds": NIGHT_TIME, "style": "fog" if rng.randf() < 0.5 else "night"}
		"flood":
			return _plan_flood()
		"rift":
			return _plan_rift()
		"harvest":
			return _plan_harvest()
	return {}

## What a player joining now still has to see (MapEvents skips what is already over)
func history_for_late_join() -> Array:
	var now = _now()
	var result: Array = []
	for e in history:
		var elapsed = now - float(e[2])
		if e[0] == "meteors" and elapsed > 8.0:
			continue
		if e[0] == "night" and elapsed > float(e[1].get("seconds", NIGHT_TIME)):
			continue
		result.append([e[0], e[1], elapsed])
	return result

# ---------------------------------------------------------------- planning

func _plan_meteors() -> Dictionary:
	var tiles = _safe_tiles(0)
	if tiles.is_empty():
		return {}
	var points: Array = []
	# Some of them fall right next to people: keep moving
	var players = _alive_players()
	for p in players:
		if points.size() >= 4:
			break
		if rng.randf() < 0.65:
			var spot = p.global_position + Vector3(rng.randf_range(-2.5, 2.5), 0.0, rng.randf_range(-2.5, 2.5))
			_add_point(points, spot)
	var want = rng.randi_range(6, 9)
	var guard = 0
	while points.size() < want and guard < 80:
		guard += 1
		var c: Vector2i = tiles[rng.randi() % tiles.size()]
		_add_point(points, grid.hex_to_world(c) + Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2)))
	if points.is_empty():
		return {}
	var delays: Array = []
	for i in points.size():
		delays.append(METEOR_WARN + i * 0.3 + rng.randf_range(0.0, 0.2))
	return {"points": points, "delays": delays}

func _add_point(points: Array, spot: Vector3) -> void:
	var tile = grid.get_tile(grid.world_to_hex(spot))
	if not tile or not tile.is_playable() or tile.is_water():
		return
	var ground = Vector3(spot.x, CoverSpawner.tile_top(tile), spot.z)
	for other in points:
		if other.distance_to(ground) < METEOR_SPACING:
			return
	points.append(ground)

func _plan_quake() -> Dictionary:
	var walls: Array = []
	if cover and is_instance_valid(cover):
		var names: Array = []
		for w in cover.walls:
			if is_instance_valid(w) and w.is_inside_tree() and not w._falling:
				names.append(String(w.name))
		names.sort()
		for n in names:
			if rng.randf() < QUAKE_WALL_SHARE:
				walls.append([n, rng.randf_range(0.3, QUAKE_TIME - 0.5)])
	return {"seconds": QUAKE_TIME, "walls": walls}

## Shallows turn deep, low shores next to the water go under (not the zone's core)
func _plan_flood() -> Dictionary:
	var deepen: Array = []
	var drown: Array = []
	var keys: Array = grid.tiles.keys()
	keys.sort()
	for c in keys:
		var tile = grid.get_tile(c)
		if not tile or not tile.is_playable():
			continue
		if tile.biome_type == HexTile.BiomeType.SHALLOW_WATER:
			deepen.append(c)
			continue
		if tile.is_water() or (destruction and DestructionSystem._dist(c, destruction.center) <= DestructionSystem.FINAL_RADIUS):
			continue
		var water_y = -INF
		for dir in HexTile.EDGE_DIRECTIONS:
			var n = grid.get_tile(c + dir)
			if n and n.is_water() and not n.is_destroyed:
				water_y = max(water_y, n.position.y)
		if water_y == -INF:
			continue
		if tile.level > 0:
			continue  # the terraces stay dry
		if tile.biome_type == HexTile.BiomeType.BEACH or tile.position.y - water_y < 0.2:
			drown.append([c, water_y])
	if deepen.size() + drown.size() < 3:
		return {}
	return {"deepen": deepen, "drown": drown}

## A straight crack through the zone center, both ways out to the edge, sparing the middle
func _plan_rift() -> Dictionary:
	if not destruction or destruction.core_mode:
		return {}
	var r = destruction.safe_radius()
	if r < RIFT_MIN_RADIUS:
		return {}
	var zone_center = destruction.center
	var center_world = grid.hex_to_world(zone_center)
	var a = rng.randf() * TAU
	var dir = Vector3(cos(a), 0.0, sin(a))
	var coords: Array = []
	var seen := {}
	var reach = (r + 2) * VisibilitySystem.HEX_SPACING
	var t = -reach
	while t <= reach:
		var c = grid.world_to_hex(center_world + dir * t)
		t += 0.4
		if seen.has(c):
			continue
		seen[c] = true
		if DestructionSystem._dist(c, zone_center) <= RIFT_KEEP:
			continue
		var tile = grid.get_tile(c)
		if tile and tile.is_playable() and tile.zone_state == HexTile.ZoneState.NONE:
			coords.append(c)
	if coords.size() < 5:
		return {}
	return {"coords": coords, "warn": RIFT_WARN, "burn": RIFT_BURN, "origin": center_world, "dir": dir}

## Somewhere in the safe area, away from everybody (worth running for)
func _plan_harvest() -> Dictionary:
	var tiles = _safe_tiles(1)
	if tiles.is_empty():
		tiles = _safe_tiles(0)
	if tiles.is_empty():
		return {}
	var players = _alive_players()
	var containers = CoverSpawner.container_tiles(grid, loot_spawner)
	var choice: Array = []
	for min_gap in [3, 2, 0]:
		choice.clear()
		for c in tiles:
			if containers.has(c):
				continue
			var ok = true
			for p in players:
				if DestructionSystem._dist(grid.world_to_hex(p.global_position), c) < min_gap:
					ok = false
					break
			if ok:
				choice.append(c)
		if not choice.is_empty():
			break
	if choice.is_empty():
		return {}
	var spot: Vector2i = choice[rng.randi() % choice.size()]
	var tile = grid.get_tile(spot)
	_harvests += 1
	return {"pos": grid.hex_to_world(spot) + Vector3(0, CoverSpawner.tile_top(tile), 0),
		"bonus": rng.randi() % MapEvents.HARVEST_NAMES.size(), "item_id": HARVEST_ID_BASE + _harvests, "grow": HARVEST_GROW}

# ---------------------------------------------------------------- tied to the zone

## A zone step was marked: on some steps a rich supply drop falls into the new safe area
func _on_phase_warned(phase: int, zone_center: Vector2i, radius: int) -> void:
	if not is_active or not phase in ZONE_DROP_PHASES or not loot_spawner:
		return
	var tiles: Array = []
	for c in grid.tiles:
		var tile = grid.get_tile(c)
		if tile and tile.is_playable() and not tile.is_water() and tile.zone_state == HexTile.ZoneState.NONE \
				and DestructionSystem._dist(c, zone_center) <= max(radius - 1, 0):
			tiles.append(c)
	if tiles.is_empty():
		return
	tiles.sort()
	var spot: Vector2i = tiles[rng.randi() % tiles.size()]
	var pos = grid.hex_to_world(spot) + Vector3(0, CoverSpawner.tile_top(grid.get_tile(spot)), 0)
	loot_spawner.drop_supplies_at(pos, true)
	send("zone_drop", {"pos": pos})

func _on_center_shift(new_center: Vector2i, seconds: float, radius: int) -> void:
	if is_active:
		send("center_shift", {"center": new_center, "radius": radius, "seconds": seconds})

# ---------------------------------------------------------------- helpers

## Playable tiles in the current safe area, not on fire, land only; `margin` rings inside its edge
func _safe_tiles(margin: int) -> Array:
	var zone_center = destruction.center if destruction else Vector2i.ZERO
	var r = destruction.safe_radius() if destruction and destruction.is_active else 999
	var result: Array = []
	for c in grid.tiles:
		var tile = grid.get_tile(c)
		if tile and tile.is_playable() and not tile.is_water() and tile.zone_state == HexTile.ZoneState.NONE \
				and DestructionSystem._dist(c, zone_center) <= r - margin:
			result.append(c)
	result.sort()
	return result

func _alive_players() -> Array:
	var result: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and p is Node3D and p.has_method("get_component"):
			var health = p.get_component("HealthComponent")
			if not health or not health.is_dead:
				result.append(p)
	return result

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
