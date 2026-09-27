## Main game server (listen server: the host plays as player 1)
extends Node
class_name GameServer

signal server_started
signal server_stopped
signal player_connected(player_id: int)
signal player_disconnected(player_id: int)

const PORT: int = 7777
const MAX_PLAYERS: int = 20

var peer: ENetMultiplayerPeer = null
var players: Dictionary = {}  # player_id -> ServerPlayer
var server_world: ServerWorld = null
var tick_system: TickSystem = null
var lobby_manager: LobbyManager = null
var network_lobby: NetworkLobby = null
var is_running: bool = false
var game_started: bool = false
var match_over: bool = false
var _participants: Dictionary = {}  # player_id -> true: everyone in the match when it started
var _end_check_timer: float = 0.0
const END_CHECK_INTERVAL: float = 0.5
# Joining a running match: only early on, and never a second time (an eliminated player going
# back to the menu and joining again used to get a fresh, full-health character)
const LATE_JOIN_WINDOW: float = 45.0
var _match_tokens: Dictionary = {}  # client token -> true: everyone who played this match
var _match_start_time: float = 0.0

func _ready():
	server_world = ServerWorld.new()
	server_world.name = "ServerWorld"
	add_child(server_world)

	tick_system = TickSystem.new()
	tick_system.name = "TickSystem"
	tick_system.set_server(self)
	add_child(tick_system)

	lobby_manager = LobbyManager.new()
	lobby_manager.name = "LobbyManager"
	add_child(lobby_manager)

	# NetworkLobby lives under NetworkManager (consistent RPC path on every peer)
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_lobby = network_manager.get_network_lobby()
		if network_lobby:
			network_lobby.setup_server(lobby_manager)

	server_world.player_spawned.connect(_on_player_spawned)
	server_world.map_ready.connect(_on_map_ready)
	lobby_manager.match_started.connect(_on_match_started)

func start_server(port: int = PORT) -> bool:
	print("[GameServer] Starting server on port %d..." % port)

	if is_running:
		print("[GameServer] ERROR: Server is already running!")
		return false

	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)

	if error != OK:
		push_error("[GameServer] Failed to create server on port %d: %d (port already in use?)" % [port, error])
		peer = null
		return false

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	is_running = true

	# The host is player 1 and joins its own lobby
	var host_player = ServerPlayer.new()
	host_player.player_id = 1
	host_player.name = "ServerPlayer_1"
	players[1] = host_player
	add_child(host_player)
	lobby_manager.add_player(1)

	server_started.emit()
	print("[GameServer] ✓ Server started on port %d (max players: %d)" % [port, MAX_PLAYERS])
	return true

func stop_server():
	if not is_running:
		return

	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)

	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	players.clear()
	is_running = false
	game_started = false
	match_over = false
	_participants.clear()
	_match_tokens.clear()
	server_stopped.emit()
	print("[GameServer] ✓ Server stopped")

func _on_map_ready():
	lobby_manager.setup_available_spawns(server_world.hex_grid)
	# Clients that connected while the map was still generating
	for player_id in multiplayer.get_peers():
		_send_map_to_peer(player_id)

func _send_map_to_peer(player_id: int):
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.send_map_info_to_client(player_id, server_world.map_seed, server_world.map_radius, server_world.destroyed_tiles)
	if network_lobby:
		network_lobby.send_map_data_to_player(player_id, server_world.hex_grid)

func _on_peer_connected(player_id: int):
	print("[GameServer] ===== Player connected: %d =====" % player_id)

	if players.has(player_id):
		return

	player_connected.emit(player_id)

	var server_player = ServerPlayer.new()
	server_player.player_id = player_id
	server_player.name = "ServerPlayer_%d" % player_id
	players[player_id] = server_player
	add_child(server_player)

	lobby_manager.add_player(player_id)

	# Otherwise it is sent from _on_map_ready
	if server_world.is_map_ready:
		_send_map_to_peer(player_id)

	# Late joiners are spawned once they picked their character (see spawn_late_joiner)

## A client joined after the match had started and told us its character
func spawn_late_joiner(player_id: int):
	if not game_started or not players.has(player_id) or server_world.players.has(player_id):
		return
	var reason = can_late_join(player_id)
	if reason != "":
		_refuse_join(player_id, reason)
		return
	print("[GameServer] Spawning late joiner %d" % player_id)
	_match_tokens[lobby_manager.get_player_token(player_id)] = true
	_participants[player_id] = true  # counts for "last one standing" from now on
	_spawn_player(player_id)

## "" if this client may still enter the running match, else why not
func can_late_join(player_id: int) -> String:
	if match_over:
		return "The match just ended - join the next one"
	var token = lobby_manager.get_player_token(player_id)
	if token != "" and _match_tokens.has(token):
		return "You already played in this match - wait for the next one"
	if Time.get_ticks_msec() / 1000.0 - _match_start_time > LATE_JOIN_WINDOW:
		return "A match is in progress - wait for the next one"
	return ""

func _refuse_join(player_id: int, reason: String):
	print("[GameServer] Refusing player %d: %s" % [player_id, reason])
	if network_lobby:
		network_lobby._receive_join_refused.rpc_id(player_id, reason)
	# Give the message a moment to arrive, then let them go
	get_tree().create_timer(0.5).timeout.connect(func():
		if peer and multiplayer.get_peers().has(player_id):
			peer.disconnect_peer(player_id)
	)

func _spawn_player(player_id: int):
	if not players.has(player_id):
		return  # Disconnected in the meantime

	var server_player = players[player_id]
	server_player.character_name = lobby_manager.get_player_character(player_id)

	var spawn_pos = Vector3.ZERO
	if server_world.hex_grid:
		spawn_pos = lobby_manager.get_spawn_position(player_id, server_world.hex_grid)

	if spawn_pos == Vector3.ZERO:
		server_world.spawn_player(player_id, server_player.character_name)
	else:
		server_world.spawn_player_at(player_id, spawn_pos, server_player.character_name)

func _on_match_started():
	print("[GameServer] ===== MATCH STARTED =====")
	game_started = true
	match_over = false
	_participants.clear()
	_match_tokens.clear()
	_match_start_time = Time.get_ticks_msec() / 1000.0
	for player_id in players.keys():
		_participants[player_id] = true
		var token = lobby_manager.get_player_token(player_id)
		if token != "":
			_match_tokens[token] = true
	server_world.start_match()

	for player_id in players.keys():
		_spawn_player(player_id)

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.notify_match_start()

func _on_peer_disconnected(player_id: int):
	print("[GameServer] Player disconnected: %d" % player_id)
	player_disconnected.emit(player_id)

	lobby_manager.remove_player(player_id)
	# Others must see them leave (and a cancelled countdown)
	if network_lobby and not game_started:
		network_lobby._broadcast_lobby_state()

	if players.has(player_id):
		var server_player = players[player_id]
		server_world.remove_player(player_id)
		server_player.queue_free()
		players.erase(player_id)

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.send_player_left(player_id)

# ---------------------------------------------------------------- match end

func _process(delta: float):
	if not game_started or match_over:
		return
	_end_check_timer += delta
	if _end_check_timer >= END_CHECK_INTERVAL:
		_end_check_timer = 0.0
		_check_match_end()

## Last one standing wins. A participant who is still connected but not spawned yet (the
## host plays the cutscene first) counts as alive; one who left counts as out.
## A solo match (practice) never ends.
func _check_match_end():
	if _participants.size() < 2:
		return
	var alive: Array = []
	for player_id in _participants:
		if not players.has(player_id):
			continue
		var entity = server_world.players.get(player_id)
		if entity == null or not is_instance_valid(entity):
			alive.append(player_id)
			continue
		var health = entity.get_component("HealthComponent")
		if health == null or not health.is_dead:
			alive.append(player_id)
	if alive.size() > 1:
		return

	match_over = true
	var winner_id: int = alive[0] if alive.size() == 1 else 0
	var winner_name = lobby_manager.get_player_character(winner_id) if winner_id != 0 else ""
	print("[GameServer] ===== MATCH OVER: winner %d (%s) =====" % [winner_id, winner_name])
	server_world.stop_match()
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.broadcast_match_end(winner_id, winner_name)

func _on_player_spawned(player_id: int, position: Vector3):
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.send_spawn_player(player_id, position)

func send_world_state(state: Dictionary):
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.send_world_state(state)

## One client's filtered view of the world (TickSystem)
func send_world_state_to(peer_id: int, state: Dictionary):
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.send_world_state_to(peer_id, state)

## Broadcast shot effect to all clients
func broadcast_shot_effect(shooter_id: int, from_pos: Vector3, to_pos: Vector3, weapon_type: int, hit: bool, show_on_host: bool = false):
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.broadcast_shot_effect(shooter_id, from_pos, to_pos, weapon_type, hit, show_on_host)
