## Spiky Skin (Pineapple): whoever hurts the pineapple gets a share of the damage back
## (meta "thorns", HealthComponent._thorns)
extends PassiveAbility
class_name SpikySkin

const VALUE = 0.2

func _init():
	ability_name = "Spiky Skin"
	cooldown = 0.0

func _on_apply(entity):  # entity: Entity
	entity.set_meta("thorns", VALUE)

func _on_remove(entity):  # entity: Entity
	if entity.has_meta("thorns"):
		entity.remove_meta("thorns")
