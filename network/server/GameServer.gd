## Main dedicated game server
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
var is_running: bool = false

func _ready():
	# Create server world
	server_world = ServerWorld.new()
	add_child(server_world)
	
	# Create tick system
	tick_system = TickSystem.new()
	tick_system.set_server(self)
	add_child(tick_system)
	
	# Connect signals
	server_world.player_spawned.connect(_on_player_spawned)

func start_server(port: int = PORT):
	print("[GameServer] Starting server on port %d..." % port)
	
	if is_running:
		print("[GameServer] ERROR: Server is already running!")
		return false
	
	print("[GameServer] Creating ENet peer...")
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		push_error("[GameServer] ERROR: Failed to create server: %d" % error)
		print("[GameServer] Error code: %d" % error)
		return false
	
	print("[GameServer] Server created successfully, setting multiplayer peer...")
	multiplayer.multiplayer_peer = peer
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	is_running = true
	server_started.emit()
	
	print("[GameServer] ✓ Server started successfully on port %d (max players: %d)" % [port, MAX_PLAYERS])
	return true

func stop_server():
	print("[GameServer] Stopping server...")
	
	if not is_running:
		print("[GameServer] Server is not running, nothing to stop")
		return
	
	if peer:
		print("[GameServer] Closing peer connection...")
		peer.close()
		peer = null
	
	print("[GameServer] Clearing players (%d players)" % players.size())
	players.clear()
	is_running = false
	server_stopped.emit()
	
	print("[GameServer] ✓ Server stopped")

func _on_peer_connected(player_id: int):
	print("[GameServer] ===== Player connected: %d =====" % player_id)

	# Check for duplicate connection
	if players.has(player_id):
		print("[GameServer] WARNING: Player %d already in players dict, ignoring duplicate" % player_id)
		return

	player_connected.emit(player_id)

	# Create server player
	print("[GameServer] Creating ServerPlayer for player %d..." % player_id)
	var server_player = ServerPlayer.new()
	server_player.player_id = player_id
	players[player_id] = server_player
	add_child(server_player)

	# Send map seed to client FIRST (before spawning)
	_send_map_seed_to_client(player_id)

	# Use call_deferred to avoid race conditions with async operations
	call_deferred("_spawn_player_deferred", player_id)

func _spawn_player_deferred(player_id: int):
	# Verify player still exists (may have disconnected)
	if not players.has(player_id):
		print("[GameServer] Player %d disconnected before spawn, skipping" % player_id)
		return

	# Spawn player in world
	print("[GameServer] Spawning player %d in world..." % player_id)
	var spawn_pos = server_world.spawn_player(player_id)
	print("[GameServer] ✓ Player %d fully connected and spawned at %s" % [player_id, spawn_pos])

func _on_peer_disconnected(player_id: int):
	print("[GameServer] Player disconnected: %d" % player_id)
	player_disconnected.emit(player_id)
	
	# Remove player from world
	if players.has(player_id):
		print("[GameServer] Removing player %d from world..." % player_id)
		var server_player = players[player_id]
		server_world.remove_player(player_id)
		server_player.queue_free()
		players.erase(player_id)
		print("[GameServer] ✓ Player %d removed (remaining players: %d)" % [player_id, players.size()])
	else:
		print("[GameServer] WARNING: Player %d not found in players dictionary" % player_id)

func _on_player_spawned(player_id: int, position: Vector3):
	print("[GameServer] Player %d spawned at position %s, notifying clients..." % [player_id, position])
	# Notify all clients about new player
	if not multiplayer.multiplayer_peer:
		print("[GameServer] WARNING: No multiplayer peer, cannot send spawn notification")
		return
	
	if not multiplayer.is_server():
		print("[GameServer] WARNING: Not server, cannot send spawn notification")
		return
	
	print("[GameServer] Sending RPC spawn_player(player_id=%d, position=%s)" % [player_id, position])
	# Use string-based rpc() call - this is more reliable in Godot 4
	rpc("spawn_player", player_id, position)
	print("[GameServer] ✓ Spawn notification sent for player %d" % player_id)

@rpc("any_peer", "reliable")
func receive_player_input(input_data: Dictionary):
	# SECURITY FIX: Use actual sender ID instead of trusting client-provided ID
	var sender_id = multiplayer.get_remote_sender_id()

	if not players.has(sender_id):
		print("[GameServer] WARNING: Received input from unknown player %d" % sender_id)
		return

	if not input_data is Dictionary:
		print("[GameServer] ERROR: input_data is not a Dictionary, got type: %s" % typeof(input_data))
		return

	var server_player = players[sender_id]
	server_player.process_input(input_data)

# RPC methods - must match client signatures exactly
# These are called on clients, empty implementation on server
@rpc("authority", "reliable")
func spawn_player(player_id: int, position: Vector3):
	# This should only be called on clients, not on server
	# If called on server, it means something is wrong
	if multiplayer.is_server():
		print("[GameServer] WARNING: spawn_player RPC called on server (should only be called on clients)")
	pass

@rpc("authority", "reliable")
func update_world_state(state: Dictionary):
	# This should only be called on clients, not on server
	# If called on server, it means something is wrong
	if multiplayer.is_server():
		print("[GameServer] WARNING: update_world_state RPC called on server (should only be called on clients)")
	pass

@rpc("authority", "reliable")
func receive_map_seed(_seed: int):
	# This is called on clients, not on server
	pass

func _send_map_seed_to_client(player_id: int):
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		return
	
	var map_seed = server_world.map_seed
	print("[GameServer] Sending map seed %d to player %d" % [map_seed, player_id])
	rpc_id(player_id, "receive_map_seed", map_seed)

func send_world_state(state: Dictionary):
	# Server-side method to send state to clients
	if not multiplayer.multiplayer_peer:
		print("[GameServer] WARNING: No multiplayer peer, cannot send world state")
		return
	
	if not multiplayer.is_server():
		print("[GameServer] WARNING: Not server, cannot send world state")
		return
	
	print("[GameServer] Sending RPC update_world_state(state with tick: %d, players: %d)" % [state.get("tick", 0), state.get("players", {}).size()])
	# Ensure we're passing only one argument (state Dictionary)
	# Use string-based rpc() call - this is more reliable in Godot 4
	if not state is Dictionary:
		print("[GameServer] ERROR: state is not a Dictionary!")
		return
	# IMPORTANT: Pass only the state Dictionary as a single argument
	rpc("update_world_state", state)
	print("[GameServer] ✓ World state sent to clients")
