## Healing Sprout - heals the caster over a few seconds
extends ActiveAbility
class_name HealingSprout

var heal_amount: float = 30.0     # in total, spread over heal_duration
var heal_radius: float = 5.0
var heal_duration: float = 3.0
const HEAL_TICKS: int = 6

func _init():
	ability_name = "Healing Sprout"
	cooldown = 12.0
	duration = heal_duration

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	# Heal self only: it's every veggie for themselves, the old "allies in radius" were enemies.
	# A replay on someone else's copy is visual only (their health comes from the server).
	var health = entity.get_component("HealthComponent")
	if health and not replay:
		_heal_over_time(entity, health)

	# Create visual effect
	_create_healing_effect(entity)

	return true

## heal_amount in HEAL_TICKS equal parts, the first one right away; stops if the caster dies
func _heal_over_time(entity, health) -> void:
	var step = heal_amount / HEAL_TICKS
	for i in HEAL_TICKS:
		if not is_instance_valid(entity) or not entity.is_inside_tree() or health.is_dead:
			return
		health.heal(step)
		if i < HEAL_TICKS - 1:
			await entity.get_tree().create_timer(heal_duration / HEAL_TICKS).timeout

func _find_allies_in_radius(entity) -> Array:  # entity: Entity
	# In Battle Royale mode, there are no allies - all other players are enemies
	# This ability only heals the caster
	# NOTE: For future team modes, implement team_id check here:
	# if entity.team_id == other_entity.team_id: allies.append(other_entity)
	return []

func _create_healing_effect(entity):  # entity: Entity
	# Create green healing particles
	var particles = GPUParticles3D.new()
	particles.name = "HealingParticles"
	particles.amount = 30
	particles.lifetime = heal_duration
	particles.one_shot = true
	particles.explosiveness = 0.3

	# Create particle material
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.5
	material.direction = Vector3(0, 1, 0)
	material.spread = 45.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 2.5
	material.gravity = Vector3(0, -1, 0)
	material.scale_min = 0.1
	material.scale_max = 0.3
	material.color = Color(0.2, 1.0, 0.3, 0.9)

	# Add color gradient (fade out)
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.2, 1.0, 0.3, 1.0))
	gradient.set_color(1, Color(0.2, 1.0, 0.3, 0.0))
	var gradient_tex = GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material

	# Create simple mesh for particles
	var mesh = SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	particles.draw_pass_1 = mesh

	# Position at entity
	particles.position = Vector3(0, 0.5, 0)
	entity.add_child(particles)

	# Auto-cleanup after effect ends
	if entity.is_inside_tree():
		await entity.get_tree().create_timer(heal_duration + 0.5).timeout
		if is_instance_valid(particles):
			particles.queue_free()
