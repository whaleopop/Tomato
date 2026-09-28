## Zest (Lemon): the ability recharges faster
## (meta "cooldown_factor", AbilityComponent.effective_cooldown)
extends PassiveAbility
class_name QuickRecharge

const VALUE = 0.75

func _init():
	ability_name = "Zest"
	cooldown = 0.0

func _on_apply(entity):  # entity: Entity
	entity.set_meta("cooldown_factor", VALUE)

func _on_remove(entity):  # entity: Entity
	if entity.has_meta("cooldown_factor"):
		entity.remove_meta("cooldown_factor")
