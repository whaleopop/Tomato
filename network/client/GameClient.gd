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

func _ready():
	# Create client world and add it to the 3D scene
	client_world = ClientWorld.new()
	# Find the GameScene root (Node3D) to add ClientWorld to it
	var game_scene = get_tree().get_first_node_in_group("game_scene")
	if not game_scene:
		# Try to find GameScene node
		game_scene = get_node_or_null("/root/GameScene")
	
	if game_scene and game_scene is Node3D:
		game_scene.add_child(client_world)
		print("[GameClient] ClientWorld added to GameScene")
	else:
		# Fallback: add to NetworkManager (but it won't be in 3D space)
		add_child(client_world)
		print("[GameClient] WARNING: Could not find GameScene, ClientWorld added to NetworkManager")
	
	# Connect multiplayer signals
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

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
		print("[GameClient] WARNING: Cannot send input, not connected to server")
		return
	
	if not multiplayer.multiplayer_peer:
		print("[GameClient] WARNING: No multiplayer peer, cannot send input")
		return
	
	if not input_data is Dictionary:
		print("[GameClient] ERROR: input_data is not a Dictionary, got type: %s" % typeof(input_data))
		return
	
	# Send input to server (ID 1 is always the server)
	# NOTE: Server will identify us by multiplayer.get_remote_sender_id()
	rpc_id(1, "receive_player_input", input_data)

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
	if client_world:
		client_world.spawn_player(player_id, position)
	else:
		print("[GameClient] ERROR: client_world is null, cannot spawn player")

@rpc("authority", "reliable")
func update_world_state(state: Dictionary):
	print("[GameClient] RPC: update_world_state called with state (tick: %d, players: %d)" % [state.get("tick", 0), state.get("players", {}).size()])
	if not state is Dictionary:
		print("[GameClient] ERROR: state is not a Dictionary, got type: %s" % typeof(state))
		return
	if client_world:
		client_world.apply_world_state(state)
	else:
		print("[GameClient] ERROR: client_world is null, cannot apply world state")

# RPC to receive map seed from server
@rpc("authority", "reliable")
func receive_map_seed(seed_value: int):
	print("[GameClient] Received map seed: %d" % seed_value)
	if client_world:
		client_world.generate_map_with_seed(seed_value)
	else:
		print("[GameClient] ERROR: client_world is null, cannot generate map")

# This RPC method exists on server, so we need it here too for checksum
# But it should never be called on client (only server receives input)
@rpc("any_peer", "reliable")
func receive_player_input(_input_data: Dictionary):
	# This should only be called on server, not on client
	if not multiplayer.is_server():
		print("[GameClient] WARNING: receive_player_input RPC called on client (should only be called on server)")
	pass

