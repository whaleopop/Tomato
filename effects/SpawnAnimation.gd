## Spawn/teleport animation effect for players
extends Node3D
class_name SpawnAnimation

signal animation_complete

@export var animation_duration: float = 1.5
@export var beam_color: Color = Color(0.3, 0.6, 1.0)  # Blue teleport beam
@export var particles_color: Color = Color(0.5, 0.8, 1.0)

var target_entity: Node3D  # The entity being spawned
var beam_mesh: MeshInstance3D
var particles: GPUParticles3D
var glow_light: OmniLight3D
var ring_mesh: MeshInstance3D

## Play spawn animation on target entity
func play_spawn_animation(entity: Node3D):
	target_entity = entity
	global_position = entity.global_position

	# Create visual effects
	_create_beam()
	_create_particles()
	_create_glow_light()
	_create_ground_ring()

	# Animate
	await _animate_spawn()

	# Cleanup
	_cleanup()

	animation_complete.emit()

## Create teleport beam
func _create_beam():
	beam_mesh = MeshInstance3D.new()

	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.8
	cylinder.bottom_radius = 0.8
	cylinder.height = 10.0
	beam_mesh.mesh = cylinder

	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = beam_color
	material.albedo_color.a = 0.3
	material.emission_enabled = true
	material.emission = beam_color
	material.emission_energy_multiplier = 2.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from inside

	beam_mesh.material_override = material
	beam_mesh.position.y = 5.0  # Center at 5m height

	add_child(beam_mesh)

## Create particle effects
func _create_particles():
	particles = GPUParticles3D.new()
	particles.emitting = true
	particles.amount = 50
	particles.lifetime = 2.0
	particles.explosiveness = 0.0

	var process_mat = ParticleProcessMaterial.new()
	# Godot 4 has no cylinder emitter; a tall ring gives the same column of particles
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process_mat.emission_ring_axis = Vector3.UP
	process_mat.emission_ring_height = 6.0
	process_mat.emission_ring_radius = 0.7
	process_mat.emission_ring_inner_radius = 0.5

	process_mat.direction = Vector3.UP
	process_mat.spread = 10
	process_mat.initial_velocity_min = 1.5
	process_mat.initial_velocity_max = 3.0
	process_mat.gravity = Vector3(0, 2, 0)  # Upward pull
	process_mat.scale_min = 0.05
	process_mat.scale_max = 0.12

	# Color gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, particles_color)
	gradient.add_point(0.7, Color(particles_color.r, particles_color.g, particles_color.b, 0.5))
	gradient.add_point(1.0, Color(particles_color.r, particles_color.g, particles_color.b, 0.0))
	var gradient_tex = GradientTexture1D.new()
	gradient_tex.gradient = gradient
	process_mat.color_ramp = gradient_tex

	particles.process_material = process_mat

	# Draw pass
	var sphere = SphereMesh.new()
	sphere.radius = 0.08
	particles.draw_pass_1 = sphere

	particles.position.y = 0.5
	add_child(particles)

## Create glow light
func _create_glow_light():
	glow_light = OmniLight3D.new()
	glow_light.light_color = beam_color
	glow_light.light_energy = 0.0
	glow_light.omni_range = 5.0
	glow_light.position.y = 1.0

	add_child(glow_light)

## Create ground ring effect
func _create_ground_ring():
	ring_mesh = MeshInstance3D.new()

	var torus = TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.8
	ring_mesh.mesh = torus

	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = beam_color
	material.albedo_color.a = 0.7
	material.emission_enabled = true
	material.emission = beam_color
	material.emission_energy_multiplier = 3.0

	ring_mesh.material_override = material
	ring_mesh.position.y = 0.05
	ring_mesh.rotation.x = deg_to_rad(90)

	add_child(ring_mesh)

## Animate spawn sequence
func _animate_spawn():
	# Hide entity initially
	if target_entity and is_instance_valid(target_entity):
		target_entity.visible = false

	# Phase 1: Beam appears from top (0.5s)
	var tween1 = create_tween()
	tween1.set_parallel(true)

	# Beam descends
	tween1.tween_property(beam_mesh, "position:y", 0.0, 0.5).from(10.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Light fades in
	tween1.tween_property(glow_light, "light_energy", 4.0, 0.5).set_ease(Tween.EASE_OUT)

	# Ring expands
	tween1.tween_property(ring_mesh, "scale", Vector3(1.5, 1.5, 1.5), 0.5).from(Vector3(0.1, 0.1, 0.1)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	await tween1.finished

	# Phase 2: Entity materializes (0.6s)
	if target_entity and is_instance_valid(target_entity):
		target_entity.visible = true

		# Apply transparency shader if entity has mesh
		_apply_materialize_effect()

	var tween2 = create_tween()
	tween2.set_parallel(true)

	# Beam shrinks
	tween2.tween_property(beam_mesh.mesh, "top_radius", 0.1, 0.6).set_ease(Tween.EASE_IN)
	tween2.tween_property(beam_mesh.mesh, "bottom_radius", 0.1, 0.6).set_ease(Tween.EASE_IN)

	# Ring pulses
	tween2.tween_property(ring_mesh, "scale", Vector3(2.0, 2.0, 2.0), 0.3).set_ease(Tween.EASE_OUT)

	await tween2.finished

	# Phase 3: Beam disappears (0.4s)
	var tween3 = create_tween()
	tween3.set_parallel(true)

	tween3.tween_property(beam_mesh.material_override, "albedo_color:a", 0.0, 0.4)
	tween3.tween_property(glow_light, "light_energy", 0.0, 0.4)
	tween3.tween_property(ring_mesh, "scale", Vector3(3.0, 3.0, 3.0), 0.4)
	tween3.tween_property(ring_mesh.material_override, "albedo_color:a", 0.0, 0.4)

	particles.emitting = false

	await tween3.finished

## Apply materialize effect to entity (fade in)
func _apply_materialize_effect():
	if not target_entity:
		return

	# Find all MeshInstance3D children
	var meshes = _find_all_meshes(target_entity)

	for mesh_instance in meshes:
		var original_material = mesh_instance.get_surface_override_material(0)

		if original_material:
			# Duplicate material to avoid affecting other instances
			var mat_copy = original_material.duplicate()

			if mat_copy is StandardMaterial3D:
				mat_copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

				# Fade from transparent to opaque
				var tween = create_tween()
				tween.tween_method(
					func(alpha: float):
						if is_instance_valid(mesh_instance) and is_instance_valid(mat_copy):
							var color = mat_copy.albedo_color
							color.a = alpha
							mat_copy.albedo_color = color,
					0.0,
					1.0,
					0.6
				)

				mesh_instance.set_surface_override_material(0, mat_copy)

## Recursively find all MeshInstance3D nodes
func _find_all_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		result.append(node)

	for child in node.get_children():
		result.append_array(_find_all_meshes(child))

	return result

## Cleanup effects
func _cleanup():
	await get_tree().create_timer(0.5).timeout
	queue_free()

## Static helper to play spawn animation on entity
static func play_on_entity(entity: Node3D, parent: Node = null):
	var spawn_anim = SpawnAnimation.new()

	if parent:
		parent.add_child(spawn_anim)
	else:
		entity.get_parent().add_child(spawn_anim)

	spawn_anim.play_spawn_animation(entity)
