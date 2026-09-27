## Ranged Damage Boost - increases ranged weapon damage (Corn passive)
extends PassiveAbility
class_name RangedDamageBoost

var damage_multiplier: float = 1.15  # 15% increase

func _init():
	ability_name = "Sharp Kernels"
	cooldown = 0.0

func _on_apply(entity):  # entity: Entity
	var combat = entity.get_component("CombatComponent")
	if combat:
		combat.set_ranged_damage_multiplier(damage_multiplier)
		print("[RangedDamageBoost] Applied %.0f%% ranged damage boost to %s" % [(damage_multiplier - 1.0) * 100, entity.name])

func _on_remove(entity):  # entity: Entity
	var combat = entity.get_component("CombatComponent")
	if combat:
		combat.set_ranged_damage_multiplier(1.0)
		print("[RangedDamageBoost] Removed ranged damage boost from %s" % entity.name)
