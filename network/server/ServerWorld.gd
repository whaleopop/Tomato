## Server-side world management
extends Node
class_name ServerWorld

signal player_spawned(player_id: int, position: Vector3)
signal player_removed(player_id: int)

var map_generator: MapGenerator = null
var destruction_system: DestructionSystem = null
var loot_spawner: LootSpawner = null
var loot_manager: NetworkLootManager = null
var players: Dictionary = {}  # player_id -> Player entity
var spawn_points: Array[Vector3] = []
var hex_grid: HexGrid = null

var map_seed: int = 0

func _ready():
	# Create network loot manager
	loot_manager = NetworkLootManager.new()
	loot_manager.name = "NetworkLootManager"
	loot_manager.is_server = true
	add_child(loot_manager)

	# Create map generator
	map_generator = MapGenerator.new()
	add_child(map_generator)

	# Generate map with random seed (will be synced to clients)
	map_seed = randi()
	hex_grid = await map_generator.generate_map(20, map_seed)
	print("[ServerWorld] Map generated with seed: %d" % map_seed)

	# Create destruction system
	destruction_system = DestructionSystem.new()
	add_child(destruction_system)
	destruction_system.start(hex_grid)

	# Create loot spawner
	loot_spawner = LootSpawner.new()
	loot_spawner.name = "LootSpawner"
	add_child(loot_spawner)
	loot_spawner.setup(hex_grid)

	# Register all spawned containers with network manager
	_register_loot_containers()

	# Generate spawn points
	_generate_spawn_points(hex_grid)

func _register_loot_containers():
	# Wait a frame for containers to be added to scene
	await get_tree().process_frame

	var containers = get_tree().get_nodes_in_group("loot_containers")
	for container in containers:
		if container is LootContainer:
			loot_manager.register_container(container)
	print("[ServerWorld] Registered %d loot containers" % containers.size())

func _generate_spawn_points(grid: HexGrid):
	spawn_points.clear()

	# Get center tiles for spawn points
	var center_coords = Vector2i(0, 0)
	var spawn_radius = 5

	for q in range(-spawn_radius, spawn_radius + 1):
		for r in range(-spawn_radius, spawn_radius + 1):
			var coords = center_coords + Vector2i(q, r)
			var tile = grid.get_tile(coords)
			if tile and not tile.is_destroyed and tile.biome_type != HexTile.BiomeType.WATER:
				var world_pos = grid.hex_to_world(coords)
				# Spawn player ON TOP of the tile (tile height + offset for player)
				world_pos.y = (tile.height * HexTile.HEX_HEIGHT) + HexTile.HEX_HEIGHT + 1.0
				spawn_points.append(world_pos)

	spawn_points.shuffle()
	print("[ServerWorld] Generated %d spawn points" % spawn_points.size())

func spawn_player(player_id: int) -> Vector3:
	print("[ServerWorld] Spawning player %d..." % player_id)

	# Check for duplicate spawn
	if players.has(player_id):
		print("[ServerWorld] WARNING: Player %d already exists, returning existing position" % player_id)
		var existing_player = players[player_id]
		if is_instance_valid(existing_player):
			return existing_player.global_position
		else:
			# Clean up invalid reference
			players.erase(player_id)

	# Get random spawn point
	if spawn_points.is_empty():
		print("[ServerWorld] WARNING: No spawn points available, using center")
		# Fallback to center
		spawn_points.append(Vector3.ZERO)

	var spawn_pos = spawn_points.pop_back()
	return _create_player_at(player_id, spawn_pos)

func spawn_player_at(player_id: int, position: Vector3) -> Vector3:
	print("[ServerWorld] Spawning player %d at specific position %s..." % [player_id, position])

	# Check for duplicate spawn
	if players.has(player_id):
		print("[ServerWorld] WARNING: Player %d already exists, returning existing position" % player_id)
		var existing_player = players[player_id]
		if is_instance_valid(existing_player):
			return existing_player.global_position
		else:
			players.erase(player_id)

	return _create_player_at(player_id, position)

func _create_player_at(player_id: int, spawn_pos: Vector3) -> Vector3:
	print("[ServerWorld] Selected spawn position: %s" % spawn_pos)

	# For host (player_id == 1), try to find existing player in ClientWorld
	var player = null
	if player_id == 1:
		# Host - look for existing player in ClientWorld
		var game_scene = get_tree().get_first_node_in_group("game_scene")
		if game_scene:
			var client_world = game_scene.get_node_or_null("ClientWorld")
			if client_world and client_world.players.has(player_id):
				player = client_world.players[player_id]
				print("[ServerWorld] Using existing host player from ClientWorld")

	# Create new player if not found (for clients or if host not yet created)
	if not player:
		print("[ServerWorld] Creating Player entity for player %d..." % player_id)
		player = Player.new()
		player.entity_id = player_id
		player.name = "Player_%d" % player_id
		add_child(player)

		# Spawn player
		player.spawn(spawn_pos)

	# Store player reference
	players[player_id] = player

	# Link player to ServerPlayer
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_server and network_manager.game_server.players.has(player_id):
		var server_player = network_manager.game_server.players[player_id]
		server_player.player_entity = player
		print("[ServerWorld] ✓ Player entity linked to ServerPlayer")

	print("[ServerWorld] ✓ Player %d spawned at %s" % [player_id, spawn_pos])
	player_spawned.emit(player_id, spawn_pos)
	return spawn_pos

func remove_player(player_id: int):
	print("[ServerWorld] Removing player %d..." % player_id)
	
	if not players.has(player_id):
		print("[ServerWorld] WARNING: Player %d not found in players dictionary" % player_id)
		return
	
	var player = players[player_id]
	players.erase(player_id)
	
	if is_instance_valid(player):
		player.queue_free()
	
	print("[ServerWorld] ✓ Player %d removed (remaining players: %d)" % [player_id, players.size()])
	player_removed.emit(player_id)

func get_player(player_id: int) -> Player:
	return players.get(player_id, null)

func get_all_players() -> Array[Player]:
	return players.values()
