## Pumpkin Smash - area damage around self
extends ActiveAbility
class_name PumpkinSmash

var damage: float = 40.0
var radius: float = 4.0

func _init():
	ability_name = "Pumpkin Smash"
	cooldown = 10.0
	duration = 0.6

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	# Deal damage to all nearby enemies
	var targets = _find_targets_in_radius(entity)
	
	for target in targets:
		var health = target.get_component("HealthComponent")
		if health:
			health.take_damage(damage, entity)
	
	# Create visual effect
	_create_smash_effect(entity)
	
	return true

func _find_targets_in_radius(entity) -> Array:  # entity: Entity
	var targets: Array = []
	var all_entities = entity.get_tree().get_nodes_in_group("entities")
	
	for other_entity in all_entities:
		if other_entity == entity:
			continue
		
		var distance = entity.global_position.distance_to(other_entity.global_position)
		if distance <= radius:
			targets.append(other_entity)
	
	return targets

func _create_smash_effect(entity):  # entity: Entity
	# Create ground shockwave effect
	var particles = GPUParticles3D.new()
	particles.name = "SmashWave"
	particles.amount = 50
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 1.0

	# Create particle material
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_radius = 0.5
	material.emission_ring_inner_radius = 0.3
	material.emission_ring_height = 0.1
	material.direction = Vector3(1, 0, 0)  # Radial outward
	material.spread = 180.0  # Full ring
	material.initial_velocity_min = radius * 2.0
	material.initial_velocity_max = radius * 3.0
	material.gravity = Vector3(0, -2, 0)
	material.scale_min = 0.3
	material.scale_max = 0.6
	material.color = Color(1.0, 0.6, 0.2, 0.9)  # Orange/pumpkin color

	# Fade gradient
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 0.6, 0.2, 1.0))
	gradient.set_color(1, Color(0.8, 0.3, 0.1, 0.0))
	var gradient_tex = GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material

	# Rocky debris mesh
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.15, 0.1, 0.15)
	particles.draw_pass_1 = mesh

	particles.position = Vector3(0, 0.1, 0)  # Near ground level
	entity.add_child(particles)

	# Cleanup
	if entity.is_inside_tree():
		await entity.get_tree().create_timer(1.0).timeout
		if is_instance_valid(particles):
			particles.queue_free()

