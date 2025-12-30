## Handles network synchronization for entity
extends Component
class_name NetworkingComponent

signal sync_data_received(data: Dictionary)
signal sync_data_sent(data: Dictionary)

var is_server_authoritative: bool = true
var sync_rate: float = 0.1  # Sync every 0.1 seconds
var sync_timer: float = 0.0
var last_synced_position: Vector3 = Vector3.ZERO
var position_threshold: float = 0.1  # Only sync if moved more than this

# Interpolation settings
const INTERPOLATION_SPEED: float = 0.3  # Lerp factor for smooth movement
const MAX_SNAP_DISTANCE: float = 5.0  # Teleport if further than this
const EXTRAPOLATION_ENABLED: bool = true
var last_velocity: Vector3 = Vector3.ZERO
var last_sync_timestamp: int = 0

func _init(p_entity = null):  # p_entity: Entity
	entity = p_entity

func update(delta: float):
	if not enabled:
		return
	
	sync_timer += delta
	
	if sync_timer >= sync_rate:
		sync_timer = 0.0
		_sync_entity()

func _sync_entity():
	if entity == null:
		return
	
	var current_position = entity.global_position
	
	# Only sync if position changed significantly
	if current_position.distance_to(last_synced_position) < position_threshold:
		return
	
	last_synced_position = current_position
	
	var sync_data = {
		"entity_id": entity.entity_id,
		"position": current_position,
		"rotation": entity.global_rotation,
	}
	
	# Add component-specific data
	_add_component_sync_data(sync_data)
	
	sync_data_sent.emit(sync_data)

func _add_component_sync_data(data: Dictionary):
	# Health
	var health = entity.get_component("HealthComponent")
	if health:
		data["health"] = health.current_health
		data["max_health"] = health.max_health
	
	# Movement
	var movement = entity.get_component("MovementComponent")
	if movement:
		data["velocity"] = movement.velocity
		data["is_moving"] = movement.is_moving
	
	# Combat
	var combat = entity.get_component("CombatComponent")
	if combat:
		data["is_attacking"] = combat.is_attacking
		if combat.current_weapon:
			data["weapon_id"] = combat.current_weapon.resource_path

func apply_sync_data(data: Dictionary):
	if entity == null:
		return

	# Store timestamp for calculating data age
	if data.has("timestamp"):
		last_sync_timestamp = data["timestamp"]

	# Apply position with interpolation (only for remote players, not local)
	if data.has("position"):
		# Only apply position if this is not the local player
		# Local player position is controlled by input
		if entity.has_method("is_local_player") and entity.is_local_player:
			# Don't override local player position - it's controlled by input
			pass
		else:
			var target_pos = data["position"]
			var current_pos = entity.global_position
			var distance = current_pos.distance_to(target_pos)

			if distance > MAX_SNAP_DISTANCE:
				# Teleport if too far (avoid rubber-banding)
				entity.global_position = target_pos
			else:
				# Smooth interpolation for remote players
				entity.global_position = current_pos.lerp(target_pos, INTERPOLATION_SPEED)

			# Store velocity for extrapolation
			if data.has("velocity"):
				last_velocity = data["velocity"]

	if data.has("rotation"):
		# Smooth rotation interpolation
		var target_rot = data["rotation"]
		entity.global_rotation = entity.global_rotation.lerp(target_rot, INTERPOLATION_SPEED)

	# Apply component data
	_apply_component_sync_data(data)

	sync_data_received.emit(data)

func _apply_component_sync_data(data: Dictionary):
	# Health - use set methods to trigger signals properly
	if data.has("health"):
		var health = entity.get_component("HealthComponent")
		if health:
			# Set max_health first if provided
			if data.has("max_health") and health.max_health != data["max_health"]:
				health.set_max_health(data["max_health"], false)

			# Apply health change through proper method to emit signals
			var new_health = data["health"]
			if health.current_health != new_health:
				var diff = new_health - health.current_health
				if diff > 0:
					health.heal(diff)
				elif diff < 0:
					health._apply_damage(-diff)  # Direct apply without resistance

	# Movement
	if data.has("velocity"):
		var movement = entity.get_component("MovementComponent")
		if movement:
			movement.velocity = data["velocity"]
	if data.has("is_moving"):
		var movement = entity.get_component("MovementComponent")
		if movement:
			movement.is_moving = data["is_moving"]

