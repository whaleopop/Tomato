## Network synchronization for spawn cutscene
extends Node
class_name NetworkCutscene

signal cutscene_data_received(data: Dictionary)
signal time_sync_received(server_time: float, phase: int)
signal cutscene_finished_on_server

var is_server: bool = false
var cutscene_active: bool = false
var cutscene_start_time: float = 0.0
var sync_interval: float = 0.5
var sync_timer: float = 0.0

# Cutscene data
var cutscene_data: Dictionary = {}

func _ready():
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		is_server = network_manager.is_server()

func _process(delta: float):
	if not cutscene_active:
		return

	if is_server:
		sync_timer += delta
		if sync_timer >= sync_interval:
			sync_timer = 0.0
			_broadcast_time_sync()

# === SERVER FUNCTIONS ===

func server_start_cutscene(data: Dictionary):
	if not is_server:
		push_error("[NetworkCutscene] server_start_cutscene called on client!")
		return

	cutscene_data = data
	cutscene_start_time = Time.get_ticks_msec() / 1000.0
	cutscene_data["start_time"] = cutscene_start_time
	cutscene_active = true

	print("[NetworkCutscene] Server starting cutscene with %d players" % data.get("spawn_positions", {}).size())

	# Broadcast to all clients
	_broadcast_cutscene_start.rpc(cutscene_data)

func server_end_cutscene():
	if not is_server:
		return

	cutscene_active = false
	_broadcast_cutscene_end.rpc()

func _broadcast_time_sync():
	if not is_server or not cutscene_active:
		return

	var elapsed = (Time.get_ticks_msec() / 1000.0) - cutscene_start_time
	var phase = _calculate_phase(elapsed)

	_receive_time_sync.rpc(elapsed, phase)

func _calculate_phase(elapsed: float) -> int:
	# Phase durations from SpawnCutsceneController
	const APPROACH = 6.0
	const EXPLOSION = 2.0
	const SCATTER = 5.0

	if elapsed < APPROACH:
		return 0  # APPROACH
	elif elapsed < APPROACH + EXPLOSION:
		return 1  # EXPLOSION
	elif elapsed < APPROACH + EXPLOSION + SCATTER:
		return 2  # SCATTER
	else:
		return 3  # LANDING

# === RPC FUNCTIONS ===

@rpc("authority", "call_remote", "reliable")
func _broadcast_cutscene_start(data: Dictionary):
	print("[NetworkCutscene] Client received cutscene start data")
	cutscene_data = data
	cutscene_start_time = data.get("start_time", Time.get_ticks_msec() / 1000.0)
	cutscene_active = true

	# Store data in GameManager for cutscene controller to access
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.cutscene_spawn_positions = data.get("spawn_positions", {})
		game_manager.cutscene_player_characters = data.get("player_characters", {})

	cutscene_data_received.emit(data)

@rpc("authority", "call_remote", "unreliable")
func _receive_time_sync(server_elapsed: float, server_phase: int):
	if is_server:
		return

	time_sync_received.emit(server_elapsed, server_phase)

	# Update cutscene controller if exists
	var cutscene = get_tree().get_first_node_in_group("spawn_cutscene")
	if cutscene and cutscene.has_method("sync_time"):
		cutscene.sync_time(server_elapsed, server_phase)

@rpc("authority", "call_remote", "reliable")
func _broadcast_cutscene_end():
	cutscene_active = false
	cutscene_finished_on_server.emit()

# === CLIENT FUNCTIONS ===

func client_request_cutscene_data():
	if is_server:
		return

	_request_cutscene_data.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_cutscene_data():
	if not is_server:
		return

	var peer_id = multiplayer.get_remote_sender_id()
	if cutscene_active:
		# Send current data with adjusted time
		var elapsed = (Time.get_ticks_msec() / 1000.0) - cutscene_start_time
		var late_join_data = cutscene_data.duplicate()
		late_join_data["elapsed_time"] = elapsed
		late_join_data["current_phase"] = _calculate_phase(elapsed)

		_receive_late_join_data.rpc_id(peer_id, late_join_data)

@rpc("authority", "call_remote", "reliable")
func _receive_late_join_data(data: Dictionary):
	print("[NetworkCutscene] Late joiner received cutscene data")
	cutscene_data = data
	cutscene_active = true

	# Fast-forward cutscene if needed
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.cutscene_spawn_positions = data.get("spawn_positions", {})
		game_manager.cutscene_player_characters = data.get("player_characters", {})
		game_manager.cutscene_fast_forward = true
		game_manager.cutscene_elapsed = data.get("elapsed_time", 0.0)

	cutscene_data_received.emit(data)

# === HELPER FUNCTIONS ===

func get_elapsed_time() -> float:
	if cutscene_start_time == 0.0:
		return 0.0
	return (Time.get_ticks_msec() / 1000.0) - cutscene_start_time

func is_cutscene_active() -> bool:
	return cutscene_active

func get_spawn_positions() -> Dictionary:
	return cutscene_data.get("spawn_positions", {})

func get_player_characters() -> Dictionary:
	return cutscene_data.get("player_characters", {})
