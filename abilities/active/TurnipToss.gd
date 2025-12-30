## Turnip Toss - leaps to target location
extends ActiveAbility
class_name TurnipToss

var damage: float = 35.0
var impact_radius: float = 3.0
var leap_speed: float = 20.0

func _init():
	ability_name = "Turnip Toss"
	cooldown = 9.0
	duration = 1.0

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	if target_position == Vector3.ZERO:
		return false
	
	# Leap to target position
	var movement = entity.get_component("MovementComponent")
	if movement:
		var direction = (target_position - entity.global_position).normalized()
		movement.velocity = direction * leap_speed
		
		# Wait for impact
		if entity and is_instance_valid(entity):
			await entity.get_tree().create_timer(duration).timeout
		
		# Deal damage on impact
		var targets = _find_targets_in_radius(entity, target_position)
		for target in targets:
			var health = target.get_component("HealthComponent")
			if health:
				health.take_damage(damage, entity)
		
		_create_impact_effect(entity, target_position)
	
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
	# Visual effect for impact
	pass

