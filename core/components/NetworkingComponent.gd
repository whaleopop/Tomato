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
const INTERPOLATION_SPEED: float = 0.3  # Lerp factor for smooth movement (increased for responsiveness)
const ROTATION_INTERPOLATION_SPEED: float = 0.4  # Separate rotation lerp for smoother turning
const MAX_SNAP_DISTANCE: float = 5.0  # Teleport if further than this
## Local player is predicted locally; only correct it when the server disagrees a lot
## (fell off a destroyed tile, got pushed, desync after lag spike...)
const LOCAL_CORRECTION_DISTANCE: float = 4.0
const EXTRAPOLATION_ENABLED: bool = true
const MAX_EXTRAPOLATION_TIME: float = 0.2  # Max 200ms of extrapolation to prevent drift
var last_velocity: Vector3 = Vector3.ZERO
var last_sync_timestamp: int = 0
var last_update_time: float = 0.0  # Track when we last received an update
var _last_hit_id: int = 0  # ServerPlayer's hit ids already shown
var target_position: Vector3 = Vector3.ZERO  # Target position for interpolation
var target_rotation: Vector3 = Vector3.ZERO  # Target rotation for interpolation

const RESPAWN_STALE_MSEC: int = 600  # states this soon after a respawn may still say "dead"

func _init(p_entity = null):  # p_entity: Entity
	entity = p_entity

func update(delta: float):
	if not enabled:
		return

	sync_timer += delta

	if sync_timer >= sync_rate:
		sync_timer = 0.0
		_sync_entity()

	# Apply smooth interpolation to remote players every frame - on a client only: the server's
	# entities ARE the truth (with a target set by Player.respawn_at the server pulled the hero
	# back to the respawn spot every frame - "can't leave the hex" in CTF / King of the Hill)
	if entity and not _is_local() and not _is_authority():
		_apply_smooth_interpolation(delta)

## is_local_player is a property on Player, not a method
func _is_local() -> bool:
	return entity != null and entity.get("is_local_player") == true

func _is_authority() -> bool:
	if entity == null or not entity.is_inside_tree():
		return false
	var mp = entity.get_tree().get_multiplayer()
	return mp.has_multiplayer_peer() and mp.is_server() and not (mp.multiplayer_peer is OfflineMultiplayerPeer)

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
		# Sync equipped ranged weapon
		if combat.equipped_ranged_weapon:
			data["equipped_weapon_name"] = combat.equipped_ranged_weapon.item_name
			data["current_ammo"] = combat.equipped_ranged_weapon.current_ammo
		elif combat.current_weapon:
			data["weapon_id"] = combat.current_weapon.resource_path

func apply_sync_data(data: Dictionary):
	if entity == null:
		return

	# Store timestamp for calculating data age
	if data.has("timestamp"):
		last_sync_timestamp = data["timestamp"]

	# Track time when we received this update (for extrapolation)
	last_update_time = Time.get_ticks_msec() / 1000.0

	# Apply position with interpolation (only for remote players, not local)
	if data.has("position"):
		# Local player position is controlled by input (client-side prediction)
		if _is_local():
			var server_pos: Vector3 = data["position"]
			if entity.global_position.distance_to(server_pos) > LOCAL_CORRECTION_DISTANCE:
				entity.global_position = server_pos
		else:
			var new_target_pos = data["position"]
			var current_pos = entity.global_position
			var distance = current_pos.distance_to(new_target_pos)

			if distance > MAX_SNAP_DISTANCE:
				# Teleport if too far (avoid rubber-banding)
				entity.global_position = new_target_pos
				target_position = new_target_pos
			else:
				# Store target position for smooth interpolation in update()
				target_position = new_target_pos

			# Store velocity for extrapolation
			if data.has("velocity"):
				last_velocity = data["velocity"]

	if data.has("rotation") and not _is_local():
		# Store target rotation for smooth interpolation in update()
		target_rotation = data["rotation"]

	# Apply component data
	_apply_component_sync_data(data)

	sync_data_received.emit(data)

## Apply smooth interpolation every frame for remote players
func _apply_smooth_interpolation(delta: float):
	if entity == null:
		return

	# Smooth position interpolation with extrapolation
	if target_position != Vector3.ZERO:
		var current_pos = entity.global_position
		var interpolation_target = target_position

		# Apply extrapolation if enabled
		if EXTRAPOLATION_ENABLED and last_update_time > 0:
			var current_time = Time.get_ticks_msec() / 1000.0
			var time_since_update = current_time - last_update_time

			# Only extrapolate if we haven't received an update recently
			# and velocity is significant
			if time_since_update > 0 and last_velocity.length() > 0.1:
				# Limit extrapolation time to prevent excessive drift
				var extrap_time = min(time_since_update, MAX_EXTRAPOLATION_TIME)

				# Predict where player should be based on velocity
				var extrapolated_offset = last_velocity * extrap_time
				interpolation_target = target_position + extrapolated_offset

		var distance = current_pos.distance_to(interpolation_target)

		# Only interpolate if target is valid and not too close
		if distance > 0.01:
			# Use delta-independent lerp for consistent framerate behavior
			var lerp_factor = 1.0 - pow(1.0 - INTERPOLATION_SPEED, delta * 60.0)
			entity.global_position = current_pos.lerp(interpolation_target, lerp_factor)

	# Smooth rotation interpolation
	if target_rotation != Vector3.ZERO:
		# Use delta-independent lerp for consistent framerate behavior
		var lerp_factor = 1.0 - pow(1.0 - ROTATION_INTERPOLATION_SPEED, delta * 60.0)
		entity.global_rotation.x = lerp_angle(entity.global_rotation.x, target_rotation.x, lerp_factor)
		entity.global_rotation.y = lerp_angle(entity.global_rotation.y, target_rotation.y, lerp_factor)
		entity.global_rotation.z = lerp_angle(entity.global_rotation.z, target_rotation.z, lerp_factor)

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
			# The respawn RPC and the state travel on different channels: a state from just before
			# the respawn can arrive after it. Its "health 0" must not kill the hero again (the dead
			# send no input: the hero stood frozen on the respawn spot), and if it did, the next
			# state's health brings it back.
			var since_respawn = Time.get_ticks_msec() - int(entity.get_meta("respawn_msec", -100000))
			if float(new_health) <= 0.0 and not health.is_dead and since_respawn < RESPAWN_STALE_MSEC:
				new_health = health.current_health
			elif health.is_dead and float(new_health) > 0.0 and entity.has_method("respawn_at") and GameModes.respawns(GameModes.current()):
				entity.respawn_at(entity.global_position)
			if health.current_health != new_health:
				var diff = new_health - health.current_health
				if diff > 0:
					health._apply_heal(diff)
				elif diff < 0:
					health._apply_damage(-diff)  # Direct apply without resistance
			if data.has("shield"):
				health.set_shield(float(data["shield"]))
			# Where our hits came from (only our own state carries them): the HUD's direction arcs
			if data.has("hits") and _is_local():
				for h in data["hits"]:
					if int(h[0]) > _last_hit_id:
						_last_hit_id = int(h[0])
						health.hit_from.emit(Vector3(float(h[1]), entity.global_position.y, float(h[2])), float(h[3]))

	# Stun, blind, stealth, knockback: the server's word, also for our own predicted player
	var status = entity.get_component("StatusComponent")
	if status and (data.has("fx") or data.has("health")):
		status.from_sync(data.get("fx", {}), _is_local())

	# Movement (the local player's movement is predicted locally; stamina is checked against the server's)
	if _is_local():
		if data.has("stamina"):
			var movement = entity.get_component("MovementComponent")
			if movement:
				movement.sync_stamina(float(data["stamina"][0]), bool(data["stamina"][1]))
		return
	if data.has("velocity"):
		var movement = entity.get_component("MovementComponent")
		if movement:
			movement.velocity = data["velocity"]
	if data.has("is_moving"):
		var movement = entity.get_component("MovementComponent")
		if movement:
			movement.is_moving = data["is_moving"]

