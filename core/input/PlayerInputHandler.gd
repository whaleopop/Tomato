## Handles player input for local player
extends Node
class_name PlayerInputHandler

signal input_sent(input_data: Dictionary)

var player: Player = null
var input_timer: float = 0.0
var input_rate: float = 1.0 / 30.0  # Send input 30 times per second
var input_sequence: int = 0  # Sequence number for lag compensation

# Aim tracking
var current_aim_position: Vector3 = Vector3.ZERO

# Опциональный smooth aiming (0 = instant, >0 = smooth для геймпадов)
@export var aim_smoothing: float = 0.0  # Для мыши = 0 (мгновенно), для геймпада можно 0.2

# One-shot actions are latched every frame and sent with the next input tick: checking
# is_action_just_pressed only on the 30 Hz tick used to drop most key presses and clicks.
const LATCHED_ACTIONS = ["jump", "attack", "reload", "interact", "use_heal", "use_shield",
	"weapon_slot_1", "weapon_slot_2", "weapon_slot_3", "weapon_slot_4", "weapon_slot_5"]
var _latched: Dictionary = {}
var _was_blocked: bool = false
## Abilities cast on release: while the key is held AimOverlay (PlayerHUD) shows the area / range.
## A quick tap casts like before; RMB (top-down) or opening a menu cancels.
var aiming_ability: int = -1

var _clicked_empty: bool = false  # the empty-gun click sounded for this trigger pull

func _ready():
	pass

func setup(p_player: Player):
	player = p_player
	set_process(true)

func _process(delta: float):
	if not player or not player.is_local_player:
		return

	var blocked = _input_blocked()
	if blocked:
		_latched.clear()
		aiming_ability = -1
		if not _was_blocked:
			_send_stop()  # let go of everything when a menu opens or we die
		_was_blocked = true
		return
	_was_blocked = false

	# Always rotate player to face mouse (Weed Swarm: towards the weed the gun locked on)
	_update_aim_direction()
	_update_auto_aim(delta)

	for action in LATCHED_ACTIONS:
		if Input.is_action_just_pressed(action):
			_latched[action] = true
	_update_ability_aim()

	input_timer += delta

	if input_timer >= input_rate:
		input_timer = 0.0
		_capture_and_send_input()
		_latched.clear()

func _update_ability_aim():
	for i in 4:
		var action = "ability_%d" % (i + 1)
		if Input.is_action_just_pressed(action):
			aiming_ability = i
		if aiming_ability == i and not Input.is_action_pressed(action):
			_latched[action] = true  # released (or tapped within one frame): cast
			aiming_ability = -1
	var camera = get_viewport().get_camera_3d()
	var tps = camera is CameraController and camera.third_person
	if aiming_ability >= 0 and not tps and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		aiming_ability = -1  # changed my mind

func _pressed(action: String) -> bool:
	return _latched.get(action, false)

## Pause menu / inventory open (nodes in "blocks_game_input"), or we are eliminated
func _input_blocked() -> bool:
	var health = player.get_component("HealthComponent")
	if health and health.is_dead:
		return true
	for node in get_tree().get_nodes_in_group("blocks_game_input"):
		if node is CanvasItem and node.is_visible_in_tree():
			return true
	return false

## One-off actions from menus (inventory use / drop), sent right away: gameplay input is
## blocked while the menu is open
func send_ui_action(action: Dictionary):
	var input_data = {"timestamp": Time.get_ticks_msec(), "sequence": input_sequence, "rotation_y": player.rotation.y}
	input_sequence += 1
	input_data.merge(action)
	_send_input_to_server(input_data)

func _send_stop():
	var input_data = {"timestamp": Time.get_ticks_msec(), "sequence": input_sequence, "rotation_y": player.rotation.y, "sprint": false}
	input_sequence += 1
	_send_input_to_server(input_data)
	_apply_input_locally(input_data)

## Update player rotation to face mouse cursor
func _update_aim_direction():
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	if camera is CameraController and camera.third_person:
		_update_aim_third_person(camera)
		return
	if camera is CameraController and camera.locked_active():
		# Locked view: the hero faces where the camera looks, the aim is the point ahead
		var fwd = camera.tps_forward()
		player.rotation.y = atan2(fwd.x, fwd.z)
		current_aim_position = camera.locked_aim_point()
		current_aim_position.y = player.global_position.y
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	# Calculate intersection with ground plane (y=player height)
	var player_y = player.global_position.y
	if abs(ray_dir.y) > 0.001:
		var t = (player_y - ray_origin.y) / ray_dir.y
		if t > 0:
			current_aim_position = ray_origin + ray_dir * t

			# Rotate player to face aim position
			var look_dir = current_aim_position - player.global_position
			look_dir.y = 0  # Keep rotation horizontal

			if look_dir.length_squared() > 0.01:
				var target_angle = atan2(look_dir.x, look_dir.z)
				# Применить smoothing если включен (для геймпадов), иначе мгновенная ротация
				if aim_smoothing > 0.0:
					player.rotation.y = lerp_angle(player.rotation.y, target_angle, aim_smoothing)
				else:
					player.rotation.y = target_angle  # Мгновенная ротация (по умолчанию для мыши)

## Third person: the hero faces where the camera looks; the aim point is what lies under the
## crosshair (screen center), searched from the hero's distance on so walls behind it don't count
func _update_aim_third_person(camera: CameraController):
	var fwd = camera.tps_forward()
	player.rotation.y = atan2(fwd.x, fwd.z)
	var center = CameraController.aim_screen_point(get_viewport())
	var origin = camera.project_ray_origin(center)
	var dir = camera.project_ray_normal(center)
	var start = origin + dir * max(0.0, (player.global_position - origin).dot(dir))
	current_aim_position = start + dir * 80.0
	var world_3d = get_viewport().world_3d
	if world_3d:
		var query = PhysicsRayQueryParameters3D.create(start, current_aim_position)
		query.exclude = [player.get_rid()]
		var hit = world_3d.direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			current_aim_position = hit.position

## Weed Swarm (meta "auto_fire", SurvivorsRules): the gun picks the nearest weed it can reach and
## see - no wall in between - and the hero turns to it; _capture_and_send_input fires at it.
## Holding the attack button still aims by hand.
var auto_target: Node3D = null
var _auto_scan: float = 0.0
const AUTO_SCAN_EVERY: float = 0.1

func _update_auto_aim(delta: float) -> void:
	if not player.has_meta("auto_fire"):
		auto_target = null
		return
	_auto_scan -= delta
	if _auto_scan <= 0.0 or not _auto_target_ok(auto_target):
		_auto_scan = AUTO_SCAN_EVERY
		auto_target = _find_auto_target()
	if auto_target and not Input.is_action_pressed("attack"):
		var dir = auto_target.global_position - player.global_position
		if Vector2(dir.x, dir.z).length_squared() > 0.01:
			player.rotation.y = atan2(dir.x, dir.z)

func _auto_target_ok(w) -> bool:
	return w != null and is_instance_valid(w) and w.is_inside_tree() and w.visible and w is Weed 		and w.health != null and not w.health.is_dead

func _find_auto_target() -> Node3D:
	var combat = player.get_component("CombatComponent")
	if not combat or not combat.equipped_ranged_weapon:
		return null
	var reach = combat.reach()
	var candidates: Array = []
	for w in get_tree().get_nodes_in_group("npcs"):
		if _auto_target_ok(w):
			var d = player.global_position.distance_to(w.global_position)
			if d <= reach:
				candidates.append([d, w])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var world_3d = get_viewport().world_3d
	var eye = player.global_position + Vector3(0, 1.0, 0)
	for c in candidates.slice(0, 6):
		if not world_3d or not CoverSpawner.line_blocked(world_3d, eye, c[1].global_position + Vector3(0, 0.9, 0)):
			return c[1]
	return null

## Get current aim position for crosshair
func get_aim_position() -> Vector3:
	return current_aim_position

## What the mouse points at: {position} plus {entity_id} when it is another player we can
## actually shoot (not ourselves, not behind a wall). Falls back to the aim point on the ground.
func _mouse_target() -> Dictionary:
	var target = {"position": current_aim_position if current_aim_position != Vector3.ZERO else player.global_position + Vector3(0, 0.5, -5)}
	var camera = get_viewport().get_camera_3d()
	var world_3d = get_viewport().world_3d
	if not camera or not world_3d:
		return target
	var mouse_pos = CameraController.aim_screen_point(get_viewport())
	var ray_origin = camera.project_ray_origin(mouse_pos)
	if camera is CameraController and camera.third_person:
		# Skip what lies between the camera and the hero (bushes, walls behind us)
		var dir = camera.project_ray_normal(mouse_pos)
		ray_origin += dir * max(0.0, (player.global_position - ray_origin).dot(dir))
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + camera.project_ray_normal(mouse_pos) * 1000.0)
	query.exclude = [player.get_rid()]  # clicking on your own character must not hit you
	var result = world_3d.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return target
	target.position = result.position
	var collider = result.get("collider")
	if collider and collider != player and "entity_id" in collider:
		var eye = player.global_position + Vector3(0, 1.0, 0)
		var body = collider.global_position + Vector3(0, 0.9, 0)
		if not CoverSpawner.line_blocked(world_3d, eye, body):
			target["entity_id"] = collider.entity_id
		else:
			target.position = body  # the shot goes into the wall
	return target

func _capture_and_send_input():
	var input_data = {
		"timestamp": Time.get_ticks_msec(),
		"sequence": input_sequence,
		"rotation_y": player.rotation.y,  # So other players see where we aim
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

	# Jump disabled for standard mode

	# Capture sprint input (Shift)
	input_data["sprint"] = Input.is_action_pressed("sprint")

	# Attack: a click, or holding the button (the weapon's fire rate limits the rate)
	var combat = player.get_component("CombatComponent")
	var holding = Input.is_action_pressed("attack") and combat != null and combat.can_attack()
	if _pressed("attack") or holding:
		input_data["attack"] = true
		var aim = _mouse_target()
		input_data["target_position"] = aim.position
		# The client picks who it hit (server-authoritative damage checks it again)
		if aim.has("entity_id"):
			input_data["hit_entity_id"] = aim.entity_id
	elif _auto_target_ok(auto_target) and combat and combat.can_shoot():
		input_data["attack"] = true
		input_data["target_position"] = auto_target.global_position + Vector3(0, 0.9, 0)
		input_data["hit_entity_id"] = auto_target.entity_id

	# Capture ability input (F/G/H/J)
	for i in range(4):
		if _pressed("ability_%d" % (i + 1)):
			input_data["ability_index"] = i
			input_data["target_position"] = _mouse_target().position

	# Health pack / shield: takes a few seconds (InventoryComponent.start_use), also on the server
	for kind in ["heal", "shield"]:
		if _pressed("use_" + kind):
			input_data["use_consumable"] = kind
			var inventory = player.get_component("InventoryComponent")
			if inventory:
				inventory.start_use(kind)

	# Capture interact input (E key)
	if _pressed("interact"):
		var interact_target = _find_interact_target()
		if interact_target:
			input_data["interact"] = true
			# Handle locally for immediate feedback
			_handle_interact(interact_target)

	# Capture reload input (R key)
	if _pressed("reload"):
		input_data["reload"] = true
		# Handle locally for immediate feedback
		_handle_reload()

	# Capture weapon slot switching (1 / 2: two gun slots)
	for i in range(InventoryComponent.MAX_WEAPON_SLOTS):
		if _pressed("weapon_slot_%d" % (i + 1)):
			input_data["weapon_slot"] = i
			_handle_weapon_switch(i)

	# Send input to server if there's any
	if input_data.size() > 0:
		_send_input_to_server(input_data)
		
		# Also apply locally for immediate feedback
		_apply_input_locally(input_data)

func _send_input_to_server(input_data: Dictionary):
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.game_client:
		network_manager.game_client.send_input(input_data)
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

		# Apply sprint
		if input_data.has("sprint"):
			movement.set_sprint(input_data.sprint)

		if input_data.get("jump", false):
			movement.jump()

	# Handle attack locally for immediate feedback (offline mode or client prediction)
	if input_data.has("attack") and input_data.attack:
		var combat = player.get_component("CombatComponent")
		if combat:
			# An empty gun clicks once per trigger pull (no reserve left to reload with)
			var gun = combat.equipped_ranged_weapon
			if gun and gun.current_ammo <= 0 and not combat.is_reloading and not _clicked_empty:
				Sfx.own("empty")
			_clicked_empty = gun != null and gun.current_ammo <= 0
			if input_data.has("target_position"):
				combat.attack(input_data.target_position)
	else:
		_clicked_empty = false

	# Handle abilities locally
	if input_data.has("ability_index") and input_data.has("target_position"):
		var ability_comp = player.get_component("AbilityComponent")
		if ability_comp:
			ability_comp.activate_ability(input_data.ability_index, input_data.target_position)

## Find nearest interactable object (container or loot item) within range
func _find_interact_target() -> Node3D:
	if not player:
		return null

	var player_pos = player.global_position + Vector3(0, 0.5, 0)
	var interact_range = 2.5

	var closest_target: Node3D = null
	var closest_dist: float = INF

	# Check containers
	var containers = get_tree().get_nodes_in_group("loot_containers")
	for container in containers:
		if container is LootContainer and not container.is_opened and not container.is_opening:
			var dist = player_pos.distance_to(container.global_position)
			if dist < interact_range and dist < closest_dist:
				closest_dist = dist
				closest_target = container

	# Check loot items (weapons, ammo, etc.)
	var loot_items = get_tree().get_nodes_in_group("loot_items")
	for item in loot_items:
		if item is LootItem and item.is_active:
			var dist = player_pos.distance_to(item.global_position)
			if dist < interact_range and dist < closest_dist:
				closest_dist = dist
				closest_target = item

	return closest_target

## Handle interact with target (called locally for immediate feedback)
func _handle_interact(target: Node3D):
	# Handle loot items (weapons, ammo, health, etc.)
	if target is LootItem:
		target.interact(player)
		return

	# Handle loot containers
	if target is LootContainer:
		# Try to use network loot manager if available
		var loot_manager = _get_loot_manager()
		if loot_manager and target.has_meta("network_id"):
			var container_id = target.get_meta("network_id")
			loot_manager.request_open_container(container_id)
		else:
			# Fallback to local interaction (offline mode)
			target.interact(player)

## Get the network loot manager (single instance under NetworkManager on every peer)
func _get_loot_manager() -> NetworkLootManager:
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.loot_manager:
		return network_manager.loot_manager
	return null

## Handle reload (called locally for immediate feedback)
func _handle_reload():
	if not player:
		return

	var combat = player.get_component("CombatComponent")
	if combat:
		combat.start_reload()

## Handle weapon slot switching
func _handle_weapon_switch(slot: int):
	if not player:
		return

	var inventory = player.get_component("InventoryComponent")
	if inventory:
		inventory.switch_weapon_slot(slot)
