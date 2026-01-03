## Controller for spawn selection scene - handles network logic
extends Node
class_name SpawnSelectController

var spawn_menu: SpawnSelectMenu = null
var network_lobby: NetworkLobby = null
var is_host: bool = false

func _ready():
	# Find or create spawn menu
	spawn_menu = get_tree().get_first_node_in_group("spawn_menu")
	if not spawn_menu:
		spawn_menu = get_parent() as SpawnSelectMenu
	if spawn_menu:
		spawn_menu.add_to_group("spawn_menu")

	# Check if we're the host
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		is_host = network_manager.is_server()

	# Setup network
	_setup_network()

	# Connect to spawn menu signals
	if spawn_menu:
		spawn_menu.spawn_confirmed.connect(_on_spawn_confirmed)
		spawn_menu.ready_toggled.connect(_on_ready_toggled)

	# Request initial state and set player name
	if network_lobby:
		await get_tree().process_frame
		# Send player name based on selected character
		_send_player_name()
		# Request map data (especially important for clients)
		if not is_host:
			network_lobby.client_request_map_data()
		network_lobby.client_request_state()

func _send_player_name():
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.selected_character:
		var char_name = game_manager.selected_character.character_name
		# Generate nickname: CharacterName_RandomNumber
		var nickname = "%s_%d" % [char_name, randi() % 1000]
		if network_lobby:
			network_lobby.client_set_name(nickname)
			# Also send character class for model sync
			network_lobby.client_set_character(char_name)

func _setup_network():
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		return

	# Get NetworkLobby from NetworkManager (same path for both client and server)
	network_lobby = network_manager.get_network_lobby()

	if is_host:
		# Host - setup local host player in lobby
		var game_server = network_manager.game_server
		if game_server:
			# Setup local host player in lobby
			if game_server.lobby_manager:
				game_server.lobby_manager.add_player(1)  # Host is always ID 1

				# Setup available spawns if hex_grid is ready
				if game_server.server_world and game_server.server_world.hex_grid:
					game_server.lobby_manager.setup_available_spawns(game_server.server_world.hex_grid)
					_setup_host_map(game_server.server_world.hex_grid)

	# Connect signals
	if network_lobby:
		network_lobby.lobby_state_updated.connect(_on_lobby_state_updated)
		network_lobby.spawn_selection_result.connect(_on_spawn_selection_result)
		network_lobby.countdown_update.connect(_on_countdown_update)
		network_lobby.match_starting.connect(_on_match_starting)

func _setup_host_map(hex_grid: HexGrid):
	if not spawn_menu:
		return

	var grid_data: Dictionary = {}
	for coords in hex_grid.tiles.keys():
		var tile = hex_grid.get_tile(coords)
		if tile and not tile.is_destroyed:
			grid_data[coords] = {
				"biome": tile.biome_type,
				"height": tile.height
			}

	spawn_menu.setup(grid_data, [], 1)

func _on_spawn_confirmed(coords: Vector2i):
	if network_lobby:
		network_lobby.client_select_spawn(coords)

func _on_ready_toggled(is_ready: bool):
	if network_lobby:
		network_lobby.client_set_ready(is_ready)

func _on_lobby_state_updated(state: Dictionary):
	if not spawn_menu:
		return

	# Update reserved spawns
	var reserved = state.get("reserved_spawns", [])
	spawn_menu.update_reserved_spawns(reserved)

	# Update players list with names from server
	var players_ready_state = state.get("players_ready", {})
	var players_names_state = state.get("players_names", {})
	var players_data: Dictionary = {}
	for player_id in players_ready_state.keys():
		var player_name = players_names_state.get(player_id, "Player_%d" % player_id)
		players_data[player_id] = {
			"name": player_name,
			"ready": players_ready_state[player_id]
		}
	spawn_menu.update_players_list(players_data)

	# Check countdown
	var countdown = state.get("countdown", 0)
	if countdown > 0:
		spawn_menu.show_countdown(countdown)
	else:
		spawn_menu.hide_countdown()

func _on_spawn_selection_result(success: bool, coords: Vector2i):
	if success:
		print("[SpawnSelectController] Spawn selection confirmed at %s" % coords)
	else:
		print("[SpawnSelectController] Spawn selection failed at %s" % coords)
		# Could show error message in UI

func _on_countdown_update(seconds: int):
	if spawn_menu:
		spawn_menu.show_countdown(seconds)

func _on_match_starting():
	print("[SpawnSelectController] Match starting!")

	# Transition to game scene
	var scene_transition = get_node_or_null("/root/SceneTransition")
	if scene_transition:
		scene_transition.fade_to_scene("res://scenes/GameScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/GameScene.tscn")
