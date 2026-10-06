## Passive ability that increases max health
extends PassiveAbility
class_name ToughSkin

var health_bonus: float = 20.0

func _init(p_bonus: float = 20.0):
	ability_name = "Tough Skin"
	icon = "gem"
	cooldown = 0.0
	health_bonus = p_bonus

func _on_apply(entity):  # entity: Entity
	var health = entity.get_component("HealthComponent")
	if health:
		var new_max = health.max_health + health_bonus
		health.set_max_health(new_max, false)
		health.heal(health_bonus)  # spawn at the new max, not 20 below it

func _on_remove(entity):  # entity: Entity
	var health = entity.get_component("HealthComponent")
	if health:
		var new_max = max(100.0, health.max_health - health_bonus)
		health.set_max_health(new_max, false)

