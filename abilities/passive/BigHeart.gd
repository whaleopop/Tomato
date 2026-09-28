## Big Heart (Watermelon): health packs heal twice as much
## (meta "heal_bonus", LootItem and InventoryComponent)
extends PassiveAbility
class_name BigHeart

const VALUE = 2.0

func _init():
	ability_name = "Big Heart"
	cooldown = 0.0

func _on_apply(entity):  # entity: Entity
	entity.set_meta("heal_bonus", VALUE)

func _on_remove(entity):  # entity: Entity
	if entity.has_meta("heal_bonus"):
		entity.remove_meta("heal_bonus")
