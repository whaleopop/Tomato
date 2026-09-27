## Cinematic camera for spawn cutscene with multiple modes
extends Camera3D
class_name CutsceneCamera

enum CameraMode {
	FOLLOW_METEOR,      # Follow meteor from behind
	DRAMATIC_ZOOM,      # Zoom in on explosion
	ORBIT_EXPLOSION,    # Orbit around explosion point
	TRACK_HEROES,       # Track multiple heroes flying
	LANDING_OVERVIEW,   # High overview of landing
	SCRIPTED            # Controller sets desired_position / look_target every frame
}

var shake_strength: float = 0.0

var current_mode: CameraMode = CameraMode.FOLLOW_METEOR
var target: Node3D = null
var targets: Array[Node3D] = []

# Camera positioning
var follow_distance: float = 25.0
var follow_height: float = 15.0
var follow_offset: Vector3 = Vector3(0, 15, 25)

# Orbit settings
var orbit_angle: float = 0.0
var orbit_radius: float = 30.0
var orbit_height: float = 20.0
var orbit_speed: float = 0.5

# Smooth movement
var position_smooth: float = 3.0
var look_smooth: float = 5.0
var desired_position: Vector3 = Vector3.ZERO
var look_target: Vector3 = Vector3.ZERO

# Dramatic zoom
var zoom_target_pos: Vector3 = Vector3.ZERO
var zoom_start_pos: Vector3 = Vector3.ZERO
var zoom_progress: float = 0.0

# Overview settings
var overview_height: float = 80.0
var overview_distance: float = 60.0

func _ready():
	# Start with reasonable position
	global_position = Vector3(0, 50, 50)
	look_at(Vector3.ZERO, Vector3.UP)
	current = true

func _process(delta: float):
	match current_mode:
		CameraMode.FOLLOW_METEOR:
			_process_follow_meteor(delta)
		CameraMode.DRAMATIC_ZOOM:
			_process_dramatic_zoom(delta)
		CameraMode.ORBIT_EXPLOSION:
			_process_orbit_explosion(delta)
		CameraMode.TRACK_HEROES:
			_process_track_heroes(delta)
		CameraMode.LANDING_OVERVIEW:
			_process_landing_overview(delta)
		CameraMode.SCRIPTED:
			pass

	# Smooth position interpolation
	global_position = global_position.lerp(desired_position, position_smooth * delta)

	# Smooth look interpolation
	if look_target != Vector3.ZERO:
		var current_look = -global_transform.basis.z
		var desired_look = (look_target - global_position).normalized()
		var smooth_look = current_look.lerp(desired_look, look_smooth * delta)
		if smooth_look.length() > 0.01:
			look_at(global_position + smooth_look, Vector3.UP)

	# Shake through the lens offset, so it never fights the smooth follow above
	shake_strength = move_toward(shake_strength, 0.0, delta * 2.5)
	h_offset = randf_range(-1.0, 1.0) * shake_strength * 0.3
	v_offset = randf_range(-1.0, 1.0) * shake_strength * 0.3

func add_shake(amount: float):
	shake_strength = max(shake_strength, amount)

## Jump straight to a pose (no smoothing), e.g. for a hard cut
func snap_to(pos: Vector3, look: Vector3):
	desired_position = pos
	look_target = look
	global_position = pos
	look_at(look, Vector3.UP)

func set_mode(mode: int, new_target: Node3D = null):
	current_mode = mode as CameraMode
	target = new_target
	print("[CutsceneCamera] Mode changed to: %s" % CameraMode.keys()[mode])

func set_targets(new_targets: Array):
	targets.clear()
	for t in new_targets:
		if t is Node3D:
			targets.append(t)

func orbit_around(node: Node3D, progress: float):
	if not node:
		return

	target = node
	orbit_angle += get_process_delta_time() * orbit_speed

	var center = node.global_position
	desired_position = center + Vector3(
		cos(orbit_angle) * orbit_radius,
		orbit_height,
		sin(orbit_angle) * orbit_radius
	)
	look_target = center

func look_at_explosion(explosion_pos: Vector3):
	zoom_target_pos = explosion_pos
	zoom_start_pos = global_position
	zoom_progress = 0.0

func orbit_explosion(explosion_pos: Vector3, progress: float):
	orbit_angle += get_process_delta_time() * orbit_speed * 2.0

	var distance = orbit_radius * (1.0 - progress * 0.3)  # Get closer over time
	desired_position = explosion_pos + Vector3(
		cos(orbit_angle) * distance,
		orbit_height * (1.0 - progress * 0.3),
		sin(orbit_angle) * distance
	)
	look_target = explosion_pos

func _process_follow_meteor(delta: float):
	if not target:
		return

	# Position behind and above meteor
	var meteor_velocity = Vector3(0, -1, 1).normalized()  # Approximate direction
	desired_position = target.global_position + follow_offset
	look_target = target.global_position

func _process_dramatic_zoom(delta: float):
	zoom_progress = min(zoom_progress + delta * 2.0, 1.0)

	# Zoom toward explosion
	var zoom_distance = lerp(40.0, 20.0, ease(zoom_progress, 2.0))
	var direction = (zoom_start_pos - zoom_target_pos).normalized()

	desired_position = zoom_target_pos + direction * zoom_distance + Vector3(0, 10, 0)
	look_target = zoom_target_pos

func _process_orbit_explosion(delta: float):
	# Handled by orbit_explosion() call from controller
	pass

func _process_track_heroes(delta: float):
	if targets.is_empty():
		return

	# Calculate center of all heroes
	var center = Vector3.ZERO
	var valid_count = 0
	for t in targets:
		if is_instance_valid(t):
			center += t.global_position
			valid_count += 1

	if valid_count == 0:
		return

	center /= valid_count

	# Calculate bounding radius
	var max_dist = 0.0
	for t in targets:
		if is_instance_valid(t):
			max_dist = max(max_dist, center.distance_to(t.global_position))

	# Position camera to see all heroes
	var view_distance = max(max_dist * 2.0 + 20.0, 40.0)
	orbit_angle += delta * orbit_speed * 0.5

	desired_position = center + Vector3(
		cos(orbit_angle) * view_distance * 0.5,
		view_distance * 0.6,
		sin(orbit_angle) * view_distance * 0.5
	)
	look_target = center

func _process_landing_overview(delta: float):
	if targets.is_empty():
		# Default overview position
		desired_position = Vector3(0, overview_height, overview_distance * 0.3)
		look_target = Vector3.ZERO
		return

	# Calculate center of landed heroes
	var center = Vector3.ZERO
	var valid_count = 0
	for t in targets:
		if is_instance_valid(t):
			center += t.global_position
			valid_count += 1

	if valid_count == 0:
		return

	center /= valid_count

	# High overview looking down at map
	desired_position = center + Vector3(0, overview_height, overview_distance * 0.3)
	look_target = center

# Shake effect for explosion
func shake(intensity: float, duration: float):
	var original_pos = global_position
	var tween = create_tween()

	for i in range(int(duration * 30)):
		var offset = Vector3(
			randf_range(-1, 1) * intensity,
			randf_range(-1, 1) * intensity * 0.5,
			randf_range(-1, 1) * intensity
		)
		tween.tween_property(self, "global_position", original_pos + offset, 0.033)
		intensity *= 0.95

	tween.tween_property(self, "global_position", original_pos, 0.1)
