## Base resource for all items
extends Resource
class_name ItemData

@export var item_name: String = ""
@export var description: String = ""
@export var icon: Texture2D = null
@export var consumable: bool = false
@export var stackable: bool = false
@export var max_stack: int = 1

