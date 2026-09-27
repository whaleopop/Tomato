## Procedural generator for hexagonal map with diverse water features
extends RefCounted
class_name HexGenerator

var noise: FastNoiseLite = null
var biome_noise: FastNoiseLite = null
var lake_noise: FastNoiseLite = null  # Для генерации озер
var river_noise: FastNoiseLite = null  # Для генерации рек
var detail_noise: FastNoiseLite = null  # Для мелких деталей
var noise_seed: int = -1

# Lake generation settings
var lake_centers: Array[Vector2i] = []
var pond_centers: Array[Vector2i] = []
var num_lakes: int = 5  # Количество крупных озер
var num_ponds: int = 15  # Количество маленьких прудов

# Water feature data
var water_tiles: Array[Vector2i] = []
var rivers: Array[Array] = []  # Массив путей рек

func _init():
	noise = FastNoiseLite.new()
	noise.frequency = 0.08
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_octaves = 4

	biome_noise = FastNoiseLite.new()
	biome_noise.frequency = 0.05
	biome_noise.noise_type = FastNoiseLite.TYPE_PERLIN

	lake_noise = FastNoiseLite.new()
	lake_noise.frequency = 0.03
	lake_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	lake_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN

	river_noise = FastNoiseLite.new()
	river_noise.frequency = 0.02
	river_noise.noise_type = FastNoiseLite.TYPE_PERLIN

	detail_noise = FastNoiseLite.new()
	detail_noise.frequency = 0.2
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN

func generate_grid(radius: int, seed_value: int = -1) -> HexGrid:
	# Set seed if provided
	if seed_value >= 0:
		noise_seed = seed_value
		noise.seed = seed_value
		biome_noise.seed = seed_value + 1000
		lake_noise.seed = seed_value + 2000
		river_noise.seed = seed_value + 3000
		detail_noise.seed = seed_value + 4000
	else:
		noise_seed = randi()
		noise.seed = noise_seed
		biome_noise.seed = noise_seed + 1000
		lake_noise.seed = noise_seed + 2000
		river_noise.seed = noise_seed + 3000
		detail_noise.seed = noise_seed + 4000

	# Generate lake centers
	_generate_lake_centers(radius)

	var grid = HexGrid.new(radius)

	# First pass: create all tiles with basic terrain
	for q in range(-radius, radius + 1):
		var r1 = max(-radius, -q - radius)
		var r2 = min(radius, -q + radius)

		for r in range(r1, r2 + 1):
			var coords = Vector2i(q, r)
			var tile = _create_tile(coords, grid)
			grid.add_tile(coords, tile)

	# Second pass: add rivers between lakes
	_generate_rivers(grid)

	# Third pass: refine water edges (beaches, shallow water)
	_refine_water_edges(grid)

	# Fourth pass: add islands in large lakes
	_add_lake_islands(grid)

	return grid

## Асинхронная версия генерации карты (не блокирует UI)
## Разбивает генерацию на чанки по 500 тайлов с yield между ними
func generate_grid_async(radius: int, seed_value: int = -1) -> HexGrid:
	# Set seed if provided
	if seed_value >= 0:
		noise_seed = seed_value
		noise.seed = seed_value
		biome_noise.seed = seed_value + 1000
		lake_noise.seed = seed_value + 2000
		river_noise.seed = seed_value + 3000
		detail_noise.seed = seed_value + 4000
	else:
		noise_seed = randi()
		noise.seed = noise_seed
		biome_noise.seed = noise_seed + 1000
		lake_noise.seed = noise_seed + 2000
		river_noise.seed = noise_seed + 3000
		detail_noise.seed = noise_seed + 4000

	# Generate lake centers
	_generate_lake_centers(radius)

	var grid = HexGrid.new(radius)

	# Собрать все координаты для генерации
	var all_coords = []
	for q in range(-radius, radius + 1):
		var r1 = max(-radius, -q - radius)
		var r2 = min(radius, -q + radius)
		for r in range(r1, r2 + 1):
			all_coords.append(Vector2i(q, r))

	print("[HexGenerator] Generating %d tiles asynchronously..." % all_coords.size())

	# First pass: create all tiles with basic terrain (by chunks)
	var chunk_size = 500
	var generated = 0

	for i in range(0, all_coords.size(), chunk_size):
		var chunk_end = mini(i + chunk_size, all_coords.size())

		for j in range(i, chunk_end):
			var coords = all_coords[j]
			var tile = _create_tile(coords, grid)
			grid.add_tile(coords, tile)

		generated = chunk_end
		var progress = float(generated) / all_coords.size() * 100.0
		print("[HexGenerator] Progress: %.1f%% (%d/%d tiles)" % [progress, generated, all_coords.size()])

		# Отдать контроль движку каждые 500 тайлов
		await Engine.get_main_loop().process_frame

	# Second pass: add rivers between lakes
	print("[HexGenerator] Second pass: Adding rivers...")
	_generate_rivers(grid)
	await Engine.get_main_loop().process_frame

	# Third pass: refine water edges
	print("[HexGenerator] Third pass: Refining water edges...")
	_refine_water_edges(grid)
	await Engine.get_main_loop().process_frame

	# Fourth pass: add islands
	print("[HexGenerator] Fourth pass: Adding lake islands...")
	_add_lake_islands(grid)

	print("[HexGenerator] Map generation complete!")
	return grid

## Generate random lake and pond centers
func _generate_lake_centers(radius: int):
	lake_centers.clear()
	pond_centers.clear()

	var rng = RandomNumberGenerator.new()
	rng.seed = noise_seed

	# Generate large lake centers
	for i in range(num_lakes):
		var angle = rng.randf() * TAU
		var distance = rng.randf_range(radius * 0.3, radius * 0.7)
		var q = int(cos(angle) * distance)
		var r = int(sin(angle) * distance)
		lake_centers.append(Vector2i(q, r))

	# Generate pond centers
	for i in range(num_ponds):
		var q = rng.randi_range(-radius + 10, radius - 10)
		var r = rng.randi_range(-radius + 10, radius - 10)
		# Check if within hex bounds
		if abs(q + r) <= radius:
			pond_centers.append(Vector2i(q, r))

func _create_tile(coords: Vector2i, grid: HexGrid) -> HexTile:
	var tile = HexTile.new()

	# Hex coordinates
	tile.hex_coords = coords

	# World position (center of hex)
	tile.position = _hex_to_world(coords)

	# Height from noise (0..1)
	var height_value = noise.get_noise_2d(coords.x, coords.y)
	var height = (height_value + 1.0) * 0.5
	tile.set_height(height)

	# Check for water features
	var biome = _determine_biome(coords, height)
	tile.set_biome(biome)

	# Health / destroy rules
	match biome:
		HexTile.BiomeType.ROCK:
			tile.max_health = 150.0
			tile.tile_health = 150.0
		HexTile.BiomeType.MOUNTAIN:
			tile.max_health = 200.0
			tile.tile_health = 200.0
			tile.can_spawn = false  # Нельзя спавниться на горах
			# Увеличиваем высоту горы на 1 тайл
			tile.set_height(height + 1.0)
		HexTile.BiomeType.WATER, HexTile.BiomeType.SHALLOW_WATER:
			tile.can_destroy = false
			tile.can_spawn = false  # Нельзя спавниться в воде
		HexTile.BiomeType.SWAMP:
			tile.max_health = 80.0
			tile.tile_health = 80.0
		_:
			tile.max_health = 100.0
			tile.tile_health = 100.0

	return tile

func _determine_biome(coords: Vector2i, height: float) -> HexTile.BiomeType:
	# Check if in lake
	var lake_influence = _get_lake_influence(coords)
	if lake_influence > 0.7:
		water_tiles.append(coords)
		return HexTile.BiomeType.WATER
	elif lake_influence > 0.4:
		return HexTile.BiomeType.SHALLOW_WATER

	# Check if in pond
	var pond_influence = _get_pond_influence(coords)
	if pond_influence > 0.8:
		water_tiles.append(coords)
		return HexTile.BiomeType.WATER

	# Check for swamp (low areas with detail noise)
	if height < 0.25:
		var detail = detail_noise.get_noise_2d(coords.x, coords.y)
		if detail > 0.2:
			return HexTile.BiomeType.SWAMP

	# Water at very low heights
	if height < 0.15:
		water_tiles.append(coords)
		return HexTile.BiomeType.WATER

	# Mountains at very high heights (выше 0.85)
	if height > 0.85:
		return HexTile.BiomeType.MOUNTAIN

	# Rock at high heights
	if height > 0.75:
		return HexTile.BiomeType.ROCK

	# Use biome noise for other biomes
	var biome_noise_value = biome_noise.get_noise_2d(coords.x, coords.y)
	if biome_noise_value < -0.3:
		return HexTile.BiomeType.FOREST
	elif biome_noise_value > 0.3:
		return HexTile.BiomeType.DESERT
	else:
		return HexTile.BiomeType.GRASS

## Calculate influence from lakes (distance-based)
func _get_lake_influence(coords: Vector2i) -> float:
	var max_influence = 0.0

	for lake_center in lake_centers:
		var distance = _hex_distance(coords, lake_center)
		var lake_noise_val = lake_noise.get_noise_2d(coords.x * 0.5, coords.y * 0.5)

		# Varied lake sizes
		var lake_size = 8.0 + lake_noise_val * 3.0
		var influence = 1.0 - (distance / lake_size)

		# Add organic shape variation
		var shape_variation = detail_noise.get_noise_2d(coords.x * 0.3, coords.y * 0.3) * 0.2
		influence += shape_variation

		max_influence = max(max_influence, influence)

	return clamp(max_influence, 0.0, 1.0)

## Calculate influence from ponds
func _get_pond_influence(coords: Vector2i) -> float:
	var max_influence = 0.0

	for pond_center in pond_centers:
		var distance = _hex_distance(coords, pond_center)
		var pond_size = 2.0 + randf() * 1.5
		var influence = 1.0 - (distance / pond_size)
		max_influence = max(max_influence, influence)

	return clamp(max_influence, 0.0, 1.0)

## Hexagonal distance
func _hex_distance(a: Vector2i, b: Vector2i) -> float:
	return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.x + a.y - b.x - b.y)) / 2.0

## Generate rivers connecting lakes
func _generate_rivers(grid: HexGrid):
	if lake_centers.size() < 2:
		return

	var rng = RandomNumberGenerator.new()
	rng.seed = noise_seed + 5000

	# Connect some lakes with rivers
	var num_rivers = mini(3, lake_centers.size() - 1)

	for i in range(num_rivers):
		var start_lake = lake_centers[i]
		var end_lake = lake_centers[(i + 1) % lake_centers.size()]

		var river_path = _create_river_path(start_lake, end_lake, grid)
		rivers.append(river_path)

		# Mark tiles along river as water
		for tile_coords in river_path:
			var tile = grid.get_tile(tile_coords)
			if tile and tile.biome_type != HexTile.BiomeType.WATER:
				tile.set_biome(HexTile.BiomeType.SHALLOW_WATER)

## Create a winding river path between two points
func _create_river_path(start: Vector2i, end: Vector2i, grid: HexGrid) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current = start

	while _hex_distance(current, end) > 1.0:
		path.append(current)

		# Move toward end with some randomness
		var direction = Vector2i(end.x - current.x, end.y - current.y)
		var neighbors = _get_hex_neighbors(current)

		# Find best neighbor (closest to end with some noise)
		var best_neighbor = current
		var best_score = 99999.0

		for neighbor in neighbors:
			var dist = _hex_distance(neighbor, end)
			var noise_val = river_noise.get_noise_2d(neighbor.x, neighbor.y) * 2.0
			var score = dist + noise_val

			if score < best_score:
				best_score = score
				best_neighbor = neighbor

		current = best_neighbor

		# Safety check to avoid infinite loop
		if path.size() > 200:
			break

	path.append(end)
	return path

## Get hex neighbors
func _get_hex_neighbors(coords: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, -1), Vector2i(-1, 1)
	]

	for dir in directions:
		neighbors.append(coords + dir)

	return neighbors

## Refine water edges with beaches and shallow water
func _refine_water_edges(grid: HexGrid):
	for tile_coords in water_tiles:
		var neighbors = _get_hex_neighbors(tile_coords)

		for neighbor_coords in neighbors:
			var neighbor = grid.get_tile(neighbor_coords)
			if neighbor == null:
				continue

			# If neighbor is land, make it beach
			if neighbor.biome_type == HexTile.BiomeType.GRASS or \
			   neighbor.biome_type == HexTile.BiomeType.DESERT:
				neighbor.set_biome(HexTile.BiomeType.BEACH)

## Add islands in large lakes
func _add_lake_islands(grid: HexGrid):
	var rng = RandomNumberGenerator.new()
	rng.seed = noise_seed + 6000

	for lake_center in lake_centers:
		# 50% chance to have an island
		if rng.randf() < 0.5:
			continue

		# Create small island near lake center
		var island_offset = Vector2i(
			rng.randi_range(-3, 3),
			rng.randi_range(-3, 3)
		)
		var island_center = lake_center + island_offset

		# Make island tiles
		var island_tiles = [island_center]
		island_tiles.append_array(_get_hex_neighbors(island_center))

		for island_coord in island_tiles:
			var tile = grid.get_tile(island_coord)
			if tile and tile.biome_type == HexTile.BiomeType.WATER:
				# Small islands are grass or forest
				if rng.randf() < 0.6:
					tile.set_biome(HexTile.BiomeType.GRASS)
				else:
					tile.set_biome(HexTile.BiomeType.FOREST)

func _hex_to_world(coords: Vector2i) -> Vector3:
	var x = sqrt(3.0) * HexTile.HEX_RADIUS * (coords.x + coords.y * 0.5)
	var z = 1.5 * HexTile.HEX_RADIUS * coords.y
	return Vector3(x, 0, z)

func hex_to_world(coords: Vector2i) -> Vector3:
	var x = sqrt(3.0) * HexTile.HEX_RADIUS * (coords.x + coords.y * 0.5)
	var z = 1.5 * HexTile.HEX_RADIUS * coords.y
	return Vector3(x, 0, z)
