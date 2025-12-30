## Ranged weapon item
extends Weapon
class_name RangedWeapon

@export var ammo_count: int = 30
@export var max_ammo: int = 30

func _init():
	pass
	item_name = "Ranged Weapon"
	consumable = false
	stackable = false

