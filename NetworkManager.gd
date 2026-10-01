## Network manager singleton
## Every RPC between peers goes through nodes under /root/NetworkManager so that the
## node paths are identical on the server and on all clients.
extends Node

signal connection_lost(reason: String)
signal match_ended(winner_id: int, winner_name: String)  # 0 = nobody left standing
## Somebody went down (ServerPlayer._on_died): the kill feed, the victim's killer card and
## spectating. killer_id 0 = nobody else (the zone, map events, your own grenade).
## info: victim_name, victim_hero, killer_name, killer_hero, killer_wear, weapon (RangedWeapon type, -1
## none), killer_health, killer_max_health, killer_kills
signal player_killed(victim_id: int, killer_id: int, info: Dictionary)
## The match mode's state (ModeRules.state_for): scores, flags, the hill, XP - ModeView shows it
signal mode_state(state: Dictionary)
## A hero came back (respawning modes)
signal player_respawned(player_id: int, pos: Vector3)

var game_server: GameServer = null
var game_client: GameClient = null
var network_lobby: NetworkLobby = null
var loot_manager: NetworkLootManager = null

# Set while we tear the connection down ourselves, so it is not reported as "lost"
var _stopping: bool = false

## Who we are for the server across reconnects within this run of the game: a player who got
## eliminated, went back to the menu and joined again is recognised and not spawned a second
## time in the same match (see GameServer.can_late_join)
var client_token: String = ""
## Why the server turned us away (shown instead of "connection lost")
var refusal_reason: String = ""

func _ready():
	client_token = Crypto.new().generate_random_bytes(8).hex_encode()

func is_server() -> bool:
	return game_server != null and game_server.is_running

func is_client() -> bool:
	return game_client != null

func get_network_lobby() -> NetworkLobby:
	return network_lobby

func _create_shared_nodes(as_server: bool):
	if not network_lobby:
		network_lobby = NetworkLobby.new()
		network_lobby.name = "NetworkLobby"
		add_child(network_lobby)
	if not loot_manager:
		loot_manager = NetworkLootManager.new()
		loot_manager.name = "NetworkLootManager"
		add_child(loot_manager)
	loot_manager.reset()
	loot_manager.is_server = as_server

## Detach before freeing: a replacement created in the same frame must get the exact same
## node name, otherwise its RPC path differs from the other peers'
func _free_now(node: Node):
	if node and is_instance_valid(node):
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.queue_free()

func _cleanup_shared_nodes():
	_free_now(network_lobby)
	network_lobby = null
	_free_now(loot_manager)
	loot_manager = null

func start_server(port: int = 7777) -> bool:
	print("[NetworkManager] Starting server on port %d..." % port)

	# Server and client cannot coexist in this process
	stop_all()

	_create_shared_nodes(true)

	game_server = GameServer.new()
	game_server.name = "GameServer"
	add_child(game_server)

	if network_lobby and game_server.lobby_manager:
		network_lobby.setup_server(game_server.lobby_manager)

	var result = game_server.start_server(port)
	if result:
		print("[NetworkManager] ✓ Server started successfully")
	else:
		print("[NetworkManager] ✗ Failed to start server")
		stop_server()

	return result

func start_client(ip: String = "127.0.0.1", port: int = 7777) -> bool:
	print("[NetworkManager] Starting client connection to %s:%d..." % [ip, port])

	stop_all()

	_create_shared_nodes(false)

	game_client = GameClient.new()
	game_client.name = "GameClient"
	add_child(game_client)
	game_client.disconnected_from_server.connect(_on_client_disconnected)

	var result = game_client.connect_to_server(ip, port)
	if not result:
		print("[NetworkManager] ✗ Failed to initiate client connection")
		stop_client()
	return result

func stop_server():
	_stopping = true
	if game_server:
		game_server.stop_server()
		_free_now(game_server)
		game_server = null
		print("[NetworkManager] ✓ Server stopped and cleaned up")
	_cleanup_shared_nodes()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_stopping = false

func stop_client():
	_stopping = true
	if game_client:
		game_client.disconnect_from_server()
		_free_now(game_client)
		game_client = null
		print("[NetworkManager] ✓ Client stopped and cleaned up")
	_cleanup_shared_nodes()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_stopping = false

## Tear down any networking and per-match state (used when returning to the main menu)
func stop_all():
	if game_server:
		stop_server()
	if game_client:
		stop_client()
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.reset_match_state()

func _on_client_disconnected():
	if _stopping:
		return
	print("[NetworkManager] Connection to server lost")
	var reason = refusal_reason if refusal_reason != "" else "Connection to the server was lost"
	refusal_reason = ""
	# Defer so we are not freeing the client from inside its own signal
	call_deferred("_handle_connection_lost", reason)

func _handle_connection_lost(reason: String):
	stop_client()
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.last_error = reason
	connection_lost.emit(reason)
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")

func _has_remote_peers() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server() and not multiplayer.get_peers().is_empty()

func _get_client_world() -> ClientWorld:
	if game_client and is_instance_valid(game_client.client_world):
		return game_client.client_world
	return null

# === Map info ===

func send_map_info_to_client(player_id: int, map_seed: int, map_radius: int, destroyed_tiles: Array):
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		return
	# Late joiners also need what happened to the loot (opened containers, pickups, drops)
	var loot_state = loot_manager.get_late_join_state() if loot_manager else {}
	print("[NetworkManager] Sending map seed %d (radius %d, %d destroyed, %d opened) to player %d" % [map_seed, map_radius, destroyed_tiles.size(), loot_state.get("opened", []).size(), player_id])
	_receive_map_info.rpc_id(player_id, map_seed, map_radius, destroyed_tiles, loot_state)

@rpc("authority", "call_remote", "reliable")
func _receive_map_info(seed_value: int, map_radius: int, destroyed_tiles: Array, loot_state: Dictionary):
	print("[NetworkManager] Received map seed: %d (radius %d)" % [seed_value, map_radius])

	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.map_seed = seed_value

	# Before the map (and its containers) gets generated
	if loot_manager:
		loot_manager.apply_late_join_state(loot_state, game_client)

	if game_client:
		game_client.receive_map_info(seed_value, map_radius, destroyed_tiles)

# === Players ===

func send_spawn_player(player_id: int, position: Vector3):
	if not _has_remote_peers():
		return
	_receive_spawn_player.rpc(player_id, position)

@rpc("authority", "call_remote", "reliable")
func _receive_spawn_player(player_id: int, position: Vector3):
	var world = _get_client_world()
	if world:
		world.spawn_player(player_id, position)
	# If the game scene is not loaded yet the next world state spawns the player

func send_player_left(player_id: int):
	if not _has_remote_peers():
		return
	_receive_player_left.rpc(player_id)

@rpc("authority", "call_remote", "reliable")
func _receive_player_left(player_id: int):
	var world = _get_client_world()
	if world:
		world.remove_player(player_id)

## World state is sent many times per second; a lost packet is superseded by the next one,
## so it goes unreliable (ordered) instead of clogging the reliable channel.
func send_world_state(state: Dictionary):
	if not _has_remote_peers():
		return
	_receive_world_state.rpc(state)

## One client's own (fog-of-war filtered) view, see TickSystem
func send_world_state_to(peer_id: int, state: Dictionary):
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		return
	_receive_world_state.rpc_id(peer_id, state)

@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_world_state(state: Dictionary):
	var world = _get_client_world()
	if world:
		world.apply_world_state(state)

func send_player_input(input_data: Dictionary):
	if not multiplayer.multiplayer_peer or multiplayer.is_server():
		return
	_receive_player_input.rpc_id(1, input_data)

@rpc("any_peer", "call_remote", "reliable")
func _receive_player_input(input_data: Dictionary):
	if not is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if game_server.players.has(sender_id):
		game_server.players[sender_id].process_input(input_data)

func notify_match_start():
	if not _has_remote_peers():
		return
	_receive_match_start_notify.rpc()

@rpc("authority", "call_remote", "reliable")
func _receive_match_start_notify():
	# Scene transition is driven by NetworkLobby.match_starting (SpawnSelectController)
	print("[NetworkManager] Match start notification received")

# === Map destruction ===

## The zone (DestructionSystem): kind = warn / burn / rise / calm / core_warn / core_burn,
## coords = the tiles of this step, seconds = how long the step lasts, center + radius = the safe area
signal zone_changed(kind: String, coords: Array, seconds: float, center: Vector2i, radius: int)

func broadcast_zone(kind: String, coords: Array, seconds: float, center: Vector2i, radius: int):
	if _has_remote_peers():
		_receive_zone.rpc(kind, coords, seconds, center, radius)
	zone_changed.emit(kind, coords, seconds, center, radius)  # the host (tiles are the server's own)

func send_zone_state_to(peer_id: int, state: Dictionary):
	if state.is_empty() or not _has_remote_peers():
		return
	_receive_zone.rpc_id(peer_id, state.kind, state.coords, state.seconds, state.center, state.radius)

@rpc("authority", "call_remote", "reliable")
func _receive_zone(kind: String, coords: Array, seconds: float, center: Vector2i, radius: int):
	var world = _get_client_world()
	if world and world.is_map_ready:
		world.apply_zone(kind, coords, seconds, center, radius)
	elif game_client:
		game_client.pending_zone.append([kind, coords, seconds, center, radius, Time.get_ticks_msec()])
	zone_changed.emit(kind, coords, seconds, center, radius)

# === Map events ===

## MapEventDirector (server): meteors, quake, night, flood, rift, harvest, zone_drop, center_shift.
## elapsed > 0: a late joiner catching up with an event that started before it came.
signal map_event(kind: String, data: Dictionary, elapsed: float)

func broadcast_map_event(kind: String, data: Dictionary):
	if _has_remote_peers():
		_receive_map_event.rpc(kind, data, 0.0)
	map_event.emit(kind, data, 0.0)  # the host's HUD (the director played it on the shared world)

## Late joiner: the events it still has to see ([kind, data, elapsed], MapEventDirector.history_for_late_join)
func send_map_events_to(peer_id: int, events: Array):
	if not _has_remote_peers():
		return
	for e in events:
		_receive_map_event.rpc_id(peer_id, e[0], e[1], e[2])

@rpc("authority", "call_remote", "reliable")
func _receive_map_event(kind: String, data: Dictionary, elapsed: float):
	var world = _get_client_world()
	if world and world.is_map_ready:
		world.apply_map_event(kind, data, elapsed)
	elif game_client:
		game_client.pending_map_events.append([kind, data, elapsed, Time.get_ticks_msec()])
	map_event.emit(kind, data, elapsed)

# === Respawns ===

func broadcast_respawn(player_id: int, pos: Vector3):
	if _has_remote_peers():
		_receive_respawn.rpc(player_id, pos)
	player_respawned.emit(player_id, pos)

@rpc("authority", "call_remote", "reliable")
func _receive_respawn(player_id: int, pos: Vector3):
	var world = _get_client_world()
	var p = world.get_player(player_id) if world and world.has_method("get_player") else null
	if p and is_instance_valid(p):
		p.respawn_at(pos)
	player_respawned.emit(player_id, pos)

# === Weeds ===

## Server: a dandelion threw seeds (the host saw it already: the weed is in its world)
func broadcast_npc_seed(from: Vector3, to: Vector3):
	if _has_remote_peers():
		_receive_npc_seed.rpc(from, to)

@rpc("authority", "call_remote", "unreliable")
func _receive_npc_seed(from: Vector3, to: Vector3):
	var world = _get_client_world()
	Weed.play_seed(from, to, world)

# === Kills ===

## Server: tell everyone who took whom out (reliable: the feed and the victim's card need it)
func broadcast_kill(victim_id: int, killer_id: int, info: Dictionary):
	if _has_remote_peers():
		_receive_kill.rpc(victim_id, killer_id, info)
	player_killed.emit(victim_id, killer_id, info)  # the host's own HUD

@rpc("authority", "call_remote", "reliable")
func _receive_kill(victim_id: int, killer_id: int, info: Dictionary):
	player_killed.emit(victim_id, killer_id, info)

# === Match end ===

## Server: the last one standing is decided
func broadcast_match_end(winner_id: int, winner_name: String):
	if _has_remote_peers():
		_receive_match_end.rpc(winner_id, winner_name)
	match_ended.emit(winner_id, winner_name)  # the host's own HUD

@rpc("authority", "call_remote", "reliable")
func _receive_match_end(winner_id: int, winner_name: String):
	match_ended.emit(winner_id, winner_name)

# === Loot ===

func broadcast_supply_drop(ground_pos: Vector3, loot_seed: int, container_id: int, rich: bool = false):
	if not _has_remote_peers():
		return
	_receive_supply_drop.rpc(ground_pos, loot_seed, container_id, rich)

@rpc("authority", "call_remote", "reliable")
func _receive_supply_drop(ground_pos: Vector3, loot_seed: int, container_id: int, rich: bool):
	var world = _get_client_world()
	if world and world.is_map_ready and world.loot_spawner and loot_manager:
		loot_manager.spawn_mirrored_supply_drop(world.loot_spawner, ground_pos, loot_seed, container_id, false, rich)
	elif game_client:
		game_client.pending_supply_drops.append([ground_pos, loot_seed, container_id, false, rich])

# === Combat effects ===

## Broadcast shot effects to all clients (unreliable for performance).
## show_on_host: also draw them locally, for shots the host would not see otherwise.
func broadcast_shot_effect(shooter_id: int, from_pos: Vector3, to_pos: Vector3, weapon_type: int, hit: bool, show_on_host: bool = false):
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		return
	# Only to clients close enough to see or hear it: a tracer carries the shooter's position
	for peer_id in multiplayer.get_peers():
		if peer_id != shooter_id and _peer_hears(peer_id, from_pos, to_pos):
			_receive_shot_effect.rpc_id(peer_id, shooter_id, from_pos, to_pos, weapon_type, hit)

	if show_on_host and shooter_id != 1:
		var scene = get_tree().current_scene
		if scene is Node3D:
			_create_remote_shot_effects(scene, from_pos, to_pos, weapon_type, hit)

@rpc("authority", "call_remote", "unreliable")
func _receive_shot_effect(shooter_id: int, from_pos: Vector3, to_pos: Vector3, weapon_type: int, hit: bool):
	# The local player already sees their own shots
	if game_client and shooter_id == game_client.local_player_id:
		return

	var world = _get_client_world()
	if world:
		_create_remote_shot_effects(world, from_pos, to_pos, weapon_type, hit)
		# Their shot lights up our fog too: shooting gives you away
		if world.visibility_system:
			world.visibility_system.add_bullet_trail(from_pos, to_pos, 0.5)

func _peer_hears(peer_id: int, from_pos: Vector3, to_pos: Vector3) -> bool:
	var world = game_server.server_world if game_server else null
	var viewer = world.get_player(peer_id) if world else null
	if viewer == null:
		return false
	return ServerVisibility.can_hear(viewer, from_pos) or ServerVisibility.can_hear(viewer, to_pos)

# === Abilities ===

## Server: someone cast an ability; clients that can see the caster replay the visuals on their
## copy (damage and movement are server-side, the caster predicted their own cast)
func broadcast_ability_cast(caster_id: int, ability_index: int, target_position: Vector3):
	if not multiplayer.multiplayer_peer or not multiplayer.is_server() or not game_server:
		return
	var world = game_server.server_world
	var caster = world.get_player(caster_id) if world else null
	if caster == null:
		return
	for peer_id in multiplayer.get_peers():
		if peer_id == caster_id:
			continue
		var viewer = world.get_player(peer_id)
		if ServerVisibility.can_see(viewer, caster, world.hex_grid):
			_receive_ability_cast.rpc_id(peer_id, caster_id, ability_index, target_position)

@rpc("authority", "call_remote", "reliable")
func _receive_ability_cast(caster_id: int, ability_index: int, target_position: Vector3):
	var world = _get_client_world()
	var caster = world.get_player(caster_id) if world else null
	if caster == null or caster.is_local_player:
		return
	var abilities = caster.get_component("AbilityComponent")
	if abilities:
		abilities.play_remote_cast(ability_index, target_position)

func _create_remote_shot_effects(parent: Node3D, from_pos: Vector3, to_pos: Vector3, weapon_type: int, hit: bool):
	var direction = (to_pos - from_pos).normalized()
	var mode = RangedWeapon.fire_mode_of(weapon_type)
	if mode == "lob":  # a grenade: the arc and the blast, no tracer
		WeaponEffects.create_muzzle_flash(parent, from_pos, direction)
		GrenadeFX.lob(parent, from_pos, to_pos, RangedWeapon.create_weapon(weapon_type).blast_radius)
		return

	# Create tracer and muzzle flash (skip for flamethrower)
	if mode != "flame":
		WeaponEffects.create_muzzle_flash(parent, from_pos, direction)
		WeaponEffects.create_tracer(parent, from_pos, to_pos)

		if hit:
			WeaponEffects.create_hit_effect(parent, to_pos, Vector3.UP, "environment")
