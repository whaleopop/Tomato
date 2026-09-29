## Places cover on the map: wall pieces to duck behind and bushes to hide in.
## Deterministic from the map seed (own RNG, sorted tile order), so the server and every client
## build identical cover - walls block movement, bullets and sight, so they must match.
## Walls stand on hex edges: tile centers stay free for spawns and loot containers.
## A piece is 1-3 consecutive edges of one tile (a slab, a corner or a U to hide in).
extends Node3D
class_name CoverSpawner

const COVER_LAYER: int = 16          # physics layer 5: blocks sight and line of fire
const WALL_CHANCE: float = 0.2       # per land tile: a wall piece starts here (tiles are big: 2-unit edges)
const MAX_STEP: float = 1.01         # walls may stand on a step of one height unit
const BUSH_CHANCE: float = 0.16      # per land tile without a container: a bush somewhere on it
const DIRECTIONS = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]  # in order around the hex
const PROPS_DIR := "res://models/props/"

var rng := RandomNumberGenerator.new()
var hex_grid: HexGrid = null
var walls: Array[CoverWall] = []
var bushes: Array[Bush] = []
var landmarks: Array[Landmark] = []
var trees: Array[GardenTree] = []

## occupied: tile coords that must not get a bush (loot containers)
func setup(grid: HexGrid, seed_value: int, occupied: Dictionary = {}) -> void:
	hex_grid = grid
	rng.seed = seed_value + 90210
	# Landmarks first (Landmark.plan: the same spots LootSpawner put their chests on)
	var plan = Landmark.plan(grid, seed_value)
	for entry in plan:
		var landmark = Landmark.new()
		landmark.kind = entry.kind
		landmark.place(grid.get_tile(entry.coords), grid)
		grid.get_tile(entry.coords).set_meta("landmark", entry.kind)  # the landing map shows it
		add_child(landmark)
		landmarks.append(landmark)
	var taken = Landmark.footprint(plan)
	var coords_list: Array = grid.tiles.keys()
	coords_list.sort()
	var used_edges: Dictionary = {}
	for c in coords_list:
		var tile = grid.get_tile(c)
		if not tile or not _is_land(tile):
			continue
		var roll = rng.randf()
		if taken.has(c):
			continue  # the landmark and its chests stand here
		if roll < WALL_CHANCE:
			_place_wall_piece(c, tile, used_edges, taken)
		elif roll < WALL_CHANCE + BUSH_CHANCE and not occupied.has(c):
			_place_bush(c, tile)
	_plant_trees(coords_list, taken, occupied, seed_value)
	print("[CoverSpawner] %d landmarks, %d wall segments, %d bushes, %d trees" % [landmarks.size(), walls.size(), bushes.size(), trees.size()])

## Trees in the forest (and one now and then on grass), off the tile center (containers) and the
## edges (walls). Their own RNG, so the walls and bushes stay where they were.
func _plant_trees(coords_list: Array, taken: Dictionary, occupied: Dictionary, seed_value: int) -> void:
	var tree_rng = RandomNumberGenerator.new()
	tree_rng.seed = seed_value + 31415
	for c in coords_list:
		var tile = hex_grid.get_tile(c)
		if not tile or not _is_land(tile) or taken.has(c):
			continue
		var count = 0
		if tile.biome_type == HexTile.BiomeType.FOREST:
			count = tree_rng.randi_range(1, 3)
		elif tile.biome_type == HexTile.BiomeType.GRASS and tree_rng.randf() < 0.06:
			count = 1
		var start = tree_rng.randf() * TAU
		for i in count:
			var a = start + i * TAU / max(count, 1) + tree_rng.randf_range(-0.4, 0.4)
			var r = tree_rng.randf_range(0.75, 1.1) * HexTile.HEX_RADIUS * 0.55
			var tree = GardenTree.new()
			tree.tree_seed = tree_rng.randi()
			tree.name = "Tree_%d_%d_%d" % [c.x, c.y, i]
			tree.position = hex_grid.hex_to_world(c) + Vector3(cos(a) * r, tile_top(tile), sin(a) * r)
			add_child(tree)
			tree.attach_to(tile)
			trees.append(tree)

## Tiles holding loot containers (same on every peer: containers come from the seeded LootSpawner)
static func container_tiles(grid: HexGrid, loot_spawner: LootSpawner) -> Dictionary:
	var result := {}
	if loot_spawner:
		for container in loot_spawner.spawned_containers:
			if is_instance_valid(container):
				result[grid.world_to_hex(container.position)] = true
	return result

func _is_land(tile: HexTile) -> bool:
	return not tile.is_destroyed and not tile.is_ramp() and not (tile.biome_type in [HexTile.BiomeType.WATER,
		HexTile.BiomeType.SHALLOW_WATER, HexTile.BiomeType.MOUNTAIN])

func _wall_kind(biome: int) -> int:
	match biome:
		HexTile.BiomeType.FOREST, HexTile.BiomeType.SWAMP:
			return CoverWall.Kind.WOOD
		HexTile.BiomeType.DESERT, HexTile.BiomeType.BEACH:
			return CoverWall.Kind.SANDBAG
		HexTile.BiomeType.ROCK:
			return CoverWall.Kind.STONE
	return CoverWall.Kind.STONE if rng.randf() < 0.6 else CoverWall.Kind.WOOD

func _place_wall_piece(c: Vector2i, tile: HexTile, used_edges: Dictionary, taken: Dictionary = {}):
	var kind = _wall_kind(tile.biome_type)
	var start = rng.randi() % 6
	var length = 1 + rng.randi() % 3
	for k in range(length):
		var n: Vector2i = c + DIRECTIONS[(start + k) % 6]
		var key = Vector4i(c.x, c.y, n.x, n.y) if c < n else Vector4i(n.x, n.y, c.x, c.y)
		if used_edges.has(key):
			continue
		var other = hex_grid.get_tile(n)
		# Only between land tiles at most one step apart: no walls over cliffs or water
		if not other or not _is_land(other) or abs(other.height - tile.height) > MAX_STEP or taken.has(n):
			continue
		used_edges[key] = true
		_spawn_wall(tile, other, kind)

func _spawn_wall(a: HexTile, b: HexTile, kind: int):
	var pa = hex_grid.hex_to_world(a.hex_coords)
	var pb = hex_grid.hex_to_world(b.hex_coords)
	var across = (pb - pa).normalized()
	var wall = CoverWall.new()
	wall.kind = kind
	wall.name = "Wall_%d_%d_%d_%d" % [a.hex_coords.x, a.hex_coords.y, b.hex_coords.x, b.hex_coords.y]
	# Stands on the lower tile and reaches up past the step, so both sides get full cover
	var low = min(tile_top(a), tile_top(b))
	wall.extra_height = abs(tile_top(a) - tile_top(b))
	wall.position = (pa + pb) / 2.0 + Vector3(0, low, 0)
	wall.rotation.y = atan2(across.x, across.z)  # local Z across the edge, length along it
	add_child(wall)
	wall.attach_to([a, b])
	walls.append(wall)

func _place_bush(c: Vector2i, tile: HexTile):
	var bush = Bush.new()
	bush.name = "Bush_%d_%d" % [c.x, c.y]
	# Off-center on the big tile, but clear of its edges (walls stand there)
	var a = rng.randf() * TAU
	var off = Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.45) * HexTile.HEX_INNER_RADIUS
	bush.position = hex_grid.hex_to_world(c) + off + Vector3(0, tile_top(tile), 0)
	bush.rotation.y = rng.randf() * TAU
	add_child(bush)
	bush.attach_to(tile)
	bushes.append(bush)

## Height of the walkable top of a tile
static func tile_top(tile: HexTile) -> float:
	return tile.height * HexTile.HEX_HEIGHT + HexTile.HEX_HEIGHT * 0.5 + tile.surface_offset()

## Is the straight line between two points blocked by cover? (sight / line of fire)
static func line_blocked(world: World3D, from: Vector3, to: Vector3) -> bool:
	if not world:
		return false
	var query = PhysicsRayQueryParameters3D.create(from, to, COVER_LAYER)
	return not world.direct_space_state.intersect_ray(query).is_empty()

## Shared prop loader (paper low-poly look), null if the model is missing
static func load_prop(prop_name: String) -> Node3D:
	var path = PROPS_DIR + prop_name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene = load(path)
	if not scene is PackedScene:
		return null
	var node = scene.instantiate()
	ModelUtils.apply_lowpoly_look(node)
	return node
