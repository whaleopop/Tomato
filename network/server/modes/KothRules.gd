## King of the Hill: a platform near the middle of the island. A hero standing on it alone scores
## POINTS_PER_SECOND; two or more on it: contested, nobody scores. First to WIN_POINTS, or the most
## points when TIME_LIMIT runs out. Fallen heroes come back after GameModes' respawn delay, away
## from the hill.
extends ModeRules
class_name KothRules

const WIN_POINTS: float = 100.0
const POINTS_PER_SECOND: float = 1.0
const TIME_LIMIT: float = 480.0
const HILL_RADIUS: float = 4.6       # world units from the hill's middle (the tile and a bit)
const RESPAWN_MIN: float = 25.0
const RESPAWN_MAX: float = 45.0

var hill_coords := Vector2i.ZERO
var hill_pos := Vector3.ZERO
var points: Dictionary = {}          # player id -> float
var holder: int = 0                  # who scores now (0 nobody)
var contested: bool = false
var _last_holder: int = 0

func on_map_ready() -> void:
	hill_coords = _land_near(Vector3.ZERO)
	hill_pos = tile_top_pos(hill_coords)

func on_match_start() -> void:
	points.clear()
	for id in server.players:
		points[id] = 0.0

func respawn_position(_player_id: int) -> Vector3:
	return _random_land_spot(hill_pos, RESPAWN_MIN, RESPAWN_MAX)

func _process(delta: float) -> void:
	if not server or not server.game_started or server.match_over:
		return
	var on_hill: Array = []
	for id in server.players:
		var e = alive_entity(id)
		if e == null:
			continue
		var d = Vector2(e.global_position.x - hill_pos.x, e.global_position.z - hill_pos.z).length()
		if d < HILL_RADIUS and abs(e.global_position.y - hill_pos.y) < 3.0:
			on_hill.append(id)
	contested = on_hill.size() > 1
	holder = on_hill[0] if on_hill.size() == 1 else 0
	if holder != 0:
		points[holder] = float(points.get(holder, 0.0)) + POINTS_PER_SECOND * delta
	if holder != _last_holder and holder != 0:
		announce("%s holds the hill", [_name(holder)], Color(0.85, 0.5, 1.0))
	_last_holder = holder

func _name(id: int) -> String:
	return String(server.lobby_manager.players_names.get(id, "Player_%d" % id))

func check_end() -> Dictionary:
	var best = 0
	var best_p = -1.0
	for id in points:
		if float(points[id]) > best_p:
			best_p = float(points[id])
			best = id
	if best_p >= WIN_POINTS or (server.match_time() >= TIME_LIMIT and best_p > 0.0):
		return {"winner_id": best, "winner_name": server.lobby_manager.get_player_character(best)}
	if server.match_time() >= TIME_LIMIT:
		return {"winner_id": 0, "winner_name": ""}
	return {}

func state_for(_viewer_id: int) -> Dictionary:
	var s = base_state()
	var pts = {}
	for id in points:
		pts[id] = int(points[id])
	s["hill"] = [hill_pos.x, hill_pos.y, hill_pos.z, HILL_RADIUS]
	s["points"] = pts
	s["holder"] = holder
	s["contested"] = contested
	s["goal"] = int(WIN_POINTS)
	s["limit"] = TIME_LIMIT
	return s
