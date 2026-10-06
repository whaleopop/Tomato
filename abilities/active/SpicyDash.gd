## Spicy Dash - a dash that leaves a trail of fire behind
extends Dash
class_name SpicyDash

func _init():
	super()
	ability_name = "Spicy Dash"
	icon = "speed"
	cooldown = 5.0

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	var start: Vector3 = entity.global_position
	if not super(entity, target_position):
		return false
	# The trail follows the dash line (stopped by walls), computed the same way on every peer:
	# someone else's copy doesn't dash itself, it's moved by the network
	var direction := _dash_direction(entity, target_position)
	var length := dash_distance
	if entity.is_inside_tree():
		var from = start + Vector3.UP * 0.5
		var query = PhysicsRayQueryParameters3D.create(from, from + direction * dash_distance, CoverSpawner.COVER_LAYER)
		var hit = entity.get_world_3d().direct_space_state.intersect_ray(query)
		if hit:
			length = max(0.0, from.distance_to(hit.position) - 0.4)
	var trail = FireTrail.new()
	trail.name = "FireTrail"
	trail.caster = entity
	var parent = entity.get_parent() if entity.get_parent() is Node3D else entity
	parent.add_child(trail)
	trail.global_position = start
	trail.lay(start, direction, length, dash_distance / dash_speed)
	return true

## The same direction Dash._on_activate uses
func _dash_direction(entity, target_position: Vector3) -> Vector3:
	var direction := Vector3.ZERO
	if target_position != Vector3.ZERO:
		direction = target_position - entity.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = entity.global_transform.basis.z
		direction.y = 0.0
	return direction.normalized()
