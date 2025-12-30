## Handles entity movement with server-authoritative support
extends Component
class_name MovementComponent

signal movement_started
signal movement_stopped
signal direction_changed(new_direction: Vector3)

const DEFAULT_SPEED: float = 5.0
const DEFAULT_ACCELERATION: float = 20.0
const DEFAULT_FRICTION: float = 15.0

var speed: float = DEFAULT_SPEED
var acceleration: float = DEFAULT_ACCELERATION
var friction: float = DEFAULT_FRICTION
var move_direction: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var is_moving: bool = false

var character_body: CharacterBody3D = null

func _init(p_entity = null):  # p_entity: Entity
	entity = p_entity

func setup(p_character_body: CharacterBody3D):
	character_body = p_character_body

func set_move_direction(direction: Vector3):
	var old_direction = move_direction
	move_direction = direction.normalized()
	
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

func update(delta: float):
	if not enabled:
		return
	
	# Apply movement
	if move_direction.length_squared() > 0.01:
		# Accelerate
		velocity = velocity.move_toward(move_direction * speed, acceleration * delta)
	else:
		# Apply friction
		velocity = velocity.move_toward(Vector3.ZERO, friction * delta)
	
	# Apply movement to entity (Entity extends Node3D)
	if entity:
		# Update position directly (no CharacterBody3D needed for now)
		entity.global_position += velocity * delta
		
		# Rotate entity to face movement direction
		if move_direction.length_squared() > 0.01:
			var look_direction = move_direction.normalized()
			entity.look_at(entity.global_position + look_direction, Vector3.UP)
	
	# Update is_moving state
	var was_moving = is_moving
	is_moving = velocity.length_squared() > 0.01
	
	if was_moving != is_moving:
		if is_moving:
			movement_started.emit()
		else:
			movement_stopped.emit()

func get_velocity() -> Vector3:
	return velocity

func set_speed(new_speed: float):
	speed = new_speed

func get_speed() -> float:
	return speed

func stop():
	set_move_direction(Vector3.ZERO)
	velocity = Vector3.ZERO

