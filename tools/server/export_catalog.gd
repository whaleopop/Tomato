extends SceneTree
## Writes what the backend needs to check purchases, equipment and mastery (prices, kinds, heroes,
## Mastery numbers) from the game's own data into tools/server/backend/catalog.json, so the shop
## never has two price lists. deploy.ps1 runs it before every upload:
##   godot --headless --path . -s tools/server/export_catalog.gd
## (Game classes are loaded at run time: a -s script must not name them, see the test notes.)

const OUT = "res://tools/server/backend/catalog.json"

func _initialize():
	var cosmetics = load("res://ui/profile/Cosmetics.gd")
	var profile = load("res://ui/profile/PlayerProfile.gd")
	var mastery = load("res://ui/profile/Mastery.gd")
	var registry = load("res://characters/CharacterRegistry.gd")

	var heroes: Array = []
	for c in registry.get_all():
		heroes.append(String(c.character_name))
	var ids: Array = []
	for id in cosmetics.SKINS:
		ids.append(String(id))
	for id in cosmetics.HATS:
		ids.append(String(id))
	for id in cosmetics.WEAPON_SKINS:
		ids.append(cosmetics.weapon_id(String(id)))
	for hero in heroes:
		ids.append(cosmetics.hero_id(hero))
	var items := {}
	for id in ids:
		items[id] = {"price": cosmetics.price_of(id), "kind": cosmetics.kind_of(id), "rank": mastery.tier_of_id(id)}

	var catalog := {
		"version": String(ProjectSettings.get_setting("application/config/version", "")),
		"start_coins": profile.START_COINS,
		"starter_picks": profile.STARTER_PICKS,
		"name_min": profile.NAME_MIN,
		"name_max": profile.NAME_MAX,
		"heroes": heroes,
		"items": items,
		"mastery": {
			"tier_levels": mastery.TIER_LEVELS, "max_level": mastery.MAX_LEVEL,
			"hero_base": mastery.HERO_BASE, "hero_step": mastery.HERO_STEP,
			"weapon_base": mastery.WEAPON_BASE, "weapon_step": mastery.WEAPON_STEP,
		},
	}
	var f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(catalog, "\t"))
	f.close()
	print("[Catalog] %d items, %d heroes -> %s" % [items.size(), heroes.size(), OUT])
	quit(0)
