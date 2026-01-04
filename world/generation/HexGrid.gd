## Manages hexagonal grid of tiles
extends Node3D
class_name HexGrid

var tiles: Dictionary = {}  # Vector2i -> HexTile
var grid_radius: int = 20

func _init(p_radius: int = 20):
	grid_radius = p_radius

func add_tile(coords: Vector2i, tile: HexTile):
	tiles[coords] = tile
	add_child(tile)

func get_tile(coords: Vector2i) -> HexTile:
	var tile = tiles.get(coords, null)
	if tile and not is_instance_valid(tile):
		tiles.erase(coords)
		return null
	return tile

func get_neighbors(coords: Vector2i) -> Array:
	var neighbors: Array = []
	var directions = [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
	]
	
	for dir in directions:
		var neighbor_coords = coords + dir
		var neighbor = get_tile(neighbor_coords)
		if neighbor:
			neighbors.append(neighbor)
	
	return neighbors

func hex_to_world(coords: Vector2i) -> Vector3:
	var x = coords.x * sqrt(3.0) * HexTile.HEX_SIZE
	var z = (coords.y + coords.x * 0.5) * 1.5 * HexTile.HEX_SIZE
	return Vector3(x, 0, z)

func world_to_hex(world_pos: Vector3) -> Vector2i:
	var q = (sqrt(3.0) / 3.0 * world_pos.x - 1.0 / 3.0 * world_pos.z) / HexTile.HEX_SIZE
	var r = (2.0 / 3.0 * world_pos.z) / HexTile.HEX_SIZE
	return _hex_round(Vector2(q, r))

func _hex_round(hex: Vector2) -> Vector2i:
	var q = round(hex.x)
	var r = round(hex.y)
	var s = round(-hex.x - hex.y)
	
	var q_diff = abs(q - hex.x)
	var r_diff = abs(r - hex.y)
	var s_diff = abs(s - (-hex.x - hex.y))
	
	if q_diff > r_diff and q_diff > s_diff:
		q = -r - s
	elif r_diff > s_diff:
		r = -q - s
	else:
		s = -q - r
	
	return Vector2i(int(q), int(r))

func get_all_tiles() -> Array:
	var result: Array = []
	for tile in tiles.values():
		# Filter out invalid/freed tiles
		if is_instance_valid(tile):
			result.append(tile)
	return result

func remove_tile(coords: Vector2i):
	if tiles.has(coords):
		var tile = tiles[coords]
		tiles.erase(coords)
		if is_instance_valid(tile):
			tile.queue_free()
