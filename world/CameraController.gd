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
var camera_pitch: float = DEFAULT_PITCH  # Vertical angle (degrees)
## Top-down: the camera looks at the hero almost straight down and just follows, it never turns
## on its own (every aim direction looks the same from up there)
const DEFAULT_PITCH: float = -72.0
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

## Locked top-down (GameSettings.camera_locked, on by default): the view is fixed behind the hero
## and turns with them. The mouse is captured: left / right turns the hero and the camera together
## (LOCKED_SENSITIVITY), up / down moves the crosshair nearer / further ahead (aim_distance);
## W always runs up the screen. Off: the old free cursor (the hero faces it, the view stays).
var locked: bool = true
const LOCKED_SENSITIVITY: float = 0.15   # degrees per pixel of mouse travel
const AIM_DISTANCE_MIN: float = 1.5
const AIM_ON_SCREEN: float = 7.0         # how far ahead of the view's middle the crosshair may go
const AIM_DISTANCE_PER_PX: float = 0.02
var aim_distance: float = 5.0
var tps_pitch: float = -12.0             # degrees, negative looks down
var tps_distance: float = TPS_DISTANCE
var _tps_aiming: bool = false
var _top_fov: float = 75.0

## Touch aim (mobile-port): set by whoever owns the on-screen aim stick (TouchControls, via
## PlayerInputHandler/GameSceneController wiring) to a world-space offset from the hero; while
## touch_mode() is on and this isn't zero, aim_screen_point uses hero position + this offset
## instead of the mouse.
var touch_aim_offset: Vector3 = Vector3.ZERO
## Last non-zero touch aim direction (world-space, horizontal, normalized): while the aim stick
## is untouched (touch_aim_offset == ZERO) the hero keeps facing this instead of snapping to
## wherever the emulated "mouse position" (the last finger touch - often the move stick) sits.
var touch_last_aim_dir: Vector3 = Vector3(0, 0, 1)  # heroes face +Z by default (PlayerInputHandler)

func _ready():
	# Set initial values
	target_angle = camera_angle
	_top_fov = fov
	if Platform.touch_mode():
		set_third_person(false, false)
		locked = false
	else:
		set_third_person(GameSettings.third_person, false)
		locked = GameSettings.camera_locked

## Sounds are heard from the hero, not from up here (everything would be equally far away and
## quiet): the listener stands at the target and faces where the view faces (Sfx)
var _listener: AudioListener3D = null

func _update_listener() -> void:
	if not target or not is_instance_valid(target) or not target.is_inside_tree():
		return
	if _listener == null:
		_listener = AudioListener3D.new()
		_listener.name = "HeroListener"
		get_parent().add_child(_listener)
		_listener.make_current()
	var fwd = -global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = global_basis.y  # looking straight down: "up" on the screen is ahead
		fwd.y = 0.0
	var pos = target.visual_position() if target.has_method("visual_position") else target.global_position
	_listener.global_transform = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), pos + Vector3(0, 1.2, 0))

func _process(delta: float):
	_update_listener()
	if Input.is_action_just_pressed("camera_mode") and not _menu_open():
		set_third_person(not third_person)
	if third_person:
		_update_mouse_capture()
		if target:
			_update_third_person(delta)
		return
	if locked_active():
		_update_mouse_capture()
	else:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_update_cursor_hidden()
	_handle_input(delta)
	_update_smooth_values(delta)

	if target:
		_update_camera_position(delta)

## Top-down: the OS cursor is hidden while you play (the HUD draws the crosshair) and back for
## menus, the death / spectator screens and when the window loses focus
func _update_cursor_hidden():
	var want = target != null and is_instance_valid(target) and ("is_local_player" in target) and target.is_local_player 		and not _menu_open() and _focused()
	if want and target.has_method("get_component"):
		var health = target.get_component("HealthComponent")
		want = health == null or not health.is_dead
	var mode = Input.get_mouse_mode()
	if want and mode == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	elif not want and mode == Input.MOUSE_MODE_HIDDEN:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

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

## Where the player aims on screen: the mouse, the screen center in third person, the point
## ahead of the hero in the locked top-down view
static func aim_screen_point(viewport: Viewport) -> Vector2:
	var cam = viewport.get_camera_3d()
	if cam is CameraController and Platform.touch_mode() and cam.target:
		var hero = cam.target.visual_position() if cam.target.has_method("visual_position") else cam.target.global_position
		var offset: Vector3
		if cam.touch_aim_offset != Vector3.ZERO:
			cam.touch_last_aim_dir = cam.touch_aim_offset.normalized()
			offset = cam.touch_aim_offset
		else:
			# Aim stick untouched: keep facing the last real aim direction instead of falling
			# back to the raw "mouse position" (the last finger touch - often the move stick).
			offset = cam.touch_last_aim_dir * 8.0
		var p = hero + offset
		if not cam.is_position_behind(p):
			return cam.unproject_position(p)
	if cam is CameraController and cam.third_person:
		return viewport.get_visible_rect().size / 2.0
	if cam is CameraController and cam.locked_active():
		var p = cam.locked_aim_point()
		if not cam.is_position_behind(p):
			return cam.unproject_position(p)
	return viewport.get_mouse_position()

## Our own living hero in the top-down view with the locked camera, no menu open
func locked_active() -> bool:
	if not locked or third_person or target == null or not is_instance_valid(target):
		return false
	if not ("is_local_player" in target) or not target.is_local_player:
		return false  # spectating: free cursor
	if target.has_method("get_component"):
		var health = target.get_component("HealthComponent")
		if health and health.is_dead:
			return false
	return true

## The crosshair's spot on the ground: aim_distance ahead of the hero
func locked_aim_point() -> Vector3:
	var hero = target.visual_position() if target.has_method("visual_position") else target.global_position
	return hero + tps_forward() * aim_distance

## How far ahead the crosshair can go: the gun's range, but no further than the screen shows
## with the view run ahead as far as that gun lets it (sniper ~17 m, pistol ~9.6 m, shotgun ~8.5 m)
func aim_distance_max() -> float:
	var limit = AIM_ON_SCREEN + _look_ahead_reach()
	if target and target.has_method("get_component"):
		var combat = target.get_component("CombatComponent")
		if combat and combat.equipped_ranged_weapon:
			limit = min(limit, combat.reach())
	return max(limit, AIM_DISTANCE_MIN + 0.5)

func set_locked(on: bool) -> void:
	locked = on
	if not on and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Horizontal direction the third-person camera looks in (the hero turns to it)
func tps_forward() -> Vector3:
	var yaw = deg_to_rad(camera_angle)
	return Vector3(-sin(yaw), 0, -cos(yaw))

func _handle_input(delta: float):


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

func _focused() -> bool:
	return get_window().has_focus()

func _update_smooth_values(delta: float):
	# Smooth zoom
	zoom_level = lerp(zoom_level, target_zoom, zoom_smooth * delta)

	# Smooth rotation
	camera_angle = lerp_angle(deg_to_rad(camera_angle), deg_to_rad(target_angle), rotation_smooth * delta)
	camera_angle = rad_to_deg(camera_angle)

## A rigid rig, the way top-down shooters do it (Enter the Gungeon, Nuclear Throne): one focus
## point = the hero (drawn position, Player.visual_position) + a look-ahead towards the cursor;
## the camera sits at a fixed offset from the focus and looks at it, so it never tilts or wobbles
## on its own. The hero is followed tightly (FOCUS_FOLLOW), only the look-ahead eases in/out
## (LOOK_AHEAD_EASE) - both frame-rate independent (exponential decay).
const FOCUS_FOLLOW: float = 18.0        # how tightly the focus sticks to the hero (1/s)
const LOOK_AHEAD_EASE: float = 4.0      # how quickly the look-ahead follows the cursor (1/s)
const LOOK_AHEAD_DEADZONE: float = 0.22 # share of the half screen around the middle that doesn't push
var _focus: Vector3 = Vector3.ZERO
var _focus_ready: bool = false

func _update_camera_position(delta: float):
	var hero = target.visual_position() if target.has_method("visual_position") else target.global_position
	hero += camera_offset

	# Look-ahead only on our own hero (not while spectating)
	var own = not ("is_local_player" in target) or target.is_local_player
	var want_ahead = Vector3.ZERO
	if locked_active():
		# The further you aim, the further the view runs ahead - up to the gun's reach
		# (_look_ahead_reach: long guns see further), like the free-cursor look-ahead
		aim_distance = clamp(aim_distance, AIM_DISTANCE_MIN, aim_distance_max())
		var share = inverse_lerp(AIM_DISTANCE_MIN, aim_distance_max(), aim_distance)
		want_ahead = tps_forward() * _look_ahead_reach() * clamp(share, 0.0, 1.0)
	elif look_ahead_enabled and own:
		want_ahead = _calculate_look_ahead_offset()
	current_look_ahead = current_look_ahead.lerp(want_ahead, 1.0 - exp(-LOOK_AHEAD_EASE * delta))
	if locked_active():
		# The crosshair never runs ahead of what the (still catching up) view shows; the view
		# then keeps easing out until it reaches the gun's full look-ahead
		var shown = AIM_ON_SCREEN + max(0.0, current_look_ahead.dot(tps_forward()))
		aim_distance = clamp(aim_distance, AIM_DISTANCE_MIN, max(AIM_DISTANCE_MIN, min(aim_distance_max(), shown)))

	if not _focus_ready or _focus.distance_to(hero) > 12.0:
		_focus = hero  # first frame, respawn, switching whom we watch: no long glide across the map
		_focus_ready = true
	else:
		_focus = _focus.lerp(hero, 1.0 - exp(-FOCUS_FOLLOW * delta))

	var angle_rad = deg_to_rad(camera_angle)
	var pitch_rad = deg_to_rad(camera_pitch)
	var dist = follow_distance * zoom_level
	var horizontal_dist = dist * cos(pitch_rad)
	var vertical_dist = dist * -sin(pitch_rad) + follow_height * zoom_level
	var offset = Vector3(sin(angle_rad) * horizontal_dist, vertical_dist, cos(angle_rad) * horizontal_dist)

	var look_at_point = _focus + current_look_ahead + Vector3(0, look_offset, 0)
	global_position = look_at_point + offset - Vector3(0, look_offset, 0)
	look_at(look_at_point, Vector3.UP)

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

	var mouse_pos = aim_screen_point(viewport)
	var screen_size = viewport.get_visible_rect().size

	# Calculate normalized offset from screen center (-1 to 1)
	var screen_center = screen_size / 2.0
	# Relative to the smaller half-size, so the push is the same up / down and sideways
	var normalized_offset = (mouse_pos - screen_center) / min(screen_center.x, screen_center.y)
	var len = normalized_offset.length()
	# A dead zone round the middle (small aim moves don't slide the view), then a soft ramp to 1
	var push = clamp((len - LOOK_AHEAD_DEADZONE) / (1.0 - LOOK_AHEAD_DEADZONE), 0.0, 1.0)
	push = push * push * (3.0 - 2.0 * push)  # smoothstep
	normalized_offset = normalized_offset / max(len, 0.001) * push
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
	if not third_person and locked_active() and event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_angle -= event.screen_relative.x * LOCKED_SENSITIVITY
		target_angle = camera_angle  # no easing: the hero and the view turn at once
		aim_distance = clamp(aim_distance - event.screen_relative.y * AIM_DISTANCE_PER_PX, AIM_DISTANCE_MIN, aim_distance_max())
		return
	if third_person:
		if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			var k = TPS_SENSITIVITY * (0.6 if _tps_aiming else 1.0)
			camera_angle -= event.screen_relative.x * k
			tps_pitch = clamp(tps_pitch - event.screen_relative.y * k, TPS_PITCH_MIN, TPS_PITCH_MAX)
		return
	# No zooming and no mouse-button turning: the view turns with Q / E and the cursor at the screen edge

func _exit_tree():
	if _listener and is_instance_valid(_listener):
		_listener.queue_free()
	if Input.get_mouse_mode() in [Input.MOUSE_MODE_CAPTURED, Input.MOUSE_MODE_HIDDEN]:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)  # back to the menus with a free mouse

func set_target(p_target: Node3D):
	target = p_target
	camera_offset = Vector3.ZERO
	_focus_ready = false  # jump to the new target, don't glide there
	print("[CameraController] Target set to: %s" % (p_target.name if p_target else "null"))

func reset_rotation():
	target_angle = 0.0
	camera_pitch = DEFAULT_PITCH
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
