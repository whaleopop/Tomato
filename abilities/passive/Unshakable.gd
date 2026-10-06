## Unshakable (Apple): not stunned, slowed, blinded or knocked back
## (meta "cc_immune", StatusComponent)
extends PassiveAbility
class_name Unshakable

const VALUE = true

func _init():
	ability_name = "Unshakable"
	icon = "locked"
	cooldown = 0.0

func _on_apply(entity):  # entity: Entity
	entity.set_meta("cc_immune", VALUE)

func _on_remove(entity):  # entity: Entity
	if entity.has_meta("cc_immune"):
		entity.remove_meta("cc_immune")
