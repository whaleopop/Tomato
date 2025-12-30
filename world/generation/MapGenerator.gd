## Main map generator that creates the entire world
extends Node3D
class_name MapGenerator

signal map_generated(grid: HexGrid)

var hex_generator: HexGenerator = null
var grid: HexGrid = null
var map_radius: int = 20
var map_seed: int = 0  # Seed for map generation

func _ready():
	hex_generator = HexGenerator.new()

func generate_map(radius: int = 20, seed_value: int = -1):
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

	# Generate new grid with seed
	grid = hex_generator.generate_grid(radius, map_seed)
	add_child(grid)

	map_generated.emit(grid)

	return grid

func get_map_seed() -> int:
	return map_seed

func get_grid() -> HexGrid:
	return grid

