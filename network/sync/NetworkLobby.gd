## Network synchronization for lobby - handles RPC for spawn selection and ready state
extends Node
class_name NetworkLobby

signal lobby_state_updated(state: Dictionary)
signal spawn_selection_result(success: bool, coords: Vector2i)
signal countdown_update(seconds: int)
signal match_starting

var is_server: bool = false
var lobby_manager: LobbyManager = null

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

# === Server -> Client RPCs ===

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
func _receive_match_start():
	match_starting.emit()

@rpc("authority", "call_remote", "reliable")
func _receive_map_data(map_data: Dictionary):
	# Store map data for spawn selection UI
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

func _on_match_started():
	_receive_match_start.rpc()

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
				"height": tile.height
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
