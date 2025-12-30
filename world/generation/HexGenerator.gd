## Procedural generator for hexagonal map
extends RefCounted
class_name HexGenerator

var noise: FastNoiseLite = null
var biome_noise: FastNoiseLite = null
var noise_seed: int = -1

func _init():
	noise = FastNoiseLite.new()
	noise.frequency = 0.1
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	biome_noise = FastNoiseLite.new()
	biome_noise.frequency = 0.05
	biome_noise.noise_type = FastNoiseLite.TYPE_PERLIN

func generate_grid(radius: int, seed_value: int = -1) -> HexGrid:
	# Set seed if provided
	if seed_value >= 0:
		noise_seed = seed_value
		noise.seed = seed_value
		biome_noise.seed = seed_value + 1000
	else:
		noise_seed = randi()
		noise.seed = noise_seed
		biome_noise.seed = noise_seed + 1000
	
	var grid = HexGrid.new(radius)
	
	for q in range(-radius, radius + 1):
		var r1 = max(-radius, -q - radius)
		var r2 = min(radius, -q + radius)
		
		for r in range(r1, r2 + 1):
			var coords = Vector2i(q, r)
			var tile = _create_tile(coords)
			grid.add_tile(coords, tile)
	
	return grid

func _create_tile(coords: Vector2i) -> HexTile:
	var tile = HexTile.new()

	# CRITICAL: Set hex coordinates (used by DestructionSystem)
	tile.hex_coords = coords

	# Calculate world position
	var world_pos = _hex_to_world(coords)
	# Use position instead of global_position (tile not in tree yet)
	tile.position = world_pos
	
	# Generate height using noise
	var height_value = noise.get_noise_2d(coords.x, coords.y)
	var height = (height_value + 1.0) * 0.5  # Normalize to 0-1
	tile.set_height(height)
	
	# Determine biome
	var biome_value = biome_noise.get_noise_2d(coords.x, coords.y)
	var biome = _get_biome_from_noise(biome_value, height)
	tile.set_biome(biome)
	
	# Set tile health based on biome
	match biome:
		HexTile.BiomeType.ROCK:
			tile.max_health = 150.0
			tile.tile_health = 150.0
		HexTile.BiomeType.WATER:
			tile.can_destroy = false
		_:
			tile.max_health = 100.0
			tile.tile_health = 100.0
	
	return tile

func _hex_to_world(coords: Vector2i) -> Vector3:
	var x = coords.x * sqrt(3.0) * HexTile.HEX_SIZE
	var z = (coords.y + coords.x * 0.5) * 1.5 * HexTile.HEX_SIZE
	return Vector3(x, 0, z)

func _get_biome_from_noise(biome_noise_value: float, height: float) -> HexTile.BiomeType:
	# Water at low heights
	if height < 0.2:
		return HexTile.BiomeType.WATER
	
	# Rock at high heights
	if height > 0.8:
		return HexTile.BiomeType.ROCK
	
	# Use biome noise for other biomes
	if biome_noise_value < -0.3:
		return HexTile.BiomeType.FOREST
	elif biome_noise_value > 0.3:
		return HexTile.BiomeType.DESERT
	else:
		return HexTile.BiomeType.GRASS
