## Minimap (top-right): the hex map as a glowing dot grid, your arrow, visible enemies.
## Fog of war: only explored tiles show their biome, the rest is a faint outline of the island.
## The tile layer is baked into a texture and rebuilt when tiles get explored or destroyed.
extends Control
class_name Minimap

const MAP_PIXELS: int = 200
const REFRESH_INTERVAL: float = 0.5
const UNEXPLORED_COLOR := Color(0.55, 0.62, 0.8, 0.14)

var map_size: Vector2 = Vector2(MAP_PIXELS, MAP_PIXELS)
var player_position: Vector2 = Vector2.ZERO  # Kept for older callers

var hex_grid: HexGrid = null
var tracked_player: Node3D = null

var _tile_texture: ImageTexture = null
var _world_min: Vector2 = Vector2.ZERO
var _world_scale: float = 1.0
var _last_tile_count: int = -1
var _last_explored: int = -1
var _refresh_timer: float = 0.0

func _fog() -> VisibilitySystem:
	return get_tree().get_first_node_in_group("visibility_system") as VisibilitySystem if is_inside_tree() else null

func _explored_count() -> int:
	var fog = _fog()
	return (fog.explored_count + (100000 if fog.reveal_all else 0)) if fog else -2

func _ready():
	custom_minimum_size = map_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup_grid(grid: HexGrid):
	hex_grid = grid
	_last_tile_count = -1
	_rebuild_texture()

func track(player: Node3D):
	tracked_player = player

func update_player_position(world_pos: Vector3):
	player_position = _world_to_map(world_pos)

func _process(delta: float):
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_INTERVAL:
		_refresh_timer = 0.0
		if hex_grid and is_instance_valid(hex_grid) and (_count_alive_tiles() != _last_tile_count or _explored_count() != _last_explored):
			_rebuild_texture()
	queue_redraw()

## Destroyed tiles stay in the dictionary until someone touches them, so count explicitly
func _count_alive_tiles() -> int:
	var n = 0
	for tile in hex_grid.tiles.values():
		if is_instance_valid(tile) and not tile.is_destroyed:
			n += 1
	return n

func _world_to_map(world_pos: Vector3) -> Vector2:
	return (Vector2(world_pos.x, world_pos.z) - _world_min) * _world_scale

func _rebuild_texture():
	if not hex_grid or not is_instance_valid(hex_grid) or hex_grid.tiles.is_empty():
		return
	_last_tile_count = _count_alive_tiles()
	_last_explored = _explored_count()
	var fog = _fog()

	# Fit the whole (original) map into the square, based on grid radius
	var r = hex_grid.grid_radius
	var extent = Vector2(sqrt(3.0) * HexTile.HEX_RADIUS * (r + 1) * 2.0, 1.5 * HexTile.HEX_RADIUS * (r + 1) * 2.0)
	var side = max(extent.x, extent.y)
	_world_min = Vector2(-side / 2.0, -side / 2.0)
	_world_scale = MAP_PIXELS / side

	var img = Image.create(MAP_PIXELS, MAP_PIXELS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dot = max(2, int(HexTile.HEX_RADIUS * _world_scale * 1.5))
	for coords in hex_grid.tiles.keys():
		var tile = hex_grid.get_tile(coords)
		if not tile or tile.is_destroyed:
			continue
		var p = _world_to_map(hex_grid.hex_to_world(coords))
		var color = UNEXPLORED_COLOR
		if not fog or fog.is_tile_explored(coords):
			color = HexMapView.BIOME_COLORS.get(tile.biome_type, Color.GRAY)
			color.a = 0.85
		img.fill_rect(Rect2i(int(p.x) - dot / 2, int(p.y) - dot / 2, dot, dot), color)
	_tile_texture = ImageTexture.create_from_image(img)

func _draw():
	var rect = Rect2(Vector2.ZERO, size)
	var frame = UITheme.glass_box(Color(0.03, 0.05, 0.10, 0.55), Color(1, 1, 1, 0.16), 24, 0, 0)
	frame.shadow_color = Color(0, 0, 0, 0.3)
	frame.shadow_size = 14
	draw_style_box(frame, rect)

	var inset = Rect2(Vector2(8, 8), size - Vector2(16, 16))
	var scale_to_rect = inset.size / Vector2(MAP_PIXELS, MAP_PIXELS)
	if _tile_texture:
		draw_texture_rect(_tile_texture, inset, false)

	# Other players currently visible to us
	for p in get_tree().get_nodes_in_group("players"):
		if p == tracked_player or not is_instance_valid(p) or not p.visible:
			continue
		var mp = inset.position + _world_to_map(p.global_position) * scale_to_rect
		if inset.has_point(mp):
			draw_circle(mp, 4.0, UITheme.ACCENT_DANGER)

	# Us: arrow pointing where we look
	if tracked_player and is_instance_valid(tracked_player):
		var mp = inset.position + _world_to_map(tracked_player.global_position) * scale_to_rect
		var yaw = tracked_player.rotation.y
		var fwd = Vector2(sin(yaw), cos(yaw))
		var right = Vector2(fwd.y, -fwd.x)
		var tip = mp + fwd * 9.0
		var pts = PackedVector2Array([tip, mp - fwd * 5.0 + right * 6.0, mp - fwd * 2.0, mp - fwd * 5.0 - right * 6.0])
		draw_circle(mp, 9.0, Color(UITheme.ACCENT_PRIMARY, 0.25))
		draw_colored_polygon(pts, Color.WHITE)
