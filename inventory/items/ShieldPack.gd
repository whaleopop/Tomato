## Shield potion: picked up into the inventory, used with the "use_shield" key over a few seconds
## (InventoryComponent.start_use), then HealthComponent.add_shield
extends ItemData
class_name ShieldPack

@export var shield_amount: float = 30.0

func _init():
	item_name = "Shield"
	description = "Adds a shield that takes damage before your health"
	consumable = true
	stackable = true
	max_stack = 5
