## Static generator for procedural structure recipes
class_name BuildingGenerator

const ProceduralStructure = preload("res://world/objects/ProceduralStructure.gd")
const StructureMaterialLib = preload("res://world/objects/StructureMaterials.gd")

enum StructureType {
	SMALL_HOUSE,
	LARGE_HOUSE,
	TOWER,
	WAREHOUSE,
	TREE_OAK,
	TREE_PINE,
	FORTIFICATION,
	URBAN_BUILDING
}

## Generate structure parts based on type and optional seed for variation
static func generate(type: StructureType, variant_seed: int = 0) -> Array[ProceduralStructure.StructurePart]:
	var rng = RandomNumberGenerator.new()
	rng.seed = variant_seed

	match type:
		StructureType.SMALL_HOUSE:
			return _generate_small_house(rng)
		StructureType.LARGE_HOUSE:
			return _generate_large_house(rng)
		StructureType.TOWER:
			return _generate_tower(rng)
		StructureType.WAREHOUSE:
			return _generate_warehouse(rng)
		StructureType.TREE_OAK:
			return _generate_tree_oak(rng)
		StructureType.TREE_PINE:
			return _generate_tree_pine(rng)
		StructureType.FORTIFICATION:
			return _generate_fortification(rng)
		StructureType.URBAN_BUILDING:
			return _generate_urban_building(rng)

	return []

## Small house: walls + pyramid roof
static func _generate_small_house(rng: RandomNumberGenerator) -> Array[ProceduralStructure.StructurePart]:
	var parts: Array[ProceduralStructure.StructurePart] = []

	var wall_material = StructureMaterialLib.MaterialType.WOOD_LIGHT if rng.randf() > 0.5 else StructureMaterialLib.MaterialType.WOOD_DARK
	var roof_material = StructureMaterialLib.MaterialType.WOOD_DARK

	var width = rng.randf_range(3.0, 4.5)
	var depth = rng.randf_range(3.0, 4.5)
	var wall_height = rng.randf_range(2.5, 3.5)

	# Walls (main box)
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.BOX,
		Vector3(width, wall_height, depth),
		Vector3(0, wall_height / 2, 0),
		Vector3.ZERO,
		wall_material,
		false
	))

	# Roof (pyramid = 4 rotated boxes or cone)
	var roof_height = rng.randf_range(1.5, 2.5)
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.CONE,
		Vector3(max(width, depth) * 0.8, roof_height, 0),
		Vector3(0, wall_height + roof_height / 2, 0),
		Vector3.ZERO,
		roof_material,
		true  # is_roof
	))

	# Door (small box cutout simulation - darker material)
	var door_width = 0.8
	var door_height = 1.8
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.BOX,
		Vector3(door_width, door_height, 0.1),
		Vector3(0, door_height / 2, depth / 2 + 0.05),
		Vector3.ZERO,
		StructureMaterialLib.MaterialType.WOOD_DARK,
		false
	))

	return parts

## Large house: multiple rooms
static func _generate_large_house(rng: RandomNumberGenerator) -> Array[ProceduralStructure.StructurePart]:
	var parts: Array[ProceduralStructure.StructurePart] = []

	var wall_material = StructureMaterialLib.MaterialType.STONE_GRAY
	var roof_material = StructureMaterialLib.MaterialType.WOOD_DARK

	var width = rng.randf_range(6.0, 8.0)
	var depth = rng.randf_range(5.0, 7.0)
	var wall_height = rng.randf_range(3.0, 4.0)

	# Main building
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.BOX,
		Vector3(width, wall_height, depth),
		Vector3(0, wall_height / 2, 0),
		Vector3.ZERO,
		wall_material,
		false
	))

	# Roof
	var roof_height = rng.randf_range(2.0, 3.0)
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.CONE,
		Vector3(max(width, depth) * 0.9, roof_height, 0),
		Vector3(0, wall_height + roof_height / 2, 0),
		Vector3.ZERO,
		roof_material,
		true
	))

	# Extension (smaller attached room)
	var ext_width = rng.randf_range(2.5, 3.5)
	var ext_depth = rng.randf_range(2.5, 3.5)
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.BOX,
		Vector3(ext_width, wall_height * 0.8, ext_depth),
		Vector3(width / 2 + ext_width / 2, wall_height * 0.4, 0),
		Vector3.ZERO,
		wall_material,
		false
	))

	return parts

## Tower: tall cylindrical structure
static func _generate_tower(rng: RandomNumberGenerator) -> Array[ProceduralStructure.StructurePart]:
	var parts: Array[ProceduralStructure.StructurePart] = []

	var radius = rng.randf_range(2.0, 3.0)
	var height = rng.randf_range(8.0, 12.0)
	var wall_material = StructureMaterialLib.MaterialType.STONE_GRAY

	# Main tower body
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.CYLINDER,
		Vector3(radius, height, 0),
		Vector3(0, height / 2, 0),
		Vector3.ZERO,
		wall_material,
		false
	))

	# Roof (cone)
	var roof_height = rng.randf_range(2.0, 3.0)
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.CONE,
		Vector3(radius * 1.2, roof_height, 0),
		Vector3(0, height + roof_height / 2, 0),
		Vector3.ZERO,
		StructureMaterialLib.MaterialType.METAL_RUSTY,
		true
	))

	# Battlements (small boxes around top)
	var battlement_count = 8
	for i in range(battlement_count):
		var angle = (i / float(battlement_count)) * TAU
		var battlement_pos = Vector3(
			cos(angle) * (radius + 0.3),
			height + 0.3,
			sin(angle) * (radius + 0.3)
		)
		parts.append(ProceduralStructure.StructurePart.new(
			ProceduralStructure.MeshType.BOX,
			Vector3(0.5, 0.8, 0.5),
			battlement_pos,
			Vector3.ZERO,
			wall_material,
			false
		))

	return parts

## Warehouse: large rectangular building
static func _generate_warehouse(rng: RandomNumberGenerator) -> Array[ProceduralStructure.StructurePart]:
	var parts: Array[ProceduralStructure.StructurePart] = []

	var width = rng.randf_range(8.0, 12.0)
	var depth = rng.randf_range(6.0, 9.0)
	var height = rng.randf_range(4.0, 6.0)

	var wall_material = StructureMaterialLib.MaterialType.METAL_RUSTY

	# Main building
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.BOX,
		Vector3(width, height, depth),
		Vector3(0, height / 2, 0),
		Vector3.ZERO,
		wall_material,
		false
	))

	# Flat roof (slightly larger than building)
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.BOX,
		Vector3(width + 0.4, 0.3, depth + 0.4),
		Vector3(0, height + 0.15, 0),
		Vector3.ZERO,
		StructureMaterialLib.MaterialType.METAL_CLEAN,
		true
	))

	# Large door
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.BOX,
		Vector3(2.5, 3.0, 0.1),
		Vector3(0, 1.5, depth / 2 + 0.05),
		Vector3.ZERO,
		StructureMaterialLib.MaterialType.METAL_CLEAN,
		false
	))

	return parts

## Oak tree: sphere crown + cylinder trunk
static func _generate_tree_oak(rng: RandomNumberGenerator) -> Array[ProceduralStructure.StructurePart]:
	var parts: Array[ProceduralStructure.StructurePart] = []

	var trunk_height = rng.randf_range(2.5, 4.0)
	var trunk_radius = rng.randf_range(0.3, 0.5)
	var crown_radius = rng.randf_range(2.0, 3.0)

	# Trunk
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.CYLINDER,
		Vector3(trunk_radius, trunk_height, 0),
		Vector3(0, trunk_height / 2, 0),
		Vector3.ZERO,
		StructureMaterialLib.MaterialType.WOOD_DARK,
		false
	))

	# Crown (sphere)
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.SPHERE,
		Vector3(crown_radius, crown_radius * 2, 0),
		Vector3(0, trunk_height + crown_radius * 0.7, 0),
		Vector3.ZERO,
		StructureMaterialLib.MaterialType.GREEN_FOLIAGE,
		false
	))

	# Additional smaller crown clusters for variation
	var cluster_count = rng.randi_range(2, 4)
	for i in range(cluster_count):
		var angle = rng.randf() * TAU
		var offset_radius = rng.randf_range(crown_radius * 0.4, crown_radius * 0.6)
		var cluster_size = rng.randf_range(crown_radius * 0.4, crown_radius * 0.6)

		parts.append(ProceduralStructure.StructurePart.new(
			ProceduralStructure.MeshType.SPHERE,
			Vector3(cluster_size, cluster_size * 2, 0),
			Vector3(
				cos(angle) * offset_radius,
				trunk_height + crown_radius * 0.5 + rng.randf_range(-0.5, 0.5),
				sin(angle) * offset_radius
			),
			Vector3.ZERO,
			StructureMaterialLib.MaterialType.GREEN_FOLIAGE,
			false
		))

	return parts

## Pine tree: cone crown + cylinder trunk
static func _generate_tree_pine(rng: RandomNumberGenerator) -> Array[ProceduralStructure.StructurePart]:
	var parts: Array[ProceduralStructure.StructurePart] = []

	var trunk_height = rng.randf_range(3.0, 5.0)
	var trunk_radius = rng.randf_range(0.25, 0.4)
	var crown_radius = rng.randf_range(1.5, 2.5)
	var crown_height = rng.randf_range(4.0, 6.0)

	# Trunk
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.CYLINDER,
		Vector3(trunk_radius, trunk_height, 0),
		Vector3(0, trunk_height / 2, 0),
		Vector3.ZERO,
		StructureMaterialLib.MaterialType.WOOD_DARK,
		false
	))

	# Crown (cone)
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.CONE,
		Vector3(crown_radius, crown_height, 0),
		Vector3(0, trunk_height + crown_height / 2, 0),
		Vector3.ZERO,
		StructureMaterialLib.MaterialType.GREEN_FOLIAGE,
		false
	))

	# Additional cone layers for fuller look
	var layer_count = rng.randi_range(1, 3)
	for i in range(layer_count):
		var layer_y = trunk_height + (crown_height * 0.3) * (i + 1)
		var layer_radius = crown_radius * (1.0 - (i * 0.2))

		parts.append(ProceduralStructure.StructurePart.new(
			ProceduralStructure.MeshType.CONE,
			Vector3(layer_radius, crown_height * 0.4, 0),
			Vector3(0, layer_y, 0),
			Vector3.ZERO,
			StructureMaterialLib.MaterialType.GREEN_FOLIAGE,
			false
		))

	return parts

## Fortification: walls with towers
static func _generate_fortification(rng: RandomNumberGenerator) -> Array[ProceduralStructure.StructurePart]:
	var parts: Array[ProceduralStructure.StructurePart] = []

	var wall_length = rng.randf_range(6.0, 10.0)
	var wall_height = rng.randf_range(3.0, 4.5)
	var wall_thickness = rng.randf_range(0.8, 1.2)

	var wall_material = StructureMaterialLib.MaterialType.STONE_GRAY

	# Main wall
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.BOX,
		Vector3(wall_length, wall_height, wall_thickness),
		Vector3(0, wall_height / 2, 0),
		Vector3.ZERO,
		wall_material,
		false
	))

	# Corner towers (2 towers at ends)
	for side in [-1, 1]:
		var tower_radius = rng.randf_range(1.0, 1.5)
		var tower_height = wall_height + rng.randf_range(1.5, 2.5)

		parts.append(ProceduralStructure.StructurePart.new(
			ProceduralStructure.MeshType.CYLINDER,
			Vector3(tower_radius, tower_height, 0),
			Vector3(side * wall_length / 2, tower_height / 2, 0),
			Vector3.ZERO,
			wall_material,
			false
		))

		# Tower roof
		parts.append(ProceduralStructure.StructurePart.new(
			ProceduralStructure.MeshType.CONE,
			Vector3(tower_radius * 1.1, 1.5, 0),
			Vector3(side * wall_length / 2, tower_height + 0.75, 0),
			Vector3.ZERO,
			StructureMaterialLib.MaterialType.METAL_RUSTY,
			true
		))

	return parts

## Urban building: multi-story structure with windows
static func _generate_urban_building(rng: RandomNumberGenerator) -> Array[ProceduralStructure.StructurePart]:
	var parts: Array[ProceduralStructure.StructurePart] = []

	var width = rng.randf_range(5.0, 8.0)
	var depth = rng.randf_range(5.0, 8.0)
	var floors = rng.randi_range(2, 4)
	var floor_height = 3.0
	var total_height = floors * floor_height

	var wall_material = StructureMaterialLib.MaterialType.STONE_BROWN

	# Main building
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.BOX,
		Vector3(width, total_height, depth),
		Vector3(0, total_height / 2, 0),
		Vector3.ZERO,
		wall_material,
		false
	))

	# Windows (simplified as small boxes)
	var windows_per_floor = 3
	for floor in range(floors):
		for window_idx in range(windows_per_floor):
			var window_y = (floor + 0.5) * floor_height
			var window_x = (window_idx - 1) * (width / 3)

			# Front windows
			parts.append(ProceduralStructure.StructurePart.new(
				ProceduralStructure.MeshType.BOX,
				Vector3(0.8, 1.2, 0.05),
				Vector3(window_x, window_y, depth / 2 + 0.025),
				Vector3.ZERO,
				StructureMaterialLib.MaterialType.GLASS,
				false
			))

	# Flat roof
	parts.append(ProceduralStructure.StructurePart.new(
		ProceduralStructure.MeshType.BOX,
		Vector3(width + 0.3, 0.3, depth + 0.3),
		Vector3(0, total_height + 0.15, 0),
		Vector3.ZERO,
		StructureMaterialLib.MaterialType.STONE_GRAY,
		true
	))

	return parts
