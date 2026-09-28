## Client-side world representation
## Remote clients generate their own copy of the map from the server's seed/radius.
## The host instead adopts the ServerWorld map and loot (adopt_server_world) so that there
## is exactly one map, one set of containers and one entity per player on the host.
extends Node3D
class_name ClientWorld

signal map_ready
signal tiles_destroyed(count: int)

var players: Dictionary = {}  # player_id -> Player entity
var local_player: Player = null
var players_character_applied: Dictionary = {}  # player_id -> bool

var map_seed: int = 0
var map_generator: MapGenerator = null
var loot_spawner: LootSpawner = null
var cover_spawner: CoverSpawner = null
var map_events: MapEvents = null  # remote clients; the host plays the server's (ServerWorld.map_events)
var hex_grid: HexGrid = null
var visibility_system: VisibilitySystem = null
var is_host_view: bool = false  # True when showing the host's ServerWorld
var last_player_states: Dictionary = {}  # latest world state per player (hidden ones too)

# Spawn queue for handling spawns before map is ready
var is_map_ready: bool = false
var is_generating: bool = false
var pending_spawns: Array = []  # Array of {player_id: int, position: Vector3}

func _get_loot_manager() -> NetworkLootManager:
	var network_manager = get_node_or_null("/root/NetworkManager")
	return network_manager.loot_manager if network_manager else null

func generate_map_with_seed(seed_value: int, radius: int = MapGenerator.MATCH_MAP_RADIUS):
	# Prevent duplicate generation
	if is_map_ready or is_generating:
		return

	print("[ClientWorld] Generating client map with seed: %d, radius %d..." % [seed_value, radius])
	is_generating = true
	map_seed = seed_value

	map_generator = MapGenerator.new()
	map_generator.name = "ClientMap"
	add_child(map_generator)
	hex_grid = await map_generator.generate_map(radius, seed_value)
	if not is_inside_tree():
		return

	_setup_visibility_system()
	_setup_post_processing()

	# Same seed as the server -> same containers in the same order -> same network ids
	loot_spawner = LootSpawner.new()
	loot_spawner.name = "LootSpawner"
	add_child(loot_spawner)
	loot_spawner.setup(hex_grid, seed_value)

	var loot_manager = _get_loot_manager()
	if loot_manager:
		for container in loot_spawner.spawned_containers:
			loot_manager.register_container(container)
		print("[ClientWorld] Registered %d loot containers" % loot_spawner.spawned_containers.size())

	# Same walls and bushes as the server (seeded, placed before any destroyed tiles are removed)
	cover_spawner = CoverSpawner.new()
	cover_spawner.name = "CoverSpawner"
	add_child(cover_spawner)
	cover_spawner.setup(hex_grid, seed_value, CoverSpawner.container_tiles(hex_grid, loot_spawner))

	map_events = MapEvents.new()
	map_events.name = "MapEvents"
	add_child(map_events)
	map_events.setup(hex_grid, cover_spawner, false)

	# Tiles the server destroyed before we got here (late join / slow load)
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_client:
		var destroyed = network_manager.game_client.pending_destroyed_tiles
		if not destroyed.is_empty():
			destroy_tiles(destroyed, false)
			network_manager.game_client.pending_destroyed_tiles = []
		# Supply drops announced while the map was generating
		if loot_manager:
			var seen: Dictionary = {}
			for drop in network_manager.game_client.pending_supply_drops:
				if seen.has(drop[2]):
					continue  # the same drop from the map info and a live announcement
				seen[drop[2]] = true
				var landed: bool = drop.size() > 3 and drop[3]  # came down before we joined
				var rich: bool = drop.size() > 4 and drop[4]
				loot_manager.spawn_mirrored_supply_drop(loot_spawner, drop[0], drop[1], drop[2], landed, rich)
		network_manager.game_client.pending_supply_drops = []
		# Zone steps announced while the map was generating (only the latest one still matters)
		var zone_events = network_manager.game_client.pending_zone
		if not zone_events.is_empty():
			var e = zone_events[zone_events.size() - 1]
			var left = e[2] - (Time.get_ticks_msec() - e[5]) / 1000.0
			if e[0] != "rise" and left > 0.0:
				apply_zone(e[0], e[1], left, e[3], e[4])
			network_manager.game_client.pending_zone = []
		# Map events announced while the map was generating
		for ev in network_manager.game_client.pending_map_events:
			apply_map_event(ev[0], ev[1], ev[2] + (Time.get_ticks_msec() - ev[3]) / 1000.0)
		network_manager.game_client.pending_map_events = []

	is_generating = false
	_mark_map_ready()
	print("[ClientWorld] ✓ Client map fully generated with seed: %d" % seed_value)

## Host: show the ServerWorld (already generated) instead of building a second map
func adopt_server_world(server_world: ServerWorld):
	is_host_view = true
	map_seed = server_world.map_seed
	hex_grid = server_world.hex_grid
	loot_spawner = server_world.loot_spawner
	cover_spawner = server_world.cover_spawner
	_setup_visibility_system()
	_setup_post_processing()
	_mark_map_ready()
	print("[ClientWorld] ✓ Host view adopted server map (seed %d)" % map_seed)

func _mark_map_ready():
	is_map_ready = true
	map_ready.emit()
	_process_pending_spawns()

func _setup_visibility_system():
	if visibility_system or not hex_grid:
		return
	visibility_system = VisibilitySystem.new()
	visibility_system.name = "VisibilitySystem"
	add_child(visibility_system)
	visibility_system.setup(hex_grid)

func _process_pending_spawns():
	if pending_spawns.is_empty():
		return

	for spawn_data in pending_spawns:
		spawn_player(spawn_data.player_id, spawn_data.position)
	pending_spawns.clear()

## Tiles the zone has already turned into mountains (map info for late joiners / slow loads)
func destroy_tiles(coords_list: Array, animate: bool = true):
	if not hex_grid:
		return
	var count = 0
	for coords in coords_list:
		var tile = hex_grid.get_tile(coords)
		if tile and tile.is_playable():
			count += 1
			tile.raise_mountain(animate)
	if animate and count > 0:
		tiles_destroyed.emit(count)

var zone_center: Vector2i = Vector2i.ZERO
var zone_radius: int = -1  # safe radius around zone_center (-1: not announced yet)

## A step of the zone (NetworkManager._receive_zone). The host doesn't get these: the server
## changes the shared tiles itself.
func apply_zone(kind: String, coords: Array, _seconds: float, center: Vector2i, radius: int):
	if not hex_grid:
		return
	zone_center = center
	zone_radius = radius
	var state = HexTile.ZoneState.NONE
	match kind:
		"warn", "core_warn":
			state = HexTile.ZoneState.WARNED
		"burn", "core_burn":
			state = HexTile.ZoneState.BURNING
	if kind == "rise":
		var raising := {}
		for c in coords:
			raising[c] = true
		var center_world = hex_grid.hex_to_world(center)
		# Our own player is predicted locally: shove it like the server shoves its copy
		if local_player and is_instance_valid(local_player):
			DestructionSystem.shove(local_player, hex_grid, raising, center_world)
		destroy_tiles(coords, true)
		get_tree().create_timer(HexTile.MOUNTAIN_RISE_TIME + 0.1).timeout.connect(func():
			if local_player and is_instance_valid(local_player) and hex_grid:
				DestructionSystem.unstick(local_player, hex_grid))
		return
	for c in coords:
		var tile = hex_grid.get_tile(c)
		if tile:
			tile.set_zone_state(state)

## A map event (NetworkManager._receive_map_event); the host's are played by ServerWorld.map_events
func apply_map_event(kind: String, data: Dictionary, elapsed: float = 0.0):
	if map_events and not is_host_view:
		map_events.play(kind, data, elapsed)

func _get_local_player_id() -> int:
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_client:
		return network_manager.game_client.local_player_id
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1

func spawn_player(player_id: int, position: Vector3):
	if is_host_view:
		return  # On the host every entity lives in ServerWorld

	if players.has(player_id):
		return

	# If map is not ready yet, queue the spawn for later
	if not is_map_ready:
		for pending in pending_spawns:
			if pending.player_id == player_id:
				return
		pending_spawns.append({"player_id": player_id, "position": position})
		return

	var player = Player.new()
	player.entity_id = player_id
	player.name = "Player_%d" % player_id

	var is_local = player_id == _get_local_player_id()
	if is_local:
		local_player = player
		player.is_local_player = true

	# Add to tree first: components are created in Player._ready()
	players[player_id] = player
	add_child(player)

	if is_local:
		var game_manager = get_node_or_null("/root/GameManager")
		if game_manager and game_manager.selected_character:
			player.setup_character(game_manager.selected_character)
			players_character_applied[player_id] = true
		if visibility_system:
			visibility_system.register_source(player)
			visibility_system.local_player = player

	player.spawn(position)
	if is_local:
		player.give_starting_loadout()

	print("[ClientWorld] ✓ Player %d spawned%s (total players: %d)" % [player_id, " (local)" if is_local else "", players.size()])

func remove_player(player_id: int):
	if not players.has(player_id):
		return

	var player = players[player_id]
	players.erase(player_id)
	players_character_applied.erase(player_id)

	if player == local_player:
		local_player = null

	if is_instance_valid(player):
		if visibility_system:
			visibility_system.unregister_source(player)
		player.queue_free()

	print("[ClientWorld] ✓ Player %d removed (remaining players: %d)" % [player_id, players.size()])

func apply_world_state(state: Dictionary):
	if is_host_view or not state.has("players"):
		return

	var player_states: Dictionary = state["players"]
	last_player_states = player_states

	# Players that are no longer on the server have left
	for player_id in players.keys():
		if not player_states.has(player_id):
			remove_player(player_id)

	for player_id in player_states:
		var player_data: Dictionary = player_states[player_id]
		if player_data.is_empty():
			continue  # Connected but not spawned yet
		if player_data.get("hidden", false):
			_apply_hidden(player_id, player_data)
			continue

		if not players.has(player_id):
			if player_data.has("position"):
				spawn_player(player_id, player_data["position"])

		var player = players.get(player_id)
		if not is_instance_valid(player):
			continue
		if player.has_meta("net_hidden"):
			player.remove_meta("net_hidden")

		# Apply character data to remote players (only once)
		if not players_character_applied.get(player_id, false):
			var char_name = player_data.get("character_name", "")
			if char_name != "":
				var char_data = CharacterRegistry.get_by_name(char_name)
				if char_data:
					player.setup_character(char_data)
					players_character_applied[player_id] = true

		var networking = player.get_component("NetworkingComponent")
		if networking:
			networking.apply_sync_data(player_data)

		# Sync weapon state for remote players
		if player_data.has("weapon_type") and not player.is_local_player:
			_sync_remote_player_weapon(player, player_data)

## Players still standing, from the server's state: with the server-side fog we may never have
## had a copy of someone far away, but their health always arrives
func count_alive() -> int:
	var alive = 0
	for data in last_player_states.values():
		if not data.is_empty() and float(data.get("health", 1.0)) > 0.0:
			alive += 1
	return alive

## The server keeps this player's position from us (out of sight: see ServerVisibility).
## The copy stays where we last saw it, invisible; only its health keeps updating.
func _apply_hidden(player_id: int, data: Dictionary):
	var player = players.get(player_id)
	if not is_instance_valid(player):
		return  # never seen: spawned once they come into view
	player.set_meta("net_hidden", true)
	var networking = player.get_component("NetworkingComponent")
	if networking:
		networking.apply_sync_data({"health": data.get("health", 0.0), "max_health": data.get("max_health", 0.0)})

func get_local_player() -> Player:
	return local_player

func get_player(player_id: int) -> Player:
	return players.get(player_id)

## Sync weapon display for remote players
func _sync_remote_player_weapon(player: Player, player_data: Dictionary):
	var weapon_type: int = player_data.get("weapon_type", -1)
	if weapon_type < 0:
		return

	var weapon_visual = player.get_node_or_null("WeaponVisual") as WeaponVisualComponent
	if not weapon_visual:
		return

	var current_type = -1
	if weapon_visual.current_weapon:
		current_type = weapon_visual.current_weapon.weapon_type
	if current_type == weapon_type:
		return

	var weapon = RangedWeapon.create_weapon(weapon_type)
	if weapon:
		weapon_visual._show_weapon(weapon)

## Настройка постобработки (Bloom, Fog, Glow)
func _setup_post_processing():
	if get_node_or_null("WorldEnvironment"):
		return

	# Only one WorldEnvironment may be active: if the scene already has one (GameEnvironment
	# with the sky), tune it instead of replacing the sky with a flat grey background.
	var scene = get_tree().current_scene
	var existing = scene.find_child("WorldEnvironment", true, false) if scene else null
	if existing is WorldEnvironment and existing.environment:
		var scene_env: Environment = existing.environment
		scene_env.glow_enabled = true
		scene_env.glow_intensity = 0.3
		scene_env.glow_bloom = 0.1
		scene_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		scene_env.ssr_enabled = true  # water reflections (see GameEnvironment)
		return

	var world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"

	var env = Environment.new()

	# Bloom (свечение ярких объектов)
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_strength = 0.8
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Fog (туман для атмосферы)
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.7, 0.85)
	env.fog_light_energy = 0.3
	env.fog_density = 0.001
	env.fog_aerial_perspective = 0.2

	# Ambient light (мягкое освещение)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.85, 0.9)
	env.ambient_light_energy = 0.4

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssr_enabled = true
	env.ssr_max_steps = 48

	world_env.environment = env
	add_child(world_env)
