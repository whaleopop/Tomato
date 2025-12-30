## Top-down camera controller with zoom and rotation
extends Camera3D
class_name CameraController

var target: Node3D = null
var follow_distance: float = 8.0   # Distance from player
var follow_height: float = 10.0    # Height above player
var follow_speed: float = 8.0      # Camera smoothing speed
var look_offset: float = 1.0       # Look slightly ahead of player

# Zoom settings
var zoom_level: float = 1.0
var target_zoom: float = 1.0
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

# Mouse rotation
var is_rotating: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

# Edge scroll (optional - disabled by default)
var edge_scroll_enabled: bool = false
var edge_scroll_margin: float = 50.0
var edge_scroll_speed: float = 5.0
var camera_offset: Vector3 = Vector3.ZERO

func _ready():
	# Set initial values
	target_angle = camera_angle

func _process(delta: float):
	_handle_input(delta)
	_update_smooth_values(delta)

	if target:
		_update_camera_position(delta)

func _handle_input(delta: float):
	# Keyboard rotation (Q/E)
	if Input.is_action_pressed("camera_left"):
		target_angle += rotation_speed * delta
	if Input.is_action_pressed("camera_right"):
		target_angle -= rotation_speed * delta

	# Keyboard zoom (+/-)
	if Input.is_action_pressed("zoom_in"):
		target_zoom = clamp(target_zoom - zoom_speed * 2.0 * delta, min_zoom, max_zoom)
	if Input.is_action_pressed("zoom_out"):
		target_zoom = clamp(target_zoom + zoom_speed * 2.0 * delta, min_zoom, max_zoom)

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

func _update_smooth_values(delta: float):
	# Smooth zoom
	zoom_level = lerp(zoom_level, target_zoom, zoom_smooth * delta)

	# Smooth rotation
	camera_angle = lerp_angle(deg_to_rad(camera_angle), deg_to_rad(target_angle), rotation_smooth * delta)
	camera_angle = rad_to_deg(camera_angle)

func _update_camera_position(delta: float):
	var target_pos = target.global_position + camera_offset

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

	# Look at target with slight offset upward
	var look_target = target_pos + Vector3(0, look_offset, 0)
	look_at(look_target, Vector3.UP)

func _input(event: InputEvent):
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)
		# Right mouse button for rotation (more intuitive)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			is_rotating = event.pressed
			if is_rotating:
				last_mouse_pos = event.position
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		# Middle mouse also works
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_rotating = event.pressed
			if is_rotating:
				last_mouse_pos = event.position
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Mouse motion for rotation
	if event is InputEventMouseMotion and is_rotating:
		var delta_motion = event.relative
		target_angle -= delta_motion.x * mouse_rotation_speed
		camera_pitch = clamp(camera_pitch - delta_motion.y * mouse_rotation_speed * 0.5, min_pitch, max_pitch)

func set_target(p_target: Node3D):
	target = p_target
	camera_offset = Vector3.ZERO
	print("[CameraController] Target set to: %s" % (p_target.name if p_target else "null"))

func reset_rotation():
	target_angle = 0.0
	camera_pitch = -50.0
	target_zoom = 1.0
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
