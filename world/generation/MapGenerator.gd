## Main map generator that creates the entire world
extends Node3D
class_name MapGenerator

signal map_generated(grid: HexGrid)

## Radius used for real matches. Server, clients and the spawn cutscene must all use the
## same value: lake placement depends on the radius, so different radii give different maps.
const MATCH_MAP_RADIUS: int = 15  # 721 tiles of radius 2 (the outer ring is the mountain wall)

var hex_generator: HexGenerator = null
var grid: HexGrid = null
var map_radius: int = MATCH_MAP_RADIUS
var map_seed: int = 243834  # Seed for map generation

# Structure generation settings
@export var structure_density: float = 0.015  # ~1.5% of tiles will have structures
@export var enable_structures: bool = false

func _ready():
	hex_generator = HexGenerator.new()

func generate_map(radius: int, seed_value: int = -1):
	map_radius = radius

	# Use provided seed or generate random one
	if seed_value < 0:
		map_seed = randi()
	else:
		map_seed = seed_value

	print("[MapGenerator] Generating map with seed: %d, radius: %d" % [map_seed, radius])

	# Clear existing grid safely (avoid race condition)
	var old_grid = grid
	grid = null

	if old_grid and is_instance_valid(old_grid):
		old_grid.queue_free()
		# Wait for the old grid to be freed before creating new one
		if is_inside_tree():
			await get_tree().process_frame

	# Generate new grid with seed (async version for smooth loading)
	grid = await hex_generator.generate_grid_async(radius, map_seed)
	add_child(grid)
	grid.update_tile_edges()  # seamless ground and water (HexTile.update_edges)
	if not get_node_or_null("WaterRipples"):
		var ripples = WaterRipples.new()
		ripples.name = "WaterRipples"
		add_child(ripples)
	get_node("WaterRipples").grid = grid

	# Place procedural structures
	if enable_structures:
		await _place_structures_async()

	# Paths connecting biome clusters and small huts
	_carve_paths(map_seed)
	grid.update_tile_edges()  # refresh seams after path biome changes
	for tile in grid.tiles.values():
		if tile.has_meta("path"):
			BiomeDecor.decorate(tile)  # now that the whole path is known (fences on its sides)
	_place_huts(map_seed)
	Waterfalls.build(grid, map_seed)  # where water meets a terrace

	map_generated.emit(grid)

	return grid

func get_map_seed() -> int:
	return map_seed

func get_grid() -> HexGrid:
	return grid

## Place procedural structures across the map (async for smooth loading)
func _place_structures_async():
	if not grid or not is_instance_valid(grid):
		return

	var rng = RandomNumberGenerator.new()
	rng.seed = map_seed + 777  # Offset seed for structures

	var all_tiles = grid.get_all_tiles()
	var structure_count = int(all_tiles.size() * structure_density)

	print("[MapGenerator] Placing %d structures..." % structure_count)

	# Shuffle tile order for random placement
	all_tiles.shuffle()

	var placed = 0
	var chunk_size = 20  # Place 20 structures per frame

	for i in range(all_tiles.size()):
		if placed >= structure_count:
			break

		var tile = all_tiles[i]

		# Skip invalid tiles (water, shallow water, swamp)
		if tile.biome_type == HexTile.BiomeType.WATER or tile.biome_type == HexTile.BiomeType.SHALLOW_WATER:
			continue

		# Determine structure type based on biome
		var structure_type = _get_structure_type_for_biome(tile.biome_type, rng)

		if structure_type == -1:  # Skip this tile
			continue

		# Generate structure
		var structure = ProceduralStructure.new()
		var parts = BuildingGenerator.generate(structure_type, map_seed + tile.hex_coords.x * 1000 + tile.hex_coords.y)

		if parts.is_empty():
			continue

		structure.build_from_parts(parts)

		# Position structure on tile (with slight random offset)
		var tile_world_pos = grid.hex_to_world(tile.hex_coords)
		var random_offset = Vector3(
			rng.randf_range(-0.5, 0.5),
			0,
			rng.randf_range(-0.5, 0.5)
		)
		structure.position = tile_world_pos + random_offset

		# Random rotation
		structure.rotation.y = rng.randf() * TAU

		grid.add_child(structure)
		placed += 1

		# Yield every chunk_size structures for smooth loading
		if placed % chunk_size == 0:
			await Engine.get_main_loop().process_frame

	print("[MapGenerator] Placed %d structures successfully" % placed)

## Determine structure type based on biome (returns BuildingGenerator.StructureType or -1 to skip)
func _get_structure_type_for_biome(biome: HexTile.BiomeType, rng: RandomNumberGenerator) -> int:
	match biome:
		HexTile.BiomeType.GRASS:
			# Mix of trees and warehouses
			var rand = rng.randf()
			if rand < 0.7:
				return BuildingGenerator.StructureType.TREE_OAK
			elif rand < 0.85:
				return BuildingGenerator.StructureType.WAREHOUSE
			else:
				return -1

		HexTile.BiomeType.FOREST:
			# Only trees
			var rand = rng.randf()
			if rand < 0.85:
				return BuildingGenerator.StructureType.TREE_OAK if rng.randf() > 0.3 else BuildingGenerator.StructureType.TREE_PINE
			else:
				return -1  # Skip

		HexTile.BiomeType.ROCK:
			# Towers, fortifications
			var rand = rng.randf()
			if rand < 0.3:
				return BuildingGenerator.StructureType.TOWER
			elif rand < 0.5:
				return BuildingGenerator.StructureType.FORTIFICATION
			elif rand < 0.65:
				return BuildingGenerator.StructureType.TREE_PINE
			else:
				return -1

		HexTile.BiomeType.MOUNTAIN:
			# Sparse structures (mostly towers)
			var rand = rng.randf()
			if rand < 0.15:
				return BuildingGenerator.StructureType.TOWER
			elif rand < 0.25:
				return BuildingGenerator.StructureType.FORTIFICATION
			else:
				return -1

		HexTile.BiomeType.DESERT:
			# Warehouses and towers
			var rand = rng.randf()
			if rand < 0.3:
				return BuildingGenerator.StructureType.WAREHOUSE
			elif rand < 0.5:
				return BuildingGenerator.StructureType.TOWER
			else:
				return -1

		HexTile.BiomeType.SWAMP:
			# Sparse trees only
			var rand = rng.randf()
			if rand < 0.5:
				return BuildingGenerator.StructureType.TREE_OAK
			else:
				return -1

		HexTile.BiomeType.BEACH:
			# Warehouses near water
			var rand = rng.randf()
			if rand < 0.3:
				return BuildingGenerator.StructureType.WAREHOUSE
			else:
				return -1

		_:
			return -1  # Skip water and unknown biomes

# ---------------------------------------------------------------- paths

## Carve 4-6 winding dirt paths across the map connecting distant tiles.
## A path is a drunk-walk of BEACH-biome tiles between two seed points.
func _carve_paths(seed_val: int) -> void:
	if not grid:
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val + 31337
	var all_land: Array = []
	for c in grid.tiles:
		var t = grid.get_tile(c)
		if t and t.is_playable() and not t.is_water() and t.biome_type != HexTile.BiomeType.MOUNTAIN:
			all_land.append(c)
	if all_land.size() < 10:
		return
	var path_count = rng.randi_range(4, 6)
	for _p in range(path_count):
		var a = all_land[rng.randi() % all_land.size()]
		var b = all_land[rng.randi() % all_land.size()]
		_drunk_path(a, b, rng)

func _drunk_path(start: Vector2i, end: Vector2i, rng: RandomNumberGenerator) -> void:
	var dirs = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
				Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
	var cur = start
	var max_steps = 60
	for _s in range(max_steps):
		var tile = grid.get_tile(cur)
		if tile and tile.biome_type not in [HexTile.BiomeType.WATER, HexTile.BiomeType.SHALLOW_WATER,
				HexTile.BiomeType.MOUNTAIN]:
			tile.set_meta("path", true)  # BiomeDecor: fences and vegetable beds along it
			tile.set_biome(HexTile.BiomeType.BEACH)
		if cur == end:
			break
		# Bias towards the end, with some random wandering
		var toward = (Vector2(end) - Vector2(cur)).normalized()
		var best_dir = dirs[0]
		var best_dot = -INF
		for d in dirs:
			var dot = Vector2(d).normalized().dot(toward) + rng.randf_range(-0.5, 0.5)
			if dot > best_dot:
				best_dot = dot
				best_dir = d
		cur = cur + best_dir
		if not grid.tiles.has(cur):
			break

# ---------------------------------------------------------------- huts

## Place 6-10 small huts (low CoverWall boxes) on playable land tiles.
## Each hut is a 3-4 wall enclosure the player can enter but not jump over.
func _place_huts(seed_val: int) -> void:
	if not grid:
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val + 54321
	var candidates: Array = []
	for c in grid.tiles:
		var t = grid.get_tile(c)
		if t and t.is_playable() and not t.is_water() and not t.is_ramp() and t.biome_type not in [
				HexTile.BiomeType.MOUNTAIN, HexTile.BiomeType.WATER, HexTile.BiomeType.SHALLOW_WATER]:
			candidates.append(c)
	if candidates.is_empty():
		return
	var hut_count = rng.randi_range(6, 10)
	var placed_centers: Array = []
	var tries = 0
	while placed_centers.size() < hut_count and tries < 200:
		tries += 1
		var c = candidates[rng.randi() % candidates.size()]
		# Keep huts apart
		var too_close = false
		for pc in placed_centers:
			if DestructionSystem._dist(c, pc) < 3:
				too_close = true
				break
		if too_close:
			continue
		placed_centers.append(c)
		_build_hut(c, rng)
	grid.set_meta("huts", placed_centers)  # Landmark.plan keeps clear of them

func _build_hut(center: Vector2i, rng: RandomNumberGenerator) -> void:
	var tile = grid.get_tile(center)
	if not tile:
		return
	var base_pos = tile.global_position
	# Simple 4-wall box hut, about 2.5m wide, 1.2m tall (player height) — low enough to shoot over
	var wall_h = 1.2
	var hw = 1.3  # half-width
	var walls = [
		# [from, to, rotation_y]
		[Vector3(-hw, 0, -hw), Vector3(hw, 0, -hw), 0.0],
		[Vector3(-hw, 0,  hw), Vector3(hw, 0,  hw), 0.0],
		[Vector3(-hw, 0, -hw), Vector3(-hw, 0, hw), PI * 0.5],
		# Leave one side open as a doorway (only 3 walls)
	]
	for w in walls:
		var wall = StaticBody3D.new()
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		var length = w[0].distance_to(w[1])
		box.size = Vector3(length, wall_h, 0.22)
		mesh_inst.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.48, 0.38, 0.28) if rng.randi() % 2 == 0 else Color(0.58, 0.52, 0.46)
		mat.roughness = 0.9
		mesh_inst.material_override = mat
		var mid = (w[0] + w[1]) * 0.5 + Vector3(0, wall_h * 0.5, 0)
		wall.position = base_pos + mid
		wall.rotation.y = w[2]
		var col = CollisionShape3D.new()
		var cs = BoxShape3D.new()
		cs.size = box.size
		col.shape = cs
		wall.add_child(mesh_inst)
		wall.add_child(col)
		wall.collision_layer = HitscanSystem.LAYER_ENVIRONMENT | CoverSpawner.COVER_LAYER
		grid.add_child(wall)
