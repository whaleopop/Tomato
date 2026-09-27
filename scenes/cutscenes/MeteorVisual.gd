## Procedural meteor visual with fire trail and glowing effects
extends Node3D
class_name MeteorVisual

# Meteor parameters
@export var meteor_radius: float = 3.0
@export var num_floating_rocks: int = 12
@export var rock_orbit_radius: float = 4.5
@export var rock_orbit_speed: float = 1.5

# Node references
var main_sphere: MeshInstance3D = null
var floating_rocks: Array[MeshInstance3D] = []
var fire_trail: GPUParticles3D = null
var smoke_trail: GPUParticles3D = null
var glow_light: OmniLight3D = null
var ember_particles: GPUParticles3D = null

# Animation
var time_elapsed: float = 0.0
var rock_angles: Array[float] = []
var rock_heights: Array[float] = []

func _ready():
	_generate_main_sphere()
	_generate_floating_rocks()
	_setup_fire_trail()
	_setup_smoke_trail()
	_setup_ember_particles()
	_setup_glow_light()

func _process(delta: float):
	time_elapsed += delta
	_animate_rocks(delta)
	_animate_glow(delta)

func _generate_main_sphere():
	main_sphere = MeshInstance3D.new()
	main_sphere.name = "MainSphere"

	# Create rocky sphere mesh
	var sphere = SphereMesh.new()
	sphere.radius = meteor_radius
	sphere.height = meteor_radius * 2
	sphere.radial_segments = 32
	sphere.rings = 16
	main_sphere.mesh = sphere

	# Rocky material with emissive cracks
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.25, 0.2)
	material.roughness = 0.9
	material.metallic = 0.1

	# Emissive for hot glow
	material.emission_enabled = true
	material.emission = Color(1.0, 0.4, 0.1)
	material.emission_energy_multiplier = 0.5

	main_sphere.material_override = material
	add_child(main_sphere)

	# Add surface details (smaller rocks attached)
	_add_surface_rocks()

func _add_surface_rocks():
	for i in range(20):
		var rock = MeshInstance3D.new()

		# Random rock shape using box with random scaling
		var mesh = BoxMesh.new()
		var size = randf_range(0.3, 0.8)
		mesh.size = Vector3(size, size * randf_range(0.5, 1.5), size * randf_range(0.5, 1.5))
		rock.mesh = mesh

		# Position on sphere surface
		var theta = randf() * TAU
		var phi = randf() * PI
		var pos = Vector3(
			sin(phi) * cos(theta),
			cos(phi),
			sin(phi) * sin(theta)
		) * meteor_radius * 0.95

		rock.position = pos
		rock.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

		# Same rocky material
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.35, 0.28, 0.22)
		material.roughness = 0.95
		rock.material_override = material

		main_sphere.add_child(rock)

func _generate_floating_rocks():
	for i in range(num_floating_rocks):
		var rock = MeshInstance3D.new()

		# Create irregular rock mesh
		var mesh = BoxMesh.new()
		var base_size = randf_range(0.4, 1.0)
		mesh.size = Vector3(
			base_size * randf_range(0.7, 1.3),
			base_size * randf_range(0.5, 1.5),
			base_size * randf_range(0.7, 1.3)
		)
		rock.mesh = mesh

		# Rocky material with slight glow
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.4, 0.32, 0.25)
		material.roughness = 0.85
		material.emission_enabled = true
		material.emission = Color(1.0, 0.3, 0.05)
		material.emission_energy_multiplier = randf_range(0.1, 0.4)
		rock.material_override = material

		# Random rotation
		rock.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

		add_child(rock)
		floating_rocks.append(rock)

		# Store orbital parameters
		rock_angles.append(randf() * TAU)
		rock_heights.append(randf_range(-1.5, 1.5))

func _animate_rocks(delta: float):
	for i in range(floating_rocks.size()):
		var rock = floating_rocks[i]
		if not is_instance_valid(rock):
			continue

		# Update angle
		rock_angles[i] += delta * rock_orbit_speed * randf_range(0.8, 1.2)

		# Orbital position with bobbing
		var angle = rock_angles[i]
		var height = rock_heights[i] + sin(time_elapsed * 2.0 + i) * 0.3
		var radius = rock_orbit_radius + sin(time_elapsed * 1.5 + i * 0.5) * 0.5

		rock.position = Vector3(
			cos(angle) * radius,
			height,
			sin(angle) * radius
		)

		# Tumble rotation
		rock.rotate_x(delta * randf_range(0.5, 1.5))
		rock.rotate_y(delta * randf_range(0.3, 1.0))

func _setup_fire_trail():
	fire_trail = GPUParticles3D.new()
	fire_trail.name = "FireTrail"
	fire_trail.amount = 300
	fire_trail.lifetime = 1.2
	fire_trail.explosiveness = 0.0
	fire_trail.randomness = 0.4
	fire_trail.local_coords = false

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = meteor_radius * 0.8
	material.direction = Vector3(0, 1, -1).normalized()
	material.spread = 25.0
	material.initial_velocity_min = 8.0
	material.initial_velocity_max = 15.0
	material.gravity = Vector3(0, 5, -3)
	material.damping_min = 0.5
	material.damping_max = 1.5

	material.scale_min = 0.3
	material.scale_max = 0.8

	# Color gradient: hot core to cool edge
	var gradient = GradientTexture1D.new()
	var grad = Gradient.new()
	grad.add_point(0.0, Color(1.0, 1.0, 0.8, 1.0))   # White hot
	grad.add_point(0.2, Color(1.0, 0.8, 0.2, 0.9))   # Yellow
	grad.add_point(0.5, Color(1.0, 0.4, 0.1, 0.7))   # Orange
	grad.add_point(0.8, Color(0.8, 0.2, 0.05, 0.4))  # Red
	grad.add_point(1.0, Color(0.3, 0.1, 0.05, 0.0))  # Dark red, fade out
	gradient.gradient = grad
	material.color_ramp = gradient

	fire_trail.process_material = material

	# Fire particle mesh (billboard quad)
	var mesh = QuadMesh.new()
	mesh.size = Vector2(1.5, 1.5)
	mesh.material = LandingImpact.soft_particle_material(true)  # glowing, soft edges
	fire_trail.draw_pass_1 = mesh

	# Position behind meteor
	fire_trail.position = Vector3(0, 0, meteor_radius)

	add_child(fire_trail)

func _setup_smoke_trail():
	smoke_trail = GPUParticles3D.new()
	smoke_trail.name = "SmokeTrail"
	smoke_trail.amount = 100
	smoke_trail.lifetime = 2.5
	smoke_trail.explosiveness = 0.0
	smoke_trail.randomness = 0.5
	smoke_trail.local_coords = false

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = meteor_radius * 0.5
	material.direction = Vector3(0, 1, -1).normalized()
	material.spread = 35.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0
	material.gravity = Vector3(0, 2, -1)
	material.damping_min = 1.0
	material.damping_max = 2.0

	material.scale_min = 0.8
	material.scale_max = 2.0

	# Smoke color gradient
	var gradient = GradientTexture1D.new()
	var grad = Gradient.new()
	grad.add_point(0.0, Color(0.3, 0.25, 0.2, 0.6))
	grad.add_point(0.5, Color(0.2, 0.18, 0.15, 0.4))
	grad.add_point(1.0, Color(0.15, 0.12, 0.1, 0.0))
	gradient.gradient = grad
	material.color_ramp = gradient

	smoke_trail.process_material = material

	var mesh = QuadMesh.new()
	mesh.size = Vector2(3.0, 3.0)
	mesh.material = LandingImpact.soft_particle_material(false)
	smoke_trail.draw_pass_1 = mesh

	smoke_trail.position = Vector3(0, 0, meteor_radius * 1.5)

	add_child(smoke_trail)

func _setup_ember_particles():
	ember_particles = GPUParticles3D.new()
	ember_particles.name = "EmberParticles"
	ember_particles.amount = 50
	ember_particles.lifetime = 0.8
	ember_particles.explosiveness = 0.0
	ember_particles.randomness = 0.6
	ember_particles.local_coords = false

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = meteor_radius
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 12.0
	material.gravity = Vector3(0, -5, 0)

	material.scale_min = 0.05
	material.scale_max = 0.15
	material.color = Color(1.0, 0.6, 0.2)

	ember_particles.process_material = material

	var mesh = SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	var ember_mat = StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.vertex_color_use_as_albedo = true
	mesh.material = ember_mat
	ember_particles.draw_pass_1 = mesh

	add_child(ember_particles)

func _setup_glow_light():
	glow_light = OmniLight3D.new()
	glow_light.name = "GlowLight"
	glow_light.light_color = Color(1.0, 0.5, 0.2)
	glow_light.light_energy = 3.0
	glow_light.omni_range = 30.0
	glow_light.omni_attenuation = 1.5
	glow_light.shadow_enabled = false
	add_child(glow_light)

func _animate_glow(delta: float):
	if glow_light:
		# Pulsing glow
		var pulse = 1.0 + sin(time_elapsed * 8.0) * 0.2
		glow_light.light_energy = 3.0 * pulse

		# Flickering
		glow_light.light_energy += randf_range(-0.3, 0.3)

	# Main sphere emission pulse
	if main_sphere and main_sphere.material_override:
		var mat = main_sphere.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 0.5 + sin(time_elapsed * 5.0) * 0.2

# Update trail direction based on velocity
func update_trail_direction(velocity: Vector3):
	if velocity.length() < 0.1:
		return

	var direction = -velocity.normalized()

	if fire_trail and fire_trail.process_material:
		var mat = fire_trail.process_material as ParticleProcessMaterial
		if mat:
			mat.direction = direction
			mat.gravity = direction * 5.0 + Vector3(0, 2, 0)

	if smoke_trail and smoke_trail.process_material:
		var mat = smoke_trail.process_material as ParticleProcessMaterial
		if mat:
			mat.direction = direction
			mat.gravity = direction * 2.0 + Vector3(0, 1, 0)

# Called when meteor explodes
func explode():
	# Stop all trails
	if fire_trail:
		fire_trail.emitting = false
	if smoke_trail:
		smoke_trail.emitting = false
	if ember_particles:
		ember_particles.emitting = false

	# Flash the glow light
	if glow_light:
		var tween = create_tween()
		tween.tween_property(glow_light, "light_energy", 20.0, 0.1)
		tween.tween_property(glow_light, "light_energy", 0.0, 0.5)
		tween.tween_callback(glow_light.queue_free)

	# Hide visual but keep node for reference
	if main_sphere:
		main_sphere.visible = false

	for rock in floating_rocks:
		if is_instance_valid(rock):
			rock.visible = false
