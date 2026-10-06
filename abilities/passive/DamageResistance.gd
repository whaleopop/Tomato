## Passive ability that provides damage resistance
extends PassiveAbility
class_name DamageResistance

var resistance_percent: float = 0.1  # 10% resistance

func _init(p_resistance: float = 0.1):
	ability_name = "Damage Resistance"
	icon = "shield"
	cooldown = 0.0
	resistance_percent = p_resistance

func _on_apply(entity):  # entity: Entity
	var health = entity.get_component("HealthComponent")
	if health:
		var current_resistance = health.damage_resistance
		health.set_damage_resistance(current_resistance + resistance_percent)

func _on_remove(entity):  # entity: Entity
	var health = entity.get_component("HealthComponent")
	if health:
		var current_resistance = health.damage_resistance
		health.set_damage_resistance(max(0.0, current_resistance - resistance_percent))
