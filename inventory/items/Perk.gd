## Perk item that provides buffs
extends ItemData
class_name Perk

@export var perk_type: String = ""  # "damage_boost", "speed_boost", etc.
@export var effect_value: float = 0.0
@export var duration: float = 30.0

func _init():
	pass
	item_name = "Perk"
	consumable = true
	stackable = false

