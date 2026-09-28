## Controller for spawn selection scene - handles network logic
extends Node
class_name SpawnSelectController

var spawn_menu: SpawnSelectMenu = null
var network_lobby: NetworkLobby = null
var is_host: bool = false
var _leaving: bool = false

func _ready():
	spawn_menu = get_parent() as SpawnSelectMenu
	if spawn_menu:
		spawn_menu.add_to_group("spawn_menu")

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		is_host = network_manager.is_server()

	_setup_network()

	if spawn_menu:
		spawn_menu.spawn_confirmed.connect(_on_spawn_confirmed)
		spawn_menu.ready_toggled.connect(_on_ready_toggled)

	if network_lobby:
		await get_tree().process_frame
		_send_player_name()
		# Coming back from character select: the menu starts "not ready", tell the server
		network_lobby.client_set_ready(false)
		if not is_host:
			# Map may already have arrived while we were in character select
			if not network_lobby.last_map_data.is_empty():
				_apply_client_map(network_lobby.last_map_data)
			network_lobby.client_request_map_data()
		network_lobby.client_request_state()

func _send_player_name():
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.selected_character and network_lobby:
		var char_name = game_manager.selected_character.character_name
		# Nickname: CharacterName_RandomNumber
		network_lobby.client_set_name("%s_%d" % [tr(char_name), randi() % 1000])  # shown to everyone
		network_lobby.client_set_character(char_name)

func _setup_network():
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		return

	network_lobby = network_manager.get_network_lobby()

	if is_host:
		var game_server = network_manager.game_server
		if game_server and game_server.server_world:
			var server_world = game_server.server_world
			if server_world.is_map_ready:
				_setup_host_map(server_world.hex_grid)
			else:
				# Host clicked through the menus faster than the map generated
				if spawn_menu:
					spawn_menu.show_status("Generating map...")
				server_world.map_ready.connect(func(): _setup_host_map(server_world.hex_grid), CONNECT_ONE_SHOT)

	if network_lobby:
		network_lobby.lobby_state_updated.connect(_on_lobby_state_updated)
		network_lobby.spawn_selection_result.connect(_on_spawn_selection_result)
		network_lobby.countdown_update.connect(_on_countdown_update)
		network_lobby.match_starting.connect(_on_match_starting)

func _setup_host_map(hex_grid: HexGrid):
	if not spawn_menu or not is_instance_valid(hex_grid):
		return

	var grid_data: Dictionary = {}
	for coords in hex_grid.tiles.keys():
		var tile = hex_grid.get_tile(coords)
		if tile and not tile.is_destroyed:
			grid_data[coords] = {
				"biome": tile.biome_type,
				"height": tile.height,
				"spawnable": tile.can_spawn
			}

	var reserved: Array = []
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_server:
		reserved = network_manager.game_server.lobby_manager.get_all_reserved_spawns().keys()

	spawn_menu.setup(grid_data, reserved, 1)

func _apply_client_map(map_data: Dictionary):
	if spawn_menu and not spawn_menu.has_map():
		spawn_menu.setup(map_data.get("hex_grid", {}), map_data.get("reserved_spawns", []), multiplayer.get_unique_id())

func _on_spawn_confirmed(coords: Vector2i):
	if network_lobby:
		network_lobby.client_select_spawn(coords)

func _on_ready_toggled(is_ready: bool):
	if network_lobby:
		network_lobby.client_set_ready(is_ready)

func _on_lobby_state_updated(state: Dictionary):
	if not spawn_menu:
		return

	# Hide our own reservation area: only other players' areas are "taken" for us
	var my_id = multiplayer.get_unique_id()
	var reserved_by: Dictionary = state.get("reserved_by", {})
	var taken: Array = []
	for coords in reserved_by.keys():
		if reserved_by[coords] != my_id:
			taken.append(coords)
	spawn_menu.update_reserved_spawns(taken)

	# Players list with names from server
	var players_ready_state = state.get("players_ready", {})
	var players_names_state = state.get("players_names", {})
	var players_data: Dictionary = {}
	for player_id in players_ready_state.keys():
		players_data[player_id] = {
			"name": players_names_state.get(player_id, "Player_%d" % player_id),
			"ready": players_ready_state[player_id]
		}
	spawn_menu.update_players_list(players_data)

	var countdown = state.get("countdown", 0)
	if countdown > 0:
		spawn_menu.show_countdown(countdown)
	else:
		spawn_menu.hide_countdown()

func _on_spawn_selection_result(success: bool, coords: Vector2i):
	if not success and spawn_menu:
		spawn_menu.clear_selection("That spot was just taken - pick another one")
		print("[SpawnSelectController] Spawn selection failed at %s" % coords)

func _on_countdown_update(seconds: int):
	if spawn_menu:
		spawn_menu.show_countdown(seconds)

func _on_match_starting(late_join: bool):
	if _leaving:
		return
	_leaving = true

	var target = "res://scenes/cutscenes/SpawnCutscene.tscn"
	if late_join:
		# Match is already running: skip the intro cutscene
		print("[SpawnSelectController] Joining match in progress")
		target = "res://scenes/GameScene.tscn"
	else:
		print("[SpawnSelectController] Match starting - launching spawn cutscene!")
		_prepare_cutscene_data()

	var scene_transition = get_node_or_null("/root/SceneTransition")
	if scene_transition:
		scene_transition.fade_to_scene(target)
	else:
		get_tree().change_scene_to_file(target)

func _prepare_cutscene_data():
	var game_manager = get_node_or_null("/root/GameManager")
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not game_manager or not network_manager or not network_manager.is_server():
		return  # Clients receive it via NetworkLobby._receive_cutscene_data

	var game_server = network_manager.game_server
	if not game_server or not game_server.lobby_manager or not game_server.server_world:
		return

	var lobby = game_server.lobby_manager
	var hex_grid = game_server.server_world.hex_grid
	var spawn_positions: Dictionary = {}
	var player_characters: Dictionary = {}

	for player_id in lobby.players_spawn.keys():
		if hex_grid:
			spawn_positions[player_id] = lobby.get_spawn_position(player_id, hex_grid)
		player_characters[player_id] = lobby.get_player_character(player_id)

	game_manager.cutscene_spawn_positions = spawn_positions
	game_manager.cutscene_player_characters = player_characters
	game_manager.map_seed = game_server.server_world.map_seed
