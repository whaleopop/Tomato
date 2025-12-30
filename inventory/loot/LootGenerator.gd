## Generates loot for chests and containers
extends RefCounted
class_name LootGenerator

var loot_tables: Dictionary = {}  # chest_type -> LootTable

func _init():
	_setup_default_loot_tables()

func _setup_default_loot_tables():
	# Common chest loot table
	var common_table = LootTable.new()
	common_table.loot_entries = [
		{"chance": 0.7, "item": _create_health_pack()},
		{"chance": 0.3, "item": _create_weapon()},
		{"chance": 0.2, "item": _create_perk()},
	]
	loot_tables["common"] = common_table

func _create_health_pack() -> HealthPack:
	var pack = HealthPack.new()
	pack.heal_amount = 50.0
	return pack

func _create_weapon() -> Weapon:
	var weapon = MeleeWeapon.new()
	return weapon

func _create_perk() -> Perk:
	var perk = Perk.new()
	perk.perk_type = "damage_boost"
	perk.effect_value = 1.2
	return perk

func generate_loot_for_chest(chest_type: String = "common") -> Array[ItemData]:
	var table = loot_tables.get(chest_type)
	if table:
		return table.generate_loot()
	return []

