## Building structure
extends Structure
class_name Building

func _ready():
	super._ready()
	_create_visual()

func _create_visual():
	# Create simple building mesh
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(2.0, 3.0, 2.0)
	mesh_instance.mesh = box_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.7, 0.7)
	mesh_instance.set_surface_override_material(0, material)
	
	add_child(mesh_instance)
