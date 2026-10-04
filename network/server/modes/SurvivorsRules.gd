## Weed Swarm (vampire-survivors-like, co-op): no zone, no other players to fight - waves of weeds
## hunt the heroes (Weed.hunter: no leash, no hiding), more of them and tougher every wave. Guns aim
## and fire on their own (meta "auto_fire", PlayerInputHandler) and never run out of reserve ammo
## (meta "endless_ammo", CombatComponent). A wave lasts WAVE_TIME; then the weeds still standing
## wither and in the break every hero standing gets a pick: two perk cards, each a buff with a
## debuff (SwarmPerks), dealt here and sent in the hero's own mode state ("offer"). The client
## picks a card (ModeView), the choice comes back as input ("mode_choice" = card index) and is
## applied here and on the owner's copy. Everyone down: game over.
extends ModeRules
class_name SurvivorsRules

const FIRST_WAVE: float = 5.0
const WAVE_TIME: float = 30.0
const BREAK_TIME: float = 8.0
const BURST_EVERY: float = 6.0
const SPAWN_MIN: float = 16.0        # world units from a hero
const SPAWN_MAX: float = 24.0
const MAX_ALIVE: int = 30
const TOUGHER_PER_WAVE: float = 0.15

var wave: int = 0
var phase: String = "wait"           # wait (before the first wave) / fight / break
var phase_left: float = FIRST_WAVE
var kills: int = 0
var pending: Dictionary = {}         # player id -> picks waiting
var offers: Dictionary = {}          # player id -> [[buff, debuff], [buff, debuff]]
var offer_seq: Dictionary = {}       # player id -> how many offers so far (the picker opens on a new one)
var taken: Dictionary = {}           # player id -> [[buff, debuff], ...]
var _burst: float = 0.0
var _second: float = 0.0
var _clearing: bool = false
var _rng := RandomNumberGenerator.new()

func on_match_start() -> void:
	wave = 0
	phase = "wait"
	phase_left = FIRST_WAVE
	kills = 0
	pending.clear()
	offers.clear()
	offer_seq.clear()
	taken.clear()
	_rng.randomize()

## The weeds are ours to send: they report their death here
func on_weed_died(_weed: Weed) -> void:
	if not _clearing:
		kills += 1

func _process(delta: float) -> void:
	if not server or not server.game_started or server.match_over:
		return
	_every_second(delta)
	phase_left -= delta
	match phase:
		"wait", "break":
			if phase_left <= 0.0:
				_start_wave()
		"fight":
			_burst -= delta
			if _burst <= 0.0:
				_burst = BURST_EVERY
				_spawn_burst()
			if phase_left <= 0.0:
				_end_wave()

func _heroes() -> Array:
	var out: Array = []
	for id in server.players:
		var e = alive_entity(id)
		if e:
			out.append(e)
	return out

func _start_wave() -> void:
	wave += 1
	phase = "fight"
	phase_left = WAVE_TIME
	_burst = 0.0
	announce("Wave %d", [wave], Color(1.0, 0.6, 0.3))
	for e in _heroes():
		var extra = float(e.get_meta("wave_shield", 0.0))
		if extra > 0.0:
			e.get_component("HealthComponent").add_shield(extra)

func _spawn_burst() -> void:
	var spawner: WeedSpawner = world().weed_spawner
	var heroes = _heroes()
	if not spawner or heroes.is_empty():
		return
	# 2 a burst in the first wave, one more every second wave and per extra hero (was 1 + heroes + wave
	# every 5 s up to 60: a solo player faced 18 in the first wave and 40+ by the fifth)
	var count = mini(1 + heroes.size() + wave / 2, MAX_ALIVE - spawner.weeds.size())
	var tough = 1.0 + (wave - 1) * TOUGHER_PER_WAVE
	for i in count:
		var hero: Node3D = heroes[i % heroes.size()]
		var pos = _random_land_spot(hero.global_position, SPAWN_MIN, SPAWN_MAX)
		var roll = randf()
		var kind = "Nettle" if roll < 0.45 else ("Dandelion" if roll < 0.8 else "Hogweed")
		if wave < 3 and kind == "Hogweed":
			kind = "Nettle"
		var weed = spawner.spawn(kind, pos)
		weed.hunter = true
		weed.health.set_max_health(weed.health.max_health * tough, true)
		weed.health.died.connect(func(): on_weed_died(weed))

## The wave is over: what is left of it withers, every hero standing gets a pick
func _end_wave() -> void:
	phase = "break"
	phase_left = BREAK_TIME
	var spawner: WeedSpawner = world().weed_spawner
	if spawner:
		_clearing = true
		for w in spawner.weeds.values():
			if is_instance_valid(w) and not w.health.is_dead:
				w.wither()
		_clearing = false
	announce("Wave %d cleared! Pick a card", [wave], Color(1.0, 0.85, 0.3))
	for id in server.players:
		if alive_entity(id):
			pending[id] = int(pending.get(id, 0)) + 1
			if not offers.has(id):
				_new_offer(id)

func _new_offer(id: int) -> void:
	offers[id] = SwarmPerks.deal(_rng)
	offer_seq[id] = int(offer_seq.get(id, 0)) + 1

## Once a second: regeneration / wilting, and the mode's metas on every hero (also late spawns)
func _every_second(delta: float) -> void:
	_second += delta
	if _second < 1.0:
		return
	_second -= 1.0
	for e in _heroes():
		e.set_meta("auto_fire", true)
		e.set_meta("endless_ammo", true)
		var regen = float(e.get_meta("sv_regen", 0.0))
		var h: HealthComponent = e.get_component("HealthComponent")
		if regen > 0.0:
			h.heal(regen)
		elif regen < 0.0 and h.current_health > 1.0:
			h.current_health = max(1.0, h.current_health + regen)
			h.health_changed.emit(h.current_health, h.max_health)

## The hero picked card 0 or 1 of their offer
func on_choice(player_id: int, choice: String) -> void:
	if int(pending.get(player_id, 0)) <= 0 or not offers.has(player_id) or not choice.is_valid_int():
		return
	var index = int(choice)
	var cards: Array = offers[player_id]
	if index < 0 or index >= cards.size() or not SwarmPerks.valid_card(cards[index]):
		return
	var e = alive_entity(player_id)
	if not e:
		return
	var card: Array = cards[index]
	SwarmPerks.apply(e, card[0])
	SwarmPerks.apply(e, card[1])
	if not taken.has(player_id):
		taken[player_id] = []
	taken[player_id].append(card)
	pending[player_id] = int(pending[player_id]) - 1
	offers.erase(player_id)
	if pending[player_id] > 0:
		_new_offer(player_id)

func check_end() -> Dictionary:
	if server._participants.is_empty():
		return {}
	for id in server._participants:
		if not server.players.has(id):
			continue
		var e = world().players.get(id)
		if e == null or not is_instance_valid(e):
			return {}  # still landing
		var h = e.get_component("HealthComponent")
		if h and not h.is_dead:
			return {}
	var t = int(server.match_time())
	return {"winner_id": 0, "winner_name": "%d:%02d|%d|%d" % [t / 60, t % 60, wave, kills]}

func state_for(viewer_id: int) -> Dictionary:
	var s = base_state()
	s["wave"] = wave
	s["phase"] = phase
	s["left"] = snappedf(max(phase_left, 0.0), 0.1)
	s["wave_time"] = WAVE_TIME if phase == "fight" else (BREAK_TIME if phase == "break" else FIRST_WAVE)
	s["kills"] = kills
	s["pending"] = int(pending.get(viewer_id, 0))
	s["seq"] = int(offer_seq.get(viewer_id, 0))
	if offers.has(viewer_id):
		s["offer"] = offers[viewer_id]
	s["taken"] = taken.get(viewer_id, [])
	return s
