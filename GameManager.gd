## Main game manager
extends Node

signal game_started
signal game_ended

var game_server: GameServer = null
var game_client: GameClient = null
var is_host: bool = false
var is_client: bool = false
var selected_character: CharacterData = null  # Character selected in CharacterSelect menu

func _ready():
	# Add to group so it can be found by GameClient
	add_to_group("game_scene")
	print("[GameManager] GameScene ready")

func start_as_host():
	is_host = true
	game_server = GameServer.new()
	add_child(game_server)
	game_server.start_server()
	game_started.emit()

func start_as_client(ip: String = "127.0.0.1"):
	is_client = true
	game_client = GameClient.new()
	add_child(game_client)
	game_client.connect_to_server(ip)
	game_started.emit()

func stop_game():
	if game_server:
		game_server.stop_server()
		game_server.queue_free()
		game_server = null
	
	if game_client:
		game_client.disconnect_from_server()
		game_client.queue_free()
		game_client = null
	
	is_host = false
	is_client = false
	game_ended.emit()
