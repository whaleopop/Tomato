## Client-side world representation
extends Node3D
class_name ClientWorld

var players: Dictionary = {}  # player_id -> Player entity
var local_player: Player = null

var map_seed: int = 0
var map_generator: MapGenerator = null
var loot_spawner: LootSpawner = null
var loot_manager: NetworkLootManager = null
var hex_grid: HexGrid = null

# Spawn queue for handling spawns before map is ready
var is_map_ready: bool = false
var pending_spawns: Array = []  # Array of {player_id: int, position: Vector3}

func _ready():
	# Create network loot manager for client
	loot_manager = NetworkLootManager.new()
	loot_manager.name = "NetworkLootManager"
	loot_manager.is_server = false
	add_child(loot_manager)

func generate_map_with_seed(seed_value: int, radius: int = 20):
	print("[ClientWorld] Generating client map with seed: %d..." % seed_value)
	map_seed = seed_value
	is_map_ready = false

	# Set random seed for consistent loot spawning
	seed(seed_value)

	if map_generator:
		map_generator.queue_free()

	map_generator = MapGenerator.new()
	add_child(map_generator)
	hex_grid = await map_generator.generate_map(radius, seed_value)

	# Spawn loot containers (same seed = same positions)
	if loot_spawner:
		loot_spawner.queue_free()

	loot_spawner = LootSpawner.new()
	loot_spawner.name = "LootSpawner"
	add_child(loot_spawner)
	loot_spawner.setup(hex_grid)

	# Register containers with network loot manager
	await get_tree().process_frame
	_register_loot_containers()

	print("[ClientWorld] Client map generated with seed: %d" % seed_value)

func _register_loot_containers():
	var containers = get_tree().get_nodes_in_group("loot_containers")
	for container in containers:
		if container is LootContainer:
			loot_manager.register_container(container)
	print("[ClientWorld] Registered %d loot containers" % containers.size())

	# Map is now ready - process any pending spawns
	is_map_ready = true
	_process_pending_spawns()

func _process_pending_spawns():
	if pending_spawns.is_empty():
		return

	print("[ClientWorld] Processing %d pending spawns..." % pending_spawns.size())
	for spawn_data in pending_spawns:
		spawn_player(spawn_data.player_id, spawn_data.position)
	pending_spawns.clear()
	print("[ClientWorld] ✓ All pending spawns processed")

func spawn_player(player_id: int, position: Vector3):
	print("[ClientWorld] Spawning player %d at position %s..." % [player_id, position])

	# If map is not ready yet, queue the spawn for later
	if not is_map_ready:
		print("[ClientWorld] Map not ready, queuing spawn for player %d" % player_id)
		pending_spawns.append({"player_id": player_id, "position": position})
		return

	# Check if player already exists
	if players.has(player_id):
		print("[ClientWorld] Player %d already exists, skipping" % player_id)
		return

	# Create player entity
	var player = Player.new()
	player.entity_id = player_id
	player.name = "Player_%d" % player_id

	# Check if this is local player BEFORE spawning (so color is set correctly)
	var client = get_node_or_null("/root/NetworkManager/GameClient")
	if not client:
		client = get_node_or_null("/root/GameClient")

	var is_local = client and player_id == client.local_player_id

	if is_local:
		print("[ClientWorld] Player %d is local player" % player_id)
		local_player = player
		player.is_local_player = true

		# Apply selected character from GameManager BEFORE spawning
		var game_manager = get_node_or_null("/root/GameManager")
		if game_manager and game_manager.selected_character:
			player.setup_character(game_manager.selected_character)
			print("[ClientWorld] Applied character: %s" % game_manager.selected_character.character_name)
	else:
		print("[ClientWorld] Player %d is remote player" % player_id)

	# Add to tree and store in dictionary
	players[player_id] = player
	add_child(player)

	# Now spawn (creates visual representation with correct color)
	player.spawn(position)

	# Setup input and camera for local player AFTER spawning
	if is_local:
		_setup_input_handler(player)
		_setup_camera_for_local_player(player)

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
