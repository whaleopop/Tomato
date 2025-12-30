## Slashing strike - melee area attack
extends ActiveAbility
class_name SlashingStrike

var damage: float = 25.0
var range: float = 3.0
var angle: float = 90.0  # Degrees

func _init():
	ability_name = "Slashing Strike"
	cooldown = 4.0
	duration = 0.5

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	var combat = entity.get_component("CombatComponent")
	if not combat:
		return false
	
	# Find targets in range
	var targets = _find_targets_in_range(entity, target_position)
	
	# Deal damage to all targets
	for target in targets:
		var health = target.get_component("HealthComponent")
		if health:
			health.take_damage(damage, entity)
	
	# Create visual effect
	_create_slash_effect(entity, target_position)
	
	return true

func _find_targets_in_range(entity, _target_position: Vector3) -> Array:  # entity: Entity
	var targets: Array = []
	
	# Get all entities in scene
	var all_entities = entity.get_tree().get_nodes_in_group("entities")
	
	for other_entity in all_entities:
		if other_entity == entity:
			continue
		
		var distance = entity.global_position.distance_to(other_entity.global_position)
		if distance <= range:
			# Check angle
			var direction_to_target = (other_entity.global_position - entity.global_position).normalized()
			var forward = entity.global_transform.basis.z
			var angle_to_target = rad_to_deg(forward.angle_to(direction_to_target))
			
			if angle_to_target <= angle / 2.0:
				targets.append(other_entity)
	
	return targets

func _create_slash_effect(_entity, _target_position: Vector3):  # entity: Entity
	# Visual effect for slash
	pass

