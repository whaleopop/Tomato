## Carrot Strike - a dash that hits everyone it passes through
extends Dash
class_name CarrotStrike

var damage: float = 25.0
var hit_radius: float = 1.2   # players don't collide with each other, so the dash goes through them

func aim_preview() -> Dictionary:
	return {"shape": "line", "range": dash_distance, "width": hit_radius * 2.0}

func _init():
	super()
	ability_name = "Carrot Strike"
	icon = "arrow_forward"
	cooldown = 6.0

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	if not super(entity, target_position):
		return false
	if not replay:  # someone else's copy doesn't move; the server does the hitting anyway
		_hit_along_path(entity)
	return true

## Every enemy that comes within reach during the dash is hit once
func _hit_along_path(entity) -> void:
	var hit: Dictionary = {}
	var time_left := dash_distance / dash_speed + 0.05
	var tree: SceneTree = entity.get_tree() if entity.is_inside_tree() else null
	while tree and time_left > 0.0 and is_instance_valid(entity):
		for other in tree.get_nodes_in_group("entities"):
			if other == entity or hit.has(other) or not other is Node3D:
				continue
			var offset: Vector3 = other.global_position - entity.global_position
			offset.y = 0.0
			if offset.length() > hit_radius:
				continue
			hit[other] = true
			var health = other.get_component("HealthComponent") if other.has_method("get_component") else null
			if health and not health.is_dead:
				health.take_damage(damage, entity)  # only counts on the server
				_create_hit_effect(entity, other.global_position)
		await tree.physics_frame
		time_left -= entity.get_physics_process_delta_time()

func _create_hit_effect(entity, position: Vector3) -> void:
	var particles = GPUParticles3D.new()
	particles.name = "CarrotHit"
	particles.amount = 14
	particles.lifetime = 0.35
	particles.one_shot = true
	particles.explosiveness = 1.0
	var material = ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 80.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0
	material.gravity = Vector3(0, -12, 0)
	material.scale_min = 0.5
	material.scale_max = 1.0
	material.color = Color(1.0, 0.6, 0.2)
	particles.process_material = material
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.08)
	particles.draw_pass_1 = mesh
	var parent = entity.get_parent() if entity.get_parent() is Node3D else entity
	parent.add_child(particles)
	particles.global_position = position + Vector3(0, 0.6, 0)
	particles.emitting = true
	await entity.get_tree().create_timer(0.8).timeout
	if is_instance_valid(particles):
		particles.queue_free()
