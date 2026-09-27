## Hero landing / spawn impact: expanding shockwave ring, dust puff, debris chips and a flash.
## Used by the spawn cutscene and when a player appears in the match.
extends Node3D
class_name LandingImpact

var tint: Color = Color(1.0, 0.85, 0.6)
var power: float = 1.0

static func create_at(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.85, 0.6), strength: float = 1.0) -> LandingImpact:
	var fx = LandingImpact.new()
	fx.tint = color
	fx.power = strength
	parent.add_child(fx)
	fx.global_position = pos
	return fx

## Soft round billboard for particles (a bare QuadMesh renders as an opaque white square)
static func soft_particle_material(additive: bool = false) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var tex = GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	mat.albedo_texture = tex
	return mat

func _ready():
	_ring()
	_dust()
	_debris()
	_flash()
	get_tree().create_timer(2.5).timeout.connect(queue_free)

func _ring():
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 48
	ring.mesh = torus
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(tint, 0.9)
	ring.material_override = mat
	ring.position.y = 0.08
	ring.scale = Vector3(0.3, 0.2, 0.3)
	add_child(ring)
	var size = 3.2 * power
	var tween = create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3(size, 0.15, size), 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.55).set_ease(Tween.EASE_IN)

func _dust():
	var dust = GPUParticles3D.new()
	dust.amount = int(36 * power)
	dust.lifetime = 1.1
	dust.one_shot = true
	dust.explosiveness = 0.95
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.6
	pm.emission_ring_inner_radius = 0.2
	pm.emission_ring_height = 0.1
	pm.direction = Vector3(0, 0.35, 0)
	pm.spread = 80.0
	pm.flatness = 0.6
	pm.initial_velocity_min = 3.0 * power
	pm.initial_velocity_max = 6.0 * power
	pm.damping_min = 4.0
	pm.damping_max = 6.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var ramp = Gradient.new()
	ramp.set_color(0, Color(0.92, 0.86, 0.76, 0.75))
	ramp.set_color(1, Color(0.8, 0.74, 0.66, 0.0))
	var ramp_tex = GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	var curve = Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.0))
	var curve_tex = CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	dust.process_material = pm
	var quad = QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	quad.material = soft_particle_material()
	dust.draw_pass_1 = quad
	dust.position.y = 0.15
	add_child(dust)
	dust.emitting = true

func _debris():
	var chips = GPUParticles3D.new()
	chips.amount = int(14 * power)
	chips.lifetime = 0.9
	chips.one_shot = true
	chips.explosiveness = 1.0
	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 4.0 * power
	pm.initial_velocity_max = 8.0 * power
	pm.gravity = Vector3(0, -22, 0)
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 0.06
	pm.scale_max = 0.14
	pm.color = Color(0.45, 0.62, 0.32)
	chips.process_material = pm
	var box = BoxMesh.new()
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	chips.draw_pass_1 = box
	chips.position.y = 0.2
	add_child(chips)
	chips.emitting = true

func _flash():
	var light = OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 5.0 * power
	light.omni_range = 7.0 * power
	light.position.y = 0.8
	add_child(light)
	create_tween().tween_property(light, "light_energy", 0.0, 0.45)
