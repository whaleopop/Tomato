## Библиотека материалов для процедурных структур
extends Node
class_name StructureMaterials

enum MaterialType {
	WOOD_LIGHT,
	WOOD_DARK,
	STONE_GRAY,
	STONE_BROWN,
	METAL_RUSTY,
	METAL_CLEAN,
	GLASS,
	FABRIC_RED,
	FABRIC_BLUE,
	GREEN_FOLIAGE  # Для листвы деревьев
}

var materials: Dictionary = {}

# Singleton instance
static var instance: StructureMaterials = null

func _init():
	if instance == null:
		instance = self
	_create_materials()

static func get_instance() -> StructureMaterials:
	if instance == null:
		instance = StructureMaterials.new()
	return instance

func _create_materials():
	# Wood Light - светлое дерево
	var wood_light = StandardMaterial3D.new()
	wood_light.albedo_color = Color(0.7, 0.5, 0.3)
	wood_light.roughness = 0.8
	materials[MaterialType.WOOD_LIGHT] = wood_light

	# Wood Dark - тёмное дерево
	var wood_dark = StandardMaterial3D.new()
	wood_dark.albedo_color = Color(0.4, 0.25, 0.15)
	wood_dark.roughness = 0.85
	materials[MaterialType.WOOD_DARK] = wood_dark

	# Stone Gray - серый камень
	var stone_gray = StandardMaterial3D.new()
	stone_gray.albedo_color = Color(0.45, 0.45, 0.45)
	stone_gray.roughness = 0.95
	materials[MaterialType.STONE_GRAY] = stone_gray

	# Stone Brown - коричневый камень
	var stone_brown = StandardMaterial3D.new()
	stone_brown.albedo_color = Color(0.5, 0.4, 0.35)
	stone_brown.roughness = 0.9
	materials[MaterialType.STONE_BROWN] = stone_brown

	# Metal Rusty - ржавый металл
	var metal_rusty = StandardMaterial3D.new()
	metal_rusty.albedo_color = Color(0.45, 0.3, 0.2)
	metal_rusty.metallic = 0.6
	metal_rusty.roughness = 0.7
	materials[MaterialType.METAL_RUSTY] = metal_rusty

	# Metal Clean - чистый металл
	var metal_clean = StandardMaterial3D.new()
	metal_clean.albedo_color = Color(0.7, 0.7, 0.7)
	metal_clean.metallic = 0.9
	metal_clean.roughness = 0.3
	materials[MaterialType.METAL_CLEAN] = metal_clean

	# Glass - стекло с прозрачностью
	var glass = StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.7, 0.8, 0.3)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.1
	glass.roughness = 0.05
	glass.emission_enabled = true
	glass.emission = Color(0.5, 0.6, 0.7)
	glass.emission_energy_multiplier = 0.2
	materials[MaterialType.GLASS] = glass

	# Fabric Red - красная ткань
	var fabric_red = StandardMaterial3D.new()
	fabric_red.albedo_color = Color(0.8, 0.2, 0.2)
	fabric_red.roughness = 1.0
	materials[MaterialType.FABRIC_RED] = fabric_red

	# Fabric Blue - синяя ткань
	var fabric_blue = StandardMaterial3D.new()
	fabric_blue.albedo_color = Color(0.2, 0.3, 0.8)
	fabric_blue.roughness = 1.0
	materials[MaterialType.FABRIC_BLUE] = fabric_blue

	# Green Foliage - зелёная листва для деревьев
	var green_foliage = StandardMaterial3D.new()
	green_foliage.albedo_color = Color(0.2, 0.6, 0.2)
	green_foliage.roughness = 0.9
	materials[MaterialType.GREEN_FOLIAGE] = green_foliage

	print("[StructureMaterials] Created %d materials for procedural structures" % materials.size())

func get_material(type: MaterialType) -> Material:
	return materials.get(type, materials[MaterialType.WOOD_LIGHT])
