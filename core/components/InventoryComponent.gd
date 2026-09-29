## Manages entity inventory and item storage
extends Component
class_name InventoryComponent

signal item_added(item: ItemData, slot: int)
signal item_removed(item: ItemData, slot: int)
signal item_used(item: ItemData)
signal inventory_full
signal weapon_equipped(weapon: RangedWeapon, slot: int)
signal weapon_slot_changed(slot: int)

var inventory = null
var max_size: int = 10

# Weapon slots (5 slots for quick weapon switching)
const MAX_WEAPON_SLOTS: int = 5
var weapon_slots: Array[RangedWeapon] = []
var current_weapon_slot: int = 0

func _init(p_entity = null, p_max_size: int = 10):  # p_entity: Entity
	entity = p_entity
	max_size = p_max_size
	var InventoryClass = load("res://inventory/Inventory.gd")
	inventory = InventoryClass.new(max_size)

	# Initialize weapon slots
	weapon_slots.resize(MAX_WEAPON_SLOTS)
	for i in range(MAX_WEAPON_SLOTS):
		weapon_slots[i] = null

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
		# At full health the pack stays in the inventory
		return health_component.heal(pack.heal_amount * float(entity.get_meta("heal_bonus", 1.0))) > 0.0
	return false

## Timed buffs: effect_value is a multiplier, undone after perk.duration seconds
func _use_perk(perk: Perk) -> bool:
	if perk.effect_value <= 0.0:
		return false
	match perk.perk_type:
		"damage_boost":
			var combat = entity.get_component("CombatComponent")
			if not combat:
				return false
			combat.ranged_damage_multiplier *= perk.effect_value
			_expire_later(perk.duration, func(): combat.ranged_damage_multiplier /= perk.effect_value)
			return true
		"speed_boost":
			var movement = entity.get_component("MovementComponent")
			if not movement:
				return false
			movement.speed *= perk.effect_value
			_expire_later(perk.duration, func(): movement.speed /= perk.effect_value)
			return true
	return false

func _expire_later(seconds: float, undo: Callable):
	if entity and entity.is_inside_tree():
		entity.get_tree().create_timer(seconds).timeout.connect(undo)

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

## Consume ammo of specific type (for reloading). Returns amount actually consumed.
## A box is only used up as far as needed; the rest of its rounds stay in it.
func consume_ammo(ammo_type: AmmoItem.AmmoType, amount: int) -> int:
	if not enabled or amount <= 0:
		return 0

	var remaining = amount
	for slot_idx in range(inventory.slots.size()):
		var stack = inventory.slots[slot_idx]
		while remaining > 0 and stack and stack.item is AmmoItem and stack.item.ammo_type == ammo_type and stack.count > 0:
			var ammo: AmmoItem = stack.item
			if ammo.ammo_amount <= remaining:
				# The whole box goes into the magazine
				remaining -= ammo.ammo_amount
				inventory.remove_item(slot_idx)
			elif stack.count == 1:
				ammo.ammo_amount -= remaining
				remaining = 0
				inventory.slot_changed.emit(slot_idx)
				inventory.inventory_changed.emit()
			else:
				# Identical boxes share one ItemData: open one, keep its leftover as a new box
				var leftover = ammo.ammo_amount - remaining
				remaining = 0
				inventory.remove_item(slot_idx)
				inventory.add_item(AmmoItem.new(ammo_type, leftover))
		if remaining <= 0:
			break

	return amount - remaining

## Get reserve ammo for equipped weapon (checks weapon's ammo type)
func get_reserve_ammo_for_weapon(weapon: RangedWeapon) -> int:
	if weapon == null:
		return 0
	return get_ammo_count(weapon.ammo_type)

## Add weapon to first available weapon slot
func add_weapon_to_slot(weapon: RangedWeapon) -> int:
	print("[InventoryComponent] add_weapon_to_slot called for: %s" % weapon.item_name)
	for i in range(MAX_WEAPON_SLOTS):
		print("[InventoryComponent] Checking slot %d: %s" % [i, "empty" if weapon_slots[i] == null else weapon_slots[i].item_name])
		if weapon_slots[i] == null:
			weapon_slots[i] = weapon
			weapon_equipped.emit(weapon, i)
			print("[InventoryComponent] ✓ Added %s to weapon slot %d" % [weapon.item_name, i + 1])

			# Auto-equip if it's the first weapon or no weapon currently equipped
			var combat = entity.get_component("CombatComponent") if entity else null
			if combat and combat.equipped_ranged_weapon == null:
				print("[InventoryComponent] Auto-equipping first/only weapon")
				switch_weapon_slot(i)

			return i
	# All five slots taken: the new gun replaces the one in hand
	var combat = entity.get_component("CombatComponent") if entity else null
	if combat:
		combat.cancel_reload()
	weapon_slots[current_weapon_slot] = weapon
	weapon_equipped.emit(weapon, current_weapon_slot)
	switch_weapon_slot(current_weapon_slot)
	return current_weapon_slot

## Remove weapon from slot
func remove_weapon_from_slot(slot: int) -> RangedWeapon:
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return null

	var weapon = weapon_slots[slot]
	weapon_slots[slot] = null

	# If removed current weapon, switch to another
	if slot == current_weapon_slot:
		_switch_to_next_weapon()

	return weapon

## Switch to weapon slot (0-4)
func switch_weapon_slot(slot: int) -> bool:
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return false

	if weapon_slots[slot] == null:
		return false

	current_weapon_slot = slot
	var weapon = weapon_slots[slot]

	# Equip the weapon in CombatComponent
	var combat = entity.get_component("CombatComponent") if entity else null
	if combat:
		combat.equip_ranged_weapon(weapon)

	weapon_slot_changed.emit(slot)
	print("[InventoryComponent] Switched to weapon slot %d: %s" % [slot + 1, weapon.item_name])
	return true

## Get current equipped weapon
func get_current_weapon() -> RangedWeapon:
	if current_weapon_slot >= 0 and current_weapon_slot < MAX_WEAPON_SLOTS:
		return weapon_slots[current_weapon_slot]
	return null

## Get weapon in specific slot
func get_weapon_in_slot(slot: int) -> RangedWeapon:
	if slot >= 0 and slot < MAX_WEAPON_SLOTS:
		return weapon_slots[slot]
	return null

## Get count of weapons in slots
func get_weapon_count() -> int:
	var count = 0
	for weapon in weapon_slots:
		if weapon != null:
			count += 1
	return count

## Switch to next available weapon
func _switch_to_next_weapon():
	for i in range(MAX_WEAPON_SLOTS):
		var next_slot = (current_weapon_slot + i + 1) % MAX_WEAPON_SLOTS
		if weapon_slots[next_slot] != null:
			switch_weapon_slot(next_slot)
			return

	# No weapons left
	current_weapon_slot = 0
	var combat = entity.get_component("CombatComponent") if entity else null
	if combat:
		combat.equipped_ranged_weapon = null
