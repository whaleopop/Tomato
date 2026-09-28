## Hot Temper (Pepper): below half health the pepper hits harder
## (meta "hot_temper", read by CombatComponent.get_damage_multiplier)
extends PassiveAbility
class_name HotTemper

const VALUE = 1.25

func _init():
	ability_name = "Hot Temper"
	cooldown = 0.0

func _on_apply(entity):  # entity: Entity
	entity.set_meta("hot_temper", VALUE)

func _on_remove(entity):  # entity: Entity
	if entity.has_meta("hot_temper"):
		entity.remove_meta("hot_temper")
