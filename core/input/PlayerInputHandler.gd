## Handles player input for local player
extends Node
class_name PlayerInputHandler

signal input_sent(input_data: Dictionary)

var player: Player = null
var input_timer: float = 0.0
var input_rate: float = 1.0 / 30.0  # Send input 30 times per second
var input_sequence: int = 0  # Sequence number for lag compensation

func _ready():
	pass

func setup(p_player: Player):
	player = p_player
	set_process(true)

func _process(delta: float):
	if not player or not player.is_local_player:
		return
	
	input_timer += delta
	
	if input_timer >= input_rate:
		input_timer = 0.0
		_capture_and_send_input()

func _capture_and_send_input():
	var input_data = {
		"timestamp": Time.get_ticks_msec(),
		"sequence": input_sequence,
	}
	input_sequence += 1
	
	# Capture movement input (WASD)
	var move_direction = Vector2.ZERO
	
	if Input.is_action_pressed("move_up"):
		move_direction.y -= 1.0
	if Input.is_action_pressed("move_down"):
		move_direction.y += 1.0
	if Input.is_action_pressed("move_left"):
		move_direction.x -= 1.0
	if Input.is_action_pressed("move_right"):
		move_direction.x += 1.0
	
	if move_direction.length_squared() > 0.01:
		input_data["move_direction"] = move_direction
	
	# Capture attack input (Left Mouse Button)
	if Input.is_action_just_pressed("attack"):
		input_data["attack"] = true
		
		# Get target position from mouse
		var camera = get_viewport().get_camera_3d()
		if camera:
			var mouse_pos = get_viewport().get_mouse_position()
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 1000.0
			
			var world_3d = get_viewport().world_3d
			if world_3d:
				var space_state = world_3d.direct_space_state
				var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
				var result = space_state.intersect_ray(query)
				
				if result:
					input_data["target_position"] = result.position
	
	# Capture ability input (1-4 keys)
	for i in range(4):
		if Input.is_action_just_pressed("ability_%d" % (i + 1)):
			input_data["ability_index"] = i
			
			# Get target position from mouse
			var camera = get_viewport().get_camera_3d()
			if camera:
				var mouse_pos = get_viewport().get_mouse_position()
				var ray_origin = camera.project_ray_origin(mouse_pos)
				var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 1000.0
				
				var world_3d = get_viewport().world_3d
				if world_3d:
					var space_state = world_3d.direct_space_state
					var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
					var result = space_state.intersect_ray(query)
					
					if result:
						input_data["target_position"] = result.position
	
	# Send input to server if there's any
	if input_data.size() > 0:
		_send_input_to_server(input_data)
		
		# Also apply locally for immediate feedback
		_apply_input_locally(input_data)

func _send_input_to_server(input_data: Dictionary):
	var client = get_node_or_null("/root/NetworkManager/GameClient")
	if client:
		client.send_input(input_data)
		input_sent.emit(input_data)

func _apply_input_locally(input_data: Dictionary):
	if not player:
		return
	
	var movement = player.get_component("MovementComponent")
	if movement and input_data.has("move_direction"):
		var move_dir = Vector3(
			input_data.move_direction.x,
			0.0,
			input_data.move_direction.y
		)
		movement.set_move_direction(move_dir)
	
	# Note: Attacks and abilities are handled server-side for server-authoritative gameplay

