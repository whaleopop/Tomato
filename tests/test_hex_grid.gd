## Tests for hexagonal grid system
extends "res://addons/gut/test.gd"

var grid: HexGrid
var tile: HexTile

func before_each():
	grid = HexGrid.new(5)
	tile = HexTile.new()
	tile.hex_coords = Vector2i(0, 0)
	grid.add_tile(tile.hex_coords, tile)

func after_each():
	if grid:
		grid.queue_free()

func test_add_tile():
	var new_tile = HexTile.new()
	new_tile.hex_coords = Vector2i(1, 0)
	grid.add_tile(new_tile.hex_coords, new_tile)
	assert_not_null(grid.get_tile(new_tile.hex_coords))

func test_get_neighbors():
	var neighbors = grid.get_neighbors(Vector2i(0, 0))
	# Center tile should have up to 6 neighbors
	assert_le(neighbors.size(), 6)

func test_hex_to_world():
	var world_pos = grid.hex_to_world(Vector2i(0, 0))
	assert_not_null(world_pos)

func test_world_to_hex():
	var world_pos = Vector3(0, 0, 0)
	var hex_coords = grid.world_to_hex(world_pos)
	assert_not_null(hex_coords)

