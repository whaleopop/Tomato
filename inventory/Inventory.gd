## Inventory system for storing items
extends RefCounted
class_name Inventory

signal inventory_changed
signal slot_changed(slot: int)

var slots: Array = []  # Array[ItemStack]
var max_size: int = 10

func _init(p_max_size: int = 10):
	max_size = p_max_size
	slots.resize(max_size)
	for i in range(max_size):
		slots[i] = ItemStack.new()

func add_item(item: ItemData) -> int:
	if item == null:
		return -1
	
	# Check if item is stackable and already exists
	if item.stackable:
		for i in range(slots.size()):
			var stack = slots[i]
			if stack.item == item and stack.count < item.max_stack:
				stack.count += 1
				slot_changed.emit(i)
				inventory_changed.emit()
				return i
	
	# Find empty slot
	for i in range(slots.size()):
		if slots[i].item == null:
			slots[i].item = item
			slots[i].count = 1
			slot_changed.emit(i)
			inventory_changed.emit()
			return i
	
	return -1  # Inventory full

func remove_item(slot: int) -> ItemData:
	if slot < 0 or slot >= slots.size():
		return null
	
	var stack = slots[slot]
	if stack.item == null:
		return null
	
	var item = stack.item
	stack.count -= 1
	
	if stack.count <= 0:
		stack.item = null
		stack.count = 0
	
	slot_changed.emit(slot)
	inventory_changed.emit()
	return item

func get_item(slot: int) -> ItemData:
	if slot < 0 or slot >= slots.size():
		return null
	return slots[slot].item

func get_item_count(slot: int) -> int:
	if slot < 0 or slot >= slots.size():
		return 0
	return slots[slot].count

func has_space() -> bool:
	for stack in slots:
		if stack.item == null:
			return true
	return false

func get_filled_slots_count() -> int:
	var count = 0
	for stack in slots:
		if stack.item != null:
			count += 1
	return count

func clear():
	for i in range(slots.size()):
		slots[i].item = null
		slots[i].count = 0
	inventory_changed.emit()
