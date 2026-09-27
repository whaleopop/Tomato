## Manages network synchronization for loot containers and items.
## Lives at /root/NetworkManager/NetworkLootManager on every peer: RPCs are routed by node
## path, so server and clients must have it at exactly the same place.
## Containers are spawned deterministically from the map seed on every peer, therefore they
## are registered in the same order and get the same ids everywhere. Items dropped by a
## container get ids derived from the container id (see LootContainer._register_network_item).
extends Node
class_name NetworkLootManager

signal container_opened_network(container_id: int, player_id: int)
signal item_picked_up_network(item_id: int, player_id: int)

const PICKUP_RANGE_TOLERANCE: float = 3.5  # Server entity may lag slightly behind the client

var next_container_id: int = 1

# Tracking dictionaries
var containers: Dictionary = {}  # container_id -> LootContainer
var items: Dictionary = {}  # item_id -> LootItem

# What already happened to the loot (late joiners get it with the map info; on clients also
# events that arrived before our copy of that container / item existed)
var opened_ids: Dictionary = {}  # container_id -> true
var picked_ids: Dictionary = {}  # item_id -> true
var supply_drops: Array = []     # server: [ground_pos, loot_seed, container_id, spawn_time_s]
const SUPPLY_DROP_FALL_TIME: float = 4.0

# Set by NetworkManager when the server/client starts
var is_server: bool = false

func reset():
	next_container_id = 1
	containers.clear()
	items.clear()
	opened_ids.clear()
	picked_ids.clear()
	supply_drops.clear()

## Server: loot history for a player joining mid-match
func get_late_join_state() -> Dictionary:
	var now = Time.get_ticks_msec() / 1000.0
	var drops: Array = []
	for d in supply_drops:
		drops.append([d[0], d[1], d[2], now - d[3] > SUPPLY_DROP_FALL_TIME])
	return {"opened": opened_ids.keys(), "picked": picked_ids.keys(), "drops": drops}

## Client: apply it (containers / items not generated yet are handled when they register)
func apply_late_join_state(state: Dictionary, game_client: GameClient):
	for id in state.get("opened", []):
		opened_ids[int(id)] = true
	for id in state.get("picked", []):
		picked_ids[int(id)] = true
	if game_client:
		game_client.pending_supply_drops.append_array(state.get("drops", []))

func record_supply_drop(ground_pos: Vector3, loot_seed: int, container_id: int):
	supply_drops.append([ground_pos, loot_seed, container_id, Time.get_ticks_msec() / 1000.0])

## Register a container for network tracking. forced_id is used by clients to mirror
## containers the server created at runtime (supply drops).
func register_container(container: LootContainer, forced_id: int = -1) -> int:
	var container_id = forced_id if forced_id > 0 else next_container_id
	next_container_id = max(next_container_id, container_id + 1)

	containers[container_id] = container
	container.set_meta("network_id", container_id)

	if not container.container_opened.is_connected(_on_container_opened):
		container.container_opened.connect(_on_container_opened.bind(container_id))

	# Opened before we (a late joiner) had this container: its loot is just lying there
	if not is_server and opened_ids.has(container_id):
		container.open_instantly()

	return container_id

## Register an item with a deterministic id
func register_item(item: LootItem, item_id: int) -> int:
	# Somebody picked it up before our copy existed
	if not is_server and picked_ids.has(item_id):
		item.is_active = false
		item.queue_free()
		return item_id
	items[item_id] = item
	item.set_meta("network_id", item_id)
	if not item.item_picked_up.is_connected(_on_item_picked_up):
		item.item_picked_up.connect(_on_item_picked_up.bind(item_id))
	return item_id

## Called when a container is opened locally
func _on_container_opened(_container: LootContainer, player: Player, container_id: int):
	var player_id = player.entity_id if player else 0
	containers.erase(container_id)
	opened_ids[container_id] = true
	# Server: however it got opened (E key, shot to pieces...), everyone opens it too
	if is_server:
		_broadcast_container_opened(container_id, player_id)
	container_opened_network.emit(container_id, player_id)

## Called when an item is picked up locally
func _on_item_picked_up(_item: LootItem, player: Player, item_id: int):
	var player_id = player.entity_id if player else 0

	if is_server:
		# Server: pickup is authoritative, tell everyone
		_broadcast_item_picked(item_id, player_id)
	elif player and player.is_local_player:
		# Client: local prediction already applied the effect, ask the server to confirm
		_request_item_pickup(item_id)

	items.erase(item_id)
	picked_ids[item_id] = true
	item_picked_up_network.emit(item_id, player_id)

func _has_peer() -> bool:
	return multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)

func _broadcast_container_opened(container_id: int, player_id: int):
	if _has_peer():
		_client_container_opened.rpc(container_id, player_id)

func _broadcast_item_picked(item_id: int, player_id: int):
	if _has_peer():
		_client_item_picked.rpc(item_id, player_id)

## Request to pickup an item (client -> server)
func _request_item_pickup(item_id: int):
	if _has_peer():
		_server_request_pickup.rpc_id(1, item_id)

## Request to open a container (local player pressed E)
func request_open_container(container_id: int):
	if is_server or not _has_peer():
		_server_open_container(container_id, multiplayer.get_unique_id() if _has_peer() else 1)
	else:
		_server_request_open_container.rpc_id(1, container_id)

# ============ RPC Methods ============

## Server receives container open request
@rpc("any_peer", "call_remote", "reliable")
func _server_request_open_container(container_id: int):
	if not is_server:
		return
	_server_open_container(container_id, multiplayer.get_remote_sender_id())

func _server_open_container(container_id: int, player_id: int):
	if not containers.has(container_id):
		return

	var container = containers[container_id]
	if not is_instance_valid(container):
		containers.erase(container_id)
		return

	if container.is_opened or container.is_opening:
		return

	# Distance check against the authoritative entity (skipped if it is not known yet)
	var player = _get_server_player(player_id)
	if player and container.global_position.distance_to(player.global_position) > LootContainer.INTERACT_RANGE + PICKUP_RANGE_TOLERANCE:
		print("[NetworkLootManager] Player %d too far from container %d" % [player_id, container_id])
		return

	# Open without the per-player range check (validated above). Clients are told in
	# _on_container_opened and roll the same (seeded) loot.
	container.interact(null)

## Server receives item pickup request
@rpc("any_peer", "call_remote", "reliable")
func _server_request_pickup(item_id: int):
	if not is_server:
		return
	var sender_id = multiplayer.get_remote_sender_id()

	if not items.has(item_id):
		return

	var item = items[item_id]
	if not is_instance_valid(item) or not item.is_active:
		items.erase(item_id)
		return

	var player = _get_server_player(sender_id)
	if not player:
		return

	var distance = item.global_position.distance_to(player.global_position)
	if distance > LootItem.INTERACT_RANGE + PICKUP_RANGE_TOLERANCE:
		print("[NetworkLootManager] Player %d too far from item %d" % [sender_id, item_id])
		return

	# Applies the effect to the server entity and broadcasts via _on_item_picked_up
	item._pickup(player)

## Client receives container opened notification
@rpc("authority", "call_remote", "reliable")
func _client_container_opened(container_id: int, _player_id: int):
	if not containers.has(container_id):
		opened_ids[container_id] = true  # our map is still generating: open it on register
		return

	var container = containers[container_id]
	if not is_instance_valid(container):
		containers.erase(container_id)
		return

	if not container.is_opened and not container.is_opening:
		container.interact(null)

## Client receives item picked notification
@rpc("authority", "call_remote", "reliable")
func _client_item_picked(item_id: int, player_id: int):
	if not items.has(item_id):
		picked_ids[item_id] = true  # our copy doesn't exist yet: drop it when it registers
		return

	var item = items[item_id]
	items.erase(item_id)
	if not is_instance_valid(item) or not item.is_active:
		return

	if player_id == multiplayer.get_unique_id():
		# The server says we got it (e.g. our entity walked over it first): apply locally
		var local_player = _get_local_player()
		if local_player:
			item._pickup(local_player)
			return

	item.is_active = false
	item._play_pickup_effect()
	item.queue_free()

## Mirror a supply drop that the server spawned
func spawn_mirrored_supply_drop(spawner: LootSpawner, ground_pos: Vector3, loot_seed: int, container_id: int, landed: bool = false):
	if not spawner:
		return
	var container = spawner.spawn_supply_drop_at(ground_pos, loot_seed, landed)
	register_container(container, container_id)

# ============ Utility Methods ============

func _get_server_player(player_id: int) -> Player:
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_server and network_manager.game_server.server_world:
		return network_manager.game_server.server_world.get_player(player_id)
	return null

func _get_local_player() -> Player:
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_client and network_manager.game_client.client_world:
		return network_manager.game_client.client_world.local_player
	return null

## Get container by network ID
func get_container(container_id: int) -> LootContainer:
	return containers.get(container_id)

## Get item by network ID
func get_item(item_id: int) -> LootItem:
	return items.get(item_id)
