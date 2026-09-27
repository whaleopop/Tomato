## Network synchronization for lobby - handles RPC for spawn selection and ready state
extends Node
class_name NetworkLobby

signal lobby_state_updated(state: Dictionary)
signal spawn_selection_result(success: bool, coords: Vector2i)
signal countdown_update(seconds: int)
signal match_starting(late_join: bool)

var is_server: bool = false
var lobby_manager: LobbyManager = null
var last_map_data: Dictionary = {}  # Client: last map received for the spawn menu

func _ready():
	pass

func setup_server(p_lobby_manager: LobbyManager):
	if is_server and lobby_manager == p_lobby_manager:
		return  # Already setup with same manager

	is_server = true
	lobby_manager = p_lobby_manager

	# Connect signals (check if not already connected)
	if not lobby_manager.player_ready_changed.is_connected(_on_player_ready_changed):
		lobby_manager.player_ready_changed.connect(_on_player_ready_changed)
	if not lobby_manager.spawn_selected.is_connected(_on_spawn_selected):
		lobby_manager.spawn_selected.connect(_on_spawn_selected)
	if not lobby_manager.countdown_tick.is_connected(_on_countdown_tick):
		lobby_manager.countdown_tick.connect(_on_countdown_tick)
	if not lobby_manager.match_started.is_connected(_on_match_started):
		lobby_manager.match_started.connect(_on_match_started)

# === Client -> Server RPCs ===

@rpc("any_peer", "call_remote", "reliable")
func request_spawn_selection(hex_q: int, hex_r: int):
	if not is_server or not lobby_manager:
		return

	var player_id = multiplayer.get_remote_sender_id()
	var coords = Vector2i(hex_q, hex_r)

	var success = lobby_manager.select_spawn(player_id, coords)

	# Send result back to player
	_send_spawn_result.rpc_id(player_id, success, hex_q, hex_r)

	# Broadcast updated state to all
	if success:
		_broadcast_lobby_state()

@rpc("any_peer", "call_remote", "reliable")
func request_ready_state(ready: bool):
	if not is_server or not lobby_manager:
		return

	var player_id = multiplayer.get_remote_sender_id()
	lobby_manager.set_player_ready(player_id, ready)

	# State will be broadcast via signal handler

@rpc("any_peer", "call_remote", "reliable")
func request_lobby_state():
	if not is_server or not lobby_manager:
		return

	var player_id = multiplayer.get_remote_sender_id()
	var state = lobby_manager.get_lobby_state()
	_receive_lobby_state.rpc_id(player_id, state)

	# Joined while a match is running: send them straight into the game - if they were let in
	# (spawn_late_joiner ran when their character arrived; otherwise they got refused)
	if lobby_manager.state == LobbyManager.LobbyState.STARTED:
		var game_server = get_node_or_null("/root/NetworkManager/GameServer")
		if game_server and game_server.server_world.players.has(player_id):
			_receive_match_start.rpc_id(player_id, true)

@rpc("any_peer", "call_remote", "reliable")
func request_map_data():
	if not is_server:
		return

	var player_id = multiplayer.get_remote_sender_id()
	var game_server = get_node_or_null("/root/NetworkManager/GameServer")
	if game_server and game_server.server_world and game_server.server_world.hex_grid:
		send_map_data_to_player(player_id, game_server.server_world.hex_grid)

@rpc("any_peer", "call_remote", "reliable")
func set_player_name(player_name: String):
	if not is_server or not lobby_manager:
		return

	var player_id = multiplayer.get_remote_sender_id()
	lobby_manager.set_player_name(player_id, player_name)
	_broadcast_lobby_state()

@rpc("any_peer", "call_remote", "reliable")
func set_player_character(character_name: String, client_token: String):
	if not is_server or not lobby_manager:
		return

	var player_id = multiplayer.get_remote_sender_id()
	lobby_manager.set_player_character(player_id, character_name)
	lobby_manager.set_player_token(player_id, client_token)
	print("[NetworkLobby] Player %d selected character: %s" % [player_id, character_name])

	# Late joiner: now that we know the character we can spawn them
	var game_server = get_node_or_null("/root/NetworkManager/GameServer")
	if game_server and game_server.game_started:
		game_server.spawn_late_joiner(player_id)

# === Server -> Client RPCs ===

## The server won't let us into the running match (shown on the main menu after it drops us)
@rpc("authority", "call_remote", "reliable")
func _receive_join_refused(reason: String):
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.refusal_reason = reason
	print("[NetworkLobby] Join refused: %s" % reason)

@rpc("authority", "call_remote", "reliable")
func _send_spawn_result(success: bool, hex_q: int, hex_r: int):
	spawn_selection_result.emit(success, Vector2i(hex_q, hex_r))

@rpc("authority", "call_remote", "reliable")
func _receive_lobby_state(state: Dictionary):
	lobby_state_updated.emit(state)

@rpc("authority", "call_remote", "reliable")
func _receive_countdown(seconds: int):
	countdown_update.emit(seconds)

@rpc("authority", "call_remote", "reliable")
func _receive_match_start(late_join: bool):
	match_starting.emit(late_join)

@rpc("authority", "call_remote", "reliable")
func _receive_cutscene_data(spawn_positions: Dictionary, player_characters: Dictionary):
	print("[NetworkLobby] Received cutscene data for %d players" % spawn_positions.size())
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.cutscene_spawn_positions = spawn_positions
		game_manager.cutscene_player_characters = player_characters
		print("[NetworkLobby] Cutscene data stored in GameManager")

@rpc("authority", "call_remote", "reliable")
func _receive_map_data(map_data: Dictionary):
	# Keep it: the spawn menu may not exist yet when this arrives
	last_map_data = map_data
	var spawn_menu = get_tree().get_first_node_in_group("spawn_menu")
	if spawn_menu and spawn_menu is SpawnSelectMenu:
		var reserved = map_data.get("reserved_spawns", [])
		var grid_data = map_data.get("hex_grid", {})
		var player_id = multiplayer.get_unique_id()
		spawn_menu.setup(grid_data, reserved, player_id)

# === Server-side signal handlers ===

func _on_player_ready_changed(_player_id: int, _is_ready: bool):
	_broadcast_lobby_state()

func _on_spawn_selected(_player_id: int, _coords: Vector2i):
	_broadcast_lobby_state()

func _on_countdown_tick(seconds: int):
	_receive_countdown.rpc(seconds)
	# Also emit locally for host UI
	countdown_update.emit(seconds)

func _on_match_started():
	# Send cutscene data to clients before match start
	_send_cutscene_data_to_clients()

	_receive_match_start.rpc(false)
	# Also emit locally for host
	match_starting.emit(false)

func _send_cutscene_data_to_clients():
	if not is_server or not lobby_manager:
		return

	var game_server = get_node_or_null("/root/NetworkManager/GameServer")
	if not game_server or not game_server.server_world:
		return

	var hex_grid = game_server.server_world.hex_grid
	if not hex_grid:
		return

	# Collect spawn positions and characters
	var spawn_positions: Dictionary = {}
	var player_characters: Dictionary = {}

	for player_id in lobby_manager.players_spawn.keys():
		spawn_positions[player_id] = lobby_manager.get_spawn_position(player_id, hex_grid)
		player_characters[player_id] = lobby_manager.get_player_character(player_id)

	# Send to all clients
	_receive_cutscene_data.rpc(spawn_positions, player_characters)

func _broadcast_lobby_state():
	if not lobby_manager:
		return

	var state = lobby_manager.get_lobby_state()
	_receive_lobby_state.rpc(state)

	# Also emit locally for server UI
	lobby_state_updated.emit(state)

# === Server utility functions ===

func send_map_data_to_player(player_id: int, hex_grid: HexGrid):
	if not is_server:
		return

	if not hex_grid:
		return  # Map still generating: GameServer sends it once it is ready

	var map_data = {
		"hex_grid": _serialize_hex_grid(hex_grid),
		"reserved_spawns": lobby_manager.get_all_reserved_spawns().keys() if lobby_manager else []
	}

	_receive_map_data.rpc_id(player_id, map_data)

func send_map_data_to_all(hex_grid: HexGrid):
	if not is_server:
		return

	var map_data = {
		"hex_grid": _serialize_hex_grid(hex_grid),
		"reserved_spawns": lobby_manager.get_all_reserved_spawns().keys() if lobby_manager else []
	}

	_receive_map_data.rpc(map_data)

func _serialize_hex_grid(hex_grid: HexGrid) -> Dictionary:
	var result: Dictionary = {}

	for coords in hex_grid.tiles.keys():
		var tile = hex_grid.get_tile(coords)
		if tile and not tile.is_destroyed:
			result[coords] = {
				"biome": tile.biome_type,
				"height": tile.height,
				"spawnable": tile.can_spawn
			}

	return result

# === Client-side functions ===

func client_select_spawn(coords: Vector2i):
	if is_server:
		# Local server player
		if lobby_manager:
			var success = lobby_manager.select_spawn(1, coords)  # Host is always ID 1
			spawn_selection_result.emit(success, coords)
			_broadcast_lobby_state()
	else:
		request_spawn_selection.rpc_id(1, coords.x, coords.y)

func client_set_ready(ready: bool):
	if is_server:
		# Local server player
		if lobby_manager:
			lobby_manager.set_player_ready(1, ready)
	else:
		request_ready_state.rpc_id(1, ready)

func client_request_state():
	if is_server:
		# Local server player - emit directly
		if lobby_manager:
			lobby_state_updated.emit(lobby_manager.get_lobby_state())
	else:
		request_lobby_state.rpc_id(1)

func client_request_map_data():
	if is_server:
		# Local server player - map is already shown via SpawnSelectController
		pass
	else:
		request_map_data.rpc_id(1)

func client_set_name(player_name: String):
	if is_server:
		# Local server player
		if lobby_manager:
			lobby_manager.set_player_name(1, player_name)
			_broadcast_lobby_state()
	else:
		set_player_name.rpc_id(1, player_name)

func client_set_character(character_name: String):
	var network_manager = get_node_or_null("/root/NetworkManager")
	var token: String = network_manager.client_token if network_manager else ""
	if is_server:
		# Local server player
		if lobby_manager:
			lobby_manager.set_player_character(1, character_name)
			lobby_manager.set_player_token(1, token)
	else:
		set_player_character.rpc_id(1, character_name, token)
