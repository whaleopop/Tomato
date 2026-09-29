## Procedural generator for hexagonal map with diverse water features
extends RefCounted
class_name HexGenerator

var noise: FastNoiseLite = null
var biome_noise: FastNoiseLite = null
var lake_noise: FastNoiseLite = null  # Для генерации озер
var river_noise: FastNoiseLite = null  # Для генерации рек
var detail_noise: FastNoiseLite = null  # Для мелких деталей
var terrace_noise: FastNoiseLite = null  # plateaus (_build_terraces)
var special_noise: FastNoiseLite = null  # which special biome a patch is (_add_special_biomes)
var special_mask: FastNoiseLite = null   # where the patches are
var noise_seed: int = -1

# Lake generation settings
var lake_centers: Array[Vector2i] = []
var pond_centers: Array[Vector2i] = []
var num_lakes: int = 5  # Количество крупных озер
var num_ponds: int = 8  # Количество маленьких прудов

# Water feature data
var water_tiles: Array[Vector2i] = []
var rivers: Array[Array] = []  # Массив путей рек

func _init():
	noise = FastNoiseLite.new()
	noise.frequency = 0.16  # sampled per tile: tiles are 2 units wide, features keep their world size
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_octaves = 4

	biome_noise = FastNoiseLite.new()
	biome_noise.frequency = 0.1
	biome_noise.noise_type = FastNoiseLite.TYPE_PERLIN

	lake_noise = FastNoiseLite.new()
	lake_noise.frequency = 0.06
	lake_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	lake_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN

	river_noise = FastNoiseLite.new()
	river_noise.frequency = 0.04
	river_noise.noise_type = FastNoiseLite.TYPE_PERLIN

	detail_noise = FastNoiseLite.new()
	detail_noise.frequency = 0.4
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN

	terrace_noise = FastNoiseLite.new()
	terrace_noise.frequency = 0.075  # per tile: plateaus a few tiles across
	terrace_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	terrace_noise.fractal_octaves = 2

	special_noise = FastNoiseLite.new()
	special_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	special_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	special_noise.frequency = 0.16
	special_mask = FastNoiseLite.new()
	special_mask.noise_type = FastNoiseLite.TYPE_PERLIN
	special_mask.frequency = 0.11

func generate_grid(radius: int, seed_value: int = -1) -> HexGrid:
	# Set seed if provided
	if seed_value >= 0:
		noise_seed = seed_value
		noise.seed = seed_value
		biome_noise.seed = seed_value + 1000
		lake_noise.seed = seed_value + 2000
		river_noise.seed = seed_value + 3000
		detail_noise.seed = seed_value + 4000
		terrace_noise.seed = seed_value + 7000
		special_noise.seed = seed_value + 8000
		special_mask.seed = seed_value + 8100
	else:
		noise_seed = randi()
		noise.seed = noise_seed
		biome_noise.seed = noise_seed + 1000
		lake_noise.seed = noise_seed + 2000
		river_noise.seed = noise_seed + 3000
		detail_noise.seed = noise_seed + 4000
		terrace_noise.seed = noise_seed + 7000
		special_noise.seed = noise_seed + 8000
		special_mask.seed = noise_seed + 8100

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
	_add_special_biomes(grid)
	_raise_rim(grid, radius)
	_build_terraces(grid, radius)

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
		terrace_noise.seed = seed_value + 7000
		special_noise.seed = seed_value + 8000
		special_mask.seed = seed_value + 8100
	else:
		noise_seed = randi()
		noise.seed = noise_seed
		biome_noise.seed = noise_seed + 1000
		lake_noise.seed = noise_seed + 2000
		river_noise.seed = noise_seed + 3000
		detail_noise.seed = noise_seed + 4000
		terrace_noise.seed = noise_seed + 7000
		special_noise.seed = noise_seed + 8000
		special_mask.seed = noise_seed + 8100

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
	_add_special_biomes(grid)
	_raise_rim(grid, radius)
	_build_terraces(grid, radius)

	print("[HexGenerator] Map generation complete!")
	return grid

## The outer ring is a mountain wall from the start: nobody falls off the island, and the zone
## closes in from there (DestructionSystem raises more mountains)
func _raise_rim(grid: HexGrid, radius: int):
	for coords in grid.tiles:
		if max(abs(coords.x), abs(coords.y), abs(coords.x + coords.y)) >= radius:
			var tile: HexTile = grid.tiles[coords]
			tile.set_biome(HexTile.BiomeType.MOUNTAIN)
			tile.can_spawn = false
			tile.can_destroy = false

# ---------------------------------------------------------------- special biomes

const SPECIAL_MASK: float = 0.12  # mask noise above this: a special patch (about a quarter of the land)
const SPECIAL_BAG = [HexTile.BiomeType.MEADOW, HexTile.BiomeType.MEADOW, HexTile.BiomeType.TALL_GRASS,
	HexTile.BiomeType.TALL_GRASS, HexTile.BiomeType.TALL_GRASS, HexTile.BiomeType.MUSHROOM, HexTile.BiomeType.MUSHROOM,
	HexTile.BiomeType.FROST, HexTile.BiomeType.FROST, HexTile.BiomeType.THORNS]
const SPECIAL_ON = [HexTile.BiomeType.GRASS, HexTile.BiomeType.FOREST, HexTile.BiomeType.DESERT, HexTile.BiomeType.ROCK]

## Patches of meadow, frost, tall grass, mushrooms and brambles (BiomeRules) on ordinary land:
## a slow mask decides where, a cellular noise which one, so every patch is one biome
func _add_special_biomes(grid: HexGrid) -> void:
	var coords_list: Array = grid.tiles.keys()
	coords_list.sort()
	for c in coords_list:
		var tile: HexTile = grid.tiles[c]
		if not tile.biome_type in SPECIAL_ON or special_mask.get_noise_2d(c.x, c.y) < SPECIAL_MASK:
			continue
		# One value per cell, hashed into a weighted bag (the raw values bunch up)
		var cell = int(abs(special_noise.get_noise_2d(c.x, c.y)) * 100003.0)
		tile.set_biome(SPECIAL_BAG[cell % SPECIAL_BAG.size()])

# ---------------------------------------------------------------- terraces

const TERRACE_THRESHOLDS = [-0.12, 0.16]  # terrace noise above these: level 1, level 2
const WATER_TOP: float = -0.05          # world y of deep water's surface
const SHALLOW_TOP: float = 0.03          # shallow water / rivers a touch higher
const RAMP_EVERY: int = 9                # one more ramp per this many tiles along a plateau's edge

## The island on up to three levels (HexTile.TERRACE_STEP apart): plateaus from a slow noise,
## water / beach / swamp at the bottom, neighbours at most one level apart (a jump clears it), no
## lone pillars or pits, ramps up onto every plateau. Seeded and in a fixed order: the same on
## the server and every client.
func _build_terraces(grid: HexGrid, radius: int) -> void:
	var coords_list: Array = grid.tiles.keys()
	coords_list.sort()
	var levels: Dictionary = {}
	for c in coords_list:
		var tile: HexTile = grid.tiles[c]
		var v = terrace_noise.get_noise_2d(c.x, c.y)
		var lv = 0
		for threshold in TERRACE_THRESHOLDS:
			if v > threshold:
				lv += 1
		if tile.biome_type in [HexTile.BiomeType.WATER, HexTile.BiomeType.SHALLOW_WATER, HexTile.BiomeType.SWAMP, HexTile.BiomeType.BEACH]:
			lv = 0
		levels[c] = lv
	var rim = func(c: Vector2i) -> bool: return max(abs(c.x), abs(c.y), abs(c.x + c.y)) >= radius

	# Lone pillars come down, lone pits fill up (the rim doesn't count)
	for c in coords_list:
		if rim.call(c):
			continue
		var lo = 99
		var hi = -1
		for n in _get_hex_neighbors(c):
			if levels.has(n) and not rim.call(n):
				lo = mini(lo, levels[n])
				hi = maxi(hi, levels[n])
		if hi >= 0 and levels[c] > hi:
			levels[c] = hi
		elif lo < 99 and levels[c] < lo and grid.tiles[c].biome_type != HexTile.BiomeType.WATER:
			levels[c] = lo
	# At most one level between neighbours: only ever lowered, so the water stays at the bottom
	var changed = true
	while changed:
		changed = false
		for c in coords_list:
			for n in _get_hex_neighbors(c):
				if levels.has(n) and levels[c] > levels[n] + 1:
					levels[c] = levels[n] + 1
					changed = true
	# The rim mountains stand at the height of the land inside, so nobody jumps over them
	for c in coords_list:
		if rim.call(c):
			var top = 0
			for n in _get_hex_neighbors(c):
				if levels.has(n) and not rim.call(n):
					top = maxi(top, levels[n])
			levels[c] = top

	for c in coords_list:
		var tile: HexTile = grid.tiles[c]
		tile.level = levels[c]
		if tile.level > 0:
			tile.set_height(tile.height + tile.level * HexTile.TERRACE_STEP / HexTile.HEX_HEIGHT)
	_place_ramps(grid, coords_list, levels, rim)
	# Water lies below its banks (the land shows an earth bank above it); MovementComponent steps
	# back out onto the shore
	for c in coords_list:
		var tile: HexTile = grid.tiles[c]
		if tile.biome_type == HexTile.BiomeType.WATER:
			tile.set_height((WATER_TOP - HexTile.HEX_HEIGHT * 0.5) / HexTile.HEX_HEIGHT)
		elif tile.biome_type == HexTile.BiomeType.SHALLOW_WATER:
			tile.set_height((SHALLOW_TOP - HexTile.HEX_HEIGHT * 0.5) / HexTile.HEX_HEIGHT)

## A ramp is a lower tile that slopes up across one edge onto a plateau. Its far side must be
## walkable ground on its own level, so you walk straight on and up.
func _place_ramps(grid: HexGrid, coords_list: Array, levels: Dictionary, rim: Callable) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = noise_seed + 7100
	var region_of: Dictionary = {}
	var regions: Array = []  # [level, [coords]]
	for c in coords_list:
		if levels[c] == 0 or region_of.has(c) or rim.call(c):
			continue
		var members: Array = []
		var stack: Array = [c]
		region_of[c] = regions.size()
		while not stack.is_empty():
			var cur = stack.pop_back()
			members.append(cur)
			for n in _get_hex_neighbors(cur):
				if levels.has(n) and not region_of.has(n) and not rim.call(n) and levels[n] == levels[c]:
					region_of[n] = regions.size()
					stack.append(n)
		regions.append([levels[c], members])

	var used: Dictionary = {}  # tiles that are ramps or a ramp's landing
	for region in regions:
		var lv: int = region[0]
		var candidates: Array = []  # [lower tile, edge towards the plateau]
		for c in region[1]:
			if grid.tiles[c].is_mountain():
				continue  # a ramp into a rock wall leads nowhere
			for k in 6:
				var low_c: Vector2i = c - HexTile.EDGE_DIRECTIONS[k]  # the plateau lies across edge k of low_c
				var far_c: Vector2i = low_c - HexTile.EDGE_DIRECTIONS[k]
				if not levels.has(low_c) or not levels.has(far_c) or rim.call(low_c) or rim.call(far_c):
					continue
				if levels[low_c] != lv - 1 or levels[far_c] != lv - 1:
					continue
				var low: HexTile = grid.tiles[low_c]
				var far: HexTile = grid.tiles[far_c]
				if not _ramp_ground(low) or not _ramp_ground(far):
					continue
				candidates.append([low_c, k])
		if candidates.is_empty():
			continue  # still reachable with a jump
		var wanted = 1 + candidates.size() / RAMP_EVERY
		var placed: Array = []
		var tries = 0
		while placed.size() < wanted and tries < candidates.size() * 2:
			tries += 1
			var pick = candidates[rng.randi() % candidates.size()]
			var low_c: Vector2i = pick[0]
			if used.has(low_c):
				continue
			var too_close = false
			for other in placed:
				if _hex_distance(other, low_c) < 3.0:
					too_close = true
			if too_close:
				continue
			var ramp: HexTile = grid.tiles[low_c]
			ramp.ramp_dir = pick[1]
			ramp.can_spawn = false
			used[low_c] = true
			used[low_c - HexTile.EDGE_DIRECTIONS[pick[1]]] = true
			placed.append(low_c)

## Dry, flat ground a ramp can stand on / lead down to
func _ramp_ground(tile: HexTile) -> bool:
	return not tile.is_ramp() and not (tile.biome_type in [HexTile.BiomeType.WATER, HexTile.BiomeType.SHALLOW_WATER, HexTile.BiomeType.MOUNTAIN])

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
		var span = max(1, radius / 2)
		var q = rng.randi_range(-span, span)
		var r = rng.randi_range(-span, span)
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
		var lake_size = 4.0 + lake_noise_val * 1.5  # in tiles
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
		var pond_size = 2.5  # was randf(): not the same on every peer (only the center tile ever counted)
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
			rng.randi_range(-1, 1),
			rng.randi_range(-1, 1)
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
