## Server-side lobby management - handles ready state and spawn selection
extends Node
class_name LobbyManager

signal player_ready_changed(player_id: int, is_ready: bool)
signal all_players_ready
signal countdown_started(seconds: int)
signal countdown_tick(seconds_remaining: int)
signal match_started
signal spawn_selected(player_id: int, hex_coords: Vector2i)

enum LobbyState { WAITING, SELECTING_SPAWN, COUNTDOWN, STARTED }

var state: LobbyState = LobbyState.WAITING
var players_ready: Dictionary = {}  # player_id -> bool
var players_spawn: Dictionary = {}  # player_id -> Vector2i (hex coords)
var players_names: Dictionary = {}  # player_id -> String (player nickname)
var players_characters: Dictionary = {}  # player_id -> String (character class name)
var players_tokens: Dictionary = {}  # player_id -> client token (NetworkManager.client_token)
var reserved_spawns: Dictionary = {}  # Vector2i -> player_id (reserved spawn points)
var available_spawns: Array[Vector2i] = []  # Available spawn hex coordinates

var countdown_timer: float = 0.0
var countdown_duration: int = 5
var _last_countdown_second: int = -1
var min_players_to_start: int = 1  # For testing, normally 2+

const SPAWN_EXCLUSION_RADIUS: int = 4  # Minimum hex distance between spawn points

func _ready():
	set_process(false)

func _process(delta: float):
	if state == LobbyState.COUNTDOWN:
		countdown_timer -= delta
		var seconds_left = ceili(countdown_timer)
		# Only when the displayed second changes (it is replicated with a reliable RPC)
		if seconds_left != _last_countdown_second and seconds_left > 0:
			_last_countdown_second = seconds_left
			countdown_tick.emit(seconds_left)

		if countdown_timer <= 0:
			_start_match()

func setup_available_spawns(hex_grid: HexGrid):
	available_spawns.clear()

	# Same rule as the map itself: no water, no mountains, nothing destroyed
	for coords in hex_grid.tiles.keys():
		var tile = hex_grid.get_tile(coords)
		if tile and not tile.is_destroyed and tile.can_spawn:
			available_spawns.append(coords)

	print("[LobbyManager] %d spawn points available" % available_spawns.size())

func add_player(player_id: int, player_name: String = ""):
	if players_ready.has(player_id):
		return  # Already in the lobby (keeps ready state / spawn)
	players_ready[player_id] = false
	players_spawn[player_id] = Vector2i(-9999, -9999)  # Invalid coords
	players_names[player_id] = player_name if player_name != "" else "Player_%d" % player_id
	players_characters[player_id] = ""
	print("[LobbyManager] Player %d (%s) joined lobby" % [player_id, players_names[player_id]])
	# A newcomer isn't ready: a running countdown stops (else they'd spawn with no character)
	if state == LobbyState.COUNTDOWN:
		_check_ready_state()
		player_ready_changed.emit(player_id, false)

func set_player_name(player_id: int, player_name: String):
	if players_ready.has(player_id):
		players_names[player_id] = player_name
		print("[LobbyManager] Player %d name set to: %s" % [player_id, player_name])

func set_player_character(player_id: int, character_name: String):
	if players_ready.has(player_id):
		players_characters[player_id] = character_name
		print("[LobbyManager] Player %d character set to: %s" % [player_id, character_name])

func get_player_character(player_id: int) -> String:
	return players_characters.get(player_id, "")

## The client's per-run identity (NetworkManager.client_token): recognises rejoining players
func set_player_token(player_id: int, token: String):
	if players_ready.has(player_id):
		players_tokens[player_id] = token

func get_player_token(player_id: int) -> String:
	return players_tokens.get(player_id, "")

func remove_player(player_id: int):
	# Free up reserved spawn
	if players_spawn.has(player_id):
		var spawn_coords = players_spawn[player_id]
		if reserved_spawns.has(spawn_coords) and reserved_spawns[spawn_coords] == player_id:
			_unreserve_spawn_area(spawn_coords)

	players_ready.erase(player_id)
	players_spawn.erase(player_id)
	players_names.erase(player_id)
	players_characters.erase(player_id)
	players_tokens.erase(player_id)
	print("[LobbyManager] Player %d left lobby" % player_id)

	# Check if we need to cancel countdown
	if state == LobbyState.COUNTDOWN:
		_check_ready_state()

func set_player_ready(player_id: int, is_ready: bool):
	if not players_ready.has(player_id):
		return

	# Player needs valid spawn to be ready
	if is_ready and not _has_valid_spawn(player_id):
		print("[LobbyManager] Player %d cannot be ready without spawn selection" % player_id)
		return

	players_ready[player_id] = is_ready
	print("[LobbyManager] Player %d ready: %s" % [player_id, is_ready])
	# Cancel / start the countdown BEFORE the state is broadcast (the signal broadcasts it),
	# otherwise everyone keeps seeing "Match starting in N..." after someone un-readies
	_check_ready_state()
	player_ready_changed.emit(player_id, is_ready)

func _has_valid_spawn(player_id: int) -> bool:
	if not players_spawn.has(player_id):
		return false
	var coords = players_spawn[player_id]
	return coords.x != -9999 and coords.y != -9999

func select_spawn(player_id: int, hex_coords: Vector2i) -> bool:
	if not players_ready.has(player_id):
		return false

	# Check if spawn is available (areas we reserved ourselves don't count)
	if not _is_spawn_available(hex_coords, player_id):
		print("[LobbyManager] Spawn %s not available for player %d" % [hex_coords, player_id])
		return false

	# Free previous spawn if any
	var old_coords = players_spawn.get(player_id, Vector2i(-9999, -9999))
	if old_coords.x != -9999:
		_unreserve_spawn_area(old_coords)

	# Reserve new spawn
	players_spawn[player_id] = hex_coords
	_reserve_spawn_area(hex_coords, player_id)

	spawn_selected.emit(player_id, hex_coords)
	print("[LobbyManager] Player %d selected spawn at %s" % [player_id, hex_coords])
	return true

func _is_spawn_available(coords: Vector2i, player_id: int = -1) -> bool:
	if coords not in available_spawns:
		return false

	# Reserved (or too close to) someone else's spawn
	if reserved_spawns.has(coords) and reserved_spawns[coords] != player_id:
		return false

	return true

func _reserve_spawn_area(center: Vector2i, player_id: int):
	reserved_spawns[center] = player_id

	# Reserve neighbors within exclusion radius
	for coords in available_spawns:
		var distance = _hex_distance(center, coords)
		if distance > 0 and distance <= SPAWN_EXCLUSION_RADIUS:
			if not reserved_spawns.has(coords):
				reserved_spawns[coords] = player_id

func _unreserve_spawn_area(center: Vector2i):
	var player_id = reserved_spawns.get(center, -1)
	if player_id == -1:
		return

	# Remove all reservations for this player
	var to_remove: Array[Vector2i] = []
	for coords in reserved_spawns.keys():
		if reserved_spawns[coords] == player_id:
			to_remove.append(coords)

	for coords in to_remove:
		reserved_spawns.erase(coords)

func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	return (abs(a.x - b.x) + abs(a.x + a.y - b.x - b.y) + abs(a.y - b.y)) / 2

func _check_ready_state():
	if state == LobbyState.STARTED:
		return
	var ready_count = 0
	var total_count = players_ready.size()

	for is_ready in players_ready.values():
		if is_ready:
			ready_count += 1

	print("[LobbyManager] Ready: %d/%d" % [ready_count, total_count])

	if ready_count >= min_players_to_start and ready_count == total_count:
		if state != LobbyState.COUNTDOWN:
			_start_countdown()
	else:
		if state == LobbyState.COUNTDOWN:
			_cancel_countdown()

func _start_countdown():
	state = LobbyState.COUNTDOWN
	countdown_timer = float(countdown_duration)
	_last_countdown_second = -1
	set_process(true)
	countdown_started.emit(countdown_duration)
	all_players_ready.emit()
	print("[LobbyManager] Countdown started: %d seconds" % countdown_duration)

func _cancel_countdown():
	state = LobbyState.WAITING
	set_process(false)
	print("[LobbyManager] Countdown cancelled")

func _start_match():
	state = LobbyState.STARTED
	set_process(false)
	match_started.emit()
	print("[LobbyManager] Match started!")

func get_spawn_position(player_id: int, hex_grid: HexGrid) -> Vector3:
	if not players_spawn.has(player_id):
		return Vector3.ZERO

	var coords = players_spawn[player_id]
	if coords.x == -9999:
		return Vector3.ZERO

	var world_pos = hex_grid.hex_to_world(coords)
	var tile = hex_grid.get_tile(coords)
	if tile:
		world_pos.y = (tile.height * HexTile.HEX_HEIGHT) + HexTile.HEX_HEIGHT + 1.0
	else:
		world_pos.y = 2.0

	return world_pos

func get_all_reserved_spawns() -> Dictionary:
	return reserved_spawns.duplicate()

func get_player_spawn(player_id: int) -> Vector2i:
	return players_spawn.get(player_id, Vector2i(-9999, -9999))

func is_all_ready() -> bool:
	if players_ready.is_empty():
		return false
	for is_ready in players_ready.values():
		if not is_ready:
			return false
	return true

func get_lobby_state() -> Dictionary:
	return {
		"state": state,
		"players_ready": players_ready.duplicate(),
		"players_spawn": players_spawn.duplicate(),
		"players_names": players_names.duplicate(),
		"reserved_spawns": reserved_spawns.keys(),
		"reserved_by": reserved_spawns.duplicate(),
		"countdown": ceili(countdown_timer) if state == LobbyState.COUNTDOWN else 0
	}

## Returns data needed for spawn cutscene
func get_cutscene_data(hex_grid: HexGrid) -> Dictionary:
	var spawn_positions: Dictionary = {}
	for player_id in players_spawn.keys():
		spawn_positions[player_id] = get_spawn_position(player_id, hex_grid)

	return {
		"spawn_positions": spawn_positions,
		"player_characters": players_characters.duplicate(),
		"players_names": players_names.duplicate()
	}
