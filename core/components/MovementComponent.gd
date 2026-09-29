## Handles entity movement with gravity, jumping, and physics
extends Component
class_name MovementComponent

signal movement_started
signal movement_stopped
signal direction_changed(new_direction: Vector3)
signal sprint_started
signal sprint_stopped

const DEFAULT_SPEED: float = 7.0  # Slightly faster base speed
const SPRINT_MULTIPLIER: float = 1.5
const DEFAULT_ACCELERATION: float = 30.0  # Faster acceleration
const DEFAULT_FRICTION: float = 25.0  # Faster stopping
const DEFAULT_AIR_CONTROL: float = 0.3  # Reduced control in air

# Physics constants
const GRAVITY: float = 25.0
const JUMP_VELOCITY: float = 10.0
const MAX_FALL_SPEED: float = 50.0

var speed: float = DEFAULT_SPEED
var acceleration: float = DEFAULT_ACCELERATION
var friction: float = DEFAULT_FRICTION
var air_control: float = DEFAULT_AIR_CONTROL

var move_direction: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var vertical_velocity: float = 0.0
var is_moving: bool = false
var is_grounded: bool = true
var is_sprinting: bool = false
var _jump_requested: bool = false
var _dash_velocity: Vector3 = Vector3.ZERO
var _dash_time: float = 0.0
## Ground under the feet: water / swamp slow you down (HexTile.speed_factor). Server and client
## read the same map, so the prediction agrees with the server.
var terrain_multiplier: float = 1.0
var terrain_biome: int = -1  # the tile under the feet (BiomeRules: grip here, effects in StatusComponent)

func _init(p_entity = null):  # p_entity: Entity
	entity = p_entity

func set_move_direction(direction: Vector3):
	var old_direction = move_direction
	move_direction = direction.normalized()
	# Only use horizontal movement
	move_direction.y = 0
	move_direction = move_direction.normalized()

	if move_direction.length_squared() > 0.01:
		if not is_moving:
			is_moving = true
			movement_started.emit()
	else:
		if is_moving:
			is_moving = false
			movement_stopped.emit()

	if old_direction.distance_to(move_direction) > 0.1:
		direction_changed.emit(move_direction)

## Jump on the next physics update if standing on the ground
func jump():
	_jump_requested = true

## Burst along the ground for `time` seconds (dash / leap abilities). Setting `velocity`
## directly did almost nothing: the acceleration smoothing pulled it back within a frame or two.
func dash(p_velocity: Vector3, time: float):
	_dash_velocity = Vector3(p_velocity.x, 0.0, p_velocity.z)
	_dash_time = max(time, 0.0)

func is_dashing() -> bool:
	return _dash_time > 0.0

func set_sprint(sprinting: bool):
	if is_sprinting != sprinting:
		is_sprinting = sprinting
		if sprinting:
			sprint_started.emit()
		else:
			sprint_stopped.emit()

func update(delta: float):
	if not enabled or not entity:
		return

	# Check if entity is a CharacterBody3D
	if entity is CharacterBody3D:
		_update_character_body(delta)
	else:
		_update_simple(delta)

func _update_character_body(delta: float):
	var body = entity as CharacterBody3D

	# Check ground state
	is_grounded = body.is_on_floor()
	var status = entity.get_component("StatusComponent") if entity.has_method("get_component") else null
	var stunned = status != null and status.is_stunned()
	if stunned:
		_jump_requested = false

	# Apply gravity
	if not is_grounded:
		vertical_velocity -= GRAVITY * delta
		vertical_velocity = max(vertical_velocity, -MAX_FALL_SPEED)
	else:
		vertical_velocity = 0
		if _jump_requested:
			vertical_velocity = JUMP_VELOCITY
	_jump_requested = false

	# Calculate horizontal movement
	if is_grounded:
		_update_terrain(body)
	var current_speed = speed * (SPRINT_MULTIPLIER if is_sprinting else 1.0) * terrain_multiplier
	if status:
		current_speed *= status.movement_factor()
	# Heavy guns slow you down while in hand (RangedWeapon.move_factor: the minigun)
	var combat = entity.get_component("CombatComponent") if entity.has_method("get_component") else null
	if combat and combat.equipped_ranged_weapon:
		current_speed *= combat.equipped_ranged_weapon.move_factor
	var target_velocity = Vector3.ZERO if stunned else move_direction * current_speed
	var grip = BiomeRules.grip(terrain_biome) if is_grounded else 1.0  # frost: you slide
	var current_control = (acceleration if is_grounded else acceleration * air_control) * grip

	# Smooth horizontal acceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, current_control * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, current_control * delta)

	# Apply friction when not moving
	if move_direction.length_squared() < 0.01:
		var current_friction = (friction if is_grounded else friction * air_control) * grip
		velocity.x = move_toward(velocity.x, 0, current_friction * delta)
		velocity.z = move_toward(velocity.z, 0, current_friction * delta)

	# A dash overrides steering until it runs out
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity.x = _dash_velocity.x
		velocity.z = _dash_velocity.z

	# Combine horizontal and vertical velocity
	body.velocity = Vector3(velocity.x, vertical_velocity, velocity.z)

	# A low ledge (out of the water, a bank, a bump) is stepped onto, not walked into.
	# Terrace cliffs are far higher than STEP_HEIGHT: those still take a jump or a ramp.
	if is_grounded:
		_step_up(body, delta)
	elif vertical_velocity > -6.0 and move_direction.length_squared() > 0.01:
		# Jumped at a ledge that is a bit too high (out of the water under a terrace): pull up
		if _step_up(body, delta, MANTLE_HEIGHT):
			vertical_velocity = 0.0
			body.velocity.y = 0.0

	# Move and slide
	body.move_and_slide()

	# Update grounded state after move
	is_grounded = body.is_on_floor()

	# Don't rotate here - rotation is handled by PlayerInputHandler (looks at mouse cursor)

	# Update is_moving state
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var was_moving = is_moving
	is_moving = horizontal_speed > 0.1

	if was_moving != is_moving:
		if is_moving:
			movement_started.emit()
		else:
			movement_stopped.emit()

const STEP_HEIGHT: float = 0.5
const MANTLE_HEIGHT: float = 1.0   # in the air (a jump): a ledge up to this far above you is climbed
const STEP_PROBE: float = 0.3      # how far ahead the ledge is looked for (about the body's radius)

## Blocked ahead but free `height` higher: lift the body onto the ledge (the same test runs on
## the server and in the client's prediction, so they agree). True if it climbed.
func _step_up(body: CharacterBody3D, delta: float, height: float = STEP_HEIGHT) -> bool:
	var motion = Vector3(body.velocity.x, 0.0, body.velocity.z) * delta
	if motion.length_squared() < 0.000001:
		return false
	var probe = motion.normalized() * max(motion.length(), STEP_PROBE)
	var from = body.global_transform
	if not body.test_move(from, probe):
		return false  # nothing in the way
	var lift = Vector3.UP * height
	if body.test_move(from, lift):
		return false  # no headroom
	var raised = from.translated(lift)
	if body.test_move(raised, probe):
		return false  # a wall or a cliff, not a step
	# Settle onto the ledge: from the raised spot ahead, down until we touch it. The rounded
	# bottom may meet the ledge's corner first (a slanted normal): that still counts, the next
	# frames finish the climb.
	var collision = KinematicCollision3D.new()
	if body.test_move(raised.translated(probe), -lift, collision):
		var rise = height - collision.get_travel().length()
		if rise > 0.02 and collision.get_normal().y > 0.3:
			body.global_position.y += rise + 0.01
			return true
	return false

## What we stand on (a short ray down to the environment layer). In the air the last value stays,
## so jumping doesn't get you through a lake faster.
func _update_terrain(body: CharacterBody3D) -> void:
	if not body.is_inside_tree():
		return
	var origin = body.global_position + Vector3.UP * 0.3
	var query = PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 0.8, 1, [body.get_rid()])
	var hit = body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider is HexTile:
		terrain_multiplier = HexTile.speed_factor(hit.collider.biome_type)
		terrain_biome = hit.collider.biome_type

func _update_simple(delta: float):
	# Fallback for non-CharacterBody3D entities
	if move_direction.length_squared() > 0.01:
		velocity = velocity.move_toward(move_direction * speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, friction * delta)

	entity.global_position += velocity * delta

	# Rotation handled by PlayerInputHandler (looks at mouse cursor)

func get_velocity() -> Vector3:
	return Vector3(velocity.x, vertical_velocity, velocity.z)

func set_speed(new_speed: float):
	speed = new_speed

func get_speed() -> float:
	return speed

func is_on_ground() -> bool:
	return is_grounded

func stop():
	set_move_direction(Vector3.ZERO)
	velocity = Vector3.ZERO
	_dash_time = 0.0

