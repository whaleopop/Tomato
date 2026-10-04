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
			if stack.item != null and same_stack(stack.item, item) and stack.count < item.max_stack:
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

## Same kind of thing (two health packs of the same size): one stack. Every pickup is its own
## object, so comparing objects never stacked anything and the bag filled up with single packs.
static func same_stack(a: ItemData, b: ItemData) -> bool:
	if a == b:
		return true
	if a.get_script() != b.get_script() or a.item_name != b.item_name:
		return false
	for key in ["heal_amount", "shield_amount"]:
		if key in a and a.get(key) != b.get(key):
			return false
	return true

## Drag and drop in the bag (InventoryMenu): onto an empty slot it moves, onto the same kind it
## stacks (as much as fits), onto something else the two swap
func move_item(from: int, to: int) -> bool:
	if from == to or from < 0 or to < 0 or from >= slots.size() or to >= slots.size():
		return false
	var a = slots[from]
	var b = slots[to]
	if a.item == null:
		return false
	if b.item != null and a.item.stackable and same_stack(a.item, b.item) and not (a.item is AmmoItem):
		var room = a.item.max_stack - b.count
		if room <= 0:
			return false
		var moved = mini(room, a.count)
		b.count += moved
		a.count -= moved
		if a.count <= 0:
			a.item = null
			a.count = 0
	else:
		slots[from] = b
		slots[to] = a
	slot_changed.emit(from)
	slot_changed.emit(to)
	inventory_changed.emit()
	return true

## Would `item` fit (onto a stack or into an empty slot)?
func has_room_for(item: ItemData) -> bool:
	for stack in slots:
		if stack.item == null:
			return true
		if item.stackable and same_stack(stack.item, item) and stack.count < item.max_stack:
			return true
	return false

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
