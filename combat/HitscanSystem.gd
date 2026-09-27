## Hitscan shooting system using raycasts
## Handles instant-hit weapons like pistols, shotguns, snipers
extends Node
class_name HitscanSystem

signal shot_fired(from: Vector3, to: Vector3, hit_result: Dictionary)
signal target_hit(target: Node3D, damage: float, hit_position: Vector3)
signal shot_missed(from: Vector3, direction: Vector3)

const MAX_RANGE: float = 100.0
const DEFAULT_DAMAGE: float = 10.0

# Collision layers
const LAYER_PLAYERS: int = 2
const LAYER_ENEMIES: int = 4
const LAYER_ENVIRONMENT: int = 1

## Perform a hitscan shot from origin in direction
## Returns hit result dictionary
static func shoot(
	world_3d: World3D,
	origin: Vector3,
	direction: Vector3,
	range: float = MAX_RANGE,
	damage: float = DEFAULT_DAMAGE,
	shooter: Node3D = null,
	collision_mask: int = LAYER_PLAYERS | LAYER_ENEMIES | LAYER_ENVIRONMENT
) -> Dictionary:
	if not world_3d:
		return {"hit": false}

	var space_state = world_3d.direct_space_state
	if not space_state:
		return {"hit": false}

	var end_point = origin + direction.normalized() * range

	var query = PhysicsRayQueryParameters3D.create(origin, end_point)
	query.collision_mask = collision_mask

	# Exclude shooter from raycast
	if shooter and shooter is CollisionObject3D:
		query.exclude = [shooter.get_rid()]

	var result = space_state.intersect_ray(query)

	if result:
		return {
			"hit": true,
			"position": result.position,
			"normal": result.normal,
			"collider": result.collider,
			"distance": origin.distance_to(result.position),
			"damage": damage
		}
	else:
		return {
			"hit": false,
			"end_position": end_point
		}

## Perform shotgun-style spread shot
## Returns array of hit results
static func shoot_spread(
	world_3d: World3D,
	origin: Vector3,
	direction: Vector3,
	pellet_count: int = 8,
	spread_angle: float = 15.0,
	range: float = 30.0,
	damage_per_pellet: float = 8.0,
	shooter: Node3D = null
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	for i in range(pellet_count):
		# Random spread within cone
		var spread_dir = _get_spread_direction(direction, spread_angle)
		var hit_result = shoot(world_3d, origin, spread_dir, range, damage_per_pellet, shooter)
		results.append(hit_result)

	return results

## Get a random direction within a cone
static func _get_spread_direction(base_direction: Vector3, max_angle_degrees: float) -> Vector3:
	var angle_rad = deg_to_rad(max_angle_degrees)

	# Random angle within cone
	var random_angle = randf() * angle_rad
	var random_rotation = randf() * TAU

	# Create perpendicular vectors
	var up = Vector3.UP if abs(base_direction.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var right = base_direction.cross(up).normalized()
	up = right.cross(base_direction).normalized()

	# Apply random spread
	var spread_offset = (right * cos(random_rotation) + up * sin(random_rotation)) * sin(random_angle)
	var spread_dir = (base_direction.normalized() + spread_offset).normalized()

	return spread_dir

## Perform sniper shot with penetration
static func shoot_penetrating(
	world_3d: World3D,
	origin: Vector3,
	direction: Vector3,
	range: float = MAX_RANGE,
	damage: float = 50.0,
	max_penetrations: int = 2,
	damage_falloff: float = 0.5,
	shooter: Node3D = null
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var current_origin = origin
	var current_damage = damage
	var excluded: Array[RID] = []

	if shooter and shooter is CollisionObject3D:
		excluded.append(shooter.get_rid())

	for _i in range(max_penetrations + 1):
		var space_state = world_3d.direct_space_state
		var end_point = current_origin + direction.normalized() * range

		var query = PhysicsRayQueryParameters3D.create(current_origin, end_point)
		query.collision_mask = LAYER_PLAYERS | LAYER_ENEMIES | LAYER_ENVIRONMENT
		query.exclude = excluded

		var result = space_state.intersect_ray(query)

		if result:
			var hit_info = {
				"hit": true,
				"position": result.position,
				"normal": result.normal,
				"collider": result.collider,
				"distance": origin.distance_to(result.position),
				"damage": current_damage,
				"penetrated": true
			}
			results.append(hit_info)

			# Setup for next penetration
			if result.collider is CollisionObject3D:
				excluded.append(result.collider.get_rid())
			current_origin = result.position + direction.normalized() * 0.1
			current_damage *= damage_falloff

			# Stop if hit environment
			if result.collider and not (result.collider.is_in_group("players") or result.collider.is_in_group("enemies")):
				hit_info["penetrated"] = false
				break
		else:
			break

	return results

## Apply damage from hit result to target
static func apply_hit_damage(hit_result: Dictionary, damage_source: Node = null) -> float:
	if not hit_result.get("hit", false):
		return 0.0

	var collider = hit_result.get("collider")
	if not collider:
		return 0.0

	var damage = hit_result.get("damage", DEFAULT_DAMAGE)
	var actual_damage = 0.0

	# Try to find health component (entities like Player)
	if collider.has_method("get_component"):
		var health_comp = collider.get_component("HealthComponent")
		if health_comp:
			var result = health_comp.take_damage(damage, damage_source)
			actual_damage = result if result != null else damage
			return actual_damage

	# Try take_damage method - check if it accepts 2 arguments or 1
	if collider.has_method("take_damage"):
		# Check method info to determine argument count
		var method_list = collider.get_method_list()
		var takes_two_args = false
		for method in method_list:
			if method.name == "take_damage":
				# args is an array of argument info
				takes_two_args = method.args.size() >= 2
				break

		if takes_two_args:
			var result = collider.take_damage(damage, damage_source)
			actual_damage = result if result != null else damage
		else:
			# HexTile and similar objects only take damage amount (may return void)
			collider.take_damage(damage)
			actual_damage = damage  # Assume full damage was applied

	return actual_damage
