## The server's rules of a match mode (GameModes): where players start and come back, what a death
## means, who wins, and the state every peer's ModeView shows (state_for, sent with the world state
## as "mode"). GameServer owns one (make) and calls the hooks; this base is the battle royale.
extends Node
class_name ModeRules

var server: GameServer = null
var mode: String = GameModes.BR
var _event_id: int = 0
var _event: Array = []          # [id, text, args, color]: the last announcement (HUD alert)

static func make(p_mode: String) -> ModeRules:
	var rules: ModeRules
	match p_mode:
		GameModes.SURVIVORS:
			rules = SurvivorsRules.new()
		GameModes.CTF:
			rules = CtfRules.new()
		GameModes.KOTH:
			rules = KothRules.new()
		_:
			rules = ModeRules.new()
	rules.mode = p_mode if GameModes.INFO.has(p_mode) else GameModes.BR
	rules.name = "ModeRules"
	return rules

func world() -> ServerWorld:
	return server.server_world if server else null

func grid() -> HexGrid:
	return world().hex_grid if world() else null

## The map is there (bases, the hill...)
func on_map_ready() -> void:
	pass

## Where the mode puts a player at the start instead of the landing spot (Vector3.ZERO: the spot)
func start_position(_player_id: int) -> Vector3:
	return Vector3.ZERO

func on_match_start() -> void:
	pass

## A hero went down (killer: the entity, or null)
func on_player_died(_player_id: int, _killer) -> void:
	pass

## Where a fallen hero comes back (respawning modes)
func respawn_position(_player_id: int) -> Vector3:
	return _random_land_spot()

func team_of(_player_id: int) -> int:
	return -1

## {} while the match goes on, else {"winner_id", "winner_name"} (teams: winner_id -1 - team)
func check_end() -> Dictionary:
	var alive: Array = []
	for player_id in server._participants:
		if not server.players.has(player_id):
			continue
		var entity = world().players.get(player_id)
		if entity == null or not is_instance_valid(entity):
			alive.append(player_id)
			continue
		var health = entity.get_component("HealthComponent")
		if health == null or not health.is_dead:
			alive.append(player_id)
	if server._participants.size() < 2 or alive.size() > 1:
		return {}
	var winner_id: int = alive[0] if alive.size() == 1 else 0
	return {"winner_id": winner_id, "winner_name": server.lobby_manager.get_player_character(winner_id) if winner_id != 0 else ""}

## What one client is shown (the HUD of the mode); {} for the battle royale
func state_for(_viewer_id: int) -> Dictionary:
	return {}

## An upgrade or another choice a player sent (survivors)
func on_choice(_player_id: int, _choice: String) -> void:
	pass

func announce(text: String, args: Array = [], color: Color = Color(1, 0.85, 0.4)) -> void:
	_event_id += 1
	_event = [_event_id, text, args, color.to_html()]

func base_state() -> Dictionary:
	var names = {}
	for id in server.players:
		names[id] = String(server.lobby_manager.players_names.get(id, "Player_%d" % id))
	return {"mode": mode, "time": server.match_time(), "event": _event, "names": names}

func alive_entity(player_id: int) -> Node3D:
	var e = world().players.get(player_id) if world() else null
	if e == null or not is_instance_valid(e):
		return null
	var h = e.get_component("HealthComponent")
	return e if h and not h.is_dead else null

## Land a hero can stand on in the open: not water, a ramp or a mountain, and not a landmark's
## tile (the windmill stands on its middle: a respawn there was stuck inside it)
func _open_land(t: HexTile) -> bool:
	if t == null or not t.is_playable() or t.is_water() or t.is_ramp():
		return false
	return t.biome_type != HexTile.BiomeType.MOUNTAIN and not t.has_meta("landmark")

## A random walkable land tile's top
func _random_land_spot(near: Vector3 = Vector3.INF, min_d: float = 0.0, max_d: float = INF) -> Vector3:
	var g = grid()
	if not g:
		return Vector3(0, 3, 0)
	var keys = g.tiles.keys()
	for attempt in 80:
		var c = keys[randi() % keys.size()]
		var t: HexTile = g.get_tile(c)
		if not _open_land(t):
			continue
		var p = g.hex_to_world(c) + Vector3(0, CoverSpawner.tile_top(t) + 1.0, 0)
		if near != Vector3.INF:
			var d = Vector2(p.x - near.x, p.z - near.z).length()
			if d < min_d or d > max_d:
				continue
		return p
	return Vector3(0, 3, 0)

## The land tile nearest to a world point
func _land_near(point: Vector3) -> Vector2i:
	var g = grid()
	var best = Vector2i.ZERO
	var best_d = INF
	for c in g.tiles:
		var t: HexTile = g.get_tile(c)
		if not _open_land(t):
			continue
		var p = g.hex_to_world(c)
		var d = Vector2(p.x - point.x, p.z - point.z).length()
		if d < best_d:
			best_d = d
			best = c
	return best

func tile_top_pos(c: Vector2i) -> Vector3:
	var g = grid()
	var t = g.get_tile(c)
	return g.hex_to_world(c) + Vector3(0, CoverSpawner.tile_top(t) if t else 0.3, 0)
