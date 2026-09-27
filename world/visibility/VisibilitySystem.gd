## Fog of war for the local player.
## Every tile has two values: visible (in sight right now) and explored (seen at least once).
##   unexplored             - covered by drifting clouds
##   explored, out of sight - dimmed: you remember the ground and the containers, but players
##                            and loot items there are hidden
##   in sight               - clear
## Sight is a circle around you (radius from the equipped weapon) that cover walls cut off
## (rays on CoverSpawner.COVER_LAYER), plus bullet trails that light up for a moment.
## Enemies in a bush stay hidden unless you come close or they shoot.
## FogOverlay draws the fog from `fog_texture`; the minimap reads `explored`.
extends Node
class_name VisibilitySystem

signal visibility_updated
signal explored_changed

const UPDATE_INTERVAL: float = 0.1
const FOG_FADE_DISTANCE: float = 2.0     # hexes at the edge of sight fade out
const BASE_VISIBILITY_RANGE: float = 5.0
const BULLET_TRAIL_WIDTH: float = 1.5
const EYE_HEIGHT: float = 1.0
const ALWAYS_SEEN: float = 1.5           # hexes around you, visible even through a wall
const BUSH_REVEAL_DISTANCE: float = 2.4  # world units: this close you spot someone in a bush
const SHOT_REVEAL_DISTANCE: float = 1.2  # a shot from inside a bush gives the shooter away
const FADE_SPEED: float = 4.0            # fog values per second on screen

var visibility_sources: Array[VisibilitySource] = []
var bullet_trails: Array[BulletTrail] = []
var hex_grid: HexGrid = null
var local_player: Player = null

var tile_visibility: Dictionary = {}  # Vector2i -> sight 0..1 (latest update)
var explored: Dictionary = {}         # Vector2i -> true
var explored_count: int = 0
var reveal_all: bool = false          # eliminated: the whole map opens up

# Fog texture: one texel per hex (axial q, r), R = sight, G = explored, smoothed over time
var fog_image: Image = null
var fog_texture: ImageTexture = null
var fog_origin: int = 0               # texel of axial (0, 0)
var fog_size: int = 1
var overlay: FogOverlay = null
var _shown: Dictionary = {}           # Vector2i -> Vector2(sight, explored) as on screen
var _timer: float = 0.0

func _ready():
	add_to_group("visibility_system")

func setup(grid: HexGrid):
	hex_grid = grid
	fog_origin = grid.grid_radius + 2
	fog_size = fog_origin * 2 + 1
	fog_image = Image.create(fog_size, fog_size, false, Image.FORMAT_RG8)
	fog_image.fill(Color(0, 0, 0))
	fog_texture = ImageTexture.create_from_image(fog_image)
	print("[VisibilitySystem] Fog of war over %d tiles" % grid.tiles.size())

func _process(delta: float):
	if not hex_grid or not is_instance_valid(hex_grid):
		return
	_update_bullet_trails(delta)

	_timer += delta
	if _timer >= UPDATE_INTERVAL:
		_timer = 0.0
		_update_reveal_all()
		_calculate_visibility()
		_update_objects_visibility()
		visibility_updated.emit()

	_animate_fog(delta)
	_keep_overlay_on_camera()

# ---------------------------------------------------------------- sight

func _calculate_visibility():
	var sight: Dictionary = {}
	for source in visibility_sources:
		if is_instance_valid(source.entity) and source.entity.is_inside_tree():
			_add_sight(source, sight)
	for trail in bullet_trails:
		_add_trail_visibility(trail, sight)
	tile_visibility = sight

	var newly = 0
	for coords in sight:
		if sight[coords] > 0.5 and not explored.has(coords):
			explored[coords] = true
			newly += 1
	if newly > 0:
		explored_count += newly
		explored_changed.emit()

## Circle of sight around a source; walls (cover layer) cast shadows
func _add_sight(source: VisibilitySource, sight: Dictionary):
	var pos: Vector3 = source.entity.global_position
	var center = hex_grid.world_to_hex(pos)
	var radius = source.get_visibility_range()
	var space = source.entity.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.collision_mask = CoverSpawner.COVER_LAYER
	query.from = pos + Vector3(0, EYE_HEIGHT, 0)
	var n = int(ceil(radius))
	for dq in range(-n, n + 1):
		for dr in range(max(-n, -dq - n), min(n, -dq + n) + 1):
			var coords = center + Vector2i(dq, dr)
			var tile = hex_grid.get_tile(coords)
			if not tile:
				continue
			var d = float(max(abs(dq), abs(dr), abs(dq + dr)))
			if d > radius:
				continue
			var vis = 1.0
			if d > radius - FOG_FADE_DISTANCE:
				vis = clamp((radius - d) / FOG_FADE_DISTANCE, 0.0, 1.0)
			if vis <= sight.get(coords, 0.0):
				continue
			if d > ALWAYS_SEEN:
				query.to = tile.global_position + Vector3(0, HexTile.HEX_HEIGHT * 0.5 + EYE_HEIGHT, 0)
				if not space.intersect_ray(query).is_empty():
					continue  # behind a wall
			sight[coords] = vis

func _add_trail_visibility(trail: BulletTrail, sight: Dictionary):
	var path_length = trail.start_pos.distance_to(trail.end_pos)
	var steps = int(ceil(path_length))
	var r = int(ceil(BULLET_TRAIL_WIDTH))
	for i in range(steps + 1):
		var t = float(i) / float(steps) if steps > 0 else 0.0
		var center = hex_grid.world_to_hex(trail.start_pos.lerp(trail.end_pos, t))
		for dq in range(-r, r + 1):
			for dr in range(max(-r, -dq - r), min(r, -dq + r) + 1):
				if float(max(abs(dq), abs(dr), abs(dq + dr))) <= BULLET_TRAIL_WIDTH:
					var coords = center + Vector2i(dq, dr)
					if hex_grid.tiles.has(coords):
						sight[coords] = max(sight.get(coords, 0.0), 0.8)

func _update_reveal_all():
	var dead = false
	if local_player and is_instance_valid(local_player):
		var health = local_player.get_component("HealthComponent")
		dead = health != null and health.is_dead
	reveal_all = dead

# ---------------------------------------------------------------- who is visible

func _update_objects_visibility():
	var tree = get_tree()
	if not tree:
		return
	var me = local_player if local_player and is_instance_valid(local_player) else null

	for player in tree.get_nodes_in_group("players"):
		if not is_instance_valid(player) or player == me:
			continue
		var health = player.get_component("HealthComponent") if player.has_method("get_component") else null
		if health and health.is_dead:
			player.visible = false
			continue
		player.visible = reveal_all or _can_see_player(player, me)

	for item in tree.get_nodes_in_group("loot_items"):
		if is_instance_valid(item):
			item.visible = reveal_all or get_visibility_at(item.global_position) > 0.3

	# Containers are remembered once seen
	for container in tree.get_nodes_in_group("loot_containers"):
		if is_instance_valid(container):
			container.visible = reveal_all or is_explored(container.global_position) or get_visibility_at(container.global_position) > 0.3

func _can_see_player(player: Node3D, me: Node3D) -> bool:
	if player.get_meta("net_hidden", false):
		return false  # the server doesn't even tell us where they are
	if get_visibility_at(player.global_position) <= 0.3:
		return false
	if not Bush.any_contains(get_tree(), player.global_position):
		return true
	# Hidden in a bush: only when right next to them, sharing the bush, or they just fired
	if me and player.global_position.distance_to(me.global_position) < BUSH_REVEAL_DISTANCE:
		return true
	for trail in bullet_trails:
		if trail.start_pos.distance_to(player.global_position + Vector3(0, EYE_HEIGHT, 0)) < SHOT_REVEAL_DISTANCE + EYE_HEIGHT:
			return true
	return false

## The local player is hidden in a bush (HUD hint)
func is_local_hidden() -> bool:
	return local_player != null and is_instance_valid(local_player) and local_player.is_inside_tree() \
		and Bush.any_contains(get_tree(), local_player.global_position)

# ---------------------------------------------------------------- fog texture

func _animate_fog(delta: float):
	var changed = false
	var step = FADE_SPEED * delta
	for coords in hex_grid.tiles:
		var target = Vector2(1.0, 1.0) if reveal_all else Vector2(tile_visibility.get(coords, 0.0), 1.0 if explored.has(coords) else 0.0)
		var shown: Vector2 = _shown.get(coords, Vector2.ZERO)
		if shown == target:
			continue
		shown = Vector2(move_toward(shown.x, target.x, step), move_toward(shown.y, target.y, step))
		_shown[coords] = shown
		var px = coords.x + fog_origin
		var py = coords.y + fog_origin
		if px >= 0 and py >= 0 and px < fog_size and py < fog_size:
			fog_image.set_pixel(px, py, Color(shown.x, shown.y, 0.0))
			changed = true
	if changed:
		fog_texture.update(fog_image)

func _keep_overlay_on_camera():
	var cam = get_viewport().get_camera_3d() if get_viewport() else null
	if not cam:
		return
	if not overlay or not is_instance_valid(overlay):
		overlay = FogOverlay.new()
		overlay.setup(self)
	if overlay.get_parent() != cam:
		if overlay.get_parent():
			overlay.get_parent().remove_child(overlay)
		cam.add_child(overlay)

func _exit_tree():
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()

# ---------------------------------------------------------------- sources & queries

func _update_bullet_trails(delta: float):
	var i = bullet_trails.size() - 1
	while i >= 0:
		bullet_trails[i].time_remaining -= delta
		if bullet_trails[i].time_remaining <= 0:
			bullet_trails.remove_at(i)
		i -= 1

## Register a visibility source (player)
func register_source(entity: Node3D, weapon: RangedWeapon = null) -> VisibilitySource:
	# Registering the same entity twice would double all the per-frame work
	for existing in visibility_sources:
		if existing.entity == entity:
			if weapon:
				existing.weapon = weapon
			return existing

	var source = VisibilitySource.new()
	source.entity = entity
	source.weapon = weapon
	visibility_sources.append(source)
	print("[VisibilitySystem] Registered visibility source: %s" % entity.name)
	return source

## Unregister a visibility source
func unregister_source(entity: Node3D):
	for i in range(visibility_sources.size() - 1, -1, -1):
		if visibility_sources[i].entity == entity:
			visibility_sources.remove_at(i)
			print("[VisibilitySystem] Unregistered visibility source: %s" % entity.name)
			return

## Update weapon for a source
func update_source_weapon(entity: Node3D, weapon: RangedWeapon):
	for source in visibility_sources:
		if source.entity == entity:
			source.weapon = weapon
			return

## Add a bullet trail for temporary visibility
func add_bullet_trail(start: Vector3, end: Vector3, duration: float = 0.5):
	var trail = BulletTrail.new()
	trail.start_pos = start
	trail.end_pos = end
	trail.time_remaining = duration
	bullet_trails.append(trail)

## Check if a position is visible
func is_position_visible(world_pos: Vector3) -> bool:
	return get_visibility_at(world_pos) > 0.5

## Get visibility at a position (0.0 - 1.0)
func get_visibility_at(world_pos: Vector3) -> float:
	if not hex_grid:
		return 1.0
	if reveal_all:
		return 1.0
	return tile_visibility.get(hex_grid.world_to_hex(world_pos), 0.0)

## Has the local player ever seen this spot?
func is_explored(world_pos: Vector3) -> bool:
	return reveal_all or hex_grid == null or explored.has(hex_grid.world_to_hex(world_pos))

func is_tile_explored(coords: Vector2i) -> bool:
	return reveal_all or explored.has(coords)

## Set local player for special handling
func set_local_player(player: Player):
	local_player = player
	register_source(player)

## Inner class for visibility source
class VisibilitySource:
	var entity: Node3D = null
	var weapon: RangedWeapon = null
	var base_range: float = BASE_VISIBILITY_RANGE

	func get_visibility_range() -> float:
		if weapon:
			return weapon.visibility_range
		return base_range

## Inner class for bullet trail
class BulletTrail:
	var start_pos: Vector3
	var end_pos: Vector3
	var time_remaining: float = 0.5
