## Библиотека материалов для биомов (батчинг материалов)
## Вместо создания 30,000 уникальных материалов, переиспользуем 9 общих
extends Node
class_name BiomeMaterialLibrary

var materials: Dictionary = {}

# Singleton instance
static var instance: BiomeMaterialLibrary = null

func _init():
	if instance == null:
		instance = self
	_create_materials()

static func get_instance() -> BiomeMaterialLibrary:
	if instance == null:
		instance = BiomeMaterialLibrary.new()
	return instance

func _create_materials():
	# GRASS - зелёная трава
	var grass = StandardMaterial3D.new()
	grass.albedo_color = Color(0.3, 0.7, 0.25)
	grass.roughness = 0.9
	materials[HexTile.BiomeType.GRASS] = grass

	# FOREST - тёмный зелёный лес
	var forest = StandardMaterial3D.new()
	forest.albedo_color = Color(0.15, 0.45, 0.15)
	forest.roughness = 0.95
	materials[HexTile.BiomeType.FOREST] = forest

	# DESERT - песчаная пустыня
	var desert = StandardMaterial3D.new()
	desert.albedo_color = Color(0.85, 0.75, 0.55)
	desert.roughness = 0.8
	materials[HexTile.BiomeType.DESERT] = desert

	# ROCK - серые камни
	var rock = StandardMaterial3D.new()
	rock.albedo_color = Color(0.45, 0.42, 0.4)
	rock.roughness = 0.9
	materials[HexTile.BiomeType.ROCK] = rock

	# WATER - глубокая вода
	var water = StandardMaterial3D.new()
	water.albedo_color = Color(0.15, 0.4, 0.75, 0.8)
	water.metallic = 0.4
	water.roughness = 0.05
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materials[HexTile.BiomeType.WATER] = water

	# SHALLOW_WATER - мелководье
	var shallow = StandardMaterial3D.new()
	shallow.albedo_color = Color(0.3, 0.55, 0.8, 0.6)
	shallow.metallic = 0.2
	shallow.roughness = 0.15
	shallow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materials[HexTile.BiomeType.SHALLOW_WATER] = shallow

	# SWAMP - болото
	var swamp = StandardMaterial3D.new()
	swamp.albedo_color = Color(0.25, 0.35, 0.2)
	swamp.roughness = 0.8
	materials[HexTile.BiomeType.SWAMP] = swamp

	# BEACH - песчаный пляж
	var beach = StandardMaterial3D.new()
	beach.albedo_color = Color(0.85, 0.8, 0.65)
	beach.roughness = 0.6
	materials[HexTile.BiomeType.BEACH] = beach

	# MOUNTAIN - горы (полупрозрачные)
	var mountain = StandardMaterial3D.new()
	mountain.albedo_color = Color(0.35, 0.32, 0.3, 0.7)
	mountain.roughness = 0.95
	mountain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materials[HexTile.BiomeType.MOUNTAIN] = mountain

	print("[BiomeMaterialLibrary] Created %d shared materials for biomes" % materials.size())

func get_material(biome_type: HexTile.BiomeType) -> Material:
	return materials.get(biome_type, materials[HexTile.BiomeType.GRASS])
