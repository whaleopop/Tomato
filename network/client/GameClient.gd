## Main game client
extends Node
class_name GameClient

signal connected_to_server
signal connection_failed
signal disconnected_from_server

const PORT: int = 7777

var peer: ENetMultiplayerPeer = null
var client_world: ClientWorld = null
var local_player_id: int = -1
var is_connected: bool = false
var pending_map_seed: int = 0  # Store map seed until GameScene is ready

func _ready():
	# Don't create ClientWorld here - it will be created when GameScene loads
	# ClientWorld needs to be in the 3D scene, which doesn't exist yet during connection
	client_world = null

	# Connect multiplayer signals
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func ensure_client_world():
	# Simply return existing ClientWorld (created by GameSceneController)
	# Don't try to create it here - GameSceneController handles creation
	if not client_world:
		print("[GameClient] ClientWorld not ready yet (GameScene may still be loading)")
		return null

	return client_world

func connect_to_server(ip: String = "127.0.0.1", port: int = PORT):
	print("[GameClient] Attempting to connect to server %s:%d..." % [ip, port])
	
	if is_connected:
		print("[GameClient] ERROR: Already connected to server!")
		return false
	
	print("[GameClient] Creating ENet client peer...")
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	
	if error != OK:
		push_error("[GameClient] ERROR: Failed to create client: %d" % error)
		print("[GameClient] Error code: %d" % error)
		connection_failed.emit()
		return false
	
	print("[GameClient] Client peer created, setting multiplayer peer...")
	multiplayer.multiplayer_peer = peer
	print("[GameClient] ✓ Connection request sent to %s:%d, waiting for response..." % [ip, port])
	return true

func disconnect_from_server():
	print("[GameClient] Disconnecting from server...")
	
	if not is_connected:
		print("[GameClient] Not connected, nothing to disconnect")
		return
	
	if peer:
		print("[GameClient] Closing peer connection...")
		peer.close()
		peer = null
	
	is_connected = false
	disconnected_from_server.emit()
	print("[GameClient] ✓ Disconnected from server")

func send_input(input_data: Dictionary):
	if not is_connected:
		return

	if not input_data is Dictionary:
		print("[GameClient] ERROR: input_data is not a Dictionary")
		return

	# Send input via NetworkManager (consistent RPC path)
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.send_player_input(input_data)

func _on_connected_to_server():
	print("[GameClient] ✓ Successfully connected to server!")
	is_connected = true
	local_player_id = multiplayer.get_unique_id()
	print("[GameClient] Assigned player ID: %d" % local_player_id)
	connected_to_server.emit()
	print("[GameClient] Connection established, ready to play")

func _on_connection_failed():
	print("[GameClient] ✗ Connection failed!")
	is_connected = false
	connection_failed.emit()
	print("[GameClient] Possible reasons: server not running, wrong IP/port, network issues")

func _on_server_disconnected():
	print("[GameClient] ✗ Server disconnected!")
	is_connected = false
	disconnected_from_server.emit()
	print("[GameClient] Connection lost with server")

# RPC methods - must match server signatures exactly
@rpc("authority", "reliable")
func spawn_player(player_id: int, position: Vector3):
	print("[GameClient] RPC: spawn_player called with player_id=%d, position=%s" % [player_id, position])

	# Wait for ClientWorld to be created by GameSceneController
	if not client_world:
		print("[GameClient] ClientWorld not ready, ignoring spawn_player RPC (will be handled by world state sync)")
		return

	client_world.spawn_player(player_id, position)

@rpc("authority", "reliable")
func update_world_state(state: Dictionary):
	if not state is Dictionary:
		print("[GameClient] ERROR: state is not a Dictionary, got type: %s" % typeof(state))
		return

	# Wait for ClientWorld to be created by GameSceneController
	if not client_world:
		# Silently ignore - next state update will come soon
		return

	client_world.apply_world_state(state)

# RPC to receive map seed from server
@rpc("authority", "reliable")
func receive_map_seed(seed_value: int):
	print("[GameClient] Received map seed: %d" % seed_value)

	# Check if ClientWorld exists (created by GameSceneController)
	if client_world:
		# GameScene ready - generate map immediately (in background)
		print("[GameClient] ClientWorld ready, starting map generation...")
		# Don't await here - RPC handlers should return quickly
		# generate_map_with_seed has duplicate prevention
		client_world.generate_map_with_seed(seed_value)
	else:
		# GameScene not ready - save seed for GameSceneController to apply later
		print("[GameClient] ClientWorld not ready, storing map seed for later")
		pending_map_seed = seed_value

# This RPC method exists on server, so we need it here too for checksum
# But it should never be called on client (only server receives input)
@rpc("any_peer", "reliable")
func receive_player_input(_input_data: Dictionary):
	# This should only be called on server, not on client
	if not multiplayer.is_server():
		print("[GameClient] WARNING: receive_player_input RPC called on client (should only be called on server)")
	pass
