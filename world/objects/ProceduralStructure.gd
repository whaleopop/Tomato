## Procedural structure generated from primitive parts
extends Structure
class_name ProceduralStructure

const StructureMaterialLib = preload("res://world/objects/StructureMaterials.gd")

enum MeshType {
	BOX,
	CYLINDER,
	SPHERE,
	CONE
}

## Structure part definition
class StructurePart:
	var mesh_type: MeshType
	var size: Vector3  # For BOX: width/height/depth, CYLINDER/SPHERE: x=radius y=height z=unused, CONE: x=radius y=height
	var position: Vector3
	var rotation: Vector3  # Euler angles in radians
	var material_type: StructureMaterialLib.MaterialType
	var is_roof: bool = false

	func _init(p_mesh_type: MeshType, p_size: Vector3, p_position: Vector3, p_rotation: Vector3 = Vector3.ZERO, p_material: StructureMaterialLib.MaterialType = StructureMaterialLib.MaterialType.WOOD_LIGHT, p_is_roof: bool = false):
		mesh_type = p_mesh_type
		size = p_size
		position = p_position
		rotation = p_rotation
		material_type = p_material
		is_roof = p_is_roof

var parts: Array[StructurePart] = []
var roof_parts: Array[MeshInstance3D] = []  # Track roof parts for visibility control
var original_roof_transparency: Array[float] = []  # Store original transparency values

## Build structure from array of StructurePart definitions
func build_from_parts(part_definitions: Array[StructurePart]):
	parts = part_definitions
	var material_lib = StructureMaterialLib.get_instance()

	for part in parts:
		var mesh_instance = MeshInstance3D.new()

		# Create mesh based on type
		match part.mesh_type:
			MeshType.BOX:
				var box_mesh = BoxMesh.new()
				box_mesh.size = part.size
				mesh_instance.mesh = box_mesh

			MeshType.CYLINDER:
				var cylinder_mesh = CylinderMesh.new()
				cylinder_mesh.top_radius = part.size.x
				cylinder_mesh.bottom_radius = part.size.x
				cylinder_mesh.height = part.size.y
				mesh_instance.mesh = cylinder_mesh

			MeshType.SPHERE:
				var sphere_mesh = SphereMesh.new()
				sphere_mesh.radius = part.size.x
				sphere_mesh.height = part.size.y
				mesh_instance.mesh = sphere_mesh

			MeshType.CONE:
				var cone_mesh = CylinderMesh.new()
				cone_mesh.top_radius = 0.0
				cone_mesh.bottom_radius = part.size.x
				cone_mesh.height = part.size.y
				mesh_instance.mesh = cone_mesh

		# Apply material
		mesh_instance.material_override = material_lib.get_material(part.material_type)

		# Set transform
		mesh_instance.position = part.position
		mesh_instance.rotation = part.rotation

		# Add collision
		var static_body = StaticBody3D.new()
		var collision_shape = CollisionShape3D.new()

		match part.mesh_type:
			MeshType.BOX:
				var box_shape = BoxShape3D.new()
				box_shape.size = part.size
				collision_shape.shape = box_shape

			MeshType.CYLINDER, MeshType.CONE:
				var cylinder_shape = CylinderShape3D.new()
				cylinder_shape.radius = part.size.x
				cylinder_shape.height = part.size.y
				collision_shape.shape = cylinder_shape

			MeshType.SPHERE:
				var sphere_shape = SphereShape3D.new()
				sphere_shape.radius = part.size.x
				collision_shape.shape = sphere_shape

		static_body.add_child(collision_shape)
		mesh_instance.add_child(static_body)

		# Track roof parts
		if part.is_roof:
			roof_parts.append(mesh_instance)
			# Store original transparency (from material)
			var mat = mesh_instance.material_override
			if mat is StandardMaterial3D:
				original_roof_transparency.append(mat.albedo_color.a)
			else:
				original_roof_transparency.append(1.0)

		add_child(mesh_instance)

## Update roof visibility based on distance from camera/player
## distance: distance from structure to camera/player
## fade_start: distance where fading begins (full opacity)
## fade_end: distance where fading ends (full transparency)
func update_roof_visibility(distance: float, fade_start: float = 5.0, fade_end: float = 2.0):
	if roof_parts.is_empty():
		return

	# Calculate alpha based on distance (fade_end is closer than fade_start)
	var alpha: float = 1.0
	if distance <= fade_end:
		alpha = 0.0  # Fully transparent when very close
	elif distance <= fade_start:
		# Linear interpolation between fade_end and fade_start
		alpha = (distance - fade_end) / (fade_start - fade_end)
	# else: alpha = 1.0 (fully opaque when far)

	# Apply alpha to all roof parts
	for i in range(roof_parts.size()):
		var roof_mesh = roof_parts[i]
		var mat = roof_mesh.material_override

		if mat is StandardMaterial3D:
			# Create material copy if it's shared (to avoid affecting other structures)
			if mat.resource_local_to_scene == false:
				mat = mat.duplicate()
				roof_mesh.material_override = mat
				mat.resource_local_to_scene = true

			# Enable transparency
			if alpha < 1.0:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

			# Apply alpha while preserving original transparency
			var original_alpha = original_roof_transparency[i] if i < original_roof_transparency.size() else 1.0
			var new_color = mat.albedo_color
			new_color.a = original_alpha * alpha
			mat.albedo_color = new_color

## Helper to reset roof to full opacity
func reset_roof_visibility():
	update_roof_visibility(999.0)  # Large distance = full opacity
