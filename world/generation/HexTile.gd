## Single hexagonal tile for the map
extends MeshInstance3D
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
const HEX_HEIGHT: float = 0.2

func _ready():
	_create_mesh()

func _create_mesh():
	var mesh_instance = MeshInstance3D.new()
	var array_mesh = ArrayMesh.new()
	
	# Create hexagonal mesh
	var vertices = _generate_hex_vertices()
	var indices = _generate_hex_indices()
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = array_mesh
	
	# Set material based on biome
	var material = _get_biome_material()
	mesh_instance.set_surface_override_material(0, material)
	
	add_child(mesh_instance)

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

func _get_biome_material() -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	
	match biome_type:
		BiomeType.GRASS:
			material.albedo_color = Color(0.2, 0.8, 0.2)
		BiomeType.FOREST:
			material.albedo_color = Color(0.1, 0.5, 0.1)
		BiomeType.DESERT:
			material.albedo_color = Color(0.9, 0.8, 0.6)
		BiomeType.ROCK:
			material.albedo_color = Color(0.5, 0.5, 0.5)
		BiomeType.WATER:
			material.albedo_color = Color(0.2, 0.4, 0.8)
			material.metallic = 0.5
			material.roughness = 0.2
	
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
	if get_child_count() > 0:
		var mesh_instance = get_child(0) as MeshInstance3D
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
