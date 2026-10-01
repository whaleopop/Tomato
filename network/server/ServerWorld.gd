## Server-side world management
## On a listen server (host) this world is also what the host sees and plays in:
## the host's game scene adopts this map/loot instead of generating a second copy.
extends Node
class_name ServerWorld

signal player_spawned(player_id: int, position: Vector3)
signal player_removed(player_id: int)
signal map_ready

var map_generator: MapGenerator = null
var destruction_system: DestructionSystem = null
var loot_spawner: LootSpawner = null
var cover_spawner: CoverSpawner = null
var map_events: MapEvents = null            # plays the map events on this (the host's) world
var event_director: MapEventDirector = null  # picks them
var weed_spawner: WeedSpawner = null         # the hostile weeds (world/enemies)
var players: Dictionary = {}  # player_id -> Player entity
var spawn_points: Array[Vector3] = []
var hex_grid: HexGrid = null

var map_seed: int = 0
var map_radius: int = MapGenerator.MATCH_MAP_RADIUS
var is_map_ready: bool = false
var destroyed_tiles: Array = []  # Vector2i coords destroyed so far (sent to late joiners)

# The host's entity is created by the game scene as its local player.
# The server only decides where it spawns.
var host_spawn_position: Vector3 = Vector3.ZERO
var has_host_spawn: bool = false


func _ready():
	map_generator = MapGenerator.new()
	map_generator.name = "ServerMap"
	add_child(map_generator)

	# Random seed, synced to clients
	map_seed = randi()
	hex_grid = await map_generator.generate_map(map_radius, map_seed)
	if not is_inside_tree() or not is_instance_valid(hex_grid):
		return  # Server was stopped while the map was generating
	print("[ServerWorld] Map generated with seed: %d" % map_seed)

	# Destruction runs only once the match starts (see start_match)
	destruction_system = DestructionSystem.new()
	destruction_system.name = "DestructionSystem"
	add_child(destruction_system)
	destruction_system.tile_destroyed.connect(_on_tile_destroyed)

	# Loot is seeded from the map seed so every client spawns the same containers
	loot_spawner = LootSpawner.new()
	loot_spawner.name = "LootSpawner"
	add_child(loot_spawner)
	loot_spawner.setup(hex_grid, map_seed)
	loot_spawner.supply_drop_spawned.connect(_on_supply_drop_spawned)
	_register_loot_containers()

	# Walls and bushes, seeded the same way (after the loot: bushes avoid container tiles)
	cover_spawner = CoverSpawner.new()
	cover_spawner.name = "CoverSpawner"
	add_child(cover_spawner)
	cover_spawner.setup(hex_grid, map_seed, CoverSpawner.container_tiles(hex_grid, loot_spawner))

	# Map events: meteors, quake, night, flood, rift, harvest, zone drops
	map_events = MapEvents.new()
	map_events.name = "MapEvents"
	add_child(map_events)
	map_events.setup(hex_grid, cover_spawner, true)
	map_events.tile_raised.connect(_on_tile_destroyed)  # the rift's rock, for late joiners
	event_director = MapEventDirector.new()
	event_director.name = "MapEventDirector"
	add_child(event_director)
	event_director.setup(hex_grid, destruction_system, map_events, loot_spawner, cover_spawner)

	# Hostile weeds: they sprout when the match starts
	weed_spawner = WeedSpawner.new()
	weed_spawner.name = "WeedSpawner"
	add_child(weed_spawner)
	weed_spawner.setup(hex_grid, self, map_seed)

	_generate_spawn_points(hex_grid)

	is_map_ready = true
	map_ready.emit()

func _get_loot_manager() -> NetworkLootManager:
	var network_manager = get_node_or_null("/root/NetworkManager")
	return network_manager.loot_manager if network_manager else null

func _register_loot_containers():
	var loot_manager = _get_loot_manager()
	if not loot_manager:
		return
	for container in loot_spawner.spawned_containers:
		loot_manager.register_container(container)
	print("[ServerWorld] Registered %d loot containers" % loot_spawner.spawned_containers.size())

## Called when the lobby countdown finishes
## mode: GameModes.info - the zone, the map events and the wild weeds only where the mode has them
func start_match(mode: Dictionary = GameModes.info(GameModes.BR)):
	if destruction_system and hex_grid and mode.get("zone", true):
		destruction_system.start(hex_grid)
	if loot_spawner:
		loot_spawner.start_supply_drops()
	if event_director and mode.get("events", true):
		event_director.start()
	if weed_spawner and mode.get("weeds", true):
		weed_spawner.start()

## The match is decided: the island stops crumbling, no more supply drops or events
func stop_match():
	if destruction_system:
		destruction_system.stop()
	if event_director:
		event_director.stop()
	if weed_spawner:
		weed_spawner.stop()
	if loot_spawner:
		loot_spawner.enable_supply_drops = false

func _on_supply_drop_spawned(container: LootContainer):
	var loot_manager = _get_loot_manager()
	if not loot_manager:
		return
	var container_id = loot_manager.register_container(container)
	var ground_pos = container.position - Vector3(0, 20.0, 0)
	loot_manager.record_supply_drop(ground_pos, container.loot_seed, container_id, container.rich)  # for late joiners
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.broadcast_supply_drop(ground_pos, container.loot_seed, container_id, container.rich)

## A tile became a mountain: remembered for late joiners (the live step goes out as a zone event)
func _on_tile_destroyed(coords: Vector2i):
	destroyed_tiles.append(coords)

func _generate_spawn_points(grid: HexGrid):
	spawn_points.clear()

	# Get center tiles for spawn points
	var center_coords = Vector2i(0, 0)
	var spawn_radius = 3  # big tiles

	for q in range(-spawn_radius, spawn_radius + 1):
		for r in range(-spawn_radius, spawn_radius + 1):
			var coords = center_coords + Vector2i(q, r)
			var tile = grid.get_tile(coords)
			# Проверяем can_spawn - нельзя спавниться на горах и в воде
			if tile and not tile.is_destroyed and tile.can_spawn:
				var world_pos = grid.hex_to_world(coords)
				# Spawn player ON TOP of the tile (tile height + offset for player)
				world_pos.y = (tile.height * HexTile.HEX_HEIGHT) + HexTile.HEX_HEIGHT + 1.0
				spawn_points.append(world_pos)

	spawn_points.shuffle()
	print("[ServerWorld] Generated %d spawn points" % spawn_points.size())

func get_random_spawn_point() -> Vector3:
	if spawn_points.is_empty():
		return Vector3(0, 3, 0)
	return spawn_points.pop_back()

func spawn_player(player_id: int, character_name: String = "") -> Vector3:
	return spawn_player_at(player_id, get_random_spawn_point(), character_name)

func spawn_player_at(player_id: int, position: Vector3, character_name: String = "") -> Vector3:
	# Already spawned?
	if players.has(player_id):
		var existing_player = players[player_id]
		if is_instance_valid(existing_player):
			return existing_player.global_position
		players.erase(player_id)

	if player_id == 1:
		# Host: remember the spot, the game scene spawns the host's local player there
		host_spawn_position = position
		has_host_spawn = true
		print("[ServerWorld] Host spawn reserved at %s" % position)
		player_spawned.emit(player_id, position)
		return position

	print("[ServerWorld] Creating Player entity for player %d (%s) at %s" % [player_id, character_name, position])
	var player = Player.new()
	player.entity_id = player_id
	player.name = "Player_%d" % player_id
	add_child(player)

	# Same stats/abilities/model as on the owning client, otherwise speed and health differ
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_server and network_manager.game_server.players.has(player_id):
		player.cosmetics = network_manager.game_server.players[player_id].cosmetics.duplicate()
	var char_data = CharacterRegistry.get_by_name(character_name)
	if char_data:
		player.setup_character(char_data)

	player.spawn(position)
	player.give_starting_loadout()

	_register_entity(player_id, player)
	player_spawned.emit(player_id, position)
	return position

## The host's local player (created by GameSceneController) becomes the server entity for id 1
func register_host_player(player: Player):
	_register_entity(1, player)

func _register_entity(player_id: int, player: Player):
	players[player_id] = player

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_server and network_manager.game_server.players.has(player_id):
		var server_player = network_manager.game_server.players[player_id]
		server_player.player_entity = player
		server_player.connect_to_entity_signals()

func remove_player(player_id: int):
	if not players.has(player_id):
		return

	var player = players[player_id]
	players.erase(player_id)

	if is_instance_valid(player) and player_id != 1:
		player.queue_free()

	print("[ServerWorld] ✓ Player %d removed (remaining players: %d)" % [player_id, players.size()])
	player_removed.emit(player_id)

func get_player(player_id: int) -> Player:
	var player = players.get(player_id, null)
	return player if is_instance_valid(player) else null

func get_all_players() -> Array[Player]:
	var result: Array[Player] = []
	for player in players.values():
		if is_instance_valid(player):
			result.append(player)
	return result
