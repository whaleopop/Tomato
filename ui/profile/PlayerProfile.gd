## The player's own profile on this computer (user://profile.cfg): the nickname (a local
## "registration" - there are no online accounts yet), the heroes they own (STARTER_PICKS of
## them are picked for free at the start, the rest are bought), coins, bought cosmetics and what
## each hero wears. Coins are earned in matches (PlayerHUD: MATCH_REWARD, KILL_REWARD, WIN_REWARD)
## and spent in the shop (ui/menus/Shop.gd). What the local player wears goes to the server with
## the chosen hero (NetworkLobby.client_set_character), so everybody sees it.
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

## The reward lines for a match: [[label, value text, coins], ...]
static func match_reward(stats: Dictionary) -> Array:
	var lines: Array = [["Match", "", MATCH_REWARD]]
	var damage = int(stats.get("damage", 0))
	lines.append(["Damage", str(damage), min(int(damage / DAMAGE_PER_COIN), DAMAGE_CAP)])
	var kills = int(stats.get("kills", 0))
	lines.append(["Eliminations", str(kills), kills * KILL_REWARD])
	var t = int(stats.get("time", 0))
	lines.append(["Survived", "%d:%02d" % [t / 60, t % 60], min(int(t / SURVIVAL_PER_COIN), SURVIVAL_CAP)])
	var place = int(stats.get("place", 0))
	if place > 0:
		lines.append(["Place", "#%d" % place, PLACE_REWARDS[place] if place < PLACE_REWARDS.size() else 0])
	return lines

static var _loaded: bool = false
static var coins: int = START_COINS
static var owned: Dictionary = {}          # cosmetic id -> true (free defaults are always owned)
static var hero_skin: Dictionary = {}      # hero name -> skin id
static var hero_hat: Dictionary = {}       # hero name -> hat id
static var weapon_skin: String = "default" # one finish for all guns
static var nickname: String = ""

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
	nickname = String(cfg.get_value("account", "nickname", ""))

static func save() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("wallet", "coins", coins)
	cfg.set_value("wallet", "owned", owned.keys())
	cfg.set_value("wear", "hero_skin", hero_skin)
	cfg.set_value("wear", "hero_hat", hero_hat)
	cfg.set_value("wear", "weapon_skin", weapon_skin)
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
	return Cosmetics.price_of(id) == 0 or owned.has(id)

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
	save()
	return true

static func equip(id: String, hero: String) -> void:
	load_profile()
	if not owns(id):
		return
	match Cosmetics.kind_of(id):
		"skin":
			hero_skin[hero] = id
		"hat":
			hero_hat[hero] = id
		"weapon":
			weapon_skin = id
	save()

static func is_equipped(id: String, hero: String) -> bool:
	var wear = equipped_for(hero)
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
	}
