## Ammunition item for weapons
extends ItemData
class_name AmmoItem

enum AmmoType {
	PISTOL,
	SHOTGUN,
	SNIPER,
	RIFLE,
	FUEL  # For flamethrower
}

@export var ammo_type: AmmoType = AmmoType.PISTOL
@export var ammo_amount: int = 30

func _init(p_ammo_type: AmmoType = AmmoType.PISTOL, p_amount: int = 30):
	ammo_type = p_ammo_type
	ammo_amount = p_amount

	# Set item properties based on ammo type
	match ammo_type:
		AmmoType.PISTOL:
			item_name = "Pistol Ammo"
			description = "9mm ammunition for pistols"
		AmmoType.SHOTGUN:
			item_name = "Shotgun Shells"
			description = "12 gauge shells for shotguns"
		AmmoType.SNIPER:
			item_name = "Sniper Rounds"
			description = "High-caliber rounds for sniper rifles"
		AmmoType.RIFLE:
			item_name = "Rifle Ammo"
			description = "5.56mm ammunition for assault rifles"
		AmmoType.FUEL:
			item_name = "Fuel Canister"
			description = "Fuel for flamethrower"

	# Ammo is stackable and not consumable (used automatically by weapons)
	consumable = false
	stackable = true
	max_stack = 999

## Get display name with amount
func get_display_name() -> String:
	return "%s x%d" % [item_name, ammo_amount]

## Static helper to get ammo type name
static func get_ammo_type_name(type: AmmoType) -> String:
	match type:
		AmmoType.PISTOL:
			return "Pistol Ammo"
		AmmoType.SHOTGUN:
			return "Shotgun Shells"
		AmmoType.SNIPER:
			return "Sniper Rounds"
		AmmoType.RIFLE:
			return "Rifle Ammo"
		AmmoType.FUEL:
			return "Fuel"
		_:
			return "Unknown Ammo"
