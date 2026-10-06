## Leap to the target location, damage on impact (Pineapple: Crown Drop)
extends ActiveAbility
class_name TurnipToss

var damage: float = 35.0
var impact_radius: float = 3.0
var leap_speed: float = 20.0

func aim_preview() -> Dictionary:
	return {"shape": "circle", "range": max_range, "radius": impact_radius}

func _init():
	ability_name = "Turnip Toss"
	cast_pose = "cast_slam"
	icon = "target"
	cooldown = 9.0
	duration = 0.8
	max_range = 8.0

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	if target_position == Vector3.ZERO:
		return false
	var movement = entity.get_component("MovementComponent")
	if not movement:
		return false

	# Leap: cover the distance to the (range-limited) target in `duration`
	var offset = target_position - entity.global_position
	offset.y = 0.0
	if not replay:  # a replayed cast follows the synced position instead
		movement.dash(offset / duration, duration)
		movement.jump()
	await entity.get_tree().create_timer(duration).timeout

	# The caster may have left or died mid-air
	if not is_instance_valid(entity) or not entity.is_inside_tree():
		return true
	var own_health = entity.get_component("HealthComponent")
	if own_health and own_health.is_dead:
		return true

	# Impact where the turnip actually came down (walls may have stopped the leap)
	var center: Vector3 = entity.global_position
	for target in _find_targets_in_radius(entity, center):
		var health = target.get_component("HealthComponent")
		if health:
			health.take_damage(damage, entity)
	_create_impact_effect(entity, center)
	return true

func _find_targets_in_radius(entity, center: Vector3) -> Array:  # entity: Entity
	var targets: Array = []
	var all_entities = entity.get_tree().get_nodes_in_group("entities")
	
	for other_entity in all_entities:
		if other_entity == entity:
			continue
		
		var distance = center.distance_to(other_entity.global_position)
		if distance <= impact_radius:
			targets.append(other_entity)
	
	return targets

func _create_impact_effect(entity, position: Vector3):  # entity: Entity
	var parent = entity.get_parent() if entity.get_parent() is Node3D else entity.get_tree().current_scene
	if parent:
		LandingImpact.create_at(parent, position, Color(0.95, 0.85, 1.0), impact_radius / 3.0)
	HexTile.shake_around(entity, position, 0.9, impact_radius)

