## Handles destruction of individual tiles
extends RefCounted
class_name TileDestroyer

signal tile_destroyed(coords: Vector2i)

func destroy_tile(tile: HexTile):
	if tile == null or tile.is_destroyed:
		return
	
	tile.destroy()
	tile_destroyed.emit(tile.hex_coords)

func destroy_tiles_in_radius(grid: HexGrid, center_coords: Vector2i, radius: int):
	var destroyed_count = 0
	
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			var coords = center_coords + Vector2i(q, r)
			var distance = _hex_distance(center_coords, coords)
			
			if distance <= radius:
				var tile = grid.get_tile(coords)
				if tile and not tile.is_destroyed:
					destroy_tile(tile)
					destroyed_count += 1
	
	return destroyed_count

func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	return (abs(a.x - b.x) + abs(a.x + a.y - b.x - b.y) + abs(a.y - b.y)) / 2

