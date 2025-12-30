## Manages entity inventory and item storage
extends Component
class_name InventoryComponent

signal item_added(item: ItemData, slot: int)
signal item_removed(item: ItemData, slot: int)
signal item_used(item: ItemData)
signal inventory_full

var inventory = null
var max_size: int = 10

func _init(p_entity = null, p_max_size: int = 10):  # p_entity: Entity
	entity = p_entity
	max_size = p_max_size
	var InventoryClass = load("res://inventory/Inventory.gd")
	inventory = InventoryClass.new(max_size)

func add_item(item: ItemData) -> bool:
	if not enabled:
		return false
	
	var slot = inventory.add_item(item)
	if slot >= 0:
		item_added.emit(item, slot)
		return true
	else:
		inventory_full.emit()
		return false

func remove_item(slot: int) -> ItemData:
	if not enabled:
		return null
	
	var item = inventory.remove_item(slot)
	if item:
		item_removed.emit(item, slot)
	return item

func use_item(slot: int) -> bool:
	if not enabled:
		return false
	
	var item = inventory.get_item(slot)
	if item == null:
		return false
	
	# Use item based on type
	var used = false
	if item is HealthPack:
		used = _use_health_pack(item)
	elif item is Perk:
		used = _use_perk(item)
	
	if used:
		item_used.emit(item)
		# Remove consumable items
		if item.consumable:
			inventory.remove_item(slot)
	
	return used

func _use_health_pack(pack: HealthPack) -> bool:
	var health_component = entity.get_component("HealthComponent")
	if health_component:
		health_component.heal(pack.heal_amount)
		return true
	return false

func _use_perk(perk: Perk) -> bool:
	# Apply perk effects to entity
	# This would integrate with other components
	return true

func get_inventory():
	return inventory

func has_space() -> bool:
	return inventory.has_space()

func get_item_count() -> int:
	return inventory.get_filled_slots_count()
