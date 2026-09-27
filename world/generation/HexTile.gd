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

const HEX_RADIUS: float = 1.0
const HEX_INNER_RADIUS: float = HEX_RADIUS * 0.8660254
const HEX_HEIGHT: float = 0.3
const BOUNCE_DEPTH: float = 0.18   # how far a tile dips when a hero lands on it
const BOUNCE_TILT: float = 0.08    # radians, tilting away from the impact
# Edge k faces 60 * k degrees in the XZ plane; corner i (60 * i + 30) sits between edges i, i + 1
const EDGE_DIRECTIONS = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
const LAND_JOIN_STEP: float = 0.075   # world units: neighbours closer than this are drawn as one surface
const WATER_JOIN_STEP: float = 0.12

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
	if biome_type == BiomeType.WATER or biome_type == BiomeType.SHALLOW_WATER:
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

## Create volumetric mountain geometry on top of base tile
func _create_mountain_geometry():
	# Create a rocky peak on top of the tile
	var peak = MeshInstance3D.new()
	peak.name = "MountainPeak"

	# Create a cone-shaped mountain
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	var normals = PackedVector3Array()

	# Peak height above the tile
	var peak_height = 1.5
	var base_radius = HEX_RADIUS * 0.8

	# Top vertex (peak)
	vertices.append(Vector3(0, HEX_HEIGHT * 0.5 + peak_height, 0))
	normals.append(Vector3.UP)

	# Create jagged mountain sides (12 points around base)
	var segments = 12
	for i in range(segments):
		var angle = (TAU / segments) * i
		# Vary radius slightly for more natural look
		var radius_var = base_radius * randf_range(0.85, 1.0)
		var x = cos(angle) * radius_var
		var z = sin(angle) * radius_var
		# Vary height slightly for jagged edges
		var y_var = HEX_HEIGHT * 0.5 + randf_range(0, 0.3)

		vertices.append(Vector3(x, y_var, z))

		# Calculate normal pointing outward and up
		var normal = Vector3(x, peak_height * 0.5, z).normalized()
		normals.append(normal)

	# Create triangles from peak to base
	for i in range(segments):
		var next = (i + 1) % segments
		indices.append(0)  # Peak
		indices.append(i + 1)
		indices.append(next + 1)

	# Create base cap
	var center_idx = vertices.size()
	vertices.append(Vector3(0, HEX_HEIGHT * 0.5, 0))
	normals.append(Vector3.DOWN)

	for i in range(segments):
		var next = (i + 1) % segments
		indices.append(center_idx)
		indices.append(next + 1)
		indices.append(i + 1)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	peak.mesh = mesh

	# Material for mountain peak - darker and rockier
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.28, 0.26)
	material.roughness = 1.0
	material.metallic = 0.1
	# Add slight transparency to not completely block view
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.85
	peak.set_surface_override_material(0, material)

	add_child(peak)

	# Add some rock details around the base
	_add_mountain_rocks()

## Add small rocks around mountain base for detail
func _add_mountain_rocks():
	var num_rocks = randi_range(3, 6)

	for i in range(num_rocks):
		var rock = MeshInstance3D.new()
		rock.name = "Rock_%d" % i

		# Small irregular rock shape
		var mesh = SphereMesh.new()
		mesh.radius = randf_range(0.1, 0.2)
		mesh.height = randf_range(0.15, 0.3)
		rock.mesh = mesh

		# Random position around mountain base
		var angle = randf() * TAU
		var distance = randf_range(0.3, 0.7)
		rock.position = Vector3(
			cos(angle) * distance,
			HEX_HEIGHT * 0.5 + randf_range(-0.05, 0.1),
			sin(angle) * distance
		)

		# Random rotation
		rock.rotation = Vector3(
			randf_range(-0.3, 0.3),
			randf() * TAU,
			randf_range(-0.3, 0.3)
		)

		# Random scale variation
		var scale_factor = randf_range(0.8, 1.3)
		rock.scale = Vector3(scale_factor, scale_factor * randf_range(0.7, 1.2), scale_factor)

		# Rock material
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.35, 0.33, 0.3)
		material.roughness = 0.95
		material.metallic = 0.05
		rock.set_surface_override_material(0, material)

		add_child(rock)
