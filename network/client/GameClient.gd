## Main game client
extends Node
class_name GameClient

signal connected_to_server
signal connection_failed
signal disconnected_from_server
signal map_info_received(seed_value: int, map_radius: int)

const PORT: int = 7777
const CONNECT_TIMEOUT: float = 8.0

var peer: ENetMultiplayerPeer = null
var client_world: ClientWorld = null  # Created by GameSceneController when the game scene loads
var local_player_id: int = -1
var is_connected_to_server: bool = false
var is_connecting: bool = false

# Map info from the server, kept until the game scene generates the map
var pending_map_seed: int = 0
var pending_map_radius: int = MapGenerator.MATCH_MAP_RADIUS
var pending_destroyed_tiles: Array = []
var pending_supply_drops: Array = []  # [ground_pos, loot_seed, container_id] received before the map
var pending_zone: Array = []  # zone events received before the map: [kind, coords, seconds, center, radius, msec]
var pending_map_events: Array = []  # map events received before the map: [kind, data, elapsed, msec]
var has_map_info: bool = false

var _connect_timer: float = 0.0

func _ready():
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float):
	if not is_connecting:
		return
	_connect_timer += delta
	if _connect_timer >= CONNECT_TIMEOUT:
		print("[GameClient] ✗ Connection timed out")
		_on_connection_failed()

func ensure_client_world():
	return client_world if is_instance_valid(client_world) else null

func connect_to_server(ip: String = "127.0.0.1", port: int = PORT) -> bool:
	print("[GameClient] Attempting to connect to server %s:%d..." % [ip, port])
	NetClock.reset()  # a new server, a new clock

	if is_connected_to_server or is_connecting:
		print("[GameClient] ERROR: Already connected or connecting!")
		return false

	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)

	if error != OK:
		push_error("[GameClient] Failed to create client: %d" % error)
		peer = null
		return false

	multiplayer.multiplayer_peer = peer
	is_connecting = true
	_connect_timer = 0.0
	print("[GameClient] ✓ Connection request sent to %s:%d, waiting for response..." % [ip, port])
	return true

func disconnect_from_server():
	var was_connected = is_connected_to_server
	is_connecting = false
	is_connected_to_server = false

	# Close the peer even if we were still connecting, otherwise ENet keeps retrying
	if peer:
		peer.close()
		peer = null
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	if was_connected:
		disconnected_from_server.emit()
		print("[GameClient] ✓ Disconnected from server")

func send_input(input_data: Dictionary):
	if not is_connected_to_server:
		return

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.send_player_input(input_data)

func _on_connected_to_server():
	print("[GameClient] ✓ Successfully connected to server!")
	is_connecting = false
	is_connected_to_server = true
	local_player_id = multiplayer.get_unique_id()
	print("[GameClient] Assigned player ID: %d" % local_player_id)
	connected_to_server.emit()

func _on_connection_failed():
	if not is_connecting:
		return
	print("[GameClient] ✗ Connection failed! (server not running, wrong IP/port, firewall?)")
	is_connecting = false
	is_connected_to_server = false
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_failed.emit()

func _on_server_disconnected():
	print("[GameClient] ✗ Server disconnected!")
	is_connected_to_server = false
	is_connecting = false
	disconnected_from_server.emit()

## Map seed + radius + already destroyed tiles, sent by the server right after connecting
func receive_map_info(seed_value: int, map_radius: int, destroyed_tiles: Array):
	pending_map_seed = seed_value
	pending_map_radius = map_radius
	pending_destroyed_tiles = destroyed_tiles.duplicate()
	has_map_info = true
	map_info_received.emit(seed_value, map_radius)

	# Game scene already loaded (late join): generate right away
	if is_instance_valid(client_world):
		client_world.generate_map_with_seed(seed_value, map_radius)
