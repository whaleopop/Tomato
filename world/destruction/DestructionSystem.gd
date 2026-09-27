## Manages map destruction over time (replaces shrinking zone)
extends Node
class_name DestructionSystem

signal destruction_phase_started(phase: int)
signal tile_destroyed(coords: Vector2i)

var grid: HexGrid = null
var tile_destroyer: TileDestroyer = null
var destruction_timer: float = 0.0
var destruction_interval: float = 30.0  # First phase after 30 s, then faster and faster
var destruction_radius: int = 1
var current_phase: int = 0
var is_active: bool = false
# Every phase eats more of the edges, sooner, until only a small core is left: the island
# keeps closing in, so a match always ends (no more "10 phases and it stops")
const MIN_INTERVAL: float = 12.0
const INTERVAL_STEP: float = 1.5
const TILES_PER_PHASE: int = 10
const TILES_GROWTH: int = 4
const CORE_TILES: int = 19          # radius-2 core that is never destroyed

func _ready():
	tile_destroyer = TileDestroyer.new()
	tile_destroyer.tile_destroyed.connect(_on_tile_destroyed)

func _process(delta: float):
	if not is_active or grid == null:
		return
	
	destruction_timer += delta
	
	if destruction_timer >= destruction_interval:
		destruction_timer = 0.0
		_execute_destruction_phase()

func start(grid: HexGrid):
	self.grid = grid
	is_active = true
	current_phase = 0

func stop():
	is_active = false

func _execute_destruction_phase():
	var alive = 0
	for tile in grid.get_all_tiles():
		if not tile.is_destroyed:
			alive += 1
	if alive <= CORE_TILES:
		stop()
		return

	current_phase += 1
	destruction_phase_started.emit(current_phase)
	destruction_interval = max(MIN_INTERVAL, destruction_interval - INTERVAL_STEP)

	# Destroy tiles from the edges (never into the core)
	_destroy_edge_tiles(min(TILES_PER_PHASE + TILES_GROWTH * current_phase, alive - CORE_TILES))

func _destroy_edge_tiles(count: int):
	if grid == null or count <= 0:
		return
	
	var all_tiles = grid.get_all_tiles()
	var edge_tiles: Array[HexTile] = []
	
	# Find edge tiles (tiles with fewer than 6 neighbors)
	for tile in all_tiles:
		# Skip invalid or freed tiles
		if not is_instance_valid(tile):
			continue

		if tile.is_destroyed:
			continue

		var coords = tile.hex_coords
		var neighbors = grid.get_neighbors(coords)
		var active_neighbors = 0

		for neighbor in neighbors:
			# Skip invalid or freed neighbors
			if not is_instance_valid(neighbor):
				continue

			if not neighbor.is_destroyed:
				active_neighbors += 1

		# Edge tile if has less than 6 neighbors
		if active_neighbors < 6:
			edge_tiles.append(tile)
	
	# Destroy random edge tiles, the outermost first
	var tiles_to_destroy = min(count * destruction_radius, edge_tiles.size())
	edge_tiles.shuffle()
	edge_tiles.sort_custom(func(a, b): return _ring(a.hex_coords) > _ring(b.hex_coords))

	for i in range(tiles_to_destroy):
		if i >= edge_tiles.size():
			break

		var tile = edge_tiles[i]
		# Skip invalid or freed tiles
		if not is_instance_valid(tile):
			continue

		if not tile.is_destroyed:
			tile_destroyer.destroy_tile(tile)

func _on_tile_destroyed(coords: Vector2i):
	tile_destroyed.emit(coords)

## Hex distance from the map center
func _ring(c: Vector2i) -> int:
	return max(abs(c.x), abs(c.y), abs(c.x + c.y))

func set_destruction_interval(interval: float):
	destruction_interval = interval

func set_destruction_radius(radius: int):
	destruction_radius = radius
