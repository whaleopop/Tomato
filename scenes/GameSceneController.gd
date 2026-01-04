## Game scene controller - manages the actual game scene
extends Node3D
class_name GameSceneController

signal game_ready

var is_initialized: bool = false

func _ready():
	# Add to group so GameClient can find us
	add_to_group("game_scene")
	print("[GameSceneController] GameScene ready")

	# Wait a frame then initialize
	await get_tree().process_frame
	_initialize_game()

func _initialize_game():
	if is_initialized:
		return

	is_initialized = true
	print("[GameSceneController] Initializing game...")

	# Check if we're a host (server exists) or client
	var network_manager = get_node_or_null("/root/NetworkManager")

	if network_manager:
		if network_manager.game_server:
			print("[GameSceneController] Running as HOST/SERVER")
			_setup_as_host()
		elif network_manager.game_client:
			print("[GameSceneController] Running as CLIENT")
			_setup_as_client()
		else:
			print("[GameSceneController] No network mode - starting offline/debug mode")
			_setup_offline_debug()
	else:
		print("[GameSceneController] NetworkManager not found - starting offline mode")
		_setup_offline_debug()

	game_ready.emit()

func _setup_as_host():
	# Host uses ServerWorld for map generation
	# The map is already created by GameServer
	print("[GameSceneController] Host setup complete - server manages world")

	# For host, also act as a client (listen-server mode)
	# Start a local client connection
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_server and not network_manager.game_client:
		print("[GameSceneController] Starting local client for host...")
		# Host needs to connect as client too to receive RPCs
		_start_host_client()

func _start_host_client():
	# Create client world for the host to see
	var client_world = ClientWorld.new()
	client_world.name = "ClientWorld"
	add_child(client_world)

	# Get map seed from server
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_server and network_manager.game_server.server_world:
		var map_seed = network_manager.game_server.server_world.map_seed
		print("[GameSceneController] Generating host client map with seed: %d" % map_seed)
		await client_world.generate_map_with_seed(map_seed)

		# Add loot spawner to client world for visual representation
		if client_world.hex_grid:
			var loot_spawner = LootSpawner.new()
			loot_spawner.name = "LootSpawner"
			client_world.add_child(loot_spawner)
			loot_spawner.setup(client_world.hex_grid)
			print("[GameSceneController] ✓ Loot spawner added to client world")

		# Spawn local player for host
		var host_id = 1  # Server is always ID 1
		var spawn_pos = Vector3(0, 2, 0)  # Default spawn above ground

		# Get spawn position from server world
		var server_world = network_manager.game_server.server_world
		if server_world.spawn_points.size() > 0:
			spawn_pos = server_world.spawn_points[0]
		print("[GameSceneController] Host spawn position: %s" % spawn_pos)

		# Create host player with proper setup
		var player = Player.new()
		player.entity_id = host_id
		player.name = "Player_%d" % host_id
		player.is_local_player = true

		# Apply selected character
		var game_manager = get_node_or_null("/root/GameManager")
		if game_manager and game_manager.selected_character:
			player.setup_character(game_manager.selected_character)
			print("[GameSceneController] Applied character: %s" % game_manager.selected_character.character_name)

		# Add to client world
		client_world.players[host_id] = player
		client_world.local_player = player
		client_world.add_child(player)

		# Spawn player
		print("[GameSceneController] Spawning host player at %s" % spawn_pos)
		player.spawn(spawn_pos)

		# Setup input and camera
		_setup_host_input_and_camera(player, client_world)

		# Link to ServerPlayer if exists
		if server_world.players.has(host_id):
			var server_player = network_manager.game_server.players.get(host_id)
			if server_player:
				server_player.player_entity = player
				print("[GameSceneController] ✓ Host player linked to ServerPlayer")

func _setup_host_input_and_camera(player: Player, client_world: ClientWorld):
	# Setup input handler
	var input_handler = preload("res://core/input/PlayerInputHandler.gd").new()
	input_handler.name = "InputHandler"
	player.add_child(input_handler)
	input_handler.setup(player)
	print("[GameSceneController] ✓ Input handler attached to host player")

	# Setup camera
	var camera = get_node_or_null("Camera")
	if camera and camera.has_method("set_target"):
		camera.set_target(player)
		print("[GameSceneController] ✓ Camera attached to host player")

	# Setup HUD
	var hud = get_node_or_null("UI/PlayerHUD")
	if hud and hud.has_method("setup"):
		hud.setup(player)
		print("[GameSceneController] ✓ HUD attached to host player")

	# Setup Inventory Menu
	_setup_inventory_menu(player)

func _setup_as_client():
	# Client setup: create ClientWorld directly in GameScene
	var network_manager = get_node_or_null("/root/NetworkManager")

	if network_manager and network_manager.game_client:
		var game_client = network_manager.game_client

		print("[GameSceneController] Creating ClientWorld for client...")

		# Create ClientWorld directly here (not via ensure_client_world)
		var client_world = ClientWorld.new()
		client_world.name = "ClientWorld"
		add_child(client_world)

		# Register with GameClient
		game_client.client_world = client_world
		print("[GameSceneController] ClientWorld created and registered")

		# Apply pending map seed if exists
		if game_client.pending_map_seed > 0:
			print("[GameSceneController] Applying pending map seed: %d" % game_client.pending_map_seed)
			client_world.generate_map_with_seed(game_client.pending_map_seed)
			game_client.pending_map_seed = 0
		else:
			print("[GameSceneController] No pending map seed, waiting for server...")

		# Wait for local player to spawn
		print("[GameSceneController] Waiting for local player to spawn...")
		_wait_for_local_player(client_world)

	print("[GameSceneController] Client setup complete")

func _wait_for_local_player(client_world: ClientWorld):
	# Check periodically for local player
	for i in range(300):  # Wait up to 5 seconds (300 frames)
		await get_tree().process_frame
		if client_world and client_world.local_player:
			print("[GameSceneController] Local player found, setting up camera...")
			_setup_client_camera_and_hud(client_world.local_player)
			return
	print("[GameSceneController] WARNING: Local player not found after waiting")

func _setup_client_camera_and_hud(player: Player):
	# Setup input handler
	var input_handler = preload("res://core/input/PlayerInputHandler.gd").new()
	input_handler.name = "InputHandler"
	player.add_child(input_handler)
	input_handler.setup(player)
	print("[GameSceneController] ✓ Input handler attached to client player")

	# Setup camera
	var camera = get_node_or_null("Camera")
	if camera and camera.has_method("set_target"):
		camera.set_target(player)
		print("[GameSceneController] ✓ Camera attached to client player")
	else:
		print("[GameSceneController] WARNING: Camera not found")

	# Setup HUD
	var hud = get_node_or_null("UI/PlayerHUD")
	if hud and hud.has_method("setup"):
		hud.setup(player)
		print("[GameSceneController] ✓ HUD attached to client player")

	# Setup Inventory Menu
	_setup_inventory_menu(player)

func _setup_offline_debug():
	# For testing without network
	print("[GameSceneController] Setting up offline debug mode...")

	# Create a floor as safety net
	_create_debug_floor()

	# Create a simple map for testing
	var map_generator = MapGenerator.new()
	add_child(map_generator)
	print("[GameSceneController] Generating debug map...")
	var hex_grid = await map_generator.generate_map(10, 12345)

	# Create loot spawner
	if hex_grid:
		var loot_spawner = LootSpawner.new()
		loot_spawner.name = "LootSpawner"
		add_child(loot_spawner)
		loot_spawner.setup(hex_grid)
		print("[GameSceneController] ✓ Loot spawner created")

	# Create a test player
	var player = Player.new()
	player.name = "DebugPlayer"
	player.is_local_player = true

	# Apply selected character BEFORE adding to tree
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.selected_character:
		player.setup_character(game_manager.selected_character)
		print("[GameSceneController] Applied character: %s" % game_manager.selected_character.character_name)

	add_child(player)

	# Spawn at height above tiles
	player.spawn(Vector3(0, 3, 0))

	# Setup input handler
	var input_handler = preload("res://core/input/PlayerInputHandler.gd").new()
	input_handler.name = "InputHandler"
	player.add_child(input_handler)
	input_handler.setup(player)

	# Setup camera
	var camera = get_node_or_null("Camera")
	if camera and camera.has_method("set_target"):
		camera.set_target(player)

	# Setup HUD
	var hud = get_node_or_null("UI/PlayerHUD")
	if hud and hud.has_method("setup"):
		hud.setup(player)

	# Setup Inventory Menu
	_setup_inventory_menu(player)

	print("[GameSceneController] Debug mode setup complete")

func _create_debug_floor():
	# Create invisible floor as safety net (in case player falls through map)
	var floor_body = StaticBody3D.new()
	floor_body.name = "SafetyFloor"

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collision.shape = shape
	collision.position = Vector3(0, -5, 0)

	floor_body.add_child(collision)
	add_child(floor_body)

func _setup_inventory_menu(player: Player):
	# Create InventoryMenu
	var inventory_menu = preload("res://ui/menus/InventoryMenu.gd").new()
	inventory_menu.name = "InventoryMenu"

	# Add to UI layer
	var ui_layer = get_node_or_null("UI")
	if ui_layer:
		ui_layer.add_child(inventory_menu)

		# Setup with player's InventoryComponent
		var inventory_component = player.get_component("InventoryComponent")
		if inventory_component:
			inventory_menu.setup(inventory_component)
			print("[GameSceneController] ✓ Inventory menu created and linked to player")
		else:
			print("[GameSceneController] WARNING: Player has no InventoryComponent")
	else:
		print("[GameSceneController] ERROR: UI layer not found")
