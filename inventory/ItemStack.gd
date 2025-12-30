## Represents a stack of items in inventory
extends RefCounted
class_name ItemStack

var item = null  # ItemData
var count: int = 0

func _init(p_item = null, p_count: int = 1):  # p_item: ItemData
	item = p_item
	count = p_count

func is_empty() -> bool:
	return item == null or count <= 0

func can_add_more() -> bool:
	if item == null:
		return false
	if not item.stackable:
		return false
	return count < item.max_stack

