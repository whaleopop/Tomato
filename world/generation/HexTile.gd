## Single hexagonal tile for the map with collision
extends StaticBody3D
class_name HexTile

# Preload material library for batching
const BiomeMaterialLibrary = preload("res://world/generation/BiomeMaterialLibrary.gd")

signal tile_destroyed
signal tile_damaged(health: float)

enum BiomeType {
	GRASS,
	FOREST,
	DESERT,
	ROCK,
	WATER,
	SHALLOW_WATER,  # Мелководье - можно проходить медленнее
	SWAMP,          # Болото - замедляет движение
	BEACH,          # Пляж - переход между водой и землей
	MOUNTAIN        # Горы - высокие, нельзя спавниться
}

var hex_coords: Vector2i = Vector2i.ZERO
var biome_type: BiomeType = BiomeType.GRASS
var height: float = 0.0
var tile_health: float = 100.0
var max_health: float = 100.0
var is_destroyed: bool = false
var can_destroy: bool = true
var can_spawn: bool = true  # Можно ли спавниться на этом тайле

const HEX_RADIUS: float = 2.0
const HEX_INNER_RADIUS: float = HEX_RADIUS * 0.8660254
const HEX_HEIGHT: float = 0.3
const BOUNCE_DEPTH: float = 0.18   # how far a tile dips when a hero lands on it
const BOUNCE_TILT: float = 0.08    # radians, tilting away from the impact
# Edge k faces 60 * k degrees in the XZ plane; corner i (60 * i + 30) sits between edges i, i + 1
const EDGE_DIRECTIONS = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
const LAND_JOIN_STEP: float = 0.075   # world units: neighbours closer than this are drawn as one surface
const WATER_JOIN_STEP: float = 0.12
# The shrinking zone (DestructionSystem): a tile is marked, catches fire, then a mountain rises on it.
# Mountains are walls: nobody walks on or over them, they block sight, and they ring the island
# from the start (HexGenerator) so nobody can fall off.
enum ZoneState { NONE, WARNED, BURNING }
const MOUNTAIN_HEIGHT: float = 3.8     # above the tile top; a jump reaches ~2
const MOUNTAIN_RISE_TIME: float = 1.2
const ZONE_DANGER = [0.0, 0.55, 1.0]  # shader glow per ZoneState
var zone_state: int = ZoneState.NONE
var _zone_fire: FireTrail = null

var _bounce_tween: Tween = null
var _visual_rest: Dictionary = {}  # MeshInstance3D -> rest transform


func _ready():
	_create_mesh()
	_create_collision()

	# For mountains, create extra volumetric geometry
	if biome_type == BiomeType.MOUNTAIN:
		_create_mountain_geometry()

func _create_mesh():
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance"

	var mesh := ArrayMesh.new()

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var normals := PackedVector3Array()

	# Top hex
	for i in range(6):
		var angle = deg_to_rad(60 * i + 30)
		var x = cos(angle) * HEX_RADIUS
		var z = sin(angle) * HEX_RADIUS
		vertices.append(Vector3(x, HEX_HEIGHT * 0.5, z))
		normals.append(Vector3.UP)

	# Bottom hex
	for i in range(6):
		var angle = deg_to_rad(60 * i + 30)
		var x = cos(angle) * HEX_RADIUS
		var z = sin(angle) * HEX_RADIUS
		vertices.append(Vector3(x, -HEX_HEIGHT * 0.5, z))
		normals.append(Vector3.DOWN)

	# Top face
	for i in range(1, 5):
		indices.append(0)
		indices.append(i)
		indices.append(i + 1)

	# Bottom face
	for i in range(1, 5):
		indices.append(6)
		indices.append(6 + i + 1)
		indices.append(6 + i)

	# Side faces
	for i in range(6):
		var a = i
		var b = (i + 1) % 6
		var c = i + 6
		var d = ((i + 1) % 6) + 6

		indices.append(a)
		indices.append(b)
		indices.append(d)

		indices.append(a)
		indices.append(d)
		indices.append(c)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = normals

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	mesh_instance.mesh = mesh
	mesh_instance.set_surface_override_material(0, _get_biome_material())
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	add_child(mesh_instance)



func _create_collision():
	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape"

	var shape = ConvexPolygonShape3D.new()
	var points := PackedVector3Array()

	for i in range(6):
		var angle = deg_to_rad(60 * i + 30)
		var x = cos(angle) * HEX_RADIUS
		var z = sin(angle) * HEX_RADIUS
		points.append(Vector3(x, HEX_HEIGHT * 0.5, z))
		points.append(Vector3(x, -HEX_HEIGHT * 0.5, z))

	shape.points = points
	collision.shape = shape
	add_child(collision)



func _generate_hex_vertices() -> PackedVector3Array:
	var vertices = PackedVector3Array()
	var center = Vector3(0, height, 0)
	
	for i in range(6):
		var angle = deg_to_rad(60 * i)
		var x = cos(angle) * HEX_INNER_RADIUS
		var z = sin(angle) * HEX_INNER_RADIUS
		vertices.append(center + Vector3(x, 0, z))
	
	# Center vertex
	vertices.append(center)
	
	return vertices

func _generate_hex_indices() -> PackedInt32Array:
	var indices = PackedInt32Array()
	var center_index = 6
	
	for i in range(6):
		var next = (i + 1) % 6
		indices.append(center_index)
		indices.append(i)
		indices.append(next)
	
	return indices

func _get_biome_material() -> Material:
	# Try to use shader material
	if biome_type == BiomeType.WATER or biome_type == BiomeType.SHALLOW_WATER:
		var shader_mat = ShaderHelper.create_water_material()
		if shader_mat:
			return shader_mat
	else:
		var shader_mat = ShaderHelper.create_hex_material(biome_type, height)
		if shader_mat:
			return shader_mat

	# Fallback: use shared material library (батчинг материалов)
	# Вместо создания нового материала каждый раз, переиспользуем общие материалы
	var material_lib = BiomeMaterialLibrary.get_instance()
	return material_lib.get_material(biome_type)

func is_water() -> bool:
	return biome_type == BiomeType.WATER or biome_type == BiomeType.SHALLOW_WATER

## Walking speed on this ground (MovementComponent.terrain_multiplier)
static func speed_factor(biome: int) -> float:
	match biome:
		BiomeType.WATER:
			return 0.65
		BiomeType.SHALLOW_WATER:
			return 0.8
		BiomeType.SWAMP:
			return 0.85
	return 1.0

## Same kind of ground (land / water) at nearly the same level: the two tiles look like one
func joins(other: HexTile) -> bool:
	if not other or other.is_destroyed or is_destroyed or other.is_water() != is_water():
		return false
	return abs(other.position.y - position.y) <= (WATER_JOIN_STEP if is_water() else LAND_JOIN_STEP)

## Tell the shader what lies across each edge and where each top corner should sit, so joined
## tiles blend their colors and meet at the same height (no line, no step). Collision is untouched:
## a corner moves by at most half a join step. Called by HexGrid.update_tile_edges.
func update_edges(grid: HexGrid) -> void:
	var mesh := get_node_or_null("MeshInstance") as GeometryInstance3D
	if not mesh or is_destroyed:
		return
	var neighbours: Array = []
	for dir in EDGE_DIRECTIONS:
		neighbours.append(grid.get_tile(hex_coords + dir))
	var water = is_water()
	var own_color = ShaderHelper.biome_color(biome_type)
	for k in 6:
		var other: HexTile = neighbours[k]
		var info := Color(own_color, 1.0)  # a = 1: rim (step, shore, void)
		if joins(other):
			if water:
				info = Color(1.0 if other.biome_type == BiomeType.SHALLOW_WATER else 0.0, 0.0, 0.0, 0.0)
			else:
				info = Color(ShaderHelper.biome_color(other.biome_type), 0.0)
		elif water:
			info = Color(0.0, 0.0, 0.0, 1.0)
		mesh.set_instance_shader_parameter("edge_%d" % k, info)

	# The three tiles at a corner agree on its height: the average of the joined ones
	# (transitively, so every tile computes the same group)
	var offsets: Array[float] = []
	for i in 6:
		var a: HexTile = neighbours[i]
		var b: HexTile = neighbours[(i + 1) % 6]
		var join_a = joins(a)
		var join_b = joins(b)
		var sum = position.y
		var count = 1
		if join_a or (join_b and b.joins(a)):
			sum += a.position.y
			count += 1
		if join_b or (join_a and a.joins(b)):
			sum += b.position.y
			count += 1
		offsets.append(sum / count - position.y)
	mesh.set_instance_shader_parameter("corner_a", Vector3(offsets[0], offsets[1], offsets[2]))
	mesh.set_instance_shader_parameter("corner_b", Vector3(offsets[3], offsets[4], offsets[5]))
	if water:
		mesh.set_instance_shader_parameter("shallow", 1.0 if biome_type == BiomeType.SHALLOW_WATER else 0.0)

func take_damage(amount: float):
	if is_destroyed or not can_destroy:
		return
	
	tile_health -= amount
	tile_damaged.emit(tile_health)
	
	if tile_health <= 0.0:
		destroy()

func destroy():
	if is_destroyed:
		return
	
	is_destroyed = true
	tile_destroyed.emit()
	# The neighbours get a rim along the hole right away
	var grid = get_parent() as HexGrid
	if grid:
		grid.refresh_edges_around(hex_coords)
	
	# Animate destruction
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.5)  # not 0: physics can't invert a zero basis
	tween.tween_callback(queue_free)

## Something heavy landed: the tile's top dips, springs back and wobbles away from the impact.
## Only the meshes move - the collision stays put, so whoever stands on it is not jostled.
func bounce(strength: float = 1.0, delay: float = 0.0, from: Vector3 = Vector3.INF) -> void:
	if is_destroyed or strength < 0.03 or not is_inside_tree():
		return
	if biome_type == BiomeType.WATER or biome_type == BiomeType.SHALLOW_WATER or is_mountain():
		return
	if _visual_rest.is_empty():
		for child in get_children():
			if child is MeshInstance3D:
				_visual_rest[child] = child.transform
	var axis := Vector3.ZERO
	if from != Vector3.INF:
		var away = global_position - from
		away.y = 0.0
		if away.length() > 0.05:
			axis = Vector3.UP.cross(away.normalized())
	if _bounce_tween and _bounce_tween.is_valid():
		_bounce_tween.kill()
	_bounce_tween = create_tween()
	if delay > 0.0:
		_bounce_tween.tween_interval(delay)
	_bounce_tween.tween_method(_apply_bounce.bind(clamp(strength, 0.0, 1.5), axis), 0.0, 1.0, 0.85)

func _apply_bounce(t: float, strength: float, axis: Vector3) -> void:
	# Starts at the bottom of the dip, overshoots up once, settles to rest at t = 1
	var wave = exp(-3.5 * t) * cos(t * 11.0) * (1.0 - t)
	var offset = Vector3(0, -BOUNCE_DEPTH * strength * wave, 0)
	var tilt = Basis(axis, BOUNCE_TILT * strength * wave) if axis != Vector3.ZERO else Basis.IDENTITY
	for node in _visual_rest:
		if is_instance_valid(node):
			var rest: Transform3D = _visual_rest[node]
			node.transform = Transform3D(tilt * rest.basis, tilt * rest.origin + offset)

## Landing thud around `pos`: the tile underneath dips hardest, the neighbours ripple after it
static func shake_around(context: Node3D, pos: Vector3, strength: float = 1.0, radius: float = 2.6) -> void:
	if not context or not context.is_inside_tree():
		return
	radius *= HEX_RADIUS  # the callers' radii are in (old, 1-unit) tile sizes
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, pos)
	var landed_in_water := false
	for hit in context.get_world_3d().direct_space_state.intersect_shape(query, 32):
		var tile = hit.collider
		if not tile is HexTile:
			continue
		var d = Vector2(tile.global_position.x - pos.x, tile.global_position.z - pos.z).length()
		if d < HEX_INNER_RADIUS and tile.is_water():
			landed_in_water = true
		var k = clamp(1.0 - d / (radius + HEX_RADIUS), 0.0, 1.0)
		tile.bounce(strength * pow(k, 1.5), d * 0.05, pos)
	if landed_in_water:
		WaterRipples.splash(pos, strength)  # water doesn't bounce, it splashes

func set_biome(biome: BiomeType):
	biome_type = biome
	# Update material
	var mesh_instance = get_node_or_null("MeshInstance") as MeshInstance3D
	if mesh_instance:
		var material = _get_biome_material()
		mesh_instance.set_surface_override_material(0, material)

func set_height(new_height: float):
	height = new_height
	# Use position if not in tree, global_position if in tree
	if is_inside_tree():
		global_position.y = new_height * HEX_HEIGHT
	else:
		position.y = new_height * HEX_HEIGHT

# ---------------------------------------------------------------- zone and mountains

func is_mountain() -> bool:
	return biome_type == BiomeType.MOUNTAIN

## Still part of the island you can walk on
func is_playable() -> bool:
	return not is_destroyed and not is_mountain()

## Marked for the next zone step (WARNED: glowing cracks) or already on fire (BURNING)
func set_zone_state(state: int) -> void:
	if is_mountain():
		return
	zone_state = state
	for node in [get_node_or_null("MeshInstance")]:
		if node:
			node.set_instance_shader_parameter("danger", ZONE_DANGER[state])
	if state == ZoneState.NONE and _zone_fire and is_instance_valid(_zone_fire):
		_zone_fire._burn_out()  # the core stopped burning (DestructionSystem "calm")
		_zone_fire = null
	if state == ZoneState.BURNING and not _zone_fire and is_inside_tree():
		_zone_fire = FireTrail.new()
		_zone_fire.name = "ZoneFire"
		_zone_fire.tick_damage = 0.0  # the zone itself burns people (server), this is the look
		_zone_fire.lifetime = 6.0
		_zone_fire.with_light = false
		_zone_fire.flame_scale = 1.7
		add_child(_zone_fire)
		_zone_fire.global_position = global_position
		var top = global_position + Vector3(0, HEX_HEIGHT * 0.5, 0)
		var points: Array = [top]
		for i in 6:
			var a = TAU * i / 6.0 + 0.5
			points.append(top + Vector3(cos(a), 0, sin(a)) * HEX_RADIUS * 0.55)
		_zone_fire.lay_points(points, 0.5)

## The flood (MapEvents): the tile goes under - it sinks to `water_y` over `seconds` (a shore) and
## becomes `to_biome` water. Cover standing on it topples, nobody spawns here any more.
func flood(to_biome: int, water_y: float, seconds: float = 0.0) -> void:
	if is_mountain() or is_destroyed:
		return
	if not is_water():
		tile_destroyed.emit()  # CoverWall / Bush attached to this tile topple
	can_spawn = false
	can_destroy = false
	if seconds > 0.0 and is_inside_tree():
		var t = create_tween()
		t.tween_property(self, "position:y", water_y, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_callback(_finish_flood.bind(to_biome))
	else:
		position.y = water_y
		_finish_flood(to_biome)

func _finish_flood(to_biome: int) -> void:
	height = position.y / HEX_HEIGHT
	set_biome(to_biome)
	var grid = get_parent() as HexGrid
	if grid:
		grid.refresh_edges_around(hex_coords)
		grid.terrain_version += 1

## The zone takes this tile: a mountain rises (animated) or simply stands there (late joiners).
## Cover on the tile falls, loot on it is gone.
func raise_mountain(animated: bool = true) -> void:
	if is_mountain() or is_destroyed:
		return
	zone_state = ZoneState.NONE
	if _zone_fire and is_instance_valid(_zone_fire):
		_zone_fire._burn_out()  # the flames would stick out of the rock
		_zone_fire = null
	tile_destroyed.emit()  # CoverWall / Bush attached to this tile topple
	_clear_loot()
	can_spawn = false
	can_destroy = false
	set_biome(BiomeType.MOUNTAIN)
	var mesh = get_node_or_null("MeshInstance")
	if mesh:
		mesh.set_instance_shader_parameter("danger", 0.0)
	_create_mountain_geometry(animated)
	var grid = get_parent() as HexGrid
	if grid:
		grid.refresh_edges_around(hex_coords)
	if animated:
		HexTile.shake_around(self, global_position, 0.9, 2.2)

func _clear_loot() -> void:
	if not is_inside_tree():
		return
	var center = Vector2(global_position.x, global_position.z)
	for group in ["loot_items", "loot_containers"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D and Vector2(node.global_position.x, node.global_position.z).distance_to(center) < HEX_RADIUS * 0.95:
				node.queue_free()

## Craggy rock wall filling the hex, seeded by the tile coordinates (the same on every peer).
## Opaque (the fog of war reads the depth buffer), on the cover layer (blocks sight and fire),
## with a tall collision prism so nobody can climb it.
func _create_mountain_geometry(animated: bool = false):
	var rng = RandomNumberGenerator.new()
	rng.seed = (hex_coords.x * 73856093) ^ (hex_coords.y * 19349663) ^ 0x5bd1e995
	var base_y = HEX_HEIGHT * 0.5

	var holder = Node3D.new()
	holder.name = "Mountain"
	add_child(holder)

	var peak = MeshInstance3D.new()
	peak.name = "MountainPeak"
	var segments = 12
	var tops = [Vector3(rng.randf_range(-0.2, 0.2), MOUNTAIN_HEIGHT * rng.randf_range(0.85, 1.0), rng.randf_range(-0.2, 0.2)) * Vector3(HEX_RADIUS, 1, HEX_RADIUS)]
	# Rings from the hex outline up to the top: a craggy cone that fills the whole tile
	var rings: Array = []
	for level in [0.0, 0.35, 0.7]:
		var ring: Array = []
		for i in range(segments):
			var angle = (TAU / segments) * i
			# The base follows the hexagon, so neighbouring mountains join into one ridge
			var hex_r = HEX_INNER_RADIUS / cos(fmod(angle + PI / 6.0, PI / 3.0) - PI / 6.0)
			var r = hex_r * lerp(0.98, 0.25, level) * rng.randf_range(0.9, 1.05)
			var y = base_y + MOUNTAIN_HEIGHT * level + rng.randf_range(0.0, 0.35) * (1.0 if level > 0.0 else 0.2)
			ring.append(Vector3(cos(angle) * r, y, sin(angle) * r))
		rings.append(ring)
	var top: Vector3 = tops[0] + Vector3(0, base_y, 0)

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat facets, like the rest of the low-poly art
	for l in range(rings.size() - 1):
		var lo: Array = rings[l]
		var hi: Array = rings[l + 1]
		for i in range(segments):
			var n = (i + 1) % segments
			for v in [lo[i], hi[n], hi[i], lo[i], lo[n], hi[n]]:
				st.add_vertex(v)
	var last: Array = rings[rings.size() - 1]
	for i in range(segments):
		var n = (i + 1) % segments
		for v in [last[i], last[n], top]:
			st.add_vertex(v)
	st.generate_normals()
	peak.mesh = st.commit()
	peak.set_surface_override_material(0, _mountain_material(0))
	holder.add_child(peak)
	_add_mountain_rocks(rng, holder)

	# Tall prism: can't be walked on, jumped over or seen through
	var collision = CollisionShape3D.new()
	collision.name = "MountainCollision"
	var shape = ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for i in range(6):
		var angle = deg_to_rad(60 * i + 30)
		pts.append(Vector3(cos(angle) * HEX_RADIUS, base_y, sin(angle) * HEX_RADIUS))
		pts.append(Vector3(cos(angle) * HEX_RADIUS * 0.8, base_y + MOUNTAIN_HEIGHT, sin(angle) * HEX_RADIUS * 0.8))
	shape.points = pts
	collision.shape = shape
	add_child(collision)
	collision_layer |= CoverSpawner.COVER_LAYER

	if animated and is_inside_tree():
		collision.disabled = true  # players are shoved off first (DestructionSystem)
		holder.position.y = -MOUNTAIN_HEIGHT - 0.5
		var t = create_tween()
		t.tween_property(holder, "position:y", 0.0, MOUNTAIN_RISE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_callback(func(): collision.disabled = false)
		_mountain_dust()

func _mountain_dust() -> void:
	var dust = GPUParticles3D.new()
	dust.name = "MountainDust"
	dust.amount = 40
	dust.lifetime = 1.4
	dust.one_shot = true
	dust.explosiveness = 0.7
	var process = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = HEX_RADIUS * 0.8
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 4.0
	process.gravity = Vector3(0, -2.5, 0)
	process.scale_min = 0.6
	process.scale_max = 1.4
	process.color = Color(0.62, 0.56, 0.5, 0.75)
	dust.process_material = process
	var quad = QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = FireTrail._soft_dot(Color(1, 1, 1, 1), Color(1, 1, 1, 0))  # round puffs, not squares
	quad.material = mat
	dust.draw_pass_1 = quad
	dust.position.y = HEX_HEIGHT
	add_child(dust)
	dust.emitting = true
	get_tree().create_timer(dust.lifetime + 0.5).timeout.connect(dust.queue_free)

static var _mountain_materials: Array = []

## Shared materials: 0 = peak, 1 = rocks
static func _mountain_material(kind: int) -> StandardMaterial3D:
	if _mountain_materials.is_empty():
		for color in [Color(0.4, 0.37, 0.35), Color(0.47, 0.44, 0.41)]:
			var material = StandardMaterial3D.new()
			material.albedo_color = color
			material.roughness = 1.0
			_mountain_materials.append(material)
	return _mountain_materials[kind]

## Rocks around the foot of the mountain
func _add_mountain_rocks(rng: RandomNumberGenerator, parent: Node3D):
	var num_rocks = rng.randi_range(3, 6)
	for i in range(num_rocks):
		var rock = MeshInstance3D.new()
		rock.name = "Rock_%d" % i
		var mesh = SphereMesh.new()
		mesh.radius = rng.randf_range(0.12, 0.25) * HEX_RADIUS
		mesh.height = rng.randf_range(0.18, 0.35) * HEX_RADIUS
		mesh.radial_segments = 6
		mesh.rings = 3
		rock.mesh = mesh
		var angle = rng.randf() * TAU
		var distance = rng.randf_range(0.7, 0.9) * HEX_INNER_RADIUS
		rock.position = Vector3(cos(angle) * distance, HEX_HEIGHT * 0.5 + rng.randf_range(0.0, 0.1), sin(angle) * distance)
		rock.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		rock.set_surface_override_material(0, _mountain_material(1))
		parent.add_child(rock)
