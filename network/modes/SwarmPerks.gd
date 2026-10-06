## Weed Swarm perk cards: after every wave each hero picks one of two cards, a buff on top and a
## debuff under it ("+30 health, BUT -10% damage"). The server deals the offers
## (SurvivorsRules._new_offer: two cards, four different perks, never a buff and a debuff on the
## same stat) and applies the pick; the picker's own client applies it too, for prediction.
## Everything here is the same on server and client: apply() only touches components and metas
## the rest of the game already reads (fire_rate_factor, range_factor, reload_factor, crit_chance,
## lifesteal, thorns, cooldown_factor, stamina_factor, heal_bonus, sv_regen, wave_shield).
## Ids go over the network: keep them, append new ones.
extends RefCounted
class_name SwarmPerks

## id -> [name, text, stat, value]
const BUFFS = {
	"b_health": ["Thick skin", "+30 max health", "health", 30.0],
	"b_damage": ["Sharp seeds", "+15% weapon damage", "damage", 0.15],
	"b_firerate": ["Quick hands", "Fire 12% faster", "firerate", 0.12],
	"b_speed": ["Long stride", "+10% walking speed", "speed", 0.10],
	"b_regen": ["Photosynthesis", "Heal 1.5 health a second", "regen", 1.5],
	"b_armor": ["Bark", "Take 10% less damage", "armor", 0.10],
	"b_range": ["Long barrel", "+20% gun range", "range", 0.20],
	"b_reload": ["Nimble fingers", "Reload 25% faster", "reload", 0.25],
	"b_crit": ["Lucky seed", "+10% chance to hit twice as hard", "crit", 0.10],
	"b_lifesteal": ["Sap drinker", "Heal 4% of the damage you deal", "lifesteal", 0.04],
	"b_thorns": ["Prickles", "Whoever hits you takes 25% back", "thorns", 0.25],
	"b_cooldown": ["Zest", "Abilities recharge 20% faster", "cooldown", 0.20],
	"b_dodge": ["Slippery peel", "6% chance to dodge a hit", "dodge", 0.06],
	"b_shield": ["Wax coat", "+20 shield now and every wave", "shield", 20.0],
	"b_juice": ["Fresh juice", "Heal to full right now", "instant", 1.0],
	"b_healpack": ["Juicy", "Health packs heal 50% more", "heal", 0.5],
}

const DEBUFFS = {
	"d_health": ["Hollow", "-20 max health", "health", -20.0],
	"d_damage": ["Blunt seeds", "-10% weapon damage", "damage", -0.10],
	"d_firerate": ["Stiff fingers", "Fire 10% slower", "firerate", -0.10],
	"d_speed": ["Heavy roots", "-8% walking speed", "speed", -0.08],
	"d_regen": ["Wilting", "Lose 1 health a second (never below 1)", "regen", -1.0],
	"d_armor": ["Thin peel", "Take 10% more damage", "armor", -0.10],
	"d_range": ["Short barrel", "-15% gun range", "range", -0.15],
	"d_reload": ["Butterfingers", "Reload 30% slower", "reload", -0.30],
	"d_cooldown": ["Sleepy", "Abilities recharge 25% slower", "cooldown", -0.25],
	"d_bruise": ["Bruised", "Lose 30% of your health now", "instant", -0.30],
	"d_brittle": ["Brittle", "Your shield breaks now", "shield", 0.0],
	"d_healpack": ["Bitter juice", "Health packs heal 30% less", "heal", -0.3],
}

## An icon name (UITheme.icon) per stat for the cards and the perk list
const ICONS = {
	"health": "heart", "damage": "sparkle", "firerate": "fast", "speed": "speed", "regen": "flower", "armor": "shield",
	"range": "target", "reload": "refresh", "crit": "star", "lifesteal": "heart", "thorns": "diamond", "cooldown": "refresh",
	"dodge": "speed", "shield": "shield", "stamina": "speed", "instant": "heart", "heal": "heart",
}

const BUFF_COLOR := Color(0.45, 1.0, 0.55)
const DEBUFF_COLOR := Color(1.0, 0.4, 0.38)

static func get_perk(id: String) -> Array:
	if BUFFS.has(id):
		return BUFFS[id]
	return DEBUFFS.get(id, [])

static func is_buff(id: String) -> bool:
	return BUFFS.has(id)

static func stat(id: String) -> String:
	var p = get_perk(id)
	return String(p[2]) if p.size() > 2 else ""

static func icon(id: String) -> String:
	return String(ICONS.get(stat(id), "dot"))

## Two cards [[buff, debuff], [buff, debuff]]: four different perks, no card that gives and takes
## the same stat
static func deal(rng: RandomNumberGenerator, cards: int = 2) -> Array:
	var buffs = BUFFS.keys()
	var debuffs = DEBUFFS.keys()
	var out: Array = []
	for i in cards:
		var b = _draw(rng, buffs, "")
		buffs.erase(b)
		var d = _draw(rng, debuffs, stat(b))
		debuffs.erase(d)
		out.append([b, d])
	return out

static func _draw(rng: RandomNumberGenerator, pool: Array, not_stat: String) -> String:
	var options = pool.filter(func(id): return stat(id) != not_stat)
	return options[rng.randi_range(0, options.size() - 1)]

static func valid_card(card) -> bool:
	return card is Array and card.size() == 2 and BUFFS.has(String(card[0])) and DEBUFFS.has(String(card[1]))

## The change itself, on the server's hero and on the owner's own copy. Health, shield and
## instant effects only count on the server (HealthComponent heals / shields are synced).
static func apply(e: Node, id: String) -> void:
	var p = get_perk(id)
	if p.is_empty() or not e or not e.has_method("get_component"):
		return
	var v = float(p[3])
	var h: HealthComponent = e.get_component("HealthComponent")
	var c = e.get_component("CombatComponent")
	var m = e.get_component("MovementComponent")
	match String(p[2]):
		"health":
			if h:
				h.set_max_health(max(20.0, h.max_health + v), false)
				if v > 0.0:
					h.heal(v)
		"damage":
			if c:
				c.ranged_damage_multiplier *= 1.0 + v
		"firerate":
			_mul(e, "fire_rate_factor", 1.0 - v)  # the time between shots
		"speed":
			if m:
				m.speed *= 1.0 + v
		"regen":
			_add(e, "sv_regen", v)
		"armor":
			if h:
				h.damage_resistance = clamp(h.damage_resistance + v, -0.5, 0.6)
		"range":
			_mul(e, "range_factor", 1.0 + v)
		"reload":
			_mul(e, "reload_factor", 1.0 - v)
		"crit":
			_add(e, "crit_chance", v)
		"lifesteal":
			_add(e, "lifesteal", v)
		"thorns":
			_add(e, "thorns", v)
		"cooldown":
			_mul(e, "cooldown_factor", 1.0 - v)
		"dodge":
			if h:
				h.dodge_chance = min(0.5, h.dodge_chance + v)
		"shield":
			if h and v > 0.0:
				_add(e, "wave_shield", v)
				if h._is_authority():
					h.add_shield(v)
			elif h and h._is_authority():
				h.set_shield(0.0)
		"stamina":
			_mul(e, "stamina_factor", 1.0 - v)
		"heal":
			_mul(e, "heal_bonus", 1.0 + v)
		"instant":
			if h and h._is_authority() and not h.is_dead:
				if v > 0.0:
					h.heal(h.max_health * v)
				else:
					h.current_health = max(1.0, h.current_health + h.max_health * v)
					h.health_changed.emit(h.current_health, h.max_health)

static func _mul(e: Node, key: String, f: float) -> void:
	e.set_meta(key, float(e.get_meta(key, 1.0)) * f)

static func _add(e: Node, key: String, v: float) -> void:
	e.set_meta(key, float(e.get_meta(key, 0.0)) + v)
