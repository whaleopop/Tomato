## Puts the hostile weeds (Weed) on the island - server only. At the match start every land tile
## has a small chance to sprout one (more in the wild biomes: brambles and tall grass grow nettles,
## meadows and swamps hogweed, grass and meadows dandelions), up to CAP. Every WAVE_EVERY seconds
## there is a WAVE_CHANCE that another one sprouts on a safe tile. Clients get the weeds they can
## see in their world state (states_for -> TickSystem "npcs" -> ClientWorld._apply_npcs).
extends Node
class_name WeedSpawner

const START_CHANCE: float = 0.007  # was 0.014 / 22 / 40 s / 0.4: far too many, sprouting all the time
const CAP: int = 12
const WAVE_EVERY: float = 90.0
const WAVE_CHANCE: float = 0.3
const SEEN_FROM: float = 42.0      # world units: weeds further from a client aren't sent to it
const KIND_BY_BIOME = {
	HexTile.BiomeType.THORNS: ["Nettle", 2.5], HexTile.BiomeType.TALL_GRASS: ["Nettle", 2.0],
	HexTile.BiomeType.FOREST: ["Nettle", 1.4], HexTile.BiomeType.SWAMP: ["Hogweed", 2.2],
	HexTile.BiomeType.MEADOW: ["Hogweed", 1.8], HexTile.BiomeType.GRASS: ["Dandelion", 1.0],
	HexTile.BiomeType.DESERT: ["Dandelion", 0.6], HexTile.BiomeType.MUSHROOM: ["Hogweed", 1.2],
}

var grid: HexGrid = null
var world: Node = null             # where the weeds live (ServerWorld / the training ground)
var weeds: Dictionary = {}         # npc id -> Weed
var running: bool = false
var _next_id: int = 1
var _wave: float = 0.0
var _rng := RandomNumberGenerator.new()

func setup(p_grid: HexGrid, p_world: Node, seed_value: int) -> void:
	grid = p_grid
	world = p_world
	_rng.seed = seed_value + 9973

func start() -> void:
	running = true
	_wave = 0.0
	if weeds.is_empty():
		_sprout_initial()

func stop() -> void:
	running = false

func _sprout_initial():
	var keys = grid.tiles.keys()
	keys.sort()
	for c in keys:
		if weeds.size() >= CAP:
			break
		var tile: HexTile = grid.get_tile(c)
		var pick = _kind_for(tile)
		if pick.is_empty():
			continue
		if _rng.randf() < START_CHANCE * float(pick[1]):
			spawn(pick[0], grid.hex_to_world(c) + Vector3(0, CoverSpawner.tile_top(tile) + 0.2, 0))

## [kind, weight] for a tile weeds can grow on, [] if none
func _kind_for(tile: HexTile) -> Array:
	if tile == null or not tile.is_playable() or tile.is_ramp() or tile.is_water() or tile.biome_type == HexTile.BiomeType.MOUNTAIN:
		return []
	if tile.zone_state != HexTile.ZoneState.NONE:
		return []
	if KIND_BY_BIOME.has(tile.biome_type):
		return KIND_BY_BIOME[tile.biome_type]
	return [["Dandelion", "Nettle", "Hogweed"][_rng.randi() % 3], 0.5]

func spawn(kind: String, pos: Vector3) -> Weed:
	var weed = Weed.new()
	weed.npc_id = _next_id
	_next_id += 1
	weed.kind = kind
	weed.authority = true
	weed.name = "Weed_%d" % weed.npc_id
	weed.position = pos
	world.add_child(weed)
	weeds[weed.npc_id] = weed
	weed.tree_exited.connect(func(): weeds.erase(weed.npc_id))
	return weed

func _process(delta: float):
	if not running:
		return
	_wave += delta
	if _wave < WAVE_EVERY:
		return
	_wave = 0.0
	if weeds.size() >= CAP or _rng.randf() > WAVE_CHANCE:
		return
	# A random safe tile away from every hero (they sprout, they don't pop up in your face)
	var keys = grid.tiles.keys()
	for attempt in 30:
		var c = keys[_rng.randi() % keys.size()]
		var tile: HexTile = grid.get_tile(c)
		var pick = _kind_for(tile)
		if pick.is_empty():
			continue
		var pos = grid.hex_to_world(c) + Vector3(0, CoverSpawner.tile_top(tile) + 0.2, 0)
		var near = false
		for p in get_tree().get_nodes_in_group("players"):
			if p is Node3D and p.global_position.distance_to(pos) < 20.0:
				near = true
		if not near:
			spawn(pick[0], pos)
			return

## What one client gets: the weeds near its hero (all of them once it is out)
func states_for(viewer: Node3D) -> Dictionary:
	var out = {}
	var everything = viewer == null or not is_instance_valid(viewer)
	if not everything and viewer.has_method("get_component"):
		var h = viewer.get_component("HealthComponent")
		everything = h != null and h.is_dead
	for id in weeds:
		var w: Weed = weeds[id]
		if not is_instance_valid(w):
			continue
		if everything or w.global_position.distance_to(viewer.global_position) < SEEN_FROM:
			out[id] = w.get_state()
	return out
