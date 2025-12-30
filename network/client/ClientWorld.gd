## Client-side world representation
extends Node3D
class_name ClientWorld

var players: Dictionary = {}  # player_id -> Player entity
var local_player: Player = null

var map_seed: int = 0
var map_generator: MapGenerator = null

func _ready():
	# Map will be generated when seed is received from server
	# For now, don't generate map - wait for server seed
	pass

func generate_map_with_seed(seed_value: int, radius: int = 20):
	print("[ClientWorld] Generating client map with seed: %d..." % seed_value)
	map_seed = seed_value
	
	if map_generator:
		map_generator.queue_free()
	
	map_generator = MapGenerator.new()
	add_child(map_generator)
	var _grid = map_generator.generate_map(radius, seed_value)
	print("[ClientWorld] ✓ Client map generated with seed: %d" % seed_value)

func spawn_player(player_id: int, position: Vector3):
	print("[ClientWorld] Spawning player %d at position %s..." % [player_id, position])
	
	# Create player entity
	var player = Player.new()
	player.entity_id = player_id
	player.name = "Player_%d" % player_id
	players[player_id] = player
	add_child(player)
	
	# Spawn player
	player.spawn(position)
	
	# Check if this is local player
	var client = get_node_or_null("/root/NetworkManager/GameClient")
	if not client:
		client = get_node_or_null("/root/GameClient")
	if client and player_id == client.local_player_id:
		print("[ClientWorld] Player %d is local player" % player_id)
		local_player = player
		local_player.is_local_player = true

		# Apply selected character from GameManager
		var game_manager = get_node_or_null("/root/GameManager")
		if game_manager and game_manager.selected_character:
			player.setup_character(game_manager.selected_character)
			print("[ClientWorld] Applied character: %s" % game_manager.selected_character.character_name)

		# Setup input handler for local player
		_setup_input_handler(player)
		# Attach camera to local player
		_setup_camera_for_local_player(player)
	else:
		print("[ClientWorld] Player %d is remote player" % player_id)
	
	print("[ClientWorld] ✓ Player %d spawned (total players: %d)" % [player_id, players.size()])

func remove_player(player_id: int):
	print("[ClientWorld] Removing player %d..." % player_id)
	
	if not players.has(player_id):
		print("[ClientWorld] WARNING: Player %d not found" % player_id)
		return
	
	var player = players[player_id]
	players.erase(player_id)
	
	if player == local_player:
		print("[ClientWorld] Removed player was local player")
		local_player = null
	
	if is_instance_valid(player):
		player.queue_free()
	
	print("[ClientWorld] ✓ Player %d removed (remaining players: %d)" % [player_id, players.size()])

func apply_world_state(state: Dictionary):
	if not state.has("players"):
		return
	
	var player_states = state["players"]
	
	for player_id in player_states:
		var player_data = player_states[player_id]
		
		if not players.has(player_id):
			# Spawn new player
			if player_data.has("position"):
				spawn_player(player_id, player_data["position"])
		
		var player = players.get(player_id)
		if player:
			# Apply sync data
			var networking = player.get_component("NetworkingComponent")
			if networking:
				networking.apply_sync_data(player_data)

func get_local_player() -> Player:
	return local_player

func _setup_input_handler(player: Player):
	print("[ClientWorld] Setting up input handler for local player...")
	var input_handler = preload("res://core/input/PlayerInputHandler.gd").new()
	input_handler.name = "InputHandler"
	player.add_child(input_handler)
	input_handler.setup(player)
	print("[ClientWorld] ✓ Input handler attached to local player")

func _setup_camera_for_local_player(player: Player):
	print("[ClientWorld] Setting up camera and HUD for local player...")
	# Find camera in GameScene
	var game_scene = get_node_or_null("/root/GameScene")
	if not game_scene:
		game_scene = get_tree().get_first_node_in_group("game_scene")
	
	if game_scene:
		# Setup camera
		var camera = game_scene.get_node_or_null("Camera")
		if camera and camera is CameraController:
			camera.set_target(player)
			print("[ClientWorld] ✓ Camera attached to local player")
		else:
			print("[ClientWorld] WARNING: Camera not found or not CameraController")
		
		# Setup HUD
		var hud = game_scene.get_node_or_null("UI/PlayerHUD")
		if hud and hud is PlayerHUD:
			hud.setup(player)
			print("[ClientWorld] ✓ HUD attached to local player")
		else:
			print("[ClientWorld] WARNING: PlayerHUD not found")
	else:
		print("[ClientWorld] WARNING: GameScene not found, cannot attach camera/HUD")

