## Server tick system for authoritative updates
extends Node
class_name TickSystem

signal tick_processed(tick: int)

const TICK_RATE: float = 1.0 / 20.0  # 20 ticks per second
const SYNC_RATE: float = 1.0 / 10.0  # Sync 10 times per second
const TICK_DELTA: float = TICK_RATE  # Delta time for each tick

var tick_timer: float = 0.0
var sync_timer: float = 0.0
var current_tick: int = 0
var server: GameServer = null

func _ready():
	print("[TickSystem] Initialized with tick rate: %.1f ticks/sec" % (1.0 / TICK_RATE))

func _process(delta: float):
	tick_timer += delta
	sync_timer += delta
	
	# Process game ticks
	if tick_timer >= TICK_RATE:
		tick_timer = 0.0
		_process_tick()
	
	# Sync with clients
	if sync_timer >= SYNC_RATE:
		sync_timer = 0.0
		_sync_clients()

func _process_tick():
	current_tick += 1

	if server == null:
		return

	# Update all player entities with server-authoritative logic
	for player_id in server.players:
		var server_player = server.players[player_id]
		if server_player and server_player.player_entity:
			_update_player_entity(server_player.player_entity)

	# Update destruction system if available
	if server.server_world and server.server_world.has_method("tick_update"):
		server.server_world.tick_update(TICK_DELTA)

	# Emit tick signal for other systems to hook into
	tick_processed.emit(current_tick)

func _update_player_entity(player: Player):
	if not is_instance_valid(player):
		return

	# Update movement component (physics simulation)
	var movement = player.get_component("MovementComponent")
	if movement and movement.enabled:
		movement.update(TICK_DELTA)

	# Update combat component (cooldowns, weapon state)
	var combat = player.get_component("CombatComponent")
	if combat and combat.enabled:
		combat.update(TICK_DELTA)

	# Update ability component (cooldowns)
	var ability = player.get_component("AbilityComponent")
	if ability and ability.enabled:
		ability.update(TICK_DELTA)

	# Update health component (regeneration, damage over time)
	var health = player.get_component("HealthComponent")
	if health and health.enabled:
		health.update(TICK_DELTA)
	
func _sync_clients():
	if server == null:
		return
	
	# Collect world state
	var world_state = _collect_world_state()
	
	# Send to all clients via GameServer
	if server and is_instance_valid(server):
		server.send_world_state(world_state)

func _collect_world_state() -> Dictionary:
	var state = {
		"tick": current_tick,
		"timestamp": Time.get_ticks_msec(),
		"players": {},
	}

	# Add player states
	if server:
		for player_id in server.players:
			var server_player = server.players[player_id]
			state.players[player_id] = server_player.get_sync_data()

	return state

func set_server(p_server: GameServer):
	server = p_server

