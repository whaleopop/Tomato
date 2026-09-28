## Small Target (Grape): enemies spot it only from part of their usual sight distance
## (meta "small_target", ServerVisibility / VisibilitySystem)
extends PassiveAbility
class_name SmallTarget

const VALUE = 0.75

func _init():
	ability_name = "Small Target"
	cooldown = 0.0

func _on_apply(entity):  # entity: Entity
	entity.set_meta("small_target", VALUE)

func _on_remove(entity):  # entity: Entity
	if entity.has_meta("small_target"):
		entity.remove_meta("small_target")
