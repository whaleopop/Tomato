## Helper class for creating and applying shaders
extends RefCounted
class_name ShaderHelper

# Shader paths
const HEX_TILE_SHADER = "res://shaders/hex_tile.gdshader"
const WATER_SHADER = "res://shaders/water.gdshader"
const OUTLINE_SHADER = "res://shaders/outline.gdshader"
const TOON_SHADER = "res://shaders/toon_character.gdshader"
const FORCE_FIELD_SHADER = "res://shaders/force_field.gdshader"

# Biome colors for hex tiles
static var biome_colors: Dictionary = {
	HexTile.BiomeType.GRASS: {
		"tile_color": Color(0.52, 0.74, 0.25),  # warm meadow green
		"edge_color": Color(0.3, 0.45, 0.14),
		"grassy": 1.0
	},
	HexTile.BiomeType.FOREST: {
		"tile_color": Color(0.27, 0.52, 0.21),
		"edge_color": Color(0.14, 0.3, 0.1),
		"grassy": 1.0
	},
	HexTile.BiomeType.DESERT: {
		"tile_color": Color(0.85, 0.75, 0.5),
		"edge_color": Color(0.6, 0.5, 0.35)
	},
	HexTile.BiomeType.ROCK: {
		"tile_color": Color(0.5, 0.48, 0.45),
		"edge_color": Color(0.35, 0.33, 0.3)
	},
	HexTile.BiomeType.WATER: {
		"tile_color": Color(0.2, 0.5, 0.85),
		"edge_color": Color(0.1, 0.3, 0.6)
	},
	HexTile.BiomeType.BEACH: {
		"tile_color": Color(0.88, 0.8, 0.58),
		"edge_color": Color(0.62, 0.54, 0.38)
	},
	HexTile.BiomeType.SWAMP: {
		"tile_color": Color(0.36, 0.46, 0.27),
		"edge_color": Color(0.2, 0.28, 0.16)
	},
	HexTile.BiomeType.MOUNTAIN: {
		"tile_color": Color(0.46, 0.44, 0.42),
		"edge_color": Color(0.3, 0.29, 0.27)
	},
	HexTile.BiomeType.MEADOW: {
		"tile_color": Color(0.5, 0.74, 0.36),
		"edge_color": Color(0.3, 0.45, 0.2),
		"grassy": 1.0
	},
	HexTile.BiomeType.FROST: {
		"tile_color": Color(0.7, 0.8, 0.88),
		"edge_color": Color(0.5, 0.62, 0.74),
		"gloss": 0.35
	},
	HexTile.BiomeType.TALL_GRASS: {
		"tile_color": Color(0.58, 0.66, 0.24),
		"edge_color": Color(0.36, 0.42, 0.14),
		"grassy": 1.0
	},
	HexTile.BiomeType.MUSHROOM: {
		"tile_color": Color(0.36, 0.32, 0.42),
		"edge_color": Color(0.22, 0.18, 0.28)
	},
	HexTile.BiomeType.THORNS: {
		"tile_color": Color(0.36, 0.3, 0.22),
		"edge_color": Color(0.22, 0.16, 0.12)
	}
}

# Shared materials: one per biome (the per-tile data - what's across each edge - comes in
# as instance uniforms, see HexTile.update_edges), so tiles batch and the lake is one surface
static var _hex_materials: Dictionary = {}
static var _water_material: ShaderMaterial = null

static func biome_color(biome: int) -> Color:
	return biome_colors.get(biome, biome_colors[HexTile.BiomeType.GRASS])["tile_color"]

## Create a hex tile material with shader (shared per biome)
static func create_hex_material(biome: HexTile.BiomeType, _height: float = 0.0) -> Material:
	if _hex_materials.has(biome):
		return _hex_materials[biome]
	var shader = load(HEX_TILE_SHADER)
	if not shader:
		return _create_fallback_hex_material(biome)

	var material = ShaderMaterial.new()
	material.shader = shader

	var colors = biome_colors.get(biome, biome_colors[HexTile.BiomeType.GRASS])
	material.set_shader_parameter("tile_color", colors["tile_color"])
	material.set_shader_parameter("edge_color", colors["edge_color"])
	material.set_shader_parameter("hex_radius", HexTile.HEX_RADIUS)
	material.set_shader_parameter("roughness", colors.get("gloss", 0.8))  # frost shines
	material.set_shader_parameter("grassy", colors.get("grassy", 0.0))     # sunlit grass look
	_hex_materials[biome] = material
	return material

## The water material (one for all water tiles; WaterRipples feeds it the ripples)
static func create_water_material() -> Material:
	if _water_material:
		return _water_material
	var shader = load(WATER_SHADER)
	if not shader:
		return _create_fallback_water_material()

	_water_material = ShaderMaterial.new()
	_water_material.shader = shader
	_water_material.set_shader_parameter("hex_radius", HexTile.HEX_RADIUS)
	return _water_material

## Create an outline material for object highlighting
static func create_outline_material(color: Color = Color.WHITE, width: float = 0.02, pulse: bool = false) -> ShaderMaterial:
	var shader = load(OUTLINE_SHADER)
	if not shader:
		return null

	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("outline_color", color)
	material.set_shader_parameter("outline_width", width)
	material.set_shader_parameter("pulse_speed", 2.0 if pulse else 0.0)

	return material

## Create a toon material for characters
static func create_toon_material(base_color: Color) -> Material:
	var shader = load(TOON_SHADER)
	if not shader:
		return _create_fallback_toon_material(base_color)

	var material = ShaderMaterial.new()
	material.shader = shader

	# Calculate shadow and highlight from base color
	var shadow = base_color.darkened(0.4)
	var highlight = base_color.lightened(0.3)

	material.set_shader_parameter("base_color", base_color)
	material.set_shader_parameter("shadow_color", shadow)
	material.set_shader_parameter("highlight_color", highlight)

	return material

## Create a force field material
static func create_force_field_material(color: Color = Color(0.2, 0.6, 1.0)) -> ShaderMaterial:
	var shader = load(FORCE_FIELD_SHADER)
	if not shader:
		return null

	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("field_color", color)

	return material

## Apply damage flash to a toon material
static func apply_damage_flash(material: ShaderMaterial, amount: float):
	if material and material.shader:
		material.set_shader_parameter("damage_flash", amount)

## Apply invincibility effect to a toon material
static func apply_invincibility(material: ShaderMaterial, enabled: bool):
	if material and material.shader:
		material.set_shader_parameter("invincibility", 1.0 if enabled else 0.0)

# Fallback materials when shaders fail to load
static func _create_fallback_hex_material(biome: HexTile.BiomeType) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	var colors = biome_colors.get(biome, biome_colors[HexTile.BiomeType.GRASS])
	material.albedo_color = colors["tile_color"]
	return material

static func _create_fallback_water_material() -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.5, 0.85)
	material.metallic = 0.3
	material.roughness = 0.1
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.7
	return material

static func _create_fallback_toon_material(base_color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = base_color
	return material
