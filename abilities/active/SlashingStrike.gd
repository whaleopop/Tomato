## Slashing strike - melee area attack
extends ActiveAbility
class_name SlashingStrike

var damage: float = 25.0
var range: float = 3.0
var angle: float = 90.0  # Degrees

func aim_preview() -> Dictionary:
	return {"shape": "cone", "range": range, "angle": angle}

func _init():
	ability_name = "Slashing Strike"
	icon = "star4"
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

func _find_targets_in_range(entity, target_position: Vector3) -> Array:  # entity: Entity
	var targets: Array = []

	# The swing goes where you aim (falls back to the facing direction)
	var forward: Vector3 = entity.global_transform.basis.z
	if target_position != Vector3.ZERO:
		var aim = target_position - entity.global_position
		aim.y = 0.0
		if aim.length_squared() > 0.01:
			forward = aim.normalized()
	forward.y = 0.0
	forward = forward.normalized()

	for other_entity in entity.get_tree().get_nodes_in_group("entities"):
		if other_entity == entity:
			continue
		var to_other: Vector3 = other_entity.global_position - entity.global_position
		to_other.y = 0.0  # height differences (tile steps) don't count
		if to_other.length() <= range:
			var direction_to_target = to_other.normalized()
			var angle_to_target = rad_to_deg(forward.angle_to(direction_to_target))

			if angle_to_target <= angle / 2.0:
				targets.append(other_entity)

	return targets

func _create_slash_effect(entity, target_position: Vector3):  # entity: Entity
	var forward: Vector3 = entity.global_transform.basis.z
	if target_position != Vector3.ZERO:
		var aim = target_position - entity.global_position
		aim.y = 0.0
		if aim.length_squared() > 0.01:
			forward = aim.normalized()
	AbilityFX.slash(entity, forward, range, angle, AbilityFX.hero_color(entity, Color(0.8, 0.2, 0.4)))

