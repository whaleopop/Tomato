## Handles entity movement with gravity, jumping, and physics
extends Component
class_name MovementComponent

signal movement_started
signal movement_stopped
signal direction_changed(new_direction: Vector3)
signal jumped
signal landed
signal sprint_started
signal sprint_stopped

const DEFAULT_SPEED: float = 6.0
const SPRINT_MULTIPLIER: float = 1.6
const DEFAULT_ACCELERATION: float = 25.0
const DEFAULT_FRICTION: float = 20.0
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
var wants_to_jump: bool = false
var is_sprinting: bool = false

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

func jump():
	if is_grounded:
		wants_to_jump = true

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

	var was_grounded = is_grounded

	# Check if entity is a CharacterBody3D
	if entity is CharacterBody3D:
		_update_character_body(delta)
	else:
		_update_simple(delta)

	# Landing detection
	if not was_grounded and is_grounded:
		landed.emit()

func _update_character_body(delta: float):
	var body = entity as CharacterBody3D

	# Check ground state
	is_grounded = body.is_on_floor()

	# Handle jumping
	if wants_to_jump and is_grounded:
		vertical_velocity = JUMP_VELOCITY
		is_grounded = false
		jumped.emit()
		wants_to_jump = false

	# Apply gravity
	if not is_grounded:
		vertical_velocity -= GRAVITY * delta
		vertical_velocity = max(vertical_velocity, -MAX_FALL_SPEED)
	else:
		vertical_velocity = 0
		wants_to_jump = false

	# Calculate horizontal movement
	var current_speed = speed * (SPRINT_MULTIPLIER if is_sprinting else 1.0)
	var target_velocity = move_direction * current_speed
	var current_control = acceleration if is_grounded else acceleration * air_control

	# Smooth horizontal acceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, current_control * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, current_control * delta)

	# Apply friction when not moving
	if move_direction.length_squared() < 0.01:
		var current_friction = friction if is_grounded else friction * air_control
		velocity.x = move_toward(velocity.x, 0, current_friction * delta)
		velocity.z = move_toward(velocity.z, 0, current_friction * delta)

	# Combine horizontal and vertical velocity
	body.velocity = Vector3(velocity.x, vertical_velocity, velocity.z)

	# Move and slide
	body.move_and_slide()

	# Update grounded state after move
	is_grounded = body.is_on_floor()

	# Rotate entity to face movement direction
	if move_direction.length_squared() > 0.01:
		var look_direction = move_direction.normalized()
		var target_rotation = atan2(look_direction.x, look_direction.z)
		entity.rotation.y = lerp_angle(entity.rotation.y, target_rotation, 10.0 * delta)

	# Update is_moving state
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var was_moving = is_moving
	is_moving = horizontal_speed > 0.1

	if was_moving != is_moving:
		if is_moving:
			movement_started.emit()
		else:
			movement_stopped.emit()

func _update_simple(delta: float):
	# Fallback for non-CharacterBody3D entities
	if move_direction.length_squared() > 0.01:
		velocity = velocity.move_toward(move_direction * speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, friction * delta)

	entity.global_position += velocity * delta

	if move_direction.length_squared() > 0.01:
		var look_direction = move_direction.normalized()
		entity.look_at(entity.global_position + look_direction, Vector3.UP)

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

