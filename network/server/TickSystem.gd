## Server tick system: broadcasts the authoritative world state to clients.
## Entities simulate themselves in Entity._physics_process; updating their components here as
## well made every server-side player move and cool down roughly twice as fast.
extends Node
class_name TickSystem

signal tick_processed(tick: int)

const TICK_RATE: float = 1.0 / 20.0  # 20 ticks per second
const SYNC_RATE: float = 1.0 / 20.0  # State sync 20 times per second

var tick_timer: float = 0.0
var sync_timer: float = 0.0
var current_tick: int = 0
var server: GameServer = null

func _process(delta: float):
	tick_timer += delta
	sync_timer += delta

	if tick_timer >= TICK_RATE:
		tick_timer -= TICK_RATE
		current_tick += 1
		tick_processed.emit(current_tick)

	if sync_timer >= SYNC_RATE:
		sync_timer = 0.0
		_sync_clients()

func _sync_clients():
	# Nothing to sync while players sit in the lobby
	if server == null or not is_instance_valid(server) or not server.game_started:
		return
	var peers = server.multiplayer.get_peers()
	if peers.is_empty():
		return
	var full = _collect_world_state()
	var world = server.server_world
	# Every client gets its own copy: positions of players it can't see are left out, so a
	# modified client has nothing to reveal (server-side fog of war, see ServerVisibility)
	for peer_id in peers:
		var viewer = world.get_player(peer_id) if world else null
		var state = {"tick": full.tick, "timestamp": full.timestamp, "players": {}}
		for player_id in full.players:
			var data: Dictionary = full.players[player_id]
			if data.is_empty() or player_id == peer_id:
				state.players[player_id] = data
				continue
			var target = world.get_player(player_id) if world else null
			if data.has("hits") or data.has("stamina"):
				data = data.duplicate()
				data.erase("hits")  # who shot them is only for their own client
				data.erase("stamina")  # and how out of breath they are
			if ServerVisibility.can_see(viewer, target, world.hex_grid if world else null):
				state.players[player_id] = data
			else:
				# Still in the match (alive count, deaths), but where is none of your business
				state.players[player_id] = {"hidden": true, "health": data.get("health", 0.0), "max_health": data.get("max_health", 0.0)}
		server.send_world_state_to(peer_id, state)

func _collect_world_state() -> Dictionary:
	var state = {
		"tick": current_tick,
		"timestamp": Time.get_ticks_msec(),
		"players": {},
	}

	for player_id in server.players:
		var server_player = server.players[player_id]
		state.players[player_id] = server_player.get_sync_data()

	return state

func set_server(p_server: GameServer):
	server = p_server
