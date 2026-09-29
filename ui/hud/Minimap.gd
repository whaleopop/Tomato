## Minimap (top-right): the hex map as a glowing dot grid and your arrow (no enemies on it).
## Fog of war: only explored tiles show their biome, the rest is a faint outline of the island.
## The tile layer is baked into a texture and rebuilt when tiles get explored or destroyed.
extends Control
class_name Minimap

const MAP_PIXELS: int = 200
const REFRESH_INTERVAL: float = 0.5
const UNEXPLORED_COLOR := Color(0.55, 0.62, 0.8, 0.14)
const MOUNTAIN_COLOR := Color(0.36, 0.33, 0.31, 0.95)  # the zone's walls: known to everyone
const WARN_COLOR := Color(1.0, 0.62, 0.15)
const BURN_COLOR := Color(1.0, 0.25, 0.1)

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
var _zone_center: Vector2i = Vector2i.ZERO
var _zone_radius: int = -1   # safe radius of the current / next step (-1: none yet)
var _shift_center: Vector2i = Vector2i.ZERO  # where the final zone moves (MapEvents center_shift)
var _shift_radius: int = -1
var _shift_until: int = 0
var _last_terrain: int = -1
var _dot: int = 2

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
		if hex_grid and is_instance_valid(hex_grid) and (_count_alive_tiles() != _last_tile_count or _explored_count() != _last_explored or hex_grid.terrain_version != _last_terrain):
			_rebuild_texture()
	queue_redraw()

## Walkable tiles (mountains rise from the zone): a change rebuilds the texture
func _count_alive_tiles() -> int:
	var n = 0
	for tile in hex_grid.tiles.values():
		if is_instance_valid(tile) and tile.is_playable():
			n += 1
	return n

## The zone's safe area (PlayerHUD passes NetworkManager.zone_changed on)
func set_zone(_kind: String, center: Vector2i, radius: int):
	_zone_center = center
	_zone_radius = radius

## The final zone moves (PlayerHUD passes the map event on): a yellow ring until it does
func set_zone_shift(center: Vector2i, radius: int, seconds: float):
	_shift_center = center
	_shift_radius = radius
	_shift_until = Time.get_ticks_msec() + int(seconds * 1000.0) + 1500

func _world_to_map(world_pos: Vector3) -> Vector2:
	return (Vector2(world_pos.x, world_pos.z) - _world_min) * _world_scale

func _rebuild_texture():
	if not hex_grid or not is_instance_valid(hex_grid) or hex_grid.tiles.is_empty():
		return
	_last_tile_count = _count_alive_tiles()
	_last_explored = _explored_count()
	_last_terrain = hex_grid.terrain_version
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
	_dot = dot
	for coords in hex_grid.tiles.keys():
		var tile = hex_grid.get_tile(coords)
		if not tile or tile.is_destroyed:
			continue
		var p = _world_to_map(hex_grid.hex_to_world(coords))
		var color = UNEXPLORED_COLOR
		if tile.is_mountain():
			color = MOUNTAIN_COLOR
		elif not fog or fog.is_tile_explored(coords):
			color = HexMapView.terrace_shade(HexMapView.BIOME_COLORS.get(tile.biome_type, Color.GRAY), tile.level)
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

	# The zone: marked tiles glow, burning ones flash, the next safe area is a white ring
	if hex_grid and is_instance_valid(hex_grid):
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
		var cell = Vector2(_dot, _dot) * scale_to_rect
		for tile in hex_grid.tiles.values():
			if not is_instance_valid(tile) or tile.zone_state == HexTile.ZoneState.NONE:
				continue
			var c = BURN_COLOR if tile.zone_state == HexTile.ZoneState.BURNING else WARN_COLOR
			var tp = inset.position + _world_to_map(tile.global_position) * scale_to_rect
			draw_rect(Rect2(tp - cell / 2.0, cell), Color(c, 0.45 + 0.45 * pulse))
		if _zone_radius >= 0:
			var zc = inset.position + _world_to_map(hex_grid.hex_to_world(_zone_center)) * scale_to_rect
			var zr = (_zone_radius + 0.55) * VisibilitySystem.HEX_SPACING * _world_scale * scale_to_rect.x
			draw_arc(zc, zr, 0, TAU, 48, Color(1, 1, 1, 0.75), 1.6, true)
		if _shift_radius >= 0 and Time.get_ticks_msec() < _shift_until:
			var sc = inset.position + _world_to_map(hex_grid.hex_to_world(_shift_center)) * scale_to_rect
			var sr = (_shift_radius + 0.55) * VisibilitySystem.HEX_SPACING * _world_scale * scale_to_rect.x
			draw_arc(sc, sr, 0, TAU, 48, Color(UITheme.ACCENT_WARNING, 0.55 + 0.4 * pulse), 2.0, true)

		# Landmarks (Landmark): a steady diamond in their color
		for landmark in get_tree().get_nodes_in_group("map_landmarks"):
			if not landmark is Node3D or not is_instance_valid(landmark):
				continue
			var lc = inset.position + _world_to_map(landmark.global_position) * scale_to_rect
			if not inset.has_point(lc):
				continue
			var lcol: Color = landmark.get_meta("marker_color", Color.WHITE)
			var dia = PackedVector2Array([lc + Vector2(0, -5), lc + Vector2(5, 0), lc + Vector2(0, 5), lc + Vector2(-5, 0)])
			draw_colored_polygon(dia, Color(0.05, 0.06, 0.1, 0.85))
			var inner = PackedVector2Array([lc + Vector2(0, -3.5), lc + Vector2(3.5, 0), lc + Vector2(0, 3.5), lc + Vector2(-3.5, 0)])
			draw_colored_polygon(inner, lcol)

		# Map events everybody knows about: meteor circles, the harvest bonus, the zone drop
		for marker in get_tree().get_nodes_in_group("map_markers"):
			if not marker is Node3D or not is_instance_valid(marker):
				continue
			var mc = inset.position + _world_to_map(marker.global_position) * scale_to_rect
			if not inset.has_point(mc):
				continue
			var color: Color = marker.get_meta("marker_color", UITheme.ACCENT_WARNING)
			draw_circle(mc, 3.0, color)
			draw_arc(mc, 5.0 + 2.5 * pulse, 0, TAU, 16, Color(color, 0.85 - 0.5 * pulse), 1.5, true)

	# Other players are never drawn: the minimap doesn't give enemies away

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
