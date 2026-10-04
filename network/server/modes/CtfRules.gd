## Capture the Flag: red (0) against blue (1), teams dealt in turn at the match start. Each team
## has a base at one end of the island with its flag. Touch the enemy flag to take it, bring it to
## your base while your own flag is home: a capture. A carrier who falls drops it; touching your own
## dropped flag sends it home (or it goes home by itself after RETURN_TIME). First to CAPTURES_TO_WIN,
## or the most when TIME_LIMIT runs out. Friendly fire is off (HealthComponent: meta "team"),
## teammates always see each other (ServerVisibility), carriers are seen by everyone.
extends ModeRules
class_name CtfRules

const CAPTURES_TO_WIN: int = 3
const TIME_LIMIT: float = 600.0
const TOUCH: float = 1.8             # world units: picking up / returning
const CAPTURE: float = 3.0           # how close to your base the carrier must come
const RETURN_TIME: float = 20.0      # a dropped flag goes home by itself after this

var teams: Dictionary = {}           # player id -> 0 / 1
var bases: Array = [Vector3.ZERO, Vector3.ZERO]
var base_coords: Array = [Vector2i.ZERO, Vector2i.ZERO]
var score: Array = [0, 0]
## Per team: {"pos": Vector3, "home": bool, "carrier": player id or 0, "dropped": seconds lying}
var flags: Array = [{}, {}]

func on_map_ready() -> void:
	# The two ends of the island along X, a few rings in from the mountain rim
	var g = grid()
	var reach = g.grid_radius * HexTile.HEX_RADIUS * 1.732 * 0.62
	base_coords[0] = _land_near(Vector3(-reach, 0, 0))
	base_coords[1] = _land_near(Vector3(reach, 0, 0))
	for t in 2:
		bases[t] = tile_top_pos(base_coords[t])
		flags[t] = {"pos": bases[t], "home": true, "carrier": 0, "dropped": 0.0}

func _deal_teams() -> void:
	var ids = server.players.keys()
	ids.sort()
	var counts = [0, 0]
	for id in ids:
		if teams.has(id):
			counts[teams[id]] += 1
	for id in ids:
		if not teams.has(id):
			var t = 0 if counts[0] <= counts[1] else 1
			var mate = _party_mate_team(id)  # friends who queued together play together
			if mate >= 0:
				t = mate
			teams[id] = t
			counts[t] += 1

## The team of this player's party mate (matchmade games: the roster's "party"), -1 if none yet
func _party_mate_team(player_id: int) -> int:
	var party = int(server.accounts.get(player_id, {}).get("party", 0))
	if party == 0:
		return -1
	for other in server.accounts:
		if other != player_id and int(server.accounts[other].get("party", 0)) == party and teams.has(other):
			return int(teams[other])
	return -1

func team_of(player_id: int) -> int:
	if not teams.has(player_id):
		_deal_teams()
	return int(teams.get(player_id, -1))

## Around the team's base: the base tile and its neighbours, one per player
func start_position(player_id: int) -> Vector3:
	return respawn_position(player_id)

func respawn_position(player_id: int) -> Vector3:
	var t = team_of(player_id)
	if t < 0:
		return Vector3.ZERO
	var g = grid()
	var spots: Array = [base_coords[t]]
	for dir in HexTile.EDGE_DIRECTIONS:
		var c = base_coords[t] + dir
		var tile: HexTile = g.get_tile(c)
		if tile and tile.is_playable() and not tile.is_water() and tile.biome_type != HexTile.BiomeType.MOUNTAIN:
			spots.append(c)
	var c2: Vector2i = spots[abs(player_id) % spots.size()]
	return tile_top_pos(c2) + Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6))

func on_match_start() -> void:
	_deal_teams()
	score = [0, 0]
	for id in teams:
		var e = world().players.get(id)
		if e:
			e.set_meta("team", teams[id])

func on_player_died(player_id: int, _killer) -> void:
	for t in 2:
		if flags[t].carrier == player_id:
			_drop(t)

func _drop(t: int) -> void:
	var carrier = world().players.get(flags[t].carrier)
	if carrier and is_instance_valid(carrier):
		carrier.remove_meta("flag_carrier")
		flags[t].pos = carrier.global_position
	flags[t].carrier = 0
	flags[t].dropped = 0.0
	announce("%s flag dropped", [GameModes.TEAM_NAMES[t]], GameModes.TEAM_COLORS[t])

func _send_home(t: int) -> void:
	flags[t].pos = bases[t]
	flags[t].home = true
	flags[t].carrier = 0
	flags[t].dropped = 0.0

func _process(delta: float) -> void:
	if not server or not server.game_started or server.match_over:
		return
	for id in server.players:
		var e = world().players.get(id)
		if e and is_instance_valid(e) and not e.has_meta("team"):
			e.set_meta("team", team_of(id))  # late joiners
	for t in 2:
		var f: Dictionary = flags[t]
		if f.carrier != 0:
			var carrier = alive_entity(f.carrier)
			if carrier == null:
				_drop(t)
				continue
			f.pos = carrier.global_position
			# Home with it while our own flag is home: a capture
			var own = team_of(f.carrier)
			if flags[own].home and _flat(carrier.global_position, bases[own]) < CAPTURE:
				score[own] += 1
				carrier.remove_meta("flag_carrier")
				announce("%s scores!  %d : %d", [GameModes.TEAM_NAMES[own], score[0], score[1]], GameModes.TEAM_COLORS[own])
				_send_home(t)
			continue
		if not f.home:
			f.dropped += delta
			if f.dropped >= RETURN_TIME:
				_send_home(t)
				announce("%s flag is back home", [GameModes.TEAM_NAMES[t]], GameModes.TEAM_COLORS[t])
				continue
		for id in server.players:
			var e = alive_entity(id)
			if e == null or _flat(e.global_position, f.pos) > TOUCH or abs(e.global_position.y - f.pos.y) > 2.5:
				continue
			var team = team_of(id)
			if team == t:
				if not f.home:
					_send_home(t)
					announce("%s flag returned", [GameModes.TEAM_NAMES[t]], GameModes.TEAM_COLORS[t])
					break
				continue  # our flag at home: nothing to do with it
			# The enemy takes it (one flag at a time)
			if not e.has_meta("flag_carrier"):
				f.carrier = id
				f.home = false
				e.set_meta("flag_carrier", t)
				announce("%s took the %s flag", [_name(id), GameModes.TEAM_NAMES[t]], GameModes.TEAM_COLORS[team])
				break

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _name(id: int) -> String:
	return String(server.lobby_manager.players_names.get(id, "Player_%d" % id))

func check_end() -> Dictionary:
	for t in 2:
		if score[t] >= CAPTURES_TO_WIN:
			return {"winner_id": -1 - t, "winner_name": GameModes.TEAM_NAMES[t]}
	if server.match_time() >= TIME_LIMIT:
		if score[0] == score[1]:
			return {"winner_id": 0, "winner_name": ""}
		var t = 0 if score[0] > score[1] else 1
		return {"winner_id": -1 - t, "winner_name": GameModes.TEAM_NAMES[t]}
	return {}

func state_for(_viewer_id: int) -> Dictionary:
	var s = base_state()
	var fl = []
	for t in 2:
		var f: Dictionary = flags[t]
		fl.append([f.pos.x, f.pos.y, f.pos.z, f.home, f.carrier])
	s["teams"] = teams.duplicate()
	s["score"] = score.duplicate()
	s["flags"] = fl
	s["bases"] = [[bases[0].x, bases[0].y, bases[0].z], [bases[1].x, bases[1].y, bases[1].z]]
	s["goal"] = CAPTURES_TO_WIN
	s["limit"] = TIME_LIMIT
	return s
