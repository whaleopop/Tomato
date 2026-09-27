## Main map generator that creates the entire world
extends Node3D
class_name MapGenerator

signal map_generated(grid: HexGrid)

## Radius used for real matches. Server, clients and the spawn cutscene must all use the
## same value: lake placement depends on the radius, so different radii give different maps.
const MATCH_MAP_RADIUS: int = 20  # 1261 tiles

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
