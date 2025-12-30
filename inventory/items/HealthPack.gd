## Health pack consumable item
extends ItemData
class_name HealthPack

@export var heal_amount: float = 50.0

func _init():
	item_name = "Health Pack"
	description = "Restores health"
	consumable = true
	stackable = true
	max_stack = 5
