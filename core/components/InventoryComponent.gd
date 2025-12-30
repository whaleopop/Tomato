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

## Equip weapon from inventory slot
func equip_weapon(slot: int) -> bool:
	if not enabled:
		return false

	var item = inventory.get_item(slot)
	if item == null or not item is Weapon:
		return false

	# Get CombatComponent and equip the weapon
	var combat_component = entity.get_component("CombatComponent")
	if combat_component and combat_component.has_method("equip_weapon"):
		# Pass the weapon's WeaponData to CombatComponent
		var weapon = item as Weapon
		combat_component.equip_weapon(weapon.weapon_data)
		print("[InventoryComponent] Equipped %s" % weapon.item_name)
		return true

	return false

## Get total ammo count for a specific ammo type across all inventory slots
func get_ammo_count(ammo_type: AmmoItem.AmmoType) -> int:
	if not enabled:
		return 0

	var total_ammo = 0
	for slot_idx in range(inventory.slots.size()):
		var stack = inventory.slots[slot_idx]
		if stack and stack.item is AmmoItem:
			var ammo = stack.item as AmmoItem
			if ammo.ammo_type == ammo_type:
				total_ammo += ammo.ammo_amount * stack.count

	return total_ammo

## Consume ammo of specific type (for reloading). Returns amount actually consumed
func consume_ammo(ammo_type: AmmoItem.AmmoType, amount: int) -> int:
	if not enabled or amount <= 0:
		return 0

	var remaining_to_consume = amount
	var consumed = 0

	# Iterate through inventory and consume ammo
	for slot_idx in range(inventory.slots.size()):
		if remaining_to_consume <= 0:
			break

		var stack = inventory.slots[slot_idx]
		if stack and stack.item is AmmoItem:
			var ammo = stack.item as AmmoItem
			if ammo.ammo_type == ammo_type:
				var available = ammo.ammo_amount * stack.count
				var to_take = min(remaining_to_consume, available)

				# Calculate how many stacks to remove
				var stacks_to_remove = ceili(float(to_take) / float(ammo.ammo_amount))
				var actual_taken = min(to_take, stacks_to_remove * ammo.ammo_amount)

				# Remove the stacks
				for i in range(stacks_to_remove):
					if stack.count > 0:
						inventory.remove_item(slot_idx, 1)

				consumed += actual_taken
				remaining_to_consume -= actual_taken

	return consumed

## Get reserve ammo for equipped weapon (checks weapon's ammo type)
func get_reserve_ammo_for_weapon(weapon: RangedWeapon) -> int:
	if weapon == null:
		return 0
	return get_ammo_count(weapon.ammo_type)
