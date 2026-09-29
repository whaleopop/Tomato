## Top-down camera controller (fixed at the closest zoom, no zooming) with rotation, plus a third-person mode (V, remembered in
## GameSettings.third_person): the camera sits behind the hero's shoulder, the mouse is captured and
## turns the view, the hero faces where the camera looks and aims at the screen center
## (aim_screen_point). WASD stays relative to camera_angle in both modes.
extends Camera3D
class_name CameraController

var target: Node3D = null
var follow_distance: float = 8.0   # Distance from player
var follow_height: float = 10.0    # Height above player
var follow_speed: float = 8.0      # Camera smoothing speed
var look_offset: float = 1.0       # Look slightly ahead of player

# Follow player rotation (for shooter games)
var follow_player_rotation: bool = false  # Camera doesn't rotate with player

# Look-ahead: camera shifts toward aim/crosshair position
var look_ahead_enabled: bool = true       # Shift camera toward mouse cursor
var look_ahead_distance: float = 4.0      # Max distance camera shifts toward cursor
var look_ahead_speed: float = 3.0         # How fast camera shifts
var current_look_ahead: Vector3 = Vector3.ZERO

# Zoom settings
# Zoom is fixed at min_zoom (the closest view): the wheel and +/- no longer zoom
var zoom_level: float = 0.5
var target_zoom: float = 0.5
var min_zoom: float = 0.5
var max_zoom: float = 2.0
var zoom_speed: float = 0.1
var zoom_smooth: float = 8.0

# Rotation settings
var camera_angle: float = 0.0      # Horizontal rotation around target (degrees)
var target_angle: float = 0.0      # Target angle for smooth rotation
var camera_pitch: float = -50.0    # Vertical angle (degrees)
var rotation_speed: float = 90.0   # Degrees per second with Q/E
var mouse_rotation_speed: float = 0.4
var rotation_smooth: float = 10.0
var min_pitch: float = -80.0
var max_pitch: float = -25.0

# Edge turn: the cursor near the left / right edge turns the view (and the hero, who faces
# the cursor, turns with it) - no Q / E needed. The rate grows towards the edge.
var edge_turn_enabled: bool = true
const EDGE_TURN_START: float = 0.72      # fraction of the half screen width where turning starts
const EDGE_TURN_SPEED: float = 130.0     # degrees per second at the very edge

# Mouse rotation
var is_rotating: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

# Edge scroll (optional - disabled by default)
var edge_scroll_enabled: bool = false
var edge_scroll_margin: float = 50.0
var edge_scroll_speed: float = 5.0
var camera_offset: Vector3 = Vector3.ZERO

# Third person
const TPS_DISTANCE: float = 5.4
const TPS_AIM_DISTANCE: float = 2.6      # right mouse held: closer over the shoulder
const TPS_PIVOT_HEIGHT: float = 2.0      # above the hero's feet
const TPS_SHOULDER: float = 0.9         # the hero stands left of the crosshair
const TPS_PITCH_MIN: float = -55.0
const TPS_PITCH_MAX: float = 40.0
const TPS_SENSITIVITY: float = 0.14      # degrees per pixel
const TPS_FOV: float = 70.0
const TPS_AIM_FOV: float = 55.0
var third_person: bool = false
var tps_pitch: float = -12.0             # degrees, negative looks down
var tps_distance: float = TPS_DISTANCE
var _tps_aiming: bool = false
var _top_fov: float = 75.0

func _ready():
	# Set initial values
	target_angle = camera_angle
	_top_fov = fov
	set_third_person(GameSettings.third_person, false)

func _process(delta: float):
	if Input.is_action_just_pressed("camera_mode") and not _menu_open():
		set_third_person(not third_person)
	if third_person:
		_update_mouse_capture()
		if target:
			_update_third_person(delta)
		return
	_handle_input(delta)
	_update_smooth_values(delta)

	if target:
		_update_camera_position(delta)

## Switch the view; `save` remembers it for the next match
func set_third_person(on: bool, save: bool = true):
	third_person = on
	is_rotating = false
	if on:
		# Start looking the way the top-down camera faced
		camera_angle = target_angle
		tps_pitch = -12.0
	else:
		fov = _top_fov
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if save and GameSettings.third_person != on:
		GameSettings.third_person = on
		GameSettings.save()
	var hud = get_tree().get_first_node_in_group("player_hud") if is_inside_tree() else null
	if save and hud and hud.has_method("show_alert"):
		hud.show_alert(tr("Third-person camera") if on else tr("Top-down camera"), UITheme.ACCENT_INFO)

## Pause menu, inventory, result screen (the same group that blocks gameplay input)
func _menu_open() -> bool:
	for node in get_tree().get_nodes_in_group("blocks_game_input"):
		if node is CanvasItem and node.is_visible_in_tree():
			return true
	return false

## The mouse is captured while playing and free while a menu is open or the window is unfocused
func _update_mouse_capture():
	var want = not _menu_open() and get_window().has_focus()
	var mode = Input.get_mouse_mode()
	if want and mode != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif not want and mode == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _update_third_person(delta: float):
	_tps_aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	var want_dist = TPS_AIM_DISTANCE if _tps_aiming else tps_distance
	fov = lerp(fov, TPS_AIM_FOV if _tps_aiming else TPS_FOV, 10.0 * delta)
	target_angle = camera_angle  # WASD and the minimap read camera_angle / target_angle

	var yaw = deg_to_rad(camera_angle)
	var pitch = deg_to_rad(tps_pitch)
	var back = Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))  # from the pivot to the camera
	var right = Vector3(cos(yaw), 0, -sin(yaw))
	var pivot = target.global_position + Vector3(0, TPS_PIVOT_HEIGHT, 0) + right * TPS_SHOULDER
	var desired = pivot + back * want_dist

	# Don't go through walls, trees or mountains behind the hero: stop short of them
	var space = get_world_3d().direct_space_state
	if space:
		var query = PhysicsRayQueryParameters3D.create(target.global_position + Vector3(0, TPS_PIVOT_HEIGHT, 0), desired)
		if target is CollisionObject3D:
			query.exclude = [target.get_rid()]
		var hit = space.intersect_ray(query)
		if not hit.is_empty():
			var from: Vector3 = query.from
			desired = from + (hit.position - from) * 0.9
	global_position = global_position.lerp(desired, clamp(20.0 * delta, 0.0, 1.0))
	look_at(global_position - back, Vector3.UP)

## Where the player aims on screen: the mouse, or the screen center in third person
static func aim_screen_point(viewport: Viewport) -> Vector2:
	var cam = viewport.get_camera_3d()
	if cam is CameraController and cam.third_person:
		return viewport.get_visible_rect().size / 2.0
	return viewport.get_mouse_position()

## Horizontal direction the third-person camera looks in (the hero turns to it)
func tps_forward() -> Vector3:
	var yaw = deg_to_rad(camera_angle)
	return Vector3(-sin(yaw), 0, -cos(yaw))

func _handle_input(delta: float):
	# Keyboard rotation (Q/E)
	if Input.is_action_pressed("camera_left"):
		target_angle += rotation_speed * delta
	if Input.is_action_pressed("camera_right"):
		target_angle -= rotation_speed * delta

	_edge_turn(delta)


	# Camera reset (C)
	if Input.is_action_just_pressed("camera_reset"):
		reset_rotation()

	# Edge scroll (if enabled)
	if edge_scroll_enabled and target:
		var viewport_size = get_viewport().get_visible_rect().size
		var mouse_pos = get_viewport().get_mouse_position()
		var scroll_dir = Vector3.ZERO

		if mouse_pos.x < edge_scroll_margin:
			scroll_dir.x -= 1.0
		elif mouse_pos.x > viewport_size.x - edge_scroll_margin:
			scroll_dir.x += 1.0

		if mouse_pos.y < edge_scroll_margin:
			scroll_dir.z -= 1.0
		elif mouse_pos.y > viewport_size.y - edge_scroll_margin:
			scroll_dir.z += 1.0

		if scroll_dir != Vector3.ZERO:
			# Rotate scroll direction by camera angle
			var angle_rad = deg_to_rad(camera_angle)
			var rotated = Vector3(
				scroll_dir.x * cos(angle_rad) - scroll_dir.z * sin(angle_rad),
				0,
				scroll_dir.x * sin(angle_rad) + scroll_dir.z * cos(angle_rad)
			)
			camera_offset += rotated * edge_scroll_speed * delta

func _edge_turn(delta: float):
	if not edge_turn_enabled or is_rotating or not target or _menu_open():
		return
	var viewport = get_viewport()
	if not viewport or not get_window().has_focus():
		return
	var rect = viewport.get_visible_rect()
	var mouse = viewport.get_mouse_position()
	if not rect.has_point(mouse):
		return  # the cursor left the window: don't spin
	var x = (mouse.x - rect.size.x / 2.0) / (rect.size.x / 2.0)  # -1 left edge .. 1 right edge
	var over = (abs(x) - EDGE_TURN_START) / (1.0 - EDGE_TURN_START)
	if over <= 0.0:
		return
	# Cursor on the right: the view turns right (the world swings left under it)
	target_angle -= sign(x) * EDGE_TURN_SPEED * over * over * delta

func _update_smooth_values(delta: float):
	# Smooth zoom
	zoom_level = lerp(zoom_level, target_zoom, zoom_smooth * delta)

	# Smooth rotation
	camera_angle = lerp_angle(deg_to_rad(camera_angle), deg_to_rad(target_angle), rotation_smooth * delta)
	camera_angle = rad_to_deg(camera_angle)

func _update_camera_position(delta: float):
	var target_pos = target.global_position + camera_offset

	# Look-ahead: shift camera toward mouse/aim position (only on our own hero: not while spectating)
	var own = not ("is_local_player" in target) or target.is_local_player
	if not own:
		current_look_ahead = Vector3.ZERO
	if look_ahead_enabled and own:
		var aim_offset = _calculate_look_ahead_offset()
		current_look_ahead = current_look_ahead.lerp(aim_offset, look_ahead_speed * delta)
		target_pos += current_look_ahead

	# Follow player rotation if enabled (for shooter games)
	if follow_player_rotation and target:
		# Get player's facing direction and convert to angle
		var player_forward = -target.global_transform.basis.z
		var player_angle = atan2(player_forward.x, player_forward.z)
		# Camera should be BEHIND player, so add PI
		var desired_camera_angle = rad_to_deg(player_angle) + 180.0
		# Smoothly interpolate camera angle
		target_angle = lerp_angle(deg_to_rad(target_angle), deg_to_rad(desired_camera_angle), 3.0 * delta)
		target_angle = rad_to_deg(target_angle)

	# Calculate camera position based on zoom and rotation
	var current_distance = follow_distance * zoom_level
	var current_height = follow_height * zoom_level

	# Convert angle to radians
	var angle_rad = deg_to_rad(camera_angle)
	var pitch_rad = deg_to_rad(camera_pitch)

	# Calculate offset based on rotation
	var horizontal_dist = current_distance * cos(pitch_rad)
	var vertical_dist = current_distance * -sin(pitch_rad) + current_height

	var offset = Vector3(
		sin(angle_rad) * horizontal_dist,
		vertical_dist,
		cos(angle_rad) * horizontal_dist
	)

	var desired_pos = target_pos + offset

	# Smooth camera movement
	global_position = global_position.lerp(desired_pos, follow_speed * delta)

	# Look at target (player + look ahead offset)
	var look_target = target.global_position + current_look_ahead + Vector3(0, look_offset, 0)
	look_at(look_target, Vector3.UP)

## Calculate offset toward mouse cursor for look-ahead
## How far the view may run ahead towards the cursor: long guns see further (their fog-of-war
## sight, RangedWeapon.visibility_range), so the camera goes further out with them
func _look_ahead_reach() -> float:
	var reach = look_ahead_distance * zoom_level
	if target and target.has_method("get_component"):
		var combat = target.get_component("CombatComponent")
		if combat and combat.equipped_ranged_weapon:
			reach = clamp((combat.equipped_ranged_weapon.visibility_range - 10.0) * 0.65, 1.5, 10.0)
	return reach

func _calculate_look_ahead_offset() -> Vector3:
	if not target:
		return Vector3.ZERO

	# Get mouse position on screen
	var viewport = get_viewport()
	if not viewport:
		return Vector3.ZERO

	var mouse_pos = viewport.get_mouse_position()
	var screen_size = viewport.get_visible_rect().size

	# Calculate normalized offset from screen center (-1 to 1)
	var screen_center = screen_size / 2.0
	var normalized_offset = (mouse_pos - screen_center) / screen_center
	if normalized_offset.length() > 1.0:
		normalized_offset = normalized_offset.normalized()
	var reach = _look_ahead_reach()

	# Convert to world offset (X and Z)
	# Account for camera rotation
	var angle_rad = deg_to_rad(camera_angle)
	var world_offset = Vector3(
		(normalized_offset.x * cos(angle_rad) + normalized_offset.y * sin(angle_rad)) * reach,
		0,
		(-normalized_offset.x * sin(angle_rad) + normalized_offset.y * cos(angle_rad)) * reach
	)

	return world_offset

func _input(event: InputEvent):
	if third_person:
		if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			var k = TPS_SENSITIVITY * (0.6 if _tps_aiming else 1.0)
			camera_angle -= event.relative.x * k
			tps_pitch = clamp(tps_pitch - event.relative.y * k, TPS_PITCH_MIN, TPS_PITCH_MAX)
		return
	# No zooming and no mouse-button turning: the view turns with Q / E and the cursor at the screen edge

func _exit_tree():
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)  # back to the menus with a free mouse

func set_target(p_target: Node3D):
	target = p_target
	camera_offset = Vector3.ZERO
	print("[CameraController] Target set to: %s" % (p_target.name if p_target else "null"))

func reset_rotation():
	target_angle = 0.0
	camera_pitch = -50.0
	target_zoom = min_zoom
	camera_offset = Vector3.ZERO

## Get camera angle in radians for movement direction transformation
func get_camera_angle_rad() -> float:
	return deg_to_rad(camera_angle)

## Transform a direction vector to be relative to camera rotation
func transform_direction(direction: Vector2) -> Vector2:
	var angle_rad = deg_to_rad(camera_angle)
	var cos_a = cos(angle_rad)
	var sin_a = sin(angle_rad)
	# Inverse rotation to match camera view direction
	return Vector2(
		direction.x * cos_a + direction.y * sin_a,
		-direction.x * sin_a + direction.y * cos_a
	)
