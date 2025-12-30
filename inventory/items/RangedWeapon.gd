## Ranged weapon item
extends Weapon
class_name RangedWeapon

@export var ammo_type: AmmoItem.AmmoType = AmmoItem.AmmoType.PISTOL
@export var current_ammo: int = 12  # Ammo currently in the magazine
@export var magazine_size: int = 12  # Maximum magazine capacity
@export var reload_time: float = 2.0  # Seconds to reload
@export var is_reloading: bool = false

# Legacy properties (kept for backwards compatibility, will be removed)
@export var ammo_count: int = 30
@export var max_ammo: int = 30

func _init():
	item_name = "Ranged Weapon"
	consumable = false
	stackable = false

## Check if weapon can shoot
func can_shoot() -> bool:
	return current_ammo > 0 and not is_reloading

## Consume one round of ammo
func consume_ammo() -> bool:
	if current_ammo > 0:
		current_ammo -= 1
		return true
	return false

## Start reload process (actual reload happens in CombatComponent with timer)
func start_reload(reserve_ammo: int) -> int:
	if is_reloading or current_ammo == magazine_size:
		return 0  # Already reloading or magazine full

	var ammo_needed = magazine_size - current_ammo
	var ammo_to_reload = min(ammo_needed, reserve_ammo)

	if ammo_to_reload > 0:
		is_reloading = true
		return ammo_to_reload

	return 0

## Complete reload (called after reload timer finishes)
func complete_reload(ammo_amount: int):
	current_ammo += ammo_amount
	current_ammo = min(current_ammo, magazine_size)
	is_reloading = false

## Get ammo display text
func get_ammo_display() -> String:
	return "%d / %d" % [current_ammo, magazine_size]

