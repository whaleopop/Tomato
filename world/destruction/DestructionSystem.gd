## The shrinking zone (server side). The island closes in on a random spot near the middle:
## every phase, the tiles further than the phase radius (hex distance from the zone center) are
##   MARKED - glowing cracks on the tiles and on the minimap, a countdown in the HUD;
##   BURNING - fire on them, anyone standing there gets burned;
##   RAISED - a mountain rises and shoves whoever is still there towards the center.
## The outer ring is mountains from the start (HexGenerator), so nobody can fall off. After the last
## phase only the core is left, and it catches fire every now and then, so a match always ends.
## Once the safe area is down to SHIFT_RADIUS the final zone moves over by a tile or two: announced
## at the start of the pause (center_shift_announced -> MapEventDirector -> HUD), applied at the
## next warning.
## Every step goes to the clients through NetworkManager.broadcast_zone; late joiners get the
## current one from send_state_to().
extends Node
class_name DestructionSystem

signal destruction_phase_started(phase: int)  # a phase's mountains rise
signal tile_destroyed(coords: Vector2i)       # a tile became a mountain (ServerWorld records it)
signal phase_warned(phase: int, center: Vector2i, radius: int)  # a new step is marked (the zone drop)
signal center_shift_announced(new_center: Vector2i, seconds: float, radius: int)

enum Stage { IDLE, WAIT, WARN, BURN }

const FIRST_WAIT: float = 25.0
const WARN_TIMES = [22.0, 20.0, 18.0, 16.0, 14.0, 12.0]  # per phase, the last one repeats
const WAIT_TIMES = [16.0, 14.0, 12.0, 11.0, 10.0, 9.0]
const BURN_TIME: float = 4.0
const FINAL_RADIUS: int = 1         # the 7 tiles around the center never become mountains
const BURN_TICK: float = 0.5
const BURN_DAMAGE: float = 6.0      # per tick: 12 per second in the fire
const CORE_WAIT: float = 20.0       # after the last phase: the core burns this often
const CORE_WARN: float = 6.0
const PUSH_SPEED: float = 13.0      # the rising mountain shoves you off
const PUSH_TIME: float = 0.45
const CRUSH_DAMAGE: float = 15.0    # still inside when it has risen: thrown out and hurt
const SHIFT_RADIUS: int = 3         # the final zone moves once the safe radius is this small

var grid: HexGrid = null
var is_active: bool = false
var current_phase: int = 0
var center: Vector2i = Vector2i.ZERO
var time_scale: float = 1.0         # tests fast-forward the zone
var stage: int = Stage.IDLE
var stage_left: float = 0.0
var marked: Array = []              # coords of the tiles of the current step
var core_mode: bool = false         # the last phase is done: the core burns now and then
var _radius: int = 0                # current safe radius
var _burn_tick: float = 0.0
var _shift_to = null                # Vector2i: the center of the next step (announced shift)
var _shifted: bool = false

## Current safe radius around `center` (hex distance)
func safe_radius() -> int:
	return _radius

func start(p_grid: HexGrid):
	grid = p_grid
	is_active = true
	current_phase = 0
	core_mode = false
	_shift_to = null
	_shifted = false
	center = _pick_center()
	_radius = _max_distance()
	_enter(Stage.WAIT, FIRST_WAIT)

func stop():
	is_active = false

func _process(delta: float):
	if not is_active or grid == null or not is_instance_valid(grid):
		return
	var dt = delta * time_scale
	stage_left -= dt
	if stage == Stage.BURN:
		_burn_tick -= dt
		if _burn_tick <= 0.0:
			_burn_tick += BURN_TICK
			_burn_players()
	if stage_left > 0.0:
		return
	match stage:
		Stage.WAIT:
			_begin_warning()
		Stage.WARN:
			_begin_burn()
		Stage.BURN:
			_end_burn()

func _enter(new_stage: int, seconds: float):
	stage = new_stage
	stage_left = seconds

# ---------------------------------------------------------------- phases

func _begin_warning():
	marked.clear()
	if _shift_to != null:
		center = _shift_to
		_shift_to = null
	if not core_mode:
		var r = _radius - 1
		while r >= FINAL_RADIUS and marked.is_empty():
			marked = _tiles_outside(r)
			if marked.is_empty():
				r -= 1
		if marked.is_empty():
			core_mode = true
		else:
			_radius = r
	if core_mode:
		marked = _tiles_outside(-1)  # everything that is left
		if marked.is_empty():
			stop()
			return
	current_phase += 1
	var seconds = CORE_WARN if core_mode else _at(WARN_TIMES, current_phase - 1)
	_set_states(HexTile.ZoneState.WARNED)
	_broadcast("core_warn" if core_mode else "warn", seconds)
	_enter(Stage.WARN, seconds)
	if not core_mode:
		phase_warned.emit(current_phase, center, _radius)

func _begin_burn():
	_set_states(HexTile.ZoneState.BURNING)
	_broadcast("core_burn" if core_mode else "burn", BURN_TIME)
	_burn_tick = 0.0
	_enter(Stage.BURN, BURN_TIME)

func _end_burn():
	if core_mode:
		_set_states(HexTile.ZoneState.NONE)
		_broadcast("calm", CORE_WAIT)
		_enter(Stage.WAIT, CORE_WAIT)
		return
	# Mountains: shove the people off first, then raise them
	var raising := {}
	for c in marked:
		raising[c] = true
	var center_world = grid.hex_to_world(center)
	for player in get_tree().get_nodes_in_group("players"):
		shove(player, grid, raising, center_world)
	for c in marked:
		var tile = grid.get_tile(c)
		if tile:
			tile.raise_mountain(true)
			tile_destroyed.emit(c)
	_broadcast("rise", _at(WAIT_TIMES, current_phase - 1))
	destruction_phase_started.emit(current_phase)
	# Whoever got stuck anyway (blocked by a wall) is thrown out once the rock is up
	get_tree().create_timer(HexTile.MOUNTAIN_RISE_TIME + 0.1).timeout.connect(func():
		if not is_instance_valid(grid):
			return
		for player in get_tree().get_nodes_in_group("players"):
			if unstick(player, grid):
				var health = player.get_component("HealthComponent") if player.has_method("get_component") else null
				if health:
					health.take_damage(CRUSH_DAMAGE, null)
	)
	_enter(Stage.WAIT, _at(WAIT_TIMES, current_phase - 1))
	if not _shifted and _radius <= SHIFT_RADIUS and _radius - 1 >= FINAL_RADIUS:
		_plan_shift()

## The final zone moves over: a new center one or two tiles away, as long as enough of the island
## is left around it. Announced now, applied when the next step is marked.
func _plan_shift():
	_shifted = true
	var r = _radius - 1
	var best: Array = []
	for d in [2, 1]:
		for c in grid.tiles:
			var tile = grid.get_tile(c)
			if not tile or not tile.is_playable() or tile.is_water() or _dist(c, center) != d:
				continue
			var room = 0
			for other in grid.tiles:
				var t = grid.get_tile(other)
				if t and t.is_playable() and _dist(other, c) <= r:
					room += 1
			if room >= 7:
				best.append(c)
		if not best.is_empty():
			break
	if best.is_empty():
		return
	best.sort()
	_shift_to = best[randi() % best.size()]
	center_shift_announced.emit(_shift_to, stage_left, r)

func _burn_players():
	var burning := {}
	for c in marked:
		burning[c] = true
	for player in get_tree().get_nodes_in_group("players"):
		if not player is Node3D or not player.has_method("get_component"):
			continue
		var health = player.get_component("HealthComponent")
		if health and not health.is_dead and burning.has(grid.world_to_hex(player.global_position - grid.global_position)):
			health.take_damage(BURN_DAMAGE, null)

func _set_states(state: int):
	for c in marked:
		var tile = grid.get_tile(c)
		if tile:
			tile.set_zone_state(state)

func _broadcast(kind: String, seconds: float):
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_method("broadcast_zone"):
		network_manager.broadcast_zone(kind, marked.duplicate(), seconds, center, _radius)

## What a late joiner needs to show the step in progress
func state_for_late_join() -> Dictionary:
	if not is_active or stage == Stage.WAIT or stage == Stage.IDLE:
		return {}
	var kind = "burn" if stage == Stage.BURN else "warn"
	if core_mode:
		kind = "core_" + kind
	return {"kind": kind, "coords": marked.duplicate(), "seconds": max(stage_left, 0.1), "center": center, "radius": _radius}

# ---------------------------------------------------------------- shared rules (server and client)

## Standing on a tile that turns into a mountain: dashed towards the zone center
static func shove(entity: Node, hex_grid: HexGrid, raising: Dictionary, center_world: Vector3) -> void:
	if not entity is Node3D or not entity.has_method("get_component"):
		return
	var health = entity.get_component("HealthComponent")
	if health and health.is_dead:
		return
	if not raising.has(hex_grid.world_to_hex(entity.global_position - hex_grid.global_position)):
		return
	var dir = center_world - entity.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	var movement = entity.get_component("MovementComponent")
	if movement:
		movement.dash(dir.normalized() * PUSH_SPEED, PUSH_TIME)

## Inside a mountain: put back onto the nearest walkable tile. True if it had to.
static func unstick(entity: Node, hex_grid: HexGrid) -> bool:
	if not entity is Node3D or not entity.has_method("get_component"):
		return false
	var health = entity.get_component("HealthComponent")
	if health and health.is_dead:
		return false
	var here = hex_grid.world_to_hex(entity.global_position - hex_grid.global_position)
	var tile = hex_grid.get_tile(here)
	if tile and tile.is_playable():
		return false
	var best: HexTile = null
	var best_d = INF
	var keys = hex_grid.tiles.keys()
	keys.sort()  # the same choice on the server and the client
	for c in keys:
		var t = hex_grid.get_tile(c)
		if not t or not t.is_playable():
			continue
		var d = t.global_position.distance_squared_to(entity.global_position)
		if d < best_d - 0.001:
			best_d = d
			best = t
	if not best:
		return false
	entity.global_position = best.global_position + Vector3(0, HexTile.HEX_HEIGHT * 0.5 + 0.2, 0)
	var movement = entity.get_component("MovementComponent")
	if movement:
		movement.stop()
	return true

# ---------------------------------------------------------------- helpers

## A random playable tile near the middle of the map
func _pick_center() -> Vector2i:
	var candidates: Array = []
	for c in grid.tiles:
		var tile = grid.get_tile(c)
		if tile and tile.is_playable() and _dist(c, Vector2i.ZERO) <= 2 and not tile.is_water():
			candidates.append(c)
	if candidates.is_empty():
		return Vector2i.ZERO
	candidates.sort()
	return candidates[randi() % candidates.size()]

func _max_distance() -> int:
	var m = 0
	for c in grid.tiles:
		var tile = grid.get_tile(c)
		if tile and tile.is_playable():
			m = max(m, _dist(c, center))
	return m

## Playable tiles further than `r` from the center (r < 0: all of them)
func _tiles_outside(r: int) -> Array:
	var result: Array = []
	for c in grid.tiles:
		var tile = grid.get_tile(c)
		if tile and tile.is_playable() and (r < 0 or _dist(c, center) > r):
			result.append(c)
	result.sort()
	return result

static func _dist(a: Vector2i, b: Vector2i) -> int:
	var d = a - b
	return max(abs(d.x), abs(d.y), abs(d.x + d.y))

func _at(list: Array, index: int) -> float:
	return list[min(index, list.size() - 1)]
