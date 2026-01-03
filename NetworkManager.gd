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
