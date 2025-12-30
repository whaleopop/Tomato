## Single hexagonal tile for the map with collision
extends StaticBody3D
class_name HexTile

signal tile_destroyed
signal tile_damaged(health: float)

enum BiomeType {
	GRASS,
	FOREST,
	DESERT,
	ROCK,
	WATER
}

var hex_coords: Vector2i = Vector2i.ZERO
var biome_type: BiomeType = BiomeType.GRASS
var height: float = 0.0
var tile_health: float = 100.0
var max_health: float = 100.0
var is_destroyed: bool = false
var can_destroy: bool = true

const HEX_SIZE: float = 1.0
const HEX_HEIGHT: float = 0.3  # Taller tiles for better visibility

func _ready():
	_create_mesh()
	_create_collision()

func _create_mesh():
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance"

	# Use a cylinder mesh for better looking hexagon with height
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = HEX_SIZE
	cylinder.bottom_radius = HEX_SIZE
	cylinder.height = HEX_HEIGHT
	cylinder.radial_segments = 6  # 6 sides = hexagon

	mesh_instance.mesh = cylinder
	# Rotate 30 degrees to align flat edge for proper tiling
	mesh_instance.rotation.y = deg_to_rad(30)

	# Set material based on biome
	var material = _get_biome_material()
	mesh_instance.set_surface_override_material(0, material)

	# Enable shadows
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	add_child(mesh_instance)

func _create_collision():
	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape"

	# Use cylinder collision matching the mesh
	var shape = CylinderShape3D.new()
	shape.radius = HEX_SIZE * 0.9
	shape.height = HEX_HEIGHT

	collision.shape = shape
	add_child(collision)

func _generate_hex_vertices() -> PackedVector3Array:
	var vertices = PackedVector3Array()
	var center = Vector3(0, height, 0)
	
	for i in range(6):
		var angle = deg_to_rad(60 * i)
		var x = cos(angle) * HEX_SIZE
		var z = sin(angle) * HEX_SIZE
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
	if biome_type == BiomeType.WATER:
		var shader_mat = ShaderHelper.create_water_material()
		if shader_mat:
			return shader_mat
	else:
		var shader_mat = ShaderHelper.create_hex_material(biome_type, height)
		if shader_mat:
			return shader_mat

	# Fallback to standard material
	var material = StandardMaterial3D.new()

	match biome_type:
		BiomeType.GRASS:
			material.albedo_color = Color(0.3, 0.7, 0.25)
		BiomeType.FOREST:
			material.albedo_color = Color(0.15, 0.45, 0.15)
		BiomeType.DESERT:
			material.albedo_color = Color(0.85, 0.75, 0.55)
		BiomeType.ROCK:
			material.albedo_color = Color(0.45, 0.42, 0.4)
			material.roughness = 0.9
		BiomeType.WATER:
			material.albedo_color = Color(0.2, 0.5, 0.85)
			material.metallic = 0.3
			material.roughness = 0.1

	return material

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
	
	# Animate destruction
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.5)
	tween.tween_callback(queue_free)

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
