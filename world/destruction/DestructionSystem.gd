## Manages map destruction over time (replaces shrinking zone)
extends Node
class_name DestructionSystem

signal destruction_phase_started(phase: int)
signal tile_destroyed(coords: Vector2i)

var grid: HexGrid = null
var tile_destroyer: TileDestroyer = null
var destruction_timer: float = 0.0
var destruction_interval: float = 30.0  # Destroy tiles every 30 seconds
var destruction_radius: int = 1
var current_phase: int = 0
var max_phases: int = 10
var is_active: bool = false

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
	current_phase += 1
	
	if current_phase > max_phases:
		stop()
		return
	
	destruction_phase_started.emit(current_phase)
	
	# Destroy tiles from the edges
	_destroy_edge_tiles()

func _destroy_edge_tiles():
	if grid == null:
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
	
	# Destroy random edge tiles
	var tiles_to_destroy = min(destruction_radius * 10, edge_tiles.size())
	edge_tiles.shuffle()

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

func set_destruction_interval(interval: float):
	destruction_interval = interval

func set_destruction_radius(radius: int):
	destruction_radius = radius
