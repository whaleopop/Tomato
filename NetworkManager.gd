## Network manager singleton
extends Node

var game_server: GameServer = null
var game_client: GameClient = null

func _ready():
	pass

func start_server(port: int = 7777):
	print("[NetworkManager] Starting server on port %d..." % port)
	
	# Clean up client if exists (server and client cannot coexist)
	if game_client:
		print("[NetworkManager] Cleaning up existing client before starting server...")
		stop_client()
	
	if game_server:
		print("[NetworkManager] ERROR: Server already exists!")
		return false
	
	print("[NetworkManager] Creating GameServer instance...")
	game_server = GameServer.new()
	add_child(game_server)
	
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
	
	print("[NetworkManager] Creating GameClient instance...")
	game_client = GameClient.new()
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

func stop_client():
	print("[NetworkManager] Stopping client...")
	if game_client:
		game_client.disconnect_from_server()
		game_client.queue_free()
		game_client = null
		print("[NetworkManager] ✓ Client stopped and cleaned up")
	else:
		print("[NetworkManager] No client to stop")
