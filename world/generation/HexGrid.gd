## Manages hexagonal grid of tiles
extends Node3D
class_name HexGrid

var tiles: Dictionary = {}  # Vector2i -> HexTile
var grid_radius: int = 20
var terrain_version: int = 0  # bumped when tiles change their ground (flood): the minimap redraws

func _init(p_radius: int = 20):
	grid_radius = p_radius

func add_tile(coords: Vector2i, tile: HexTile):
	tiles[coords] = tile
	add_child(tile)

func get_tile(coords: Vector2i) -> HexTile:
	if not tiles.has(coords):
		return null
	var tile = tiles[coords]
	if not is_instance_valid(tile):
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
	var x = sqrt(3.0) * HexTile.HEX_RADIUS * (coords.x + coords.y * 0.5)
	var z = 1.5 * HexTile.HEX_RADIUS * coords.y
	return Vector3(x, 0, z)


func world_to_hex(world_pos: Vector3) -> Vector2i:
	var q = (sqrt(3.0) / 3.0 * world_pos.x - 1.0 / 3.0 * world_pos.z) / HexTile.HEX_RADIUS
	var r = (2.0 / 3.0 * world_pos.z) / HexTile.HEX_RADIUS
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
	var to_remove: Array[Vector2i] = []
	for coords in tiles.keys():
		var tile = tiles[coords]
		if is_instance_valid(tile):
			result.append(tile)
		else:
			to_remove.append(coords)
	# Cleanup invalid references
	for coords in to_remove:
		tiles.erase(coords)
	return result

func remove_tile(coords: Vector2i):
	if not tiles.has(coords):
		return
	var tile = tiles[coords]
	tiles.erase(coords)
	if is_instance_valid(tile):
		tile.queue_free()
	refresh_edges_around(coords)

## Tell tiles what lies across their edges (HexTile.update_edges) - all of them, or `list`
func update_tile_edges(list = null) -> void:
	for tile in (get_all_tiles() if list == null else list):
		if is_instance_valid(tile):
			tile.update_edges(self)

## The tile at `coords` appeared, changed or vanished: it and its neighbours redraw their borders
func refresh_edges_around(coords: Vector2i) -> void:
	var list: Array = []
	var own = get_tile(coords)
	if own:
		list.append(own)
	for dir in HexTile.EDGE_DIRECTIONS:
		var other = get_tile(coords + dir)
		if other:
			list.append(other)
	update_tile_edges(list)
