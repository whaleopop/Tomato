## Manages network synchronization for loot containers and items
## Handles server-authoritative loot spawning and pickup
extends Node
class_name NetworkLootManager

signal container_opened_network(container_id: int, player_id: int)
signal item_picked_up_network(item_id: int, player_id: int)
signal item_spawned_network(item_data: Dictionary)

# Unique ID counter for network objects
var next_container_id: int = 1
var next_item_id: int = 1

# Tracking dictionaries
var containers: Dictionary = {}  # container_id -> LootContainer
var items: Dictionary = {}  # item_id -> LootItem

# Is this running on server?
var is_server: bool = false

func _ready():
	# Determine if we're the server
	is_server = multiplayer.is_server() if multiplayer.has_multiplayer_peer() else false

## Register a container for network tracking
func register_container(container: LootContainer) -> int:
	var container_id = next_container_id
	next_container_id += 1

	containers[container_id] = container
	container.set_meta("network_id", container_id)

	# Connect signals
	container.container_opened.connect(_on_container_opened.bind(container_id))

	return container_id

## Register an item for network tracking
func register_item(item: LootItem) -> int:
	var item_id = next_item_id
	next_item_id += 1

	items[item_id] = item
	item.set_meta("network_id", item_id)

	# Connect signals
	item.item_picked_up.connect(_on_item_picked_up.bind(item_id))

	return item_id

## Called when a container is opened locally
func _on_container_opened(container: LootContainer, player: Player, container_id: int):
	var player_id = player.entity_id if player else 0

	if is_server:
		# Server: broadcast to all clients
		_broadcast_container_opened(container_id, player_id)
	else:
		# Client: already handled locally, server will validate
		pass

	container_opened_network.emit(container_id, player_id)

## Called when an item is picked up locally
func _on_item_picked_up(item: LootItem, player: Player, item_id: int):
	var player_id = player.entity_id if player else 0

	if is_server:
		# Server: validate and broadcast
		_broadcast_item_picked(item_id, player_id)
	else:
		# Client: request pickup from server
		_request_item_pickup(item_id)

	item_picked_up_network.emit(item_id, player_id)

## Broadcast container opened to all clients
func _broadcast_container_opened(container_id: int, player_id: int):
	if not multiplayer.has_multiplayer_peer():
		return

	rpc("_client_container_opened", container_id, player_id)

## Broadcast item picked up to all clients
func _broadcast_item_picked(item_id: int, player_id: int):
	if not multiplayer.has_multiplayer_peer():
		return

	rpc("_client_item_picked", item_id, player_id)

## Broadcast new item spawned to all clients
func broadcast_item_spawned(item: LootItem, position: Vector3):
	if not multiplayer.has_multiplayer_peer():
		return

	var item_id = register_item(item)
	var item_data = {
		"id": item_id,
		"type": item.item_type,
		"name": item.item_name,
		"value": item.item_value,
		"position": position
	}

	rpc("_client_spawn_item", item_data)
	item_spawned_network.emit(item_data)

## Request to pickup an item (client -> server)
func _request_item_pickup(item_id: int):
	if not multiplayer.has_multiplayer_peer():
		return

	rpc_id(1, "_server_request_pickup", item_id)

## Request to open a container (client -> server)
func request_open_container(container_id: int):
	if not multiplayer.has_multiplayer_peer():
		return

	if is_server:
		# Server can open directly
		_server_open_container(container_id, multiplayer.get_unique_id())
	else:
		# Client requests from server
		rpc_id(1, "_server_request_open_container", container_id)

# ============ RPC Methods ============

## Server receives container open request
@rpc("any_peer", "call_remote", "reliable")
func _server_request_open_container(container_id: int):
	var sender_id = multiplayer.get_remote_sender_id()
	_server_open_container(container_id, sender_id)

func _server_open_container(container_id: int, player_id: int):
	if not containers.has(container_id):
		print("[NetworkLootManager] Container %d not found" % container_id)
		return

	var container = containers[container_id]
	if not is_instance_valid(container):
		containers.erase(container_id)
		return

	if container.is_opened or container.is_opening:
		return

	# Find player entity
	var server_world = get_node_or_null("/root/NetworkManager/GameServer/ServerWorld")
	var player: Player = null
	if server_world:
		player = server_world.get_player(player_id)

	# Open the container (this will spawn items)
	container.interact(player)

	# Broadcast to all clients
	_broadcast_container_opened(container_id, player_id)

## Server receives item pickup request
@rpc("any_peer", "call_remote", "reliable")
func _server_request_pickup(item_id: int):
	var sender_id = multiplayer.get_remote_sender_id()

	if not items.has(item_id):
		print("[NetworkLootManager] Item %d not found" % item_id)
		return

	var item = items[item_id]
	if not is_instance_valid(item) or not item.is_active:
		items.erase(item_id)
		return

	# Find player entity
	var server_world = get_node_or_null("/root/NetworkManager/GameServer/ServerWorld")
	var player: Player = null
	if server_world:
		player = server_world.get_player(sender_id)

	if not player:
		return

	# Check distance
	var distance = item.global_position.distance_to(player.global_position)
	if distance > 2.0:  # Pickup range
		print("[NetworkLootManager] Player %d too far from item %d" % [sender_id, item_id])
		return

	# Apply effect server-side
	item._apply_effect(player)
	item.is_active = false

	# Broadcast pickup to all clients
	_broadcast_item_picked(item_id, sender_id)

	# Remove from tracking
	items.erase(item_id)

## Client receives container opened notification
@rpc("authority", "call_remote", "reliable")
func _client_container_opened(container_id: int, player_id: int):
	if not containers.has(container_id):
		return

	var container = containers[container_id]
	if not is_instance_valid(container):
		containers.erase(container_id)
		return

	# Open container locally (visual only if not our player)
	if not container.is_opened and not container.is_opening:
		container.is_opening = true
		container._play_open_animation()

	containers.erase(container_id)

## Client receives item picked notification
@rpc("authority", "call_remote", "reliable")
func _client_item_picked(item_id: int, player_id: int):
	if not items.has(item_id):
		return

	var item = items[item_id]
	if not is_instance_valid(item):
		items.erase(item_id)
		return

	# If we're not the picker, just show visual effect
	var my_id = multiplayer.get_unique_id()
	if player_id != my_id:
		item._play_pickup_effect()
		item.is_active = false
		if item.respawn_time <= 0:
			item.queue_free()

	items.erase(item_id)

## Client receives spawn item notification
@rpc("authority", "call_remote", "reliable")
func _client_spawn_item(item_data: Dictionary):
	var item = LootItem.new()
	item.item_type = item_data.get("type", LootItem.ItemType.HEALTH)
	item.item_name = item_data.get("name", "Item")
	item.item_value = item_data.get("value", 25.0)
	item.position = item_data.get("position", Vector3.ZERO)
	item.respawn_time = 0  # Network-spawned items don't respawn

	# Add to scene
	var world = get_node_or_null("/root/NetworkManager/GameClient/ClientWorld")
	if world:
		world.add_child(item)
	else:
		get_tree().current_scene.add_child(item)

	# Track item
	var item_id = item_data.get("id", next_item_id)
	next_item_id = max(next_item_id, item_id + 1)
	items[item_id] = item
	item.set_meta("network_id", item_id)
	item.item_picked_up.connect(_on_item_picked_up.bind(item_id))

# ============ Utility Methods ============

## Get container by network ID
func get_container(container_id: int) -> LootContainer:
	return containers.get(container_id)

## Get item by network ID
func get_item(item_id: int) -> LootItem:
	return items.get(item_id)

## Clean up invalid references
func cleanup():
	var invalid_containers: Array[int] = []
	for id in containers:
		if not is_instance_valid(containers[id]):
			invalid_containers.append(id)
	for id in invalid_containers:
		containers.erase(id)

	var invalid_items: Array[int] = []
	for id in items:
		if not is_instance_valid(items[id]):
			invalid_items.append(id)
	for id in invalid_items:
		items.erase(id)
