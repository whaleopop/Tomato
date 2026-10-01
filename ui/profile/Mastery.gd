## Mastery: the more you play a hero / use a gun, the higher its level (XP from real matches,
## PlayerHUD._reward_row -> PlayerProfile.add_match_xp). Levels pass through five ranks - Bronze,
## Silver, Gold, Obsidian, Diamond (TIER_LEVELS) - and every rank gives its free skin for that hero
## (Cosmetics.SKINS "m_<rank>") or its finish for that gun (WEAPON_SKINS "m_<rank>"), like the camo
## grind in Call of Duty. Cards show the level in the corner and look richer with the rank
## (ParallaxCard.level / .mastery, shaders/card_background.gdshader).
extends RefCounted
class_name Mastery

const TIERS = ["bronze", "silver", "gold", "obsidian", "diamond"]
const TIER_NAMES = ["Bronze", "Silver", "Gold", "Obsidian", "Diamond"]
const TIER_COLORS = [Color(0.86, 0.55, 0.32), Color(0.8, 0.85, 0.92), Color(1.0, 0.8, 0.3), Color(0.62, 0.38, 1.0), Color(0.55, 0.95, 1.0)]
const TIER_LEVELS = [3, 6, 10, 15, 20]   # the level each rank starts at
const MAX_LEVEL: int = 25

# Heroes: XP to go from level n to n+1 = HERO_BASE + HERO_STEP * (n - 1)
const HERO_BASE: int = 500
const HERO_STEP: int = 100
# Guns level faster (a match is spent with a couple of them)
const WEAPON_BASE: int = 300
const WEAPON_STEP: int = 60

# XP for a match with a hero
const XP_MATCH: int = 100
const XP_PER_DAMAGE: float = 1.0
const XP_DAMAGE_CAP: int = 1500
const XP_PER_KILL: int = 150
const XP_PER_SECOND: float = 0.5
const XP_PLACE = [0, 500, 300, 200]
# XP for a gun: its damage and its kills
const WXP_PER_DAMAGE: float = 1.0
const WXP_PER_KILL: int = 100

static func _cost(level: int, weapon: bool) -> int:
	return (WEAPON_BASE + WEAPON_STEP * (level - 1)) if weapon else (HERO_BASE + HERO_STEP * (level - 1))

## {level, tier (-1 none .. 4 diamond), into (XP into this level), need (XP for the next), max}
static func progress(xp: int, weapon: bool = false) -> Dictionary:
	var level = 1
	var left = max(xp, 0)
	while level < MAX_LEVEL and left >= _cost(level, weapon):
		left -= _cost(level, weapon)
		level += 1
	return {"level": level, "tier": tier_for_level(level), "into": left, "need": _cost(level, weapon), "max": level >= MAX_LEVEL}

static func tier_for_level(level: int) -> int:
	var t = -1
	for i in TIER_LEVELS.size():
		if level >= TIER_LEVELS[i]:
			t = i
	return t

## XP a match gives the hero played (stats from the server: damage, kills, time, place)
static func hero_xp(stats: Dictionary) -> int:
	var xp = XP_MATCH
	xp += min(int(float(stats.get("damage", 0)) * XP_PER_DAMAGE), XP_DAMAGE_CAP)
	xp += int(stats.get("kills", 0)) * XP_PER_KILL
	xp += int(float(stats.get("time", 0)) * XP_PER_SECOND)
	var place = int(stats.get("place", 0))
	if place > 0 and place < XP_PLACE.size():
		xp += XP_PLACE[place]
	return xp

## XP per gun type for a match: {type: xp} from the server's per-weapon damage / kills
static func weapon_xp(stats: Dictionary) -> Dictionary:
	var out = {}
	var dmg: Dictionary = stats.get("wdmg", {})
	var kills: Dictionary = stats.get("wkills", {})
	for t in dmg:
		out[int(t)] = out.get(int(t), 0) + int(float(dmg[t]) * WXP_PER_DAMAGE)
	for t in kills:
		out[int(t)] = out.get(int(t), 0) + int(kills[t]) * WXP_PER_KILL
	return out

## The rank of a mastery cosmetic id ("m_gold" / "w_m_gold"), -1 for ordinary ones
static func tier_of_id(id: String) -> int:
	var key = id.substr(2) if id.begins_with("w_") else id
	if not key.begins_with("m_"):
		return -1
	return TIERS.find(key.substr(2))

static func tier_name(tier: int) -> String:
	return TIER_NAMES[tier] if tier >= 0 and tier < TIER_NAMES.size() else ""

static func tier_color(tier: int) -> Color:
	return TIER_COLORS[tier] if tier >= 0 and tier < TIER_COLORS.size() else Color(0.75, 0.8, 0.9)
