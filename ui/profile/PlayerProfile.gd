## The player's own profile on this computer (user://profile.cfg): the nickname (a local
## "registration" - there are no online accounts yet), the heroes they own (STARTER_PICKS of
## them are picked for free at the start, the rest are bought), coins, bought cosmetics and what
## each hero wears. Coins are earned in matches (PlayerHUD: MATCH_REWARD, KILL_REWARD, WIN_REWARD)
## and spent in the shop (ui/menus/Shop.gd). What the local player wears goes to the server with
## the chosen hero (NetworkLobby.client_set_character), so everybody sees it.
## Online (network/online/Online.gd logged in) this is a mirror of the profile on the server: nothing
## is saved here, purchases / equipment / names / starters also go to the server (whose answer
## replaces the mirror), and match coins / XP are credited by the game server's report - what the
## HUD adds in memory after a match is only for the result screen.
extends RefCounted
class_name PlayerProfile

const PATH = "user://profile.cfg"
const START_COINS: int = 300
const STARTER_PICKS: int = 2  # a new player picks this many heroes from the whole roster
const NAME_MIN: int = 3
const NAME_MAX: int = 16
# Coins for a match, from how it went (PlayerHUD._reward_row, stats from ServerPlayer)
const MATCH_REWARD: int = 10      # for playing
const KILL_REWARD: int = 15       # per elimination
const DAMAGE_PER_COIN: float = 10.0
const DAMAGE_CAP: int = 80
const SURVIVAL_PER_COIN: float = 10.0  # seconds alive
const SURVIVAL_CAP: int = 40
const PLACE_REWARDS = [0, 100, 50, 30]  # 1st, 2nd, 3rd place
const WIN_REWARD: int = 100
const WEED_REWARD: int = 3       # per weed felled (Weed Swarm and the wild weeds)
const WEED_CAP: int = 150

## The reward lines for a match: [[label, value text, coins], ...]
static func match_reward(stats: Dictionary) -> Array:
	var lines: Array = [["Match", "", MATCH_REWARD]]
	var damage = int(stats.get("damage", 0))
	lines.append(["Damage", str(damage), min(int(damage / DAMAGE_PER_COIN), DAMAGE_CAP)])
	var kills = int(stats.get("kills", 0))
	lines.append(["Eliminations", str(kills), kills * KILL_REWARD])
	var t = int(stats.get("time", 0))
	lines.append(["Survived", "%d:%02d" % [t / 60, t % 60], min(int(t / SURVIVAL_PER_COIN), SURVIVAL_CAP)])
	var weeds = int(stats.get("weeds", 0))
	if weeds > 0:
		lines.append(["Weeds", str(weeds), min(weeds * WEED_REWARD, WEED_CAP)])
	var place = int(stats.get("place", 0))
	if place > 0:
		lines.append(["Place", "#%d" % place, PLACE_REWARDS[place] if place < PLACE_REWARDS.size() else 0])
	return lines

static var _loaded: bool = false
static var coins: int = START_COINS
static var owned: Dictionary = {}          # cosmetic id -> true (free defaults are always owned)
static var hero_skin: Dictionary = {}      # hero name -> skin id
static var hero_hat: Dictionary = {}       # hero name -> hat id
static var weapon_skin: String = "default" # one finish for all guns...
static var weapon_skin_by_type: Dictionary = {}  # ...unless a gun has its own (mastery camos): "type" -> id
static var hero_xp: Dictionary = {}        # hero name -> mastery XP (Mastery.gd)
static var weapon_xp: Dictionary = {}      # "weapon type" -> mastery XP
static var nickname: String = ""
static var online: bool = false  # the server's profile (Online.gd), not user://profile.cfg

## The server's profile (every answer of the backend carries it)
static func apply_remote(p: Dictionary) -> void:
	_loaded = true
	online = true
	coins = int(p.get("coins", 0))
	owned = {}
	for id in p.get("owned", []):
		owned[String(id)] = true
	hero_skin = p.get("hero_skin", {})
	hero_hat = p.get("hero_hat", {})
	weapon_skin = String(p.get("weapon_skin", "default"))
	weapon_skin_by_type = p.get("weapon_skin_by_type", {})
	hero_xp = p.get("hero_xp", {})
	weapon_xp = p.get("weapon_xp", {})
	nickname = String(p.get("nickname", ""))

## Tell the server (online only); its answer brings the profile back
static func _remote(path: String, body: Dictionary) -> void:
	if not online:
		return
	var tree = Engine.get_main_loop() as SceneTree
	var service = tree.root.get_node_or_null("Online") if tree else null
	if service:
		service.request(HTTPClient.METHOD_POST, path, body)

static func load_profile() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	coins = int(cfg.get_value("wallet", "coins", START_COINS))
	for id in cfg.get_value("wallet", "owned", []):
		owned[String(id)] = true
	hero_skin = cfg.get_value("wear", "hero_skin", {})
	hero_hat = cfg.get_value("wear", "hero_hat", {})
	weapon_skin = String(cfg.get_value("wear", "weapon_skin", "default"))
	weapon_skin_by_type = cfg.get_value("wear", "weapon_skin_by_type", {})
	hero_xp = cfg.get_value("mastery", "heroes", {})
	weapon_xp = cfg.get_value("mastery", "weapons", {})
	nickname = String(cfg.get_value("account", "nickname", ""))

static func save() -> void:
	if online:
		return
	var cfg = ConfigFile.new()
	cfg.set_value("wallet", "coins", coins)
	cfg.set_value("wallet", "owned", owned.keys())
	cfg.set_value("wear", "hero_skin", hero_skin)
	cfg.set_value("wear", "hero_hat", hero_hat)
	cfg.set_value("wear", "weapon_skin", weapon_skin)
	cfg.set_value("wear", "weapon_skin_by_type", weapon_skin_by_type)
	cfg.set_value("mastery", "heroes", hero_xp)
	cfg.set_value("mastery", "weapons", weapon_xp)
	cfg.set_value("account", "nickname", nickname)
	cfg.save(PATH)

static func get_coins() -> int:
	load_profile()
	return coins

static func add_coins(amount: int) -> void:
	load_profile()
	coins = max(coins + amount, 0)
	save()

static func owns(id: String) -> bool:
	load_profile()
	if Cosmetics.is_mastery(id):
		return false  # earned per hero / per gun: owns_for
	return Cosmetics.price_of(id) == 0 or owned.has(id)

## Owned for this hero (skins) / this gun (finishes): mastery ones once its rank is reached
static func owns_for(id: String, hero: String = "", weapon_type: int = -1) -> bool:
	var rank = Mastery.tier_of_id(id)
	if rank < 0:
		return owns(id)
	if Cosmetics.kind_of(id) == "weapon":
		return weapon_type >= 0 and weapon_progress(weapon_type).tier >= rank
	return hero != "" and hero_progress(hero).tier >= rank

static func hero_progress(hero: String) -> Dictionary:
	load_profile()
	return Mastery.progress(int(hero_xp.get(hero, 0)))

static func weapon_progress(weapon_type: int) -> Dictionary:
	load_profile()
	return Mastery.progress(int(weapon_xp.get(str(weapon_type), 0)), true)

## The finish this gun wears: its own (a mastery camo) or the one for all guns
static func weapon_finish_for(weapon_type: int) -> String:
	load_profile()
	return String(weapon_skin_by_type.get(str(weapon_type), weapon_skin))

## A real match is over: XP for the hero played and every gun used. Returns what to show:
## {hero: [before, after, xp], weapons: {type: [before, after, xp]}, unlocked: [[hero / gun name, rank]]}
static func add_match_xp(hero: String, stats: Dictionary) -> Dictionary:
	load_profile()
	var report = {"weapons": {}, "unlocked": []}
	if hero != "":
		var before = hero_progress(hero)
		var gain = Mastery.hero_xp(stats)
		hero_xp[hero] = int(hero_xp.get(hero, 0)) + gain
		var after = hero_progress(hero)
		report["hero"] = [before, after, gain]
		for t in range(before.tier + 1, after.tier + 1):
			report.unlocked.append([hero, t])
	var wx = Mastery.weapon_xp(stats)
	for t in wx:
		if wx[t] <= 0:
			continue
		var wb = weapon_progress(t)
		weapon_xp[str(t)] = int(weapon_xp.get(str(t), 0)) + int(wx[t])
		var wa = weapon_progress(t)
		report.weapons[t] = [wb, wa, wx[t]]
		for r in range(wb.tier + 1, wa.tier + 1):
			report.unlocked.append([RangedWeapon.create_weapon(t).item_name, r])
	save()
	return report

## Buy a cosmetic: false if it costs more than we have
static func buy(id: String) -> bool:
	load_profile()
	if owns(id):
		return true
	var price = Cosmetics.price_of(id)
	if price < 0 or coins < price:
		return false
	coins -= price
	owned[id] = true
	Sfx.ui("purchase")
	save()
	_remote("/profile/buy", {"id": id})
	return true

static func equip(id: String, hero: String) -> void:
	load_profile()
	if not owns_for(id, hero):
		return
	match Cosmetics.kind_of(id):
		"skin":
			hero_skin[hero] = id
		"hat":
			hero_hat[hero] = id
		"weapon":
			weapon_skin = id
	save()
	_remote("/profile/equip", {"id": id, "hero": hero, "weapon_type": -1})

## Put a finish on one gun: a mastery camo stays on that gun; an ordinary finish goes on every
## gun and this one drops its own
static func equip_weapon(id: String, weapon_type: int) -> void:
	load_profile()
	if not owns_for(id, "", weapon_type):
		return
	if Cosmetics.is_mastery(id):
		weapon_skin_by_type[str(weapon_type)] = id
	else:
		weapon_skin = id
		weapon_skin_by_type.erase(str(weapon_type))
	save()
	_remote("/profile/equip", {"id": id, "hero": "", "weapon_type": weapon_type})

static func is_equipped(id: String, hero: String, weapon_type: int = -1) -> bool:
	var wear = equipped_for(hero)
	if Cosmetics.kind_of(id) == "weapon" and weapon_type >= 0:
		return weapon_finish_for(weapon_type) == id
	return wear.skin == id or wear.hat == id or wear.weapon == id

# ---------------------------------------------------------------- account and heroes

static func has_account() -> bool:
	load_profile()
	return nickname != ""

## "" if the name is fine, else why not
static func check_name(name: String) -> String:
	var n = name.strip_edges()
	if n.length() < NAME_MIN or n.length() > NAME_MAX:
		return "The name must be 3 to 16 characters long"
	return ""

static func register(name: String) -> void:
	load_profile()
	nickname = name.strip_edges()
	save()
	_remote("/profile/name", {"name": nickname})

## Still has to pick the starting hero (new profiles, and profiles from before heroes were bought)
static func needs_starter() -> bool:
	return owned_heroes().is_empty()

## The free heroes of a new profile (any STARTER_PICKS from the roster)
static func choose_starters(heroes: Array) -> void:
	load_profile()
	if not needs_starter() or heroes.size() != STARTER_PICKS:
		return
	for hero in heroes:
		if CharacterRegistry.get_by_name(hero):
			owned[Cosmetics.hero_id(hero)] = true
	save()
	_remote("/profile/starters", {"heroes": heroes})

static func owns_hero(hero: String) -> bool:
	return owns(Cosmetics.hero_id(hero))

static func owned_heroes() -> Array:
	load_profile()
	var result: Array = []
	for id in owned:
		if String(id).begins_with("hero:"):
			result.append(String(id).substr(5))
	return result

## What `hero` wears: {"skin", "hat", "weapon"} (sent over the network with the hero)
static func equipped_for(hero: String) -> Dictionary:
	load_profile()
	return {
		"skin": String(hero_skin.get(hero, "classic")),
		"hat": String(hero_hat.get(hero, "no_hat")),
		"weapon": weapon_skin,
		"weapons": weapon_skin_by_type.duplicate(),  # per-gun finishes (mastery camos)
		"level": hero_progress(hero).level,          # others see your card's level and rank
		"mastery": hero_progress(hero).tier,
	}
