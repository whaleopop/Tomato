## Dash ability - quick movement in a direction
extends ActiveAbility
class_name Dash

var dash_speed: float = 15.0
var dash_distance: float = 5.0

func aim_preview() -> Dictionary:
	return {"shape": "line", "range": dash_distance, "width": 1.0}

func _init():
	ability_name = "Dash"
	cooldown = 3.0
	duration = 0.3

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	var movement = entity.get_component("MovementComponent")
	if not movement:
		return false
	
	# Calculate dash direction
	var dash_direction: Vector3
	if target_position != Vector3.ZERO:
		dash_direction = (target_position - entity.global_position).normalized()
	else:
		# Use current movement direction
		dash_direction = movement.move_direction
		if dash_direction.length_squared() < 0.01:
			dash_direction = entity.global_transform.basis.z
	
	# Apply dash: dash_distance at dash_speed, along the ground
	dash_direction.y = 0.0
	if dash_direction.length_squared() < 0.01:
		dash_direction = entity.global_transform.basis.z
	dash_direction = dash_direction.normalized()
	if not replay:
		movement.dash(dash_direction * dash_speed, dash_distance / dash_speed)
	
	# Create dash effect
	_create_dash_effect(entity, dash_direction)
	
	return true

func _create_dash_effect(entity, direction: Vector3):  # entity: Entity
	# Create speed trail particles
	var particles = GPUParticles3D.new()
	particles.name = "DashTrail"
	particles.amount = 20
	particles.lifetime = duration
	particles.one_shot = true
	particles.explosiveness = 0.8

	# Create particle material
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(0.3, 0.5, 0.3)
	material.direction = -direction  # Particles trail behind
	material.spread = 10.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 4.0
	material.gravity = Vector3.ZERO
	material.scale_min = 0.2
	material.scale_max = 0.4
	material.color = Color(0.8, 0.9, 1.0, 0.7)

	# Fade out gradient
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.8, 0.9, 1.0, 0.8))
	gradient.set_color(1, Color(0.8, 0.9, 1.0, 0.0))
	var gradient_tex = GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material

	# Simple mesh
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.1, 0.1, 0.2)
	particles.draw_pass_1 = mesh

	particles.position = Vector3(0, 0.5, 0)
	entity.add_child(particles)

	# Cleanup
	if entity.is_inside_tree():
		await entity.get_tree().create_timer(duration + 0.3).timeout
		if is_instance_valid(particles):
			particles.queue_free()

func _on_deactivate(entity):  # entity: Entity
	# Dash finished, return to normal movement
	pass

