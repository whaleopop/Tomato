## Full-screen fog of war pass (child of the active camera). For every pixel it rebuilds the
## world position from the depth buffer and looks the hex up in VisibilitySystem.fog_texture,
## so the fog edge is soft and lies correctly on tiles, walls, containers and characters alike.
extends MeshInstance3D
class_name FogOverlay

func setup(system: VisibilitySystem):
	name = "FogOverlay"
	var quad = QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh = quad
	var mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/fog_overlay.gdshader")
	mat.set_shader_parameter("fog_map", system.fog_texture)
	mat.set_shader_parameter("fog_origin", float(system.fog_origin))
	mat.set_shader_parameter("fog_size", float(system.fog_size))
	mat.set_shader_parameter("hex_radius", HexTile.HEX_RADIUS)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	sorting_offset = 1000.0  # after every other transparent object: fog covers effects too
	position = Vector3(0, 0, -0.5)
