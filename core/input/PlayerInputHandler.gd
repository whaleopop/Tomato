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
		# Transform movement direction relative to camera rotation
		var camera = get_viewport().get_camera_3d() as CameraController
		if camera:
			move_direction = camera.transform_direction(move_direction)
		input_data["move_direction"] = move_direction

	# Capture jump input (Space)
	if Input.is_action_just_pressed("jump"):
		input_data["jump"] = true

	# Capture sprint input (Shift)
	input_data["sprint"] = Input.is_action_pressed("sprint")
	
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

	# Capture interact input (E key)
	if Input.is_action_just_pressed("interact"):
		var interact_target = _find_interact_target()
		if interact_target:
			input_data["interact"] = true
			# Handle locally for immediate feedback
			_handle_interact(interact_target)

	# Capture reload input (R key)
	if Input.is_action_just_pressed("reload"):
		input_data["reload"] = true
		# Handle locally for immediate feedback
		_handle_reload()

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
	if movement:
		# Apply movement direction
		if input_data.has("move_direction"):
			var move_dir = Vector3(
				input_data.move_direction.x,
				0.0,
				input_data.move_direction.y
			)
			movement.set_move_direction(move_dir)
		else:
			# No movement input - stop moving
			movement.set_move_direction(Vector3.ZERO)

		# Apply jump
		if input_data.has("jump") and input_data.jump:
			movement.jump()

		# Apply sprint
		if input_data.has("sprint"):
			movement.set_sprint(input_data.sprint)

	# Note: Attacks and abilities are handled server-side for server-authoritative gameplay

## Find nearest interactable object (container) within range
func _find_interact_target() -> Node3D:
	if not player:
		return null

	var world_3d = get_viewport().world_3d
	if not world_3d:
		return null

	var space_state = world_3d.direct_space_state
	var player_pos = player.global_position + Vector3(0, 0.5, 0)

	# Use sphere query to find nearby containers
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 2.5  # Interact range
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, player_pos)
	query.collision_mask = 8  # Layer 4 for interactive objects (containers)

	var results = space_state.intersect_shape(query)

	var closest_container: Node3D = null
	var closest_dist: float = INF

	for result in results:
		var collider = result.collider
		if collider is LootContainer and not collider.is_opened and not collider.is_opening:
			var dist = player_pos.distance_to(collider.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_container = collider

	return closest_container

## Handle interact with target (called locally for immediate feedback)
func _handle_interact(target: Node3D):
	if target is LootContainer:
		# Try to use network loot manager if available
		var loot_manager = _get_loot_manager()
		if loot_manager and target.has_meta("network_id"):
			var container_id = target.get_meta("network_id")
			loot_manager.request_open_container(container_id)
		else:
			# Fallback to local interaction (offline mode)
			target.interact(player)

## Get the network loot manager
func _get_loot_manager() -> NetworkLootManager:
	# Try client world first
	var client_world = get_node_or_null("/root/NetworkManager/GameClient/ClientWorld")
	if client_world and client_world.loot_manager:
		return client_world.loot_manager

	# Try server world
	var server_world = get_node_or_null("/root/NetworkManager/GameServer/ServerWorld")
	if server_world and server_world.loot_manager:
		return server_world.loot_manager

	return null

## Handle reload (called locally for immediate feedback)
func _handle_reload():
	if not player:
		return

	var combat = player.get_component("CombatComponent")
	if combat:
		combat.start_reload()

