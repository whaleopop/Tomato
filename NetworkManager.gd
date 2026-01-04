## Network manager singleton
extends Node

var game_server: GameServer = null
var game_client: GameClient = null
var network_lobby: NetworkLobby = null

func _ready():
	pass

func is_server() -> bool:
	return game_server != null and game_server.is_running

func is_client() -> bool:
	return game_client != null

func get_network_lobby() -> NetworkLobby:
	return network_lobby

func _create_network_lobby():
	if network_lobby:
		return
	network_lobby = NetworkLobby.new()
	network_lobby.name = "NetworkLobby"
	add_child(network_lobby)

func _cleanup_network_lobby():
	if network_lobby:
		network_lobby.queue_free()
		network_lobby = null

func start_server(port: int = 7777):
	print("[NetworkManager] Starting server on port %d..." % port)

	# Clean up client if exists (server and client cannot coexist)
	if game_client:
		print("[NetworkManager] Cleaning up existing client before starting server...")
		stop_client()

	if game_server:
		print("[NetworkManager] ERROR: Server already exists!")
		return false

	# Create network lobby first (must be under NetworkManager for consistent RPC paths)
	_create_network_lobby()

	print("[NetworkManager] Creating GameServer instance...")
	game_server = GameServer.new()
	game_server.name = "GameServer"
	add_child(game_server)

	# Setup server's NetworkLobby after GameServer is ready
	if network_lobby and game_server.lobby_manager:
		network_lobby.setup_server(game_server.lobby_manager)

	print("[NetworkManager] Calling GameServer.start_server()...")
	var result = game_server.start_server(port)

	if result:
		print("[NetworkManager] ✓ Server started successfully")
	else:
		print("[NetworkManager] ✗ Failed to start server")

	return result

func start_client(ip: String = "127.0.0.1", port: int = 7777):
	print("[NetworkManager] Starting client connection to %s:%d..." % [ip, port])

	# Clean up server if exists (server and client cannot coexist)
	if game_server:
		print("[NetworkManager] Cleaning up existing server before starting client...")
		stop_server()

	if game_client:
		print("[NetworkManager] ERROR: Client already exists!")
		return false

	# Create network lobby (must be under NetworkManager for consistent RPC paths)
	_create_network_lobby()

	print("[NetworkManager] Creating GameClient instance...")
	game_client = GameClient.new()
	game_client.name = "GameClient"
	add_child(game_client)

	print("[NetworkManager] Calling GameClient.connect_to_server()...")
	var result = game_client.connect_to_server(ip, port)

	if result:
		print("[NetworkManager] ✓ Client connection initiated")
	else:
		print("[NetworkManager] ✗ Failed to initiate client connection")

	return result

func stop_server():
	print("[NetworkManager] Stopping server...")
	if game_server:
		game_server.stop_server()
		game_server.queue_free()
		game_server = null
		print("[NetworkManager] ✓ Server stopped and cleaned up")
	else:
		print("[NetworkManager] No server to stop")
	_cleanup_network_lobby()

func stop_client():
	print("[NetworkManager] Stopping client...")
	if game_client:
		game_client.disconnect_from_server()
		game_client.queue_free()
		game_client = null
		print("[NetworkManager] ✓ Client stopped and cleaned up")
	else:
		print("[NetworkManager] No client to stop")
	_cleanup_network_lobby()

# === RPC Methods (must be at same path on client and server) ===

func send_map_seed_to_client(player_id: int, map_seed: int):
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		return
	print("[NetworkManager] Sending map seed %d to player %d" % [map_seed, player_id])
	_receive_map_seed.rpc_id(player_id, map_seed)

@rpc("authority", "call_remote", "reliable")
func _receive_map_seed(seed_value: int):
	print("[NetworkManager] Received map seed: %d" % seed_value)
	# Delegate to GameClient which handles pending seeds properly
	if game_client:
		game_client.receive_map_seed(seed_value)

func send_spawn_player(player_id: int, position: Vector3):
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		return
	print("[NetworkManager] Sending spawn_player RPC for player %d at %s" % [player_id, position])
	_receive_spawn_player.rpc(player_id, position)

@rpc("authority", "call_remote", "reliable")
func _receive_spawn_player(player_id: int, position: Vector3):
	print("[NetworkManager] Received spawn_player for player %d at %s" % [player_id, position])
	if game_client:
		var world = game_client.ensure_client_world()
		if world:
			world.spawn_player(player_id, position)

func send_world_state(state: Dictionary):
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		return
	_receive_world_state.rpc(state)

@rpc("authority", "call_remote", "reliable")
func _receive_world_state(state: Dictionary):
	if game_client:
		var world = game_client.ensure_client_world()
		if world:
			world.apply_world_state(state)

func send_player_input(input_data: Dictionary):
	if not multiplayer.multiplayer_peer:
		return
	# Send to server (ID 1)
	_receive_player_input.rpc_id(1, input_data)

@rpc("any_peer", "call_remote", "reliable")
func _receive_player_input(input_data: Dictionary):
	if not is_server() or not game_server:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if game_server.players.has(sender_id):
		var server_player = game_server.players[sender_id]
		server_player.process_input(input_data)

func notify_match_start():
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		return
	_receive_match_start_notify.rpc()

@rpc("authority", "call_remote", "reliable")
func _receive_match_start_notify():
	# Client received match start notification
	# Transition to game scene if not already there
	print("[NetworkManager] Match start notification received")
	var current_scene = get_tree().current_scene
	if current_scene and current_scene.name != "GameScene":
		get_tree().change_scene_to_file("res://scenes/GameScene.tscn")
