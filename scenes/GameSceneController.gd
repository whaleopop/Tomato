## Game scene controller - manages the actual game scene
extends Node3D
class_name GameSceneController

signal game_ready

const MAP_WAIT_TIMEOUT: float = 30.0
const PLAYER_WAIT_TIMEOUT: float = 30.0

var is_initialized: bool = false
var client_world: ClientWorld = null
var visibility_system: VisibilitySystem = null
var pause_menu: PauseMenu = null
var loading_overlay: Control = null

func _ready():
	add_to_group("game_scene")

	# Keep mouse visible - we draw custom crosshair at mouse position
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_show_loading("Loading map...")

	await get_tree().process_frame
	_initialize_game()

func _initialize_game():
	if is_initialized:
		return
	is_initialized = true

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_server():
		print("[GameSceneController] Running as HOST")
		await _setup_as_host()
	elif network_manager and network_manager.game_client:
		print("[GameSceneController] Running as CLIENT")
		await _setup_as_client()
	else:
		print("[GameSceneController] No network - offline/debug mode")
		await _setup_offline_debug()

	_hide_loading()
	game_ready.emit()

# ---------------------------------------------------------------- host

func _setup_as_host():
	var network_manager = get_node_or_null("/root/NetworkManager")
	var game_server: GameServer = network_manager.game_server
	var server_world: ServerWorld = game_server.server_world

	client_world = ClientWorld.new()
	client_world.name = "ClientWorld"
	add_child(client_world)

	if not server_world.is_map_ready:
		await server_world.map_ready
	if not is_inside_tree():
		return

	# One map, one set of loot, one entity per player on the host
	client_world.adopt_server_world(server_world)
	visibility_system = client_world.visibility_system

	# Spawn where the host chose in the lobby (reserved by ServerWorld at match start)
	var spawn_pos = server_world.host_spawn_position if server_world.has_host_spawn else Vector3.ZERO
	if spawn_pos == Vector3.ZERO and server_world.hex_grid:
		spawn_pos = game_server.lobby_manager.get_spawn_position(1, server_world.hex_grid)
	if spawn_pos == Vector3.ZERO:
		spawn_pos = server_world.get_random_spawn_point()

	var player = Player.new()
	player.entity_id = 1
	player.name = "Player_1"
	player.is_local_player = true
	client_world.players[1] = player
	client_world.local_player = player
	client_world.add_child(player)

	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.selected_character:
		player.setup_character(game_manager.selected_character)

	player.spawn(spawn_pos)
	player.give_starting_loadout()

	# The host's local player IS the authoritative server entity for id 1
	server_world.register_host_player(player)

	_setup_local_player(player)
	print("[GameSceneController] ✓ Host spawned at %s" % spawn_pos)

# ---------------------------------------------------------------- client

func _setup_as_client():
	var network_manager = get_node_or_null("/root/NetworkManager")
	var game_client: GameClient = network_manager.game_client

	client_world = ClientWorld.new()
	client_world.name = "ClientWorld"
	add_child(client_world)
	game_client.client_world = client_world

	# Map info normally arrived while we were in the lobby
	var waited := 0.0
	while not client_world.is_map_ready and waited < MAP_WAIT_TIMEOUT:
		if game_client.has_map_info and not client_world.is_generating:
			client_world.generate_map_with_seed(game_client.pending_map_seed, game_client.pending_map_radius)
		await get_tree().process_frame
		if not is_inside_tree():
			return
		waited += get_process_delta_time()

	if not client_world.is_map_ready:
		_fail_to_menu("The server did not send the map")
		return

	visibility_system = client_world.visibility_system
	_show_loading("Waiting for the server...")

	# Local player is spawned by the server's spawn RPC / world state
	waited = 0.0
	while not is_instance_valid(client_world.local_player) and waited < PLAYER_WAIT_TIMEOUT:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		waited += get_process_delta_time()

	if not is_instance_valid(client_world.local_player):
		_fail_to_menu("The server did not spawn your character")
		return

	_setup_local_player(client_world.local_player)
	print("[GameSceneController] ✓ Client setup complete")

func _fail_to_menu(reason: String):
	push_warning("[GameSceneController] " + reason)
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.last_error = reason
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.stop_all()
	var transition = get_node_or_null("/root/SceneTransition")
	if transition:
		transition.fade_to_scene("res://scenes/MainMenuScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")

# ---------------------------------------------------------------- offline

func _setup_offline_debug():
	_create_debug_floor()

	var map_generator = MapGenerator.new()
	add_child(map_generator)
	var hex_grid = await map_generator.generate_map(10, 12345)

	if hex_grid:
		var loot_spawner = LootSpawner.new()
		loot_spawner.name = "LootSpawner"
		add_child(loot_spawner)
		loot_spawner.setup(hex_grid, 12345)

		var cover_spawner = CoverSpawner.new()
		cover_spawner.name = "CoverSpawner"
		add_child(cover_spawner)
		cover_spawner.setup(hex_grid, 12345, CoverSpawner.container_tiles(hex_grid, loot_spawner))

		visibility_system = VisibilitySystem.new()
		visibility_system.name = "VisibilitySystem"
		add_child(visibility_system)
		visibility_system.setup(hex_grid)

	var player = Player.new()
	player.name = "DebugPlayer"
	player.is_local_player = true
	add_child(player)

	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.selected_character:
		player.setup_character(game_manager.selected_character)

	player.spawn(Vector3(0, 3, 0))
	player.give_starting_loadout()

	_setup_local_player(player)

func _create_debug_floor():
	# Invisible floor as safety net (in case player falls through map)
	var floor_body = StaticBody3D.new()
	floor_body.name = "SafetyFloor"

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collision.shape = shape
	collision.position = Vector3(0, -5, 0)

	floor_body.add_child(collision)
	add_child(floor_body)

# ---------------------------------------------------------------- local player

## Input, camera, HUD, menus and fog of war for whoever we control
func _setup_local_player(player: Player):
	var input_handler = PlayerInputHandler.new()
	input_handler.name = "InputHandler"
	player.add_child(input_handler)
	input_handler.setup(player)

	var camera = get_node_or_null("Camera")
	if camera and camera.has_method("set_target"):
		camera.set_target(player)

	var hud = get_node_or_null("UI/PlayerHUD")
	if hud and hud.has_method("setup"):
		var grid: HexGrid = null
		if client_world:
			grid = client_world.hex_grid
		elif visibility_system:
			grid = visibility_system.hex_grid
		hud.setup(player, grid)
		_connect_destruction_alerts(hud)

	_setup_inventory_menu(player)
	_setup_pause_menu()
	_register_player_visibility(player)

## "The edges are crumbling!" banner whenever a destruction wave hits
func _connect_destruction_alerts(hud):
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_server():
		var destruction = network_manager.game_server.server_world.destruction_system
		if destruction:
			destruction.destruction_phase_started.connect(func(_phase): hud.show_alert("The edges are crumbling!"))
	elif client_world:
		client_world.tiles_destroyed.connect(func(_count): hud.show_alert("The edges are crumbling!"))

func _setup_inventory_menu(player: Player):
	var ui_layer = get_node_or_null("UI")
	if not ui_layer or ui_layer.has_node("InventoryMenu"):
		return

	var inventory_menu = preload("res://ui/menus/InventoryMenu.gd").new()
	inventory_menu.name = "InventoryMenu"
	ui_layer.add_child(inventory_menu)

	var inventory_component = player.get_component("InventoryComponent")
	if inventory_component:
		inventory_menu.setup(inventory_component)

func _setup_pause_menu():
	var ui_layer = get_node_or_null("UI")
	if not ui_layer or pause_menu:
		return

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Freezing the tree would freeze the server/network for everyone
	var network_manager = get_node_or_null("/root/NetworkManager")
	pause_menu.pause_tree = not (network_manager and (network_manager.is_server() or network_manager.game_client))
	ui_layer.add_child(pause_menu)

func _register_player_visibility(player: Player):
	if not visibility_system:
		return

	visibility_system.local_player = player

	var combat = player.get_component("CombatComponent")
	var weapon: RangedWeapon = null
	if combat and combat.equipped_ranged_weapon:
		weapon = combat.equipped_ranged_weapon

	visibility_system.register_source(player, weapon)

	if combat:
		combat.weapon_changed.connect(func(_w):
			if combat.equipped_ranged_weapon and is_instance_valid(visibility_system):
				visibility_system.update_source_weapon(player, combat.equipped_ranged_weapon)
		)

# ---------------------------------------------------------------- loading overlay

func _show_loading(text: String):
	var ui_layer = get_node_or_null("UI")
	if not ui_layer:
		return
	if not loading_overlay:
		loading_overlay = UITheme.create_loading_overlay(text)
		ui_layer.add_child(loading_overlay)
	else:
		UITheme.set_loading_text(loading_overlay, text)

func _hide_loading():
	if not loading_overlay:
		return
	var overlay = loading_overlay
	loading_overlay = null
	var tween = create_tween()
	tween.tween_property(overlay, "modulate:a", 0.0, 0.35)
	tween.tween_callback(overlay.queue_free)
