## Explosion visual effects for meteor destruction
extends Node3D
class_name ExplosionFX

# Explosion parameters
@export var explosion_radius: float = 15.0
@export var flash_duration: float = 0.3
@export var debris_count: int = 30
@export var shockwave_speed: float = 80.0

# Node references
var main_flash: GPUParticles3D = null
var debris_particles: GPUParticles3D = null
var spark_particles: GPUParticles3D = null
var shockwave_ring: MeshInstance3D = null
var explosion_light: OmniLight3D = null

var has_exploded: bool = false

func _ready():
	visible = false

func explode():
	if has_exploded:
		return

	has_exploded = true
	visible = true

	_create_main_flash()
	_create_debris()
	_create_sparks()
	_create_shockwave()
	_create_explosion_light()

	# Screen shake
	var screen_effects = get_node_or_null("/root/ScreenEffects")
	if screen_effects and screen_effects.has_method("shake"):
		screen_effects.shake(1.5, 0.8)

func _create_main_flash():
	main_flash = GPUParticles3D.new()
	main_flash.amount = 150
	main_flash.lifetime = 0.6
	main_flash.one_shot = true
	main_flash.explosiveness = 1.0
	main_flash.randomness = 0.3

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 2.0
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 25.0
	material.initial_velocity_max = 50.0
	material.gravity = Vector3(0, -10, 0)
	material.damping_min = 2.0
	material.damping_max = 5.0

	material.scale_min = 0.5
	material.scale_max = 2.0

	# Bright fire colors
	var gradient = GradientTexture1D.new()
	var grad = Gradient.new()
	grad.add_point(0.0, Color(1.0, 1.0, 0.9, 1.0))
	grad.add_point(0.2, Color(1.0, 0.9, 0.5, 0.9))
	grad.add_point(0.5, Color(1.0, 0.5, 0.1, 0.7))
	grad.add_point(0.8, Color(0.8, 0.2, 0.05, 0.3))
	grad.add_point(1.0, Color(0.2, 0.05, 0.02, 0.0))
	gradient.gradient = grad
	material.color_ramp = gradient

	main_flash.process_material = material

	var mesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	main_flash.draw_pass_1 = mesh

	add_child(main_flash)
	main_flash.emitting = true

func _create_debris():
	debris_particles = GPUParticles3D.new()
	debris_particles.amount = debris_count
	debris_particles.lifetime = 3.0
	debris_particles.one_shot = true
	debris_particles.explosiveness = 0.9
	debris_particles.randomness = 0.5

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 3.0
	material.direction = Vector3(0, 1, 0)
	material.spread = 180.0
	material.initial_velocity_min = 15.0
	material.initial_velocity_max = 35.0
	material.gravity = Vector3(0, -20, 0)
	material.angular_velocity_min = -720.0
	material.angular_velocity_max = 720.0

	material.scale_min = 0.3
	material.scale_max = 1.2

	# Dark rock colors with slight glow
	var gradient = GradientTexture1D.new()
	var grad = Gradient.new()
	grad.add_point(0.0, Color(0.6, 0.4, 0.3, 1.0))
	grad.add_point(0.3, Color(0.4, 0.3, 0.25, 1.0))
	grad.add_point(1.0, Color(0.3, 0.2, 0.15, 1.0))
	gradient.gradient = grad
	material.color_ramp = gradient

	debris_particles.process_material = material

	# Use box mesh for debris
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.8, 0.6, 0.7)
	debris_particles.draw_pass_1 = mesh

	add_child(debris_particles)
	debris_particles.emitting = true

func _create_sparks():
	spark_particles = GPUParticles3D.new()
	spark_particles.amount = 80
	spark_particles.lifetime = 1.0
	spark_particles.one_shot = true
	spark_particles.explosiveness = 1.0
	spark_particles.randomness = 0.4

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 30.0
	material.initial_velocity_max = 60.0
	material.gravity = Vector3(0, -15, 0)
	material.damping_min = 3.0
	material.damping_max = 6.0

	material.scale_min = 0.05
	material.scale_max = 0.15

	# Bright spark colors
	var gradient = GradientTexture1D.new()
	var grad = Gradient.new()
	grad.add_point(0.0, Color(1.0, 1.0, 0.8, 1.0))
	grad.add_point(0.3, Color(1.0, 0.8, 0.4, 0.8))
	grad.add_point(0.7, Color(1.0, 0.5, 0.2, 0.5))
	grad.add_point(1.0, Color(0.8, 0.3, 0.1, 0.0))
	gradient.gradient = grad
	material.color_ramp = gradient

	spark_particles.process_material = material

	var mesh = SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	spark_particles.draw_pass_1 = mesh

	add_child(spark_particles)
	spark_particles.emitting = true

func _create_shockwave():
	shockwave_ring = MeshInstance3D.new()

	var torus = TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.2
	torus.rings = 32
	torus.ring_segments = 16
	shockwave_ring.mesh = torus

	# Transparent, glowing material
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.8, 0.5, 0.8)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.6, 0.3)
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shockwave_ring.material_override = material

	# Rotate to be horizontal
	shockwave_ring.rotation.x = PI / 2
	shockwave_ring.scale = Vector3(0.1, 0.1, 0.1)

	add_child(shockwave_ring)

	# Animate shockwave expansion
	var tween = create_tween()
	tween.set_parallel(true)

	# Scale up
	tween.tween_property(shockwave_ring, "scale", Vector3(explosion_radius, explosion_radius, 1.0), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)

	# Fade out
	tween.tween_property(material, "albedo_color:a", 0.0, 0.8)
	tween.tween_property(material, "emission_energy_multiplier", 0.0, 0.8)

	tween.chain().tween_callback(shockwave_ring.queue_free)

func _create_explosion_light():
	explosion_light = OmniLight3D.new()
	explosion_light.light_color = Color(1.0, 0.7, 0.3)
	explosion_light.light_energy = 15.0
	explosion_light.omni_range = 50.0
	explosion_light.omni_attenuation = 1.0
	explosion_light.shadow_enabled = false

	add_child(explosion_light)

	# Animate light
	var tween = create_tween()
	tween.tween_property(explosion_light, "light_energy", 25.0, 0.1)
	tween.tween_property(explosion_light, "light_energy", 0.0, 1.0).set_ease(Tween.EASE_IN)
	tween.tween_callback(explosion_light.queue_free)

# Reset for reuse
func reset():
	has_exploded = false
	visible = false

	# Clean up any remaining particles
	for child in get_children():
		child.queue_free()
