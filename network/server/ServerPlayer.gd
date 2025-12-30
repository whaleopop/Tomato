## Server-side player representation
extends Node
class_name ServerPlayer

var player_id: int = -1
var player_entity: Player = null
var last_input_time: float = 0.0

# Lag compensation: buffer of recent inputs with timestamps
var input_buffer: Array = []
const MAX_INPUT_BUFFER_SIZE: int = 60  # ~2 seconds at 30 inputs/sec
var last_processed_sequence: int = -1

func _ready():
	pass

func process_input(input_data: Dictionary):
	if player_entity == null:
		return

	# Check sequence number to avoid processing old/duplicate inputs
	if input_data.has("sequence"):
		var seq = input_data["sequence"]
		if seq <= last_processed_sequence:
			# Old or duplicate input, ignore
			return
		last_processed_sequence = seq

	# Store input in buffer for lag compensation
	input_buffer.append({
		"data": input_data,
		"server_time": Time.get_ticks_msec(),
		"client_time": input_data.get("timestamp", 0)
	})

	# Trim buffer if too large
	while input_buffer.size() > MAX_INPUT_BUFFER_SIZE:
		input_buffer.pop_front()

	# Process movement input
	if input_data.has("move_direction"):
		var move_direction = Vector3(
			input_data.move_direction.x,
			0.0,
			input_data.move_direction.y
		)
		var movement = player_entity.get_component("MovementComponent")
		if movement:
			movement.set_move_direction(move_direction)
	
	# Process attack input
	if input_data.has("attack") and input_data.attack:
		var combat = player_entity.get_component("CombatComponent")
		if combat:
			var target_pos = Vector3.ZERO
			if input_data.has("target_position"):
				target_pos = Vector3(
					input_data.target_position.x,
					input_data.target_position.y,
					input_data.target_position.z
				)
			combat.attack(target_pos)
	
	# Process ability input
	if input_data.has("ability_index"):
		var ability_component = player_entity.get_component("AbilityComponent")
		if ability_component:
			var target_pos = Vector3.ZERO
			if input_data.has("target_position"):
				target_pos = Vector3(
					input_data.target_position.x,
					input_data.target_position.y,
					input_data.target_position.z
				)
			ability_component.activate_ability(input_data.ability_index, target_pos)
	
	last_input_time = Time.get_ticks_msec() / 1000.0

func get_sync_data() -> Dictionary:
	if player_entity == null:
		return {}
	
	# Get position from entity
	var position = player_entity.global_position if player_entity else Vector3.ZERO
	
	var data = {
		"player_id": player_id,
		"position": player_entity.global_position,
		"rotation": player_entity.global_rotation,
	}
	
	# Add component data
	var health = player_entity.get_component("HealthComponent")
	if health:
		data["health"] = health.current_health
		data["max_health"] = health.max_health
	
	var movement = player_entity.get_component("MovementComponent")
	if movement:
		data["velocity"] = movement.velocity
		data["is_moving"] = movement.is_moving
	
	return data

