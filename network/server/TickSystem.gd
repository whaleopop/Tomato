## Server tick system: broadcasts the authoritative world state to clients.
## Entities simulate themselves in Entity._physics_process; updating their components here as
## well made every server-side player move and cool down roughly twice as fast.
extends Node
class_name TickSystem

signal tick_processed(tick: int)

const TICK_RATE: float = 1.0 / 20.0  # 20 ticks per second
const SYNC_RATE: float = 1.0 / 20.0  # State sync 20 times per second
## Player fields that hardly change (~half of a player's 880 bytes): sent to a client when they
## change or at least every SLOW_EVERY ticks (the state is unreliable), not 20 times a second.
## The client keeps the last ones it got (ClientWorld.apply_world_state).
const SLOW_KEYS = ["character_name", "cosmetics", "stats"]
const SLOW_EVERY: int = 20

var tick_timer: float = 0.0
var sync_timer: float = 0.0
var current_tick: int = 0
var server: GameServer = null
var _slow_sent: Dictionary = {}  # peer -> {player_id: [tick, hash of the slow fields]}

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
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and server.rules and not server.dedicated:
		nm.mode_state.emit(server.rules.state_for(1))  # the host's own HUD (ModeView)
	var peers = server.multiplayer.get_peers()
	if peers.is_empty():
		return
	var full = _collect_world_state()
	var world = server.server_world
	var board = server.scoreboard() if current_tick % SLOW_EVERY == 0 else {}  # Tab, once a second
	var slow_hash = {}
	for player_id in full.players:
		var d: Dictionary = full.players[player_id]
		slow_hash[player_id] = hash([d.get("character_name"), d.get("cosmetics"), d.get("stats")])
	for peer_id in _slow_sent.keys():
		if not peers.has(peer_id):
			_slow_sent.erase(peer_id)
	# Every client gets its own copy: positions of players it can't see are left out, so a
	# modified client has nothing to reveal (server-side fog of war, see ServerVisibility)
	for peer_id in peers:
		var viewer = world.get_player(peer_id) if world else null
		var state = {"tick": full.tick, "timestamp": full.timestamp, "players": {}}
		if world and world.weed_spawner:
			state["npcs"] = world.weed_spawner.states_for(viewer)
		if server.rules and server.rules.mode != GameModes.BR:
			state["mode"] = server.rules.state_for(peer_id)
		if board.size() > 0:
			state["board"] = board
		var sent: Dictionary = _slow_sent.get_or_add(peer_id, {})
		for player_id in full.players:
			var data: Dictionary = full.players[player_id]
			if data.is_empty():
				state.players[player_id] = data  # connected, not spawned yet
				continue
			var own = player_id == peer_id
			var target = world.get_player(player_id) if world else null
			if not own and not ServerVisibility.can_see(viewer, target, world.hex_grid if world else null):
				# Still in the match (alive count, deaths), but where is none of your business
				state.players[player_id] = {"hidden": true, "health": data.get("health", 0.0), "max_health": data.get("max_health", 0.0)}
				continue
			var last = sent.get(player_id)
			var slow_known = last != null and last[1] == slow_hash[player_id] and full.tick - int(last[0]) < SLOW_EVERY
			if slow_known or (not own and (data.has("hits") or data.has("dealt"))):
				data = data.duplicate()
			if slow_known:
				for k in SLOW_KEYS:
					data.erase(k)
			else:
				sent[player_id] = [full.tick, slow_hash[player_id]]
			if not own:
				data.erase("hits")  # who shot them is only for their own client
				data.erase("dealt")  # same for their hitmarker
			state.players[player_id] = data
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
