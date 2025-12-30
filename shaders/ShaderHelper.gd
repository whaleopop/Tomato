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
		"tile_color": Color(0.35, 0.7, 0.3),
		"edge_color": Color(0.2, 0.4, 0.15)
	},
	HexTile.BiomeType.FOREST: {
		"tile_color": Color(0.2, 0.5, 0.2),
		"edge_color": Color(0.1, 0.3, 0.1)
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
	}
}

## Create a hex tile material with shader
static func create_hex_material(biome: HexTile.BiomeType, height: float = 0.0) -> Material:
	var shader = load(HEX_TILE_SHADER)
	if not shader:
		return _create_fallback_hex_material(biome)

	var material = ShaderMaterial.new()
	material.shader = shader

	var colors = biome_colors.get(biome, biome_colors[HexTile.BiomeType.GRASS])
	material.set_shader_parameter("tile_color", colors["tile_color"])
	material.set_shader_parameter("edge_color", colors["edge_color"])
	material.set_shader_parameter("tile_height", height)

	return material

## Create a water material with animated shader
static func create_water_material() -> Material:
	var shader = load(WATER_SHADER)
	if not shader:
		return _create_fallback_water_material()

	var material = ShaderMaterial.new()
	material.shader = shader

	return material

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
