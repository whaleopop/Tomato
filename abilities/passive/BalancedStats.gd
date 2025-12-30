## Balanced Stats - small bonuses to all stats (Turnip passive)
extends PassiveAbility
class_name BalancedStats

var stat_multiplier: float = 1.05  # 5% increase to all stats

# Store original values to avoid stacking issues
var original_max_health: float = -1.0
var original_speed: float = -1.0
var original_damage: float = -1.0

func _init():
	ability_name = "Balanced"
	cooldown = 0.0

func _on_apply(entity):  # entity: Entity
	# Apply to health
	var health = entity.get_component("HealthComponent")
	if health:
		if original_max_health < 0:
			original_max_health = health.max_health
		health.set_max_health(original_max_health * stat_multiplier, false)

	# Apply to movement
	var movement = entity.get_component("MovementComponent")
	if movement:
		if original_speed < 0:
			original_speed = movement.get_speed()
		movement.set_speed(original_speed * stat_multiplier)

	# Apply to combat
	var combat = entity.get_component("CombatComponent")
	if combat:
		if original_damage < 0:
			original_damage = combat.base_damage
		combat.set_base_damage(original_damage * stat_multiplier)

	print("[BalancedStats] Applied %.0f%% stat boost to %s" % [(stat_multiplier - 1.0) * 100, entity.name])

func _on_remove(entity):  # entity: Entity
	# Restore original values
	var health = entity.get_component("HealthComponent")
	if health and original_max_health >= 0:
		health.set_max_health(original_max_health, false)
		original_max_health = -1.0

	var movement = entity.get_component("MovementComponent")
	if movement and original_speed >= 0:
		movement.set_speed(original_speed)
		original_speed = -1.0

	var combat = entity.get_component("CombatComponent")
	if combat and original_damage >= 0:
		combat.set_base_damage(original_damage)
		original_damage = -1.0

	print("[BalancedStats] Removed stat boost from %s" % entity.name)

