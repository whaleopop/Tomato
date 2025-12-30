## Defines what loot can drop from chests
extends Resource
class_name LootTable

@export var loot_entries: Array[Dictionary] = []

func generate_loot() -> Array[ItemData]:
	var items: Array[ItemData] = []
	
	for entry in loot_entries:
		if not entry.has("chance") or not entry.has("item"):
			continue
		
		if randf() < entry["chance"]:
			var item = entry["item"] as ItemData
			if item:
				items.append(item)
	
	return items

