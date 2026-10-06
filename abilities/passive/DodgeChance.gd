## Dodge Chance - chance to avoid damage (Pepper, Grape, Banana)
extends PassiveAbility
class_name DodgeChance

var dodge_chance: float = 0.15  # 15% chance to dodge attacks

func _init():
	ability_name = "Dodge Chance"
	icon = "fast"
	cooldown = 0.0

func _on_apply(entity):  # entity: Entity
	var health = entity.get_component("HealthComponent")
	if health:
		health.set_dodge_chance(dodge_chance)
		print("[DodgeChance] Applied %.0f%% dodge chance to %s" % [dodge_chance * 100, entity.name])

func _on_remove(entity):  # entity: Entity
	var health = entity.get_component("HealthComponent")
	if health:
		health.set_dodge_chance(0.0)
		print("[DodgeChance] Removed dodge chance from %s" % entity.name)

